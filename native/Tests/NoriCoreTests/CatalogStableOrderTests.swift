import XCTest
@testable import NoriCore

/// Die Reihenfolge einer Katalogansicht bleibt stehen, während TMDB nachkommt.
///
/// Dieselben Fälle wie `shared/nori-core/test/catalog-order.test.ts`: die
/// Apple-Apps und der Fernseher sollen sich hier gleich verhalten.
final class CatalogStableOrderTests: XCTestCase {

    private func order(_ previous: CatalogOrder<String>?, view: String = "popular", fresh: [String], available: Set<String>? = nil, merged: [String: String] = [:]) -> CatalogOrder<String> {
        let known = available ?? Set(fresh)
        return CatalogStableOrder.next(previous: previous, view: view, fresh: fresh) { id in
            if let target = merged[id] { return target }
            return known.contains(id) ? id : nil
        }
    }

    func testFirstBuildTakesTheFreshOrder() {
        XCTAssertEqual(order(nil, fresh: ["a", "b", "c", "b"]).ids, ["a", "b", "c"])
    }

    /// Der zweite Durchgang sortiert anders — gezeigt wird weiter die erste Folge.
    func testSameViewKeepsTheOrderWhenEnrichmentResorts() {
        let first = order(nil, fresh: ["a", "b", "c"])
        let second = order(first, fresh: ["c", "a", "b"])
        XCTAssertEqual(second.ids, ["a", "b", "c"])
    }

    func testNewEntriesAreAppendedAndRemovedOnesDrop() {
        let first = order(nil, fresh: ["a", "b", "c"])
        let second = order(first, fresh: ["d", "c", "a"], available: ["a", "c", "d"])
        XCTAssertEqual(second.ids, ["a", "c", "d"])
    }

    /// Ein TMDB-abhängiger Filter würde einen Titel inzwischen ausschließen —
    /// solange die Quelle ihn führt, bleibt er an seiner Stelle.
    func testEntriesStayWhileTheSourceStillHasThem() {
        let first = order(nil, fresh: ["a", "b", "c"])
        let second = order(first, fresh: ["a", "c"], available: ["a", "b", "c"])
        XCTAssertEqual(second.ids, ["a", "b", "c"])
    }

    /// Dieselbe Serie beider Quellen wird zusammengeführt: der Eintrag bleibt
    /// an der Stelle der Karte, die schon dastand.
    func testMergedEntryKeepsThePositionOfTheVisibleCard() {
        let first = order(nil, fresh: ["aniworld|x", "serienstream|y", "aniworld|z"])
        let second = order(
            first,
            fresh: ["aniworld|z", "serienstream|x"],
            available: ["aniworld|z", "serienstream|x"],
            merged: ["aniworld|x": "serienstream|x", "serienstream|y": "serienstream|x"]
        )
        XCTAssertEqual(second.ids, ["serienstream|x", "aniworld|z"])
    }

    func testAnotherViewReorders() {
        let first = order(nil, fresh: ["a", "b", "c"])
        let second = order(first, view: "az", fresh: ["c", "b", "a"])
        XCTAssertEqual(second.ids, ["c", "b", "a"])
    }

    func testExplicitRebuildReorders() {
        let first = order(nil, fresh: ["a", "b", "c"])
        XCTAssertEqual(first.ids, ["a", "b", "c"])
        XCTAssertEqual(order(nil, fresh: ["c", "a", "b"]).ids, ["c", "a", "b"])
    }

    func testEmptyPreviousOrderIsRebuilt() {
        let empty = CatalogOrder(view: "popular", ids: [String]())
        XCTAssertEqual(order(empty, fresh: ["b", "a"]).ids, ["b", "a"])
    }
}
