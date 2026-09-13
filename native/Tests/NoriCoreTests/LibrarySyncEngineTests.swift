import XCTest
@testable import NoriCore

// Der Ablauf eines Abgleichs — ohne Google, ohne Netz.
//
// Ablage und Transport sind ausgetauscht. Das ist kein Kompromiss: was hier
// geprüft wird, sind Reihenfolge, Wiederholung und Fehlerbehandlung, und das
// sind Entscheidungen im Nori-Code und keine Eigenschaften von Drive. Ein Test
// gegen das echte Google prüfte vor allem, ob gerade Netz da ist.

/// Eine Ablage im Arbeitsspeicher. Verhält sich wie der `appDataFolder`: viele
/// Dateien, jede einem Gerät zugeordnet, jede mit einem Änderungsstempel.
private final class FakeSnapshotStore: LibrarySnapshotStore, @unchecked Sendable {
    let name = "Testablage"
    /// Eigene Kennungen je Ablage — sonst fiele eine verwechselte Kennung nicht auf.
    var idPrefix = "file"
    /// Im Papierkorb: noch vorhanden, aber von der Suche (`trashed=false`) nicht gefunden.
    var trashed: Set<String> = []
    var files: [String: (deviceId: String, modifiedTime: Int, data: Data)] = [:]
    var listError: Error?
    var uploadError: Error?
    var downloadError: Error?
    private(set) var uploads = 0
    private(set) var downloads = 0
    private(set) var lists = 0
    private var clock = 0
    private var nextId = 0

    func list() async throws -> [RemoteSnapshotRef] {
        lists += 1
        if let listError { throw listError }
        return files.filter { !trashed.contains($0.key) }.map { id, file in
            RemoteSnapshotRef(id: id, deviceId: file.deviceId, modifiedTime: "\(file.modifiedTime)", size: file.data.count)
        }
        .sorted { $0.id < $1.id }
    }

    func download(_ ref: RemoteSnapshotRef) async throws -> Data {
        if let downloadError { throw downloadError }
        downloads += 1
        guard let file = files[ref.id] else { throw GoogleDriveError.notFound }
        return file.data
    }

    func upload(_ data: Data, deviceId: String, fileId: String?) async throws -> RemoteSnapshotRef {
        if let uploadError { throw uploadError }
        uploads += 1
        clock += 1
        if let fileId {
            guard files[fileId] != nil else { throw GoogleDriveError.notFound }
            files[fileId] = (deviceId, clock, data)
            return RemoteSnapshotRef(id: fileId, deviceId: deviceId, modifiedTime: "\(clock)", size: data.count)
        }
        nextId += 1
        let id = "\(idPrefix)-\(nextId)"
        files[id] = (deviceId, clock, data)
        return RemoteSnapshotRef(id: id, deviceId: deviceId, modifiedTime: "\(clock)", size: data.count)
    }

    /// Eine Datei von Hand einschleusen — für „das andere Gerät war schon da".
    func seed(id: String, deviceId: String, data: Data) {
        clock += 1
        files[id] = (deviceId, clock, data)
    }
}

private final class FakeBookkeeping: SyncBookkeeping {
    var values: [String: String] = [:]
    func syncValue(forKey key: String) -> String? { values[key] }
    func setSyncValue(_ value: String?, forKey key: String) { values[key] = value }
}

@MainActor
final class LibrarySyncEngineTests: XCTestCase {

    private var folders: [URL] = []

    override func tearDown() {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
        super.tearDown()
    }

    private func makeStore() -> LibraryStore {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-sync-\(UUID().uuidString)", isDirectory: true)
        folders.append(folder)
        return LibraryStore(directory: folder)
    }

    private func engine(_ store: LibraryStore, _ remote: FakeSnapshotStore, _ books: FakeBookkeeping) -> LibrarySyncEngine {
        let engine = LibrarySyncEngine(store: store, bookkeeping: books)
        engine.connect(to: remote, startSync: false)
        return engine
    }

    private func snapshot(_ data: LibraryData) -> Data {
        try! JSONEncoder().encode(data)
    }

    // MARK: - B: erstes Gerät

    /// Lokale Bibliothek, leere Cloud. Danach liegt dort genau eine Datei.
    func testFirstDeviceUploadsItsLibrary() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        let books = FakeBookkeeping()

        await engine(store, remote, books).run()

