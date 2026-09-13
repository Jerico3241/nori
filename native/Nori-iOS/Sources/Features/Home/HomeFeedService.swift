import SwiftUI

/// Stellt den Inhalt der Startseite zusammen.
///
/// ## Warum es diesen Dienst gibt
///
/// Die vorherige Startseite hat ihre Reihen in `body` und in einer `task`
/// gebaut: eine Genre-Gruppierung hier, eine Hero-Auswahl dort, dazwischen
/// `CoverIndex`-Abrufe in jeder einzelnen Kachel. Das hatte drei Folgen — die
/// Reihenfolge lief bei jedem Neuzeichnen erneut, sie war nicht prüfbar, und
/// ein Datenwechsel zog einen kompletten Neuaufbau nach sich.
///
/// Hier ist die Zuständigkeit getrennt:
///
/// - **`NoriCore`** rechnet (`HomeRanking`, `HomeTaste`, `HomeEpisodes`) und
///   weiß nichts von SwiftUI. Geprüft wird dort.
/// - **Dieser Dienst** holt, was die Rechnung braucht, und legt das Ergebnis
///   als `HomeFeed` ab.
/// - **`NoriHomeView`** stellt `HomeFeed` dar und sortiert nichts mehr selbst.
///
/// ## Zwei Durchgänge
///
/// `load` veröffentlicht **zweimal**: erst aus dem, was ohne Netz dasteht,
/// dann mit frischen TMDB-Daten. Damit erscheint die Seite sofort mit Noris
/// eigenen Daten und dem TMDB-Stand von vorhin, statt auf ein halbes Dutzend
/// Abrufe zu warten. Das ist die Umsetzung von „Startseite muss sofort
/// erscheinen": kein minutenlanges Ladeskelett, sondern ein vollständiger
/// erster Aufbau, der sich still verbessert.
///
/// ## Die Ordnung bleibt stehen
///
/// Der zweite Durchgang ändert **Inhalte, nicht die Ordnung**. Vorher ersetzte
/// er den ganzen Feed: Karten wechselten innerhalb einer Reihe die Stelle, der
/// Kopfbereich zeigte plötzlich einen anderen Titel, und „Neue Episoden"
/// schob sich zwischen zwei Reihen, während schon gescrollt wurde. Jetzt legt
/// `HomeFeedStability` den frischen Feed über den sichtbaren. Neu geordnet
/// wird nur beim ersten Aufbau und beim bewussten Aktualisieren.
///
/// Ohne jeden TMDB-Stand von vorhin — erster Start, geleerter Cache — stünden
/// im ersten Durchgang nur Genre-Reihen; alles, was TMDB bringt, käme darunter.
/// Dann wartet die Seite im Ladeskelett auf den zweiten Durchgang, höchstens
/// `coldStartHold` lang.
///
/// ## Wenn TMDB ausfällt
///
/// Nichts hier wirft. Ohne Schlüssel, ohne Netz oder bei Ratenbegrenzung
/// bleiben die Signale leer; „Neu & beliebt" und „Für dich" entfallen dann,
/// „Weiterschauen", „Neue Episoden" und die Genre-Reihen stehen weiter, weil
/// sie aus Noris eigenen Daten kommen. TMDB ist eine Verbesserung, keine
/// Voraussetzung.
@MainActor
@Observable
final class HomeFeedService {
    /// Was die Ansicht darstellt.
    private(set) var feed = HomeFeed()
    /// Läuft gerade der zweite Durchgang? Nur für einen dezenten Hinweis in
    /// der Kopfzeile — die Seite steht währenddessen vollständig da.
    private(set) var enriching = false
    /// Der erste Durchgang lief noch nie. Unterscheidet „leer, weil nichts
    /// da ist" von „leer, weil noch nicht gerechnet".
    private(set) var ready = false
    /// Kalter Start: die Seite hält das Ladeskelett, bis der zweite Durchgang
    /// die Ordnung festlegen kann (siehe oben).
    private(set) var holding = false

    /// Wie lange ein kalter Start höchstens auf TMDB wartet, bevor er zeigt,
    /// was ohne Netz dasteht.
    static let coldStartHold: Duration = .seconds(3)
    private var holdTask: Task<Void, Never>?

