import XCTest
@testable import NoriCore

/// Countdown, Quellenwechsel nach einem Fehlschlag und Übersprungmarken.
///
/// Dieselben Fälle prüft `shared/nori-core/test/playback.test.ts`. Die
/// Wiederherstellung ist der Teil, der vorher auf jeder Plattform anders war:
/// iOS bot nach einem Fehler „einen anderen Hoster" an und nahm dabei den
/// nächsten der Rangfolge — auch wenn das derselbe war, der eben nicht ging.
final class PlaybackTests: XCTestCase {

    private func option(_ name: String, _ lang: String = "DE") -> HosterOption {
        HosterOption(name: name, lang: lang, langKey: lang, redirectPath: "/redirect/\(name)")
    }

    private var options: [HosterOption] {
        [option("Doodstream"), option("VOE"), option("Vidoza"), option("Filemoon"), option("VOE", "EN")]
    }

    // MARK: - Nächste Folge

    func testCountdownIsTenSeconds() {
        XCTAssertEqual(Playback.autoplayCountdownSec, 10)
    }

    func testCountdownOnlyNearTheEnd() {
        XCTAssertFalse(Playback.shouldOfferNextEpisode(
            positionSec: 600, durationSec: 1_400, hasNext: true, autoplayEnabled: true))
        XCTAssertTrue(Playback.shouldOfferNextEpisode(
            positionSec: 1_380, durationSec: 1_400, hasNext: true, autoplayEnabled: true))
    }

    func testCountdownNeedsBothSwitchAndNextEpisode() {
        XCTAssertFalse(Playback.shouldOfferNextEpisode(
            positionSec: 1_380, durationSec: 1_400, hasNext: false, autoplayEnabled: true))
        XCTAssertFalse(Playback.shouldOfferNextEpisode(
            positionSec: 1_380, durationSec: 1_400, hasNext: true, autoplayEnabled: false))
    }

    func testVeryShortClipsGetNoCountdown() {
        XCTAssertFalse(Playback.shouldOfferNextEpisode(
            positionSec: 18, durationSec: 19, hasNext: true, autoplayEnabled: true))
    }

    // MARK: - Wiederherstellung

    func testFirstFailureRetriesTheSameSource() {
        var recovery = PlaybackRecovery(episode: "aniworld|/a/1")
        let current = SourceRef(hoster: "VOE", lang: "DE")
        recovery.noteFailure(nil)
        XCTAssertEqual(recovery.plan(options: options, current: current), .retry)
    }

    func testAFailedSourceIsNeverOfferedAgain() {
        var recovery = PlaybackRecovery(episode: "aniworld|/a/1")
        let voe = SourceRef(hoster: "VOE", lang: "DE")
        recovery.noteFailure(voe)

        guard case let .switchTo(next) = recovery.plan(options: options, current: voe) else {
            return XCTFail("Nach einer gescheiterten Quelle muss gewechselt werden")
        }
        XCTAssertNotEqual(next.name.lowercased(), "voe")
        // Die Rangfolge aus dem Contract gilt weiter: Vidoza vor Filemoon,
        // Doodstream zuletzt.
        XCTAssertEqual(next.name, "Vidoza")
    }

    /// Der Fall, der iOS endlos im Kreis laufen ließ.
    func testTwoBrokenSourcesDoNotAlternateForever() {
        var recovery = PlaybackRecovery(episode: "aniworld|/a/1")
        var current = SourceRef(hoster: "VOE", lang: "DE")
        for _ in 0 ..< 6 {
            recovery.noteFailure(current)
            switch recovery.plan(options: options, current: current) {
            case .retry:
                continue
            case let .switchTo(option):
                recovery.noteSwitch()
                current = SourceRef(hoster: option.name, lang: option.lang)
            case .giveUp:
                XCTAssertLessThanOrEqual(recovery.switches, PlaybackRecovery.maxAutomaticSwitches)
                return
            }
        }
        XCTFail("Die Wiederherstellung muss nach wenigen Versuchen aufgeben")
    }

