import SwiftUI

/// Stellt den Katalog zusammen und hält seinen Zustand.
///
/// ## Warum es diesen Dienst gibt
///
/// Der vorherige Katalog filterte in einer berechneten Eigenschaft der
/// Ansicht. Das lief bei jedem Neuzeichnen erneut, war nicht prüfbar und
/// konnte nur das, was sich in drei Zeilen unterbringen ließ — eine
/// Teilzeichenkette im Titel. Alles Weitere — Zusammenführen zweier Quellen,
/// TMDB-Anreicherung, Rangfolgen, Facetten — hätte dort nicht hingepasst.
///
/// Hier ist die Zuständigkeit getrennt, genau wie bei der Startseite:
///
/// - **`NoriCore`** rechnet (`CatalogBuilder`, `CatalogEngine`,
///   `CatalogRanking`) und weiß nichts von SwiftUI. Geprüft wird dort.
/// - **Dieser Dienst** holt, was die Rechnung braucht, und legt Ergebnis und
///   Facetten ab.
/// - **`CatalogView`** stellt dar und filtert nichts mehr selbst.
///
/// ## Zwei Durchgänge
///
/// `load` veröffentlicht **zweimal**: erst aus dem, was ohne Netz dasteht —
/// Providerkatalog, abgelegte TMDB-Listen, Cover-Index —, dann mit frischen
/// TMDB-Daten und Kalender. Damit steht das Raster sofort, statt auf ein
/// halbes Dutzend Abrufe zu warten.
///
/// ## Die Reihenfolge bleibt stehen
///
/// Der zweite Durchgang bringt die Werte, nach denen „Beliebt" und
/// „Bewertung" sortieren. Sortierte er neu, wanderten Kacheln weg, während
/// jemand schon scrollte. Deshalb gilt `CatalogStableOrder`: frische Daten ja,
/// neue Reihenfolge nur bei einer anderen Abfrage, beim bewussten
/// Aktualisieren — und wenn die erste Reihenfolge ohne jedes TMDB-Signal
/// entstand, also noch gar keine Rangfolge war.
///
/// ## Wenn TMDB ausfällt
///
/// Nichts hier wirft. Ohne Schlüssel, ohne Netz oder bei Ratenbegrenzung
/// bleiben die Signale leer: Der Katalog zeigt dann Titel, Genres und Cover
/// der Quelle, die Suche funktioniert vollständig, und die Filter bieten nur
/// noch an, was ohne TMDB belegbar ist. TMDB ist eine Anreicherung, keine
/// Voraussetzung.
@MainActor
@Observable
final class CatalogService {
    enum Phase {
        /// Noch nie gerechnet.
        case idle
        /// Erster Durchgang läuft, es steht noch nichts da.
        case loading
        /// Es steht etwas da.
        case ready
    }

    private(set) var entries: [CatalogEntry] = []
    /// Die Ergebnisliste zur aktuellen Abfrage — fertig gefiltert und
    /// sortiert.
    private(set) var results: [CatalogEntry] = []
    private(set) var facets = CatalogFacets()
    private(set) var phase: Phase = .idle
    /// Läuft der zweite Durchgang? Nur für einen dezenten Hinweis; das Raster
    /// steht währenddessen vollständig da.
    private(set) var enriching = false

    private(set) var query = CatalogQuery()

    /// Die gezeigte Reihenfolge — siehe „Die Reihenfolge bleibt stehen".
    @ObservationIgnored private var order: CatalogOrder<CatalogQuery>?
    /// Stand die Reihenfolge schon auf TMDB-Signalen? Ohne sie war sie keine
    /// Rangfolge und darf ersetzt werden, sobald Signale da sind.
    @ObservationIgnored private var orderHadSignals = false

    /// Der lokale Stand, wie ihn die Ansicht mitgibt.
    ///
    /// Bewusst eine Kopie und keine Referenz auf `LibraryStore`: läse der
    /// Dienst den Store selbst, würde jeder Tick des laufenden Players den
    /// ganzen Katalog neu bauen.
    struct LocalState {
        /// In welchen Sprachen tatsächlich schon abgespielt wurde. Der
        /// belastbarste Sprachbeleg, den Nori hat.
        var playedLanguages: [String: Set<CatalogLanguage>] = [:]

