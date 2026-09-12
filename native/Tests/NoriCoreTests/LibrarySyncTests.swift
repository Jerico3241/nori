import XCTest
@testable import NoriCore

/// Der Geräteabgleich, gegen die gemeinsamen Fälle aus
/// `config/sync-fixtures.json`.
///
/// Dieselbe Datei liest `shared/nori-core/test/sync.test.ts`. Das ist der
/// eigentliche Punkt dieser Tests: nicht nur, dass Swift richtig rechnet,
/// sondern dass Swift und TypeScript **gleich** rechnen. Läuft das
/// auseinander, entscheidet der Fernseher anders als das iPhone, beide
/// schreiben ihr Ergebnis zurück, und die Bibliothek pendelt zwischen zwei
/// Ständen — ein Fehler, den niemand als Konflikt erkennt, weil jedes Gerät
/// für sich betrachtet richtig aussieht.
final class LibrarySyncTests: XCTestCase {

    private struct FixtureFile: Decodable {
        let now: Double
        let cases: [Case]
    }

    private struct Case: Decodable {
        let name: String
        let snapshots: [LibraryData]
        let expect: Expectation
    }

    private struct Expectation: Decodable {
        var favorites: [String]?
        var favoriteSource: [String: String]?
        var recents: [String]?
        var progress: [String: Double]?
        var preferences: [String: String]?
        var titles: [String: String]?
    }