    /// Der lokale Stand, wie ihn die Ansicht mitgibt.
    ///
    /// Bewusst eine Kopie und keine Referenz auf `LibraryStore`: läse der
    /// Dienst den Store selbst, würde jede Fortschrittsänderung — also jeder
    /// Tick des laufenden Players — einen Neuaufbau der ganzen Startseite
    /// auslösen.
    struct LocalState {
        var progress: [WatchProgress] = []
        var continueWatching: [WatchProgress] = []
        var favorites: [String] = []
        var favoriteSource: [String: CatalogProvider] = [:]
    }

    /// Merkt sich, womit zuletzt gerechnet wurde — ein erneuter Aufruf mit
    /// demselben Stand tut nichts.
    private var lastKey: String = ""

    /// - Parameter sourceKey: woran erkennbar ist, dass sich etwas geändert
    ///   hat — aus den Revisionen von Katalog und Bibliothek (siehe
    ///   `NoriHomeView.feedKey`). Vorher rechnete der Dienst ihn selbst aus
    ///   Anzahlen und dem jüngsten Fortschrittszeitpunkt; eine abgeschlossene
    ///   Folge oder ein ersetzter Merklisteneintrag ändern keine Anzahl.
    func load(catalog: [CatalogItem], sourceKey: String, local: LocalState, force: Bool = false) async {
        let key = sourceKey
        if !force, key == lastKey, ready { return }
        lastKey = key
        holdTask?.cancel()
        holdTask = nil
        holding = false
        // Neu geordnet wird beim ersten Aufbau und beim bewussten
        // Aktualisieren. Jeder andere Aufbau — ein nachgeladener Katalog, eine
        // Bibliotheksänderung — hält die Ordnung, die schon dasteht.
        let reorder = force || !ready

        guard !catalog.isEmpty else {
            // Ohne Katalog gibt es keine Kacheln — aber „Weiterschauen" steht
            // im gespeicherten Stand und braucht ihn gar nicht.
            feed = Self.watchingOnly(local)
            ready = true
            return
        }

        // Titel, Index und beide Aufbauten laufen abseits des Hauptthreads;
        // hier wird nur veröffentlicht. Gemessen mit dem Time Profiler
        // (iPad-Simulator, Release, Start mit beiden Katalogen): der Index
        // allein kostete 435 ms Hauptthread — Normalisieren über reguläre
        // Ausdrücke für jeden Titel und Alternativtitel —, der ganze Aufbau
        // rund 700 ms. So lange nahm die Startseite beim Start keine Eingabe an.
        let prepared = await Task.detached(priority: .userInitiated) {
            let titles = catalog.map { HomeTitle($0, fallback: .aniworld) }
            return (titles: titles, index: HomeCatalogIndex(titles))
        }.value
        guard !Task.isCancelled else { return }
        let titles = prepared.titles
        let index = prepared.index
        let seeds = await Self.seedSignals(titles: titles, local: local)

        // --- Durchgang 1: alles, was ohne Netz dasteht.
        let cached = await TMDBCatalog.shared.cachedSignals()
        let firstCalendar = calendarCache
        let firstRecommended = recommendationCache
        let first = await Task.detached(priority: .userInitiated) {
            Self.assemble(
                titles: titles,
                index: index,
                local: local,
                trending: cached.trending,
                others: cached.others,
                airing: cached.airing,
                calendar: firstCalendar,
                seedSignals: seeds,
                recommended: firstRecommended,
                now: Date()
            )
        }.value
        guard !Task.isCancelled else { return }
        let cold = cached.trending.isEmpty && cached.others.isEmpty && cached.airing.isEmpty
        if !reorder {
            publish(first)
        } else if cold, !force {
            hold(fallback: first, local: local)
        } else {
            feed = first.feed
        }
        ready = true
        guard !Task.isCancelled else { return }

        // --- Durchgang 2: TMDB und Kalender.
        enriching = true
        defer { enriching = false }

        async let signals = TMDBCatalog.shared.signals(force: force)
        async let calendar = Self.recentEpisodes(force: force)
        let fresh = await signals
        calendarCache = await calendar
        guard !Task.isCancelled else { return }

        // Empfehlungen hängen am Profil, das Profil an den Kennungen — erst
        // jetzt steht fest, wonach überhaupt gefragt werden soll.
        let profile = HomeTaste.profile(
            progress: local.progress,
            favorites: local.favorites,
            favoriteSource: local.favoriteSource,
            catalog: titles,
            signals: seeds,
            now: Date()
        )
        recommendationCache = await Self.related(seeds: profile.seeds, index: index)
        guard !Task.isCancelled else { return }

        let secondCalendar = calendarCache
        let secondRecommended = recommendationCache
        let second = await Task.detached(priority: .userInitiated) {
            Self.assemble(
                titles: titles,
                index: index,
                local: local,
                trending: fresh.trending,
                others: fresh.others,
                airing: fresh.airing,
                calendar: secondCalendar,
                seedSignals: seeds,
                recommended: secondRecommended,
                now: Date()
            )
        }.value
        guard !Task.isCancelled else { return }
        holdTask?.cancel()
        holdTask = nil
        holding = false
        publish(second)
    }

