import XCTest
@testable import NoriCore

/// Die Zuordnung zwischen der Staffelzählung der Quelle und der von TMDB.
///
/// Die Zahlen in den Fällen stammen aus echten TMDB-Antworten (Stand der
/// Untersuchung), nicht aus dem Kopf: Jujutsu Kaisen ist dort **eine** Staffel
/// mit 59 Folgen, während AniWorld zwei führt; `/tv/95479/season/2` antwortet
/// mit HTTP 404.
final class TMDBSeasonMapTests: XCTestCase {

    private func source(_ pairs: [(Int, String)]) -> [TMDBSeasonMap.SourceEpisode] {
        pairs.map { TMDBSeasonMap.SourceEpisode(number: $0.0, titles: [$0.1]) }
    }

    // MARK: - Versatz

    func testSameCountingYieldsOffsetZero() {
        let src = source([(1, "Ryomen Sukuna"), (2, "Für mich selbst"), (3, "Mädchen aus Stahl"), (4, "Verfluchter Bauch")])
        let tmdb = [1: "Ryomen Sukuna", 2: "Für mich selbst", 3: "Mädchen aus Stahl", 4: "Verfluchter Bauch"]
        XCTAssertEqual(TMDBSeasonMap.offset(source: src, tmdb: tmdb), 0)
    }

    /// Der eigentliche Fall: Die Quelle zählt die zweite Staffel wieder ab 1,
    /// TMDB zählt in einer Flachstaffel durch.
    func testSecondSourceSeasonMapsIntoFlatTmdbSeason() {
        let src = source([(1, "Hidden Inventory"), (2, "Hidden Inventory 2"), (3, "Hidden Inventory 3"), (4, "Premature Death")])
        var tmdb: [Int: String] = [:]
        for n in 1 ... 24 { tmdb[n] = "Staffel eins Folge \(n) mit eigenem Namen" }
        tmdb[25] = "Hidden Inventory"
        tmdb[26] = "Hidden Inventory 2"
        tmdb[27] = "Hidden Inventory 3"
        tmdb[28] = "Premature Death"
        XCTAssertEqual(TMDBSeasonMap.offset(source: src, tmdb: tmdb), 24)
    }

    func testOffsetIsRejectedWithoutEnoughAnchors() {
        let src = source([(1, "Ein Titel"), (2, "Zweiter"), (3, "Dritter"), (4, "Vierter")])
        // Nur eine einzige Übereinstimmung — zu wenig, um einen Versatz zu belegen.
        let tmdb = [40: "Ein Titel", 41: "Etwas ganz anderes", 42: "Noch etwas", 43: "Und noch was"]
        XCTAssertNil(TMDBSeasonMap.offset(source: src, tmdb: tmdb))
    }

    /// Zwei gleich gut belegte Versätze sind keine Zuordnung, sondern ein
    /// Münzwurf. Dann lieber nichts zuordnen.
    func testAmbiguousOffsetIsRejected() {
        let src = source([(1, "Wiederkehr"), (2, "Aufbruch"), (3, "Ende")])
        let tmdb = [
            1: "Wiederkehr", 2: "Aufbruch", 3: "Ende",
            11: "Wiederkehr", 12: "Aufbruch", 13: "Ende",
        ]
        XCTAssertNil(TMDBSeasonMap.offset(source: src, tmdb: tmdb))
    }

    /// „Folge 3" ist kein Titel, sondern dieselbe Nummer noch einmal. Als
    /// Anker würde sie bei jedem Versatz irgendwo passen.
    func testPlaceholderTitlesAreNoAnchors() {
        let src = source([(1, "Folge 1"), (2, "Folge 2"), (3, "Folge 3"), (4, "Folge 4")])
        let tmdb = [1: "Folge 1", 2: "Folge 2", 3: "Folge 3", 4: "Folge 4"]
        XCTAssertNil(TMDBSeasonMap.offset(source: src, tmdb: tmdb))
    }

    func testPlaceholderDetection() {
        XCTAssertTrue(TMDBSeasonMap.isPlaceholder("Folge 11"))
        XCTAssertTrue(TMDBSeasonMap.isPlaceholder("Episode 4"))
        XCTAssertTrue(TMDBSeasonMap.isPlaceholder("  episode 200 "))
        XCTAssertFalse(TMDBSeasonMap.isPlaceholder("Folge des Zorns"))
        XCTAssertFalse(TMDBSeasonMap.isPlaceholder("Episode 11: Der Sturm"))
    }

