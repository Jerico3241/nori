import XCTest
@testable import NoriCore

/// Der Katalog: Zusammenführung, Suche, Filter, Sortierung, Abzeichen.
///
/// Die Behauptungen, die der Katalog aufstellt, sind im Simulator nicht
/// nachprüfbar: Ein Raster unter der Überschrift „Top bewertet" sieht richtig
/// aus, egal wonach es sortiert ist, und ein „NEU" auf einer Kachel sieht
/// echt aus, auch wenn es geraten wurde. Deshalb stehen die Regeln als reine
/// Funktionen in `CatalogFeed.swift`, `CatalogRanking.swift` und
/// `CatalogBuilder.swift` — und werden hier durchgespielt.
final class CatalogFeedTests: XCTestCase {
    /// Ein fester Zeitpunkt. Mit `Date()` hinge das Ergebnis davon ab, wann
    /// jemand die Tests laufen lässt.
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func days(_ count: Double) -> Date { now.addingTimeInterval(-count * 86_400) }

    // MARK: - Hilfen

    private func sample(
        _ slug: String,
        provider: CatalogProvider = .aniworld,
        title: String? = nil,
        originalTitle: String? = nil,
        alternates: [String] = [],
        year: Int? = nil,
        genres: [String] = [],
        status: CatalogStatus = .unknown,
        languages: [CatalogLanguage] = [],
        popularity: Double? = nil,
        voteAverage: Double? = nil,
        voteCount: Int? = nil,
        trendingRank: Int? = nil,
        firstAired: Date? = nil,
        lastAired: Date? = nil,
        tmdbID: Int? = nil,
        fresh: Bool = false
    ) -> CatalogEntry {
        var signals = TMDBSignals()
        signals.tmdbID = tmdbID
        signals.popularity = popularity
        signals.voteAverage = voteAverage
        signals.voteCount = voteCount
        signals.trendingRank = trendingRank
        signals.firstAirDate = firstAired
        signals.lastAirDate = lastAired

        let name = title ?? slug.capitalized
        var item = CatalogEntry(primary: CatalogSource(provider: provider, slug: slug, title: name))
        item.title = name
        item.originalTitle = originalTitle
        item.alternativeTitles = alternates
        item.year = year
        item.genres = genres
        item.status = status
        item.languages = languages
        item.signals = signals
        item.hasFreshEpisode = fresh
        item.titleKey = TMDBMatcher.stripVariants(name)
        item.searchKey = CatalogSearch.key(
            title: name,
            originalTitle: originalTitle,
            alternates: alternates,
            genres: genres,
            year: year
        )
        return item
    }

    private func item(
        _ slug: String,
        _ title: String,
        provider: CatalogProvider,
        alts: [String] = [],
        genres: [String] = []
    ) -> CatalogItem {
        CatalogItem(slug: slug, title: title, alts: alts, genres: genres, provider: provider)
    }

    private func airing(
        slug: String,
        provider: CatalogProvider,
        daysAgo: Double,
        languages: [String] = ["DE"]
    ) -> AiringEntry {
        AiringEntry(
            airingAt: days(daysAgo).timeIntervalSince1970 * 1000,
            episode: 3,
            season: "1",
            title: slug.capitalized,
            english: nil,
            slug: slug,
            languages: languages,
            dayKey: "k",
            dayLabel: "Montag",
            coverPath: nil,
            provider: provider
        )
    }

    private func ids(_ entries: [CatalogEntry]) -> [String] { entries.map(\.id) }

    // MARK: - Genres

    func testGenreAliasesCollapseToOneName() {
        // Drei Schreibweisen, ein Genre. Ohne das wären es drei Filter, von
        // denen jeder ein Drittel der Treffer zeigt.
        XCTAssertEqual(CatalogGenres.canonical("Sci-Fi"), "Sci-Fi")
        XCTAssertEqual(CatalogGenres.canonical("Sci Fi"), "Sci-Fi")
        XCTAssertEqual(CatalogGenres.canonical("Science Fiction"), "Sci-Fi")
        XCTAssertEqual(CatalogGenres.canonical("Adventure"), "Abenteuer")
        XCTAssertEqual(CatalogGenres.canonical("Abenteuer"), "Abenteuer")
    }