        init() {}

        init(progress: [WatchProgress]) {
            for item in progress {
                guard let raw = item.lang, let language = CatalogLanguage.parse(raw) else { continue }
                playedLanguages[item.slug, default: []].insert(language)
            }
        }

        /// Woran erkennbar ist, dass sich etwas geändert hat.
        ///
        /// Aus dem Inhalt, nicht aus Anzahlen: vorher zählte die Signatur Slugs
        /// und Sprachen. Eine Folge in GerSub statt Deutsch änderte keine der
        /// beiden Zahlen, und der Sprachfilter blieb beim alten Stand.
        var signature: Int {
            var hasher = Hasher()
            for slug in playedLanguages.keys.sorted() {
                hasher.combine(slug)
                for language in (playedLanguages[slug] ?? []).sorted(by: { $0.order < $1.order }) {
                    hasher.combine(language.rawValue)
                }
            }
            return hasher.finalize()
        }
    }

    /// Womit zuletzt gerechnet wurde. Ein erneuter Aufruf mit demselben Stand
    /// tut nichts.
    private var lastKey = ""
    /// Kalender und TMDB-Listen überleben einen Neuaufbau: sie ändern sich
    /// langsamer als das, was ihn auslöst.
    private var calendarCache: [AiringEntry] = []

    // MARK: - Abfrage

    /// Eine neue Abfrage anwenden.
    ///
    /// Rechnet **hier** und nicht in `body`: Filtern und Sortieren von
    /// zehntausend Einträgen bei jedem Neuzeichnen wäre der sicherste Weg zu
    /// einer ruckelnden Liste. Ein unveränderter Wert kostet nichts.
    func apply(_ next: CatalogQuery) {
        guard next != query else { return }
        query = next
        recompute(reorder: true)
    }

    private func recompute(reorder: Bool) {
        let fresh = CatalogEngine.results(for: query, in: entries, now: Date())
        var current: [String: CatalogEntry] = [:]
        var owner: [String: String] = [:]
        current.reserveCapacity(entries.count)
        owner.reserveCapacity(entries.count)
        for entry in entries {
            current[entry.id] = entry
            for source in entry.sources { owner[source.id] = entry.id }
        }
        let hasSignals = fresh.contains { $0.tmdbID != nil }
        let rebuild = reorder || !orderHadSignals
        let next = CatalogStableOrder.next(
            previous: rebuild ? nil : order,
            view: query,
            fresh: fresh.map(\.id),
            resolve: { owner[$0] }
        )
        if rebuild || order?.view != query { orderHadSignals = hasSignals }
        order = next
        results = next.ids.compactMap { current[$0] }
    }

    /// Die Schnellfilter: die festen vier und die tatsächlich häufigen Genres.
    var quickFilters: [CatalogQuickFilter] {
        var out: [CatalogQuickFilter] = [.all, .fresh, .popular, .topRated]
        out.append(contentsOf: facets.quickGenres().map { CatalogQuickFilter.genre($0) })
        return out
    }

    // MARK: - Laden

