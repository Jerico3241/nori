import SwiftUI

/// Noris Startseite.
///
/// Aufbau: ein durchgehender senkrechter Lauf. Oben ein großer, cinematischer
/// Kopfbereich über rund drei Viertel des Bildschirms, darunter waagerechte
/// Reihen — Weiterschauen, Neu & beliebt, Neue Episoden, Für dich und, sofern
/// die Daten es hergeben, weitere. Dazwischen liegt nichts: kein Umschalter
/// „Anime | Serien", keine Pillenreihe, keine nachgebaute Tab-Leiste.
///
/// ## Was diese Ansicht **nicht** tut
///
/// Sie sortiert nichts. Welcher Titel im Kopfbereich steht, was „neu und
/// beliebt" heißt und was zu jemandem passt, rechnet `HomeFeedService` aus
/// Bausteinen in `NoriCore` — und die sind geprüft. Die vorherige Startseite
/// hatte ihre Auswahl in `body` und in einer `task`; dadurch lief sie bei
/// jedem Neuzeichnen, war nicht prüfbar, und die Überschrift „Beliebte Titel"
/// stand über den ersten zwanzig Einträgen des alphabetisch sortierten
/// Katalogs.
///
/// ## Anime und Serien gemeinsam
///
/// Die Startseite bekommt bewusst den **vollständigen** Katalog, nicht den
/// nach `LibraryScope` ausgeschnittenen. Sie hat keinen Bereichsumschalter,
/// also wäre ein Ausschnitt für den Betrachter nicht erklärbar: er hätte ihn
/// zuletzt im Katalog-Tab gesetzt und fände die Startseite ohne ersichtlichen
/// Grund halb leer. Katalog, Kalender und Merkliste schneiden weiterhin zu.
struct NoriHomeView: View {
    @Environment(LibraryStore.self) private var library
    /// Der vollständige Katalog beider Quellen.
    let catalog: [CatalogItem]
    let loading: Bool
    let error: String?
    let reload: () async -> Void
    /// Wechselt in den Katalog-Tab, wo Noris Suche liegt.
    let openSearch: () -> Void
    /// Wechselt in den Kalender-Tab.
    let openCalendar: () -> Void

    @State private var service = HomeFeedService()
    /// Welcher der vorgeschlagenen Titel gerade im Kopfbereich steht.
    @State private var heroIndex = 0
    @State private var play: SeriesView.PlayTarget?
    /// Wessen Folge gerade geholt wird — Kennung der Kachel, oder
    /// `HomeIdentifier.hero` für den Kopfbereich.
    @State private var preparing: String?
    /// Fehler der Direktwiedergabe. Getrennt von `error`, das von außen kommt
    /// und den Katalog betrifft.
    @State private var playError: String?

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var feed: HomeFeed { service.feed }

    private var hero: HomeCandidate? {
        guard !feed.hero.isEmpty else { return nil }
        return feed.hero[min(heroIndex, feed.hero.count - 1)]
    }