        XCTAssertEqual(remote.files.count, 1)
        let uploaded = try! JSONDecoder().decode(LibraryData.self, from: remote.files.values.first!.data)
        XCTAssertEqual(uploaded.favorites, ["one-piece"])
        XCTAssertEqual(uploaded.sync?.deviceId, store.deviceId)
        XCTAssertNotNil(books.values["nori.sync.driveFileId"])
    }

    /// Und beim zweiten Lauf keine zweite Datei — `update` statt `create`.
    func testSecondRunUpdatesInsteadOfCreating() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        let sync = engine(store, remote, FakeBookkeeping())

        await sync.run()
        store.toggleFavorite("naruto", title: "Naruto")
        await sync.run()

        XCTAssertEqual(remote.files.count, 1, "Bei jedem Abgleich eine neue Datei — der Ordner liefe voll.")
        XCTAssertEqual(remote.uploads, 2)
    }

    // MARK: - C: zweites Gerät

    /// Frische Installation, bestehende Cloud. Der Fremdstand wird übernommen,
    /// und der leere lokale löscht ihn nicht.
    func testFreshDeviceAdoptsRemoteLibrary() async {
        let quelle = makeStore()
        quelle.toggleFavorite("one-piece", title: "One Piece")
        quelle.remember(slug: "one-piece", title: "One Piece")
        quelle.upsert(WatchProgress(
            slug: "one-piece", title: "One Piece", season: "1", episode: 3,
            episodePath: "/anime/stream/one-piece/staffel-1/episode-3",
            germanTitle: "", englishTitle: "", positionSec: 640, durationSec: 1400,
            updatedAt: Date().timeIntervalSince1970 * 1000, provider: .aniworld))

        let remote = FakeSnapshotStore()
        remote.seed(id: "fremd", deviceId: quelle.deviceId, data: snapshot(quelle.snapshot()))

        let neu = makeStore()
        XCTAssertTrue(neu.favorites.isEmpty)
        await engine(neu, remote, FakeBookkeeping()).run()

        XCTAssertEqual(neu.favorites, ["one-piece"])
        XCTAssertEqual(neu.recents.map(\.slug), ["one-piece"])
        XCTAssertEqual(neu.progress.count, 1)
        XCTAssertEqual(neu.titles["one-piece"], "One Piece")

        // Und der Stand des anderen Geräts liegt unverändert daneben.
        let fremd = try! JSONDecoder().decode(LibraryData.self, from: remote.files["fremd"]!.data)
        XCTAssertEqual(fremd.favorites, ["one-piece"])
    }

    // MARK: - D/K: zwei Geräte, zwei Änderungen

    func testTwoDevicesKeepBothChanges() async {
        let remote = FakeSnapshotStore()
        let a = makeStore(), b = makeStore()
        let syncA = engine(a, remote, FakeBookkeeping())
        let syncB = engine(b, remote, FakeBookkeeping())

        a.toggleFavorite("one-piece", title: "One Piece")
        await syncA.run()
        await syncB.run()   // B holt sich den Stand

        b.upsert(WatchProgress(
            slug: "naruto", title: "Naruto", season: "1", episode: 2,
            episodePath: "/anime/stream/naruto/staffel-1/episode-2",
            germanTitle: "", englishTitle: "", positionSec: 900, durationSec: 1400,
            updatedAt: Date().timeIntervalSince1970 * 1000, provider: .aniworld))
        await syncB.run()
        await syncA.run()

        XCTAssertEqual(a.favorites, ["one-piece"])
        XCTAssertEqual(a.progress.count, 1, "A hat den Fortschritt von B nicht bekommen")
        XCTAssertEqual(b.favorites, ["one-piece"])
    }

    /// E über den ganzen Weg: entfernt bleibt entfernt, auch wenn das andere
    /// Gerät noch den alten Stand hat.
    func testRemovalSurvivesAStaleDevice() async {
        let remote = FakeSnapshotStore()
        let a = makeStore(), b = makeStore()
        let syncA = engine(a, remote, FakeBookkeeping())
        let syncB = engine(b, remote, FakeBookkeeping())

        a.toggleFavorite("one-piece", title: "One Piece")
        await syncA.run()
        await syncB.run()
        XCTAssertEqual(b.favorites, ["one-piece"])

        a.toggleFavorite("one-piece")          // entfernen
        await syncA.run()
        await syncB.run()

        XCTAssertEqual(b.favorites, [], "Der Grabstein hat nicht gehalten")
        await syncA.run()
        XCTAssertEqual(a.favorites, [], "B hat den Titel wieder hingelegt")
    }

    // MARK: - G/H über den ganzen Weg

    func testClearedHistoryDoesNotComeBack() async {
        let remote = FakeSnapshotStore()
        let a = makeStore(), b = makeStore()
        let syncA = engine(a, remote, FakeBookkeeping())
        let syncB = engine(b, remote, FakeBookkeeping())

        a.remember(slug: "one-piece", title: "One Piece")
        await syncA.run()
        await syncB.run()
        XCTAssertEqual(b.recents.count, 1)

        a.clearHistory()
        await syncA.run()
        await syncB.run()

        XCTAssertEqual(b.recents, [], "Der gelöschte Verlauf ist zurückgekommen")
    }

    func testClearedProgressDoesNotComeBack() async {
        let remote = FakeSnapshotStore()
        let a = makeStore(), b = makeStore()
        let syncA = engine(a, remote, FakeBookkeeping())
        let syncB = engine(b, remote, FakeBookkeeping())

        a.upsert(WatchProgress(
            slug: "naruto", title: "Naruto", season: "1", episode: 2,
            episodePath: "/anime/stream/naruto/staffel-1/episode-2",
            germanTitle: "", englishTitle: "", positionSec: 900, durationSec: 1400,
            updatedAt: Date().timeIntervalSince1970 * 1000, provider: .aniworld))
        await syncA.run()
        await syncB.run()
        XCTAssertEqual(b.progress.count, 1)

        a.clearProgress()
        await syncA.run()
        await syncB.run()

        XCTAssertEqual(b.progress.count, 0, "Der gelöschte Fortschritt ist zurückgekommen")
    }

    // MARK: - J: offline

    /// Kein Netz heißt: nichts geht verloren, und es wird später erneut
    /// versucht. Ausdrücklich **nicht**: die lokale Bibliothek anfassen.
    func testOfflineKeepsEverythingLocal() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        remote.listError = GoogleDriveError.transport("Kein Netz")
        let sync = engine(store, remote, FakeBookkeeping())

        await sync.run()

        XCTAssertEqual(sync.status, .offline)
        XCTAssertTrue(sync.hasPendingChanges || store.favorites == ["one-piece"])
        XCTAssertEqual(store.favorites, ["one-piece"], "Ein Netzfehler hat die Bibliothek angefasst")

        // Netz zurück: derselbe Abgleich läuft durch.
        remote.listError = nil
        await sync.run()
        XCTAssertEqual(sync.status, .idle)
        XCTAssertEqual(remote.files.count, 1)
    }

    // MARK: - K: die Berechtigung gilt nicht mehr

    /// Eine abgelaufene Berechtigung ist ein eigener Zustand und kein Fehler.
    ///
    /// Vorher stand hier `.error` mit dem Satz „Die Verbindung zu Google ist
    /// abgelaufen. Bitte neu verbinden." — ein Fehlertext, aus dem die
    /// Oberfläche keine Handlung ableiten konnte. Jetzt kann sie „Erneut
    /// anmelden" anbieten.
    func testExpiredAuthorizationAsksForANewSignIn() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        remote.listError = GoogleDriveError.notAuthorized
        let sync = engine(store, remote, FakeBookkeeping())

        await sync.run()

        XCTAssertEqual(sync.status, .needsReauthorization)
        XCTAssertNil(sync.lastError, "Ein technischer Text, wo eine Handlung gehört")
        XCTAssertEqual(store.favorites, ["one-piece"], "Die Bibliothek wurde angefasst")
    }

    /// Und ebenso, wenn Google gar keine dauerhafte Berechtigung erteilt hat.
    func testAMissingRefreshTokenAsksForANewSignIn() async {
        let store = makeStore()
        let remote = FakeSnapshotStore()
        remote.listError = GoogleOAuthError.noRefreshToken
        let sync = engine(store, remote, FakeBookkeeping())

        await sync.run()

        XCTAssertEqual(sync.status, .needsReauthorization)
        XCTAssertNil(sync.lastError)
    }

    // MARK: - L: kaputter Fremdstand

    /// Eine unlesbare Fremddatei nimmt nur sich selbst mit.
    func testCorruptRemoteSnapshotIsSkipped() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")

        let gut = makeStore()
        gut.toggleFavorite("naruto", title: "Naruto")

        let remote = FakeSnapshotStore()
        remote.seed(id: "kaputt", deviceId: "xxx", data: Data("{ das ist kein JSON".utf8))
        remote.seed(id: "gut", deviceId: gut.deviceId, data: snapshot(gut.snapshot()))

        let sync = engine(store, remote, FakeBookkeeping())
        await sync.run()

        XCTAssertEqual(sync.status, .idle, "Ein kaputter Fremdstand hat den Abgleich abgebrochen")
        XCTAssertNotNil(sync.lastWarning)
        XCTAssertEqual(Set(store.favorites), ["one-piece", "naruto"], "Der gültige Fremdstand fehlt")
    }

    // MARK: - M: neuere Schemaversion

    /// Eine ältere App darf einen neueren Stand **nicht** überschreiben.
    func testNewerRemoteSchemaBlocksUpload() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")

        var zukunft = store.snapshot()
        zukunft.version = LibraryStore.schemaVersion + 1
        let remote = FakeSnapshotStore()
        remote.seed(id: "neuer", deviceId: "zzz", data: snapshot(zukunft))

        let sync = engine(store, remote, FakeBookkeeping())
        await sync.run()

        XCTAssertEqual(sync.status, .unsupportedRemoteVersion)
        XCTAssertEqual(remote.uploads, 0, "Eine ältere App hat einen neueren Stand überschrieben")
        XCTAssertEqual(store.favorites, ["one-piece"], "Die lokale Bibliothek ist trotzdem benutzbar")
    }

    // MARK: - P/Q/R

    /// Die Gerätekennung überlebt einen Neustart. Täte sie das nicht, läge in
    /// Drive nach einer Woche für dasselbe Gerät ein Dutzend Dateien.
    func testDeviceIdSurvivesRestart() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-restart-\(UUID().uuidString)", isDirectory: true)
        folders.append(folder)

        let erst = LibraryStore(directory: folder)
        let kennung = erst.deviceId
        XCTAssertFalse(kennung.isEmpty)
        erst.toggleFavorite("one-piece", title: "One Piece")

        let danach = LibraryStore(directory: folder)
        XCTAssertEqual(danach.deviceId, kennung)
        XCTAssertEqual(danach.favorites, ["one-piece"])
    }

    /// Trennen löscht Tokens und Zeitplan — nicht die Bibliothek und nicht die
    /// Daten der anderen Geräte.
    func testDisconnectKeepsTheLibrary() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        let sync = engine(store, remote, FakeBookkeeping())
        await sync.run()

        sync.disconnect()

        XCTAssertEqual(sync.status, .disconnected)
        XCTAssertFalse(sync.isConnected)
        XCTAssertEqual(store.favorites, ["one-piece"])
        XCTAssertEqual(remote.files.count, 1, "Trennen hat die Drive-Datei gelöscht")
    }

    /// Erneut verbinden führt zusammen, statt zu überschreiben.
    func testReconnectMergesAgain() async {
        let remote = FakeSnapshotStore()
        let store = makeStore()
        let books = FakeBookkeeping()
        let sync = engine(store, remote, books)

        store.toggleFavorite("one-piece", title: "One Piece")
        await sync.run()
        sync.disconnect()

        // In der Zwischenzeit hat ein anderes Gerät etwas hinzugefügt.
        let anderes = makeStore()
        anderes.toggleFavorite("naruto", title: "Naruto")
        remote.seed(id: "anderes", deviceId: anderes.deviceId, data: snapshot(anderes.snapshot()))

        sync.connect(to: remote, startSync: false)
        await sync.run()

        XCTAssertEqual(Set(store.favorites), ["one-piece", "naruto"])
    }

    /// Ein Kontowechsel ist ein anderer Sync-Raum: die gemerkte Dateikennung
    /// zeigt dort auf nichts.
    func testAccountSwitchForgetsTheFileId() async {
        let store = makeStore()
        let remote = FakeSnapshotStore()
        let books = FakeBookkeeping()
        let sync = LibrarySyncEngine(store: store, bookkeeping: books)

        sync.connect(to: remote, accountId: "konto-a", startSync: false)
        await sync.run()
        let ersteDatei = books.values["nori.sync.driveFileId"]
        XCTAssertNotNil(ersteDatei)

        sync.connect(to: remote, accountId: "konto-b", startSync: false)
        XCTAssertNil(books.values["nori.sync.driveFileId"] ?? nil,
                     "Die Dateikennung des alten Kontos wurde ins neue übernommen")
    }

    /// Zeigt die gemerkte Dateikennung ins Leere, wird eine neue Datei angelegt
    /// — statt den Abgleich scheitern zu lassen.
    func testStaleFileIdIsReplaced() async {
        let store = makeStore()
        let remote = FakeSnapshotStore()
        let books = FakeBookkeeping()
        books.values["nori.sync.driveFileId"] = "gibt-es-nicht"

        await engine(store, remote, books).run()

        XCTAssertEqual(remote.files.count, 1)
        XCTAssertNotEqual(books.values["nori.sync.driveFileId"], "gibt-es-nicht")
    }

    /// Unveränderte Fremddateien werden nicht erneut geholt.
    func testUnchangedSnapshotsAreNotDownloadedTwice() async {
        let store = makeStore()
        let anderes = makeStore()
        anderes.toggleFavorite("naruto", title: "Naruto")
        let remote = FakeSnapshotStore()
        remote.seed(id: "anderes", deviceId: anderes.deviceId, data: snapshot(anderes.snapshot()))

        let sync = engine(store, remote, FakeBookkeeping())
        await sync.run()
        let nachErstem = remote.downloads
        await sync.run()

        XCTAssertEqual(remote.downloads, nachErstem, "Ein unveränderter Fremdstand wurde erneut geladen")
    }

    /// Ein Abgleich, der nichts geändert hat, schreibt auch nichts.
    ///
    /// Vorher lud jedes Gerät im Vordergrund alle 30 Sekunden seine
    /// unveränderte Datei hoch. Jeder Upload setzt einen neuen
    /// Änderungsstempel, und jedes andere Gerät holte die Datei danach erneut —
    /// für nichts, gegen Googles Kontingent.
    func testAnUnchangedLibraryIsNotUploadedAgain() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        let sync = engine(store, remote, FakeBookkeeping())

        await sync.run()
        await sync.run()
        await sync.run()

        XCTAssertEqual(remote.uploads, 1, "Ein unveränderter Stand wurde erneut hochgeladen")
        XCTAssertEqual(remote.lists, 3, "Geholt werden muss trotzdem — sonst kämen fremde Änderungen nie an")
        XCTAssertEqual(sync.status, .idle)
        XCTAssertNotNil(sync.lastSuccessfulSync)

        // Eine echte Änderung wird selbstverständlich wieder geschrieben.
        store.toggleFavorite("naruto", title: "Naruto")
        await sync.run()
        XCTAssertEqual(remote.uploads, 2)
    }

    /// Hat ein anderes Gerät etwas geändert, entsteht ein neuer Stand — und der
    /// wird geschrieben, auch wenn lokal nichts passiert ist.
    func testAMergedRemoteChangeIsUploaded() async {
        let store = makeStore()
        let remote = FakeSnapshotStore()
        let sync = engine(store, remote, FakeBookkeeping())
        await sync.run()
        XCTAssertEqual(remote.uploads, 1)

        let anderes = makeStore()
        anderes.toggleFavorite("naruto", title: "Naruto")
        remote.seed(id: "anderes", deviceId: anderes.deviceId, data: snapshot(anderes.snapshot()))
        await sync.run()

        XCTAssertEqual(store.favorites, ["naruto"])
        XCTAssertEqual(remote.uploads, 2, "Der zusammengeführte Stand wurde nicht geschrieben")
    }

    /// Wurde die eigene Datei zwischendurch anderswo verändert oder gelöscht,
    /// wird wieder geschrieben — die Abkürzung gilt nur für einen Stand, der
    /// nachweislich unverändert in der Cloud liegt.
    func testAnOwnFileChangedElsewhereIsWrittenAgain() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        let books = FakeBookkeeping()
        let sync = engine(store, remote, books)
        await sync.run()

        let own = books.values["nori.sync.driveFileId"]!
        remote.files[own] = nil
        await sync.run()

        // Eine neue Datei statt gar keiner: der Stand liegt wieder in der Cloud.
        XCTAssertEqual(remote.files.count, 1, "Die gelöschte eigene Datei wurde nicht neu geschrieben")
        XCTAssertNotEqual(books.values["nori.sync.driveFileId"], own)
    }

    /// Nach vorn kommen gleicht nicht bei jedem Fensterwechsel ab.
    func testForegroundIsThrottledUnlessSomethingIsPending() async {
        final class Clock: @unchecked Sendable {
            var now: Double = 1_000_000
        }
        let clock = Clock()
        let store = makeStore()
        let remote = FakeSnapshotStore()
        let sync = LibrarySyncEngine(store: store, bookkeeping: FakeBookkeeping(), clock: { clock.now })
        sync.connect(to: remote, startSync: false)
        await sync.run()
        XCTAssertEqual(remote.lists, 1)

        clock.now += 5_000
        sync.syncOnForeground()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(remote.lists, 1, "Fünf Sekunden nach dem letzten Abgleich wurde erneut gefragt")

        clock.now += LibrarySyncEngine.foregroundPoll * 1000
        sync.syncOnForeground()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(remote.lists, 2)
    }

    /// In den Hintergrund ohne Änderung ist kein Anlass für eine Anfrage.
    func testBackgroundOnlySyncsPendingChanges() async {
        let store = makeStore()
        let remote = FakeSnapshotStore()
        let sync = engine(store, remote, FakeBookkeeping())
        await sync.run()

        sync.syncOnBackground()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(remote.lists, 1)

        store.toggleFavorite("naruto", title: "Naruto")
        sync.noteChange()
        sync.syncOnBackground()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(remote.lists, 2)
        XCTAssertEqual(remote.uploads, 2)
    }
}

