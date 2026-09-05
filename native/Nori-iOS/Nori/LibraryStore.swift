import Foundation
import Observation

@Observable
final class LibraryStore {
    static let schemaVersion = 4
    private static let cloudDataKey = "nori.library.v3"
    private static let cloudUpdatedKey = "nori.library.v3.updatedAt"

    var favorites: [String] = []
    var recents: [RecentItem] = []
    var titles: [String: String] = [:]
    var progress: [String: WatchProgress] = [:]
    var favoriteSource: [String: CatalogProvider] = [:]
    var langPref: String = "DE" { didSet { persist() } }
    var hosterPref: String = "VOE" { didSet { persist() } }
    var resumeEnabled: Bool = true { didSet { persist() } }
    var autoplayNext: Bool = true { didSet { persist() } }
    var playbackSpeed: Float = 1.0 { didSet { persist() } }
    var provider: CatalogProvider = .aniworld { didSet { persist() } }
    /// Was die Bibliothek zeigt. Vorgabe „Alle": beide Quellen in einer
    /// Liste. `provider` bleibt daneben bestehen und entscheidet, welche
    /// Seite ein Titel ohne eigene Quellangabe öffnet.
    var scope: LibraryScope = .all { didSet { persist() } }
    var cloudSyncEnabled: Bool = false {
        didSet {
            // Beim Einlesen nichts auslösen: `apply` setzt dieses Feld mit,
            // wodurch mitten im Laden ein Abgleich startete, der über
            // mergeCloudIfNewer erneut in `apply` lief. Nach dem Laden richtet
            // `init` die Synchronisation ohnehin selbst ein.
            guard !isLoading else { return }
            persist()
            configureCloudSync()
            if cloudSyncEnabled { syncNow() }
        }
    }
    var cloudLastSync: Double?

    private let url: URL
    private let cloud = NSUbiquitousKeyValueStore.default
    private var cloudObserver: NSObjectProtocol?
    private var isLoading = false
    private var modifiedAt: Double = 0

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("Nori", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("library.json")
        load()
        configureCloudSync()
        if cloudSyncEnabled { syncNow() }
    }

