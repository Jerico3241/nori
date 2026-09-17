import XCTest
@testable import NoriCore

/// Manuelle Markierung „gesehen“ / „ungesehen“, Untertitel-Einstellungen, eigene
/// Listen und überspringbare Abschnitte.
///
/// Dieselben Fälle wie in `shared/nori-core/test/library.test.ts` und
/// `shared/nori-core/test/sync.test.ts` — Swift und TypeScript rechnen gegen
/// dieselben Regeln, damit der Geräteabgleich denselben Stand liest.
final class MarkingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func episodes(_ count: Int, season: String = "1") -> [Episode] {
        (1...count).map {
            Episode(number: $0, germanTitle: "Folge \($0)", englishTitle: "",
                    path: "/anime/stream/a/staffel-\(season)/episode-\($0)",
                    hosters: [], languages: [])
        }
    }

    private func episode(_ number: Int, season: String = "1") -> Episode {
        Episode(number: number, germanTitle: "Folge \(number)", englishTitle: "",
                path: "/anime/stream/a/staffel-\(season)/episode-\(number)",
                hosters: [], languages: [])
    }

    private func ctx(season: String = "1") -> MarkContext {
        MarkContext(slug: "a", title: "A", season: season, provider: .aniworld)
    }

    // MARK: - Manuelle Markierung

    func testMarkEpisodeSetsCompletedWithoutRealPosition() {
        var progress: [String: WatchProgress] = [:]
        progress = markEpisodeProgress(progress, ctx: ctx(), episode: episode(4), completed: true, now: 1000)
        let entry = progress.values.first
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.episode, 4)
        XCTAssertEqual(entry?.completed, true)
        // completed allein reicht, ohne dass durationSec die Schwelle erfüllen muss.
        XCTAssertTrue(isEpisodeComplete(entry))
    }

    func testMarkEpisodeRemovesEntryWhenUnmarking() {
        var progress: [String: WatchProgress] = [:]
        let ep = episode(1)
        progress = markEpisodeProgress(progress, ctx: ctx(), episode: ep, completed: true)
        XCTAssertEqual(progress.count, 1)
        progress = markEpisodeProgress(progress, ctx: ctx(), episode: ep, completed: false)
        XCTAssertEqual(progress.count, 0)
    }

    func testMarkEpisodeKeepsRealPositionWhenMarking() {
        var progress: [String: WatchProgress] = [
            "aniworld|/anime/stream/one-piece/staffel-1/episode-1": WatchProgress(
                slug: "one-piece", title: "One Piece", season: "1", episode: 1,
                episodePath: "/anime/stream/one-piece/staffel-1/episode-1",
                germanTitle: "", englishTitle: "",
                positionSec: 400, durationSec: 1400, updatedAt: 1000,
                lang: "DE", completed: false, provider: .aniworld)
        ]
        let ep = Episode(number: 1, germanTitle: "", englishTitle: "",
                         path: "/anime/stream/one-piece/staffel-1/episode-1",
                         hosters: [], languages: [])
        progress = markEpisodeProgress(progress,
                                       ctx: MarkContext(slug: "one-piece", title: "One Piece", season: "1", provider: .aniworld),
                                       episode: ep, completed: true, now: 5000)
        let entry = progress["aniworld|/anime/stream/one-piece/staffel-1/episode-1"]
        XCTAssertEqual(entry?.positionSec, 400)
        XCTAssertEqual(entry?.completed, true)
        XCTAssertEqual(entry?.updatedAt, 5000)
    }

    func testMarkSeasonMarksAllEpisodes() {
        var progress: [String: WatchProgress] = [:]
        let eps = episodes(12)
        progress = markSeasonProgress(progress, ctx: ctx(), episodes: eps, completed: true)
        XCTAssertEqual(progress.count, 12)
        XCTAssertTrue(progress.values.allSatisfy { $0.completed == true })
        // Statistik sieht die Staffel als vollständig gesehen.
        let store = LibraryStore(directory: directory)
        for ep in eps { store.upsert(WatchProgress(slug: "a", title: "A", season: "1", episode: ep.number,
            episodePath: ep.path, germanTitle: ep.germanTitle, englishTitle: ep.englishTitle,
            positionSec: 0, durationSec: 0, updatedAt: 1, lang: "DE", completed: true, provider: .aniworld)) }
        XCTAssertEqual(store.seasonStats(slug: "a", season: "1", episodes: eps).watched, 12)
        // Aufheben entfernt alle wieder.
        progress = markSeasonProgress(progress, ctx: ctx(), episodes: eps, completed: false)
        XCTAssertEqual(progress.count, 0)
    }

    func testMarkSeriesMarksKnownEpisodesAcrossSeasons() {
        var progress: [String: WatchProgress] = [:]
        let s1 = episodes(6, season: "1")
        let s2 = episodes(4, season: "2")
        progress = markSeriesProgress(progress, slug: "a", title: "A", provider: .aniworld,
                                      seasons: [("1", s1), ("2", s2)], completed: true)
        XCTAssertEqual(progress.count, 10)
        let store = LibraryStore(directory: directory)
        for ep in s1 { store.upsert(WatchProgress(slug: "a", title: "A", season: "1",
            episode: ep.number, episodePath: ep.path, germanTitle: ep.germanTitle, englishTitle: ep.englishTitle,
            positionSec: 0, durationSec: 0, updatedAt: 1, lang: "DE", completed: true, provider: .aniworld)) }
        for ep in s2 { store.upsert(WatchProgress(slug: "a", title: "A", season: "2",
            episode: ep.number, episodePath: ep.path, germanTitle: ep.germanTitle, englishTitle: ep.englishTitle,
            positionSec: 0, durationSec: 0, updatedAt: 1, lang: "DE", completed: true, provider: .aniworld)) }
        XCTAssertEqual(store.seasonStats(slug: "a", season: "1", episodes: s1).watched, 6)
        XCTAssertEqual(store.seasonStats(slug: "a", season: "2", episodes: s2).watched, 4)
    }

    func testMarkedEpisodesLeaveContinueWatching() {
        // Über den Store, der die Continue-Watching-Auswahl implementiert.
        let store = LibraryStore(directory: directory)
        // Eine angefangene Folge landet in Weiterschauen.
        let item = WatchProgress(slug: "a", title: "A", season: "1", episode: 1,
            episodePath: "/anime/stream/a/staffel-1/episode-1",
            germanTitle: "", englishTitle: "",
            positionSec: 200, durationSec: 1400, updatedAt: 100,
            lang: "DE", completed: false, provider: .aniworld)
        store.upsert(item)
        XCTAssertEqual(store.continueWatching().count, 1)
        // Manuell als gesehen markiert -> raus aus Weiterschauen.
        let ep = Episode(number: 1, germanTitle: "", englishTitle: "",
                         path: "/anime/stream/a/staffel-1/episode-1", hosters: [], languages: [])
        store.markEpisode(ep, season: "1", slug: "a", title: "A", provider: .aniworld, completed: true)
        XCTAssertEqual(store.continueWatching().count, 0)
    }

    // MARK: - Untertitel-Einstellungen

    func testSubtitlePreferencesPersistAndDecode() {
        let store = LibraryStore(directory: directory)
        store.subtitlePref = "DE"
        store.subtitlesEnabled = true
        let reloaded = LibraryStore(directory: directory)
        XCTAssertEqual(reloaded.subtitlePref, "DE")
        XCTAssertEqual(reloaded.subtitlesEnabled, true)
        // Ein Stand ohne die Felder bekommt die Voreinstellung „aus“.
        let fresh = LibraryStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-tests-\(UUID().uuidString)", isDirectory: true))
        XCTAssertEqual(fresh.subtitlePref, "off")
        XCTAssertFalse(fresh.subtitlesEnabled)
    }

    // MARK: - Eigene Listen

    func testCustomListHelpers() {
        var lists: [String: CustomList] = [:]
        lists = ensureList(lists, id: "isekai", name: "Isekai", now: 1000)
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists["isekai"]?.name, "Isekai")
        lists = toggleListItem(lists, id: "isekai", item: "aniworld|shield-hero", now: 2000)
        XCTAssertEqual(lists["isekai"]?.items, ["aniworld|shield-hero"])
        lists = toggleListItem(lists, id: "isekai", item: "aniworld|shield-hero", now: 3000)
        XCTAssertEqual(lists["isekai"]?.items, [])
        lists = renameList(lists, id: "isekai", name: "Iseaki", now: 4000)
        XCTAssertEqual(lists["isekai"]?.name, "Iseaki")
        lists = deleteList(lists, id: "isekai")
        XCTAssertNil(lists["isekai"])
    }

    func testListsPersistAndDecode() {
        let store = LibraryStore(directory: directory)
        store.lists = ["isekai": CustomList(id: "isekai", name: "Isekai", items: ["aniworld|shield-hero"], updatedAt: 100)]
        let reloaded = LibraryStore(directory: directory)
        XCTAssertEqual(reloaded.lists.count, 1)
        XCTAssertEqual(reloaded.lists["isekai"]?.items, ["aniworld|shield-hero"])
        // Eine Bibliothek ohne Listen-Feld dekodiert leer.
        let fresh = LibraryStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-tests-\(UUID().uuidString)", isDirectory: true))
        XCTAssertEqual(fresh.lists.count, 0)
    }

    // MARK: - Skip-Segmente

    func testActiveSkipSegmentMatchesPosition() {
        let segments = [
            SkipSegment(type: .intro, start: 10, end: 80),
            SkipSegment(type: .outro, start: 1320, end: 1400)
        ]
        XCTAssertNil(activeSkipSegment(segments, position: 5))
        XCTAssertEqual(activeSkipSegment(segments, position: 30)?.type, .intro)
        XCTAssertEqual(activeSkipSegment(segments, position: 1350)?.type, .outro)
        XCTAssertNil(activeSkipSegment(segments, position: 100))
    }

    func testFirstSkipSegmentByType() {
        let segments = [
            SkipSegment(type: .intro, start: 10, end: 80),
            SkipSegment(type: .recap, start: 0, end: 9),
            SkipSegment(type: .outro, start: 1320, end: 1400)
        ]
        XCTAssertEqual(firstSkipSegment(segments, type: .outro)?.end, 1400)
        XCTAssertEqual(firstSkipSegment(segments, type: .recap)?.type, .recap)
        XCTAssertEqual(firstSkipSegment(segments, type: .intro)?.type, .intro)
    }
}
