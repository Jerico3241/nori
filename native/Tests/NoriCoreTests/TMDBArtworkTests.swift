import XCTest
@testable import NoriCore

/// Logoauswahl, Sprachrückfall und die Unterscheidung zwischen „hat TMDB
/// nicht" und „Abruf gescheitert".
final class TMDBArtworkTests: XCTestCase {

    private func logo(_ path: String, _ iso: String?, vote: Double = 0, count: Int = 0) -> [String: Any] {
        var row: [String: Any] = ["file_path": path, "vote_average": vote, "vote_count": count]
        if let iso { row["iso_639_1"] = iso }
        return row
    }

    // MARK: - Logos

    func testGermanLogoWinsOverEnglish() {
        let rows = [logo("/en.png", "en", vote: 9), logo("/de.png", "de", vote: 1)]
        XCTAssertEqual(TMDBArtwork.bestLogoPath(rows), "/de.png")
    }

    /// Der Punkt, an dem sich die Rangfolge von der alten unterscheidet: ein
    /// Logo **ohne** Sprachkennzeichen gehört vor ein japanisches, nicht mit
    /// ihm auf eine Stufe. Vorher entschied bei beiden die Bewertung.
    func testNeutralLogoWinsOverForeignLanguage() {
        let rows = [logo("/ja.png", "ja", vote: 9), logo("/neutral.png", nil, vote: 1)]
        XCTAssertEqual(TMDBArtwork.bestLogoPath(rows), "/neutral.png")
    }

    func testForeignLogoIsStillBetterThanNone() {
        XCTAssertEqual(TMDBArtwork.bestLogoPath([logo("/th.png", "th")]), "/th.png")
    }

    /// SVG stellt `AsyncImage` nicht dar — ein SVG-Logo bliebe unsichtbar.
    func testSVGIsNeverChosen() {
        let rows = [logo("/de.svg", "de", vote: 9), logo("/ja.png", "ja", vote: 1)]
        XCTAssertEqual(TMDBArtwork.bestLogoPath(rows), "/ja.png")
    }

    func testOnlySVGMeansNoLogo() {
        XCTAssertNil(TMDBArtwork.bestLogoPath([logo("/a.svg", "de"), logo("/b.SVG", "en")]))
    }

    func testEmptyPathIsNotALogo() {
        XCTAssertNil(TMDBArtwork.bestLogoPath([logo("", "de")]))
    }

    func testVoteDecidesWithinTheSameLanguage() {
        let rows = [logo("/a.png", "de", vote: 2, count: 99), logo("/b.png", "de", vote: 7, count: 1)]
        XCTAssertEqual(TMDBArtwork.bestLogoPath(rows), "/b.png")
    }

    func testVoteCountBreaksTheTie() {
        let rows = [logo("/a.png", "de", vote: 5, count: 3), logo("/b.png", "de", vote: 5, count: 40)]
        XCTAssertEqual(TMDBArtwork.bestLogoPath(rows), "/b.png")
    }

    func testLanguageRankOrder() {
        XCTAssertLessThan(TMDBArtwork.languageRank("de"), TMDBArtwork.languageRank("en"))
        XCTAssertLessThan(TMDBArtwork.languageRank("en"), TMDBArtwork.languageRank(nil))
        XCTAssertLessThan(TMDBArtwork.languageRank(nil), TMDBArtwork.languageRank("ja"))
        XCTAssertEqual(TMDBArtwork.languageRank(""), TMDBArtwork.languageRank(nil))
    }

    // MARK: - Sprachrückfall

    /// Der Kern von Punkt „leerer deutscher Text ist kein Ergebnis": TMDB
    /// liefert für eine Folge ohne deutsche Beschreibung nicht etwa gar kein
    /// Feld, sondern `"overview": ""`.
    func testEmptyStringIsTreatedAsMissing() {
        XCTAssertNil(TMDBArtwork.firstNonEmpty(""))
        XCTAssertNil(TMDBArtwork.firstNonEmpty("   "))
        XCTAssertNil(TMDBArtwork.firstNonEmpty(nil, ""))
        XCTAssertEqual(TMDBArtwork.firstNonEmpty("", nil, "englisch"), "englisch")
    }

    func testFallbackFillsOnlyTheGaps() {
        let german = EpisodeInfo(title: "Deutscher Titel", overview: "", still: nil, airDate: "2023-10-06", runtime: nil)
        let english = EpisodeInfo(title: "English Title", overview: "An English text", still: "/s.jpg", airDate: "2023-10-07", runtime: 24)
        let merged = TMDBArtwork.filling(german, with: english)
        XCTAssertEqual(merged.title, "Deutscher Titel", "Vorhandenes Deutsch bleibt stehen")
        XCTAssertEqual(merged.overview, "An English text")
        XCTAssertEqual(merged.still, "/s.jpg")
        XCTAssertEqual(merged.airDate, "2023-10-06", "Vorhandenes Datum bleibt stehen")
        XCTAssertEqual(merged.runtime, 24, "Laufzeit ging im alten Zusammenführen verloren")
    }

