import XCTest
@testable import NoriCore

/// „Gesehen", „ungesehen" und „aus Weiterschauen entfernen".
///
/// Dieselben Fälle prüft `shared/nori-core/test/watch.test.ts` für den
/// TypeScript-Kern. Weichen die beiden ab, zeigt der Fernseher auf denselben
/// Drive-Daten einen anderen Stand als das iPhone.
final class WatchMarksTests: XCTestCase {

    private let provider = CatalogProvider.aniworld

    private func path(_ slug: String, _ season: String, _ number: Int) -> String {
        "/anime/stream/\(slug)/staffel-\(season)/episode-\(number)"
    }

    private func episode(_ number: Int, slug: String = "demo", season: String = "1") -> Episode {
        Episode(
            number: number,
            germanTitle: "Folge \(number)",
            englishTitle: "Episode \(number)",
            path: path(slug, season, number),
            hosters: [],
            languages: []
        )
    }

    private func entry(
        _ number: Int,
        position: Double,
        duration: Double,
        completed: Bool? = nil,
        season: String = "1",
        updatedAt: Double = 1_000
    ) -> WatchProgress {
        WatchProgress(
            slug: "demo",
            title: "Demo",
            season: season,
            episode: number,
            episodePath: path("demo", season, number),
            germanTitle: "Folge \(number)",
            englishTitle: "Episode \(number)",
            positionSec: position,
            durationSec: duration,
            updatedAt: updatedAt,
            lang: "DE",
            completed: completed,
            provider: provider
        )
    }

    private func store(_ items: [WatchProgress]) -> [String: WatchProgress] {
        var out: [String: WatchProgress] = [:]
        for item in items {
            out[progressKey(path: item.episodePath, provider: item.provider)] = item
        }
        return out
    }

    private func target(season: String = "1") -> MarkTarget {
        MarkTarget(slug: "demo", title: "Demo", season: season, provider: provider)
    }

    // MARK: - Einzelne Folge

    func testMarkingSeenKeepsTheKnownRuntime() {
        let progress = store([entry(1, position: 300, duration: 1_400)])
        let marked = WatchMarks.episode(
            in: progress, target: target(), episode: episode(1), seen: true, now: 9_000
        )
        XCTAssertTrue(isEpisodeComplete(marked))
        XCTAssertEqual(marked.durationSec, 1_400)
        XCTAssertEqual(marked.positionSec, 1_400)
        XCTAssertEqual(marked.updatedAt, 9_000)
        // Die Sprache eines bekannten Eintrags bleibt stehen.
        XCTAssertEqual(marked.lang, "DE")
    }

    func testMarkingAnUnknownEpisodeSeenWorksWithoutRuntime() {
        let marked = WatchMarks.episode(
            in: [:], target: target(), episode: episode(3), seen: true, now: 9_000
        )
        XCTAssertTrue(isEpisodeComplete(marked))
        XCTAssertEqual(marked.durationSec, 0)
        XCTAssertEqual(marked.episodePath, path("demo", "1", 3))
    }

    /// Kein Löschen: ein leerer Eintrag mit frischem Zeitstempel gewinnt die
    /// Zusammenführung, ein fehlender käme vom nächsten Gerät zurück.
    func testMarkingUnseenWritesAnEmptyEntryInsteadOfDeleting() {
        let progress = store([entry(1, position: 1_400, duration: 1_400, completed: true)])
        let marked = WatchMarks.episode(
            in: progress, target: target(), episode: episode(1), seen: false, now: 9_000
        )
        XCTAssertFalse(isEpisodeComplete(marked))
        XCTAssertEqual(marked.positionSec, 0)
        XCTAssertEqual(marked.durationSec, 1_400, "Die Laufzeit ist eine Auskunft und geht nicht verloren")
        XCTAssertEqual(marked.updatedAt, 9_000)
        XCTAssertEqual(watchSummary(for: [marked]).state, .unseen)
    }

    /// Der Zeitstempel ist in Millisekunden — wie überall sonst in Nori.
    func testStampIsInMilliseconds() {
        let before = Date().timeIntervalSince1970 * 1000
        let marked = WatchMarks.episode(in: [:], target: target(), episode: episode(1), seen: true)
        XCTAssertGreaterThanOrEqual(marked.updatedAt, before)
        XCTAssertLessThan(marked.updatedAt, before + 60_000)
    }

    // MARK: - Staffel und Serie

    func testMarkingASeasonCoversEveryEpisode() {
        let episodes = (1...4).map { episode($0) }
        let marked = WatchMarks.season(in: [:], target: target(), episodes: episodes, seen: true, now: 5)
        XCTAssertEqual(marked.count, 4)
        XCTAssertTrue(marked.allSatisfy { isEpisodeComplete($0) })
        XCTAssertEqual(Set(marked.map(\.episode)), [1, 2, 3, 4])
    }