    deinit {
        if let cloudObserver { NotificationCenter.default.removeObserver(cloudObserver) }
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

    func source(of slug: String) -> CatalogProvider { favoriteSource[slug] ?? provider }

    func remember(slug: String, title: String, provider: CatalogProvider? = nil) {
        titles[slug] = title
        recents.removeAll { $0.slug == slug }
        recents.insert(RecentItem(slug: slug, title: title, viewedAt: Date().timeIntervalSince1970 * 1000, provider: provider ?? self.provider), at: 0)
        if recents.count > 100 { recents = Array(recents.prefix(100)) }
        persist()
    }

    func progress(forPath path: String, lang: String? = nil, provider: CatalogProvider? = nil) -> WatchProgress? {
        let clean = normalizeEpisodePath(path)
        let expectedProvider = provider
        if let expectedProvider, let direct = progress[progressKey(path: clean, provider: expectedProvider)] { return direct }
        if let direct = progress[clean] { return direct }
        var best: WatchProgress?
        for item in progress.values {
            guard normalizeEpisodePath(item.episodePath) == clean else { continue }
            if let expectedProvider {
                let itemProvider = item.provider ?? providerFromPath(item.episodePath)
                guard itemProvider == expectedProvider else { continue }
            }
            if best == nil || item.updatedAt > best!.updatedAt { best = item }
        }
        return best
    }

    func progress(slug: String, season: String, episode: Int, path: String? = nil, provider: CatalogProvider? = nil) -> WatchProgress? {
        if let path, let byPath = self.progress(forPath: path, provider: provider) { return byPath }
        var best: WatchProgress?
        for item in progress.values where item.slug == slug && item.season == season && item.episode == episode {
            if let provider {
                let itemProvider = item.provider ?? providerFromPath(item.episodePath)
                guard itemProvider == provider else { continue }
            }
            if best == nil || item.updatedAt > best!.updatedAt { best = item }
        }
        return best
    }

    func upsert(_ item: WatchProgress) {
        let path = normalizeEpisodePath(item.episodePath)
        var next = item
        next.episodePath = path
        next.provider = next.provider ?? providerFromPath(path)
        if next.durationSec >= 20, next.positionSec >= next.durationSec * 0.9 { next.completed = true }
        progress[progressKey(path: path, provider: next.provider)] = next
        removeLegacyDuplicates(for: next)
        persist()
    }

    func continueWatching() -> [WatchProgress] {
        var latest: [String: WatchProgress] = [:]
        for item in progress.values {
            let itemProvider = item.provider ?? providerFromPath(item.episodePath)
            let key = "\(itemProvider.rawValue)|\(item.slug)"
            if latest[key] == nil || item.updatedAt > latest[key]!.updatedAt { latest[key] = item }
        }
        return latest.values
            .filter { !isEpisodeComplete($0) && ($0.positionSec < $0.durationSec * 0.96 || $0.durationSec < 20) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(16).map { $0 }
    }

    func seasonStats(slug: String, season: String, episodes: [Episode]) -> (watched: Int, total: Int, pct: Int) {
        let watched = episodes.filter { isEpisodeComplete(progress(slug: slug, season: season, episode: $0.number, path: $0.path, provider: provider)) }.count
        let total = episodes.count
        return (watched, total, total == 0 ? 0 : Int(round(Double(watched) / Double(total) * 100)))
    }

    func nextPlay(slug: String, season: String, episodes: [Episode]) -> (episode: Int, resumeAt: Double, kind: String) {
        guard !episodes.isEmpty else { return (1, 0, "play") }
        let relevant = progress.values.filter { $0.slug == slug && ($0.provider ?? providerFromPath($0.episodePath)) == provider }
        if let latest = relevant.max(by: { $0.updatedAt < $1.updatedAt }), latest.season == season, !isEpisodeComplete(latest), episodes.contains(where: { $0.number == latest.episode }) {
            let at = resumeEnabled ? resumePosition(latest) : 0
            return (latest.episode, at, at >= 8 ? "resume" : "play")
        }
        for ep in episodes.sorted(by: { $0.number < $1.number }) {
            let item = progress(slug: slug, season: season, episode: ep.number, path: ep.path, provider: provider)
            if !isEpisodeComplete(item) {
                let at = resumeEnabled ? resumePosition(item) : 0
                return (ep.number, at, at >= 8 ? "resume" : "next")
            }
        }
        return (episodes.sorted(by: { $0.number < $1.number })[0].number, 0, "play")
    }

    func nextEpisode(after episode: Episode, in episodes: [Episode]) -> Episode? {
        let sorted = episodes.sorted { $0.number < $1.number }
        guard let index = sorted.firstIndex(where: { $0.number == episode.number }) else { return nil }
        let next = sorted.index(after: index)
        return next < sorted.endIndex ? sorted[next] : nil
    }

    func clearHistory() { recents = []; persist() }
    func clearProgress() { progress = [:]; persist() }

    func syncNow() {
        guard cloudSyncEnabled else { return }
        _ = cloud.synchronize()
        mergeCloudIfNewer()
        pushCloud()
    }

    private func configureCloudSync() {
        if let cloudObserver { NotificationCenter.default.removeObserver(cloudObserver); self.cloudObserver = nil }
        guard cloudSyncEnabled else { return }
        cloudObserver = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) { [weak self] _ in
            self?.mergeCloudIfNewer()
        }
    }

    private func mergeCloudIfNewer() {
        guard cloudSyncEnabled,
              let data = cloud.data(forKey: Self.cloudDataKey),
              let bag = try? JSONDecoder().decode(Bag.self, from: data)
        else { return }
        let remoteModified = bag.modifiedAt ?? cloud.double(forKey: Self.cloudUpdatedKey)
        guard remoteModified > modifiedAt else { return }
        apply(bag)
        modifiedAt = remoteModified
        cloudLastSync = remoteModified
        writeLocal(makeBag(modifiedAt: remoteModified))
    }

    private func load() {
        guard let data = try? Data(contentsOf: url), let bag = try? JSONDecoder().decode(Bag.self, from: data) else { return }
        apply(bag)
        modifiedAt = bag.modifiedAt ?? 0
        if (bag.version ?? 1) < Self.schemaVersion || progress.count != bag.progress.count { persist() }
    }

    private func apply(_ bag: Bag) {
        isLoading = true
        favorites = bag.favorites
        recents = bag.recents
        titles = bag.titles
        langPref = bag.langPref ?? "DE"
        hosterPref = bag.hosterPref ?? "VOE"
        resumeEnabled = bag.resumeEnabled ?? true
        autoplayNext = bag.autoplayNext ?? true
        playbackSpeed = bag.playbackSpeed ?? 1.0
        cloudSyncEnabled = bag.cloudSyncEnabled ?? false
        cloudLastSync = bag.cloudLastSync
        if let raw = bag.provider, let next = CatalogProvider(rawValue: raw) { provider = next }
        // Ältere Stände kennen den Bereich nicht. Sie bekommen „Alle" — das
        // ist der Sinn der gemeinsamen Bibliothek, nicht ein Verlust.
        scope = bag.scope.flatMap(LibraryScope.init(rawValue:)) ?? .all
        favoriteSource = bag.favoriteSource?.compactMapValues { CatalogProvider(rawValue: $0) } ?? [:]
        progress = migrateProgress(bag.progress)
        isLoading = false
    }

    private func migrateProgress(_ old: [String: WatchProgress]) -> [String: WatchProgress] {
        var migrated: [String: WatchProgress] = [:]
        for value in old.values {
            var item = value
            item.episodePath = normalizeEpisodePath(item.episodePath)
            item.provider = item.provider ?? providerFromPath(item.episodePath)
            let key = progressKey(path: item.episodePath, provider: item.provider)
            if migrated[key] == nil || item.updatedAt > migrated[key]!.updatedAt { migrated[key] = item }
        }
        return migrated
    }

    private func removeLegacyDuplicates(for item: WatchProgress) {
        let clean = normalizeEpisodePath(item.episodePath)
        let keep = progressKey(path: clean, provider: item.provider)
        let matching = progress.keys.filter { key in
            guard key != keep, let existing = progress[key] else { return false }
            return normalizeEpisodePath(existing.episodePath) == clean && (existing.provider ?? providerFromPath(existing.episodePath)) == item.provider
        }
        for key in matching { progress.removeValue(forKey: key) }
    }

    private func persist() {
        guard !isLoading else { return }
        modifiedAt = Date().timeIntervalSince1970 * 1000
        let bag = makeBag(modifiedAt: modifiedAt)
        writeLocal(bag)
        if cloudSyncEnabled { pushCloud(bag) }
    }

    private func pushCloud(_ bag: Bag? = nil) {
        guard cloudSyncEnabled else { return }
        let next = bag ?? makeBag(modifiedAt: modifiedAt)
        guard let data = try? JSONEncoder().encode(next) else { return }
        cloud.set(data, forKey: Self.cloudDataKey)
        cloud.set(modifiedAt, forKey: Self.cloudUpdatedKey)
        _ = cloud.synchronize()
        cloudLastSync = modifiedAt
    }

    private func writeLocal(_ bag: Bag) {
        if let data = try? JSONEncoder().encode(bag) { try? data.write(to: url, options: .atomic) }
    }

    private func makeBag(modifiedAt: Double) -> Bag {
        Bag(version: Self.schemaVersion, modifiedAt: modifiedAt, favorites: favorites, recents: recents, titles: titles, progress: progress, langPref: langPref, hosterPref: hosterPref, resumeEnabled: resumeEnabled, autoplayNext: autoplayNext, playbackSpeed: playbackSpeed, provider: provider.rawValue, scope: scope.rawValue, favoriteSource: favoriteSource.mapValues(\.rawValue), cloudSyncEnabled: cloudSyncEnabled, cloudLastSync: cloudLastSync)
    }

    private struct Bag: Codable {
        var version: Int?
        var modifiedAt: Double?
        var favorites: [String]
        var recents: [RecentItem]
        var titles: [String: String]
        var progress: [String: WatchProgress]
        var langPref: String?
        var hosterPref: String?
        var resumeEnabled: Bool?
        var autoplayNext: Bool?
        var playbackSpeed: Float?
        var provider: String?
        var scope: String?
        var favoriteSource: [String: String]?
        var cloudSyncEnabled: Bool?
        var cloudLastSync: Double?
    }
}