    /// „Folge 11" ist kein Titel. Trägt die englische Fassung einen echten,
    /// gewinnt der.
    func testPlaceholderTitleIsReplacedByARealOne() {
        let german = EpisodeInfo(title: "Folge 11")
        let english = EpisodeInfo(title: "The Fated Duel")
        XCTAssertEqual(TMDBArtwork.filling(german, with: english).title, "The Fated Duel")
    }

    func testPlaceholderIsKeptWhenTheFallbackIsAlsoOne() {
        let merged = TMDBArtwork.filling(EpisodeInfo(title: "Folge 11"), with: EpisodeInfo(title: "Episode 11"))
        XCTAssertNil(merged.namedTitle)
    }

    func testMergingAddsEpisodesTheFirstLanguageDoesNotHave() {
        let german: [Int: EpisodeInfo] = [1: EpisodeInfo(title: "Eins", overview: "Text")]
        let english: [Int: EpisodeInfo] = [1: EpisodeInfo(title: "One", overview: "Other"), 2: EpisodeInfo(title: "Two")]
        let merged = TMDBArtwork.merging(german, with: english)
        XCTAssertEqual(merged[1]?.overview, "Text")
        XCTAssertEqual(merged[2]?.title, "Two")
    }

    /// Gemessener Fall: *Dan Da Dan*, Staffel 1 — 23 von 24 deutschen
    /// Beschreibungen vorhanden, die 24. leer. Die frühere Schwelle („erst ab
    /// der Hälfte nachladen") griff nicht, und die Lücke blieb, obwohl der
    /// englische Text vorlag.
    func testASingleGapIsEnoughToAskForTheSecondLanguage() {
        var season: [Int: EpisodeInfo] = [:]
        for n in 1 ... 23 { season[n] = EpisodeInfo(title: "Titel \(n)", overview: "Text", still: "/s.jpg") }
        season[24] = EpisodeInfo(title: "Titel 24", overview: "", still: "/s.jpg")
        XCTAssertTrue(TMDBArtwork.hasGaps(season))
    }

    func testACompleteSeasonNeedsNoSecondRequest() {
        var season: [Int: EpisodeInfo] = [:]
        for n in 1 ... 12 { season[n] = EpisodeInfo(title: "Titel \(n)", overview: "Text", still: "/s.jpg") }
        XCTAssertFalse(TMDBArtwork.hasGaps(season))
    }

    func testAMissingStillCountsAsAGap() {
        let season: [Int: EpisodeInfo] = [1: EpisodeInfo(title: "Titel", overview: "Text", still: nil)]
        XCTAssertTrue(TMDBArtwork.hasGaps(season))
    }

    // MARK: - Fehlschläge

    /// Der Unterschied, an dem die Cache-Fehler hingen: Nur 404 darf dauerhaft
    /// als „hat TMDB nicht" abgelegt werden.
    func testOnly404IsDefinitive() {
        XCTAssertTrue(TMDBFailure.notFound.isDefinitive)
        for failure: TMDBFailure in [.rateLimited, .unauthorized, .network, .malformed, .server(503), .noKey] {
            XCTAssertFalse(failure.isDefinitive, "\(failure) darf nicht dauerhaft gemerkt werden")
        }
    }

    func testStatusMapping() {
        XCTAssertNil(TMDBFailure.from(status: 200))
        XCTAssertNil(TMDBFailure.from(status: 204))
        XCTAssertEqual(TMDBFailure.from(status: 401), .unauthorized)
        XCTAssertEqual(TMDBFailure.from(status: 403), .unauthorized)
        XCTAssertEqual(TMDBFailure.from(status: 404), .notFound)
        XCTAssertEqual(TMDBFailure.from(status: 429), .rateLimited)
        XCTAssertEqual(TMDBFailure.from(status: 503), .server(503))
    }

    func testFailureLabelsNeverCarryAKey() {
        for failure: TMDBFailure in [.noKey, .notFound, .unauthorized, .rateLimited, .network, .malformed, .server(500)] {
            XCTAssertFalse(failure.label.contains("api_key"))
            XCTAssertFalse(failure.label.lowercased().contains("key") && failure != .noKey)
        }
    }

    // MARK: - Bildadressen

    func testEpisodeStillUsesStillPathAndTheStillSize() {
        let url = TMDBImages.url("/abc.jpg", .still)
        XCTAssertEqual(url?.absoluteString, "https://image.tmdb.org/t/p/w454_and_h254_bestv2/abc.jpg")
    }

    func testMissingSlashIsAdded() {
        XCTAssertEqual(TMDBImages.url("abc.jpg", .posterCard)?.absoluteString,
                       "https://image.tmdb.org/t/p/w342/abc.jpg")
    }

    func testEmptyPathIsNoImage() {
        XCTAssertNil(TMDBImages.url("", .posterCard))
        XCTAssertNil(TMDBImages.url(nil, .backdropHero))
    }
}
