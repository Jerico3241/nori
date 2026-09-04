import SwiftUI

struct SeriesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerHost.self) private var playerHost
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let slug: String
    let titleHint: String
    var providerOverride: CatalogProvider? = nil

    @State private var detail: SeriesDetail?
    @State private var season: String = "1"
    @State private var error: String?
    @State private var loading = true
    @State private var coverColor = NoriTheme.accent

    var body: some View {
        ZStack(alignment: .top) {
            NoriTheme.bg
            LinearGradient(
                colors: [coverColor.opacity(0.30), NoriTheme.bg.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 360)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: coverColor)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(NoriTheme.fg)
        }
        .navigationTitle(detail?.title ?? titleHint)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    library.toggleFavorite(slug, title: detail?.title ?? titleHint)
                } label: {
                    Label(
                        library.isFavorite(slug) ? "Gemerkt" : "Merken",
                        systemImage: library.isFavorite(slug) ? "heart.fill" : "heart"
                    )
                    .contentTransition(.symbolEffect(.replace))
                }
                .help(library.isFavorite(slug) ? "Aus Merkliste entfernen" : "Zur Merkliste hinzufügen")
            }
        }
        .task { await load(season: nil) }
        .task(id: detail?.coverPath) {
            guard let url = AniworldClient.coverURL(detail?.coverPath, provider: library.provider) else { return }
            if let tone = await CoverToneSampler.sample(url: url) { coverColor = tone }
        }
    }

    private var subtitle: String {
        guard let detail else { return "" }
        var parts: [String] = []
        if let year = detail.yearStart, !year.isEmpty { parts.append(year) }
        if !detail.genres.isEmpty { parts.append(detail.genres.prefix(3).joined(separator: " · ")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var content: some View {
        if loading && detail == nil {
            ProgressView("Serie wird geladen")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error, detail == nil {
            ContentUnavailableView(
                "Nicht geladen",
                systemImage: "wifi.exclamationmark",
                description: Text(error)
            )
        } else if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(detail)
                    if !detail.description.isEmpty {
                        Text(detail.description)
                            .font(.callout)
                            .foregroundStyle(NoriTheme.muted)
                            .textSelection(.enabled)
                            .frame(maxWidth: 760, alignment: .leading)
                    }
                    episodes(detail)
                }
                .padding(.horizontal, 28)
                .padding(.top, 34)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func header(_ detail: SeriesDetail) -> some View {
        HStack(alignment: .top, spacing: 22) {
            PosterTile(
                title: detail.title,
                slug: detail.slug,
                coverURL: AniworldClient.coverURL(detail.coverPath, provider: library.provider)
            )
            .frame(width: 176)

            VStack(alignment: .leading, spacing: 12) {
                Text(detail.title)
                    .font(.title.weight(.semibold))
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    ForEach(metaChips(detail), id: \.self) { chip in
                        Text(chip)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(NoriTheme.elevated, in: Capsule())
                    }
                }

                let stats = library.seasonStats(slug: slug, season: season, episodes: detail.episodes)
                if stats.total > 0 {
                    HStack(spacing: 10) {
                        ProgressView(value: Double(stats.watched), total: Double(stats.total))
                            .frame(width: 160)
                        Text("\(stats.pct) % · \(stats.watched)/\(stats.total) Folgen")
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                    }
                }

                HStack(spacing: 12) {
                    let target = library.nextPlay(slug: slug, season: season, episodes: detail.episodes)
                    Button {
                        guard let ep = detail.episodes.first(where: { $0.number == target.episode }) else { return }
                        open(series: detail, episode: ep, resumeAt: library.resumeEnabled ? target.resumeAt : 0)
                    } label: {
                        Label(cta(target.kind, episode: target.episode), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)

                    if detail.seasons.count > 1 {
                        Picker("Staffel", selection: seasonBinding) {
                            ForEach(detail.seasons) { item in
                                Text(item.label).tag(item.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 190)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 900, alignment: .leading)
    }

    private func metaChips(_ detail: SeriesDetail) -> [String] {
        var chips: [String] = []
        if let fsk = detail.fsk, !fsk.isEmpty { chips.append("FSK \(fsk)") }
        if let start = detail.yearStart, !start.isEmpty {
            if let end = detail.yearEnd, !end.isEmpty, end != start {
                chips.append("\(start)–\(end)")
            } else {
                chips.append(start)
            }
        }
        chips.append(contentsOf: detail.genres.prefix(3))
        return chips
    }

    private var seasonBinding: Binding<String> {
        Binding(
            get: { season },
            set: { next in
                guard next != season else { return }
                season = next
                Task { await load(season: next) }
            }
        )
    }

    private func episodes(_ detail: SeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NoriSectionHeader("Folgen", trailing: "\(detail.episodes.count)")
            VStack(spacing: 0) {
                ForEach(Array(detail.episodes.enumerated()), id: \.element.id) { index, ep in
                    if index > 0 { Divider().padding(.leading, 62) }
                    EpisodeRow(series: detail, episode: ep, season: season) { resumeAt in
                        open(series: detail, episode: ep, resumeAt: resumeAt)
                    }
                }
            }
            .background(NoriTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(NoriTheme.border)
            }
        }
        .frame(maxWidth: 900, alignment: .leading)
    }

    private func open(series: SeriesDetail, episode: Episode, resumeAt: Double) {
        playerHost.request = PlayerRequest(
            series: series,
            episode: episode,
            season: season,
            resumeAt: resumeAt
        )
        openWindow(id: NoriWindow.player)
    }

    func cta(_ kind: String, episode: Int) -> String {
        switch kind {
        case "resume": return "Weiterschauen · Folge \(episode)"
        case "next": return "Weiter · Folge \(episode)"
        default: return "Abspielen · Folge \(episode)"
        }
    }

    func load(season: String?) async {
        loading = detail == nil
        error = nil
        let first = providerOverride ?? library.provider
        do {
            let loaded = try await AniworldClient.shared.getSeries(provider: first, slug: slug, season: season)
            if library.provider != first { library.provider = first }
            detail = loaded
            self.season = loaded.activeSeason
            library.remember(slug: slug, title: loaded.title, provider: first)
        } catch let firstError {
            // Die andere Quelle nur probieren, wenn der Aufrufer keine genannt
            // hat. Mit ausdrücklich übergebener Quelle — Kalender, Merkliste,
            // Weiterschauen — stellte ein einmaliger Fehler sonst die ganze App
            // auf die falsche Quelle um, und der nächste Aufruf landete auf
            // einer Seite, die es dort nicht gibt.
            if providerOverride != nil {
                self.error = firstError.localizedDescription
            } else {
                let other: CatalogProvider = first == .aniworld ? .serienstream : .aniworld
                do {
                    let loaded = try await AniworldClient.shared.getSeries(provider: other, slug: slug, season: season)
                    library.provider = other
                    detail = loaded
                    self.season = loaded.activeSeason
                    library.remember(slug: slug, title: loaded.title, provider: other)
                } catch {
                    self.error = firstError.localizedDescription
                }
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
    let play: (Double) -> Void

    @State private var hovering = false

    var body: some View {
        let item = library.progress(slug: series.slug, season: season, episode: episode.number, path: episode.path, provider: library.provider)
        let complete = isEpisodeComplete(item)
        let ratio = watchRatio(item)
        let resumeAt = library.resumeEnabled ? resumePosition(item) : 0

        Button {
            play(resumeAt)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(NoriTheme.elevated)
                        .frame(width: 38, height: 38)
                    if hovering {
                        Image(systemName: "play.fill")
                            .foregroundStyle(NoriTheme.accent)
                    } else if complete {
                        Image(systemName: "checkmark")
                            .foregroundStyle(NoriTheme.muted)
                    } else {
                        Text("\(episode.number)")
                            .font(.callout.weight(.medium).monospacedDigit())
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.germanTitle.isEmpty ? "Folge \(episode.number)" : episode.germanTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if !episode.englishTitle.isEmpty {
                        Text(episode.englishTitle)
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                            .lineLimit(1)
                    }
                    if ratio > 0, !complete {
                        ProgressView(value: ratio)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                            .frame(maxWidth: 220)
                    }
                }

                Spacer(minLength: 8)

                if !episode.languages.isEmpty {
                    Text(episode.languages.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(NoriTheme.muted)
                }
                if let item, !complete, item.positionSec >= 8 {
                    Text("\(Int(ratio * 100)) %")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(NoriTheme.muted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(hovering ? NoriTheme.hover : Color.clear)
        }
        .buttonStyle(NoriPressStyle(enabled: !reduceMotion))
        .onHover { hovering = $0 }
        .help(episode.germanTitle.isEmpty ? "Folge \(episode.number)" : episode.germanTitle)
        .contextMenu {
            Button("Abspielen") { play(resumeAt) }
            if resumeAt >= 8 {
                Button("Von vorne abspielen") { play(0) }
            }
        }
    }
}
