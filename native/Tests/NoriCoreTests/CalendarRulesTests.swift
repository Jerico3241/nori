import XCTest
@testable import NoriCore

/// Die Regeln, nach denen der Kalender aus zwei Quellen eine Liste macht.
///
/// Genau hier wird ein Kalender still falsch: dieselbe Folge steht zweimal
/// drin, ein Eintrag rutscht über die Zeitzone auf den falschen Tag, oder eine
/// Ankündigung ohne Uhrzeit behauptet, um Mitternacht zu laufen. Nichts davon
/// fällt beim Draufschauen auf.
final class CalendarRulesTests: XCTestCase {

    // MARK: - Hilfen

    private func berlinCalendar() -> Calendar {
        calendar(in: "Europe/Berlin")
    }

    private func calendar(in identifier: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return cal
    }

    private func entry(
        slug: String = "one-piece",
        title: String = "One Piece",
        season: String = "1",
        episode: Int = 7,
        year: Int = 2026,
        month: Int = 9,
        day: Int = 14,
        hour: Int = 0,
        minute: Int = 0,
        hasTime: Bool = true,
        languages: [String] = ["DE"],
        coverPath: String? = nil,
        provider: CatalogProvider = .aniworld
    ) -> AiringEntry {
        AiringEntry(
            airingAt: berlinDate(year: year, month: month, day: day, hour: hour, minute: minute)
                .timeIntervalSince1970 * 1000,
            episode: episode,
            season: season,
            title: title,
            english: nil,
            slug: slug,
            languages: languages,
            dayKey: String(format: "%04d-%02d-%02d", year, month, day),
            dayLabel: "egal",
            coverPath: coverPath,
            hasTime: hasTime,
            provider: provider
        )
    }

    // MARK: - Entdoppeln

