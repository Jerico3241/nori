import XCTest
@testable import NoriCore

/// `LibraryStore` hält Merkliste, Verlauf und Wiedergabefortschritt. Geht hier
/// etwas schief, verliert jemand seinen Stand — die teuerste Fehlerklasse in
/// diesem Projekt, und bis hierher ungeprüft.
///
/// Getestet wird über die echte API, nicht über geöffnete Interna: der Store
/// bekommt ein eigenes Verzeichnis, wird beschrieben, weggeworfen und neu
/// aufgebaut. Damit steht genau das auf dem Prüfstand, was auch beim Start der
/// App passiert.
final class LibraryStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ json: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: directory.appendingPathComponent("library.json"))
    }

    func testNextPlayUsesExplicitSourceWithoutChangingDefault() {
        let store = LibraryStore(directory: directory)
        store.provider = .serienstream
        let path = "/anime/stream/demo/staffel-1/episode-2"
        store.upsert(WatchProgress(slug: "demo", title: "Demo", season: "1", episode: 2,
            episodePath: path, germanTitle: "Folge", englishTitle: "Episode",
            positionSec: 120, durationSec: 1400, updatedAt: 1, lang: "DE",
            completed: false, provider: .aniworld))
        let episodes = [1, 2].map { Episode(number: $0, germanTitle: "Folge", englishTitle: "",
            path: "/anime/stream/demo/staffel-1/episode-\($0)", hosters: [], languages: []) }
        let result = store.nextPlay(slug: "demo", season: "1", episodes: episodes, source: .aniworld)
        XCTAssertTrue(store.hasProgress(slug: "demo", season: "1", source: .aniworld))
        XCTAssertFalse(store.hasProgress(slug: "demo", season: "1"))
        XCTAssertEqual(result.episode, 2)
        XCTAssertEqual(result.resumeAt, 120)
        XCTAssertEqual(store.provider, .serienstream)
        XCTAssertEqual(store.nextPlay(slug: "demo", season: "1", episodes: episodes).resumeAt, 0)
    }

    // MARK: - Leerer und kaputter Stand

    func testEmptyDirectoryGivesDefaults() {
        let store = LibraryStore(directory: directory)
        XCTAssertEqual(store.scope, .all)
        XCTAssertEqual(store.provider, .aniworld)
        XCTAssertEqual(store.langPref, "DE")
        XCTAssertEqual(store.hosterPref, "VOE")
        XCTAssertTrue(store.resumeEnabled)
        XCTAssertEqual(store.preferredQuality, "auto")
        XCTAssertTrue(store.autoplayNext)
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertTrue(store.progress.isEmpty)
    }

    /// Eine beschädigte Datei darf die App nicht am Start hindern.
    func testBrokenFileFallsBackToDefaults() throws {
        try write("{ das ist kein JSON")
        let store = LibraryStore(directory: directory)
        XCTAssertEqual(store.scope, .all)
        XCTAssertTrue(store.favorites.isEmpty)
    }

    // MARK: - Ältere Stände

    /// Ein Stand aus Schema 3 kennt den Bereich noch nicht. Er bekommt „Alle" —
    /// das ist der Sinn der gemeinsamen Bibliothek, und alles andere muss
    /// unangetastet ankommen.
    func testSchemaThreeLibraryKeepsEverythingAndGainsScope() throws {
        try write("""
        {
          "version": 3,
          "favorites": ["one-piece", "dexter"],
          "recents": [],
          "titles": {"one-piece": "One Piece"},
          "progress": {},
          "langPref": "GerSub",
          "hosterPref": "Vidoza",
          "resumeEnabled": false,
          "autoplayNext": false,
          "playbackSpeed": 1.5,
          "provider": "serienstream"
        }
        """)
        let store = LibraryStore(directory: directory)

        XCTAssertEqual(store.scope, .all)
        XCTAssertEqual(store.favorites, ["one-piece", "dexter"])
        XCTAssertEqual(store.titles["one-piece"], "One Piece")
        XCTAssertEqual(store.langPref, "GerSub")
        XCTAssertEqual(store.hosterPref, "Vidoza")
        XCTAssertFalse(store.resumeEnabled)
        XCTAssertFalse(store.autoplayNext)
        XCTAssertEqual(store.playbackSpeed, 1.5)
        XCTAssertEqual(store.provider, .serienstream)
        // Die Qualitätsvorgabe kennt Schema 3 nicht. Sie muss auf „auto"
        // landen, nicht auf einer Stufe, die nie gewählt wurde.
        XCTAssertEqual(store.preferredQuality, "auto")
    }

    /// Die Qualitätsvorgabe muss einen Umlauf durch die Datei überleben —
    /// sonst steht sie nach dem nächsten Start wieder auf „auto".
    func testPreferredQualitySurvivesAReload() {
        let first = LibraryStore(directory: directory)
        first.preferredQuality = "720"

        let second = LibraryStore(directory: directory)
        XCTAssertEqual(second.preferredQuality, "720")
    }

    func testStoredScopeIsRestored() throws {
        try write("""
        {
          "version": 4, "favorites": [], "recents": [], "titles": {}, "progress": {},
          "scope": "serienstream"
        }
        """)
        XCTAssertEqual(LibraryStore(directory: directory).scope, .serienstream)
    }

    /// Ein unbekannter Wert darf nicht dazu führen, dass die Bibliothek leer
    /// aussieht.
    func testUnknownScopeFallsBackToAll() throws {
        try write("""
        {
          "version": 4, "favorites": [], "recents": [], "titles": {}, "progress": {},
          "scope": "irgendwas"
        }
        """)
        XCTAssertEqual(LibraryStore(directory: directory).scope, .all)
    }

    // MARK: - Schreiben und wieder einlesen

    func testSettingsSurviveARestart() {
        let first = LibraryStore(directory: directory)
        first.scope = .aniworld
        first.langPref = "EN"
        first.playbackSpeed = 2.0
        first.toggleFavorite("one-piece", title: "One Piece")

        let second = LibraryStore(directory: directory)
        XCTAssertEqual(second.scope, .aniworld)
        XCTAssertEqual(second.langPref, "EN")
        XCTAssertEqual(second.playbackSpeed, 2.0)
        XCTAssertTrue(second.isFavorite("one-piece"))
        XCTAssertEqual(second.titles["one-piece"], "One Piece")
    }

    func testProgressSurvivesARestart() {
        let first = LibraryStore(directory: directory)
        first.upsert(
            WatchProgress(
                slug: "one-piece", title: "One Piece", season: "1", episode: 3,
                episodePath: "/anime/stream/one-piece/staffel-1/episode-3",
                germanTitle: "Folge 3", englishTitle: "Episode 3",
                positionSec: 400, durationSec: 1400,
                updatedAt: Date().timeIntervalSince1970 * 1000,
                lang: "DE", completed: nil, provider: .aniworld
            )
        )

        let second = LibraryStore(directory: directory)
        let found = second.progress(
            slug: "one-piece", season: "1", episode: 3,
            path: "/anime/stream/one-piece/staffel-1/episode-3", provider: .aniworld
        )
        XCTAssertEqual(found?.positionSec, 400)
        XCTAssertEqual(found?.durationSec, 1400)
    }

    /// Dieselbe Serie bei beiden Quellen muss getrennt bleiben — sonst springt
    /// der Fortschritt der einen auf die andere über.
    func testProgressStaysSeparatePerProvider() {
        let store = LibraryStore(directory: directory)
        for (provider, position) in [(CatalogProvider.aniworld, 100.0), (.serienstream, 900.0)] {
            store.upsert(
                WatchProgress(
                    slug: "gantz", title: "Gantz", season: "1", episode: 1,
                    episodePath: provider.episodePath(slug: "gantz", season: "1", episode: 1),
                    germanTitle: "", englishTitle: "",
                    positionSec: position, durationSec: 1400, updatedAt: 0,
                    lang: "DE", completed: nil, provider: provider
                )
            )
        }

        XCTAssertEqual(store.progress.count, 2)
        XCTAssertEqual(
            store.progress(slug: "gantz", season: "1", episode: 1, provider: .aniworld)?.positionSec,
            100
        )
        XCTAssertEqual(
            store.progress(slug: "gantz", season: "1", episode: 1, provider: .serienstream)?.positionSec,
            900
        )
    }

    // MARK: - Löschen

    func testClearingProgressKeepsFavourites() {
        let store = LibraryStore(directory: directory)
        store.toggleFavorite("one-piece", title: "One Piece")
        store.upsert(
            WatchProgress(
                slug: "one-piece", title: "One Piece", season: "1", episode: 1,
                episodePath: "/anime/stream/one-piece/staffel-1/episode-1",
                germanTitle: "", englishTitle: "", positionSec: 10, durationSec: 100,
                updatedAt: 0, lang: nil, completed: nil, provider: .aniworld
            )
        )

        store.clearProgress()

        XCTAssertTrue(store.progress.isEmpty)
        XCTAssertTrue(store.isFavorite("one-piece"))
        XCTAssertTrue(LibraryStore(directory: directory).isFavorite("one-piece"))
    }

    func testTogglingAFavouriteTwiceRemovesIt() {
        let store = LibraryStore(directory: directory)
        store.toggleFavorite("dexter", title: "Dexter")
        XCTAssertTrue(store.isFavorite("dexter"))
        store.toggleFavorite("dexter")
        XCTAssertFalse(store.isFavorite("dexter"))
        XCTAssertFalse(LibraryStore(directory: directory).isFavorite("dexter"))
    }

    // MARK: - Weiterschauen

    /// Abgeschlossene Folgen gehören nicht in „Schau weiter".
    func testContinueWatchingSkipsFinishedEpisodes() {
        let store = LibraryStore(directory: directory)
        func add(_ slug: String, position: Double, completed: Bool?) {
            store.upsert(
                WatchProgress(
                    slug: slug, title: slug, season: "1", episode: 1,
                    episodePath: "/anime/stream/\(slug)/staffel-1/episode-1",
                    germanTitle: "", englishTitle: "",
                    positionSec: position, durationSec: 1400,
                    updatedAt: Date().timeIntervalSince1970 * 1000,
                    lang: nil, completed: completed, provider: .aniworld
                )
            )
        }
        add("angefangen", position: 400, completed: nil)
        add("fertig", position: 1399, completed: true)

        let open = store.continueWatching().map(\.slug)
        XCTAssertTrue(open.contains("angefangen"))
        XCTAssertFalse(open.contains("fertig"))
    }
}
