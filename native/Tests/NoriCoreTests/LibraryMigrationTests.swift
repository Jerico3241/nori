import XCTest
@testable import NoriCore

/// Der Übergang von Schema v5 auf v6.
///
/// Die teuerste Fehlerklasse in diesem Projekt: geht hier etwas schief,
/// verliert jemand seine Merkliste, seinen Verlauf oder seinen Stand — und
/// zwar still, weil eine leere Bibliothek genauso aussieht wie eine neue
/// Installation.
final class LibraryMigrationTests: XCTestCase {

    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-migration-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func write(_ json: String) {
        try! Data(json.utf8).write(to: folder.appendingPathComponent("library.json"))
    }

    /// Ein realistischer v5-Stand — jedes Feld belegt, das v5 kennt.
    private static let v5 = """
    {
      "version": 5,
      "modifiedAt": 1770000000000,
      "favorites": ["one-piece", "naruto"],
      "favoriteSource": {"one-piece": "aniworld", "naruto": "serienstream"},
      "favoriteAddedAt": {"one-piece": 1769000000000, "naruto": 1768000000000},
      "recents": [
        {"slug": "one-piece", "title": "One Piece", "viewedAt": 1769500000000, "provider": "aniworld"}
      ],
      "titles": {"one-piece": "One Piece", "naruto": "Naruto"},
      "progress": {
        "aniworld|/anime/stream/one-piece/staffel-1/episode-3": {
          "slug": "one-piece", "title": "One Piece", "season": "1", "episode": 3,
          "episodePath": "/anime/stream/one-piece/staffel-1/episode-3",
          "germanTitle": "Folge 3", "englishTitle": "Episode 3",
          "positionSec": 640, "durationSec": 1400, "updatedAt": 1769500000000,
          "lang": "DE", "completed": false, "provider": "aniworld"
        }
      },
      "langPref": "GerSub",
      "hosterPref": "Vidmoly",
      "resumeEnabled": false,
      "preferredQuality": "720",
      "autoplayNext": false,
      "playbackSpeed": 1.25,
      "provider": "serienstream",
      "scope": "aniworld"
    }
    """

    /// A — kein Datenverlust.
    func testEveryV5FieldSurvives() {
        write(Self.v5)
        let store = LibraryStore(directory: folder)

        XCTAssertEqual(store.favorites, ["one-piece", "naruto"])
        XCTAssertEqual(store.favoriteSource["one-piece"], .aniworld)
        XCTAssertEqual(store.favoriteSource["naruto"], .serienstream)
        XCTAssertEqual(store.favoriteAddedAt["one-piece"], 1769000000000)
        XCTAssertEqual(store.favoriteAddedAt["naruto"], 1768000000000)
        XCTAssertEqual(store.recents.map(\.slug), ["one-piece"])
        XCTAssertEqual(store.titles["naruto"], "Naruto")
        XCTAssertEqual(store.progress.count, 1)
        XCTAssertEqual(store.progress.values.first?.positionSec, 640)
        XCTAssertEqual(store.langPref, "GerSub")
        XCTAssertEqual(store.hosterPref, "Vidmoly")
        XCTAssertEqual(store.resumeEnabled, false)
        XCTAssertEqual(store.preferredQuality, "720")
        XCTAssertEqual(store.autoplayNext, false)
        XCTAssertEqual(store.playbackSpeed, 1.25)
        XCTAssertEqual(store.provider, .serienstream)
        XCTAssertEqual(store.scope, .aniworld)
    }

    /// Und der Stand auf der Platte ist danach v6 — mit Gerätekennung.
    func testMigrationIsWrittenBack() throws {
        write(Self.v5)
        let store = LibraryStore(directory: folder)
        XCTAssertFalse(store.deviceId.isEmpty)

        let data = try Data(contentsOf: folder.appendingPathComponent("library.json"))
        let stored = try JSONDecoder().decode(LibraryData.self, from: data)

        XCTAssertEqual(stored.version, 6)
        XCTAssertEqual(stored.sync?.deviceId, store.deviceId)
        XCTAssertEqual(stored.sync?.formatVersion, librarySyncFormatVersion)
        XCTAssertEqual(stored.favorites, ["one-piece", "naruto"])
    }