    func testUnknownGenreKeepsItsOwnSpelling() {
        // Eine feste Erlaubnisliste würde still ausblenden, was die Quellen
        // morgen dazunehmen.
        XCTAssertEqual(CatalogGenres.canonical("Mecha"), "Mecha")
        XCTAssertNil(CatalogGenres.canonical("   "))
    }

    func testTMDBCombinedGenreBecomesTwoNoriGenres() {
        // 10765 heißt bei TMDB „Sci-Fi & Fantasy" — in jedem Katalog sind das
        // zwei Genres.
        XCTAssertEqual(CatalogGenres.canonical(tmdbIDs: [10765]), ["Sci-Fi", "Fantasy"])
        XCTAssertEqual(CatalogGenres.canonical(tmdbIDs: [10759]), ["Action", "Abenteuer"])
    }

    // MARK: - Suche

    func testSearchFindsGermanOriginalAndAlternativeTitles() {
        let show = sample(
            "demon",
            title: "Dämonenjäger",
            originalTitle: "鬼滅の刃",
            alternates: ["Demon Slayer", "Kimetsu no Yaiba"],
            genres: ["Action"]
        )
        for needle in ["dämonenjäger", "damonenjager", "demon slayer", "kimetsu"] {
            XCTAssertTrue(
                CatalogSearch.matches(show, terms: CatalogSearch.terms(needle)),
                "\(needle) sollte treffen"
            )
        }
    }

    func testSearchFindsGenreAndYear() {
        let show = sample("x", title: "Beispiel", year: 2024, genres: ["Fantasy"])
        XCTAssertTrue(CatalogSearch.matches(show, terms: CatalogSearch.terms("fantasy")))
        XCTAssertTrue(CatalogSearch.matches(show, terms: CatalogSearch.terms("2024")))
        XCTAssertFalse(CatalogSearch.matches(show, terms: CatalogSearch.terms("2023")))
    }

    func testSearchIsToleranrOfPunctuationAndCase() {
        let show = sample("rezero", title: "Re:ZERO – Starting Life in Another World")
        for needle in ["re zero", "RE:ZERO", "re-zero starting life"] {
            XCTAssertTrue(
                CatalogSearch.matches(show, terms: CatalogSearch.terms(needle)),
                "\(needle) sollte treffen"
            )
        }
    }

    func testSeveralWordsMeanAll() {
        let fantasy = sample("a", title: "Alpha", year: 2024, genres: ["Fantasy"])
        let action = sample("b", title: "Beta", year: 2024, genres: ["Action"])
        let terms = CatalogSearch.terms("fantasy 2024")
        XCTAssertTrue(CatalogSearch.matches(fantasy, terms: terms))
        XCTAssertFalse(CatalogSearch.matches(action, terms: terms))
    }

    // MARK: - „Neu"

    func testNewComesFromRealSignalsOnly() {
        // Eine Folge, die Noris Kalender vor zwei Tagen gemeldet hat.
        XCTAssertTrue(CatalogRanking.isNew(sample("a", fresh: true), now: now))
        // TMDB führt eine Ausstrahlung im Aktualitätsfenster.
        XCTAssertTrue(CatalogRanking.isNew(sample("b", lastAired: days(10)), now: now))
        // Alte Serie, seit Jahren nichts mehr: nicht neu, egal wie beliebt.
        XCTAssertFalse(
            CatalogRanking.isNew(sample("c", popularity: 900, firstAired: days(3000)), now: now)
        )
        // Gar kein Signal heißt nicht neu — und nicht „vielleicht".
        XCTAssertFalse(CatalogRanking.isNew(sample("d"), now: now))
    }

    func testNewFilterKeepsOnlyRealNewTitles() {
        let entries = [
            sample("fresh", fresh: true),
            sample("aired", lastAired: days(5)),
            sample("old", firstAired: days(4000)),
        ]
        var query = CatalogQuery()
        query.quick = .fresh
        let results = CatalogEngine.results(for: query, in: entries, now: now)
        XCTAssertEqual(Set(ids(results)), ["aniworld|fresh", "aniworld|aired"])
    }

    // MARK: - „Beliebt"