    func testMarkingASeriesCoversEverySeason() {
        let seasons = [
            SeasonEpisodes(season: "1", episodes: [episode(1), episode(2)]),
            SeasonEpisodes(season: "2", episodes: [episode(1, season: "2")]),
        ]
        let marked = WatchMarks.series(
            in: [:], slug: "demo", title: "Demo", provider: provider, seasons: seasons, seen: true, now: 5
        )
        XCTAssertEqual(marked.count, 3)
        XCTAssertEqual(Set(marked.map(\.season)), ["1", "2"])
    }

    /// „Serie als ungesehen" braucht keine Folgenliste und damit kein Netz.
    func testResettingASeriesTouchesOnlyStartedEntries() {
        let progress = store([
            entry(1, position: 1_400, duration: 1_400, completed: true),
            entry(2, position: 120, duration: 1_400),
            entry(3, position: 0, duration: 0),
        ])
        let reset = WatchMarks.resetSeries(in: progress, slug: "demo", provider: provider, now: 9_000)
        XCTAssertEqual(reset.count, 2, "Der nie angefasste Eintrag braucht keine Marke")
        XCTAssertTrue(reset.allSatisfy { $0.positionSec == 0 && $0.completed == false })
        XCTAssertTrue(reset.allSatisfy { $0.updatedAt == 9_000 })
    }

    func testResettingASeasonLeavesOtherSeasonsAlone() {
        let progress = store([
            entry(1, position: 600, duration: 1_400, season: "1"),
            entry(1, position: 600, duration: 1_400, season: "2"),
        ])
        let reset = WatchMarks.resetSeason(
            in: progress, slug: "demo", season: "2", provider: provider, now: 9_000
        )
        XCTAssertEqual(reset.count, 1)
        XCTAssertEqual(reset.first?.season, "2")
    }

    /// Eine andere Quelle mit demselben Slug bleibt unberührt — der Fortschritt
    /// ist nach `provider|episodePath` getrennt.
    func testMarksNeverCrossProviders() {
        var other = entry(1, position: 600, duration: 1_400)
        other.provider = .serienstream
        other.episodePath = "/serie/demo/staffel-1/episode-1"
        let progress = store([entry(1, position: 600, duration: 1_400), other])

        let reset = WatchMarks.resetSeries(in: progress, slug: "demo", provider: .serienstream, now: 9_000)
        XCTAssertEqual(reset.count, 1)
        XCTAssertEqual(reset.first?.provider, .serienstream)
    }

    // MARK: - Weiterschauen

    func testRemovingFromContinueWatchingKeepsFinishedEpisodes() {
        let progress = store([
            entry(1, position: 1_400, duration: 1_400, completed: true),
            entry(2, position: 300, duration: 1_400),
        ])
        let touched = WatchMarks.removeFromContinueWatching(
            in: progress, slug: "demo", provider: provider, now: 9_000
        )
        XCTAssertEqual(touched.count, 1)
        XCTAssertEqual(touched.first?.episode, 2)
        XCTAssertEqual(touched.first?.positionSec, 0)
    }

    func testStoreRemovesTheSeriesFromContinueWatching() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = LibraryStore(directory: directory)
        library.upsert(entry(2, position: 300, duration: 1_400, updatedAt: nowMillis()))
        XCTAssertEqual(library.continueWatching().count, 1)

        library.removeFromContinueWatching(slug: "demo", provider: provider)
        XCTAssertTrue(library.continueWatching().isEmpty)
        XCTAssertEqual(library.seriesWatchSummary(slug: "demo", provider: provider).state, .unseen)
    }

    func testStoreMarksASeasonSeenInOneWrite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = LibraryStore(directory: directory)
        let episodes = (1...3).map { episode($0) }
        library.setSeasonWatched(
            true, slug: "demo", title: "Demo", season: "1", episodes: episodes, provider: provider
        )
        let summary = library.seriesWatchSummary(slug: "demo", provider: provider)
        XCTAssertEqual(summary.state, .seen)
        XCTAssertEqual(summary.completedEpisodes, 3)
        XCTAssertEqual(library.seasonStats(slug: "demo", season: "1", episodes: episodes).watched, 3)

        library.setSeasonWatched(
            false, slug: "demo", title: "Demo", season: "1", episodes: episodes, provider: provider
        )
        XCTAssertEqual(library.seriesWatchSummary(slug: "demo", provider: provider).state, .unseen)
    }

    // MARK: - Beschriftung

    func testSeasonProgressLabel() {
        XCTAssertEqual(seasonProgressLabel(watched: 7, total: 12), "7 von 12 gesehen")
        XCTAssertNil(seasonProgressLabel(watched: 0, total: 12))
        XCTAssertNil(seasonProgressLabel(watched: 0, total: 0))
    }
}
