import XCTest
@testable import NoriCore

/// `LibraryScope` entscheidet, was in den Listen steht. Seit `.kdrama` hängt
/// ein Bereich nicht mehr nur an einer Quelle, sondern an Quelle **und**
/// Genre — und ein Fehler darin sieht nicht nach einem Fehler aus: die Liste
/// ist dann bloß zu voll oder zu leer, nichts stürzt ab.
final class LibraryScopeTests: XCTestCase {
    private func item(
        _ slug: String,
        provider: CatalogProvider?,
        genres: [String]
    ) -> CatalogItem {
        CatalogItem(slug: slug, title: slug, alts: [], genres: genres, provider: provider)
    }

    /// K-Dramas sind keine dritte Quelle: der Bereich lädt Serienstream.
    func testKdramaUsesSerienstream() {
        XCTAssertEqual(LibraryScope.kdrama.provider, .serienstream)
        XCTAssertEqual(LibraryScope.kdrama.genre, "K-Drama")
    }

    /// Nur die Bereiche, die an einem Genre hängen, tragen eines.
    func testOnlyKdramaCarriesGenre() {
        XCTAssertNil(LibraryScope.all.genre)
        XCTAssertNil(LibraryScope.aniworld.genre)
        XCTAssertNil(LibraryScope.serienstream.genre)
    }

    func testKdramaTakesSerienstreamTitlesWithGenre() {
        let hit = item("boys-over-flowers", provider: .serienstream, genres: ["K-Drama", "Romantik"])
        XCTAssertTrue(LibraryScope.kdrama.includes(item: hit))
    }

    /// Eine Serie ohne das Genre gehört nicht dazu, auch wenn die Quelle passt.
    func testKdramaRejectsOtherSerienstreamTitles() {
        let miss = item("dexter", provider: .serienstream, genres: ["Krimi", "Drama"])
        XCTAssertFalse(LibraryScope.kdrama.includes(item: miss))
    }

    /// Die Quelle zählt trotzdem: ein Anime mit dem Genre wäre ein Treffer im
    /// Serienbereich, nicht im K-Drama-Bereich — sonst führte die Kachel auf
    /// die falsche Seite.
    func testKdramaRejectsForeignProvider() {
        let wrongSource = item("kdrama-anime", provider: .aniworld, genres: ["K-Drama"])
        XCTAssertFalse(LibraryScope.kdrama.includes(item: wrongSource))
    }

    /// Die Schreibweise kommt unverändert von der Katalogseite. Ändert die
    /// Quelle sie, soll der Bereich gefüllt bleiben statt still leer zu laufen.
    func testGenreMatchIgnoresCase() {
        let shouted = item("laut", provider: .serienstream, genres: ["K-DRAMA"])
        let quiet = item("leise", provider: .serienstream, genres: ["k-drama"])
        XCTAssertTrue(LibraryScope.kdrama.includes(item: shouted))
        XCTAssertTrue(LibraryScope.kdrama.includes(item: quiet))
    }

    /// Ein Titel ohne Genres ist in `.kdrama` kein K-Drama, sondern einer,
    /// über den nichts bekannt ist. Anders als bei der fehlenden Quelle gibt
    /// es hier bewusst keine Nachsicht — sonst wäre der Bereich die zweite
    /// Serienliste.
    func testTitleWithoutGenresIsNotAKdrama() {
        let unknown = item("ohne-genre", provider: .serienstream, genres: [])
        XCTAssertFalse(LibraryScope.kdrama.includes(item: unknown))
    }

    /// Der alte Weg bleibt, wie er war: Einträge ohne eigene Quelle stammen
    /// aus einem älteren Stand und werden nicht ausgefiltert.
    func testProviderOnlyCheckKeepsEntriesWithoutSource() {
        XCTAssertTrue(LibraryScope.kdrama.includes(nil))
        XCTAssertTrue(LibraryScope.serienstream.includes(nil))
        XCTAssertTrue(LibraryScope.all.includes(.aniworld))
        XCTAssertFalse(LibraryScope.aniworld.includes(.serienstream))
    }

    /// Die bestehenden Bereiche dürfen sich durch den neuen nicht ändern.
    func testExistingScopesUnchanged() {
        let anime = item("one-piece", provider: .aniworld, genres: ["Action"])
        let serie = item("dexter", provider: .serienstream, genres: ["Krimi"])

        XCTAssertTrue(LibraryScope.all.includes(item: anime))
        XCTAssertTrue(LibraryScope.all.includes(item: serie))
        XCTAssertTrue(LibraryScope.aniworld.includes(item: anime))
        XCTAssertFalse(LibraryScope.aniworld.includes(item: serie))
        XCTAssertTrue(LibraryScope.serienstream.includes(item: serie))
        XCTAssertFalse(LibraryScope.serienstream.includes(item: anime))
    }

    /// Der Rohwert steht in `library.json` und wandert über iCloud. Ändert er
    /// sich, verlieren bestehende Installationen ihren gewählten Bereich.
    func testRawValuesAreStable() {
        XCTAssertEqual(LibraryScope.kdrama.rawValue, "kdrama")
        XCTAssertEqual(LibraryScope(rawValue: "kdrama"), .kdrama)
        XCTAssertEqual(LibraryScope.allCases.map(\.rawValue), ["all", "aniworld", "serienstream", "kdrama"])
    }

    /// Jeder Bereich braucht sichtbaren Text — eine leere Beschriftung fiele
    /// im segmentierten Regler erst am Bildschirm auf.
    func testEveryScopeIsLabelled() {
        for scope in LibraryScope.allCases {
            XCTAssertFalse(scope.label.isEmpty, "Bereich \(scope.rawValue) ohne Beschriftung")
            XCTAssertFalse(scope.headline.isEmpty, "Bereich \(scope.rawValue) ohne Überschrift")
        }
    }
}