    /// Dieselbe Folge bei AniWorld **und** Serienstream ist ein Eintrag, nicht
    /// zwei. Vorher enthielt `AiringEntry.id` die Quelle, weshalb der Kalender
    /// sie doppelt zeigte.
    func testSameEpisodeFromBothProvidersBecomesOneRelease() {
        let releases = CalendarMerge.releases(
            from: [
                entry(languages: ["DE"], provider: .aniworld),
                entry(languages: ["GerSub"], provider: .serienstream),
            ],
            calendar: berlinCalendar()
        )

        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.providers, [.aniworld, .serienstream])
        XCTAssertEqual(releases.first?.languages, ["DE", "GerSub"])
    }

    /// Serienstream führt dieselbe Folge je Sprache einmal. Die Sprachen
    /// gehören zusammengelegt, nicht untereinander.
    func testSameEpisodeInTwoLanguagesBecomesOneRelease() {
        let releases = CalendarMerge.releases(
            from: [
                entry(languages: ["DE"], provider: .serienstream),
                entry(languages: ["EN"], provider: .serienstream),
            ],
            calendar: berlinCalendar()
        )

        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.languages, ["DE", "EN"])
        XCTAssertEqual(releases.first?.providers, [.serienstream])
    }

    /// Die geöffnete Quelle darf nicht davon abhängen, welcher Abruf zuerst
    /// zurückkam — sonst führt dieselbe Zeile mal hierhin und mal dorthin.
    func testPrimaryProviderIsStableRegardlessOfArrivalOrder() {
        let forwards = CalendarMerge.releases(
            from: [entry(provider: .serienstream), entry(provider: .aniworld)],
            calendar: berlinCalendar()
        )
        let backwards = CalendarMerge.releases(
            from: [entry(provider: .aniworld), entry(provider: .serienstream)],
            calendar: berlinCalendar()
        )

        XCTAssertEqual(forwards.first?.primaryProvider, .aniworld)
        XCTAssertEqual(backwards.first?.primaryProvider, .aniworld)
    }

    /// Das Cover steht oft nur bei einem der zusammengeführten Einträge.
    func testCoverSurvivesTheMerge() {
        let releases = CalendarMerge.releases(
            from: [
                entry(coverPath: nil, provider: .aniworld),
                entry(coverPath: "/cover.jpg", provider: .serienstream),
            ],
            calendar: berlinCalendar()
        )

        XCTAssertEqual(releases.first?.coverPath, "/cover.jpg")
    }

    /// Verschiedene Folgen bleiben verschieden — die Entdopplung darf nicht
    /// über das Ziel hinausschießen.
    func testDifferentEpisodesStayApart() {
        let releases = CalendarMerge.releases(
            from: [entry(episode: 7), entry(episode: 8)],
            calendar: berlinCalendar()
        )
        XCTAssertEqual(releases.count, 2)
    }

    // MARK: - Zeitzone

    /// Eine Ausstrahlung um 22:30 Berliner Zeit ist in Tokio am Folgetag. Der
    /// Kalender muss sie dort auch unter dem Folgetag einsortieren.
    func testTimedEntryIsBucketedInTheDeviceTimeZone() {
        let releases = CalendarMerge.releases(
            from: [entry(day: 14, hour: 22, minute: 30, hasTime: true)],
            calendar: calendar(in: "Asia/Tokyo")
        )

        XCTAssertEqual(releases.first?.dayKey, "2026-09-15")
    }

    /// Eine Ankündigung **ohne** Uhrzeit bleibt an ihrem veröffentlichten
    /// Datum — in jeder Zeitzone.
    ///
    /// Ihre Mitternacht ist eine Lücke, kein Zeitpunkt. Würde sie mit
    /// umgerechnet, wanderte der Eintrag westlich von Berlin um einen Tag
    /// zurück und stünde in New York am 14., obwohl „15. September"
    /// angekündigt war.
    func testUntimedEntryKeepsItsPublishedDate() {
        let tokyo = CalendarMerge.releases(
            from: [entry(day: 15, hasTime: false)],
            calendar: calendar(in: "Asia/Tokyo")
        )
        let newYork = CalendarMerge.releases(
            from: [entry(day: 15, hasTime: false)],
            calendar: calendar(in: "America/New_York")
        )

        XCTAssertEqual(tokyo.first?.dayKey, "2026-09-15")
        XCTAssertEqual(newYork.first?.dayKey, "2026-09-15")
    }

    /// `hasTime` muss die Zusammenführung überleben — daran hängt, ob die
    /// Zeile eine Uhrzeit zeigt.
    func testHasTimeSurvivesTheMerge() {
        let releases = CalendarMerge.releases(
            from: [entry(hour: 20, minute: 15, hasTime: true)],
            calendar: berlinCalendar()
        )
        XCTAssertEqual(releases.first?.hasTime, true)

        let untimed = CalendarMerge.releases(
            from: [entry(hasTime: false)],
            calendar: berlinCalendar()
        )
        XCTAssertEqual(untimed.first?.hasTime, false)
    }

    // MARK: - Reihenfolge

    /// Nach Tag, darin nach Zeit — und ein Eintrag ohne Uhrzeit steht am Ende
    /// **seines** Tages, nicht vor dem ganzen Rest.
    func testOrderIsByDayThenTimeWithUntimedLast() {
        let releases = CalendarMerge.releases(
            from: [
                entry(slug: "ohne-zeit", title: "Ohne Zeit", day: 14, hasTime: false),
                entry(slug: "abends", title: "Abends", day: 14, hour: 20, hasTime: true),
                entry(slug: "morgens", title: "Morgens", day: 14, hour: 9, hasTime: true),
                entry(slug: "tags-drauf", title: "Tags drauf", day: 15, hour: 8, hasTime: true),
            ],
            calendar: berlinCalendar()
        )

        XCTAssertEqual(releases.map(\.slug), ["morgens", "abends", "ohne-zeit", "tags-drauf"])
    }

    /// Bei gleicher Zeit entscheidet der Titel, damit die Reihenfolge nicht
    /// zufällig aus dem Wörterbuch fällt.
    func testEqualTimesAreOrderedByTitle() {
        let releases = CalendarMerge.releases(
            from: [
                entry(slug: "zeta", title: "Zeta", hour: 18),
                entry(slug: "alpha", title: "Alpha", hour: 18),
            ],
            calendar: berlinCalendar()
        )
        XCTAssertEqual(releases.map(\.title), ["Alpha", "Zeta"])
    }

    // MARK: - Filter

    private func release(
        slug: String = "one-piece",
        languages: [String] = ["DE"],
        providers: [CatalogProvider] = [.aniworld]
    ) -> CalendarRelease {
        CalendarRelease(
            slug: slug,
            title: slug,
            season: "1",
            episode: 1,
            airingAt: Date(timeIntervalSince1970: 0),
            hasTime: true,
            dayKey: "2026-09-14",
            providers: providers,
            languages: languages,
            coverPath: nil
        )
    }

    func testLanguageFilterUsesProviderAvailability() {
        var filter = CalendarFilter()
        filter.language = .subtitled

        XCTAssertTrue(CalendarSelection.matches(
            release(languages: ["DE", "GerSub"]), filter: filter, favorites: [], started: []
        ))
        XCTAssertFalse(CalendarSelection.matches(
            release(languages: ["DE"]), filter: filter, favorites: [], started: []
        ))
    }

    func testWatchlistFilterUsesTheLibrary() {
        var filter = CalendarFilter()
        filter.source = .watchlist

        XCTAssertTrue(CalendarSelection.matches(
            release(slug: "gemerkt"), filter: filter, favorites: ["gemerkt"], started: []
        ))
        XCTAssertFalse(CalendarSelection.matches(
            release(slug: "fremd"), filter: filter, favorites: ["gemerkt"], started: []
        ))
    }

    func testStartedFilterUsesProgress() {
        var filter = CalendarFilter()
        filter.source = .started

        XCTAssertTrue(CalendarSelection.matches(
            release(slug: "angefangen"), filter: filter, favorites: [], started: ["angefangen"]
        ))
        XCTAssertFalse(CalendarSelection.matches(
            release(slug: "neu"), filter: filter, favorites: [], started: ["angefangen"]
        ))
    }

    /// Ohne Einschränkung kommt alles durch — der Vorgabefilter darf nichts
    /// schlucken.
    func testDefaultFilterKeepsEverything() {
        let all = [release(slug: "a"), release(slug: "b", languages: ["EN"])]
        let kept = CalendarSelection.filtered(all, filter: CalendarFilter(), favorites: [], started: [])
        XCTAssertEqual(kept.count, 2)
    }

    // MARK: - Woche und Monat

    /// Montag bis Sonntag, unabhängig davon, wo die Woche laut Systemvorgabe
    /// beginnt. Sonst hiesse „diese Woche" in den USA etwas anderes als hier.
    func testWeekAlwaysStartsOnMonday() {
        var cal = berlinCalendar()
        cal.firstWeekday = 1 // Sonntag, wie in den USA
        let wednesday = berlinDate(year: 2026, month: 9, day: 16, hour: 12, minute: 0)

        let days = CalendarSelection.week(containing: wednesday, calendar: cal)

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(CalendarRelease.dayKey(for: days[0], calendar: cal), "2026-09-14")
        XCTAssertEqual(CalendarRelease.dayKey(for: days[6], calendar: cal), "2026-09-20")
    }

    /// Das Raster beginnt an der richtigen Spalte und endet auf einer vollen
    /// Zeile — sonst franst der Monat aus.
    func testMonthGridPadsToWholeWeeks() {
        let cal = berlinCalendar()
        let september = berlinDate(year: 2026, month: 9, day: 16, hour: 12, minute: 0)

        let cells = CalendarSelection.monthGrid(containing: september, calendar: cal)

        XCTAssertEqual(cells.count % 7, 0)
        // Der 1. September 2026 ist ein Dienstag: eine Spalte bleibt frei.
        XCTAssertNil(cells.first ?? nil)
        XCTAssertEqual(cells.compactMap { $0 }.count, 30)
        let first = try? XCTUnwrap(cells[1])
        XCTAssertEqual(first.map { CalendarRelease.dayKey(for: $0, calendar: cal) }, "2026-09-01")
    }

    /// Ein Tagesschlüssel muss sich zurück in ein Datum lesen lassen —
    /// darüber findet die Wochenleiste ihr Sprungziel.
    func testDayKeyRoundTrip() {
        let cal = berlinCalendar()
        let date = CalendarSelection.date(fromDayKey: "2026-09-15", calendar: cal)
        XCTAssertNotNil(date)
        XCTAssertEqual(date.map { CalendarRelease.dayKey(for: $0, calendar: cal) }, "2026-09-15")
        XCTAssertNil(CalendarSelection.date(fromDayKey: "kein-datum", calendar: cal))
    }

    /// Nach Tagen gebündelt und chronologisch — auch wenn die Eingabe es nicht
    /// ist.
    func testDaysAreGroupedAndOrdered() {
        let releases = CalendarMerge.releases(
            from: [
                entry(slug: "spaeter", day: 16, hour: 10),
                entry(slug: "frueher", day: 14, hour: 10),
                entry(slug: "auch-frueher", day: 14, hour: 20),
            ],
            calendar: berlinCalendar()
        )

        let days = CalendarSelection.days(releases, calendar: berlinCalendar())

        XCTAssertEqual(days.map(\.key), ["2026-09-14", "2026-09-16"])
        XCTAssertEqual(days.first?.releases.count, 2)
    }

    func testCountsPerDay() {
        let releases = CalendarMerge.releases(
            from: [entry(slug: "a", day: 14), entry(slug: "b", day: 14), entry(slug: "c", day: 15)],
            calendar: berlinCalendar()
        )
        let counts = CalendarSelection.counts(releases)

        XCTAssertEqual(counts["2026-09-14"], 2)
        XCTAssertEqual(counts["2026-09-15"], 1)
    }

    // MARK: - Beschriftung

    /// TMDB füllt unbenannte Folgen mit „Folge 11" bzw. „Episode 11" auf. Das
    /// ist kein Titel, sondern dieselbe Nummer noch einmal — im Kalender stand
    /// dadurch „Staffel 3 · Folge 11 · Folge 11".
    func testPlaceholderEpisodeTitlesAreNotTreatedAsTitles() {
        XCTAssertNil(EpisodeInfo(title: "Folge 11").namedTitle)
        XCTAssertNil(EpisodeInfo(title: "Episode 7").namedTitle)
        XCTAssertNil(EpisodeInfo(title: "folge 3").namedTitle)
        XCTAssertNil(EpisodeInfo(title: "  Folge 12  ").namedTitle)
        XCTAssertNil(EpisodeInfo(title: "   ").namedTitle)
        XCTAssertNil(EpisodeInfo(title: nil).namedTitle)
    }

    /// Ein echter Titel muss durchkommen — auch wenn er mit einer Zahl endet
    /// oder das Wort „Folge" enthält.
    func testRealEpisodeTitlesSurvive() {
        XCTAssertEqual(EpisodeInfo(title: "Der stille Turm").namedTitle, "Der stille Turm")
        XCTAssertEqual(EpisodeInfo(title: "Die letzte Folge des Sommers").namedTitle, "Die letzte Folge des Sommers")
        XCTAssertEqual(EpisodeInfo(title: "Kapitel 7").namedTitle, "Kapitel 7")
        XCTAssertEqual(EpisodeInfo(title: "Folge dem Licht").namedTitle, "Folge dem Licht")
    }

    /// Eine Folgennummer 0 heisst „die Quelle hat keine genannt" — dann steht
    /// dort nichts, statt „Folge 0".
    func testEpisodeLabelOmitsMissingNumbers() {
        let known = CalendarMerge.releases(from: [entry(season: "2", episode: 10)], calendar: berlinCalendar())
        XCTAssertEqual(known.first?.episodeLabel, "Staffel 2 · Folge 10")

        let unknown = CalendarMerge.releases(from: [entry(season: "2", episode: 0)], calendar: berlinCalendar())
        XCTAssertEqual(unknown.first?.episodeLabel, "Staffel 2")
    }
}
