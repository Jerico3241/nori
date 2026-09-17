import XCTest
@testable import NoriCore

/// Die Stufen der Titelsuche und die Tippfehlertoleranz.
///
/// Dieselben Fälle prüft `shared/nori-core/test/search.test.ts` für den
/// TypeScript-Kern. Weichen die beiden ab, sucht der Fernseher anders als das
/// iPhone — auf demselben Katalog, mit derselben Eingabe.
final class CatalogSearchRankingTests: XCTestCase {

    private func prepared(_ title: String, _ alternates: [String] = []) -> CatalogSearch.Prepared {
        CatalogSearch.Prepared(rawTitle: title, alternates: alternates)
    }

    private func score(_ title: String, _ alternates: [String] = [], _ query: String) -> Int {
        CatalogSearch.score(prepared(title, alternates), needle: CatalogSearch.needle(query))
    }

    // MARK: - Stufen

    func testExactTitleIsTheBestStep() {
        XCTAssertEqual(score("Frieren", "frieren"), 0)
        // Akzente, Satzzeichen und Groß-/Kleinschreibung zählen nicht mit.
        XCTAssertEqual(score("Re:ZERO", "re zero"), 0)
        XCTAssertEqual(score("Pokémon", "pokemon"), 0)
    }

    func testPrefixBeatsContainsBeatsAlternate() {
        XCTAssertEqual(score("Attack on Titan", "attack"), 1)
        XCTAssertEqual(score("Attack on Titan", "titan"), 2)
        XCTAssertEqual(score("Dämonenjäger", ["Demon Slayer"], "demon slayer"), 3)
    }

    /// Der Fall aus der Aufgabe: die japanische Umschrift steht bei den Quellen
    /// im Alternativtitel, nicht im Titel.
    func testRomajiFindsTheGermanTitle() {
        let entry = prepared("Attack on Titan", ["Shingeki no Kyojin", "Angriff auf Titan"])
        XCTAssertGreaterThanOrEqual(
            CatalogSearch.score(entry, needle: CatalogSearch.needle("shingeki no kyojin")), 0
        )
        XCTAssertGreaterThanOrEqual(
            CatalogSearch.score(entry, needle: CatalogSearch.needle("angriff auf titan")), 0
        )
    }

    func testEveryWordMustAppear() {
        // Nicht nebeneinander: „kyojin attack" steht so in keinem Titel, aber
        // beide Wörter stehen im Eintrag.
        XCTAssertEqual(score("Attack on Titan", ["Shingeki no Kyojin"], "kyojin attack"), 4)
        XCTAssertEqual(score("Attack on Titan", "titan drama"), -1)
    }

    func testNoMatchIsMinusOne() {
        XCTAssertEqual(score("Frieren", "monster"), -1)
    }

    // MARK: - Tippfehler

    func testTypoWithinToleranceStillMatches() {
        let entry = prepared("Dämonenjäger")
        let needle = CatalogSearch.needle("damonenjager")
        XCTAssertEqual(CatalogSearch.score(entry, needle: needle), 0)

        // Ein Buchstabe daneben: die strenge Stufe findet nichts, die tolerante
        // schon.
        let typo = CatalogSearch.needle("damonejager")
        XCTAssertEqual(CatalogSearch.score(entry, needle: typo), -1)
        XCTAssertEqual(CatalogSearch.fuzzyScore(entry, needle: typo), 5)
    }

    func testShortWordsGetNoTolerance() {
        // Unter vier Buchstaben wäre jeder zweite Titel ein Treffer: „dak"
        // trifft „Dark" nicht, „bark" mit vier Buchstaben schon.
        XCTAssertEqual(CatalogSearch.fuzzyScore(prepared("Dark"), needle: CatalogSearch.needle("dak")), -1)
        XCTAssertEqual(CatalogSearch.fuzzyScore(prepared("Dark"), needle: CatalogSearch.needle("bark")), 5)
        // Unter drei Buchstaben fällt ein Wort ganz heraus.
        XCTAssertEqual(CatalogSearch.fuzzyScore(prepared("Dark"), needle: CatalogSearch.needle("da")), -1)
    }

    /// Ziffern sind keine Tippfehler, sondern andere Zahlen.
    func testDigitsAreNeverCorrected() {
        let entry = prepared("Titel 1999")
        XCTAssertEqual(CatalogSearch.fuzzyScore(entry, needle: CatalogSearch.needle("titel 1998")), -1)
        XCTAssertEqual(CatalogSearch.fuzzyScore(entry, needle: CatalogSearch.needle("titel 1999")), 5)
    }

    // MARK: - Reihenfolge

    func testRankPutsTheBestStepFirst() {
        let titles = ["Titan Games", "Attack on Titan", "Titan"]
        let ranked = CatalogSearch.rank(titles, query: "titan") { prepared($0) }
        XCTAssertEqual(ranked, ["Titan", "Titan Games", "Attack on Titan"])
    }

    func testTooShortQueryMatchesEverything() {
        let titles = ["Frieren", "Dark"]
        XCTAssertEqual(CatalogSearch.rank(titles, query: "d") { prepared($0) }, titles)
        XCTAssertEqual(CatalogSearch.rank(titles, query: "") { prepared($0) }, titles)
    }

    /// Tippfehler erst, wenn die strengen Stufen wenig finden — sonst
    /// verdünnten sie gute Treffer mit schlechten.
    func testFuzzyOnlyRunsWhenStrictFindsLittle() {
        var titles = (0 ..< 30).map { "Frieren Teil \($0)" }
        titles.append("Frieran")
        let ranked = CatalogSearch.rank(titles, query: "frieren") { prepared($0) }
        XCTAssertEqual(ranked.count, 30)
        XCTAssertFalse(ranked.contains("Frieran"))

        // Wenige strenge Treffer: jetzt zählt auch der Vertipper.
        let few = CatalogSearch.rank(["Frieren", "Frieran", "Dark"], query: "frieren") { prepared($0) }
        XCTAssertEqual(few, ["Frieren", "Frieran"])
    }
}
