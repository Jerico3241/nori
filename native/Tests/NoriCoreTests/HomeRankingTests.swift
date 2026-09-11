import XCTest
@testable import NoriCore

/// Die Reihenfolge der Startseite.
///
/// Die Reihen heißen „Neu & beliebt", „Neue Episoden" und „Für dich" — und
/// die Namen müssen stimmen. Eine zufällig sortierte Katalogliste unter der
/// Überschrift „Neu & beliebt" sieht im Simulator genauso aus wie eine
/// richtige und ist trotzdem falsch. Deshalb steht die Rechnung als reine
/// Funktion in `HomeFeed.swift` und wird hier durchgespielt.
final class HomeRankingTests: XCTestCase {
    /// Ein fester Zeitpunkt. Mit `Date()` hinge das Ergebnis davon ab, wann
    /// jemand die Tests laufen lässt.
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func title(_ slug: String, provider: CatalogProvider = .aniworld, genres: [String] = []) -> HomeTitle {
        HomeTitle(slug: slug, title: slug.capitalized, provider: provider, genres: genres)
    }

    private func candidate(
        _ slug: String,
        provider: CatalogProvider = .aniworld,
        genres: [String] = [],
        tmdbID: Int? = 1,
        popularity: Double? = nil,
        voteAverage: Double? = nil,
        voteCount: Int? = nil,
        firstAired: TimeInterval? = nil,
        lastAired: TimeInterval? = nil,
        trendingRank: Int? = nil,
        genreIDs: [Int] = [],
        hasBackdrop: Bool = true,
        watched: Double = 0,
        freshEpisode: Bool = false
    ) -> HomeCandidate {
        var signals = TMDBSignals()
        signals.tmdbID = tmdbID
        signals.popularity = popularity
        signals.voteAverage = voteAverage
        signals.voteCount = voteCount
        signals.firstAirDate = firstAired.map { now.addingTimeInterval(-$0 * 86_400) }
        signals.lastAirDate = lastAired.map { now.addingTimeInterval(-$0 * 86_400) }
        signals.trendingRank = trendingRank
        signals.genreIDs = genreIDs
        signals.hasBackdrop = hasBackdrop
        return HomeCandidate(
            title: title(slug, provider: provider, genres: genres),
            signals: signals,
            watchedRatio: watched,
            hasFreshEpisode: freshEpisode
        )
    }

    // MARK: - „Neu"

    func testNewMeansRecentlyAiredNotRecentlyPremiered() {
        // Eine zehn Jahre alte Serie mit einer Staffel von letzter Woche ist
        // neu. Ihre Erstausstrahlung ist es nicht.
        let longRunning = candidate("aired-last-week", firstAired: 3650, lastAired: 5)
        XCTAssertTrue(HomeRanking.isNew(longRunning.signals, now: now))

        let dormant = candidate("dormant", firstAired: 3650, lastAired: 400)
        XCTAssertFalse(HomeRanking.isNew(dormant.signals, now: now))
    }

    func testUpcomingCountsAsNew() {
        // Eine Serie, die diese Woche anläuft, ist das Neueste, was es gibt —
        // auch wenn das Datum noch in der Zukunft liegt.
        var signals = TMDBSignals()
        signals.firstAirDate = now.addingTimeInterval(3 * 86_400)
        XCTAssertTrue(HomeRanking.isNew(signals, now: now))
    }

    // MARK: - „Neu & beliebt"

    func testTrendingOldTitleBeatsNewUnknownTitle() {
        // Der Fall aus der Aufgabenstellung: ein alter, stark trendender
        // Titel gegen einen neuen, den niemand kennt.
        let trendingOld = candidate("trending-old", popularity: 900, firstAired: 2000, lastAired: 1800, trendingRank: 2)
        let newUnknown = candidate("new-unknown", popularity: 0.4, firstAired: 10, lastAired: 10)

        let ranked = HomeRanking.newAndPopular([newUnknown, trendingOld], now: now)
        XCTAssertEqual(ranked.first?.title.slug, "trending-old")
    }

    func testHighRatingWithFewVotesDoesNotWin() {
        // 10/10 aus zwei Stimmen ist keine Auskunft.
        let perfectButUnseen = candidate("two-votes", popularity: 1, voteAverage: 10, voteCount: 2, lastAired: 20)
        let solidAndPopular = candidate("solid", popularity: 300, voteAverage: 7.4, voteCount: 4000, lastAired: 20)

        let ranked = HomeRanking.newAndPopular([perfectButUnseen, solidAndPopular], now: now)
        XCTAssertEqual(ranked.first?.title.slug, "solid")
    }