// MARK: - Wiedererkennung der eigenen Datei

extension LibrarySyncEngineTests {

    /// Ohne gemerkte Kennung wird die eigene Datei am Gerätekennzeichen
    /// wiedererkannt — statt eine zweite anzulegen.
    ///
    /// Der Fall tritt nach jeder erneuten Zustimmung ein: die Engine hält die
    /// Kennung dann für die eines anderen Kontos und vergisst sie. Ohne diesen
    /// Weg füllte sich der Ordner mit Karteileichen desselben Geräts.
    func testOwnFileIsFoundByDeviceIdWhenTheIdWasForgotten() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        let books = FakeBookkeeping()
        let sync = engine(store, remote, books)

        await sync.run()
        XCTAssertEqual(remote.files.count, 1)

        // Wie nach einer erneuten Zustimmung.
        books.values["nori.sync.driveFileId"] = nil
        store.toggleFavorite("naruto", title: "Naruto")
        await sync.run()

        XCTAssertEqual(remote.files.count, 1, "Für dasselbe Gerät liegen jetzt zwei Dateien in Drive")
    }
}

// MARK: - Zwei Ablagen: appDataFolder und TV-Spiegel

extension LibrarySyncEngineTests {

    private func mirrorEngine(_ store: LibraryStore, _ remote: FakeSnapshotStore, _ books: FakeBookkeeping) -> LibrarySyncEngine {
        let engine = LibrarySyncEngine(store: store, bookkeeping: books, keyPrefix: GoogleDriveSync.tvMirrorKeyPrefix)
        engine.connect(to: remote, startSync: false)
        return engine
    }