    /// Legt einen frisch gerechneten Feed über den sichtbaren, ohne dessen
    /// Ordnung zu ändern.
    private func publish(_ assembly: Assembly) {
        feed = HomeFeedStability.stabilize(previous: feed, fresh: assembly.feed, candidates: assembly.candidates)
    }

    /// Kalter Start: nur „Weiterschauen" steht, der Rest bleibt im Skelett.
    /// Kommt der zweite Durchgang nicht rechtzeitig, erscheint der erste —
    /// was TMDB danach bringt, hängt `HomeFeedStability` unten an.
    private func hold(fallback: Assembly, local: LocalState) {
        feed = Self.watchingOnly(local)
        holding = true
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: Self.coldStartHold)
            guard !Task.isCancelled, let self, self.holding else { return }
            self.holding = false
            self.publish(fallback)
        }
    }

    private static func watchingOnly(_ local: LocalState) -> HomeFeed {
        var out = HomeFeed()
        out.continueWatching = local.continueWatching
        out.sections = HomeSection.canonical(for: out)
        return out
    }

    /// Kalender und Empfehlungen überleben einen Neuaufbau: sie ändern sich
    /// langsamer als der Fortschritt, der ihn auslöst.
    private var calendarCache: [AiringEntry] = []
    private var recommendationCache: [Int: Int] = [:]

    // MARK: - Beschaffen

    /// Die TMDB-Kennungen der Titel, mit denen der Nutzer schon zu tun hatte.
    ///
    /// Aus dem Cover-Index, **ohne** nachzuschlagen: die Kennungen liegen dort
    /// von der Cover-Suche her vor. Eine Suche je gesehenem Titel wäre ein
    /// Dutzend Anfragen beim Öffnen der Startseite, und ein Titel ohne
    /// Kennung fällt einfach aus dem Profil.
    private static func seedSignals(titles: [HomeTitle], local: LocalState) async -> [String: TMDBSignals] {
        var slugs: Set<String> = []
        for item in local.progress { slugs.insert(item.slug) }
        for slug in local.favorites { slugs.insert(slug) }
        guard !slugs.isEmpty else { return [:] }

        let ids = await CoverIndex.shared.tvIDs(for: Array(slugs))
        var out: [String: TMDBSignals] = [:]
        for title in titles where slugs.contains(title.slug) {
            guard let id = ids[title.slug] else { continue }
            var signals = TMDBSignals()
            signals.tmdbID = id
            out[title.id] = signals
        }
        return out
    }

    /// Was TMDB zu den meistgesehenen Titeln als verwandt nennt, auf Noris
    /// Katalog zurückgeführt.
    ///
    /// Das Ergebnis zählt, von **wie vielen** Ausgangstiteln ein Kandidat
    /// empfohlen wurde: zweimal genannt ist ein stärkeres Zeichen als einmal.
    private static func related(seeds: [Int], index: HomeCatalogIndex) async -> [Int: Int] {
        guard !seeds.isEmpty else { return [:] }
        var hits: [Int: Int] = [:]
        for seed in seeds.prefix(4) {
            let rows = await TMDBCatalog.shared.related(to: seed)
            var seen: Set<Int> = []
            for row in rows {
                guard seen.insert(row.id).inserted else { continue }
                // Nur zählen, was Nori auch führt. Eine Empfehlung, die sich
                // nicht öffnen lässt, ist keine.
                guard index.match(row) != nil else { continue }
                hits[row.id, default: 0] += 1
            }
        }
        return hits
    }

    /// Noris eigener Kalender, beide Quellen, nur der bereits gelaufene Teil.
    ///
    /// `CalendarService.payload` ist dieselbe Funktion, die der Kalender-Tab
    /// benutzt — inklusive Zwischenspeicher im Client. Die Startseite holt
    /// dadurch nichts zusätzlich, wenn der Tab kurz vorher offen war.
    private static func recentEpisodes(force: Bool) async -> [AiringEntry] {
        do {
            // Ausdrücklich `.all`: die Startseite führt Anime und Serien
            // gemeinsam, unabhängig vom Bereich, der in den anderen Tabs
            // eingestellt ist.
            let payload = try await CalendarService.payload(scope: .all, slugs: nil, force: force)
            return payload.recent
        } catch {
            // Ein ausgefallener Kalender blendet die Reihe aus. Er darf die
            // übrige Startseite nicht mitreißen.
            return []
        }
    }

    // MARK: - Zusammenbauen

    /// Ein gerechneter Feed samt aller Kandidaten, aus denen er gewählt hat —
    /// `HomeFeedStability` braucht sie, um sichtbare Karten mit frischen Daten
    /// zu versorgen.
    struct Assembly {
        var feed: HomeFeed
        var candidates: [String: HomeCandidate]
    }

    /// Rein: dieselben Eingaben ergeben denselben Feed. `nonisolated`, damit
    /// der Aufbau abseits des Hauptthreads laufen kann.
    nonisolated static func assemble(
        titles: [HomeTitle],
        index: HomeCatalogIndex,
        local: LocalState,
        trending: [TMDBCandidate],
        others: [TMDBCandidate],
        airing: [TMDBCandidate],
        calendar: [AiringEntry],
        seedSignals: [String: TMDBSignals],
        recommended: [Int: Int],
        now: Date
    ) -> Assembly {
        var watched: [String: Double] = [:]
        for item in local.progress {
            let provider = item.provider ?? providerFromPath(item.episodePath)
            let key = "\(provider.rawValue)|\(item.slug)"
            watched[key] = max(watched[key] ?? 0, watchRatio(item))
        }

        let available = Set(titles.map(\.id))
        let episodes = HomeEpisodes.recent(
            entries: calendar,
            now: now,
            availableSlugs: available,
            limit: 12
        )
        let fresh = Set(episodes.map { "\($0.provider?.rawValue ?? "")|\($0.slug)" })

        let candidates = HomeSignals.candidates(
            catalog: titles,
            index: index,
            trending: trending,
            popular: others,
            airing: airing,
            watched: watched,
            favorites: Set(local.favorites),
            freshEpisodes: fresh,
            now: now
        )

        var feed = HomeFeed()
        feed.continueWatching = local.continueWatching
        feed.newEpisodes = episodes

        // Der Tag geht in die Auswahl des Kopfbereichs ein: ohne ihn stünde
        // dort wochenlang derselbe Titel.
        let day = Int(now.timeIntervalSince1970 / 86_400)
        feed.hero = HomeRanking.heroPicks(candidates, now: now, day: day, limit: 5)

        // Ab hier wird entdoppelt: was schon steht, steht nicht noch einmal.
        var used = Set(feed.hero.map(\.id))
        feed.newAndPopular = HomeRanking.newAndPopular(candidates, now: now, excluding: used, limit: 20)
        used.formUnion(feed.newAndPopular.map(\.id))

        // Die angefangenen Titel stehen schon in „Weiterschauen".
        used.formUnion(local.continueWatching.map { item in
            let provider = item.provider ?? providerFromPath(item.episodePath)
            return "\(provider.rawValue)|\(item.slug)"
        })

        var profileSignals = seedSignals
        for candidate in candidates where !candidate.signals.isEmpty {
            profileSignals[candidate.id] = candidate.signals
        }
        let profile = HomeTaste.profile(
            progress: local.progress,
            favorites: local.favorites,
            favoriteSource: local.favoriteSource,
            catalog: titles,
            signals: profileSignals,
            now: now
        )

        if profile.isMeaningful {
            feed.recommendations = HomeTaste.recommend(
                candidates,
                profile: profile,
                recommended: recommended,
                excluding: used,
                limit: 20
            )
            feed.recommendationTitle = "Für dich"
        }
        if feed.recommendations.isEmpty {
            // Kaltstart oder zu wenig Signal. Dann heißt die Reihe auch
            // anders — „Für dich" über einer Beliebtheitsliste wäre eine
            // Behauptung, die die Seite nicht einlöst.
            feed.recommendations = HomeRanking.topRated(
                candidates,
                excluding: used,
                minimumVotes: 200,
                limit: 20
            )
            feed.recommendationTitle = "Entdecke etwas Neues"
        }
        used.formUnion(feed.recommendations.map(\.id))

        feed.extraRows = extraRows(candidates, titles: titles, used: &used, now: now)
        feed.sections = HomeSection.canonical(for: feed)
        let pool = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Assembly(feed: feed, candidates: pool)
    }

    /// Die zusätzlichen Reihen unter den festen.
    ///
    /// Mit Mindestbesetzung: eine Reihe mit drei Kacheln sieht nach einem
    /// Fehler aus. Und nur, was übrig bleibt — eine Trendreihe, die nach dem
    /// Entdoppeln fast leer ist, sagt dasselbe wie „Neu & beliebt" darüber
    /// und entfällt.
    nonisolated private static func extraRows(
        _ candidates: [HomeCandidate],
        titles: [HomeTitle],
        used: inout Set<String>,
        now: Date
    ) -> [HomeRow] {
        var rows: [HomeRow] = []
        let minimum = 6

        let trending = HomeRanking.trending(candidates, excluding: used, limit: 18)
        if trending.count >= minimum {
            rows.append(HomeRow(title: "Gerade im Trend", items: trending))
            used.formUnion(trending.map(\.id))
        }

        let rated = HomeRanking.topRated(candidates, excluding: used, minimumVotes: 500, limit: 18)
        if rated.count >= minimum {
            rows.append(HomeRow(title: "Top bewertet", items: rated))
            used.formUnion(rated.map(\.id))
        }

        rows.append(contentsOf: genreRows(candidates, used: &used, now: now, minimum: minimum))
        return rows
    }

    /// Genre-Reihen aus dem, was danach noch übrig ist.
    ///
    /// Sie sind der Rückfall, der auch ohne TMDB trägt: die Genres stehen im
    /// Katalog der Quelle. Sortiert wird trotzdem nach Punkten, damit in einer
    /// Fantasy-Reihe nicht alphabetisch der Anfang des Katalogs steht.
    nonisolated private static func genreRows(
        _ candidates: [HomeCandidate],
        used: inout Set<String>,
        now: Date,
        minimum: Int
    ) -> [HomeRow] {
        var counts: [String: Int] = [:]
        var labels: [String: String] = [:]
        for candidate in candidates {
            for genre in candidate.title.genres.prefix(3) where !genre.isEmpty {
                let key = TMDBMatcher.normalize(genre)
                guard !key.isEmpty else { continue }
                counts[key, default: 0] += 1
                labels[key] = genre
            }
        }

        var ranked: [(key: String, count: Int)] = []
        for (key, count) in counts where count >= 12 {
            ranked.append((key, count))
        }
        ranked.sort { lhs, rhs in
            lhs.count == rhs.count ? lhs.key < rhs.key : lhs.count > rhs.count
        }

        var rows: [HomeRow] = []
        for entry in ranked.prefix(6) {
            var pool: [HomeCandidate] = []
            for candidate in candidates {
                guard !used.contains(candidate.id) else { continue }
                let match = candidate.title.genres.contains { TMDBMatcher.normalize($0) == entry.key }
                guard match else { continue }
                pool.append(candidate)
            }
            var scored: [HomeRanking.Scored] = []
            for candidate in pool {
                scored.append(HomeRanking.Scored(
                    candidate: candidate,
                    score: HomeRanking.newAndPopularScore(candidate, now: now)
                ))
            }
            let items = Array(HomeRanking.ordered(scored).prefix(18))
            guard items.count >= minimum else { continue }
            used.formUnion(items.map(\.id))
            rows.append(HomeRow(title: labels[entry.key] ?? entry.key, items: items))
        }
        return rows
    }
}
