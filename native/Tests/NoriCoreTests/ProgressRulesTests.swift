import XCTest
@testable import NoriCore

/// Die Regeln für „gesehen" und „Weiterschauen" stehen in der Projektvorgabe
/// und dürfen sich nicht unbemerkt verschieben.
final class ProgressRulesTests: XCTestCase {
    private func progress(
        position: Double,
        duration: Double,
        completed: Bool? = nil,
        slug: String = "demo",
        season: String = "1",
        episode: Int = 1,
        path: String = "/anime/stream/demo/staffel-1/episode-1"
    ) -> WatchProgress {
        WatchProgress(
            slug: slug,
            title: "Demo",
            season: season,
            episode: episode,
            episodePath: path,
            germanTitle: "Folge",
            englishTitle: "Episode",
            positionSec: position,
            durationSec: duration,
            updatedAt: 0,
            lang: "DE",
            completed: completed,
            provider: .aniworld
        )
    }

    // MARK: - Abschluss

    func testCompletedFlagWins() {
        XCTAssertTrue(isEpisodeComplete(progress(position: 0, duration: 1400, completed: true)))
    }

    func testNinetyPercentCountsAsComplete() {
        XCTAssertTrue(isEpisodeComplete(progress(position: 1260, duration: 1400)))
    }

    func testJustUnderNinetyPercentIsNotComplete() {
        XCTAssertFalse(isEpisodeComplete(progress(position: 1259, duration: 1400)))
    }

    func testShortClipsNeverCountAsComplete() {
        // Unter 20 Sekunden Laufzeit greift die Prozentregel bewusst nicht.
        XCTAssertFalse(isEpisodeComplete(progress(position: 19, duration: 19)))
    }

    func testNilIsNotComplete() {
        XCTAssertFalse(isEpisodeComplete(nil))
    }

    // MARK: - Fortschrittsanteil

    func testRatioOfCompletedEpisodeIsOne() {
        XCTAssertEqual(watchRatio(progress(position: 10, duration: 1400, completed: true)), 1)
    }

    func testRatioIsClampedToOne() {
        XCTAssertEqual(watchRatio(progress(position: 5000, duration: 1400)), 1)
    }

    func testRatioIsZeroForVeryShortDuration() {
        XCTAssertEqual(watchRatio(progress(position: 4, duration: 7)), 0)
    }

    func testRatioIsZeroWithoutProgress() {
        XCTAssertEqual(watchRatio(nil), 0)
    }

    // MARK: - Resume

    func testResumeStartsFromBeginningBelowEightSeconds() {
        XCTAssertEqual(resumePosition(progress(position: 7.9, duration: 1400)), 0)
    }

    func testResumeUsesStoredPositionFromEightSeconds() {
        XCTAssertEqual(resumePosition(progress(position: 8, duration: 1400)), 8)
    }

    func testCompletedEpisodeRestartsFromBeginning() {
        XCTAssertEqual(resumePosition(progress(position: 1300, duration: 1400, completed: true)), 0)
    }

    func testResumeWithoutProgressIsZero() {
        XCTAssertEqual(resumePosition(nil), 0)
    }
}