    func testPopularUsesMoreThanTheAverageVote() {
        // Perfekte Bewertung, aber niemand kennt ihn.
        let unknown = sample("unknown", voteAverage: 10, voteCount: 3)
        // Schlechter bewertet, steht aber auf Platz 2 der Wochenliste.
        let trending = sample("trending", popularity: 300, voteAverage: 7.1, voteCount: 9000, trendingRank: 2)
        XCTAssertGreaterThan(
            CatalogRanking.popularityScore(trending),
            CatalogRanking.popularityScore(unknown)
        )
    }

    func testPopularFilterRequiresAPopularitySignal() {
        let entries = [
            sample("with", popularity: 40),
            sample("rank", trendingRank: 12),
            sample("without"),
        ]
        var query = CatalogQuery()
        query.quick = .popular
        let results = CatalogEngine.results(for: query, in: entries, now: now)
        XCTAssertEqual(Set(ids(results)), ["aniworld|with", "aniworld|rank"])
    }

    // MARK: - „Top bewertet"

    func testTopRatedWeighsVoteCount() {
        // Der Fall aus der Aufgabe: 10/10 aus zwei Stimmen darf nicht vor
        // 9/10 aus 50 000 Stimmen stehen.
        let thin = sample("thin", voteAverage: 10, voteCount: 2)
        let solid = sample("solid", voteAverage: 9, voteCount: 50_000)
        let sorted = CatalogRanking.sort([thin, solid], by: .rating, now: now)
        XCTAssertEqual(ids(sorted), ["aniworld|solid", "aniworld|thin"])
        XCTAssertLessThan(
            CatalogRanking.weightedRating(thin) ?? 0,
            CatalogRanking.weightedRating(solid) ?? 0
        )
    }

    func testWeightedRatingWithoutVotesIsNothing() {
        XCTAssertNil(CatalogRanking.weightedRating(sample("a", voteAverage: 8)))
        XCTAssertNil(CatalogRanking.weightedRating(sample("b", voteCount: 400)))
    }

    func testTitlesWithoutRatingSortLast() {
        let rated = sample("rated", voteAverage: 7, voteCount: 900)
        let blank = sample("blank")
        let sorted = CatalogRanking.sort([blank, rated], by: .rating, now: now)
        XCTAssertEqual(ids(sorted), ["aniworld|rated", "aniworld|blank"])
    }

    // MARK: - Sortierung

    func testEverySortChangesTheOrder() {
        let entries = [
            sample("zulu", title: "Zulu", year: 2012, popularity: 5, voteAverage: 9.4, voteCount: 8000, firstAired: days(4000)),
            sample("alpha", title: "Alpha", year: 2025, popularity: 400, voteAverage: 6.0, voteCount: 900, lastAired: days(3)),
            sample("mike", title: "Mike", year: 2019, popularity: 60, voteAverage: 8.1, voteCount: 200, firstAired: days(2000)),
        ]
        XCTAssertEqual(CatalogRanking.sort(entries, by: .popular, now: now).first?.title, "Alpha")
        XCTAssertEqual(CatalogRanking.sort(entries, by: .newest, now: now).first?.title, "Alpha")
        XCTAssertEqual(CatalogRanking.sort(entries, by: .oldest, now: now).first?.title, "Zulu")
        XCTAssertEqual(CatalogRanking.sort(entries, by: .rating, now: now).first?.title, "Zulu")
        XCTAssertEqual(CatalogRanking.sort(entries, by: .titleAscending, now: now).map(\.title), ["Alpha", "Mike", "Zulu"])
        XCTAssertEqual(CatalogRanking.sort(entries, by: .titleDescending, now: now).map(\.title), ["Zulu", "Mike", "Alpha"])
    }

    func testOrderIsStableForEqualScores() {
        // Ohne zweiten Schlüssel sortierte sich das Raster bei jedem Aufbau
        // anders.
        let entries = [sample("b", title: "Gleich"), sample("a", title: "Gleich")]
        let first = CatalogRanking.sort(entries, by: .popular, now: now)
        let second = CatalogRanking.sort(entries.reversed(), by: .popular, now: now)
        XCTAssertEqual(ids(first), ids(second))
    }

    // MARK: - Filter

