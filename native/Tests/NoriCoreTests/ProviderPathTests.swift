import XCTest
@testable import NoriCore

/// Die Pfadbildung entscheidet, welche Seite abgerufen wird. Ein Fehler hier
/// führt zu 404 statt zu einem sichtbaren Absturz — schwer zu bemerken.
final class ProviderPathTests: XCTestCase {
    func testAniworldSeriesPath() {
        XCTAssertEqual(CatalogProvider.aniworld.seriesPath(slug: "one-piece"), "/anime/stream/one-piece")
        XCTAssertEqual(
            CatalogProvider.aniworld.seriesPath(slug: "one-piece", season: "3"),
            "/anime/stream/one-piece/staffel-3"
        )
        XCTAssertEqual(
            CatalogProvider.aniworld.seriesPath(slug: "one-piece", season: "filme"),
            "/anime/stream/one-piece/filme"
        )
    }

    func testSerienstreamSeriesPath() {
        XCTAssertEqual(CatalogProvider.serienstream.seriesPath(slug: "dexter"), "/serie/dexter")
        XCTAssertEqual(
            CatalogProvider.serienstream.seriesPath(slug: "dexter", season: "2"),
            "/serie/dexter/staffel-2"
        )
    }

    func testEpisodePaths() {
        XCTAssertEqual(
            CatalogProvider.aniworld.episodePath(slug: "demo", season: "2", episode: 5),
            "/anime/stream/demo/staffel-2/episode-5"
        )
        XCTAssertEqual(
            CatalogProvider.serienstream.episodePath(slug: "demo", season: "2", episode: 5),
            "/serie/demo/staffel-2/episode-5"
        )
        XCTAssertEqual(
            CatalogProvider.aniworld.episodePath(slug: "demo", season: "filme", episode: 3),
            "/anime/stream/demo/filme/film-3"
        )
    }

    func testEmptySeasonFallsBackToOne() {
        XCTAssertEqual(
            CatalogProvider.aniworld.episodePath(slug: "demo", season: "", episode: 1),
            "/anime/stream/demo/staffel-1/episode-1"
        )
    }

    /// Die Quelle wird an mehreren Stellen aus dem Pfad abgeleitet.
    func testProviderFromPath() {
        XCTAssertEqual(providerFromPath("/serie/dexter/staffel-1/episode-1"), .serienstream)
        XCTAssertEqual(providerFromPath("/anime/stream/demo/staffel-1/episode-1"), .aniworld)
    }

    func testNormalizeEpisodePath() {
        XCTAssertEqual(
            normalizeEpisodePath("https://aniworld.to/anime/stream/demo/staffel-1/episode-2/"),
            "/anime/stream/demo/staffel-1/episode-2"
        )
        XCTAssertEqual(normalizeEpisodePath("/serie/demo///"), "/serie/demo")
    }

    /// Dieselbe Serie bei beiden Quellen muss getrennt gespeichert bleiben.
    func testProgressKeySeparatesProviders() {
        let path = "/x/y"
        XCTAssertNotEqual(
            progressKey(path: path, provider: .aniworld),
            progressKey(path: path, provider: .serienstream)
        )
        XCTAssertEqual(progressKey(path: "/x/y/", provider: nil), "/x/y")
    }

    func testFormatClock() {
        XCTAssertEqual(formatClock(0), "0:00")
        XCTAssertEqual(formatClock(65), "1:05")
        XCTAssertEqual(formatClock(3661), "1:01:01")
        XCTAssertEqual(formatClock(-5), "0:00")
    }
}
