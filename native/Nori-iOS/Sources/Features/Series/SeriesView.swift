import SwiftUI

/// Die Detailseite einer Serie.
///
/// Aufbau: ein durchgehender senkrechter Lauf aus zwei Teilen. Oben der
/// Kopfbereich — Artwork über die volle Breite, bis unter die Statusleiste,
/// und darauf Schriftzug, Eckdaten, Beschreibung und die beiden Knöpfe. Darunter
/// die Staffelwahl und die vollständige Folgenliste. Dazwischen liegt nichts:
/// kein Umschalter „Details | Folgen", keine Reihe „Als Nächstes", keine
/// aufklappbaren Staffeln.
///
/// Diese Datei hält nur den Zustand und die Ladewege zusammen. Gezeichnet wird
/// in `SeriesHeroView`, `SeriesEpisodeList` und `SeriesEpisodeCard`.
struct SeriesView: View {
    @Environment(LibraryStore.self) private var library
    /// „Dynamische Farben" aus „Mehr → Darstellung": ob die Farbe des Artworks
    /// Kleinigkeiten der Seite einfärben darf.
    @AppStorage(NoriLook.dynamicColorsKey) private var dynamicColors = true
    let slug: String
    let titleHint: String
    var providerOverride: CatalogProvider? = nil

    @State private var detail: SeriesDetail?
    @State private var season: String = "1"
    @State private var error: String?
    @State private var loading = true
    /// Eine andere Staffel wird geholt. Die Liste bleibt stehen und blendet
    /// ab, statt zu verschwinden.
    @State private var switchingSeason = false
    @State private var play: PlayTarget?
    /// Standbilder, Titel, Laufzeiten und Erstausstrahlung der Folgen, nach
    /// Nummer.
    @State private var episodeInfo: [Int: EpisodeInfo] = [:]
    /// Breitbild, Poster, Beschreibung und Bewertung aus TMDB.
    @State private var art = CoverDetails(poster: nil, backdrop: nil, overview: nil, rating: nil)
    /// Das Cover der Quelle. Nur nötig, wenn TMDB die Serie nicht führt —
    /// ohne das bliebe der Kopfbereich dann leer.
    @State private var sourceCover: URL?
    @State private var logo: URL?
    /// Die vorherrschende Farbe des Artworks. Trägt den Schimmer im
    /// Kopfbereich und den Fortschritt in der Liste.
    @State private var tone: Color?
    /// Die Quelle, aus der die Serie tatsächlich kam.
    ///
    /// `load` weicht auf die andere Seite aus, wenn die erste nichts hergibt.
    /// Ohne diesen Merker liefe danach alles andere — Referer der Bilder,
    /// Schlüssel des Fortschritts, die Quelle im Player — weiter gegen die
    /// Seite, die gar nicht geantwortet hat.
    @State private var resolvedProvider: CatalogProvider?

    /// Läuft neu, sobald die Staffel wechselt **oder** die Serie eintrifft:
    /// beim ersten Aufbau steht die Staffel schon auf „1“, `detail` aber noch
    /// nicht — ein Schlüssel nur aus der Staffel würde das verpassen.
    private var episodeTaskID: String { "\(slug)|\(season)|\(detail == nil ? 0 : 1)" }

    struct PlayTarget: Identifiable {
        var id: String { "\(episode.number)-\(resumeAt)" }
        let series: SeriesDetail
        let episode: Episode
        let resumeAt: Double
        let provider: CatalogProvider
    }