    func testRatingCountsOnceThereAreEnoughVotes() {
        let good = candidate("good", popularity: 100, voteAverage: 8.6, voteCount: 3000, lastAired: 20)
        let weak = candidate("weak", popularity: 100, voteAverage: 5.2, voteCount: 3000, lastAired: 20)
        XCTAssertGreaterThan(
            HomeRanking.newAndPopularScore(good, now: now),
            HomeRanking.newAndPopularScore(weak, now: now)
        )
    }

    func testPopularityIsDampenedSoOneOutlierDoesNotOwnTheRow() {
        // `popularity` ist nach oben offen. Linear gewichtet schöbe ein
        // einziger Ausreißer alles andere aus der Reihe.
        let huge = candidate("huge", popularity: 20_000)
        let large = candidate("large", popularity: 2_000)
        let gap = HomeRanking.newAndPopularScore(huge, now: now) - HomeRanking.newAndPopularScore(large, now: now)
        XCTAssertLessThan(gap, 40)
    }

    func testFinishedTitlesAreDampened() {
        let unseen = candidate("unseen", popularity: 300, lastAired: 10)
        let finished = candidate("finished", popularity: 300, lastAired: 10, watched: 1)
        XCTAssertGreaterThan(
            HomeRanking.newAndPopularScore(unseen, now: now),
            HomeRanking.newAndPopularScore(finished, now: now)
        )
    }

    func testTitlesWithoutAnyTMDBSignalAreLeftOut() {
        // Ohne Signal gibt es keine Aussage über „neu" oder „beliebt" —
        // dann gehört der Titel nicht in eine Reihe, die genau das behauptet.
        let blind = HomeCandidate(title: title("no-signal"))
        XCTAssertTrue(HomeRanking.newAndPopular([blind], now: now).isEmpty)
    }

    func testHeroTitleIsRemovedFromTheRow() {
        let hero = candidate("hero", popularity: 900, lastAired: 5, trendingRank: 1)
        let other = candidate("other", popularity: 400, lastAired: 5)
        let ranked = HomeRanking.newAndPopular([hero, other], now: now, excluding: [hero.id])
        XCTAssertEqual(ranked.map(\.title.slug), ["other"])
    }

    func testOrderIsStableForEqualScores() {
        // Ohne zweiten Sortierschlüssel sortierte sich die Startseite bei
        // jedem Neuaufbau anders.
        let a = candidate("alpha", popularity: 100, lastAired: 10)
        let b = candidate("beta", popularity: 100, lastAired: 10)
        XCTAssertEqual(
            HomeRanking.newAndPopular([b, a], now: now).map(\.title.slug),
            HomeRanking.newAndPopular([a, b], now: now).map(\.title.slug)
        )
    }

    // MARK: - Kopfbereich

    func testHeroNeedsABackdrop() {
        // Der Kopfbereich ist fast ein halber Bildschirm. Ohne Breitbild
        // bliebe dort eine schwarze Fläche.
        let noArt = candidate("no-art", popularity: 5000, trendingRank: 1, hasBackdrop: false)
        XCTAssertTrue(HomeRanking.heroPicks([noArt], now: now, day: 0).isEmpty)
    }

    func testHeroSkipsFinishedSeries() {
        let done = candidate("done", popularity: 900, trendingRank: 1, watched: 1)
        XCTAssertTrue(HomeRanking.heroPicks([done], now: now, day: 0).isEmpty)
    }

    func testHeroRotatesByDayButIsStableWithinOneDay() {
        let pool = (1 ... 6).map { candidate("title-\($0)", popularity: Double(1000 - $0 * 10), lastAired: 5) }
        let monday = HomeRanking.heroPicks(pool, now: now, day: 100, limit: 3)
        let mondayAgain = HomeRanking.heroPicks(pool, now: now, day: 100, limit: 3)
        let tuesday = HomeRanking.heroPicks(pool, now: now, day: 101, limit: 3)

        XCTAssertEqual(monday.map(\.id), mondayAgain.map(\.id))
        XCTAssertNotEqual(monday.map(\.id), tuesday.map(\.id))
        XCTAssertEqual(monday.count, 3)
    }