    private var mixed: [CatalogEntry] {
        [
            sample("anime-fantasy", provider: .aniworld, title: "Anime Fantasy", year: 2022,
                  genres: ["Fantasy", "Action"], status: .completed, languages: [.german, .gerSub],
                  voteAverage: 8.4, voteCount: 4000),
            sample("anime-new", provider: .aniworld, title: "Anime Neu", year: 2025,
                  genres: ["Fantasy"], status: .running, languages: [.gerSub], fresh: true),
            sample("serie-drama", provider: .serienstream, title: "Serien Drama", year: 2019,
                  genres: ["Drama"], status: .running, languages: [.german],
                  popularity: 120, voteAverage: 7.6, voteCount: 12_000),
            sample("serie-alt", provider: .serienstream, title: "Serien Alt", year: 2001,
                  genres: ["Krimi"], languages: [.german]),
        ]
    }

    func testContentFilter() {
        var query = CatalogQuery()
        query.filters.mediaType = .anime
        XCTAssertEqual(Set(ids(CatalogEngine.results(for: query, in: mixed, now: now))),
                       ["aniworld|anime-fantasy", "aniworld|anime-new"])
        query.filters.mediaType = .series
        XCTAssertEqual(Set(ids(CatalogEngine.results(for: query, in: mixed, now: now))),
                       ["serienstream|serie-drama", "serienstream|serie-alt"])
    }

    func testStatusFilterIgnoresUnknownStatus() {
        var query = CatalogQuery()
        query.filters.status = .running
        XCTAssertEqual(Set(ids(CatalogEngine.results(for: query, in: mixed, now: now))),
                       ["aniworld|anime-new", "serienstream|serie-drama"])
        query.filters.status = .completed
        XCTAssertEqual(ids(CatalogEngine.results(for: query, in: mixed, now: now)), ["aniworld|anime-fantasy"])
    }

    func testGenreFilterIsAnOrOverSeveralGenres() {
        var query = CatalogQuery()
        query.filters.genres = ["Fantasy", "Drama"]
        XCTAssertEqual(Set(ids(CatalogEngine.results(for: query, in: mixed, now: now))),
                       ["aniworld|anime-fantasy", "aniworld|anime-new", "serienstream|serie-drama"])
    }

    func testLanguageFilterUsesProviderAvailability() {
        var query = CatalogQuery()
        query.filters.language = .gerSub
        XCTAssertEqual(Set(ids(CatalogEngine.results(for: query, in: mixed, now: now))),
                       ["aniworld|anime-fantasy", "aniworld|anime-new"])
    }

    func testYearFilter() {
        var query = CatalogQuery()
        query.filters.years = 2020 ... 2026
        XCTAssertEqual(Set(ids(CatalogEngine.results(for: query, in: mixed, now: now))),
                       ["aniworld|anime-fantasy", "aniworld|anime-new"])
    }

    func testCombinedFiltersWorkTogether() {
        // Anime + Fantasy + abgeschlossen + ab 2020 + nach Bewertung.
        var query = CatalogQuery()
        query.filters.mediaType = .anime
        query.filters.genres = ["Fantasy"]
        query.filters.status = .completed
        query.filters.years = 2020 ... 2026
        query.sort = .rating
        XCTAssertEqual(ids(CatalogEngine.results(for: query, in: mixed, now: now)), ["aniworld|anime-fantasy"])
    }

    func testSearchAndFiltersCombine() {
        var query = CatalogQuery()
        query.text = "serien"
        query.filters.genres = ["Drama"]
        XCTAssertEqual(ids(CatalogEngine.results(for: query, in: mixed, now: now)), ["serienstream|serie-drama"])
    }

    func testImpossibleCombinationYieldsNothing() {
        var query = CatalogQuery()
        query.filters.mediaType = .anime
        query.filters.genres = ["Krimi"]
        XCTAssertTrue(CatalogEngine.results(for: query, in: mixed, now: now).isEmpty)
    }

    // MARK: - Facetten

    func testFacetsComeFromTheDataNotFromAList() {
        let facets = CatalogFacets.of(mixed)
        XCTAssertEqual(facets.years, 2001 ... 2025)
        XCTAssertEqual(facets.statuses, [.running, .completed])
        XCTAssertEqual(facets.languages, [.german, .gerSub])
        XCTAssertEqual(facets.mediaTypes, [.anime, .series])
        XCTAssertEqual(facets.genres.first?.label, "Fantasy")
        XCTAssertEqual(facets.genres.first?.count, 2)
    }

