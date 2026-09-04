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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct PlayTarget: Identifiable {
        var id: String { "\(episode.number)-\(resumeAt)" }
        let series: SeriesDetail
        let episode: Episode
        let resumeAt: Double
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
                                    let stats = library.seasonStats(slug: slug, season: season, episodes: detail.episodes)
                                    if stats.total > 0 {
                                        Text("\(stats.pct)% gesehen  \(stats.watched)/\(stats.total)")
                                            .font(.caption.weight(.medium))
                                    }
                                    Button {
                                        let target = library.nextPlay(slug: slug, season: season, episodes: detail.episodes)
                                        if let ep = detail.episodes.first(where: { $0.number == target.episode }) {
                                            play = PlayTarget(series: detail, episode: ep, resumeAt: library.resumeEnabled ? target.resumeAt : 0)
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
                                EpisodeRow(series: detail, episode: ep, season: season) { resumeAt in
                                    play = PlayTarget(series: detail, episode: ep, resumeAt: resumeAt)
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
        .task(id: detail?.coverPath) {
            guard let url = AniworldClient.coverURL(detail?.coverPath, provider: library.provider) else { return }
            if let tone = await CoverToneSampler.sample(url: url) {
                coverColor = tone
            }
        }
        .fullScreenCover(item: $play) { target in
            PlayerScreen(series: target.series, episode: target.episode, season: season, resumeAt: target.resumeAt)
        }
    }

    func cta(_ kind: String, episode: Int) -> String {
        switch kind {
        case "resume": return "Weiter · Folge \(episode)"
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
        } catch {
            let other: CatalogProvider = first == .aniworld ? .serienstream : .aniworld
            do {
                let loaded = try await AniworldClient.shared.getSeries(provider: other, slug: slug, season: season)
                library.provider = other
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
    let play: (Double) -> Void

    var body: some View {
        let item = library.progress(slug: series.slug, season: season, episode: episode.number, path: episode.path)
        let complete = isEpisodeComplete(item)
        let ratio = watchRatio(item)
        Button {
            play(library.resumeEnabled ? resumePosition(item) : 0)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(NoriTheme.elevated)
                        .frame(width: 44, height: 44)
                    if complete {
                        Image(systemName: "checkmark")
                    } else {
                        Text("\(episode.number)").font(.headline)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.germanTitle).font(.body.weight(.medium)).lineLimit(1)
                    if !episode.englishTitle.isEmpty {
                        Text(episode.englishTitle).font(.caption).foregroundStyle(NoriTheme.muted).lineLimit(1)
                    }
                    if ratio > 0, !complete {
                        ProgressView(value: ratio).tint(NoriTheme.accent)
                    }
                }
                Spacer()
                if let item, !complete, item.positionSec >= 8 {
                    Text("\(Int(ratio * 100))%").font(.caption).foregroundStyle(NoriTheme.muted)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(NoriPressStyle(enabled: !reduceMotion))
    }
}