    // MARK: - Verfügbarkeit

    func testOnlyNoriTitlesBecomeCandidates() {
        // Der harte Teil der Regel: TMDBs Listen enthalten überwiegend Titel,
        // die Nori nicht anbietet. Aus ihnen darf keine Kachel entstehen.
        let catalog = [title("vinland-saga")]
        let rows = [
            TMDBCandidate(id: 1, name: "Vinland-Saga", popularity: 80, genreIDs: [16], originCountries: ["JP"], backdropPath: "/b.jpg"),
            TMDBCandidate(id: 2, name: "Stranger Things", popularity: 5000, genreIDs: [18], originCountries: ["US"], backdropPath: "/c.jpg"),
        ]
        let candidates = HomeSignals.candidates(catalog: catalog, trending: rows, now: now)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.title.slug, "vinland-saga")
        XCTAssertEqual(candidates.first?.signals.trendingRank, 1)
        XCTAssertTrue(candidates.first?.signals.hasBackdrop == true)
    }

    func testCatalogTitlesWithoutATMDBRowKeepEmptySignals() {
        let candidates = HomeSignals.candidates(catalog: [title("obscure")], trending: [], now: now)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(candidates.first?.signals.isEmpty == true)
    }

    // MARK: - Neue Episoden

    private func airing(_ slug: String, daysAgo: Double, episode: Int = 1, provider: CatalogProvider = .aniworld) -> AiringEntry {
        AiringEntry(
            airingAt: (now.timeIntervalSince1970 - daysAgo * 86_400) * 1000,
            episode: episode,
            season: "1",
            title: slug.capitalized,
            english: nil,
            slug: slug,
            languages: ["GerSub"],
            dayKey: "2025-01-01",
            dayLabel: "Heute",
            coverPath: nil,
            provider: provider
        )
    }

    func testNewEpisodesAreChronologicalNewestFirst() {
        // Ausdrücklich nicht nach Beliebtheit: „Neue Episoden" beantwortet
        // die Frage „was ist seit gestern dazugekommen".
        let rows = [airing("old", daysAgo: 2), airing("fresh", daysAgo: 0.1), airing("mid", daysAgo: 1)]
        XCTAssertEqual(
            HomeEpisodes.recent(entries: rows, now: now).map(\.slug),
            ["fresh", "mid", "old"]
        )
    }

    func testNewEpisodesSkipFutureAirings() {
        let rows = [airing("later", daysAgo: -1), airing("already", daysAgo: 0.5)]
        XCTAssertEqual(HomeEpisodes.recent(entries: rows, now: now).map(\.slug), ["already"])
    }

    func testNewEpisodesDropEntriesNoriCannotOpen() {
        let rows = [airing("known", daysAgo: 0.5), airing("unknown", daysAgo: 0.2)]
        let available: Set<String> = ["aniworld|known"]
        XCTAssertEqual(
            HomeEpisodes.recent(entries: rows, now: now, availableSlugs: available).map(\.slug),
            ["known"]
        )
    }

    func testNewEpisodesCollapseTheSameEpisodeInSeveralLanguages() {
        var german = airing("dub", daysAgo: 0.3)
        german.languages = ["Deutsch"]
        let subbed = airing("dub", daysAgo: 0.3)
        XCTAssertEqual(HomeEpisodes.recent(entries: [german, subbed], now: now).count, 1)
    }

    // MARK: - „Für dich"

    private func progress(slug: String, ratio: Double, provider: CatalogProvider = .aniworld) -> WatchProgress {
        WatchProgress(
            slug: slug,
            title: slug.capitalized,
            season: "1",
            episode: 1,
            episodePath: provider.episodePath(slug: slug, season: "1", episode: 1),
            germanTitle: "Folge",
            englishTitle: "Episode",
            positionSec: 1200 * ratio,
            durationSec: 1200,
            updatedAt: now.timeIntervalSince1970 * 1000,
            lang: "DE",
            completed: ratio >= 0.9 ? true : nil,
            provider: provider
        )
    }

    func testColdStartProfileIsNotMeaningful() {
        // Ohne Verlauf gibt es keine Personalisierung. Die Startseite zeigt
        // dann ausdrücklich etwas anderes, statt „Für dich" mit einer zweiten
        // Beliebtheitsliste zu füllen.
        let profile = HomeTaste.profile(
            progress: [],
            favorites: [],
            favoriteSource: [:],
            catalog: [title("a", genres: ["Action"])],
            signals: [:],
            now: now
        )
        XCTAssertFalse(profile.isMeaningful)
    }

    func testProfilePicksUpGenresFromWatchedTitles() {
        let catalog = [
            title("a", genres: ["Action", "Fantasy"]),
            title("b", genres: ["Fantasy"]),
            title("c", genres: ["Romance"]),
        ]
        let profile = HomeTaste.profile(
            progress: [progress(slug: "a", ratio: 1), progress(slug: "b", ratio: 0.5)],
            favorites: ["c"],
            favoriteSource: ["c": .aniworld],
            catalog: catalog,
            signals: [:],
            now: now
        )
        XCTAssertTrue(profile.isMeaningful)
        XCTAssertNotNil(profile.genreWeights["fantasy"])
        XCTAssertGreaterThan(profile.genreWeights["fantasy"] ?? 0, profile.genreWeights["romance"] ?? 0)
    }

    func testRecommendationsPreferMatchingGenresAndSkipWhatIsAlreadyStarted() {
        let catalog = [
            title("watched", genres: ["Fantasy"]),
            title("fantasy-new", genres: ["Fantasy", "Adventure"]),
            title("cooking-show", genres: ["Kochen"]),
        ]
        let profile = HomeTaste.profile(
            progress: [progress(slug: "watched", ratio: 1)],
            favorites: ["watched"],
            favoriteSource: ["watched": .aniworld],
            catalog: catalog,
            signals: [:],
            now: now
        )
        let pool = [
            candidate("watched", genres: ["Fantasy"], popularity: 500),
            candidate("fantasy-new", genres: ["Fantasy", "Adventure"], popularity: 50),
            candidate("cooking-show", genres: ["Kochen"], popularity: 500),
        ]
        let picked = HomeTaste.recommend(pool, profile: profile, limit: 5)

        XCTAssertEqual(picked.first?.title.slug, "fantasy-new")
        // Angefangenes steht in „Weiterschauen" — zweimal dasselbe auf einem
        // Bildschirm ist einmal zu viel.
        XCTAssertFalse(picked.contains { $0.title.slug == "watched" })
    }

    func testTMDBRecommendationOutweighsGenreOverlap() {
        let profile = HomeTaste.profile(
            progress: [progress(slug: "seed", ratio: 1)],
            favorites: [],
            favoriteSource: [:],
            catalog: [title("seed", genres: ["Drama"])],
            signals: [:],
            now: now
        )
        let byGenre = candidate("same-genre", genres: ["Drama"], tmdbID: 50)
        let byTMDB = candidate("tmdb-says-so", genres: ["Sport"], tmdbID: 51)

        let picked = HomeTaste.recommend([byGenre, byTMDB], profile: profile, recommended: [51: 3])
        XCTAssertEqual(picked.first?.title.slug, "tmdb-says-so")
    }

    func testRecommendationsWithoutAnyConnectionAreDropped() {
        // Eine Empfehlung mit null Punkten ist keine Empfehlung, sondern ein
        // Lückenfüller.
        let profile = HomeTaste.profile(
            progress: [progress(slug: "seed", ratio: 1)],
            favorites: [],
            favoriteSource: [:],
            catalog: [title("seed", genres: ["Drama"])],
            signals: [:],
            now: now
        )
        let unrelated = HomeCandidate(title: title("unrelated", genres: ["Sport"]))
        XCTAssertTrue(HomeTaste.recommend([unrelated], profile: profile).isEmpty)
    }

    // MARK: - Weitere Reihen

    func testTopRatedIgnoresThinVoteCounts() {
        let thin = candidate("thin", popularity: nil, voteAverage: 9.9, voteCount: 12)
        let solid = candidate("solid", popularity: nil, voteAverage: 8.1, voteCount: 5000)
        XCTAssertEqual(HomeRanking.topRated([thin, solid]).map(\.title.slug), ["solid"])
    }

    func testTrendingRowFollowsTMDBRank() {
        let third = candidate("third", trendingRank: 3)
        let first = candidate("first", trendingRank: 1)
        let none = candidate("none")
        XCTAssertEqual(HomeRanking.trending([third, none, first]).map(\.title.slug), ["first", "third"])
    }
}
