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
    /// Backdrop, Logo und Bewertung aus TMDB. Der Kopfbereich lebt davon.
    @State private var art = CoverDetails(poster: nil, backdrop: nil, overview: nil, rating: nil)
    @State private var logo: URL?
    @State private var tab: DetailTab = .episodes
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

    /// Details oder Folgen — wie in Serien-Apps ueblich.
    enum DetailTab: String, CaseIterable, Identifiable {
        case details, episodes
        var id: String { rawValue }
        var label: String { self == .details ? "Details" : "Folgen" }
    }

    var body: some View {
        ZStack(alignment: .top) {
            NoriTheme.bg.ignoresSafeArea()

            if loading && detail == nil {
                ProgressView("Serie wird geladen").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, detail == nil {
                ContentUnavailableView("Nicht geladen", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if let detail {
                content(detail)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load(season: nil) }
        .task(id: episodeTaskID) { await loadEpisodeInfo() }
        .task(id: detail?.slug) { await loadArt() }
        .fullScreenCover(item: $play) { target in
            PlayerScreen(series: target.series, episode: target.episode, season: season, resumeAt: target.resumeAt, provider: target.provider)
        }
    }

    // MARK: - Aufbau

    private func content(_ detail: SeriesDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(detail)
                Picker("Ansicht", selection: $tab) {
                    ForEach(DetailTab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                switch tab {
                case .details: detailsTab(detail)
                case .episodes: episodesTab(detail)
                }
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
    }

    /// Backdrop, darueber der Schriftzug, darunter die Eckdaten.
    ///
    /// Das Bild laeuft bis unter die Statusleiste und verlaeuft nach unten in
    /// den Hintergrund — dieselbe Form, die Serien-Apps benutzen. Das Poster
    /// kommt hier nicht mehr vor: es stand frueher als Kachel neben dem
    /// Titel, und beides zusammen war doppelt.
    private func header(_ detail: SeriesDetail) -> some View {
        VStack(spacing: 12) {
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay { backdropImage(detail) }
                .overlay {
                    LinearGradient(
                        colors: [.clear, NoriTheme.bg.opacity(0.55), NoriTheme.bg],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .bottom) { titleArt(detail).padding(.horizontal, 24) }

            metaLines(detail)
            actionRow(detail)
        }
    }

    @ViewBuilder
    private func backdropImage(_ detail: SeriesDetail) -> some View {
        if let url = art.backdrop ?? AniworldClient.coverURL(detail.coverPath, provider: source) {
            NoriCoverImage(url: url, referer: source.origin + "/") { NoriTheme.elevated }
        } else {
            NoriTheme.elevated
        }
    }

    /// Schriftzug aus TMDB, sonst der Titel. Wie auf der Startseite.
    @ViewBuilder
    private func titleArt(_ detail: SeriesDetail) -> some View {
        if let logo {
            AsyncImage(url: logo) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                EmptyView()
            }
            .frame(maxWidth: .infinity, maxHeight: 84)
            .accessibilityLabel(detail.title)
        } else {
            Text(detail.title)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
        }
    }

    /// Zwei Zeilen Eckdaten, mittig — Jahr und Genres, darunter Staffelzahl,
    /// Stand und Bewertung.
    private func metaLines(_ detail: SeriesDetail) -> some View {
        VStack(spacing: 6) {
            let first = [detail.yearStart, detail.genres.prefix(3).joined(separator: " · ")]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
            if !first.isEmpty {
                Text(first).font(.subheadline).foregroundStyle(NoriTheme.muted)
            }
            HStack(spacing: 8) {
                Text(seasonSummary(detail))
                if let stars = art.stars {
                    Text("★ \(String(format: "%.1f", stars))").foregroundStyle(.yellow)
                }
            }
            .font(.subheadline)
            .foregroundStyle(NoriTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    private func seasonSummary(_ detail: SeriesDetail) -> String {
        let count = detail.seasons.count
        let seasons = count == 1 ? "1 Staffel" : "\(count) Staffeln"
        guard let end = detail.yearEnd, !end.isEmpty else { return "\(seasons) · Laufend" }
        return "\(seasons) · Beendet"
    }

    /// Merkliste und ein Ueberlaufmenue — bewusst ohne Anbieter-Zeile.
    private func actionRow(_ detail: SeriesDetail) -> some View {
        HStack(spacing: 12) {
            Button {
                library.toggleFavorite(slug, title: detail.title)
            } label: {
                Label(
                    library.isFavorite(slug) ? "Gemerkt" : "Merkliste",
                    systemImage: library.isFavorite(slug) ? "bookmark.fill" : "bookmark"
                )
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Capsule().fill(NoriTheme.elevated))
                .overlay { Capsule().strokeBorder(NoriTheme.border) }
            }
            .buttonStyle(.plain)

            Menu {
                Button("Von vorn abspielen") { playEpisode(first(detail), in: detail, at: 0) }
                if library.hasProgress(slug: slug, season: season) {
                    Button("Fortschritt dieser Staffel vergessen", role: .destructive) {
                        for ep in detail.episodes {
                            library.upsert(WatchProgress(
                                slug: slug, title: detail.title, season: season, episode: ep.number,
                                episodePath: ep.path, germanTitle: ep.germanTitle,
                                englishTitle: ep.englishTitle, positionSec: 0, durationSec: 0,
                                updatedAt: Date().timeIntervalSince1970, provider: source
                            ))
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.callout.weight(.bold))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(NoriTheme.elevated))
                    .overlay { Circle().strokeBorder(NoriTheme.border) }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Details

    @ViewBuilder
    private func detailsTab(_ detail: SeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !detail.description.isEmpty {
                Text(detail.description).font(.subheadline).foregroundStyle(NoriTheme.fg.opacity(0.9))
            }
            if !detail.alts.isEmpty {
                infoLine("Auch bekannt als", detail.alts.prefix(3).joined(separator: " · "))
            }
            if let fsk = detail.fsk, !fsk.isEmpty { infoLine("FSK", fsk) }
            infoLine("Quelle", source.label)
        }
        .padding(.horizontal, 20)
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(.caption).foregroundStyle(NoriTheme.muted).frame(width: 120, alignment: .leading)
            Text(value).font(.subheadline)
        }
    }

    // MARK: - Folgen

    @ViewBuilder
    private func episodesTab(_ detail: SeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            watchNext(detail)
            seasonList(detail)
        }
    }

    /// „Als Naechstes" — waagerechte Karten mit Standbild.
    ///
    /// Beginnt bei der Folge, die `nextPlay` bestimmt: der zuletzt
    /// angefangenen, solange sie nicht zu Ende gesehen ist, sonst der
    /// naechsten unfertigen. Danach die darauffolgenden.
    @ViewBuilder
    private func watchNext(_ detail: SeriesDetail) -> some View {
        let upcoming = nextEpisodes(detail)
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Als Nächstes").font(.title3.weight(.semibold))
                    Spacer()
                    Text(seasonLabel(detail)).font(.subheadline).foregroundStyle(NoriTheme.muted)
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(upcoming) { ep in
                            nextCard(ep, in: detail)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func nextCard(_ ep: Episode, in detail: SeriesDetail) -> some View {
        Button {
            let at = library.resumeEnabled
                ? resumePosition(library.progress(forPath: ep.path, provider: source))
                : 0
            playEpisode(ep, in: detail, at: at)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        if let still = episodeInfo[ep.number]?.stillURL {
                            // TMDB-Bilder brauchen keinen Referer, anders als die Cover der Quellen.
                            NoriCoverImage(url: still, referer: "") { NoriTheme.elevated }
                        } else {
                            NoriTheme.elevated
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("FOLGE \(ep.number)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(NoriTheme.muted)
                Text(episodeTitle(ep))
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .frame(width: 240, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    /// Die Staffelliste. Die gewaehlte Staffel klappt ihre Folgen darunter auf.
    private func seasonList(_ detail: SeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Alle Folgen")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            ForEach(detail.seasons) { ref in
                seasonRow(ref, in: detail)
                if ref.id == season {
                    ForEach(detail.episodes) { ep in
                        EpisodeRow(series: detail, episode: ep, season: season, info: episodeInfo[ep.number]) { at in
                            play = PlayTarget(series: detail, episode: ep, resumeAt: at, provider: source)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
    }

    private func seasonRow(_ ref: SeasonRef, in detail: SeriesDetail) -> some View {
        Button {
            guard ref.id != season else { return }
            season = ref.id
            Task { await load(season: ref.id) }
        } label: {
            HStack(spacing: 14) {
                Text(ref.label).font(.headline)
                Spacer()
                Image(systemName: ref.id == season ? "chevron.down" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NoriTheme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(ref.id == season ? NoriTheme.surface : .clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hilfen

    /// Die Quelle dieser Serie — nie der globale Schalter.
    private var source: CatalogProvider { providerOverride ?? library.provider }

    private func first(_ detail: SeriesDetail) -> Episode? {
        detail.episodes.min(by: { $0.number < $1.number })
    }

    /// Der Titel einer Folge: TMDB zuerst, dann die Quelle, sonst die Nummer.
    private func episodeTitle(_ ep: Episode) -> String {
        if let tmdb = episodeInfo[ep.number]?.title, !tmdb.isEmpty { return tmdb }
        if !ep.germanTitle.isEmpty { return ep.germanTitle }
        if !ep.englishTitle.isEmpty { return ep.englishTitle }
        return "Folge \(ep.number)"
    }

    private func seasonLabel(_ detail: SeriesDetail) -> String {
        detail.seasons.first(where: { $0.id == season })?.label ?? "Staffel \(season)"
    }

    private func nextEpisodes(_ detail: SeriesDetail, limit: Int = 8) -> [Episode] {
        let target = library.nextPlay(slug: slug, season: season, episodes: detail.episodes, source: source)
        let sorted = detail.episodes.sorted { $0.number < $1.number }
        guard let index = sorted.firstIndex(where: { $0.number == target.episode }) else {
            return Array(sorted.prefix(limit))
        }
        return Array(sorted[index...].prefix(limit))
    }

    private func playEpisode(_ ep: Episode?, in detail: SeriesDetail, at position: Double) {
        guard let ep else { return }
        play = PlayTarget(series: detail, episode: ep, resumeAt: position, provider: source)
    }

    private func loadArt() async {
        guard let detail else { return }
        art = await CoverIndex.shared.detailsLoading(slug: slug, title: detail.title, kind: source)
        logo = await CoverIndex.shared.logoLoading(
            slug: slug, title: detail.title, alternates: detail.alts, kind: source
        )
    }

    private func loadEpisodeInfo() async {
        guard let detail else { return }
        // Erst das, was schon dasteht: die Liste erscheint mit Bildern, ohne
        // auf TMDB zu warten. Der Aufruf traegt danach nach.
        episodeInfo = await EpisodeIndex.shared.cached(slug: slug, season: season)
        let loaded = await EpisodeIndex.shared.load(
            slug: slug,
            title: detail.title,
            // Die Quelle fuehrt Serien oft unter einem eingedeutschten oder
            // verkuerzten Namen, den TMDB nicht kennt. Die Alternativtitel von
            // der Detailseite treffen dann meist.
            alternates: detail.alts,
            season: season,
            kind: source
        )
        guard !Task.isCancelled, !loaded.isEmpty else { return }
        episodeInfo = loaded
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