    /// Jede Ablage führt ihre eigenen Merkposten. Eine Dateikennung aus dem
    /// `appDataFolder` darf nie im Spiegel benutzt werden — und umgekehrt.
    func testTheSpacesKeepSeparateBookkeeping() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let books = FakeBookkeeping()
        let cloud = FakeSnapshotStore()
        cloud.idPrefix = "appdata"
        let mirror = FakeSnapshotStore()
        mirror.idPrefix = "mirror"
        let app = engine(store, cloud, books)
        let tv = mirrorEngine(store, mirror, books)

        await app.run()
        await tv.run()

        XCTAssertEqual(books.values["nori.sync.driveFileId"]?.hasPrefix("appdata-"), true)
        XCTAssertEqual(books.values["nori.sync.tvMirror.driveFileId"]?.hasPrefix("mirror-"), true)
        XCTAssertNotNil(books.values["nori.sync.lastUpload"])
        XCTAssertNotNil(books.values["nori.sync.tvMirror.lastUpload"])

        // Ausschalten betrifft nur den Spiegel.
        tv.disconnect()
        XCTAssertNil(books.values["nori.sync.tvMirror.driveFileId"])
        XCTAssertNotNil(books.values["nori.sync.driveFileId"])

        // Selbst eine hineingeschmuggelte Kennung des appDataFolder führt
        // nicht dorthin.
        books.values["nori.sync.tvMirror.driveFileId"] = books.values["nori.sync.driveFileId"]
        tv.connect(to: mirror, startSync: false)
        store.toggleFavorite("naruto", title: "Naruto")
        await tv.run()