    var body: some View {
        ZStack {
            NoriTheme.bg.ignoresSafeArea()

            if let detail {
                content(detail)
            } else if let error {
                ContentUnavailableView(
                    "Nicht geladen",
                    systemImage: "wifi.exclamationmark",
                    description: Text(error)
                )
            } else if loading {
                // Der Umriss der Seite statt eines Rädchens mitten im Schwarz:
                // der Titel ist vom Antippen her bekannt und steht sofort da,
                // Kopfbereich und Folgenliste haben ihren Platz schon.
                SeriesSkeleton(title: titleHint, screen: NoriScreenMetrics.size)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Das Artwork läuft unter der Leiste durch; ein Balken darüber würde
        // es abschneiden.
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let detail {
                ToolbarItem(placement: .topBarTrailing) { moreMenu(detail) }
            }
        }
        .task { await load(season: nil) }
        .task(id: episodeTaskID) { await loadEpisodeInfo() }
        .task(id: detail?.slug) { await loadArt() }
        .task(id: artwork.url) { await sampleTone() }
        .fullScreenCover(item: $play) { target in
            PlayerScreen(
                series: target.series,
                episode: target.episode,
                season: season,
                resumeAt: target.resumeAt,
                provider: target.provider
            )
        }
    }

    // MARK: - Aufbau

    private func content(_ detail: SeriesDetail) -> some View {
        let screen = NoriScreenMetrics.size

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SeriesHeroView(
                    detail: detail,
                    artwork: artwork,
                    tone: tone,
                    logo: logo,
                    stars: art.stars,
                    overview: art.overview,
                    season: season,
                    provider: source,
                    screen: screen,
                    play: { episode, at in start(episode, in: detail, at: at) }
                )

                SeriesEpisodeList(
                    detail: detail,
                    season: season,
                    provider: source,
                    episodeInfo: episodeInfo,
                    artwork: artwork,
                    tone: tone,
                    switching: switchingSeason,
                    width: min(screen.width, SeriesMetrics.content),
                    select: select,
                    play: { episode, at in start(episode, in: detail, at: at) }
                )
                // Auf dem iPad soll die Liste nicht über die ganze Breite
                // laufen — eine Folgenkarte von 1000 Punkten ist eine Zeile mit
                // sehr viel Luft, keine Karte. Der Kopfbereich darüber bleibt
                // absichtlich voll breit.
                .frame(maxWidth: SeriesMetrics.content)
                .frame(maxWidth: .infinity)
            }
            // Platz für die Tableiste; ohne ihn steht die letzte Folge
            // dahinter.
            .padding(.bottom, 56)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .noriSoftScrollEdges(.top)
    }

