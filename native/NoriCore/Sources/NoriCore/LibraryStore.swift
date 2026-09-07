import Foundation
import Observation

/// Wohin die Bibliothek gespiegelt werden kann.
///
/// Bewusst schmal: die Bibliothek ist eine einzige JSON-Datei mit einem
/// Zeitstempel, und mehr braucht ein Abgleich nicht. Wer eine Ablage anbindet
/// — Google Drive, Dropbox, WebDAV — beantwortet genau zwei Fragen: was liegt
/// dort, und nimm das hier.
///
/// Zuvor war iCloud direkt im Store verdrahtet. Das ließ sich weder ersetzen
/// noch abschalten, und es funktionierte nicht: ohne die
/// Ubiquity-Berechtigung tut `NSUbiquitousKeyValueStore` nichts, ohne dass
/// irgendwo ein Fehler entsteht.
protocol LibrarySyncProvider: AnyObject, Sendable {
    /// Für die Oberfläche, etwa „Google Drive".
    var name: String { get }
    /// Der abgelegte Stand, oder `nil`, wenn dort noch nichts liegt.
    func load() async throws -> Data?
    func save(_ data: Data, modifiedAt: Double) async throws
}

@Observable
final class LibraryStore {
    static let schemaVersion = 4

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
    /// Wann zuletzt mit einem Fremdstand abgeglichen wurde. Ohne eingerichteten
    /// Anbieter bleibt der Wert leer.
    var syncLastRun: Double?

    /// Wohin die Bibliothek gespiegelt wird — oder `nil`, solange nichts
    /// eingerichtet ist.
    ///
    /// Hier stand iCloud, fest verdrahtet. Es hat nie funktioniert:
    /// `NSUbiquitousKeyValueStore` braucht die Berechtigung
    /// `com.apple.developer.ubiquity-kvstore-identifier`, und die gibt es nur
    /// im kostenpflichtigen Apple-Developer-Programm. Ohne sie tun die Aufrufe
    /// schlicht nichts — kein Fehler, keine Meldung. Der Schalter in den
    /// Einstellungen versprach also eine Synchronisation, die nie stattfand.
    ///
    /// Statt das zu kaschieren ist der Weg jetzt offen: ein Anbieter wird von
    /// außen gesetzt. Solange keiner da ist, sagt die Oberfläche das auch.
    var syncProvider: LibrarySyncProvider?

    private let url: URL
    private var isLoading = false
    private var modifiedAt: Double = 0

    /// `directory` nur für Tests.
    ///
    /// Ohne das müsste ein Test entweder in die echte Bibliothek des Benutzers
    /// schreiben oder die Persistenz ungeprüft lassen — und genau dort liegen
    /// Merkliste, Verlauf und Fortschritt. Die App ruft weiterhin
    /// `LibraryStore()` und landet im Anwendungsunterstützungsordner.
    init(directory: URL? = nil) {
        let folder = directory ?? NoriStorage.directory
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

    /// Wurde in dieser Staffel überhaupt schon etwas angeschaut?
    ///
    /// Die Unterscheidung fehlte: eine nie geöffnete Serie landete in der
    /// Schleife unten und bekam damit die Beschriftung „Weiter" — obwohl es
    /// nichts fortzusetzen gab. Auch die Fortschrittsangabe hing daran und
    /// stand mit „0 % gesehen" auf jeder Detailseite.
    func hasProgress(slug: String, season: String) -> Bool {
        progress.values.contains {
            $0.slug == slug
                && $0.season == season
                && ($0.provider ?? providerFromPath($0.episodePath)) == provider
                && ($0.positionSec > 0 || $0.completed == true)
        }
    }

    func nextPlay(slug: String, season: String, episodes: [Episode]) -> (episode: Int, resumeAt: Double, kind: String) {
        guard !episodes.isEmpty else { return (1, 0, "play") }
        let relevant = progress.values.filter { $0.slug == slug && ($0.provider ?? providerFromPath($0.episodePath)) == provider }
        if let latest = relevant.max(by: { $0.updatedAt < $1.updatedAt }), latest.season == season, !isEpisodeComplete(latest), episodes.contains(where: { $0.number == latest.episode }) {
            let at = resumeEnabled ? resumePosition(latest) : 0
            return (latest.episode, at, at >= 8 ? "resume" : "play")
        }
        // „next" nur, wenn es tatsächlich etwas gab, das weitergeht.
        let started = hasProgress(slug: slug, season: season)
        for ep in episodes.sorted(by: { $0.number < $1.number }) {
            let item = progress(slug: slug, season: season, episode: ep.number, path: ep.path, provider: provider)
            if !isEpisodeComplete(item) {
                let at = resumeEnabled ? resumePosition(item) : 0
                if at >= 8 { return (ep.number, at, "resume") }
                return (ep.number, at, started ? "next" : "play")
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

    /// Von Hand angestoßener Abgleich. Ohne eingerichteten Anbieter passiert
    /// nichts — und die Oberfläche bietet den Knopf dann auch nicht an.
    func syncNow() {
        guard let syncProvider else { return }
        Task { await runSync(with: syncProvider) }
    }

    private func runSync(with provider: LibrarySyncProvider) async {
        // Erst holen: ein neuerer Fremdstand gewinnt, danach wird der
        // zusammengeführte Stand zurückgeschrieben.
        if let data = try? await provider.load(),
           let bag = try? JSONDecoder().decode(Bag.self, from: data),
           let remote = bag.modifiedAt, remote > modifiedAt {
            apply(bag)
            modifiedAt = remote
            writeLocal(makeBag(modifiedAt: remote))
        }
        let bag = makeBag(modifiedAt: modifiedAt)
        guard let data = try? JSONEncoder().encode(bag) else { return }
        try? await provider.save(data, modifiedAt: modifiedAt)
        syncLastRun = Date().timeIntervalSince1970 * 1000
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
        // Kein automatisches Hochladen: das lief früher bei jeder Änderung.
        // Ein Anbieter, der über das Netz geht, gehört nicht in jeden
        // Tastendruck — angestoßen wird über `syncNow`.
    }

    private func writeLocal(_ bag: Bag) {
        if let data = try? JSONEncoder().encode(bag) { try? data.write(to: url, options: .atomic) }
    }

    private func makeBag(modifiedAt: Double) -> Bag {
        Bag(version: Self.schemaVersion, modifiedAt: modifiedAt, favorites: favorites, recents: recents, titles: titles, progress: progress, langPref: langPref, hosterPref: hosterPref, resumeEnabled: resumeEnabled, autoplayNext: autoplayNext, playbackSpeed: playbackSpeed, provider: provider.rawValue, scope: scope.rawValue, favoriteSource: favoriteSource.mapValues(\.rawValue))
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
        // `cloudSyncEnabled` und `cloudLastSync` standen hier, solange iCloud
        // eingebaut war. Ältere library.json tragen die Schlüssel weiter;
        // JSONDecoder überliest, was der Typ nicht kennt.
    }
}