    func testStatusIsNotOfferedWhenNothingIsKnown() {
        let blind = [sample("a"), sample("b")]
        XCTAssertTrue(CatalogFacets.of(blind).statuses.isEmpty)
        XCTAssertTrue(CatalogFacets.of(blind).languages.isEmpty)
        XCTAssertNil(CatalogFacets.of(blind).years)
    }

    // MARK: - Abzeichen

    func testBadgesOnlyClaimWhatIsTrue() {
        let top = sample("top", trendingRank: 4)
        XCTAssertEqual(CatalogRanking.badges(for: top, now: now, showsKind: false), [.top(4)])

        let rank11 = sample("eleven", trendingRank: 11, firstAired: days(400), lastAired: days(400))
        XCTAssertTrue(CatalogRanking.badges(for: rank11, now: now, showsKind: false).isEmpty)

        let done = sample("done", status: .completed)
        XCTAssertEqual(CatalogRanking.badges(for: done, now: now, showsKind: false), [.complete])

        let plain = sample("plain")
        XCTAssertTrue(CatalogRanking.badges(for: plain, now: now, showsKind: false).isEmpty)
    }

    func testKindBadgeOnlyInAMixedGrid() {
        let show = sample("x", provider: .serienstream)
        XCTAssertEqual(CatalogRanking.badges(for: show, now: now, showsKind: true), [.kind(.series)])
        XCTAssertTrue(CatalogRanking.badges(for: show, now: now, showsKind: false).isEmpty)
    }

    // MARK: - Entdecken

    func testDiscoverStaysInsideTheResultSet() {
        var generator = SystemRandomNumberGenerator()
        var query = CatalogQuery()
        query.filters.mediaType = .anime
        query.filters.genres = ["Fantasy"]
        let results = CatalogEngine.results(for: query, in: mixed, now: now)
        for _ in 0 ..< 40 {
            let pick = CatalogEngine.discover(in: results, using: &generator)
            XCTAssertNotNil(pick)
            XCTAssertTrue(results.contains { $0.id == pick?.id })
        }
    }

    func testDiscoverDoesNotRepeatItself() {
        var generator = SystemRandomNumberGenerator()
        let results = mixed
        for _ in 0 ..< 40 {
            let pick = CatalogEngine.discover(in: results, excluding: results[0].id, using: &generator)
            XCTAssertNotEqual(pick?.id, results[0].id)
        }
    }

    func testDiscoverOnEmptyResultsIsNothing() {
        var generator = SystemRandomNumberGenerator()
        XCTAssertNil(CatalogEngine.discover(in: [], using: &generator))
    }

    // MARK: - Aufbau aus Providerlisten

    func testCatalogIsBuiltFromProvidersNotFromTMDB() {
        let items = [item("one", "Nur bei Nori", provider: .aniworld)]
        var context = CatalogBuilder.Context()
        // Eine TMDB-Zeile, die Nori gar nicht führt.
        context.popular = [TMDBCandidate(id: 99, name: "Gibt es bei Nori nicht", popularity: 900)]
        let built = CatalogBuilder.build(items, context: context, now: now)
        XCTAssertEqual(built.count, 1)
        XCTAssertEqual(built[0].title, "Nur bei Nori")
    }

    func testCatalogWorksWithoutTMDB() {
        let items = [
            item("a", "Alpha", provider: .aniworld, genres: ["Fantasy"]),
            item("b", "Beta", provider: .serienstream, genres: ["Drama"]),
        ]
        let built = CatalogBuilder.build(items, context: CatalogBuilder.Context(), now: now)
        XCTAssertEqual(built.count, 2)
        XCTAssertEqual(Set(built.map(\.title)), ["Alpha", "Beta"])
        XCTAssertTrue(built.allSatisfy { $0.signals.isEmpty })
        XCTAssertTrue(built.allSatisfy { $0.status == .unknown })
        // Und die Genres der Quelle stehen trotzdem zur Verfügung.
        XCTAssertEqual(CatalogFacets.of(built).genres.map(\.label).sorted(), ["Drama", "Fantasy"])
    }