    var body: some View {
        GeometryReader { proxy in
            screen(size: proxy.size, topInset: proxy.safeAreaInsets.top)
        }
        .background(NoriTheme.bg.ignoresSafeArea())
        .foregroundStyle(NoriTheme.fg)
        // Der Kopfbereich bringt Marke und Suche selbst mit; eine zweite
        // Leiste darüber wäre doppelt und schnitte das Artwork ab.
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $play) { target in
            PlayerScreen(
                series: target.series,
                episode: target.episode,
                season: target.series.activeSeason,
                resumeAt: target.resumeAt,
                provider: target.provider
            )
        }
        .task(id: feedKey) { await rebuild() }
    }

    // MARK: - Aufbau

    private func screen(size: CGSize, topInset: CGFloat) -> some View {
        let regular = sizeClass == .regular
        let posterWidth = HomeMetrics.posterWidth(screen: size.width, regular: regular)
        let landscapeWidth = HomeMetrics.landscapeWidth(screen: size.width, regular: regular)
        // Höhe aus dem **Fenster**, nicht aus dem Messrahmen: der liegt
        // innerhalb von Tab-Leiste und Sicherheitszone und meldet gut
        // hundert Punkte zu wenig. Der Kopfbereich läuft aber über beide
        // hinweg — nach ihm gerechnet geriete er ein Sechstel zu flach und
        // wirkte wie ein Banner statt wie der Anfang der Seite.
        let box = CGSize(width: size.width, height: NoriScreenMetrics.size.height)
        let heroHeight = HomeMetrics.heroHeight(screen: box, regular: regular)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: HomeMetrics.section) {
                if let hero {
                    HomeHeroView(
                        candidate: hero,
                        height: heroHeight,
                        topInset: topInset,
                        canAdvance: feed.hero.count > 1,
                        onSearch: openSearch,
                        onNext: advanceHero,
                        onPlay: { start(hero) },
                        preparing: preparing == HomeIdentifier.hero
                    )
                    // Der Inhalt rückt leicht unter den Kopfbereich, statt mit
                    // vollem Abschnittsabstand darunter zu beginnen — der
                    // Verlauf endet ohnehin in der Hintergrundfarbe.
                    .padding(.bottom, -14)
                } else if !service.ready || (loading && catalog.isEmpty) {
                    HomeSkeleton(heroHeight: heroHeight, posterWidth: posterWidth)
                }

                if let error {
                    HomeErrorBanner(text: error) { Task { await reload() } }
                }
                if let playError {
                    Text(playError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, HomeMetrics.screen)
                }

                sections(posterWidth: posterWidth, landscapeWidth: landscapeWidth)

                HomeAttribution()
                    .padding(.top, 12)
            }
            .padding(.bottom, HomeMetrics.bottom)
        }
        // Nur das Artwork des Kopfbereichs darf unter die Statusleiste — das
        // ist sein Sinn. Gibt es keines, bliebe die erste Reihe sonst unter
        // der Uhr stehen; deshalb hängt es am Kopfbereich.
        .ignoresSafeArea(edges: hero == nil ? [] : .top)
        .noriSoftScrollEdges()
        .scrollIndicators(.hidden)
        .refreshable { await refresh() }
    }

    /// Die Reihen, in der festgelegten Reihenfolge.
    ///
    /// Als eigene Teilansicht, weil der Typechecker beim Aufbau als Ganzes
    /// aufgibt — dieselbe Erfahrung wie auf der vorherigen Startseite. Jede
    /// weitere Verschachtelung im `LazyVStack` kostet ihn überproportional
    /// viel; kleine Teilansichten kosten nichts.
    @ViewBuilder
    private func sections(posterWidth: CGFloat, landscapeWidth: CGFloat) -> some View {
        ContinueWatchingSection(
            items: feed.continueWatching,
            width: landscapeWidth,
            preparing: preparing,
            onPlay: resume
        )

        HomePosterSection(
            title: "Neu & beliebt",
            items: feed.newAndPopular,
            width: posterWidth,
            showsBadges: true
        )

        NewEpisodesSection(
            entries: feed.newEpisodes,
            preparing: preparing,
            onPlay: start,
            onCalendar: openCalendar
        )

        HomePosterSection(
            title: feed.recommendationTitle,
            items: feed.recommendations,
            width: posterWidth
        )

        ForEach(feed.extraRows) { row in
            HomePosterSection(title: row.title, items: row.items, width: posterWidth)
        }
    }

    // MARK: - Daten

    /// Woran die Ansicht merkt, dass neu gerechnet gehört.
    ///
    /// Ausdrücklich **nicht** der Fortschrittsstand selbst: der ändert sich
    /// während der Wiedergabe im Sekundentakt, und die Reihenfolge der
    /// Startseite hängt nicht daran. Ein neuer oder entfernter Eintrag ändert
    /// dagegen die Anzahl — und genau das ist der Fall, in dem
    /// „Weiterschauen" anders aussieht.
    private var feedKey: String {
        "\(catalog.count)|\(library.progress.count)|\(library.favorites.count)"
    }

    private func rebuild(force: Bool = false) async {
        await service.load(catalog: catalog, local: localState, force: force)
        // Der Kopfbereich kann kürzer geworden sein, seit jemand
        // weitergeblättert hat.
        if heroIndex >= feed.hero.count { heroIndex = 0 }
    }

    private func refresh() async {
        await reload()
        await rebuild(force: true)
    }

    /// Der lokale Stand als Kopie.
    ///
    /// Der Dienst bekommt Werte und keine Referenz auf den Store: läse er ihn
    /// selbst, würde jeder Tick des laufenden Players einen Neuaufbau der
    /// ganzen Startseite auslösen.
    private var localState: HomeFeedService.LocalState {
        HomeFeedService.LocalState(
            progress: Array(library.progress.values),
            continueWatching: library.continueWatching(),
            favorites: library.favorites,
            favoriteSource: library.favoriteSource
        )
    }

    private func advanceHero() {
        guard feed.hero.count > 1 else { return }
        withAnimation(NoriMotion.content) {
            heroIndex = (heroIndex + 1) % feed.hero.count
        }
    }

    // MARK: - Wiedergabe

    private func resume(_ item: WatchProgress) {
        run(id: item.id) {
            try await HomePlayback.target(for: item, library: library)
        }
    }

    private func start(_ candidate: HomeCandidate) {
        run(id: HomeIdentifier.hero) {
            try await HomePlayback.target(for: candidate.title, library: library)
        }
    }

    private func start(_ entry: AiringEntry) {
        run(id: entry.id) {
            try await HomePlayback.target(for: entry, library: library)
        }
    }

    /// Eine Folge holen und abspielen — mit Schleier auf der angetippten
    /// Kachel und Fehlermeldung statt eines toten Tipps.
    private func run(id: String, _ work: @escaping () async throws -> SeriesView.PlayTarget) {
        guard preparing == nil else { return }
        preparing = id
        playError = nil
        Task {
            defer { preparing = nil }
            do {
                play = try await work()
            } catch {
                playError = error.localizedDescription
            }
        }
    }
}

