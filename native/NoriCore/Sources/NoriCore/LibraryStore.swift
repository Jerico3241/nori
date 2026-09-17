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
    static let schemaVersion = 6

    /// Wie lange Fortschritt aus einer laufenden Wiedergabe höchstens nur im
    /// Speicher steht, bevor er auf die Platte geht.
    ///
    /// Der Player sichert alle fünf Sekunden. Jede Sicherung schrieb bisher die
    /// **ganze** Bibliothek atomar auf die Platte — auf dem Hauptthread, eine
    /// Folge lang zwölfmal pro Minute. Die Oberfläche bekommt den Stand
    /// weiterhin sofort; geschrieben wird gebündelt und sofort bei `flush()`:
    /// Pause, Ende der Wiedergabe, Hintergrund.
    static let deferredWriteDelay: TimeInterval = 10

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

    // Einstellungen. Eine Zuweisung desselben Wertes ist **keine** Änderung:
    // der Player setzt Hoster und Sprache bei jedem Start. Bekäme derselbe
    // Wert eine frische Marke, überschriebe er beim nächsten Abgleich die
    // bewusste Wahl eines anderen Geräts — und jede Wiedergabe schriebe die
    // Bibliothek zweimal auf die Platte und stieße einen Upload an.
    var langPref: String = "DE" { didSet { preferenceChanged(.langPref, oldValue != langPref) } }
    var hosterPref: String = "VOE" { didSet { preferenceChanged(.hosterPref, oldValue != hosterPref) } }
    var resumeEnabled: Bool = true { didSet { preferenceChanged(.resumeEnabled, oldValue != resumeEnabled) } }
    /// Bevorzugte Bildhöhe als Zeichenkette: „auto", „1080", „720", „480".
    ///
    /// Eine Höhe und keine Bitrate, weil die Oberfläche Höhen nennt und jede
    /// Master-Playlist sie mitliefert. „auto" heißt: der Spieler entscheidet.
    ///
    /// Erzwingen lässt sich das nur, wo der Hoster überhaupt mehrere Spuren
    /// anbietet — eine einzelne MP4-Datei hat keine Stufen, und Nori tut dann
    /// auch nicht so. Die Auswahl ist deshalb ein *Wunsch*: der Spieler nimmt
    /// die höchste angebotene Stufe, die nicht darüber liegt.
    var preferredQuality: String = "auto" { didSet { preferenceChanged(.preferredQuality, oldValue != preferredQuality) } }
    var autoplayNext: Bool = true { didSet { preferenceChanged(.autoplayNext, oldValue != autoplayNext) } }
    var playbackSpeed: Float = 1.0 { didSet { preferenceChanged(.playbackSpeed, oldValue != playbackSpeed) } }
    var provider: CatalogProvider = .aniworld { didSet { preferenceChanged(.provider, oldValue != provider) } }
    /// Was die Bibliothek zeigt. Vorgabe „Alle": beide Quellen in einer
    /// Liste. `provider` bleibt daneben bestehen und entscheidet, welche
    /// Seite ein Titel ohne eigene Quellangabe öffnet.
    var scope: LibraryScope = .all { didSet { preferenceChanged(.scope, oldValue != scope) } }
    /// Wann zuletzt mit einem Fremdstand abgeglichen wurde. Ohne eingerichteten
    /// Anbieter bleibt der Wert leer.
    var syncLastRun: Double?

    // MARK: - Revisionen

    // Woran eine Ansicht erkennt, dass sie neu rechnen muss.
    //
    // Vorher standen dort Anzahlen — `favorites.count`, `progress.count`. Eine
    // Anzahl bleibt aber gleich, wenn ein Titel entfernt und ein anderer
    // gemerkt wird, und sie ändert sich nicht, wenn eine angefangene Folge zu
    // Ende gesehen wird. Die Merkliste und „Weiterschauen" standen dann
    // veraltet da, bis zufällig ein Eintrag dazukam.
    //
    // Eine Revision zählt nur hoch. Sie zu lesen kostet nichts, und eine
    // Ansicht, die nur sie liest, zeichnet nicht bei jeder anderen Änderung
    // des Stores neu.

    /// Merkliste: gemerkt, entfernt, zurückgelegt, übernommen.
    private(set) var favoritesRevision = 0
    /// Verlauf: geöffnet, entfernt, gelöscht, übernommen.
    private(set) var recentsRevision = 0
    /// **Jede** Änderung am Fortschritt — auch der Fünf-Sekunden-Takt des
    /// Players. Für Ansichten, die die laufende Position zeigen.
    private(set) var progressRevision = 0
    /// Änderungen am Fortschritt, nach denen Listen neu gerechnet gehören: eine
    /// neue oder wieder aufgenommene Folge, eine abgeschlossene, eine andere
    /// Sprache, Löschen, ein übernommener Fremdstand — und das Ende einer
    /// Wiedergabe (`flush()`). **Nicht** der laufende Takt: sonst rechnete die
    /// Startseite hinter dem Player alle fünf Sekunden neu.
    private(set) var watchRevision = 0

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

    /// Zufällige Kennung dieser Installation, als UUID.
    ///
    /// Sie steht in jeder abgelegten Datei und entscheidet bei gleichen
    /// Zeitstempeln, welcher Wert gewinnt — sonst hinge das Ergebnis davon ab,
    /// in welcher Reihenfolge Drive die Dateien herausgibt.
    ///
    /// Bewusst aus nichts abgeleitet: kein Gerätename, keine Seriennummer,
    /// keine Werbekennung. Wer die Bibliothek in die Hand bekommt, soll daraus
    /// nicht ablesen können, wem sie gehört.
    private(set) var deviceId: String = ""

    /// Wann Verlauf beziehungsweise Fortschritt zuletzt vollständig gelöscht
    /// wurden. Ohne diese beiden Marken brächte das nächste Gerät mit altem
    /// Stand alles zurück, was gerade gelöscht wurde.
    private(set) var historyClearedAt: Double = 0
    private(set) var progressClearedAt: Double = 0
    private var preferenceStamps: [String: Double] = [:]
    private var favoriteMarks: [String: FavoriteMark] = [:]
    private var recentsRemoved: [String: Double] = [:]

    private let url: URL
    private var isLoading = false
    private var modifiedAt: Double = 0

    /// Der Schlüssel der zuletzt gesicherten Folge. Nur wer **dieselbe** Folge
    /// erneut sichert, ist ein Takt; die erste Sicherung einer Wiedergabe
    /// ändert „Weiterschauen" und zählt.
    @ObservationIgnored private var lastProgressKey: String?
    /// Seit der letzten abgeschlossenen Änderung gab es Takte.
    @ObservationIgnored private var pendingProgressTick = false
    /// Das geplante Schreiben nach einem Takt.
    @ObservationIgnored private var deferredWrite: DispatchWorkItem?
    @ObservationIgnored private let writeDelay: TimeInterval

    /// Was der Abgleich hochladen soll, sobald er darf.
    ///
    /// Der Zeitplan liegt in `LibrarySyncEngine`; der Store sagt nur Bescheid.
    /// Ohne das müsste entweder jede Änderung sofort ins Netz — bei laufender
    /// Wiedergabe im Sekundentakt — oder der Abgleich müsste raten.
    var onChange: (@Sendable () -> Void)?

    /// `directory` nur für Tests.
    ///
    /// Ohne das müsste ein Test entweder in die echte Bibliothek des Benutzers
    /// schreiben oder die Persistenz ungeprüft lassen — und genau dort liegen
    /// Merkliste, Verlauf und Fortschritt. Die App ruft weiterhin
    /// `LibraryStore()` und landet im Anwendungsunterstützungsordner.
    /// `deferredWriteDelay` ebenso — ein Test soll nicht zehn Sekunden warten.
    init(directory: URL? = nil, deferredWriteDelay: TimeInterval = LibraryStore.deferredWriteDelay) {
        writeDelay = deferredWriteDelay
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

    /// Jetzt, in Millisekunden seit 1970 — dieselbe Einheit wie überall sonst
    /// in der Bibliothek.
    private var now: Double { Date().timeIntervalSince1970 * 1000 }

    /// Den Änderungszeitpunkt einer Einstellung festhalten.
    ///
    /// Während des Ladens nicht: `apply` setzt dieselben Eigenschaften, und
    /// jeder `didSet` schlüge sonst als frische Änderung durch. Ein gerade
    /// eingelesener Fremdwert hätte damit immer den jüngsten Zeitstempel und
    /// gewänne jeden künftigen Vergleich.
    private func stamp(_ preference: SyncPreference) {
        guard !isLoading else { return }
        preferenceStamps[preference.rawValue] = now
    }

    private func preferenceChanged(_ preference: SyncPreference, _ changed: Bool) {
        guard changed else { return }
        stamp(preference)
        persist()
    }

    func isFavorite(_ slug: String) -> Bool { favorites.contains(slug) }

    func toggleFavorite(_ slug: String, title: String? = nil) {
        if favorites.contains(slug) {
            _ = removeFavorite(slug)
        } else {
            let stamp = now
            favorites.insert(slug, at: 0)
            favoriteSource[slug] = provider
            favoriteAddedAt[slug] = stamp
            favoriteMarks[favoriteKey(slug: slug, provider: provider)] =
                FavoriteMark(isFavorite: true, updatedAt: stamp, addedAt: stamp)
            if let title { titles[slug] = title }
            favoritesRevision &+= 1
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
        let source = favoriteSource[slug] ?? provider
        favorites.remove(at: index)
        favoriteSource.removeValue(forKey: slug)
        favoriteAddedAt.removeValue(forKey: slug)
        // Der Grabstein. Ohne ihn wäre „entfernt" nur die Abwesenheit eines
        // Eintrags, und jedes Gerät mit älterem Stand legte ihn wieder hin.
        favoriteMarks[favoriteKey(slug: slug, provider: source)] =
            FavoriteMark(isFavorite: false, updatedAt: now, addedAt: snapshot.addedAt)
        favoritesRevision &+= 1
        persist()
        return snapshot
    }

    /// Einen entfernten Eintrag zurücklegen — an dieselbe Stelle, mit
    /// demselben Zeitpunkt.
    func restoreFavorite(_ snapshot: FavoriteSnapshot) {
        guard !favorites.contains(snapshot.slug) else { return }
        favorites.insert(snapshot.slug, at: min(snapshot.index, favorites.count))
        if let source = snapshot.source { favoriteSource[snapshot.slug] = source }
        let addedAt = snapshot.addedAt ?? now
        favoriteAddedAt[snapshot.slug] = addedAt
        // `updatedAt` ist jetzt, `addedAt` bleibt der alte: die Rücknahme ist
        // frisch und schlägt den Grabstein, der Platz in der Liste nicht.
        favoriteMarks[favoriteKey(slug: snapshot.slug, provider: snapshot.source ?? provider)] =
            FavoriteMark(isFavorite: true, updatedAt: now, addedAt: addedAt)
        if let title = snapshot.title { titles[snapshot.slug] = title }
        favoritesRevision &+= 1
        persist()
    }

    func remember(slug: String, title: String, provider: CatalogProvider? = nil) {
        let source = provider ?? self.provider
        titles[slug] = title
        recents.removeAll { $0.slug == slug }
        recents.insert(RecentItem(slug: slug, title: title, viewedAt: now, provider: source), at: 0)
        if recents.count > 100 { recents = Array(recents.prefix(100)) }
        // Wer den Titel erneut öffnet, hebt sein früheres „aus dem Verlauf
        // nehmen" auf. Bliebe der Grabstein stehen, verschwände der Eintrag
        // beim nächsten Abgleich wieder.
        recentsRemoved.removeValue(forKey: recentKey(slug: slug, provider: source))
        recentsRevision &+= 1
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

    /// Den Stand einer Folge sichern.
    ///
    /// Ist es dieselbe Folge wie beim letzten Aufruf, nur weiter, ist das ein
    /// **Takt** der laufenden Wiedergabe: der Speicher ist sofort aktuell,
    /// geschrieben wird gebündelt (`deferredWriteDelay`), und `watchRevision`
    /// bleibt stehen. Alles andere — eine neue Folge, eine abgeschlossene, eine
    /// andere Sprache — wird sofort geschrieben und zählt.
    func upsert(_ item: WatchProgress) {
        let tick = store(item)
        if tick {
            pendingProgressTick = true
            persist(deferWrite: true)
        } else {
            pendingProgressTick = false
            watchRevision &+= 1
            persist()
        }
    }

    /// Mehrere Folgen auf einmal — „Staffel als gesehen markieren".
    ///
    /// Ein Schreibvorgang und eine Meldung an den Abgleich statt einer je
    /// Folge: bei vierundzwanzig Folgen waren das vierundzwanzig vollständige
    /// Schreibvorgänge der Bibliothek hintereinander.
    func upsert(contentsOf items: [WatchProgress]) {
        guard !items.isEmpty else { return }
        for item in items { _ = store(item) }
        lastProgressKey = nil
        pendingProgressTick = false
        watchRevision &+= 1
        persist()
    }

    /// Einen Eintrag ablegen. Gibt zurück, ob es nur ein Takt war.
    private func store(_ item: WatchProgress) -> Bool {
        let path = normalizeEpisodePath(item.episodePath)
        var next = item
        next.episodePath = path
        next.provider = next.provider ?? providerFromPath(path)
        if next.durationSec >= 20, next.positionSec >= next.durationSec * 0.9 { next.completed = true }
        let key = progressKey(path: path, provider: next.provider)
        let previous = progress[key]
        progress[key] = next
        let removed = removeLegacyDuplicates(for: next)
        progressRevision &+= 1

        let tick = removed == 0
            && key == lastProgressKey
            && previous != nil
            && isEpisodeComplete(previous) == isEpisodeComplete(next)
            && previous?.lang == next.lang
        lastProgressKey = key
        return tick
    }

    /// Was noch nicht auf der Platte steht, jetzt schreiben.
    ///
    /// Aufzurufen, wenn eine Wiedergabe endet oder anhält und wenn die App in
    /// den Hintergrund geht. Takte seit der letzten abgeschlossenen Änderung
    /// gelten danach als abgeschlossen: Listen wie „Weiterschauen" sehen den
    /// neuen Stand über `watchRevision`.
    func flush() {
        if deferredWrite != nil { writeNow() }
        if pendingProgressTick {
            pendingProgressTick = false
            watchRevision &+= 1
        }
        lastProgressKey = nil
    }

    /// Je Serie der jüngste **angefasste** Eintrag, sofern er nicht durch ist.
    ///
    /// „Angefasst" heißt Position > 0 oder abgeschlossen — dieselbe Grenze wie
    /// in `watchSummary`. Bis hierher zählte jeder Eintrag, auch der leere, den
    /// schon das bloße Öffnen einer Folge anlegt. Das hatte zwei Folgen: eine
    /// nur angetippte Folge stand in „Weiterschauen", und „Aus Weiterschauen
    /// entfernen" konnte gar nicht wirken — der zurückgesetzte Eintrag wäre
    /// mit Position 0 sofort wieder dagewesen.
    ///
    /// Die halb gesehene Folge bleibt trotzdem stehen, wenn danach eine andere
    /// nur geöffnet wurde: der leere Eintrag zählt nicht mehr mit, also ist der
    /// jüngste angefasste weiterhin der halb gesehene.
    func continueWatching() -> [WatchProgress] {
        var latest: [String: WatchProgress] = [:]
        for item in progress.values where item.positionSec > 0 || item.completed == true {
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

    func clearHistory() {
        recents = []
        historyClearedAt = now
        // Einzelne Grabsteine sind damit erledigt — die Marke erschlägt sie
        // alle, und die Datei muss sie nicht weiter mitschleppen.
        recentsRemoved = [:]
        recentsRevision &+= 1
        persist()
    }

    /// Einen einzelnen Verlaufseintrag entfernen.
    ///
    /// Der Fortschritt bleibt stehen: „aus dem Verlauf nehmen" heißt, den
    /// Eintrag aus der Liste der zuletzt angesehenen Titel zu streichen, nicht
    /// zu vergessen, wie weit die Folge lief. Wer das will, löscht den
    /// Fortschritt — dafür gibt es `clearProgress`.
    func forgetRecent(slug: String) {
        let before = recents.count
        let sources = Set(recents.filter { $0.slug == slug }.map { $0.provider ?? provider })
        recents.removeAll { $0.slug == slug }
        guard recents.count != before else { return }
        for source in sources { recentsRemoved[recentKey(slug: slug, provider: source)] = now }
        recentsRevision &+= 1
        persist()
    }

    func clearProgress() {
        progress = [:]
        progressClearedAt = now
        lastProgressKey = nil
        pendingProgressTick = false
        progressRevision &+= 1
        watchRevision &+= 1
        persist()
    }

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
               let bag = try? JSONDecoder().decode(LibraryData.self, from: data),
               let remote = bag.modifiedAt, remote > modifiedAt {
                apply(bag)
                modifiedAt = remote
                writeNow()
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
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(LibraryData.self, from: data) else {
            // Erster Start. Die Gerätekennung wird sofort festgeschrieben:
            // entstünde sie erst bei der ersten Änderung, hätte jeder Start bis
            // dahin eine andere, und in Drive läge für dasselbe Gerät bei jedem
            // Lauf eine weitere Datei.
            deviceId = UUID().uuidString
            preferenceStamps = SyncPreference.allCases.reduce(into: [:]) { $0[$1.rawValue] = 0 }
            persist()
            return
        }
        apply(stored)
        modifiedAt = stored.modifiedAt ?? 0
        let issued = adoptSyncMeta(stored)
        let migrated = (stored.version ?? 1) < Self.schemaVersion
        if migrated || issued || progress.count != stored.progress.count { persist() }
    }

    /// Die Sync-Angaben aus einer geladenen Datei übernehmen — und das
    /// ergänzen, was eine ältere Datei nicht haben kann.
    ///
    /// Das ist die Migration v5 → v6, und sie erfindet nichts: die Merkliste
    /// wird zu lauter „gemerkt seit `favoriteAddedAt`", die Einstellungen
    /// bekommen den Änderungszeitpunkt der ganzen Datei. Beides ist die beste
    /// Auskunft, die in einem v5-Stand überhaupt steckt.
    ///
    /// Die Zeitstempel der Einstellungen werden dabei **festgeschrieben**.
    /// Ließe man sie leer und fiele beim Vergleich auf `modifiedAt` zurück,
    /// würde jede spätere Änderung an *einer* Einstellung alle anderen
    /// mit frischmachen — wer heute die Sprache umstellt, überschriebe damit
    /// den Hoster, den ein anderes Gerät gestern bewusst gewählt hat.
    /// Gibt zurück, ob eine neue Gerätekennung vergeben wurde — dann muss die
    /// Datei geschrieben werden, sonst bekäme der nächste Start wieder eine
    /// andere.
    @discardableResult
    private func adoptSyncMeta(_ stored: LibraryData) -> Bool {
        let meta = stored.sync
        let existing = meta?.deviceId.flatMap { $0.isEmpty ? nil : $0 }
        deviceId = existing ?? UUID().uuidString
        historyClearedAt = meta?.historyClearedAt ?? 0
        progressClearedAt = meta?.progressClearedAt ?? 0
        recentsRemoved = meta?.recentsRemoved ?? [:]

        if let stamps = meta?.preferences, !stamps.isEmpty {
            preferenceStamps = stamps.mapValues(\.updatedAt)
        } else {
            let anchor = stored.modifiedAt ?? 0
            preferenceStamps = SyncPreference.allCases.reduce(into: [:]) { $0[$1.rawValue] = anchor }
        }

        if let marks = meta?.favorites, !marks.isEmpty {
            favoriteMarks = marks
        } else {
            favoriteMarks = [:]
            for slug in favorites {
                let stamp = favoriteAddedAt[slug] ?? stored.modifiedAt ?? 0
                favoriteMarks[favoriteKey(slug: slug, provider: favoriteSource[slug] ?? provider)] =
                    FavoriteMark(isFavorite: true, updatedAt: stamp, addedAt: stamp)
            }
        }
        return existing == nil
    }

    private func apply(_ bag: LibraryData) {
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
        // Ein übernommener Stand kann alles geändert haben.
        lastProgressKey = nil
        pendingProgressTick = false
        favoritesRevision &+= 1
        recentsRevision &+= 1
        progressRevision &+= 1
        watchRevision &+= 1
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

    /// Ältere Einträge derselben Folge unter einem anderen Schlüssel entfernen.
    /// Gibt zurück, wie viele es waren.
    @discardableResult
    private func removeLegacyDuplicates(for item: WatchProgress) -> Int {
        let clean = normalizeEpisodePath(item.episodePath)
        let keep = progressKey(path: clean, provider: item.provider)
        let matching = progress.keys.filter { key in
            guard key != keep, let existing = progress[key] else { return false }
            return normalizeEpisodePath(existing.episodePath) == clean && (existing.provider ?? providerFromPath(existing.episodePath)) == item.provider
        }
        for key in matching { progress.removeValue(forKey: key) }
        return matching.count
    }

    /// Eine Änderung festhalten: Zeitstempel, Platte, Abgleich.
    ///
    /// `deferWrite` nur für Takte der Wiedergabe — siehe `deferredWriteDelay`.
    /// Alles andere wird sofort geschrieben; eine gemerkte Serie oder eine
    /// geänderte Einstellung soll einen Absturz eine Sekunde später überleben.
    private func persist(deferWrite: Bool = false) {
        guard !isLoading else { return }
        modifiedAt = now
        if deferWrite {
            scheduleDeferredWrite()
        } else {
            writeNow()
        }
        // Kein Hochladen von hier aus. Der Fortschritt wird während der
        // Wiedergabe regelmäßig gesichert, und eine Netzanfrage je Takt wäre
        // weder Drive noch dem Gerät zumutbar. Gemeldet wird nur, *dass* sich
        // etwas geändert hat; wann daraus ein Upload wird, entscheidet
        // `LibrarySyncEngine`.
        onChange?()
    }

    /// Einmal schreiben, nicht einmal je Takt: ein bereits geplantes Schreiben
    /// wird nicht verschoben, sonst schöbe jeder Takt es weiter hinaus.
    private func scheduleDeferredWrite() {
        guard deferredWrite == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.deferredWrite != nil else { return }
            self.writeNow()
        }
        deferredWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + writeDelay, execute: work)
    }

    private func writeNow() {
        deferredWrite?.cancel()
        deferredWrite = nil
        writeLocal(makeBag(modifiedAt: modifiedAt))
    }

    private func writeLocal(_ bag: LibraryData) {
        guard let data = try? JSONEncoder().encode(bag) else { return }
        // `.atomic` schreibt in eine Nebendatei und tauscht sie erst danach
        // ein. Ein Absturz mittendrin lässt damit den alten Stand stehen
        // statt eines halben JSON, das beim nächsten Start gar nicht lädt.
        try? data.write(to: url, options: .atomic)
    }

    private func makeBag(modifiedAt: Double) -> LibraryData {
        LibraryData(version: Self.schemaVersion, modifiedAt: modifiedAt, favorites: favorites, recents: recents, titles: titles, progress: progress, langPref: langPref, hosterPref: hosterPref, resumeEnabled: resumeEnabled, autoplayNext: autoplayNext, playbackSpeed: playbackSpeed, preferredQuality: preferredQuality, provider: provider.rawValue, scope: scope.rawValue, favoriteSource: favoriteSource.mapValues(\.rawValue), favoriteAddedAt: favoriteAddedAt, sync: makeSyncMeta(generatedAt: modifiedAt))
    }

    private func makeSyncMeta(generatedAt: Double) -> SyncMeta {
        SyncMeta(
            formatVersion: librarySyncFormatVersion,
            deviceId: deviceId,
            platform: LibraryStore.platformName,
            appVersion: appVersion,
            generatedAt: generatedAt,
            historyClearedAt: historyClearedAt,
            progressClearedAt: progressClearedAt,
            preferences: preferenceStamps.mapValues(SyncStamp.init(updatedAt:)),
            favorites: favoriteMarks,
            recentsRemoved: recentsRemoved
        )
    }

    /// Der lokale Stand als Datensatz — die Eingabe für `mergeLibrarySnapshots`
    /// und zugleich das, was hochgeladen wird.
    func snapshot() -> LibraryData { makeBag(modifiedAt: modifiedAt) }

    /// Einen zusammengeführten Stand übernehmen.
    ///
    /// Der Gegenstück zu `snapshot()`. Die eigene Gerätekennung bleibt: sie
    /// gehört zur Installation, nicht zu den Daten, und ein zusammengeführter
    /// Stand trägt gar keine.
    ///
    /// Geschrieben wird sofort und atomar. Ein Absturz direkt danach darf
    /// nicht dazu führen, dass der Abgleich gelaufen ist, das Ergebnis aber
    /// nur im Arbeitsspeicher stand.
    func applyMerged(_ merged: LibraryData) {
        var next = merged
        next.sync?.deviceId = deviceId
        apply(next)
        historyClearedAt = next.sync?.historyClearedAt ?? historyClearedAt
        progressClearedAt = next.sync?.progressClearedAt ?? progressClearedAt
        recentsRemoved = next.sync?.recentsRemoved ?? recentsRemoved
        if let stamps = next.sync?.preferences { preferenceStamps = stamps.mapValues(\.updatedAt) }
        if let marks = next.sync?.favorites { favoriteMarks = marks }
        modifiedAt = max(modifiedAt, next.modifiedAt ?? 0)
        writeNow()
    }

    /// Version der laufenden App, für die Metadaten im abgelegten Stand.
    /// Wird von der App gesetzt; der Kern kennt kein Bundle.
    var appVersion: String?

    static var platformName: String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #elseif os(Android)
        return "android"
        #else
        return "unknown"
        #endif
    }
}