    func testTMDBEnrichesMatchingTitles() {
        let items = [item("hunter", "Hunter x Hunter", provider: .aniworld)]
        var context = CatalogBuilder.Context()
        context.trending = [
            TMDBCandidate(
                id: 11,
                name: "Hunter x Hunter",
                originalName: "ハンター×ハンター",
                firstAirYear: 2011,
                firstAirDate: TMDBCandidate.date("2011-10-02"),
                popularity: 88,
                voteAverage: 8.8,
                voteCount: 3000,
                genreIDs: [16, 10759],
                originCountries: ["JP"]
            )
        ]
        let built = CatalogBuilder.build(items, context: context, now: now)
        XCTAssertEqual(built.count, 1)
        let show = built[0]
        XCTAssertEqual(show.tmdbID, 11)
        XCTAssertEqual(show.year, 2011)
        XCTAssertEqual(show.signals.trendingRank, 1)
        XCTAssertEqual(show.stars.map { ($0 * 10).rounded() / 10 }, 4.4)
        XCTAssertTrue(show.genres.contains("Animation"))
        XCTAssertTrue(show.genres.contains("Action"))
    }

    func testCalendarSuppliesLanguagesFreshnessAndStatus() {
        let items = [item("laufend", "Laufend", provider: .aniworld)]
        var context = CatalogBuilder.Context()
        context.calendar = [
            airing(slug: "laufend", provider: .aniworld, daysAgo: 3, languages: ["DE"]),
            airing(slug: "laufend", provider: .aniworld, daysAgo: 10, languages: ["GerSub"]),
        ]
        let built = CatalogBuilder.build(items, context: context, now: now)
        XCTAssertEqual(built[0].languages, [.german, .gerSub])
        XCTAssertTrue(built[0].hasFreshEpisode)
        XCTAssertEqual(built[0].status, .running)
        XCTAssertTrue(CatalogRanking.isNew(built[0], now: now))
    }

    func testEndedListMarksCompletedTitles() {
        let items = [item("schluss", "Schluss", provider: .serienstream)]
        var context = CatalogBuilder.Context()
        context.ended = [TMDBCandidate(id: 7, name: "Schluss", originCountries: ["US"])]
        let built = CatalogBuilder.build(items, context: context, now: now)
        XCTAssertEqual(built[0].status, .completed)
    }

    func testKnownIDsAndRatingsFromTheCoverIndexCount() {
        let items = [item("cover", "Cover", provider: .aniworld)]
        var context = CatalogBuilder.Context()
        context.knownIDs = ["cover": 42]
        context.knownRatings = ["cover": 7.4]
        let built = CatalogBuilder.build(items, context: context, now: now)
        XCTAssertEqual(built[0].tmdbID, 42)
        XCTAssertEqual(built[0].rating, 7.4)
    }

    func testYearFallsBackToTheTitleSuffix() {
        let items = [item("bsg", "Battlestar Galactica (2003)", provider: .serienstream)]
        let built = CatalogBuilder.build(items, context: CatalogBuilder.Context(), now: now)
        XCTAssertEqual(built[0].year, 2003)
        // Und die Jahreszahl steht nicht mehr in der Überschrift der Kachel.
        XCTAssertEqual(built[0].title, "Battlestar Galactica")
    }

    // MARK: - Dubletten

    func testSameTitleOnBothProvidersBecomesOneEntry() {
        let items = [
            item("alice", "Alice in Borderland", provider: .aniworld, genres: ["Mystery"]),
            item("alice-in-borderland", "Alice In Borderland", provider: .serienstream, genres: ["Thriller"]),
        ]
        let built = CatalogBuilder.build(items, context: CatalogBuilder.Context(), now: now)
        XCTAssertEqual(built.count, 1)
        XCTAssertEqual(built[0].sources.count, 2)
        XCTAssertEqual(built[0].mediaTypes, [.anime, .series])
        // Beide Genrelisten stehen danach am selben Eintrag.
        XCTAssertEqual(Set(built[0].genres), ["Mystery", "Thriller"])
    }

    func testMergedEntryAppearsUnderBothContentFilters() {
        let items = [
            item("doppelt", "Doppelt", provider: .aniworld),
            item("doppelt", "Doppelt", provider: .serienstream),
        ]
        let built = CatalogBuilder.build(items, context: CatalogBuilder.Context(), now: now)
        XCTAssertEqual(built.count, 1)
        for type in [CatalogMediaType.anime, .series] {
            var query = CatalogQuery()
            query.filters.mediaType = type
            XCTAssertEqual(CatalogEngine.results(for: query, in: built, now: now).count, 1)
        }
    }

