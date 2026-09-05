import XCTest
@testable import NoriCore

/// Serienstream hat ein eigenes Markup — Knöpfe statt Links, SVG statt
/// Fähnchen-Bildern, Kalender als JSON. Deshalb ein eigener Parser und eigene
/// Tests.
final class SerienstreamParsingTests: XCTestCase {

    // MARK: - Katalog

    func testCatalogReadsSeriesPerGenre() throws {
        let items = try HTML.parseCatalogSerienstream(Fixtures.serienstreamCatalog)
        let slugs = Set(items.map(\.slug))
        XCTAssertTrue(slugs.contains("dexter"))
        XCTAssertTrue(slugs.contains("breaking-bad"))
    }

    /// Anime gehören zu AniWorld. Steht ein Titel im Genre „Anime", fällt er
    /// hier raus — sonst steht dieselbe Serie in beiden Katalogen.
    func testCatalogDropsTitlesFromTheAnimeGenre() throws {
        let items = try HTML.parseCatalogSerienstream(Fixtures.serienstreamCatalog)
        XCTAssertFalse(items.contains { $0.slug == "naruto" })
    }

    /// Staffel- und Folgenlinks sind keine Serien.
    func testCatalogIgnoresSeasonLinks() throws {
        let items = try HTML.parseCatalogSerienstream(Fixtures.serienstreamCatalog)
        XCTAssertFalse(items.contains { $0.title == "Staffel 1" })
    }

    func testCatalogReadsAlternativeTitlesFromDataSearch() throws {
        let items = try HTML.parseCatalogSerienstream(Fixtures.serienstreamCatalog)
        let dexter = try XCTUnwrap(items.first { $0.slug == "dexter" })
        XCTAssertEqual(dexter.alts, ["Dexter Morgan"])
    }

    func testDropAnimeTitlesFiltersByKeywordAndScript() {
        let items = [
            CatalogItem(slug: "a", title: "Dexter", alts: [], genres: ["Drama"]),
            CatalogItem(slug: "b", title: "Naruto", alts: [], genres: ["Anime"]),
            CatalogItem(slug: "c", title: "ワンピース", alts: [], genres: ["Drama"]),
            CatalogItem(slug: "d", title: "Sword Art Online", alts: ["Isekai"], genres: []),
        ]
        XCTAssertEqual(HTML.dropAnimeTitles(items).map(\.slug), ["a"])
    }

    // MARK: - Serie

    func testSeriesPrefersTheVisibleDescription() throws {
        let detail = try HTML.parseSeriesSerienstream(Fixtures.serienstreamSeries, slug: "dexter", requestedSeason: nil)
        XCTAssertEqual(detail.title, "Dexter")
        XCTAssertEqual(detail.description, "Ein Forensiker mit einem Nebengewerbe.")
    }

    /// Ohne `<img>` im Seiteninhalt zieht der Parser das Cover aus og:image —
    /// und speichert nur den Pfad, nicht die vollständige Adresse.
    func testSeriesFallsBackToTheOpenGraphImage() throws {
        let detail = try HTML.parseSeriesSerienstream(Fixtures.serienstreamSeries, slug: "dexter", requestedSeason: nil)
        // Aus dem og:image: Host und Abfrage fallen weg, der Pfad bleibt.
        XCTAssertEqual(detail.coverPath, "/media/images/channel/desktop/dexter-7sqv7dhs")
    }

    func testSeasonsAreSortedWithFilmsLast() throws {
        let detail = try HTML.parseSeriesSerienstream(Fixtures.serienstreamSeries, slug: "dexter", requestedSeason: nil)
        XCTAssertEqual(detail.seasons.map(\.id), ["1", "2", "filme"])
    }

    /// Die aktive Staffel steht nicht im Pfad, sondern an der Klasse `active`.
    func testActiveSeasonComesFromTheMarkedLink() throws {
        let detail = try HTML.parseSeriesSerienstream(Fixtures.serienstreamSeries, slug: "dexter", requestedSeason: nil)
        XCTAssertEqual(detail.activeSeason, "2")
    }

    func testRequestedSeasonWinsOverTheMarkedLink() throws {
        let detail = try HTML.parseSeriesSerienstream(Fixtures.serienstreamSeries, slug: "dexter", requestedSeason: "1")
        XCTAssertEqual(detail.activeSeason, "1")
    }

    /// Der Folgenpfad steckt bei Serienstream im `onclick`, nicht in einem
    /// `href` — und trägt dort einen Query-Anhang, der weg muss.
    func testEpisodePathComesFromOnclickWithoutQuery() throws {
        let detail = try HTML.parseSeriesSerienstream(Fixtures.serienstreamSeries, slug: "dexter", requestedSeason: nil)
        XCTAssertEqual(detail.episodes.first?.path, "/serie/dexter/staffel-2/episode-1")
    }

    func testEpisodeFallsBackToTheAnchorHref() throws {
        let detail = try HTML.parseSeriesSerienstream(Fixtures.serienstreamSeries, slug: "dexter", requestedSeason: nil)
        XCTAssertEqual(detail.episodes.count, 2)
        XCTAssertEqual(detail.episodes[1].path, "/serie/dexter/staffel-2/episode-2")
    }

    func testEpisodeReadsTitlesHostersAndLanguages() throws {
        let detail = try HTML.parseSeriesSerienstream(Fixtures.serienstreamSeries, slug: "dexter", requestedSeason: nil)
        let first = try XCTUnwrap(detail.episodes.first)
        XCTAssertEqual(first.number, 1)
        XCTAssertEqual(first.germanTitle, "Es ist Zeit")
        XCTAssertEqual(first.englishTitle, "It's Alive")
        XCTAssertEqual(first.hosters, ["VOE"])
        XCTAssertEqual(first.languages, ["DE"])

        // „Hoster " ist auch hier ein Präfix des Markups.
        XCTAssertEqual(detail.episodes[1].hosters, ["Vidoza"])
    }

    // MARK: - Folge

    func testWatchReadsPlayButtons() throws {
        let info = try HTML.parseWatchSerienstream(Fixtures.serienstreamWatch, path: "/serie/dexter/staffel-2/episode-1")
        XCTAssertEqual(info.hosters.map(\.name), ["VOE", "Vidoza"])
        XCTAssertEqual(info.hosters.map(\.redirectPath), ["/r?t=abc123", "/r?t=def456"])
        XCTAssertEqual(info.hosters.map(\.lang), ["DE", "GerSub"])
    }

    /// Ein Knopf, der auf eine fremde Adresse zeigt, ist kein Hoster dieser
    /// Seite — der Player würde sonst irgendwohin geschickt.
    func testWatchIgnoresAbsoluteForeignTargets() throws {
        let info = try HTML.parseWatchSerienstream(Fixtures.serienstreamWatch, path: "/x")
        XCTAssertFalse(info.hosters.contains { $0.name == "Fremd" })
    }

    func testWatchReadsEpisodeTitles() throws {
        let info = try HTML.parseWatchSerienstream(Fixtures.serienstreamWatch, path: "/x")
        XCTAssertEqual(info.title, "Dexter")
        XCTAssertEqual(info.germanTitle, "Es ist Zeit")
        XCTAssertEqual(info.englishTitle, "It's Alive")
    }
}
