import XCTest
@testable import NoriCore

/// Die Startseite behält ihre sichtbare Ordnung, während TMDB nachkommt.
///
/// Vorher ersetzte der zweite Durchgang den ganzen Feed: Karten wechselten die
/// Stelle, der Kopfbereich den Titel, und ein neuer Abschnitt schob sich
/// zwischen zwei Reihen, während schon gescrollt wurde.
final class HomeFeedStabilityTests: XCTestCase {

    private func candidate(_ slug: String, popularity: Double? = nil) -> HomeCandidate {
        var signals = TMDBSignals()
        signals.popularity = popularity
        return HomeCandidate(title: HomeTitle(slug: slug, title: slug.capitalized, provider: .aniworld), signals: signals)
    }

    private func pool(_ items: [HomeCandidate]) -> [String: HomeCandidate] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func feed(
        hero: [HomeCandidate] = [],
        popular: [HomeCandidate] = [],
        episodes: [AiringEntry] = [],
        recommendations: [HomeCandidate] = [],
        extra: [HomeRow] = [],
        watching: [WatchProgress] = []
    ) -> HomeFeed {
        var out = HomeFeed()
        out.hero = hero
        out.newAndPopular = popular
        out.newEpisodes = episodes
        out.recommendations = recommendations
        out.extraRows = extra
        out.continueWatching = watching
        out.sections = HomeSection.canonical(for: out)
        return out
    }

    private func episode(_ slug: String, number: Int) -> AiringEntry {
        AiringEntry(
            airingAt: 0, episode: number, season: "1", title: slug, english: nil, slug: slug,
            languages: ["DE"], dayKey: "2026-09-13", dayLabel: "Heute", coverPath: nil, hasTime: true, provider: .aniworld
        )
    }

    private func progress(_ slug: String) -> WatchProgress {
        WatchProgress(
            slug: slug, title: slug, season: "1", episode: 1,
            episodePath: "/anime/stream/\(slug)/staffel-1/episode-1",
            germanTitle: "", englishTitle: "", positionSec: 300, durationSec: 1400,
            updatedAt: 1, lang: "DE", completed: nil, provider: .aniworld
        )
    }

    // MARK: - Reihen

    /// Frische Beliebtheit sortiert die Reihe anders — gezeigt wird die alte
    /// Folge, aber mit den neuen Daten.
    func testRowKeepsItsOrderButTakesFreshData() {
        let a = candidate("a"), b = candidate("b"), c = candidate("c")
        let previous = feed(popular: [a, b, c])
        let freshA = candidate("a", popularity: 10), freshB = candidate("b", popularity: 90), freshC = candidate("c", popularity: 50)
        let fresh = feed(popular: [freshB, freshC, freshA])

        let result = HomeFeedStability.stabilize(previous: previous, fresh: fresh, candidates: pool([freshA, freshB, freshC]))

        XCTAssertEqual(result.newAndPopular.map(\.id), [a.id, b.id, c.id])
        XCTAssertEqual(result.newAndPopular.first?.signals.popularity, 10)
    }

    func testNewTitlesAreAppendedNotInserted() {
        let a = candidate("a"), b = candidate("b"), d = candidate("d")
        let previous = feed(popular: [a, b])
        let fresh = feed(popular: [d, a, b])

        let result = HomeFeedStability.stabilize(previous: previous, fresh: fresh, candidates: pool([a, b, d]))

        XCTAssertEqual(result.newAndPopular.map(\.title.slug), ["a", "b", "d"])
    }

    /// Nicht mehr auf der Rangliste, aber noch im Katalog: bleibt. Nicht mehr im
    /// Katalog: fällt weg.
    func testTitlesStayWhileTheCatalogHasThem() {
        let a = candidate("a"), b = candidate("b"), c = candidate("c")
        let previous = feed(popular: [a, b, c])
        let fresh = feed(popular: [c])

        let result = HomeFeedStability.stabilize(previous: previous, fresh: fresh, candidates: pool([a, c]))

        XCTAssertEqual(result.newAndPopular.map(\.title.slug), ["a", "c"])
    }

    func testAppendingNeverDuplicatesATitleFromAnotherRow() {
        let a = candidate("a"), b = candidate("b"), c = candidate("c")
        let previous = feed(popular: [a], recommendations: [b])
        let fresh = feed(popular: [b, a], recommendations: [a, c])

        let result = HomeFeedStability.stabilize(previous: previous, fresh: fresh, candidates: pool([a, b, c]))

        XCTAssertEqual(result.newAndPopular.map(\.title.slug), ["a"])
        XCTAssertEqual(result.recommendations.map(\.title.slug), ["b", "c"])
    }

