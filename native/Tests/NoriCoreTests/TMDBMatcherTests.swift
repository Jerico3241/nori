import XCTest
@testable import NoriCore

/// Die Zuordnung zwischen einem Nori-Titel und einem TMDB-Eintrag.
///
/// Warum das geprüft gehört: Eine falsche Zuordnung ist nicht bloß ein
/// falsches Bild. Sie zieht Beschreibung, Bewertung, Folgentitel, Standbilder
/// und die Beliebtheitssignale der Startseite hinter sich her — die Serie sieht
/// dann durchgehend nach einer anderen aus. Die Fälle hier sind deshalb die
/// Schreibweisen, unter denen AniWorld und Serienstream ihre Titel tatsächlich
/// führen.
final class TMDBMatcherTests: XCTestCase {

    // MARK: - Normalisierung

    func testNormalizeFoldsCaseAccentsAndPunctuation() {
        XCTAssertEqual(TMDBMatcher.normalize("Pokémon"), "pokemon")
        XCTAssertEqual(TMDBMatcher.normalize("Re:ZERO – Starting Life"), "re zero starting life")
        XCTAssertEqual(TMDBMatcher.normalize("  Fullmetal   Alchemist  "), "fullmetal alchemist")
        XCTAssertEqual(TMDBMatcher.normalize("KONOSUBA -God's blessing-"), "konosuba god s blessing")
    }

    func testNormalizeKeepsDigits() {
        // „86" und „91 Days" sind Titel, keine Zählung. Ziffern zu entfernen
        // machte aus beiden dieselbe leere Zeichenkette.
        XCTAssertEqual(TMDBMatcher.normalize("86"), "86")
        XCTAssertEqual(TMDBMatcher.normalize("91 Days"), "91 days")
    }

    func testStripVariantsRemovesSeasonAndYearSuffixes() {
        XCTAssertEqual(TMDBMatcher.stripVariants("Vinland Saga Staffel 2"), "vinland saga")
        XCTAssertEqual(TMDBMatcher.stripVariants("Attack on Titan Final Season"), "attack on titan")
        XCTAssertEqual(TMDBMatcher.stripVariants("Overlord 2nd Season"), "overlord")
        XCTAssertEqual(TMDBMatcher.stripVariants("Dark (2017)"), "dark")
        XCTAssertEqual(TMDBMatcher.stripVariants("Mushoku Tensei Part 2"), "mushoku tensei")
    }

    func testStripVariantsLeavesNumericTitlesAlone() {
        // „1899" ist kein Jahreszusatz, sondern der Serienname. Die Regel
        // greift nur am Ende eines längeren Titels.
        XCTAssertEqual(TMDBMatcher.stripVariants("1899"), "1899")
    }

    // MARK: - Suchbegriffe

    func testQueriesPutsSourceTitleFirstThenAlternates() {
        let queries = TMDBMatcher.queries(
            for: "Dämonenjäger",
            alternates: ["Demon Slayer", "Kimetsu no Yaiba"]
        )
        XCTAssertEqual(queries.first, "Dämonenjäger")
        XCTAssertTrue(queries.contains("Demon Slayer"))
        XCTAssertTrue(queries.contains("Kimetsu no Yaiba"))
    }

    func testQueriesAddsPartBeforeColonAndDropsDuplicates() {
        let queries = TMDBMatcher.queries(for: "Sword Art Online: Alicization", alternates: ["Sword Art Online"])
        // „Titel: Untertitel" steht bei TMDB oft nur als „Titel" — der
        // Kurzform-Eintrag muss dabei sein, aber nur einmal.
        XCTAssertEqual(queries.filter { $0 == "Sword Art Online" }.count, 1)
    }

    // MARK: - Titelnähe

    func testExactTitleBeatsEverythingElse() {
        let exact = TMDBCandidate(id: 1, name: "Bleach", popularity: 5)
        let popular = TMDBCandidate(id: 2, name: "Bleach: Thousand-Year Blood War", popularity: 900)
        let best = TMDBMatcher.best(in: [popular, exact], query: "Bleach", kind: .aniworld)
        XCTAssertEqual(best?.id, 1)
    }

    func testPopularityCannotCreateAMatch() {
        // Der Fall, aus dem früher die falschen Cover entstanden: eine sehr
        // bekannte, völlig andere Serie riss die Schwelle allein durch
        // Beliebtheit.
        let unrelated = TMDBCandidate(id: 7, name: "Game of Thrones", popularity: 5000, genreIDs: [18])
        XCTAssertNil(TMDBMatcher.score(candidate: unrelated, query: "Frieren", kind: .aniworld))
        XCTAssertNil(TMDBMatcher.best(in: [unrelated], query: "Frieren", kind: .aniworld))
    }

    func testShortWordInsideLongerTitleIsNotAMatch() {
        let onePiece = TMDBCandidate(id: 3, name: "One Piece")
        XCTAssertNil(TMDBMatcher.score(candidate: onePiece, query: "One", kind: .aniworld))
    }

    func testSeasonSuffixStillMatchesTheSameSeries() {
        let series = TMDBCandidate(id: 4, name: "Vinland Saga", genreIDs: [16], originCountries: ["JP"])
        let score = TMDBMatcher.score(candidate: series, query: "Vinland Saga Staffel 2", kind: .aniworld)
        XCTAssertNotNil(score)
    }