    /// Die Merkliste wird zu Zustandsmarken — je Eintrag mit seiner Quelle.
    func testFavoritesBecomeMarks() throws {
        write(Self.v5)
        let store = LibraryStore(directory: folder)
        let marks = store.snapshot().sync?.favorites ?? [:]

        XCTAssertEqual(marks["aniworld|one-piece"]?.isFavorite, true)
        XCTAssertEqual(marks["aniworld|one-piece"]?.addedAt, 1769000000000)
        XCTAssertEqual(marks["serienstream|naruto"]?.isFavorite, true)
        XCTAssertNil(marks["aniworld|naruto"], "Die Quelle des Eintrags wurde nicht übernommen")
    }

    /// Die Einstellungen bekommen **festgeschriebene** Zeitstempel.
    ///
    /// Bliebe der Zeitstempel leer und fiele der Vergleich auf `modifiedAt`
    /// zurück, machte jede spätere Änderung an einer Einstellung alle anderen
    /// mit frisch — wer heute die Sprache umstellt, überschriebe damit den
    /// Hoster, den ein anderes Gerät gestern gewählt hat.
    func testPreferenceStampsAreFrozenAtMigration() throws {
        write(Self.v5)
        let store = LibraryStore(directory: folder)
        let vorher = store.snapshot().sync?.preferences ?? [:]
        XCTAssertEqual(vorher["langPref"]?.updatedAt, 1770000000000)
        XCTAssertEqual(vorher["hosterPref"]?.updatedAt, 1770000000000)

        store.langPref = "EN"
        let nachher = store.snapshot().sync?.preferences ?? [:]
        XCTAssertGreaterThan(nachher["langPref"]?.updatedAt ?? 0, 1770000000000)
        XCTAssertEqual(nachher["hosterPref"]?.updatedAt, 1770000000000,
                       "Eine Änderung an der Sprache hat den Hoster mit frischgemacht")
    }

    /// Ein v4-Stand ohne `favoriteAddedAt` geht denselben Weg — über die
    /// Reihenfolge, wie seit v5.
    func testV4StillMigrates() {
        write("""
        {"version": 4, "modifiedAt": 1760000000000,
         "favorites": ["neu", "mittel", "alt"], "recents": [], "titles": {}, "progress": {}}
        """)
        let store = LibraryStore(directory: folder)

        XCTAssertEqual(store.favorites, ["neu", "mittel", "alt"])
        let addedAt = store.favoriteAddedAt
        XCTAssertGreaterThan(addedAt["neu"] ?? 0, addedAt["mittel"] ?? 0)
        XCTAssertGreaterThan(addedAt["mittel"] ?? 0, addedAt["alt"] ?? 0)
        XCTAssertEqual(store.snapshot().sync?.favorites?["aniworld|neu"]?.isFavorite, true)
    }

    /// Eine unlesbare Datei setzt die Bibliothek zurück — aber sie darf die
    /// Kennung nicht jedes Mal neu vergeben und auch nicht abstürzen.
    func testUnreadableFileStartsCleanWithAStableDeviceId() {
        write("{ das ist kein JSON")
        let erst = LibraryStore(directory: folder)
        XCTAssertFalse(erst.deviceId.isEmpty)
        XCTAssertEqual(erst.favorites, [])

        let danach = LibraryStore(directory: folder)
        XCTAssertEqual(danach.deviceId, erst.deviceId)
    }

    /// Ein Stand ohne den Sync-Block, aber schon mit v6-Nummer: der Block wird
    /// ergänzt, ohne dass etwas verloren geht.
    func testMissingSyncBlockIsFilledIn() {
        write("""
        {"version": 6, "modifiedAt": 1770000000000, "favorites": ["x"],
         "favoriteSource": {"x": "aniworld"}, "recents": [], "titles": {}, "progress": {}}
        """)
        let store = LibraryStore(directory: folder)

        XCTAssertFalse(store.deviceId.isEmpty)
        XCTAssertEqual(store.snapshot().sync?.favorites?["aniworld|x"]?.isFavorite, true)
    }
}
