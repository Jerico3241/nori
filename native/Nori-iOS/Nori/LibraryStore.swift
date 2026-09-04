import Foundation
import Observation

@Observable
final class LibraryStore {
    var favorites: [String] = []
    var recents: [RecentItem] = []
    var titles: [String: String] = [:]
    var progress: [String: WatchProgress] = [:]
    var favoriteSource: [String: CatalogProvider] = [:]
    var langPref: String = "DE" { didSet { persist() } }
    var hosterPref: String = "VOE" { didSet { persist() } }
    var resumeEnabled: Bool = true { didSet { persist() } }
    var autoplayNext: Bool = true { didSet { persist() } }
    var provider: CatalogProvider = .aniworld { didSet { persist() } }

    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("Nori", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("library.json")
        load()
    }

    func isFavorite(_ slug: String) -> Bool { favorites.contains(slug) }

    func toggleFavorite(_ slug: String, title: String? = nil) {
        if let idx = favorites.firstIndex(of: slug) {
            favorites.remove(at: idx)
            favoriteSource.removeValue(forKey: slug)
        } else {
            favorites.insert(slug, at: 0)
            favoriteSource[slug] = provider
            if let title { titles[slug] = title }
        }
        persist()
    }

    func source(of slug: String) -> CatalogProvider {
        favoriteSource[slug] ?? provider
    }

    func remember(slug: String, title: String, provider: CatalogProvider? = nil) {
        titles[slug] = title
        recents.removeAll { $0.slug == slug }
        recents.insert(RecentItem(slug: slug, title: title, viewedAt: Date().timeIntervalSince1970 * 1000, provider: provider ?? self.provider), at: 0)
        if recents.count > 40 { recents = Array(recents.prefix(40)) }
        persist()
    }

    func progress(forPath path: String, lang: String? = nil) -> WatchProgress? {
        let clean = normalizeEpisodePath(path)
        if let lang {
            if let keyed = progress[progressKey(path: clean, lang: lang)] { return keyed }
        }
        if let direct = progress[clean] ?? progress[path] { return direct }
        var best: WatchProgress?
        for (key, item) in progress where key == clean || key == path || key.hasPrefix("\(clean)::") || key.hasPrefix("\(path)::") {
            if best == nil || item.updatedAt > best!.updatedAt { best = item }
        }
        return best
    }

    func progress(slug: String, season: String, episode: Int, path: String? = nil) -> WatchProgress? {
        if let path, let byPath = self.progress(forPath: path) { return byPath }
        var best: WatchProgress?
        for item in progress.values where item.slug == slug && item.season == season && item.episode == episode {
            if best == nil || item.updatedAt > best!.updatedAt { best = item }
        }
        return best
    }

    func upsert(_ item: WatchProgress) {
        let path = normalizeEpisodePath(item.episodePath)
        var next = item
        next.episodePath = path
        if next.durationSec >= 20, next.positionSec >= next.durationSec * 0.9 {
            next.completed = true
        }
        progress[progressKey(path: path, lang: next.lang)] = next
        progress[path] = next
        persist()
    }

    func continueWatching() -> [WatchProgress] {
        var latest: [String: WatchProgress] = [:]
        for item in progress.values {
            if latest[item.slug] == nil || item.updatedAt > latest[item.slug]!.updatedAt {
                latest[item.slug] = item
            }
        }
        return latest.values
            .filter { !isEpisodeComplete($0) && ($0.positionSec < $0.durationSec * 0.96 || $0.durationSec < 20) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(16)
            .map { $0 }
    }

    func seasonStats(slug: String, season: String, episodes: [Episode]) -> (watched: Int, total: Int, pct: Int) {
        var watched = 0
        for ep in episodes {
            if isEpisodeComplete(progress(slug: slug, season: season, episode: ep.number, path: ep.path)) {
                watched += 1
            }
        }
        let total = episodes.count
        return (watched, total, total == 0 ? 0 : Int(round(Double(watched) / Double(total) * 100)))
    }

    func nextPlay(slug: String, season: String, episodes: [Episode]) -> (episode: Int, resumeAt: Double, kind: String) {
        guard !episodes.isEmpty else { return (1, 0, "play") }
        if let latest = progress.values.filter({ $0.slug == slug }).max(by: { $0.updatedAt < $1.updatedAt }),
           latest.season == season,
           !isEpisodeComplete(latest),
           episodes.contains(where: { $0.number == latest.episode })
        {
            let at = resumeEnabled ? resumePosition(latest) : 0
            return (latest.episode, at, at >= 8 ? "resume" : "play")
        }
        for ep in episodes {
            let item = progress(slug: slug, season: season, episode: ep.number, path: ep.path)
            if !isEpisodeComplete(item) {
                let at = resumeEnabled ? resumePosition(item) : 0
                return (ep.number, at, at >= 8 ? "resume" : "next")
            }
        }
        return (episodes[0].number, 0, "play")
    }

    func clearHistory() {
        recents = []
        persist()
    }

    func clearProgress() {
        progress = [:]
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let bag = try? JSONDecoder().decode(Bag.self, from: data)
        else { return }
        favorites = bag.favorites
        recents = bag.recents
        titles = bag.titles
        progress = bag.progress
        langPref = bag.langPref ?? "DE"
        hosterPref = bag.hosterPref ?? "VOE"
        resumeEnabled = bag.resumeEnabled ?? true
        autoplayNext = bag.autoplayNext ?? true
        if let raw = bag.provider, let next = CatalogProvider(rawValue: raw) {
            provider = next
        }
        if let sources = bag.favoriteSource {
            favoriteSource = sources.compactMapValues { CatalogProvider(rawValue: $0) }
        }
    }

    private func persist() {
        let bag = Bag(
            favorites: favorites,
            recents: recents,
            titles: titles,
            progress: progress,
            langPref: langPref,
            hosterPref: hosterPref,
            resumeEnabled: resumeEnabled,
            autoplayNext: autoplayNext,
            provider: provider.rawValue,
            favoriteSource: favoriteSource.mapValues(\.rawValue)
        )
        if let data = try? JSONEncoder().encode(bag) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private struct Bag: Codable {
        var favorites: [String]
        var recents: [RecentItem]
        var titles: [String: String]
        var progress: [String: WatchProgress]
        var langPref: String?
        var hosterPref: String?
        var resumeEnabled: Bool?
        var autoplayNext: Bool?
        var provider: String?
        var favoriteSource: [String: String]?
    }
}