    func testGermanTitleMatchesViaAlternateName() {
        let candidate = TMDBCandidate(
            id: 5,
            name: "Demon Slayer: Kimetsu no Yaiba",
            originalName: "鬼滅の刃",
            alternateNames: ["Dämonenjäger"],
            genreIDs: [16],
            originCountries: ["JP"]
        )
        XCTAssertNotNil(TMDBMatcher.score(candidate: candidate, query: "Dämonenjäger", kind: .aniworld))
    }

    func testAccentsAndSpecialCharactersDoNotBlockAMatch() {
        let candidate = TMDBCandidate(id: 6, name: "Re:ZERO -Starting Life in Another World-")
        XCTAssertNotNil(
            TMDBMatcher.score(candidate: candidate, query: "Re Zero Starting Life in Another World", kind: .aniworld)
        )
    }

    // MARK: - Quelle als Unterscheidung

    func testSameNameAnimeAndLiveActionSplitByProvider() {
        // Dieselbe Marke gibt es oft zweimal: als Anime und als
        // Realverfilmung. Die Quelle des Nori-Titels entscheidet.
        let anime = TMDBCandidate(id: 10, name: "One Piece", genreIDs: [16], originCountries: ["JP"], posterPath: "/a.jpg")
        let live = TMDBCandidate(id: 11, name: "One Piece", genreIDs: [18], originCountries: ["US"], posterPath: "/b.jpg")

        XCTAssertEqual(TMDBMatcher.best(in: [anime, live], query: "One Piece", kind: .aniworld)?.id, 10)
        XCTAssertEqual(TMDBMatcher.best(in: [anime, live], query: "One Piece", kind: .serienstream)?.id, 11)
    }

    // MARK: - Jahr

    func testYearSeparatesRemakesWithTheSameName() {
        let old = TMDBCandidate(id: 20, name: "Hunter x Hunter", firstAirYear: 1999, genreIDs: [16], originCountries: ["JP"])
        let new = TMDBCandidate(id: 21, name: "Hunter x Hunter", firstAirYear: 2011, genreIDs: [16], originCountries: ["JP"])

        XCTAssertEqual(
            TMDBMatcher.best(in: [old, new], query: "Hunter x Hunter", kind: .aniworld, expectedYear: 2011)?.id,
            21
        )
        XCTAssertEqual(
            TMDBMatcher.best(in: [old, new], query: "Hunter x Hunter", kind: .aniworld, expectedYear: 1999)?.id,
            20
        )
    }

    func testWrongYearAloneDoesNotDiscardAnExactTitle() {
        // Kein Ausschluss: die Quellen führen das Jahr oft gar nicht oder
        // nennen das Jahr der deutschen Erstausstrahlung.
        let candidate = TMDBCandidate(id: 22, name: "Dark", firstAirYear: 2017)
        XCTAssertNotNil(TMDBMatcher.score(candidate: candidate, query: "Dark", kind: .serienstream, expectedYear: 2024))
    }

    // MARK: - Poster

    func testRequirePosterSkipsRowsWithoutOne() {
        let withoutPoster = TMDBCandidate(id: 30, name: "Frieren")
        let withPoster = TMDBCandidate(id: 31, name: "Frieren", posterPath: "/f.jpg")

        XCTAssertEqual(TMDBMatcher.best(in: [withoutPoster], query: "Frieren", kind: .aniworld)?.id, 30)
        XCTAssertNil(TMDBMatcher.best(in: [withoutPoster], query: "Frieren", kind: .aniworld, requirePoster: true))
        XCTAssertEqual(
            TMDBMatcher.best(in: [withoutPoster, withPoster], query: "Frieren", kind: .aniworld, requirePoster: true)?.id,
            31
        )
    }

    // MARK: - Rückweg auf den Nori-Katalog

    func testCatalogIndexFindsNoriTitleForTMDBRow() {
        let catalog = [
            HomeTitle(slug: "vinland-saga", title: "Vinland Saga", provider: .aniworld),
            HomeTitle(slug: "dark", title: "Dark", provider: .serienstream),
        ]
        let index = HomeCatalogIndex(catalog)
        let row = TMDBCandidate(id: 40, name: "Vinland Saga", genreIDs: [16], originCountries: ["JP"])
        XCTAssertEqual(index.match(row)?.slug, "vinland-saga")
    }

    func testCatalogIndexRejectsTitlesNoriDoesNotHave() {
        // Der Kern der Regel: TMDBs Ranglisten bestehen überwiegend aus
        // Titeln, die Nori nicht anbietet. Keiner davon darf auf der
        // Startseite landen.
        let index = HomeCatalogIndex([HomeTitle(slug: "dark", title: "Dark", provider: .serienstream)])
        let row = TMDBCandidate(id: 41, name: "Stranger Things", genreIDs: [18], originCountries: ["US"])
        XCTAssertNil(index.match(row))
    }

    func testCatalogIndexMatchesViaAlternateTitleOfTheSource() {
        let catalog = [
            HomeTitle(
                slug: "daemonenjaeger",
                title: "Dämonenjäger",
                provider: .aniworld,
                alts: ["Demon Slayer: Kimetsu no Yaiba"]
            )
        ]
        let index = HomeCatalogIndex(catalog)
        let row = TMDBCandidate(
            id: 42,
            name: "Demon Slayer: Kimetsu no Yaiba",
            genreIDs: [16],
            originCountries: ["JP"]
        )
        XCTAssertEqual(index.match(row)?.slug, "daemonenjaeger")
    }
}
