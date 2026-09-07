import SwiftUI

struct SeriesView: View {
    @Environment(LibraryStore.self) private var library
    let slug: String
    let titleHint: String
    var providerOverride: CatalogProvider? = nil

    @State private var detail: SeriesDetail?
    @State private var season: String = "1"
    @State private var error: String?
    @State private var loading = true
    @State private var play: PlayTarget?
    @State private var coverColor = NoriTheme.accent
    /// Standbilder und Beschreibungen der Folgen, nach Nummer.
    @State private var episodeInfo: [Int: EpisodeInfo] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Läuft neu, sobald die Staffel wechselt **oder** die Serie eintrifft:
    /// beim ersten Aufbau steht die Staffel schon auf „1", `detail` aber noch
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
        ZStack(alignment: .topLeading) {
            RadialGradient(
                colors: [coverColor.opacity(0.42), NoriTheme.bg],
                center: .topLeading,
                startRadius: 8,
                endRadius: 480
            )
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: coverColor)

            Group {
                if loading && detail == nil {
                    ProgressView("Serie wird geladen").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, detail == nil {
                    ContentUnavailableView("Nicht geladen", systemImage: "wifi.exclamationmark", description: Text(error))
                } else if let detail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 16) {
                                PosterTile(
                                    title: detail.title,
                                    slug: detail.slug,
                                    coverURL: AniworldClient.coverURL(detail.coverPath, provider: library.provider)
                                )
                                .frame(width: 120)
                                .shadow(color: coverColor.opacity(0.45), radius: 18, y: 8)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(detail.title).font(.title2.weight(.semibold))
                                    if !detail.genres.isEmpty {
                                        Text(detail.genres.prefix(4).joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(NoriTheme.muted)
                                    }
                                    // Erst zeigen, wenn tatsächlich etwas
                                    // angesehen wurde. „0 % gesehen 0/1" auf
                                    // einer Serie, die man noch nie geöffnet
                                    // hat, ist keine Angabe, sondern Lärm.
                                    let stats = library.seasonStats(slug: slug, season: season, episodes: detail.episodes)
                                    if library.hasProgress(slug: slug, season: season), stats.total > 0 {
                                        Text("\(stats.pct)% gesehen  \(stats.watched)/\(stats.total)")
                                            .font(.caption.weight(.medium))
                                    }
                                    Button {
                                        let target = library.nextPlay(slug: slug, season: season, episodes: detail.episodes)
                                        if let ep = detail.episodes.first(where: { $0.number == target.episode }) {
                                            play = PlayTarget(series: detail, episode: ep, resumeAt: library.resumeEnabled ? target.resumeAt : 0, provider: library.provider)
                                        }
                                    } label: {
                                        let target = library.nextPlay(slug: slug, season: season, episodes: detail.episodes)
                                        Text(cta(target.kind, episode: target.episode))
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(coverColor)
                                    .foregroundStyle(NoriTheme.bg)
                                }
                            }
                            if !detail.description.isEmpty {
                                Text(detail.description).font(.subheadline).foregroundStyle(NoriTheme.muted)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(detail.seasons) { s in
                                        Button(s.label) {
                                            season = s.id
                                            Task { await load(season: s.id) }
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(season == s.id ? coverColor : NoriTheme.muted)
                                    }
                                }
                            }
                            ForEach(detail.episodes) { ep in
                                EpisodeRow(
                                    series: detail,
                                    episode: ep,
                                    season: season,
                                    info: episodeInfo[ep.number]
                                ) { resumeAt in
                                    play = PlayTarget(series: detail, episode: ep, resumeAt: resumeAt, provider: library.provider)
                                }
                            }
                        }
                        .padding(20)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: detail.episodes.count)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(NoriTheme.fg)
        }
        .navigationTitle(detail?.title ?? titleHint)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.toggleFavorite(slug, title: detail?.title ?? titleHint)
                } label: {
                    Image(systemName: library.isFavorite(slug) ? "heart.fill" : "heart")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
        .task {
            await load(season: nil)
        }
        .task(id: episodeTaskID) {
            guard let detail else { return }
            // Erst das, was schon dasteht: die Liste erscheint mit Bildern,
            // ohne auf TMDB zu warten. Der Aufruf trägt danach nach.
            episodeInfo = await EpisodeIndex.shared.cached(slug: slug, season: season)
            let loaded = await EpisodeIndex.shared.load(
                slug: slug,
                title: detail.title,
                // Die Quelle führt Serien oft unter einem eingedeutschten oder
                // verkürzten Namen, den TMDB nicht kennt. Die Alternativtitel
                // von der Detailseite treffen dann meist.
                alternates: detail.alts,
                season: season,
                kind: library.provider
            )
            guard !Task.isCancelled, !loaded.isEmpty else { return }
            episodeInfo = loaded
        }
        .task(id: detail?.coverPath) {
            guard let url = AniworldClient.coverURL(detail?.coverPath, provider: library.provider) else { return }
            if let tone = await CoverToneSampler.sample(url: url) {
                coverColor = tone
            }
        }
        .fullScreenCover(item: $play) { target in
            PlayerScreen(series: target.series, episode: target.episode, season: season, resumeAt: target.resumeAt, provider: target.provider)
        }
    }

    func cta(_ kind: String, episode: Int) -> String {
        switch kind {
        case "resume": return "Weiter · Folge \(episode)"
        case "next": return "Weiter · Folge \(episode)"
        default: return "Abspielen · Folge \(episode)"
        }
    }

    /// Die Serie laden — **ohne** globalen Zustand anzufassen.
    ///
    /// Frueher setzte diese Funktion `library.provider` auf die Quelle, aus
    /// der die Serie kam, und die Merkliste tat dasselbe beim Oeffnen. Das
    /// stammt aus der Zeit, als der Umschalter ein Moduswechsel war. Seit die
    /// Bibliothek beide Quellen zusammenfuehrt, ist es schaedlich: `source(of:)`
    /// faellt fuer Eintraege ohne eigene Quellangabe auf `library.provider`
    /// zurueck, und die Merkliste teilt danach in „Anime" und „Serien" auf.
    /// Ein einziges Oeffnen verschob damit fremde Eintraege zwischen den
    /// Abschnitten. Was ein Titel oeffnet, steht in `providerOverride`
    /// beziehungsweise am Eintrag selbst — dafuer braucht es keinen globalen
    /// Schalter.
    func load(season: String?) async {
        loading = detail == nil
        error = nil
        let first = providerOverride ?? library.provider
        do {
            let loaded = try await AniworldClient.shared.getSeries(provider: first, slug: slug, season: season)
            detail = loaded
            self.season = loaded.activeSeason
            library.remember(slug: slug, title: loaded.title, provider: first)
        } catch {
            let other: CatalogProvider = first == .aniworld ? .serienstream : .aniworld
            do {
                let loaded = try await AniworldClient.shared.getSeries(provider: other, slug: slug, season: season)
                detail = loaded
                self.season = loaded.activeSeason
                library.remember(slug: slug, title: loaded.title, provider: other)
            } catch {
                self.error = error.localizedDescription
            }
        }
        loading = false
    }
}