/// Kennungen, die keiner Kachel gehören.
enum HomeIdentifier {
    static let hero = "nori.home.hero"
}

// MARK: - Wiedergabe aus der Startseite heraus

/// Von einer Kachel zur laufenden Folge.
///
/// Drei Einstiege, eine Regel: welche Folge tatsächlich startet, entscheidet
/// `LibraryStore.nextPlay` — dieselbe Funktion, die auch die Detailseite
/// benutzt. Damit landen Kopfbereich, „Weiterschauen" und die Detailseite
/// garantiert in derselben Folge, statt drei ähnliche Regeln zu pflegen.
///
/// Warum das überhaupt einen Netzabruf braucht: „die nächste Folge" ist ohne
/// Folgenliste nicht bestimmbar, und die steht auf der Detailseite der Quelle.
/// Der Fortschritt allein weiß, wo man stehen geblieben ist, aber nicht, was
/// danach kommt.
@MainActor
enum HomePlayback {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// In welcher Staffel dieses Titels zuletzt etwas lief, falls überhaupt.
    ///
    /// Entscheidet die Beschriftung des Kopfbereich-Knopfes („Weiter ansehen"
    /// gegen „Jetzt ansehen") und welche Staffel geholt wird.
    static func startedSeason(for title: HomeTitle, in library: LibraryStore) -> String? {
        var best: WatchProgress?
        for item in library.progress.values {
            guard item.slug == title.slug else { continue }
            let provider = item.provider ?? providerFromPath(item.episodePath)
            guard provider == title.provider else { continue }
            guard item.positionSec > 0 || item.completed == true else { continue }
            if best == nil || item.updatedAt > best!.updatedAt { best = item }
        }
        return best?.season
    }

    /// Aus dem Kopfbereich heraus.
    ///
    /// Ohne Fortschritt beginnt es bei Staffel 1 und dort bei der ersten
    /// regulären Folge — Specials und „Filme" werden ausdrücklich nicht
    /// bevorzugt. Mit Fortschritt wird die zuletzt angefangene Staffel
    /// geholt.
    static func target(for title: HomeTitle, library: LibraryStore) async throws -> SeriesView.PlayTarget {
        let season = startedSeason(for: title, in: library) ?? "1"
        let detail = try await series(slug: title.slug, provider: title.provider, season: season)
        let next = library.nextPlay(
            slug: title.slug,
            season: detail.activeSeason,
            episodes: detail.episodes,
            source: title.provider
        )
        guard let episode = detail.episodes.first(where: { $0.number == next.episode }) else {
            throw Failure(message: "\(title.title) hat in dieser Staffel keine abrufbaren Folgen.")
        }
        return SeriesView.PlayTarget(
            series: detail,
            episode: episode,
            resumeAt: library.resumeEnabled ? next.resumeAt : 0,
            provider: title.provider
        )
    }