    private func loadFixtures() throws -> FixtureFile {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // NoriCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // native/
            .deletingLastPathComponent()   // Wurzel des Repositorys
            .appendingPathComponent("config/sync-fixtures.json")
        return try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: url))
    }

    func testSharedFixtures() throws {
        let file = try loadFixtures()
        XCTAssertFalse(file.cases.isEmpty, "Die Fixture-Datei ist leer — dann prüft dieser Test nichts.")

        for fixture in file.cases {
            let merged = mergeLibrarySnapshots(fixture.snapshots, now: file.now)
            let expect = fixture.expect

            if let favorites = expect.favorites {
                XCTAssertEqual(merged.favorites, favorites, "\(fixture.name): Merkliste")
            }
            if let sources = expect.favoriteSource {
                for (slug, source) in sources {
                    XCTAssertEqual(merged.favoriteSource?[slug], source, "\(fixture.name): Quelle von \(slug)")
                }
            }
            if let recents = expect.recents {
                XCTAssertEqual(merged.recents.map(\.slug), recents, "\(fixture.name): Verlauf")
            }
            if let progress = expect.progress {
                XCTAssertEqual(Set(merged.progress.keys), Set(progress.keys), "\(fixture.name): Fortschritts-Schlüssel")
                for (key, position) in progress {
                    XCTAssertEqual(merged.progress[key]?.positionSec, position, "\(fixture.name): Position \(key)")
                }
            }
            if let preferences = expect.preferences {
                let actual = preferenceText(merged)
                for (key, value) in preferences {
                    XCTAssertEqual(actual[key], value, "\(fixture.name): Einstellung \(key)")
                }
            }
            if let titles = expect.titles {
                for (slug, title) in titles {
                    XCTAssertEqual(merged.titles[slug], title, "\(fixture.name): Titel \(slug)")
                }
            }
        }
    }

    /// `merge(A, B, C)` muss `merge(C, A, B)` sein.
    ///
    /// Drive gibt Dateien in keiner zugesicherten Reihenfolge heraus, und zwei
    /// Geräte sehen sie deshalb verschieden. Hinge das Ergebnis daran, käme
    /// jedes Gerät zu einem anderen Stand, schriebe ihn zurück, und der nächste
    /// Abgleich drehte es wieder um.
    func testOrderDoesNotMatter() throws {
        let file = try loadFixtures()
        for fixture in file.cases {
            let reference = summary(mergeLibrarySnapshots(fixture.snapshots, now: file.now))
            for permutation in permutations(of: fixture.snapshots) {
                let other = summary(mergeLibrarySnapshots(permutation, now: file.now))
                XCTAssertEqual(other, reference, "\(fixture.name): Ergebnis hängt an der Reihenfolge")
            }
        }
    }

    /// Zweimal zusammenführen ändert nichts mehr.
    ///
    /// Ohne das liefe der Abgleich nie zur Ruhe: jedes Gerät schriebe ein
    /// anderes Ergebnis, das beim nächsten Lauf wieder ein anderes ergäbe.
    func testMergeIsIdempotent() throws {
        let file = try loadFixtures()
        for fixture in file.cases {
            let once = mergeLibrarySnapshots(fixture.snapshots, now: file.now)
            let twice = mergeLibrarySnapshots([once], now: file.now)
            XCTAssertEqual(summary(twice), summary(once), "\(fixture.name): zweiter Lauf ändert das Ergebnis")
        }
    }

    /// Ein einzelner Stand geht unverändert durch.
    func testSingleSnapshotSurvives() throws {
        let file = try loadFixtures()
        for fixture in file.cases {
            for snapshot in fixture.snapshots {
                let merged = mergeLibrarySnapshots([snapshot], now: file.now)
                let expected = normalizedSnapshot(snapshot, now: file.now)
                XCTAssertEqual(
                    Set(merged.progress.keys),
                    Set(expected.progress.filter { $0.value.updatedAt > (expected.sync?.progressClearedAt ?? 0) }.keys),
                    "\(fixture.name): ein einzelner Stand verliert Fortschritt"
                )
            }
        }
    }

    // MARK: - Hilfen

    private func preferenceText(_ data: LibraryData) -> [String: String] {
        var out: [String: String] = [:]
        if let value = data.langPref { out["langPref"] = value }
        if let value = data.hosterPref { out["hosterPref"] = value }
        if let value = data.resumeEnabled { out["resumeEnabled"] = value ? "true" : "false" }
        if let value = data.preferredQuality { out["preferredQuality"] = value }
        if let value = data.autoplayNext { out["autoplayNext"] = value ? "true" : "false" }
        if let value = data.playbackSpeed { out["playbackSpeed"] = number(value) }
        if let value = data.provider { out["provider"] = value }
        if let value = data.scope { out["scope"] = value }
        return out
    }

    /// „2" statt „2.0" — damit Swift und TypeScript dieselbe Zeichenkette
    /// bilden und die gemeinsame Fixture-Datei für beide stimmt.
    private func number(_ value: Float) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// Ein Ergebnis auf eine vergleichbare Zeichenkette bringen.
    ///
    /// Alles sortiert: Dictionaries haben in Swift keine feste Reihenfolge, und
    /// ein Vergleich, der daran hängt, prüft die Hash-Ordnung statt den Inhalt.
    private func summary(_ data: LibraryData) -> String {
        var lines: [String] = []
        lines.append("favorites=" + data.favorites.joined(separator: ","))
        lines.append("source=" + (data.favoriteSource ?? [:]).sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: ","))
        lines.append("added=" + (data.favoriteAddedAt ?? [:]).sorted { $0.key < $1.key }
            .map { "\($0.key):\(Int($0.value))" }.joined(separator: ","))
        lines.append("recents=" + data.recents.map { "\($0.slug)@\(Int($0.viewedAt))" }.joined(separator: ","))
        lines.append("progress=" + data.progress.sorted { $0.key < $1.key }
            .map { "\($0.key):\(Int($0.value.positionSec)):\(Int($0.value.updatedAt))" }.joined(separator: ","))
        lines.append("titles=" + data.titles.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: ","))
        lines.append("prefs=" + preferenceText(data).sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: ","))
        lines.append("historyClearedAt=\(Int(data.sync?.historyClearedAt ?? 0))")
        lines.append("progressClearedAt=\(Int(data.sync?.progressClearedAt ?? 0))")
        lines.append("marks=" + (data.sync?.favorites ?? [:]).sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value.isFavorite):\(Int($0.value.updatedAt))" }.joined(separator: ","))
        lines.append("removed=" + (data.sync?.recentsRemoved ?? [:]).sorted { $0.key < $1.key }
            .map { "\($0.key):\(Int($0.value))" }.joined(separator: ","))
        return lines.joined(separator: "\n")
    }

    /// Alle Reihenfolgen — bei bis zu vier Ständen sind das höchstens 24.
    private func permutations<T>(of items: [T]) -> [[T]] {
        guard items.count > 1 else { return [items] }
        guard items.count <= 5 else { return [items.reversed()] }
        var out: [[T]] = []
        for (index, item) in items.enumerated() {
            var rest = items
            rest.remove(at: index)
            for tail in permutations(of: rest) { out.append([item] + tail) }
        }
        return out
    }
}