    /// - Parameter revision: `catalogRevision` der Wurzelansicht. Sie ändert
    ///   sich genau dann, wenn sich der Inhalt des Katalogs ändert — anders als
    ///   die Anzahl, die vorher hier stand.
    func load(items: [CatalogItem], revision: Int, local: LocalState, force: Bool = false) async {
        let key = "\(revision)|\(local.signature)"
        if !force, key == lastKey, phase == .ready { return }
        lastKey = key

        guard !items.isEmpty else {
            entries = []
            results = []
            order = nil
            facets = CatalogFacets()
            phase = .ready
            return
        }
        if entries.isEmpty { phase = .loading }

        // --- Durchgang 1: alles, was ohne Netz dasteht.
        var context = await Self.offlineContext(items: items, local: local, calendar: calendarCache)
        await publish(items: items, context: context, reorder: force || order == nil)
        guard !Task.isCancelled else { return }

        // --- Durchgang 2: TMDB und Kalender.
        enriching = true
        defer { enriching = false }

        async let signals = TMDBCatalog.shared.signals(force: force)
        async let ended = TMDBCatalog.shared.ended(force: force)
        async let calendar = Self.recentEpisodes(force: force)

        let fresh = await signals
        let completed = await ended
        let dates = await calendar
        guard !Task.isCancelled else { return }
        if !dates.isEmpty { calendarCache = dates }

        context.trending = fresh.trending
        context.popular = fresh.others
        context.airing = fresh.airing
        context.ended = completed
        context.calendar = calendarCache
        // Beim bewussten Aktualisieren wartet der Betrachter auf das Ergebnis
        // (die Aktualisieren-Geste steht so lange) — dann darf es neu sortiert
        // dastehen. Sonst bleibt die Reihenfolge.
        await publish(items: items, context: context, reorder: force)
    }

    /// Was ohne eine einzige Netzanfrage zur Verfügung steht.
    private static func offlineContext(
        items: [CatalogItem],
        local: LocalState,
        calendar: [AiringEntry]
    ) async -> CatalogBuilder.Context {
        let slugs = items.map(\.slug)
        let cached = await TMDBCatalog.shared.cachedSignals()
        var context = CatalogBuilder.Context()
        context.trending = cached.trending
        context.popular = cached.others
        context.airing = cached.airing
        context.ended = await TMDBCatalog.shared.cachedEnded()
        context.calendar = calendar
        // Beides liegt vom Cover-Nachladen her vor und kostet keine Anfrage.
        // Für Titel, die auf keiner Rangliste stehen, ist es die einzige
        // TMDB-Auskunft überhaupt.
        context.knownIDs = await CoverIndex.shared.tvIDs(for: slugs)
        context.knownRatings = await CoverIndex.shared.ratings(for: slugs)
        context.playedLanguages = local.playedLanguages
        return context
    }

    private func publish(items: [CatalogItem], context: CatalogBuilder.Context, reorder: Bool) async {
        let built = await Self.assemble(items: items, context: context)
        guard !Task.isCancelled else { return }
        entries = built
        facets = CatalogFacets.of(built)
        phase = .ready
        recompute(reorder: reorder)
    }

    /// Den Katalog außerhalb des Hauptactors bauen.
    ///
    /// Zehntausend Einträge zusammenzuführen, zu entdoppeln und zu indizieren
    /// dauert lange genug, dass es auf dem Hauptactor sichtbar wäre — und es
    /// geschieht zweimal je Laden.
    private nonisolated static func assemble(
        items: [CatalogItem],
        context: CatalogBuilder.Context
    ) async -> [CatalogEntry] {
        await Task.detached(priority: .userInitiated) {
            CatalogBuilder.build(items, context: context, now: Date())
        }.value
    }

    /// Noris eigener Kalender, beide Quellen.
    ///
    /// `CalendarService.payload` ist dieselbe Funktion, die der Kalender-Tab
    /// und die Startseite benutzen — inklusive Zwischenspeicher im Client. Der
    /// Katalog holt dadurch nichts zusätzlich, wenn eine der beiden kurz
    /// vorher offen war.
    ///
    /// Ausdrücklich `.all`: Der Katalog führt Anime und Serien gemeinsam.
    private static func recentEpisodes(force: Bool) async -> [AiringEntry] {
        do {
            let payload = try await CalendarService.payload(scope: .all, slugs: nil, force: force)
            // Kommendes zählt mit: Eine angekündigte Folge ist der stärkste
            // Beleg dafür, dass eine Serie läuft.
            return payload.recent + payload.upcoming
        } catch {
            // Ein ausgefallener Kalender kostet Sprachen, Status und
            // Aktualität — nicht den Katalog.
            return []
        }
    }
}
