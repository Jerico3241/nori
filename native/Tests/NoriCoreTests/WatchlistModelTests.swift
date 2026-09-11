import XCTest
@testable import NoriCore

/// Die Rechnung hinter der Merkliste: Status, Fortschritt, Suche, Filter,
/// Sortierung.
///
/// Diese Regeln lassen sich in der Oberfläche nur von Hand prüfen, und
/// gerade die Statusgrenzen sind die, die sich leise verschieben — „noch
/// nicht fertig" gegen „noch nie angesehen" ist genau der Fehler, der einen
/// Filter dauerhaft leer laufen lässt, ohne dass irgendwo etwas rot wird.
final class WatchlistModelTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-watchlist-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func progress(
        slug: String = "demo",
        season: String = "1",
        episode: Int,
        position: Double,
        duration: Double = 1400,
        updatedAt: Double,
        completed: Bool? = nil,
        provider: CatalogProvider = .aniworld
    ) -> WatchProgress {
        WatchProgress(
            slug: slug,
            title: slug,
            season: season,
            episode: episode,
            episodePath: provider.episodePath(slug: slug, season: season, episode: episode),
            germanTitle: "Folge \(episode)",
            englishTitle: "Episode \(episode)",
            positionSec: position,
            durationSec: duration,
            updatedAt: updatedAt,
            lang: "DE",
            completed: completed,
            provider: provider
        )
    }

    // MARK: - Status

    func testWithoutProgressATitleIsUnseen() {
        XCTAssertEqual(watchSummary(for: []).state, .unseen)
        XCTAssertEqual(watchSummary(for: []).ratio, 0)
    }

    /// Eine Folge, die nur geöffnet wurde, ist kein Anfang. Sonst genügte ein
    /// Fehlklick, um den Titel aus „Ungesehen" zu nehmen.
    func testOpeningAnEpisodeWithoutWatchingStaysUnseen() {
        let summary = watchSummary(for: [progress(episode: 1, position: 0, updatedAt: 10)])
        XCTAssertEqual(summary.state, .unseen)
    }

    func testPartlyWatchedIsStartedNotUnseen() {
        let summary = watchSummary(for: [progress(episode: 7, position: 700, duration: 1400, updatedAt: 20)])
        XCTAssertEqual(summary.state, .started)
        XCTAssertEqual(summary.ratio, 0.5, accuracy: 0.0001)
        XCTAssertEqual(summary.episode, 7)
        XCTAssertEqual(summary.season, "1")
        XCTAssertEqual(summary.stateText, "S1 · F7 · 50 %")
    }

    /// Der wichtigste Fall: viele Folgen fertig, eine noch offen. Das ist
    /// angefangen — nicht ungesehen und nicht gesehen.
    func testManyFinishedEpisodesWithOneOpenIsStarted() {
        let entries = [
            progress(episode: 1, position: 1400, updatedAt: 1, completed: true),
            progress(episode: 2, position: 1400, updatedAt: 2, completed: true),
            progress(episode: 3, position: 420, updatedAt: 3),
        ]
        let summary = watchSummary(for: entries)
        XCTAssertEqual(summary.state, .started)
        XCTAssertEqual(summary.completedEpisodes, 2)
        XCTAssertEqual(summary.episode, 3)
        XCTAssertEqual(summary.ratio, 0.3, accuracy: 0.0001)
    }

    func testEveryKnownEpisodeCompleteMeansSeen() {
        let entries = [
            progress(episode: 1, position: 1400, updatedAt: 1, completed: true),
            progress(episode: 2, position: 1400, updatedAt: 2, completed: true),
        ]
        let summary = watchSummary(for: entries)
        XCTAssertEqual(summary.state, .seen)
        XCTAssertEqual(summary.ratio, 1)
        XCTAssertEqual(summary.stateText, "Komplett gesehen")
    }

    /// Die 90-%-Regel des Contracts gilt auch hier: sie steht in
    /// `isEpisodeComplete`, und der Status rechnet nicht daneben nach.
    func testNinetyPercentCountsAsCompleteWithoutTheFlag() {
        let summary = watchSummary(for: [progress(episode: 1, position: 1300, duration: 1400, updatedAt: 1)])
        XCTAssertEqual(summary.state, .seen)
    }

    /// Steht die zuletzt gesehene Folge auf „fertig", während eine frühere
    /// offen ist, zeigt der Balken die frühere — er darf nicht auf 100 %
    /// stehen, solange etwas aussteht.
    func testLatestEpisodeCompleteButEarlierOneOpenShowsTheOpenOne() {
        let entries = [
            progress(episode: 4, position: 200, updatedAt: 5),
            progress(episode: 5, position: 1400, updatedAt: 9, completed: true),
        ]
        let summary = watchSummary(for: entries)
        XCTAssertEqual(summary.state, .started)
        XCTAssertEqual(summary.episode, 4)
        XCTAssertEqual(summary.lastWatched, 9)
    }

    func testMovieSeasonGetsItsOwnLabel() {
        let summary = watchSummary(for: [progress(season: "filme", episode: 2, position: 350, updatedAt: 1)])
        XCTAssertEqual(summary.stateText, "Filme · F2 · 25 %")
    }

    // MARK: - Aufbau aus dem Store

    func testItemsComeFromFavoritesAndKeepProviderApart() {
        let store = LibraryStore(directory: directory)
        store.provider = .aniworld
        store.toggleFavorite("demo", title: "Demo")
        store.provider = .serienstream
        store.toggleFavorite("serie", title: "Serie")

        // Derselbe Slug, andere Quelle: der Fortschritt darf nicht
        // hinüberlaufen.
        store.upsert(progress(episode: 1, position: 700, updatedAt: 5, provider: .aniworld))
        store.upsert(progress(slug: "serie", episode: 1, position: 0, updatedAt: 6, provider: .serienstream))

        let items = store.watchlistItems()
        XCTAssertEqual(items.count, 2)
        let demo = try! XCTUnwrap(items.first { $0.slug == "demo" })
        let serie = try! XCTUnwrap(items.first { $0.slug == "serie" })
        XCTAssertEqual(demo.provider, .aniworld)
        XCTAssertEqual(demo.watch.state, .started)
        XCTAssertEqual(serie.provider, .serienstream)
        XCTAssertEqual(serie.watch.state, .unseen)
    }

    func testProgressOfTheOtherProviderDoesNotCount() {
        let store = LibraryStore(directory: directory)
        store.provider = .serienstream
        store.toggleFavorite("demo", title: "Demo")
        // Gemerkt ist der Serienstream-Titel, gesehen wurde der bei AniWorld.
        store.upsert(progress(episode: 3, position: 900, updatedAt: 7, provider: .aniworld))

        let items = store.watchlistItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].watch.state, .unseen)
    }

    func testCatalogOnlyAddsMetadataAndNeverDecidesMembership() {
        let store = LibraryStore(directory: directory)
        store.toggleFavorite("demo", title: "Demo")
        let catalog = [
            CatalogItem(slug: "demo", title: "Demo", alts: ["Demo Original"], genres: ["Fantasy", "Mystery"], provider: .aniworld),
            CatalogItem(slug: "other", title: "Other", alts: [], genres: [], provider: .aniworld),
        ]
        let withCatalog = store.watchlistItems(catalog: catalog)
        XCTAssertEqual(withCatalog.count, 1)
        XCTAssertEqual(withCatalog[0].genres, ["Fantasy", "Mystery"])
        XCTAssertEqual(withCatalog[0].metaText, "Fantasy · Mystery")

        // Ohne Katalog bleibt der Titel stehen — nur ohne Genres.
        let withoutCatalog = store.watchlistItems()
        XCTAssertEqual(withoutCatalog.count, 1)
        XCTAssertEqual(withoutCatalog[0].title, "Demo")
        XCTAssertTrue(withoutCatalog[0].genres.isEmpty)
        XCTAssertEqual(withoutCatalog[0].metaText, "Anime")
    }

    // MARK: - Merkzeitpunkt

    func testAddedAtIsRecordedAndSurvivesAReload() throws {
        let store = LibraryStore(directory: directory)
        let before = Date().timeIntervalSince1970 * 1000
        store.toggleFavorite("demo", title: "Demo")
        let stamp = try XCTUnwrap(store.addedAt("demo"))
        XCTAssertGreaterThanOrEqual(stamp, before)

        let reloaded = LibraryStore(directory: directory)
        XCTAssertEqual(reloaded.addedAt("demo"), stamp)
    }

    /// Ein Stand aus v4 kennt das Feld nicht. Er darf seine Reihenfolge nicht
    /// verlieren — sie ist die einzige Auskunft darüber, was zuletzt gemerkt
    /// wurde.
    func testOlderLibraryDerivesAddedAtFromTheExistingOrder() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"version":4,"favorites":["neu","mittel","alt"],"recents":[],"titles":{},"progress":{}}
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("library.json"))

        let store = LibraryStore(directory: directory)
        let neu = try XCTUnwrap(store.addedAt("neu"))
        let mittel = try XCTUnwrap(store.addedAt("mittel"))
        let alt = try XCTUnwrap(store.addedAt("alt"))
        XCTAssertGreaterThan(neu, mittel)
        XCTAssertGreaterThan(mittel, alt)

        let sorted = sortWatchlist(store.watchlistItems(), by: .added).map(\.slug)
        XCTAssertEqual(sorted, ["neu", "mittel", "alt"])
    }

    /// Ein abgeleiteter Zeitpunkt darf keinen echten überholen.
    func testDerivedStampsStayBelowKnownOnes() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"version":4,"favorites":["ohne","mit"],"recents":[],"titles":{},"progress":{},
         "favoriteAddedAt":{"mit":1000000}}
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("library.json"))

        let store = LibraryStore(directory: directory)
        XCTAssertEqual(store.addedAt("mit"), 1_000_000)
        XCTAssertLessThan(try XCTUnwrap(store.addedAt("ohne")), 1_000_000)
    }

    func testRemovingAFavoriteKeepsWatchProgress() {
        let store = LibraryStore(directory: directory)
        store.toggleFavorite("demo", title: "Demo")
        store.upsert(progress(episode: 2, position: 600, updatedAt: 4))
        XCTAssertEqual(store.progress.count, 1)

        store.removeFavorite("demo")
        XCTAssertFalse(store.isFavorite("demo"))
        XCTAssertEqual(store.progress.count, 1, "Merkliste und Verlauf sind getrennt.")
        XCTAssertEqual(store.recents.count, 0)

        let reloaded = LibraryStore(directory: directory)
        XCTAssertEqual(reloaded.progress.count, 1)
        XCTAssertFalse(reloaded.isFavorite("demo"))
    }

    func testUndoPutsTheTitleBackWhereItWas() throws {
        let store = LibraryStore(directory: directory)
        store.toggleFavorite("a", title: "A")
        store.toggleFavorite("b", title: "B")
        store.toggleFavorite("c", title: "C")
        XCTAssertEqual(store.favorites, ["c", "b", "a"])
        let stamp = try XCTUnwrap(store.addedAt("b"))

        let snapshot = try XCTUnwrap(store.removeFavorite("b"))
        XCTAssertEqual(store.favorites, ["c", "a"])
        store.restoreFavorite(snapshot)
        XCTAssertEqual(store.favorites, ["c", "b", "a"])
        XCTAssertEqual(store.addedAt("b"), stamp)
    }

    /// `favoriteAddedAt` darf nicht mitwachsen, wenn Titel gehen und kommen.
    func testStampsOfRemovedTitlesAreNotKept() throws {
        let store = LibraryStore(directory: directory)
        store.toggleFavorite("a", title: "A")
        store.toggleFavorite("b", title: "B")
        store.removeFavorite("a")
        let reloaded = LibraryStore(directory: directory)
        XCTAssertEqual(Set(reloaded.favoriteAddedAt.keys), ["b"])
    }

    // MARK: - Suche, Filter, Sortierung

    private func item(
        _ slug: String,
        title: String,
        provider: CatalogProvider = .aniworld,
        genres: [String] = [],
        alts: [String] = [],
        addedAt: Double,
        watch: WatchSummary = .none
    ) -> WatchlistItem {
        WatchlistItem(
            slug: slug,
            provider: provider,
            title: title,
            alternateTitles: alts,
            genres: genres,
            addedAt: addedAt,
            watch: watch
        )
    }

    private var sample: [WatchlistItem] {
        [
            item("a", title: "Azure Signal", genres: ["Sci-Fi", "Action"], addedAt: 600,
                 watch: WatchSummary(state: .started, ratio: 0.31, season: "1", episode: 3, completedEpisodes: 2, lastWatched: 90)),
            item("b", title: "Crimson Veil", provider: .serienstream, genres: ["Drama"], alts: ["Roter Schleier"], addedAt: 700),
            item("c", title: "Falling Ember", genres: ["Fantasy"], addedAt: 500,
                 watch: WatchSummary(state: .seen, ratio: 1, season: "2", episode: 12, completedEpisodes: 12, lastWatched: 50)),
            item("d", title: "Night Protocol", provider: .serienstream, genres: ["Action"], addedAt: 400),
        ]
    }

    func testStatsCountTheWholeListNotTheFilteredOne() {
        let stats = watchlistStats(sample)
        XCTAssertEqual(stats.saved, 4)
        XCTAssertEqual(stats.unseen, 2)
        XCTAssertEqual(stats.started, 1)
        XCTAssertEqual(stats.seen, 1)
    }

    func testQuickFilterSelectsByState() {
        XCTAssertEqual(watchlistResults(sample, query: "", quick: .all, filters: .none).count, 4)
        XCTAssertEqual(watchlistResults(sample, query: "", quick: .unseen, filters: .none).map(\.slug), ["b", "d"])
        XCTAssertEqual(watchlistResults(sample, query: "", quick: .started, filters: .none).map(\.slug), ["a"])
        XCTAssertEqual(watchlistResults(sample, query: "", quick: .seen, filters: .none).map(\.slug), ["c"])
    }

    func testSearchCoversTitleAlternatesAndGenre() {
        XCTAssertEqual(watchlistResults(sample, query: "azure", quick: .all, filters: .none).map(\.slug), ["a"])
        XCTAssertEqual(watchlistResults(sample, query: "schleier", quick: .all, filters: .none).map(\.slug), ["b"])
        XCTAssertEqual(
            Set(watchlistResults(sample, query: "action", quick: .all, filters: .none).map(\.slug)),
            ["a", "d"]
        )
        XCTAssertTrue(watchlistResults(sample, query: "gibtesnicht", quick: .all, filters: .none).isEmpty)
    }

    func testKindFilterLivesInTheSheetAndCombinesWithTheQuickFilter() {
        var filters = WatchlistFilters(kind: .serien)
        XCTAssertEqual(watchlistResults(sample, query: "", quick: .all, filters: filters).map(\.slug), ["b", "d"])
        XCTAssertEqual(watchlistResults(sample, query: "", quick: .unseen, filters: filters).map(\.slug), ["b", "d"])
        filters.kind = .anime
        XCTAssertEqual(watchlistResults(sample, query: "", quick: .started, filters: filters).map(\.slug), ["a"])
        XCTAssertEqual(watchlistResults(sample, query: "", quick: .seen, filters: filters).map(\.slug), ["c"])
    }

    func testKindStateAndSortCombine() {
        let filters = WatchlistFilters(kind: .anime, state: .started, sort: .progress)
        let result = watchlistResults(sample, query: "", quick: .all, filters: filters)
        XCTAssertEqual(result.map(\.slug), ["a"])
    }

    func testContradictingFiltersGiveNoResultsRatherThanTheWrongOnes() {
        let filters = WatchlistFilters(state: .unseen)
        XCTAssertTrue(watchlistResults(sample, query: "", quick: .seen, filters: filters).isEmpty)
    }

    func testGenreFilterUsesOnlyGenresThatOccur() {
        XCTAssertEqual(watchlistGenres(sample), ["Action", "Drama", "Fantasy", "Sci-Fi"])
        let filters = WatchlistFilters(genre: "action")
        XCTAssertEqual(
            Set(watchlistResults(sample, query: "", quick: .all, filters: filters).map(\.slug)),
            ["a", "d"]
        )
    }

    func testSortOrders() {
        XCTAssertEqual(sortWatchlist(sample, by: .added).map(\.slug), ["b", "a", "c", "d"])
        XCTAssertEqual(sortWatchlist(sample, by: .title).map(\.slug), ["a", "b", "c", "d"])
        // Fortschritt: abgeschlossene Folgen führen, dann der Stand darin.
        XCTAssertEqual(sortWatchlist(sample, by: .progress).map(\.slug), ["c", "a", "b", "d"])
        // Zuletzt angesehen: nie Angesehenes ans Ende, dort nach Merkzeitpunkt.
        XCTAssertEqual(sortWatchlist(sample, by: .lastWatched).map(\.slug), ["a", "c", "b", "d"])
    }

    func testProgressSortPrefersMoreFinishedEpisodesOverAHigherPositionInOne() {
        let deep = item("deep", title: "Deep", addedAt: 1,
                        watch: WatchSummary(state: .started, ratio: 0.1, season: "1", episode: 40, completedEpisodes: 39))
        let shallow = item("shallow", title: "Shallow", addedAt: 2,
                           watch: WatchSummary(state: .started, ratio: 0.9, season: "1", episode: 1, completedEpisodes: 0))
        XCTAssertEqual(sortWatchlist([shallow, deep], by: .progress).map(\.slug), ["deep", "shallow"])
    }

    func testFilterFlagAndResetLeaveSortAndSearchAlone() {
        var filters = WatchlistFilters()
        XCTAssertFalse(filters.isActive)
        filters.sort = .title
        XCTAssertFalse(filters.isActive, "Sortierung versteckt nichts und markiert den Knopf nicht.")
        filters.kind = .anime
        XCTAssertTrue(filters.isActive)
        filters.reset()
        XCTAssertFalse(filters.isActive)
        XCTAssertEqual(filters.sort, .added)
        XCTAssertNil(filters.state)
        XCTAssertNil(filters.genre)
    }

    func testEmptyListStaysEmptyThroughEveryFilter() {
        for quick in WatchlistQuickFilter.allCases {
            XCTAssertTrue(watchlistResults([], query: "", quick: quick, filters: .none).isEmpty)
        }
        XCTAssertEqual(watchlistStats([]).saved, 0)
        XCTAssertTrue(watchlistGenres([]).isEmpty)
    }

    func testSingleItemIsNotASpecialCase() {
        let one = [sample[0]]
        XCTAssertEqual(watchlistResults(one, query: "", quick: .started, filters: .none).count, 1)
        XCTAssertEqual(watchlistStats(one).saved, 1)
        XCTAssertEqual(sortWatchlist(one, by: .title).count, 1)
    }
}