        XCTAssertEqual(cloud.uploads, 1, "Der Spiegel hat in den appDataFolder geschrieben")
        XCTAssertEqual(mirror.files.count, 1)
        XCTAssertTrue(mirror.files.keys.allSatisfy { $0.hasPrefix("mirror-") })
        XCTAssertEqual(books.values["nori.sync.tvMirror.driveFileId"]?.hasPrefix("mirror-"), true)
    }

    /// Der zuletzt geschriebene Stand ist gespeichert, nicht nur im
    /// Arbeitsspeicher: ein Neustart ohne Änderung schreibt nichts.
    func testAnUnchangedLibraryIsNotWrittenAfterARestart() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        let books = FakeBookkeeping()

        await engine(store, remote, books).run()
        XCTAssertEqual(remote.uploads, 1)

        // Neustart: eine neue Engine mit denselben Merkposten.
        await engine(store, remote, books).run()
        XCTAssertEqual(remote.uploads, 1, "Nach dem Neustart wurde der unveränderte Stand erneut geschrieben")

        // Hat jemand die Datei inzwischen verändert, wird wieder geschrieben.
        let own = books.values["nori.sync.driveFileId"]!
        remote.seed(id: own, deviceId: store.deviceId, data: remote.files[own]!.data)
        await engine(store, remote, books).run()
        XCTAssertEqual(remote.uploads, 2)

        // Und eine echte Änderung sowieso.
        store.toggleFavorite("naruto", title: "Naruto")
        await engine(store, remote, books).run()
        XCTAssertEqual(remote.uploads, 3)
        XCTAssertEqual(remote.files.count, 1)
    }

    /// Eine erneute Zustimmung — etwa für „Mit Fernseher teilen" — bringt einen
    /// neuen Auffrischungstoken und damit einen neuen Kontofingerabdruck. Der
    /// unveränderte Stand wird deshalb nicht noch einmal geschrieben.
    func testANewConsentDoesNotRewriteAnUnchangedLibrary() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        let sync = LibrarySyncEngine(store: store, bookkeeping: FakeBookkeeping())
        sync.connect(to: remote, accountId: "fingerabdruck-1", startSync: false)
        await sync.run()

        sync.connect(to: remote, accountId: "fingerabdruck-2", startSync: false)
        await sync.run()

        XCTAssertEqual(remote.uploads, 1)
        XCTAssertEqual(remote.files.count, 1)
    }

    /// Zwei Dateien mit derselben Gerätekennung: genommen wird deterministisch
    /// die neueste, die andere nicht geladen und nicht gelöscht.
    func testDuplicateFilesOfOneDeviceUseTheNewestAndDeleteNothing() async {
        let older = makeStore()
        older.toggleFavorite("alt", title: "Alt")
        let newer = makeStore()
        newer.toggleFavorite("neu", title: "Neu")
        let remote = FakeSnapshotStore()
        // Wie nach einem aus dem Papierkorb zurückgeholten Spiegel.
        remote.seed(id: "z-alt", deviceId: "mac", data: snapshot(older.snapshot()))
        remote.seed(id: "a-neu", deviceId: "mac", data: snapshot(newer.snapshot()))
        let store = makeStore()
        let sync = engine(store, remote, FakeBookkeeping())

        await sync.run()

        XCTAssertEqual(store.favorites, ["neu"])
        XCTAssertEqual(remote.downloads, 1, "Die überzählige Datei wurde trotzdem geladen")
        XCTAssertEqual(remote.files.count, 3, "Nori hat eine Datei gelöscht")
        XCTAssertEqual(sync.remoteDeviceCount, 1)
        XCTAssertNotNil(sync.lastWarning)
    }

    /// Liegen eigene Dateien doppelt vor, wird die neueste beschrieben — und
    /// keine dritte angelegt.
    func testDuplicateOwnFilesAreWrittenToTheNewest() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        remote.seed(id: "eigen-alt", deviceId: store.deviceId, data: snapshot(store.snapshot()))
        remote.seed(id: "eigen-neu", deviceId: store.deviceId, data: snapshot(store.snapshot()))
        let books = FakeBookkeeping()
        let sync = engine(store, remote, books)
        store.toggleFavorite("naruto", title: "Naruto")

        await sync.run()

        XCTAssertEqual(remote.files.count, 2, "Für dasselbe Gerät kam eine dritte Datei dazu")
        XCTAssertEqual(books.values["nori.sync.driveFileId"], "eigen-neu")
        XCTAssertEqual(remote.files["eigen-alt"]?.modifiedTime, 1, "Die ältere Datei wurde angefasst")
    }

    /// Eine in den Papierkorb gelegte eigene Spiegeldatei ließe sich weiter
    /// beschreiben, aber niemand fände sie. Also eine neue — und die alte bleibt.
    func testATrashedOwnMirrorFileIsReplacedNotReused() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        remote.idPrefix = "mirror"
        let books = FakeBookkeeping()
        let sync = mirrorEngine(store, remote, books)
        await sync.run()
        let first = books.values["nori.sync.tvMirror.driveFileId"]!

        remote.trashed.insert(first)
        await sync.run()

        let second = books.values["nori.sync.tvMirror.driveFileId"]!
        XCTAssertNotEqual(first, second, "Die Datei im Papierkorb wurde weiter beschrieben")
        XCTAssertEqual(remote.uploads, 2)
        XCTAssertNotNil(remote.files[first], "Nori hat die Datei im Papierkorb gelöscht")
    }

    /// Das Relais: iPhone nur im `appDataFolder`, Fernseher nur im Spiegel, der
    /// Mac mit Freigabe in beiden. Änderungen kommen in beide Richtungen an,
    /// Entfernungen als Grabstein.
    func testChangesAreRelayedBothWaysIncludingRemovals() async {
        final class Log { var names: [String] = [] }
        let iphone = makeStore()
        let mac = makeStore()
        let tv = makeStore()
        let cloud = FakeSnapshotStore()
        cloud.idPrefix = "appdata"
        let mirror = FakeSnapshotStore()
        mirror.idPrefix = "mirror"
        let macBooks = FakeBookkeeping()
        let log = Log()
        let iphoneSync = engine(iphone, cloud, FakeBookkeeping())
        let macApp = engine(mac, cloud, macBooks)
        let macMirror = mirrorEngine(mac, mirror, macBooks)
        let tvSync = mirrorEngine(tv, mirror, FakeBookkeeping())
        macApp.onMergedChange = { log.names.append("zum Spiegel") }
        macMirror.onMergedChange = { log.names.append("zum appDataFolder") }

        // iPhone → Mac → Fernseher
        iphone.toggleFavorite("naruto", title: "Naruto")
        await iphoneSync.run()
        await macApp.run()
        XCTAssertEqual(log.names, ["zum Spiegel"], "Der Spiegel erfuhr nichts von der neuen Merkliste")
        await macMirror.run()
        await tvSync.run()
        XCTAssertEqual(tv.favorites, ["naruto"], "Die Merkliste des iPhones kam nicht am Fernseher an")

        // Fernseher → Mac → iPhone
        try? await Task.sleep(nanoseconds: 5_000_000)
        tv.toggleFavorite("one-piece", title: "One Piece")
        await tvSync.run()
        await macMirror.run()
        XCTAssertEqual(log.names.last, "zum appDataFolder")
        await macApp.run()
        await iphoneSync.run()
        XCTAssertEqual(Set(iphone.favorites), ["naruto", "one-piece"], "Die Merkliste des Fernsehers kam nicht am iPhone an")

        // Eine Entfernung auf dem iPhone kommt am Fernseher an.
        try? await Task.sleep(nanoseconds: 5_000_000)
        iphone.toggleFavorite("naruto", title: "Naruto")
        await iphoneSync.run()
        await macApp.run()
        await macMirror.run()
        await tvSync.run()
        XCTAssertEqual(tv.favorites, ["one-piece"], "Die Entfernung kam am Fernseher nicht an")

        // Jede Ablage kennt nur ihre Geräte und ihre Kennungen.
        XCTAssertEqual(Set(cloud.files.values.map(\.deviceId)), [iphone.deviceId, mac.deviceId])
        XCTAssertEqual(Set(mirror.files.values.map(\.deviceId)), [mac.deviceId, tv.deviceId])
        XCTAssertTrue(cloud.files.keys.allSatisfy { $0.hasPrefix("appdata-") })
        XCTAssertTrue(mirror.files.keys.allSatisfy { $0.hasPrefix("mirror-") })
        XCTAssertEqual(tvSync.remoteDeviceCount, 1)
    }

    /// Gemeldet wird nur ein wirklich veränderter Stand. Sonst stießen sich
    /// beide Ablagen gegenseitig an, ohne dass etwas zu tun wäre.
    func testOnlyAChangedLibraryNotifiesTheOtherSpace() async {
        final class Counter { var value = 0 }
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        let counter = Counter()
        let sync = engine(store, remote, FakeBookkeeping())
        sync.onMergedChange = { counter.value += 1 }

        await sync.run()
        XCTAssertEqual(counter.value, 0, "Der eigene Stand allein ist keine Änderung")

        let anderes = makeStore()
        anderes.toggleFavorite("naruto", title: "Naruto")
        remote.seed(id: "anderes", deviceId: anderes.deviceId, data: snapshot(anderes.snapshot()))
        await sync.run()
        XCTAssertEqual(counter.value, 1)

        await sync.run()
        await sync.run()
        XCTAssertEqual(counter.value, 1, "Ohne neue Änderung wurde die andere Ablage erneut angestoßen")
    }

    func testRemoteDeviceCountSeesOtherDevicesOnly() async {
        let store = makeStore()
        let remote = FakeSnapshotStore()
        let sync = engine(store, remote, FakeBookkeeping())
        XCTAssertNil(sync.remoteDeviceCount)

        await sync.run()
        XCTAssertEqual(sync.remoteDeviceCount, 0, "Die eigene Datei zählt nicht")

        for name in ["iphone", "ipad", "mac"] {
            let other = makeStore()
            other.toggleFavorite(name, title: name)
            remote.seed(id: name, deviceId: other.deviceId, data: snapshot(other.snapshot()))
        }
        await sync.run()
        XCTAssertEqual(sync.remoteDeviceCount, 3)
        XCTAssertEqual(Set(store.favorites), ["iphone", "ipad", "mac"])
    }

    /// Zwei Anstöße zugleich — etwa beide Ablagen melden sich — legen keine
    /// zweite Datei an.
    func testTwoRunsAtOnceWriteOneFile() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let remote = FakeSnapshotStore()
        let sync = engine(store, remote, FakeBookkeeping())

        async let first: Void = sync.run()
        async let second: Void = sync.run()
        _ = await (first, second)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(remote.files.count, 1)
        XCTAssertEqual(remote.uploads, 1)
    }

    /// Fehler im Spiegel bleiben im Spiegel: der `appDataFolder` gleicht
    /// weiter ab, und die Bibliothek bleibt unangetastet.
    func testMirrorErrorsStayInTheMirror() async {
        let store = makeStore()
        store.toggleFavorite("one-piece", title: "One Piece")
        let books = FakeBookkeeping()
        let cloud = FakeSnapshotStore()
        let mirror = FakeSnapshotStore()
        let app = engine(store, cloud, books)
        let tv = mirrorEngine(store, mirror, books)
        let file = [GoogleDriveClient.scope, GoogleDriveClient.fileScope]

        mirror.listError = GoogleDriveError.notAuthorized
        await tv.run()
        XCTAssertEqual(tv.status, .needsReauthorization)

        // Zustimmung entzogen: die Oberfläche bietet sie erneut an.
        mirror.listError = GoogleDriveError.forbidden("insufficientScopes")
        await tv.run()
        XCTAssertEqual(TVMirrorState.resolve(enabled: true, grantedScopes: file, mirrorError: tv.lastError), .needsConsent)

        mirror.listError = GoogleDriveError.http(status: 429, message: "Rate Limit")
        await tv.run()
        XCTAssertNotEqual(tv.status, .idle)
        XCTAssertEqual(TVMirrorState.resolve(enabled: true, grantedScopes: file, mirrorError: tv.lastError), .active,
                       "Ein Rate Limit ist keine fehlende Zustimmung")

        mirror.listError = GoogleDriveError.transport("Kein Netz")
        await tv.run()
        XCTAssertEqual(tv.status, .offline)

        await app.run()
        XCTAssertEqual(app.status, .idle, "Ein Fehler im Spiegel hat den appDataFolder aufgehalten")
        XCTAssertEqual(cloud.files.count, 1)
        XCTAssertEqual(mirror.files.count, 0)
        XCTAssertEqual(store.favorites, ["one-piece"])

        mirror.listError = nil
        await tv.run()
        XCTAssertEqual(tv.status, .idle)
        XCTAssertEqual(mirror.files.count, 1)
    }

    func testTVSharingStateFollowsSwitchScopeAndErrors() {
        let both = [GoogleDriveClient.scope, GoogleDriveClient.fileScope]
        XCTAssertEqual(TVMirrorState.resolve(enabled: false, grantedScopes: both, mirrorError: nil), .off,
                       "Ohne Schalter kein Spiegel, auch wenn die Zustimmung da ist")
        XCTAssertEqual(TVMirrorState.resolve(enabled: true, grantedScopes: [GoogleDriveClient.scope], mirrorError: nil), .needsConsent)
        XCTAssertEqual(TVMirrorState.resolve(enabled: true, grantedScopes: both, mirrorError: "insufficientScopes"), .needsConsent)
        XCTAssertEqual(TVMirrorState.resolve(enabled: true, grantedScopes: both, mirrorError: "Kein Netz"), .active)
        XCTAssertEqual(TVMirrorState.resolve(enabled: true, grantedScopes: both, mirrorError: nil), .active)
    }

    /// Ohne Schalter ändert sich nichts — und eingeschaltet wird nur auf diesem
    /// Gerät, nie heimlich.
    func testTVSharingIsOffUntilSwitchedOnOnThisDevice() async {
        let suite = "nori-tv-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let sync = GoogleDriveSync(
            store: makeStore(), makePresenter: { _ in nil }, tokenStore: MemoryTokenStore(),
            bookkeeping: FakeBookkeeping(), defaults: defaults)
        XCTAssertFalse(sync.isTVMirrorEnabled)
        XCTAssertEqual(sync.tvMirrorState, .off)
        XCTAssertFalse(sync.mirrorEngine.isConnected)

        // Ohne Anmeldung lässt sich nichts einschalten.
        await sync.enableTVMirror()
        XCTAssertFalse(sync.isTVMirrorEnabled)
        XCTAssertFalse(defaults.bool(forKey: GoogleDriveSync.tvMirrorEnabledKey))

        // Eingeschaltet, aber Google hat den Bereich (noch) nicht erteilt.
        defaults.set(true, forKey: GoogleDriveSync.tvMirrorEnabledKey)
        let again = GoogleDriveSync(
            store: makeStore(), makePresenter: { _ in nil }, tokenStore: MemoryTokenStore(),
            bookkeeping: FakeBookkeeping(), defaults: defaults)
        XCTAssertTrue(again.isTVMirrorEnabled)
        XCTAssertEqual(again.tvMirrorState, .needsConsent)
        XCTAssertFalse(again.mirrorEngine.isConnected)
        XCTAssertNotNil(again.engine.onMergedChange)
        XCTAssertNotNil(again.mirrorEngine.onMergedChange)

        again.disableTVMirror()
        XCTAssertFalse(again.isTVMirrorEnabled)
        XCTAssertFalse(defaults.bool(forKey: GoogleDriveSync.tvMirrorEnabledKey))
    }

    func testTheReadingOrderDoesNotDependOnDrive() {
        let refs = [
            RemoteSnapshotRef(id: "b", deviceId: "mac", modifiedTime: "2026-09-13T10:00:00.000Z", size: 1),
            RemoteSnapshotRef(id: "a", deviceId: "mac", modifiedTime: "2026-09-13T11:00:00.000Z", size: 1),
            RemoteSnapshotRef(id: "c", deviceId: "iphone", modifiedTime: "2026-09-13T09:00:00.000Z", size: 1),
            RemoteSnapshotRef(id: "d", deviceId: "mac", modifiedTime: "2026-09-13T11:00:00.000Z", size: 1),
        ]
        let expected = [["c"], ["d", "a", "b"]]
        XCTAssertEqual(LibrarySyncEngine.candidateGroups(refs).map { $0.map(\.id) }, expected)
        XCTAssertEqual(LibrarySyncEngine.candidateGroups(Array(refs.reversed())).map { $0.map(\.id) }, expected)
    }
}
