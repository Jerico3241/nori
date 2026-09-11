import XCTest
@testable import NoriCore

/// Der Kalender kommt von den beiden Quellen in völlig verschiedener Form:
/// AniWorld als HTML-Abschnitte je Tag, Serienstream als JSON-Objekt mit dem
/// Datum als Schlüssel. Beide landen in derselben `CalendarPayload`.
final class CalendarParsingTests: XCTestCase {

    /// Fester Bezugspunkt, damit die Einordnung nicht davon abhängt, wann der
    /// Test läuft: 14.09.2026, 08:00 Berliner Zeit — vor allen Fixture-Zeiten,
    /// also steht alles unter „kommend" und nichts doppelt.
    private let morning = berlinDate(year: 2026, month: 9, day: 14, hour: 8, minute: 0)

    // MARK: - AniWorld

    func testAniworldCalendarReadsDateTimeAndEpisode() throws {
        let payload = try HTML.parseAniworldCalendar(Fixtures.aniworldCalendar, now: morning)
        let onePiece = try XCTUnwrap(payload.upcoming.first { $0.slug == "one-piece" })

        XCTAssertEqual(onePiece.title, "One Piece")
        XCTAssertEqual(onePiece.season, "21")
        XCTAssertEqual(onePiece.episode, 1120)
        XCTAssertEqual(onePiece.dayKey, "2026-09-14")
        XCTAssertEqual(onePiece.dayLabel, "Montag, 14. September")
        XCTAssertEqual(
            onePiece.airingAt,
            berlinDate(year: 2026, month: 9, day: 14, hour: 9, minute: 30).timeIntervalSince1970 * 1000
        )
    }

    /// Dieselbe Folge steht für jede Sprache einmal im Markup. Zusammenführen,
    /// sonst steht sie mehrfach im Kalender.
    func testAniworldCalendarMergesLanguagesOfTheSameEpisode() throws {
        let payload = try HTML.parseAniworldCalendar(Fixtures.aniworldCalendar, now: morning)
        let onePiece = payload.upcoming.filter { $0.slug == "one-piece" }

        XCTAssertEqual(onePiece.count, 1)
        XCTAssertEqual(onePiece.first?.languages, ["DE", "JP"])
    }

    /// Das Cover steht nur im ersten der beiden Einträge und muss die
    /// Zusammenführung überleben; das Sprachfähnchen darf nicht dafür gehalten
    /// werden.
    func testAniworldCalendarTakesTheCoverNotTheFlag() throws {
        let payload = try HTML.parseAniworldCalendar(Fixtures.aniworldCalendar, now: morning)
        let onePiece = try XCTUnwrap(payload.upcoming.first { $0.slug == "one-piece" })
        XCTAssertEqual(
            onePiece.coverPath,
            "/public/img/cover/one-piece-stream-cover-WWoAujz6fnp93s8iZ3F9iqqjO7WtXiIV_220x330.jpg"
        )
    }

    func testAniworldCalendarReadsSubtitleFlag() throws {
        let payload = try HTML.parseAniworldCalendar(Fixtures.aniworldCalendar, now: morning)
        let frieren = try XCTUnwrap(payload.upcoming.first { $0.slug == "frieren" })
        XCTAssertEqual(frieren.languages, ["GerSub"])
        XCTAssertEqual(frieren.season, "2")
        XCTAssertEqual(frieren.episode, 3)
    }

    func testAniworldCalendarSortsByAiringTime() throws {
        let payload = try HTML.parseAniworldCalendar(Fixtures.aniworldCalendar, now: morning)
        XCTAssertEqual(payload.upcoming.map(\.slug), ["one-piece", "frieren", "ohne-zeit"])
    }

    /// Steht keine Uhrzeit im Markup, landet `airingAt` auf Mitternacht —
    /// sortieren lässt sich damit, anzeigen nicht. `hasTime` hält den
    /// Unterschied fest, damit der Kalender keine Zeit erfindet.
    func testAniworldCalendarMarksEntriesWithoutAClockTime() throws {
        let payload = try HTML.parseAniworldCalendar(Fixtures.aniworldCalendar, now: morning)

        let frieren = try XCTUnwrap(payload.upcoming.first { $0.slug == "frieren" })
        XCTAssertEqual(frieren.hasTime, true)

        let ohneZeit = try XCTUnwrap(payload.upcoming.first { $0.slug == "ohne-zeit" })
        XCTAssertEqual(ohneZeit.hasTime, false)
        XCTAssertEqual(
            ohneZeit.airingAt,
            berlinDate(year: 2026, month: 9, day: 15, hour: 0, minute: 0).timeIntervalSince1970 * 1000
        )
    }

    // MARK: - Serienstream