    func testGivingUpWhenNothingIsLeft() {
        var recovery = PlaybackRecovery(episode: "aniworld|/a/1")
        let only = [option("VOE")]
        let current = SourceRef(hoster: "VOE", lang: "DE")
        recovery.noteFailure(current)
        guard case let .giveUp(reason) = recovery.plan(options: only, current: current) else {
            return XCTFail("Ohne weitere Quelle gibt es nichts zu wechseln")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func testRemainingStaysWithinTheLanguage() {
        var recovery = PlaybackRecovery(episode: "aniworld|/a/1")
        recovery.noteFailure(SourceRef(hoster: "VOE", lang: "DE"))
        let left = recovery.remaining(options, lang: "DE").map(\.name)
        XCTAssertFalse(left.contains("VOE"))
        XCTAssertEqual(Set(left), ["Vidoza", "Filemoon", "Doodstream"])

        // Dieselbe Quelle in einer anderen Sprache ist eine andere Quelle.
        XCTAssertEqual(recovery.remaining(options, lang: "EN").map(\.name), ["VOE"])
    }

    func testANewEpisodeStartsOver() {
        var recovery = PlaybackRecovery(episode: "aniworld|/a/1")
        recovery.noteFailure(SourceRef(hoster: "VOE", lang: "DE"))
        recovery.noteSwitch()
        recovery.begin(episode: "aniworld|/a/2")
        XCTAssertTrue(recovery.failed.isEmpty)
        XCTAssertEqual(recovery.switches, 0)
        XCTAssertEqual(recovery.remaining(options, lang: "DE").first?.name, "VOE")
    }

    func testBeginningTheSameEpisodeKeepsTheState() {
        var recovery = PlaybackRecovery(episode: "aniworld|/a/1")
        recovery.noteFailure(SourceRef(hoster: "VOE", lang: "DE"))
        recovery.begin(episode: "aniworld|/a/1")
        XCTAssertEqual(recovery.failed.count, 1)
    }

    // MARK: - Übersprungmarken

    func testSanitizeDropsNonsense() {
        let raw = [
            // Negativer Beginn wird auf null gezogen.
            SkipSegment(type: .intro, start: -10, end: 90),
            // Vertauschte Grenzen werden gedreht.
            SkipSegment(type: .outro, start: 1_400, end: 1_300),
            // Unter zwei Sekunden: keine Marke, ein Messfehler.
            SkipSegment(type: .recap, start: 100, end: 101),
            // Jenseits der Laufzeit: fällt ganz weg.
            SkipSegment(type: .outro, start: 1_500, end: 1_600),
        ]
        let clean = SkipSegments.sanitize(raw, durationSec: 1_400)
        XCTAssertEqual(clean.count, 2)
        XCTAssertEqual(clean[0].type, .intro)
        XCTAssertEqual(clean[0].start, 0)
        XCTAssertEqual(clean[0].end, 90)
        XCTAssertEqual(clean[1].type, .outro)
        XCTAssertEqual(clean[1].start, 1_300)
        XCTAssertEqual(clean[1].end, 1_400)
    }

    func testOverlappingSegmentsOfTheSameKindMerge() {
        let raw = [
            SkipSegment(type: .intro, start: 0, end: 90),
            SkipSegment(type: .intro, start: 80, end: 120),
        ]
        let clean = SkipSegments.sanitize(raw, durationSec: 1_400)
        XCTAssertEqual(clean.count, 1)
        XCTAssertEqual(clean[0].end, 120)
    }

    func testActiveSegmentAtPosition() {
        let segments = [SkipSegment(type: .intro, start: 30, end: 120)]
        XCTAssertNil(SkipSegments.active(segments, at: 29))
        XCTAssertEqual(SkipSegments.active(segments, at: 30)?.type, .intro)
        XCTAssertNil(SkipSegments.active(segments, at: 120))
    }

    /// Es gibt heute keine Quelle für Zeitmarken. Ohne Daten darf nichts
    /// angeboten werden — geraten wäre schlechter als gar nichts.
    func testNoSegmentsMeansNoOffer() {
        XCTAssertNil(SkipSegments.active([], at: 42))
        XCTAssertTrue(SkipSegments.sanitize([], durationSec: 1_400).isEmpty)
    }
}