    func testSeasonsOfTheSameProviderStaySeparateTitles() {
        // AniWorld führt beide als eigene Titel mit eigenen Folgenlisten.
        // Zusammenzufassen hieße, einen davon aus dem Katalog zu entfernen.
        let items = [
            item("aot", "Attack on Titan", provider: .aniworld),
            item("aot-final", "Attack on Titan: Final Season", provider: .aniworld),
        ]
        let built = CatalogBuilder.build(items, context: CatalogBuilder.Context(), now: now)
        XCTAssertEqual(built.count, 2)
    }

    func testRemakesWithDifferentYearsAreNotMerged() {
        let items = [
            item("bsg-1978", "Battlestar Galactica (1978)", provider: .aniworld),
            item("bsg-2003", "Battlestar Galactica (2003)", provider: .serienstream),
        ]
        let built = CatalogBuilder.build(items, context: CatalogBuilder.Context(), now: now)
        XCTAssertEqual(built.count, 2)
    }

    func testTMDBIdentifierMergesDifferentSpellings() {
        let items = [
            item("kaisen", "Jujutsu Kaisen", provider: .aniworld),
            item("jjk", "Jujutsu Kaisen - Ein Kampf der Zauberer", provider: .serienstream),
        ]
        var context = CatalogBuilder.Context()
        context.knownIDs = ["kaisen": 95479, "jjk": 95479]
        let built = CatalogBuilder.build(items, context: context, now: now)
        XCTAssertEqual(built.count, 1)
        XCTAssertEqual(built[0].sources.count, 2)
    }

    func testMergePrefersTheBetterKnownSourceForNavigation() {
        let items = [
            item("arm", "Gleicher Titel", provider: .serienstream),
            item("reich", "Gleicher Titel", provider: .aniworld),
        ]
        var context = CatalogBuilder.Context()
        context.knownIDs = ["reich": 5]
        context.knownRatings = ["reich": 8.0]
        let built = CatalogBuilder.build(items, context: context, now: now)
        XCTAssertEqual(built.count, 1)
        XCTAssertEqual(built[0].provider, .aniworld)
        XCTAssertEqual(built[0].slug, "reich")
    }

    // MARK: - Große Mengen

    func testManyEntriesStayCorrectAndFast() {
        var items: [CatalogItem] = []
        for index in 0 ..< 4000 {
            items.append(item("slug-\(index)", "Titel \(index)", provider: index.isMultiple(of: 2) ? .aniworld : .serienstream, genres: ["Drama"]))
        }
        let built = CatalogBuilder.build(items, context: CatalogBuilder.Context(), now: now)
        XCTAssertEqual(built.count, 4000)

        var query = CatalogQuery()
        query.text = "titel 1999"
        let results = CatalogEngine.results(for: query, in: built, now: now)
        XCTAssertEqual(results.map(\.title), ["Titel 1999"])
    }
}