struct EpisodeRow: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let series: SeriesDetail
    let episode: Episode
    let season: String
    /// Bild und Beschreibung aus TMDB. `nil`, solange nichts geladen ist oder
    /// TMDB die Serie nicht kennt — dann sieht die Zeile aus wie zuvor, nur
    /// mit einer Kachel im 16:9-Format statt eines Quadrats.
    var info: EpisodeInfo? = nil
    let play: (Double) -> Void

    /// „Episode 7" ist kein Titel, sondern die Nummer in Worten. Beide Quellen
    /// setzen das ein, wo sie keinen echten Titel haben — und daneben steht
    /// dann noch einmal dasselbe als englischer Titel.
    private static func isPlaceholder(_ text: String) -> Bool {
        text.range(
            of: #"^\s*(episode|folge|ep\.?)\s*\d+\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// Der Titel der Quelle, sofern es einer ist; sonst der von TMDB, sonst
    /// die Nummer.
    private var shownTitle: String {
        let own = episode.germanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty, !Self.isPlaceholder(own) { return own }
        if let other = info?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !other.isEmpty, !Self.isPlaceholder(other) {
            return other
        }
        if !own.isEmpty { return own }
        return "Folge \(episode.number)"
    }

    /// Der englische Titel, aber nur wenn er etwas hinzufügt: dieselbe
    /// Zeichenkette zweimal untereinander ist keine Auskunft.
    private var shownSubtitle: String? {
        let other = episode.englishTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !other.isEmpty, !Self.isPlaceholder(other) else { return nil }
        guard other.caseInsensitiveCompare(shownTitle) != .orderedSame else { return nil }
        return other
    }

    var body: some View {
        let item = library.progress(slug: series.slug, season: season, episode: episode.number, path: episode.path)
        let complete = isEpisodeComplete(item)
        let ratio = watchRatio(item)
        Button {
            play(library.resumeEnabled ? resumePosition(item) : 0)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                thumb(complete: complete, ratio: ratio)
                VStack(alignment: .leading, spacing: 4) {
                    Text(shownTitle).font(.body.weight(.medium)).lineLimit(2)
                    if let shownSubtitle {
                        Text(shownSubtitle).font(.caption).foregroundStyle(NoriTheme.muted).lineLimit(1)
                    }
                    if let text = info?.overview, !text.isEmpty {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if let item, !complete, item.positionSec >= 8 {
                    Text("\(Int(ratio * 100))%").font(.caption).foregroundStyle(NoriTheme.muted)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(NoriPressStyle(enabled: !reduceMotion))
    }

    /// Die Folgenkachel: das Standbild aus TMDB, sonst die Nummer wie bisher.
    ///
    /// Der Fortschritt liegt als schmaler Streifen am unteren Rand statt als
    /// `ProgressView` unter dem Titel — dort stand er zwischen Titel und
    /// Beschreibung im Weg, und am Bild ist er die geläufige Form.
    private func thumb(complete: Bool, ratio: Double) -> some View {
        ZStack {
            NoriTheme.elevated
            if let url = info?.stillURL {
                // image.tmdb.org braucht keine Kopfzeilen; `NoriCoverImage`
                // bringt aber den Zwischenspeicher mit, den `AsyncImage` nicht
                // hat — dieselbe Folge wird beim Blättern nicht neu geladen.
                NoriCoverImage(url: url, referer: "https://www.themoviedb.org/") {
                    Color.clear
                }
            }
            if complete {
                Color.black.opacity(info?.stillURL == nil ? 0 : 0.5)
                Image(systemName: "checkmark")
                    .font(.headline)
            } else if info?.stillURL == nil {
                Text("\(episode.number)").font(.headline)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if info?.stillURL != nil, !complete {
                Text("\(episode.number)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(5)
            }
        }
        .overlay(alignment: .bottom) {
            if ratio > 0, !complete {
                GeometryReader { geo in
                    Rectangle()
                        .fill(NoriTheme.accent)
                        .frame(width: geo.size.width * min(max(ratio, 0), 1), height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 3)
            }
        }
        .frame(width: 112, height: 63)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(NoriTheme.border)
        }
    }
}

