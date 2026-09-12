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
        return files.map { id, file in
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
        let id = "file-\(nextId)"
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