/// Die Sortierung auf einem Bestand in Kataloggröße.
///
/// Eigene Klasse, weil sie einen anderen Fall prüft als die Beispiele oben:
/// dort stehen drei Titel mit vollständigen Angaben nebeneinander, hier
/// stehen ein paar Hundert mit Datum zwischen Tausenden ohne. Genau in
/// dieser Mischung fiel beim Durchsehen im Simulator auf, dass sich die
/// Reihenfolge nicht mehr von selbst versteht.
final class CatalogLargeSortTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// 3000 Titel, jeder zehnte mit Erstausstrahlung.
    private func bulk() -> [CatalogEntry] {
        var items: [CatalogItem] = []
        for index in 0 ..< 3000 {
            items.append(CatalogItem(
                slug: "slug-\(index)",
                title: "Titel \(String(format: "%04d", index))",
                alts: [],
                genres: ["Drama"],
                provider: .aniworld
            ))
        }
        var context = CatalogBuilder.Context()
        var rows: [TMDBCandidate] = []
        for index in stride(from: 0, to: 3000, by: 10) {
            let year = 1990 + (index / 10) % 36
            rows.append(TMDBCandidate(
                id: 100_000 + index,
                name: "Titel \(String(format: "%04d", index))",
                firstAirYear: year,
                firstAirDate: TMDBCandidate.date("\(year)-06-01"),
                popularity: Double(index % 97),
                voteAverage: 5 + Double(index % 5),
                voteCount: 100 + index
            ))
        }
        context.popular = rows
        return CatalogBuilder.build(items, context: context, now: now)
    }

    func testNewestPutsEveryDatedTitleBeforeEveryUndatedOne() {
        let entries = bulk()
        let sorted = CatalogRanking.sort(entries, by: .newest, now: now)
        XCTAssertEqual(sorted.count, 3000)

        let dated = sorted.prefix { CatalogRanking.releaseReference($0) != nil }
        XCTAssertEqual(dated.count, 300, "jeder zehnte Titel trägt ein Datum")
        // Und im vorderen Teil geht es lückenlos abwärts.
        var last = Date.distantFuture
        for entry in dated {
            guard let reference = CatalogRanking.releaseReference(entry) else { continue }
            XCTAssertLessThanOrEqual(reference, last)
            last = reference
        }
        // Dahinter steht nichts mit Datum mehr.
        for entry in sorted.dropFirst(dated.count) {
            XCTAssertNil(CatalogRanking.releaseReference(entry))
        }
    }

    func testPopularPutsEveryRankedTitleBeforeEveryUnrankedOne() {
        let entries = bulk()
        let sorted = CatalogRanking.sort(entries, by: .popular, now: now)
        var last = Double.greatestFiniteMagnitude
        var seenZero = false
        for entry in sorted {
            let score = CatalogRanking.popularityScore(entry)
            if score == 0 { seenZero = true; continue }
            XCTAssertFalse(seenZero, "nach dem ersten Titel ohne Signal darf keiner mit Signal mehr kommen")
            XCTAssertLessThanOrEqual(score, last)
            last = score
        }
    }

    /// Der Fall, der im Simulator auffiel.
    ///
    /// Alle drei Titel stehen in TMDBs Liste kürzlich ausgestrahlter Serien
    /// und tragen deshalb dieselbe grobe Ersatzzeit. Ohne zweiten Schlüssel
    /// entschied dann der Titel — und „Neueste" zeigte eine alphabetische
    /// Reihe, in der die Jahreszahlen von 2026 auf 1996 sprangen.
    func testTitlesWithTheSameCoarseAirDateFallBackToThePremiere() {
        let items = [
            CatalogItem(slug: "alt", title: "Alt Detektiv", alts: [], genres: [], provider: .aniworld),
            CatalogItem(slug: "mittel", title: "Mittel Serie", alts: [], genres: [], provider: .aniworld),
            CatalogItem(slug: "neu", title: "Zuletzt Gestartet", alts: [], genres: [], provider: .aniworld),
        ]
        var context = CatalogBuilder.Context()
        context.airing = [
            TMDBCandidate(id: 1, name: "Alt Detektiv", firstAirDate: TMDBCandidate.date("1996-01-08")),
            TMDBCandidate(id: 2, name: "Mittel Serie", firstAirDate: TMDBCandidate.date("2004-10-05")),
            TMDBCandidate(id: 3, name: "Zuletzt Gestartet", firstAirDate: TMDBCandidate.date("2026-04-01")),
        ]
        let built = CatalogBuilder.build(items, context: context, now: now)
        // Alle drei haben dieselbe letzte Ausstrahlung — das ist die Absicht
        // der Liste, nicht ein Fehler.
        XCTAssertEqual(Set(built.map { $0.signals.lastAirDate }).count, 1)

        let sorted = CatalogRanking.sort(built, by: .newest, now: now)
        XCTAssertEqual(sorted.map(\.title), ["Zuletzt Gestartet", "Mittel Serie", "Alt Detektiv"])

        let reversed = CatalogRanking.sort(built, by: .oldest, now: now)
        XCTAssertEqual(reversed.map(\.title), ["Alt Detektiv", "Mittel Serie", "Zuletzt Gestartet"])
    }

    func testYearShownOnACardAlwaysHasASortableDate() {
        // Beide Angaben stammen aus derselben Quelle. Stünde auf einer Kachel
        // ein Jahr, ohne dass die Sortierung eines kennt, sähe „Neueste" wie
        // eine alphabetische Liste aus — und genau so sah es einmal aus.
        for entry in bulk() where entry.year != nil {
            XCTAssertNotNil(CatalogRanking.releaseReference(entry))
        }
    }
}
