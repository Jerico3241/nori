import XCTest
@testable import NoriCore

/// Der HTML-Parser ist die Stelle, die als Erstes bricht, wenn AniWorld sein
/// Markup ändert. Er lief bisher ohne jede Prüfung.
final class AniworldParsingTests: XCTestCase {

    // MARK: - Katalog

    func testCatalogReadsSlugAndTitle() throws {
        let items = try HTML.parseCatalog(Fixtures.aniworldCatalog)
        XCTAssertEqual(items.map(\.slug), ["one-piece", "naruto"])
        XCTAssertEqual(items.first?.title, "One Piece")
    }

    func testCatalogMergesGenresOfTheSameSlug() throws {
        let items = try HTML.parseCatalog(Fixtures.aniworldCatalog)
        let onePiece = try XCTUnwrap(items.first { $0.slug == "one-piece" })
        XCTAssertEqual(onePiece.genres, ["Action", "Abenteuer"])
    }

    func testCatalogIgnoresLinksOutsideTheAnimePath() throws {
        let items = try HTML.parseCatalog(Fixtures.aniworldCatalog)
        XCTAssertFalse(items.contains { $0.title == "Impressum" })
    }

    /// Ein Alternativtitel, der dem Haupttitel entspricht, ist keiner.
    func testCatalogDropsAlternativeTitleEqualToTheTitle() throws {
        let items = try HTML.parseCatalog(Fixtures.aniworldCatalog)
        let naruto = try XCTUnwrap(items.first { $0.slug == "naruto" })
        XCTAssertEqual(naruto.alts, [])

        let onePiece = try XCTUnwrap(items.first { $0.slug == "one-piece" })
        XCTAssertEqual(onePiece.alts, ["Wan Pisu"])
    }

    // MARK: - Serie

    func testSeriesReadsTitleFromTheSpan() throws {
        let detail = try HTML.parseSeries(Fixtures.aniworldSeries, slug: "one-piece", requestedSeason: nil)
        XCTAssertEqual(detail.title, "One Piece")
    }

    func testSeriesPrefersTheFullDescription() throws {
        let detail = try HTML.parseSeries(Fixtures.aniworldSeries, slug: "one-piece", requestedSeason: nil)
        XCTAssertEqual(detail.description, "Ruffy will Piratenkönig werden.")
        XCTAssertFalse(detail.description.contains("mehr anzeigen"))
    }

    func testSeriesReadsMetadata() throws {
        let detail = try HTML.parseSeries(Fixtures.aniworldSeries, slug: "one-piece", requestedSeason: nil)
        XCTAssertEqual(detail.coverPath, "/public/img/cover/one-piece.jpg")
        XCTAssertEqual(detail.yearStart, "1999")
        XCTAssertEqual(detail.yearEnd, "2026")
        XCTAssertEqual(detail.fsk, "12")
        XCTAssertEqual(detail.imdb, "tt0388629")
    }

    /// Sprachangaben stehen im selben Markup wie Genres, sind aber keine.
    func testSeriesDropsLanguageLabelsFromGenres() throws {
        let detail = try HTML.parseSeries(Fixtures.aniworldSeries, slug: "one-piece", requestedSeason: nil)
        XCTAssertEqual(detail.genres, ["Action", "Abenteuer"])
    }

    /// „Animes Stream:" ist ein Präfix der Quelle, kein Titel.
    func testSeriesStripsTheAlternativeTitlePrefix() throws {
        let detail = try HTML.parseSeries(Fixtures.aniworldSeries, slug: "one-piece", requestedSeason: nil)
        XCTAssertEqual(detail.alts, ["Wan Pisu"])
    }

    func testSeasonsAreSortedWithFilmsLast() throws {
        let detail = try HTML.parseSeries(Fixtures.aniworldSeries, slug: "one-piece", requestedSeason: nil)
        XCTAssertEqual(detail.seasons.map(\.id), ["1", "2", "filme"])
        XCTAssertEqual(detail.seasons.last?.label, "Filme")
    }

    func testEpisodesReadNumberTitlesHostersAndLanguages() throws {
        let detail = try HTML.parseSeries(Fixtures.aniworldSeries, slug: "one-piece", requestedSeason: nil)
        XCTAssertEqual(detail.episodes.count, 2)

        let first = try XCTUnwrap(detail.episodes.first)
        XCTAssertEqual(first.number, 1)
        XCTAssertEqual(first.germanTitle, "Ich bin Ruffy")
        XCTAssertEqual(first.englishTitle, "I'm Luffy")
        XCTAssertEqual(first.path, "/anime/stream/one-piece/staffel-1/episode-1")
        // „Hoster " ist ein Präfix des Markups, kein Teil des Namens.
        XCTAssertEqual(first.hosters, ["VOE", "Vidmoly"])
        XCTAssertEqual(first.languages, ["DE", "GerSub"])

        XCTAssertEqual(detail.episodes[1].languages, ["EN"])
    }

