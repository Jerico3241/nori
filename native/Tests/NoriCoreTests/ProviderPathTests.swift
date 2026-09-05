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

    // MARK: - Abgeleiteter Coverpfad

    /// Ein Katalogeintrag trägt kein Bild. Ohne diese Ableitung bleibt im
    /// Raster nur TMDB, und findet TMDB nichts, ein Buchstabe.
    func testGuessedCoverPathPerProvider() {
        XCTAssertEqual(
            CatalogProvider.aniworld.guessedCoverPath(slug: "one-piece"),
            "/public/img/cover/one-piece.jpg"
        )
        XCTAssertEqual(
            CatalogProvider.serienstream.guessedCoverPath(slug: "dexter"),
            "/media/images/channel/desktop/dexter.jpg"
        )
    }

    /// Der Pfad wird aus dem Slug zusammengesetzt — ein Slug mit Schrägstrich
    /// oder Punkt führte aus dem Cover-Verzeichnis heraus.
    func testGuessedCoverPathRejectsUnusualSlugs() {
        for slug in ["", "../../etc/passwd", "a/b", "one.piece", "one piece", "one?x=1"] {
            XCTAssertNil(
                CatalogProvider.aniworld.guessedCoverPath(slug: slug),
                "\(slug) hätte abgelehnt werden müssen"
            )
        }
    }

    func testGuessedCoverPathAllowsDigitsAndUnderscore() {
        XCTAssertEqual(
            CatalogProvider.aniworld.guessedCoverPath(slug: "86_eighty-six2"),
            "/public/img/cover/86_eighty-six2.jpg"
        )
    }

    /// Gegenprobe zur Annahme, auf der die Ableitung beruht: `slugFromPoster`
    /// gewinnt aus dem Posternamen den Slug. Beide Richtungen müssen sich
    /// treffen, sonst stimmt die Vermutung nicht.
    func testGuessAndSlugFromPosterAreInverse() {
        let slug = "one-piece"
        let path = CatalogProvider.aniworld.guessedCoverPath(slug: slug)
        XCTAssertEqual(HTML.slugFromPoster(path ?? ""), slug)
    }

    // MARK: - Gemeinsame Bibliothek

    /// Beide Quellen können denselben Slug führen. Ohne die Quelle in der
    /// Kennung fiele in einer gemeinsamen Liste einer der beiden Titel weg.
    func testCatalogItemIdSeparatesProviders() {
        let anime = CatalogItem(slug: "gantz", title: "Gantz", alts: [], genres: [], provider: .aniworld)
        let serie = CatalogItem(slug: "gantz", title: "Gantz", alts: [], genres: [], provider: .serienstream)

        XCTAssertNotEqual(anime.id, serie.id)
        XCTAssertEqual(Set([anime, serie]).count, 2)
    }

    /// Ältere gespeicherte Kataloge kennen das Feld nicht.
    func testCatalogItemDecodesWithoutProvider() throws {
        let json = Data("""
        {"slug":"one-piece","title":"One Piece","alts":[],"genres":["Action"]}
        """.utf8)
        let item = try JSONDecoder().decode(CatalogItem.self, from: json)
        XCTAssertNil(item.provider)
        XCTAssertEqual(item.slug, "one-piece")
    }

    // MARK: - Bereich der Bibliothek

    func testScopeAllIncludesEverything() {
        XCTAssertTrue(LibraryScope.all.includes(.aniworld))
        XCTAssertTrue(LibraryScope.all.includes(.serienstream))
        XCTAssertTrue(LibraryScope.all.includes(nil))
        XCTAssertNil(LibraryScope.all.provider)
    }

    func testNamedScopeFiltersByProvider() {
        XCTAssertTrue(LibraryScope.aniworld.includes(.aniworld))
        XCTAssertFalse(LibraryScope.aniworld.includes(.serienstream))
        XCTAssertEqual(LibraryScope.aniworld.provider, .aniworld)
        XCTAssertEqual(LibraryScope.serienstream.provider, .serienstream)
    }

    /// Einträge aus einem älteren gespeicherten Stand tragen keine Quelle.
    /// Sie auszufiltern hieße, sie ganz verschwinden zu lassen.
    func testEntriesWithoutProviderSurviveEveryScope() {
        for scope in LibraryScope.allCases {
            XCTAssertTrue(scope.includes(nil), "\(scope.rawValue) hat einen Eintrag ohne Quelle verworfen")
        }
    }

    func testScopeLabelsAndHeadlines() {
        XCTAssertEqual(LibraryScope.all.label, "Alle")
        XCTAssertEqual(LibraryScope.aniworld.label, "Anime")
        XCTAssertEqual(LibraryScope.serienstream.label, "Serien")
        XCTAssertEqual(LibraryScope.all.headline, "Alle Titel")
        XCTAssertEqual(LibraryScope.serienstream.headline, "Alle Serien")
    }

    /// Der Kalender führt beide Quellen zusammen und entdoppelt über die
    /// Kennung — dieselbe Folge kann bei beiden Seiten am selben Tag laufen.
    func testAiringEntryIdSeparatesProviders() {
        func entry(_ provider: CatalogProvider?) -> AiringEntry {
            AiringEntry(
                airingAt: 0, episode: 3, season: "2", title: "Gantz", english: nil,
                slug: "gantz", languages: [], dayKey: "2026-09-14",
                dayLabel: "Montag, 14. September", coverPath: nil, provider: provider
            )
        }
        XCTAssertNotEqual(entry(.aniworld).id, entry(.serienstream).id)
        XCTAssertEqual(Set([entry(.aniworld), entry(.serienstream)]).count, 2)
    }
}