    /// Der Anker darf an Groß-/Kleinschreibung, Satzzeichen und Akzenten
    /// nicht scheitern — die Quellen schreiben anders als TMDB.
    func testAnchorsSurviveSpellingDifferences() {
        let src = source([(1, "Re:ZERO – Der Anfang"), (2, "Pokémon, los!"), (3, "DAS ENDE.")])
        let tmdb = [7: "Re Zero - Der Anfang", 8: "Pokemon los", 9: "Das Ende"]
        XCTAssertEqual(TMDBSeasonMap.offset(source: src, tmdb: tmdb), 6)
    }

    /// Deutscher und englischer Titel derselben Folge dürfen nicht doppelt
    /// zählen.
    ///
    /// Die Quellen führen bei vielen Folgen denselben Text in beiden Feldern.
    /// Zählte jeder für sich, sähen zwei übereinstimmende Folgen wie vier aus
    /// — und ein Versatz, der auf zwei Folgen beruht, gälte als belegt.
    func testGermanAndEnglishTitleOfOneEpisodeCountOnce() {
        let src = [
            TMDBSeasonMap.SourceEpisode(number: 1, titles: ["Der Anfang", "Der Anfang!"]),
            TMDBSeasonMap.SourceEpisode(number: 2, titles: ["Zweiter", "Zweiter."]),
            TMDBSeasonMap.SourceEpisode(number: 3, titles: ["Dritter", "Third"]),
            TMDBSeasonMap.SourceEpisode(number: 4, titles: ["Vierter", "Fourth"]),
        ]
        // Nur die ersten beiden Folgen kommen bei TMDB vor: zwei Anker bei
        // vier benennbaren Folgen. Würden beide Schreibweisen je Folge zählen,
        // kämen vier heraus und der Versatz gälte fälschlich als belegt.
        let tmdb = [1: "Der Anfang", 2: "Zweiter"]
        XCTAssertNil(TMDBSeasonMap.offset(source: src, tmdb: tmdb))
    }

    // MARK: - Abdeckung und Umschreiben

    func testCoverageCountsSourceEpisodesTmdbActuallyHas() {
        let src = source([(1, "a"), (2, "b"), (3, "c"), (4, "d")])
        let tmdb: [Int: EpisodeInfo] = [1: EpisodeInfo(title: "a"), 2: EpisodeInfo(title: "b")]
        XCTAssertEqual(TMDBSeasonMap.coverage(source: src, tmdb: tmdb), 0.5, accuracy: 0.001)
    }

    func testRemapMovesEpisodesOntoSourceNumbers() {
        let src = source([(1, "x"), (2, "y")])
        let tmdb: [Int: EpisodeInfo] = [
            25: EpisodeInfo(title: "x", overview: "erste"),
            26: EpisodeInfo(title: "y", overview: "zweite"),
        ]
        let mapped = TMDBSeasonMap.remap(tmdb, by: 24, to: src)
        XCTAssertEqual(mapped[1]?.overview, "erste")
        XCTAssertEqual(mapped[2]?.overview, "zweite")
        XCTAssertNil(mapped[25])
    }

    func testRemapDropsEpisodesTmdbDoesNotHave() {
        let src = source([(1, "x"), (2, "y"), (3, "z")])
        let mapped = TMDBSeasonMap.remap([25: EpisodeInfo(title: "x")], by: 24, to: src)
        XCTAssertEqual(mapped.count, 1)
        XCTAssertNil(mapped[3])
    }

    func testEpisodesConvertToSourceEpisodesWithBothTitles() {
        let episodes = [
            Episode(number: 1, germanTitle: "Der Anfang", englishTitle: "The Beginning", path: "/a", hosters: [], languages: []),
            Episode(number: 2, germanTitle: "", englishTitle: "Second", path: "/b", hosters: [], languages: []),
        ]
        let converted = episodes.tmdbSourceEpisodes
        XCTAssertEqual(converted[0].titles, ["Der Anfang", "The Beginning"])
        // Leere Titel fallen heraus, statt als Anker zu zählen.
        XCTAssertEqual(converted[1].titles, ["Second"])
    }
}