    /// Das Überlaufmenü oben rechts — der einzige weitere Knopf im
    /// Kopfbereich neben „Zurück“.
    ///
    /// Nur, was die App auch kann: teilen, von vorn abspielen, den Stand einer
    /// Staffel setzen oder verwerfen, dazu Quelle, Freigabe und
    /// Alternativtitel zum Nachlesen.
    private func moreMenu(_ detail: SeriesDetail) -> some View {
        Menu {
            if let url = seriesURL() {
                ShareLink(item: url) { Label("Teilen", systemImage: "square.and.arrow.up") }
            }

            Section {
                Button {
                    start(first(detail), in: detail, at: 0)
                } label: {
                    Label("Von vorn abspielen", systemImage: "backward.end.fill")
                }
                .disabled(detail.episodes.isEmpty)

                Button {
                    markSeasonWatched(detail)
                } label: {
                    Label("Staffel als gesehen markieren", systemImage: "checkmark.circle")
                }
                .disabled(detail.episodes.isEmpty)

                if library.hasProgress(slug: slug, season: season, source: source) {
                    Button(role: .destructive) {
                        forgetSeason(detail)
                    } label: {
                        Label("Fortschritt der Staffel vergessen", systemImage: "arrow.counterclockwise")
                    }
                }
            }

            Section("Quelle") {
                Text(source.label)
                if let fsk = detail.fsk, !fsk.isEmpty { Text("FSK \(fsk)") }
            }

            if !detail.alts.isEmpty {
                Section("Auch bekannt als") {
                    ForEach(detail.alts.prefix(3), id: \.self) { Text($0) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Weitere Aktionen")
    }

    // MARK: - Daten

    /// Die Quelle dieser Serie — nie der globale Schalter, sofern die Serie
    /// schon geladen ist.
    private var source: CatalogProvider {
        resolvedProvider ?? providerOverride ?? library.provider
    }

    /// Das Bild, das Kopfbereich, Farbabtastung und der Rückfall der
    /// Folgenkacheln benutzen.
    private var artwork: SeriesArtwork {
        SeriesArtwork.resolve(details: art, sourceCover: sourceCover, provider: source)
    }

    private func first(_ detail: SeriesDetail) -> Episode? {
        detail.episodes.min(by: { $0.number < $1.number })
    }

    private func seriesURL() -> URL? {
        URL(string: source.origin + source.seriesPath(slug: slug, season: season))
    }

    private func start(_ episode: Episode?, in detail: SeriesDetail, at position: Double) {
        guard let episode else { return }
        play = PlayTarget(series: detail, episode: episode, resumeAt: position, provider: source)
    }

    /// Staffel wechseln. Die bisherige Liste bleibt stehen, bis die neue da
    /// ist — sonst fiele die Seite bei jedem Wechsel kurz in sich zusammen.
    private func select(_ next: String) {
        guard next != season else { return }
        season = next
        Task { await load(season: next) }
    }

    /// Eine ganze Staffel auf einmal — ein Schreibvorgang, nicht einer je Folge.
    private func markSeasonWatched(_ detail: SeriesDetail) {
        let now = Date().timeIntervalSince1970
        let items = detail.episodes.map { episode in
            // Die Laufzeit, sofern schon eine bekannt ist: sie stehen zu
            // lassen ist richtiger, als sie beim Abhaken auf null zu setzen.
            let known = library.progress(
                slug: slug, season: season, episode: episode.number, path: episode.path, provider: source
            )
            return WatchProgress(
                slug: slug, title: detail.title, season: season, episode: episode.number,
                episodePath: episode.path, germanTitle: episode.germanTitle,
                englishTitle: episode.englishTitle,
                positionSec: known?.durationSec ?? 0, durationSec: known?.durationSec ?? 0,
                updatedAt: now, lang: known?.lang, completed: true, provider: source
            )
        }
        library.upsert(contentsOf: items)
    }

    private func forgetSeason(_ detail: SeriesDetail) {
        let now = Date().timeIntervalSince1970
        let items = detail.episodes.map { episode in
            WatchProgress(
                slug: slug, title: detail.title, season: season, episode: episode.number,
                episodePath: episode.path, germanTitle: episode.germanTitle,
                englishTitle: episode.englishTitle, positionSec: 0, durationSec: 0,
                updatedAt: now, provider: source
            )
        }
        library.upsert(contentsOf: items)
    }

    private func loadArt() async {
        guard let detail else { return }
        art = await CoverIndex.shared.detailsLoading(
            slug: slug,
            title: detail.title,
            // Ohne die Alternativtitel sucht TMDB nur unter dem Namen, unter
            // dem die Quelle die Serie führt — bei Anime regelmäßig einer,
            // den TMDB gar nicht kennt.
            alternates: detail.alts,
            kind: source
        )

        // Ohne TMDB-Treffer hätte der Kopfbereich weder Breitbild noch Poster
        // und bliebe leer. Der Coverpfad steht schon auf der Detailseite und
        // kostet nichts; erst wenn auch der fehlt, wird nachgeschlagen.
        if art.backdrop == nil, art.poster == nil {
            if let own = AniworldClient.coverURL(detail.coverPath, provider: source) {
                sourceCover = own
            } else {
                sourceCover = await CoverIndex.shared.fetchSourceCover(slug: slug, provider: source)
            }
        }

        logo = await CoverIndex.shared.logoLoading(
            slug: slug, title: detail.title, alternates: detail.alts, kind: source
        )
    }

    /// Die vorherrschende Farbe des Artworks abtasten.
    ///
    /// Sie färbt nur Kleinigkeiten ein — den Schimmer hinter dem Titel, den
    /// Fortschrittsring, den Streifen unter einem angefangenen Standbild. Die
    /// Seite selbst bleibt dunkel; ein rotes Artwork macht aus Nori keine rote
    /// App.
    private func sampleTone() async {
        // „Dynamische Farben" aus „Mehr → Darstellung". Aus heißt: gar nicht
        // abtasten — sonst liefe der Abruf weiter und nur das Ergebnis bliebe
        // ungenutzt.
        guard dynamicColors else {
            tone = nil
            return
        }
        guard let url = artwork.url else {
            tone = nil
            return
        }
        let sampled = await CoverToneSampler.sample(url: url)
        guard !Task.isCancelled else { return }
        withAnimation(NoriMotion.content) { tone = sampled?.noriReadableAccent() }
    }

    private func loadEpisodeInfo() async {
        guard let detail else { return }
        // Erst das, was schon dasteht: die Liste erscheint mit Bildern, ohne
        // auf TMDB zu warten. Der Aufruf trägt danach nach.
        episodeInfo = await EpisodeIndex.shared.cached(slug: slug, season: season)
        let loaded = await EpisodeIndex.shared.load(
            slug: slug,
            title: detail.title,
            // Die Quelle führt Serien oft unter einem eingedeutschten oder
            // verkürzten Namen, den TMDB nicht kennt. Die Alternativtitel von
            // der Detailseite treffen dann meist.
            alternates: detail.alts,
            season: season,
            kind: source,
            // Die Folgen der Quelle als Anker: TMDB teilt Anime oft anders in
            // Staffeln ein, und dann trifft die bloße Nummer die falsche
            // Folge oder gar keine.
            sourceEpisodes: detail.episodes.tmdbSourceEpisodes
        )
        guard !Task.isCancelled, !loaded.isEmpty else { return }
        episodeInfo = loaded
    }

    /// Die Serie laden — **ohne** globalen Zustand anzufassen.
    ///
    /// Früher setzte diese Funktion `library.provider` auf die Quelle, aus
    /// der die Serie kam, und die Merkliste tat dasselbe beim Öffnen. Das
    /// stammt aus der Zeit, als der Umschalter ein Moduswechsel war. Seit die
    /// Bibliothek beide Quellen zusammenführt, ist es schädlich: `source(of:)`
    /// fällt für Einträge ohne eigene Quellangabe auf `library.provider`
    /// zurück, und die Merkliste teilt danach in „Anime“ und „Serien“ auf.
    /// Ein einziges Öffnen verschob damit fremde Einträge zwischen den
    /// Abschnitten. Was ein Titel öffnet, steht in `providerOverride`
    /// beziehungsweise am Eintrag selbst — dafür braucht es keinen globalen
    /// Schalter.
    func load(season: String?) async {
        loading = detail == nil
        switchingSeason = detail != nil
        error = nil
        defer {
            loading = false
            switchingSeason = false
        }

        let first = providerOverride ?? library.provider
        do {
            let loaded = try await AniworldClient.shared.getSeries(provider: first, slug: slug, season: season)
            apply(loaded, from: first)
        } catch {
            let other: CatalogProvider = first == .aniworld ? .serienstream : .aniworld
            do {
                let loaded = try await AniworldClient.shared.getSeries(provider: other, slug: slug, season: season)
                apply(loaded, from: other)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func apply(_ loaded: SeriesDetail, from provider: CatalogProvider) {
        detail = loaded
        season = loaded.activeSeason
        resolvedProvider = provider
        library.remember(slug: slug, title: loaded.title, provider: provider)
    }
}

/// Die Detailseite, bevor die Serie da ist.
///
/// Aufgebaut wie die fertige Seite: das Artworkband oben, darunter Titel,
/// Eckdaten, Beschreibung und die beiden Knöpfe, dann die Folgen. Der Titel
/// ist schon bekannt — er kam mit dem Antippen — und steht deshalb echt da
/// statt als Balken.
private struct SeriesSkeleton: View {
    let title: String
    let screen: CGSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Color.clear.frame(height: max(screen.height * 0.34, 150))
                    Text(title)
                        .font(.system(size: screen.width > 700 ? 44 : 34, weight: .bold, design: .serif))
                        .foregroundStyle(NoriTheme.fg)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                    Group {
                        Text("2024 · Genre · Genre")
                            .font(.subheadline)
                        Text("Eine Beschreibung der Serie über drei Zeilen, damit der Platz dafür reserviert ist und nichts springt, wenn der Text eintrifft.")
                            .font(.callout)
                            .lineLimit(3)
                    }
                    .redacted(reason: .placeholder)
                    .foregroundStyle(NoriTheme.elevated)
                    HStack(spacing: 10) {
                        Capsule().fill(NoriTheme.elevated).frame(height: 50)
                        Capsule().fill(NoriTheme.elevated).frame(width: 50, height: 50)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, NoriSpacing.screen)
                .frame(maxWidth: SeriesMetrics.content)
                .frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    LinearGradient(
                        colors: [NoriTheme.elevated, NoriTheme.bg],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: max(screen.height * 0.34, 150) + 60)
                }

                VStack(spacing: 12) {
                    ForEach(0 ..< 4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NoriTheme.elevated)
                            .frame(height: 92)
                    }
                }
                .padding(.horizontal, NoriSpacing.screen)
                .frame(maxWidth: SeriesMetrics.content)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollDisabled(true)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) wird geladen")
    }
}