    func testSerienstreamCalendarReadsJSON() throws {
        let data = try XCTUnwrap(Fixtures.serienstreamCalendarJSON.data(using: .utf8))
        let payload = try HTML.parseSerienstreamCalendar(data, now: morning)
        let dexter = try XCTUnwrap(payload.upcoming.first { $0.slug == "dexter" })

        XCTAssertEqual(dexter.title, "Dexter")
        XCTAssertEqual(dexter.season, "2")
        XCTAssertEqual(dexter.episode, 3)
        // Der Kalender reicht den Poster unverändert durch — samt Abfrage.
        // Das ist in Ordnung: `AniworldClient.coverURL` schreibt `format`
        // später auf jpg um, egal was hier steht (siehe
        // ProviderPathTests.testCoverURLForcesJpegOnSerienstream).
        // Die Detailseite schneidet die Abfrage dagegen ab; beide Wege enden
        // deshalb bei derselben Adresse.
        XCTAssertEqual(dexter.coverPath, "/media/images/channel/desktop/dexter-7sqv7dhs?format=avif")
        XCTAssertEqual(
            dexter.airingAt,
            berlinDate(year: 2026, month: 9, day: 14, hour: 20, minute: 15).timeIntervalSince1970 * 1000
        )
    }

    /// Bei Serienstream trennt die Sprache die Einträge — dieselbe Folge auf
    /// Deutsch und Englisch sind zwei Zeilen, nicht eine.
    func testSerienstreamCalendarKeepsLanguagesApart() throws {
        let data = try XCTUnwrap(Fixtures.serienstreamCalendarJSON.data(using: .utf8))
        let payload = try HTML.parseSerienstreamCalendar(data, now: morning)
        let dexter = payload.upcoming.filter { $0.slug == "dexter" }

        XCTAssertEqual(dexter.count, 2)
        XCTAssertEqual(Set(dexter.flatMap(\.languages)), ["DE", "EN"])
    }

    /// Ein Schlüssel, der kein Datum ist, darf den ganzen Kalender nicht
    /// kippen.
    func testSerienstreamCalendarSkipsMalformedDayKeys() throws {
        let data = try XCTUnwrap(Fixtures.serienstreamCalendarJSON.data(using: .utf8))
        let payload = try HTML.parseSerienstreamCalendar(data, now: morning)
        XCTAssertFalse(payload.upcoming.contains { $0.slug == "ignoriert" })
        XCTAssertEqual(payload.upcoming.count, 3)
    }

    /// Serienstream schreibt in **jede** Kalenderzeile „00:00" — nachgezählt
    /// an einem vollständigen Abruf. Das ist ein Platzhalter, keine
    /// Ausstrahlungszeit, und darf deshalb nicht als Uhrzeit durchgehen.
    func testSerienstreamCalendarTreatsMidnightAsNoClockTime() throws {
        let data = try XCTUnwrap(Fixtures.serienstreamCalendarJSON.data(using: .utf8))
        let payload = try HTML.parseSerienstreamCalendar(data, now: morning)

        let dexter = try XCTUnwrap(payload.upcoming.first { $0.slug == "dexter" })
        XCTAssertEqual(dexter.hasTime, true)

        let ohneZeit = try XCTUnwrap(payload.upcoming.first { $0.slug == "ohne-zeit" })
        XCTAssertEqual(ohneZeit.hasTime, false)
    }

    // MARK: - Einordnung nach Zeit

    private func entry(_ slug: String, hour: Int) -> AiringEntry {
        AiringEntry(
            airingAt: berlinDate(year: 2026, month: 9, day: 14, hour: hour, minute: 0).timeIntervalSince1970 * 1000,
            episode: 1,
            season: "1",
            title: slug,
            english: nil,
            slug: slug,
            languages: [],
            dayKey: "2026-09-14",
            dayLabel: "Montag, 14. September",
            coverPath: nil
        )
    }

    func testPackCalendarSplitsUpcomingAndRecent() {
        let noon = berlinDate(year: 2026, month: 9, day: 14, hour: 12, minute: 0)
        let payload = HTML.packCalendar([entry("spaet", hour: 20), entry("frueh", hour: 2)], now: noon)

        XCTAssertEqual(payload.upcoming.map(\.slug), ["spaet"])
        XCTAssertEqual(payload.recent.map(\.slug), ["frueh"])
    }

    /// Eine Folge, die vor weniger als drei Stunden lief, steht bewusst in
    /// beiden Listen: unter „kommend", weil sie gerade erst anlief, und unter
    /// „kürzlich", weil sie schon vorbei ist. Das ist Absicht, kein Fehler —
    /// festgehalten, damit die Kulanzspanne nicht unbemerkt verschwindet.
    func testJustAiredAppearsInBothLists() {
        let noon = berlinDate(year: 2026, month: 9, day: 14, hour: 12, minute: 0)
        let payload = HTML.packCalendar([entry("gerade", hour: 10)], now: noon)

        XCTAssertEqual(payload.upcoming.map(\.slug), ["gerade"])
        XCTAssertEqual(payload.recent.map(\.slug), ["gerade"])
    }

    func testPackCalendarDropsEntriesOlderThanTwoDays() {
        let noon = berlinDate(year: 2026, month: 9, day: 14, hour: 12, minute: 0)
        let old = AiringEntry(
            airingAt: berlinDate(year: 2026, month: 9, day: 10, hour: 12, minute: 0).timeIntervalSince1970 * 1000,
            episode: 1,
            season: "1",
            title: "alt",
            english: nil,
            slug: "alt",
            languages: [],
            dayKey: "2026-09-10",
            dayLabel: "Donnerstag, 10. September",
            coverPath: nil
        )
        let payload = HTML.packCalendar([old], now: noon)

        XCTAssertTrue(payload.upcoming.isEmpty)
        XCTAssertTrue(payload.recent.isEmpty)
    }
}