    func testRowDoesNotGrowBeyondTheLongerVersion() {
        let items = (0 ..< 6).map { candidate("t\($0)") }
        let previous = feed(popular: Array(items[0 ..< 3]))
        let fresh = feed(popular: Array(items[3 ..< 6]))

        let result = HomeFeedStability.stabilize(previous: previous, fresh: fresh, candidates: pool(items))

        XCTAssertEqual(result.newAndPopular.count, 3)
    }

    // MARK: - Kopfbereich

    func testHeroKeepsItsTitlesWithFreshData() {
        let a = candidate("a"), b = candidate("b")
        let previous = feed(hero: [a, b])
        let freshA = candidate("a", popularity: 7)
        let fresh = feed(hero: [candidate("z"), freshA])

        let result = HomeFeedStability.stabilize(previous: previous, fresh: fresh, candidates: pool([freshA, b, candidate("z")]))

        XCTAssertEqual(result.hero.map(\.title.slug), ["a", "b"])
        XCTAssertEqual(result.hero.first?.signals.popularity, 7)
    }

    /// Stand noch kein Kopfbereich da, darf der erste kommen.
    func testEmptyHeroTakesTheFreshOne() {
        let z = candidate("z")
        let result = HomeFeedStability.stabilize(previous: feed(), fresh: feed(hero: [z]), candidates: pool([z]))
        XCTAssertEqual(result.hero.map(\.title.slug), ["z"])
    }

    // MARK: - Abschnitte

    /// „Neue Episoden" kommt mit dem Kalender erst im zweiten Durchgang — und
    /// steht dann unten, nicht zwischen zwei sichtbaren Reihen.
    func testANewSectionIsAppendedAtTheEnd() {
        let a = candidate("a"), b = candidate("b")
        let previous = feed(popular: [a], recommendations: [b])
        let fresh = feed(popular: [a], episodes: [episode("x", number: 3)], recommendations: [b])

        let result = HomeFeedStability.stabilize(previous: previous, fresh: fresh, candidates: pool([a, b]))

        XCTAssertEqual(result.sections, [.newAndPopular, .recommendations, .newEpisodes])
        XCTAssertEqual(HomeSection.canonical(for: fresh), [.newAndPopular, .newEpisodes, .recommendations])
    }

    func testNewExtraRowsComeAfterExistingOnes() {
        let a = candidate("a"), b = candidate("b"), c = candidate("c")
        let previous = feed(popular: [a], extra: [HomeRow(title: "Drama", items: [b])])
        let fresh = feed(popular: [a], extra: [HomeRow(title: "Trend", items: [c]), HomeRow(title: "Drama", items: [b])])

        let result = HomeFeedStability.stabilize(previous: previous, fresh: fresh, candidates: pool([a, b, c]))

        XCTAssertEqual(result.extraRows.map(\.title), ["Drama", "Trend"])
        XCTAssertEqual(result.sections, [.newAndPopular, .extra("Drama"), .extra("Trend")])
    }

    /// „Weiterschauen" gehört der Bibliothek: es wird nie festgehalten, und
    /// erscheint es neu, steht es oben.
    func testContinueWatchingFollowsTheLibraryAndGoesOnTop() {
        let a = candidate("a")
        let previous = feed(popular: [a])
        let fresh = feed(popular: [a], watching: [progress("frieren")])

        let result = HomeFeedStability.stabilize(previous: previous, fresh: fresh, candidates: pool([a]))

        XCTAssertEqual(result.continueWatching.map(\.slug), ["frieren"])
        XCTAssertEqual(result.sections.first, .continueWatching)
    }

    /// Eine angefangene Serie wandert nach „Weiterschauen" — und steht dann
    /// nicht zusätzlich weiter unter den Empfehlungen.
    func testStartedTitleLeavesRecommendations() {
        let a = candidate("frieren"), b = candidate("b")
        let previous = feed(recommendations: [a, b])
        let fresh = feed(recommendations: [b], watching: [progress("frieren")])

        let result = HomeFeedStability.stabilize(previous: previous, fresh: fresh, candidates: pool([a, b]))

        XCTAssertEqual(result.recommendations.map(\.title.slug), ["b"])
    }

    func testEpisodesKeepTheirOrder() {
        let previous = feed(episodes: [episode("a", number: 1), episode("b", number: 2)])
        let fresh = feed(episodes: [episode("b", number: 2), episode("c", number: 5), episode("a", number: 1)])

        let result = HomeFeedStability.stabilize(previous: previous, fresh: fresh, candidates: [:])

        XCTAssertEqual(result.newEpisodes.map(\.slug), ["a", "b", "c"])
    }
}