    /// Ohne angeforderte Staffel ist die erste echte Staffel aktiv, nicht
    /// „Filme".
    func testActiveSeasonDefaultsToTheFirstRealSeason() throws {
        let detail = try HTML.parseSeries(Fixtures.aniworldSeries, slug: "one-piece", requestedSeason: nil)
        XCTAssertEqual(detail.activeSeason, "1")

        let requested = try HTML.parseSeries(Fixtures.aniworldSeries, slug: "one-piece", requestedSeason: "2")
        XCTAssertEqual(requested.activeSeason, "2")
    }

    // MARK: - Folge

    func testWatchBuildsRedirectPathsFromTheLinkId() throws {
        let info = try HTML.parseWatch(Fixtures.aniworldWatch, path: "/anime/stream/one-piece/staffel-1/episode-1")
        XCTAssertEqual(info.hosters.first?.redirectPath, "/redirect/123456")
    }

    /// Derselbe Pfad in derselben Sprache ist derselbe Hoster.
    func testWatchDropsDuplicateHosters() throws {
        let info = try HTML.parseWatch(Fixtures.aniworldWatch, path: "/x")
        XCTAssertEqual(info.hosters.count, 3)
        XCTAssertEqual(info.hosters.map(\.name), ["VOE", "Vidmoly", "Filemoon"])
    }

    func testWatchMapsLanguageKeys() throws {
        let info = try HTML.parseWatch(Fixtures.aniworldWatch, path: "/x")
        XCTAssertEqual(info.hosters.map(\.lang), ["DE", "GerSub", "EN"])
    }

    func testWatchReadsEpisodeTitles() throws {
        let info = try HTML.parseWatch(Fixtures.aniworldWatch, path: "/x")
        XCTAssertEqual(info.title, "One Piece")
        XCTAssertEqual(info.germanTitle, "Ich bin Ruffy")
        XCTAssertEqual(info.englishTitle, "I'm Luffy")
    }

    // MARK: - Hilfsfunktionen

    func testToAniworldPathStripsHostAndQuery() {
        XCTAssertEqual(
            HTML.toAniworldPath("https://aniworld.to/anime/stream/demo?x=1"),
            "/anime/stream/demo"
        )
        XCTAssertEqual(HTML.toAniworldPath("/serie/demo#top"), "/serie/demo")
    }

    func testFlagLabelPrefersSubtitlesOverLanguage() {
        // „Mit Untertitel Deutsch" enthält beides; GerSub muss gewinnen.
        XCTAssertEqual(HTML.flagLabel("Mit Untertitel Deutsch"), "GerSub")
        XCTAssertEqual(HTML.flagLabel("Deutsch"), "DE")
        XCTAssertEqual(HTML.flagLabel("English"), "EN")
        XCTAssertEqual(HTML.flagLabel("Japanisch"), "JP")
        XCTAssertNil(HTML.flagLabel("   "))
    }

    /// Aus „one.piece.jpg" wurde einmal der Slug „one", weil am ersten Punkt
    /// geschnitten wurde. Jetzt fällt nur die Endung weg — und weil im Rest ein
    /// Punkt steht, gibt es lieber gar keinen Slug als einen falschen.
    func testSlugFromPosterCutsOnlyTheExtension() {
        XCTAssertEqual(HTML.slugFromPoster("/media/one-piece.jpg"), "one-piece")
        XCTAssertNotEqual(HTML.slugFromPoster("/media/one.piece.jpg"), "one")
        XCTAssertNil(HTML.slugFromPoster("/media/one.piece.jpg"))
        // Zu kurz und ohne Buchstaben.
        XCTAssertNil(HTML.slugFromPoster("/media/12.jpg"))
        XCTAssertNil(HTML.slugFromPoster(""))
    }

    func testSlugFromHrefHandlesBothSources() {
        XCTAssertEqual(HTML.slugFromHref("/anime/stream/one-piece/staffel-1"), "one-piece")
        XCTAssertEqual(HTML.slugFromHref("https://s.to/serie/dexter"), "dexter")
        XCTAssertNil(HTML.slugFromHref("/impressum"))
    }

    func testUniqueKeepsOrderAndDropsBlanks() {
        XCTAssertEqual(HTML.unique(["a", " a ", "", "b"]), ["a", "b"])
    }
}
