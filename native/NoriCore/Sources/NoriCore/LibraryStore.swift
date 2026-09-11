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
    static let schemaVersion = 5

    var favorites: [String] = []
    var recents: [RecentItem] = []
    var titles: [String: String] = [:]
    var progress: [String: WatchProgress] = [:]
    var favoriteSource: [String: CatalogProvider] = [:]
    /// Wann ein Titel gemerkt wurde, als Millisekunden seit 1970.
    ///
    /// Neu in Schema v5. Vorher gab es dazu nur die Reihenfolge in
    /// `favorites` — neu Gemerktes kam nach vorn. Das reicht, solange eine
    /// Liste genau so angezeigt wird, wie sie gespeichert ist; sobald jemand
    /// alphabetisch sortiert und danach „zuletzt hinzugefügt" wählt, ist die
    /// Information nicht mehr rekonstruierbar. Die Merkliste sortiert genau
    /// danach, also braucht sie einen echten Zeitpunkt und kein Ersatzmaß.
    ///
    /// Ältere Stände tragen ihn nicht. Sie bekommen ihn beim Laden aus der
    /// bestehenden Reihenfolge abgeleitet (siehe `backfillAddedAt`) — der
    /// erste Eintrag gilt als der jüngste. Das ist keine Erfindung, sondern
    /// genau die Aussage, die in der Reihenfolge steckt.
    var favoriteAddedAt: [String: Double] = [:]
    var langPref: String = "DE" { didSet { persist() } }
    var hosterPref: String = "VOE" { didSet { persist() } }
    var resumeEnabled: Bool = true { didSet { persist() } }
    /// Bevorzugte Bildhöhe als Zeichenkette: „auto", „1080", „720", „480".
    ///
    /// Eine Höhe und keine Bitrate, weil die Oberfläche Höhen nennt und jede
    /// Master-Playlist sie mitliefert. „auto" heißt: der Spieler entscheidet.
    ///
    /// Erzwingen lässt sich das nur, wo der Hoster überhaupt mehrere Spuren
    /// anbietet — eine einzelne MP4-Datei hat keine Stufen, und Nori tut dann
    /// auch nicht so. Die Auswahl ist deshalb ein *Wunsch*: der Spieler nimmt
    /// die höchste angebotene Stufe, die nicht darüber liegt.
    var preferredQuality: String = "auto" { didSet { persist() } }
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

    /// Was der Abgleich gerade tut.
    ///
    /// Nicht abgelegt und deshalb auch nicht in `Bag`: der Zustand gilt für
    /// diesen Programmlauf. Die Oberfläche braucht ihn, um einen laufenden
    /// Abgleich von einem fertigen und von einem fehlgeschlagenen zu
    /// unterscheiden — vorher gab es nur `syncLastRun`, und ein Fehlschlag sah
    /// damit genauso aus wie „noch nie gelaufen".
    var syncState: SyncState = .idle

    enum SyncState: Equatable {
        case idle
        case running
        case failed(String)
    }

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
        let folder: URL
        if let directory {
            folder = directory
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            folder = dir.appendingPathComponent("Nori", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("library.json")
        load()
    }

    func isFavorite(_ slug: String) -> Bool { favorites.contains(slug) }

    func toggleFavorite(_ slug: String, title: String? = nil) {
        if favorites.contains(slug) {
            _ = removeFavorite(slug)
        } else {
            favorites.insert(slug, at: 0)
            favoriteSource[slug] = provider
            favoriteAddedAt[slug] = Date().timeIntervalSince1970 * 1000
            if let title { titles[slug] = title }
            persist()
        }
    }

    func source(of slug: String) -> CatalogProvider { favoriteSource[slug] ?? provider }

    /// Wann der Titel gemerkt wurde. `nil`, wenn er gar nicht gemerkt ist.
    ///
    /// Nie `nil` für einen gemerkten Titel: fehlt der Zeitpunkt, wird er beim
    /// Laden aus der Reihenfolge abgeleitet. Die Merkliste darf sich also
    /// darauf verlassen, statt nebenher einen zweiten Ersatzwert zu pflegen.
    func addedAt(_ slug: String) -> Double? {
        guard favorites.contains(slug) else { return nil }
        return favoriteAddedAt[slug]
    }

    /// Was ein entfernter Eintrag hinterlässt — genug, um ihn unverändert
    /// zurückzulegen.
    ///
    /// Für „Rückgängig" in der Merkliste. Über `toggleFavorite` wieder
    /// hinzugefügt käme der Titel an Position 0 und mit neuem Zeitpunkt
    /// zurück; er stünde danach woanders als vorher, und das sieht aus wie
    /// ein zweiter Fehler statt wie eine Rücknahme.
    ///
    /// Ausdrücklich **ohne** Fortschritt: Merkliste und Verlauf sind
    /// getrennt, und deshalb ist beim Entfernen auch nichts davon verloren
    /// gegangen, das hier zurückgelegt werden müsste.
    struct FavoriteSnapshot: Hashable {
        let slug: String
        let index: Int
        let title: String?
        let source: CatalogProvider?
        let addedAt: Double?
    }

    /// Aus der Merkliste nehmen. Fortschritt, Verlauf und Titel bleiben.
    ///
    /// Der Titel bleibt bewusst in `titles` stehen: er trägt die Namen im
    /// Verlauf und in „Weiterschauen", die mit der Merkliste nichts zu tun
    /// haben. Ein entfernter Titel würde dort sonst als Slug erscheinen.
    @discardableResult
    func removeFavorite(_ slug: String) -> FavoriteSnapshot? {
        guard let index = favorites.firstIndex(of: slug) else { return nil }
        let snapshot = FavoriteSnapshot(
            slug: slug,
            index: index,
            title: titles[slug],
            source: favoriteSource[slug],
            addedAt: favoriteAddedAt[slug]
        )
        favorites.remove(at: index)
        favoriteSource.removeValue(forKey: slug)
        favoriteAddedAt.removeValue(forKey: slug)
        persist()
        return snapshot
    }

    /// Einen entfernten Eintrag zurücklegen — an dieselbe Stelle, mit
    /// demselben Zeitpunkt.
    func restoreFavorite(_ snapshot: FavoriteSnapshot) {
        guard !favorites.contains(snapshot.slug) else { return }
        favorites.insert(snapshot.slug, at: min(snapshot.index, favorites.count))
        if let source = snapshot.source { favoriteSource[snapshot.slug] = source }
        favoriteAddedAt[snapshot.slug] = snapshot.addedAt ?? Date().timeIntervalSince1970 * 1000
        if let title = snapshot.title { titles[snapshot.slug] = title }
        persist()
    }

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
    func hasProgress(slug: String, season: String, source: CatalogProvider? = nil) -> Bool {
        let provider = source ?? self.provider
        return progress.values.contains {
            $0.slug == slug
                && $0.season == season
                && ($0.provider ?? providerFromPath($0.episodePath)) == provider
                && ($0.positionSec > 0 || $0.completed == true)
        }
    }

    /// Welche Folge beim Antippen laufen soll.
    ///
    /// `source` gibt die Quelle vor, statt die Vorgabequelle zu nehmen. Ohne
    /// das griff die Suche daneben, sobald ein Titel der *anderen* Seite
    /// angetippt wurde — seit die Bibliothek beide Quellen zusammenführt, ist
    /// das der Normalfall und nicht die Ausnahme. Ohne Angabe bleibt es beim
    /// alten Verhalten, damit bestehende Aufrufe unverändert weiterlaufen.
    func nextPlay(
        slug: String,
        season: String,
        episodes: [Episode],
        source: CatalogProvider? = nil
    ) -> (episode: Int, resumeAt: Double, kind: String) {
        guard !episodes.isEmpty else { return (1, 0, "play") }
        let provider = source ?? self.provider
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

    /// Einen einzelnen Verlaufseintrag entfernen.
    ///
    /// Der Fortschritt bleibt stehen: „aus dem Verlauf nehmen" heißt, den
    /// Eintrag aus der Liste der zuletzt angesehenen Titel zu streichen, nicht
    /// zu vergessen, wie weit die Folge lief. Wer das will, löscht den
    /// Fortschritt — dafür gibt es `clearProgress`.
    func forgetRecent(slug: String) {
        let before = recents.count
        recents.removeAll { $0.slug == slug }
        guard recents.count != before else { return }
        persist()
    }
    func clearProgress() { progress = [:]; persist() }

    /// Von Hand angestoßener Abgleich. Ohne eingerichteten Anbieter passiert
    /// nichts — und die Oberfläche bietet den Knopf dann auch nicht an.
    func syncNow() {
        guard let syncProvider, syncState != .running else { return }
        Task { await runSync(with: syncProvider) }
    }

    /// Holen, zusammenführen, zurückschreiben.
    ///
    /// Fehlschläge werden gemeldet statt verschluckt. Vorher stand hier
    /// durchgehend `try?`: ein Anbieter ohne Netz tat dann scheinbar nichts,
    /// und `syncLastRun` blieb leer — von „noch nie gelaufen" nicht zu
    /// unterscheiden. Die Oberfläche kann einen Fehler nur zeigen, wenn er
    /// irgendwo ankommt.
    private func runSync(with provider: LibrarySyncProvider) async {
        syncState = .running
        do {
            // Erst holen: ein neuerer Fremdstand gewinnt, danach wird der
            // zusammengeführte Stand zurückgeschrieben.
            if let data = try await provider.load(),
               let bag = try? JSONDecoder().decode(Bag.self, from: data),
               let remote = bag.modifiedAt, remote > modifiedAt {
                apply(bag)
                modifiedAt = remote
                writeLocal(makeBag(modifiedAt: remote))
            }
            let bag = makeBag(modifiedAt: modifiedAt)
            let data = try JSONEncoder().encode(bag)
            try await provider.save(data, modifiedAt: modifiedAt)
            syncLastRun = Date().timeIntervalSince1970 * 1000
            syncState = .idle
        } catch {
            syncState = .failed(error.localizedDescription)
        }
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
        preferredQuality = bag.preferredQuality ?? "auto"
        autoplayNext = bag.autoplayNext ?? true
        playbackSpeed = bag.playbackSpeed ?? 1.0
        if let raw = bag.provider, let next = CatalogProvider(rawValue: raw) { provider = next }
        // Ältere Stände kennen den Bereich nicht. Sie bekommen „Alle" — das
        // ist der Sinn der gemeinsamen Bibliothek, nicht ein Verlust.
        scope = bag.scope.flatMap(LibraryScope.init(rawValue:)) ?? .all
        favoriteSource = bag.favoriteSource?.compactMapValues { CatalogProvider(rawValue: $0) } ?? [:]
        favoriteAddedAt = backfillAddedAt(bag.favoriteAddedAt ?? [:], favorites: favorites)
        progress = migrateProgress(bag.progress)
        isLoading = false
    }

    /// Fehlende Merkzeitpunkte aus der Reihenfolge ergänzen.
    ///
    /// Vor Schema v5 gab es das Feld nicht; `favorites` war die einzige
    /// Auskunft, und darin steht das zuletzt Gemerkte vorn. Genau das wird
    /// hier zu Zeitpunkten gemacht: der erste Eintrag bekommt den jüngsten.
    ///
    /// Der Anker liegt **unterhalb** aller bereits bekannten Zeitpunkte, in
    /// Ein-Minuten-Schritten rückwärts. Sonst könnte ein abgeleiteter Wert
    /// einen echten überholen, und ein Titel, der gestern gemerkt wurde,
    /// stünde vor einem von heute. Ohne echte Werte ist der Anker „jetzt",
    /// womit ein alter Stand beim ersten Laden genau seine bisherige
    /// Reihenfolge behält.
    ///
    /// Einträge zu Slugs, die nicht mehr gemerkt sind, fallen weg — sonst
    /// wüchse die Datei mit jedem entfernten Titel weiter.
    private func backfillAddedAt(_ stored: [String: Double], favorites: [String]) -> [String: Double] {
        var out = stored.filter { favorites.contains($0.key) }
        let missing = favorites.filter { out[$0] == nil }
        guard !missing.isEmpty else { return out }
        let step: Double = 60_000
        var stamp = (out.values.min() ?? Date().timeIntervalSince1970 * 1000)
        // Der jüngste fehlende Eintrag steht vorn in `favorites` und bekommt
        // deshalb den größten Wert; jeder weitere liegt eine Minute davor.
        for slug in missing {
            stamp -= step
            out[slug] = stamp
        }
        return out
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
        Bag(version: Self.schemaVersion, modifiedAt: modifiedAt, favorites: favorites, recents: recents, titles: titles, progress: progress, langPref: langPref, hosterPref: hosterPref, resumeEnabled: resumeEnabled, autoplayNext: autoplayNext, playbackSpeed: playbackSpeed, preferredQuality: preferredQuality, provider: provider.rawValue, scope: scope.rawValue, favoriteSource: favoriteSource.mapValues(\.rawValue), favoriteAddedAt: favoriteAddedAt)
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
        var preferredQuality: String?
        var provider: String?
        var scope: String?
        var favoriteSource: [String: String]?
        /// Neu in v5. Optional, damit ältere library.json weiter dekodieren;
        /// fehlt der Eintrag, leitet `backfillAddedAt` ihn aus `favorites` ab.
        var favoriteAddedAt: [String: Double]?
        // `cloudSyncEnabled` und `cloudLastSync` standen hier, solange iCloud
        // eingebaut war. Ältere library.json tragen die Schlüssel weiter;
        // JSONDecoder überliest, was der Typ nicht kennt.
    }
}