    /// Aus „Weiterschauen" heraus.
    ///
    /// Die Quelle wird ausdrücklich mitgegeben. Ohne sie nähme `nextPlay` die
    /// Vorgabequelle, und die passt bei einer gemeinsamen Bibliothek
    /// regelmäßig nicht zum angetippten Titel.
    static func target(for item: WatchProgress, library: LibraryStore) async throws -> SeriesView.PlayTarget {
        let provider = item.provider ?? providerFromPath(item.episodePath)
        let detail = try await series(slug: item.slug, provider: provider, season: item.season)
        let next = library.nextPlay(
            slug: item.slug,
            season: item.season,
            episodes: detail.episodes,
            source: provider
        )
        guard let episode = detail.episodes.first(where: { $0.number == next.episode }) else {
            throw Failure(message: "Folge \(next.episode) ist in dieser Staffel nicht mehr eingetragen.")
        }
        return SeriesView.PlayTarget(
            series: detail,
            episode: episode,
            resumeAt: library.resumeEnabled ? next.resumeAt : 0,
            provider: provider
        )
    }

    /// Aus „Neue Episoden" heraus — genau die Folge, die dort steht.
    ///
    /// Hier gilt `nextPlay` nicht: der Kalendereintrag benennt die Folge
    /// bereits, und „die nächste unfertige" wäre eine andere. Steht sie auf
    /// der Detailseite noch nicht, sagt die Meldung genau das, statt still
    /// etwas anderes abzuspielen.
    static func target(for entry: AiringEntry, library: LibraryStore) async throws -> SeriesView.PlayTarget {
        // Ältere Kalendereinträge tragen die Quelle nicht als Feld;
        // AniWorld ist dieselbe Vorgabe wie überall im Kern.
        let provider = entry.provider ?? .aniworld
        let detail = try await series(slug: entry.slug, provider: provider, season: entry.season)
        guard let episode = detail.episodes.first(where: { $0.number == entry.episode }) else {
            throw Failure(message: "Folge \(entry.episode) ist bei \(provider.label) noch nicht abrufbar.")
        }
        let known = library.progress(
            slug: entry.slug,
            season: entry.season,
            episode: entry.episode,
            path: episode.path,
            provider: provider
        )
        return SeriesView.PlayTarget(
            series: detail,
            episode: episode,
            resumeAt: library.resumeEnabled ? resumePosition(known) : 0,
            provider: provider
        )
    }

    /// Die Serie holen, notfalls ohne Staffelangabe.
    ///
    /// Der zweite Versuch ist für Titel, die gar keine Staffel 1 führen —
    /// reine Filmreihen etwa. Ohne ihn liefe „Jetzt ansehen" dort in eine
    /// 404, obwohl es auf der Grundseite etwas abzuspielen gibt.
    private static func series(
        slug: String,
        provider: CatalogProvider,
        season: String
    ) async throws -> SeriesDetail {
        do {
            return try await AniworldClient.shared.getSeries(provider: provider, slug: slug, season: season)
        } catch {
            return try await AniworldClient.shared.getSeries(provider: provider, slug: slug, season: nil)
        }
    }
}

// MARK: - Nachweis

/// Der Hinweis auf TMDB am Fuß der Startseite.
///
/// TMDBs Nutzungsbedingungen verlangen von jeder Anwendung, die ihre Daten
/// verwendet, einen sichtbaren Hinweis samt Logo mit dem Wortlaut, dass die
/// Anwendung TMDB benutzt, aber nicht von TMDB stammt oder unterstützt wird.
/// Das Logo liegt nicht bei — es gehört TMDB und darf nicht nachgezeichnet
/// werden —, deshalb steht hier der Text, und die Einstellungen nennen die
/// Quelle noch einmal ausführlich.
///
/// Der Hinweis steht am Fuß der Startseite und nicht in einem Untermenü:
/// hier werden die Daten tatsächlich gezeigt.
struct HomeAttribution: View {
    var body: some View {
        Text("Metadaten, Bilder und Beliebtheitswerte von TMDB. Nori wird von TMDB weder unterstützt noch zertifiziert.")
            .font(.caption2)
            .foregroundStyle(NoriTheme.muted.opacity(0.75))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HomeMetrics.screen)
    }
}
