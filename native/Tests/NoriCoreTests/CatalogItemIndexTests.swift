import XCTest
@testable import NoriCore

/// Die Suche des Mac-Katalogs über `CatalogItem`.
///
/// Sie muss dasselbe finden wie die iPhone-Suche über `CatalogEntry`: dieselbe
/// Normalisierung, dieselbe Und-Verknüpfung. Vorher suchte der Mac mit
/// `lowercased().contains` — ohne Akzente zu entfernen und ohne Genres.
final class CatalogItemIndexTests: XCTestCase {

    private func item(_ title: String, slug: String? = nil, alts: [String] = [], genres: [String] = []) -> CatalogItem {
        CatalogItem(
            slug: slug ?? title.lowercased().replacingOccurrences(of: " ", with: "-"),
            title: title,
            alts: alts,
            genres: genres,
            provider: .aniworld
        )
    }

    func testEmptyQueryReturnsEverythingInOrder() {
        let items = [item("Frieren"), item("Dark"), item("Monster")]
        let index = CatalogItemIndex(items)
        XCTAssertEqual(index.search("").map(\.title), ["Frieren", "Dark", "Monster"])
        XCTAssertEqual(index.search("   ").map(\.title), ["Frieren", "Dark", "Monster"])
    }

    func testAccentsAndPunctuationAreIgnored() {
        let index = CatalogItemIndex([item("Pokémon Horizonte"), item("Re:ZERO"), item("Dark")])
        XCTAssertEqual(index.search("pokemon").map(\.title), ["Pokémon Horizonte"])
        XCTAssertEqual(index.search("re zero").map(\.title), ["Re:ZERO"])
    }

    func testAlternateTitleSlugAndGenreMatch() {
        let index = CatalogItemIndex([
            item("Dämonenjäger", slug: "kimetsu-no-yaiba", alts: ["Demon Slayer"], genres: ["Action"]),
            item("Frieren", genres: ["Fantasy"]),
        ])
        XCTAssertEqual(index.search("demon slayer").map(\.slug), ["kimetsu-no-yaiba"])
        XCTAssertEqual(index.search("kimetsu").map(\.slug), ["kimetsu-no-yaiba"])
        XCTAssertEqual(index.search("fantasy").map(\.title), ["Frieren"])
    }

    /// Mehrere Wörter heißen „alle davon", nicht „eines davon".
    func testTermsAreCombinedWithAnd() {
        let index = CatalogItemIndex([
            item("Attack on Titan", genres: ["Action"]),
            item("Titan Games", genres: ["Reality"]),
        ])
        XCTAssertEqual(index.search("titan action").map(\.title), ["Attack on Titan"])
        XCTAssertTrue(index.search("titan drama").isEmpty)
    }

    /// Zehntausend Einträge: eine Suche darf keine spürbare Pause sein.
    func testSearchOverALargeCatalogStaysFast() {
        let items = (0 ..< 10_000).map { item("Titel \($0) Abenteuer", genres: ["Genre \($0 % 40)"]) }
        let index = CatalogItemIndex(items)
        let started = Date()
        for query in ["titel", "abenteuer 99", "genre 7", "nichts davon"] {
            _ = index.search(query)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
        XCTAssertEqual(index.search("titel 9999").count, 1)
    }
}
