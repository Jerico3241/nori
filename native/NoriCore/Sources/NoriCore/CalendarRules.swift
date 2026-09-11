import Foundation

// Die Regeln des Kalenders: Modus, Filter, der zusammengeführte
// Veröffentlichungseintrag, das Zusammenführen und die Auswahl.
//
// Bewusst hier und nicht bei den Ansichten. Die vorherige Kalenderansicht hatte
// ihr Zusammenführen, ihr Gruppieren und ihr Laden in derselben Datei wie die
// Zeilen — prüfbar war davon nichts, und „welche Folge erscheint heute" stand
// als Filterausdruck mitten in einer `ForEach`.
//
// Im Kern statt im iOS-Ziel, damit `swift test` sie erreicht: Entdopplung,
// Zeitzonen und die Reihenfolge sind genau die Stellen, an denen ein Kalender
// still falsch wird, und die lassen sich nur mit Tests festhalten. Dieselbe
// Bauform wie `HomeFeed.swift`, das aus demselben Grund hier liegt, obwohl es
// zurzeit nur das iOS-Ziel übersetzt.

// MARK: - Modus

/// Welchen Zeitraum der Kalender zeigt.
enum CalendarMode: String, CaseIterable, Identifiable, Hashable {
    case today
    case week
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Heute"
        case .week: return "Woche"
        case .month: return "Monat"
        }
    }
}

// MARK: - Filter

/// Was der Kalender zeigen soll.
///
/// Jede Möglichkeit hier muss sich aus Daten entscheiden lassen, die Nori
/// wirklich hat. Deshalb gibt es zum Beispiel keinen Filter „Nur laufende
/// Serien": ob eine Serie fortgesetzt wird oder abgeschlossen ist, sagt weder
/// AniWorld noch Serienstream, und TMDB wird von Nori nur nach Bildern und
/// Texten gefragt. Ein Filter, der die Hälfte der Einträge nach Gefühl
/// ausblendet, ist schlechter als keiner — „Nur begonnene Titel" tritt an
/// seine Stelle und entscheidet sich am gespeicherten Fortschritt.
///
/// ## Warum „Inhalt" hier fehlt
///
/// Anime gegen Serien ist in Nori `LibraryScope` — derselbe Bereich, den
/// Katalog und Merkliste verwenden, mit „K-Drama" als vierter Möglichkeit. Der
/// Filterbogen des Kalenders stellt ihn mit ein, statt daneben eine zweite
/// Anime/Serien-Unterscheidung zu führen, die mit der ersten auseinanderlaufen
/// könnte.
struct CalendarFilter: Equatable {
    /// Sprache aus der Verfügbarkeit der Quelle — nicht aus TMDB.
    enum Language: String, CaseIterable, Identifiable {
        case all
        case german
        case subtitled

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "Alle"
            case .german: return "Deutsch"
            case .subtitled: return "GerSub"
            }
        }

        /// Die Kennung, wie die Parser sie ablegen.
        var code: String? {
            switch self {
            case .all: return nil
            case .german: return "DE"
            case .subtitled: return "GerSub"
            }
        }
    }

    /// Woraus die Einträge kommen.
    enum Source: String, CaseIterable, Identifiable {
        case catalog
        case watchlist
        case started

        var id: String { rawValue }

        var label: String {
            switch self {
            case .catalog: return "Gesamter Katalog"
            case .watchlist: return "Nur Merkliste"
            case .started: return "Nur begonnene Titel"
            }
        }

        var note: String {
            switch self {
            case .catalog: return "Alles, was die Quellen ankündigen."
            case .watchlist: return "Nur Titel, die in deiner Merkliste stehen."
            case .started: return "Nur Titel, von denen du schon eine Folge angefangen hast."
            }
        }
    }

    var language: Language = .all
    var source: Source = .catalog

    var isDefault: Bool { self == CalendarFilter() }
}

// MARK: - Eintrag

/// Eine Veröffentlichung, wie der Bildschirm sie braucht.
///
/// Entsteht aus einem oder mehreren `AiringEntry`: dieselbe Folge steht bei
/// AniWorld und Serienstream, und bei Serienstream zusätzlich je Sprache
/// einmal. Hier ist sie **ein** Eintrag, der alle beteiligten Quellen und
/// Sprachen trägt.
struct CalendarRelease: Identifiable, Hashable {
    let slug: String
    let title: String
    let season: String
    let episode: Int
    /// Der Zeitpunkt als absoluter Augenblick. Bei Einträgen ohne genannte
    /// Uhrzeit ist das Mitternacht Berliner Zeit — brauchbar zum Sortieren,
    /// nicht zum Anzeigen. Siehe `hasTime`.
    let airingAt: Date
    /// Ob die Quelle eine Uhrzeit genannt hat. Nur dann zeigt die Zeile eine.
    let hasTime: Bool
    /// Der Tag, unter dem der Eintrag einsortiert wird — in der Zeitzone des
    /// Geräts, siehe `CalendarRelease.dayKey(for:)`.
    let dayKey: String
    /// Alle Quellen, die diese Folge an diesem Tag führen. Mehr als eine, wenn
    /// AniWorld und Serienstream dieselbe Folge ankündigen.
    var providers: [CatalogProvider]
    /// Alle Sprachen aller beteiligten Quellen, zusammengeführt.
    var languages: [String]
    var coverPath: String?

    /// Die Quelle, die beim Antippen geöffnet wird: die erste in der
    /// Rangfolge von `CatalogProvider.allCases`, damit die Wahl bei gleichem
    /// Datenstand immer gleich ausfällt.
    var primaryProvider: CatalogProvider { providers.first ?? .aniworld }

    var id: String { "\(slug)|\(season)|\(episode)|\(dayKey)" }

    /// Liegt der Zeitpunkt in der Vergangenheit? Dann ist die Folge da und
    /// darf geöffnet werden; sonst führt der Tipper nur auf die Detailseite.
    func isAvailable(now: Date = Date()) -> Bool { airingAt <= now }

    /// „S2 · F10" — ohne erfundene Angaben: eine Folgennummer 0 heißt, dass
    /// die Quelle keine genannt hat.
    var episodeLabel: String {
        var parts: [String] = []
        if !season.isEmpty { parts.append("Staffel \(season)") }
        if episode > 0 { parts.append("Folge \(episode)") }
        return parts.joined(separator: " · ")
    }

    /// Der Tagesschlüssel eines Zeitpunkts in der Zeitzone des Geräts.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

// MARK: - Zusammenführen

enum CalendarMerge {
    /// Aus den Einträgen beider Quellen eine Liste ohne Dubletten bauen.
    ///
    /// Geschlüsselt wird über Serie, Staffel, Folge und Tag — **ohne** Quelle
    /// und ohne Sprache. Genau das unterscheidet die Liste von der alten:
    /// `AiringEntry.id` enthält die Quelle, weshalb dieselbe Folge vorher
    /// zweimal im Kalender stand, wenn beide Seiten sie ankündigten, und bei
    /// Serienstream zusätzlich einmal je Sprache.
    ///
    /// Der Tag kommt bei Einträgen mit Uhrzeit aus dem Augenblick in der
    /// Zeitzone des Geräts, bei Einträgen ohne Uhrzeit aus dem veröffentlichten
    /// Datum. Das ist kein Widerspruch, sondern der Unterschied zwischen einer
    /// Ausstrahlung um 22:30 Berliner Zeit — die in Tokio am Folgetag liegt —
    /// und einer Ankündigung „am 15. September", die in jeder Zeitzone der
    /// 15. September bleibt. Würde Letztere umgerechnet, wanderte sie westlich
    /// von Berlin um einen Tag zurück, weil die künstliche Mitternacht mit
    /// umgerechnet würde.
    static func releases(from entries: [AiringEntry], calendar: Calendar) -> [CalendarRelease] {
        var merged: [String: CalendarRelease] = [:]

        for entry in entries {
            let date = Date(timeIntervalSince1970: entry.airingAt / 1000)
            let hasTime = entry.hasTime ?? false
            let day = hasTime ? CalendarRelease.dayKey(for: date, calendar: calendar) : entry.dayKey
            let key = "\(entry.slug)|\(entry.season)|\(entry.episode)|\(day)"
            let provider = entry.provider ?? .aniworld

            guard var existing = merged[key] else {
                merged[key] = CalendarRelease(
                    slug: entry.slug,
                    title: entry.title,
                    season: entry.season,
                    episode: entry.episode,
                    airingAt: date,
                    hasTime: hasTime,
                    dayKey: day,
                    providers: [provider],
                    languages: entry.languages,
                    coverPath: entry.coverPath
                )
                continue
            }

            for language in entry.languages where !existing.languages.contains(language) {
                existing.languages.append(language)
            }
            if !existing.providers.contains(provider) {
                existing.providers.append(provider)
                // Feste Rangfolge, damit bei gleichem Datenstand immer
                // dieselbe Quelle geöffnet wird — sonst entschiede die
                // Reihenfolge, in der die beiden Abrufe zurückkamen.
                existing.providers.sort { left, right in
                    let order = CatalogProvider.allCases
                    return (order.firstIndex(of: left) ?? 0) < (order.firstIndex(of: right) ?? 0)
                }
            }
            if existing.coverPath == nil { existing.coverPath = entry.coverPath }
            merged[key] = existing
        }

        return merged.values.sorted(by: order)
    }

    /// Nach Tag, darin chronologisch, bei gleicher Zeit alphabetisch.
    ///
    /// Der **Tag** kommt zuerst und nicht der Zeitpunkt. Das ist der
    /// Unterschied, der einen Eintrag ohne Uhrzeit richtig einordnet: seine
    /// künstliche Mitternacht ist eine Lücke, keine frühe Ausstrahlung. Nach
    /// dem Zeitpunkt allein sortiert stünde „am 15. September" vor der
    /// Ausstrahlung am 14. um 20:15 — und innerhalb des 15. ganz vorn, als
    /// käme sie zuerst. Nach dem Tag sortiert steht sie am Ende ihres eigenen
    /// Tages, wo sie hingehört.
    static func order(_ left: CalendarRelease, _ right: CalendarRelease) -> Bool {
        if left.dayKey != right.dayKey { return left.dayKey < right.dayKey }
        if left.hasTime != right.hasTime { return left.hasTime }
        if left.airingAt != right.airingAt { return left.airingAt < right.airingAt }
        return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
}

// MARK: - Auswahl

/// Die Auswahlregeln des Kalenders: filtern, nach Tagen bündeln, zählen.
///
/// Freie Funktionen auf einem Wertetyp, nicht Methoden der Ansicht — damit
/// „was erscheint heute" eine Regel ist und kein Filterausdruck mitten in
/// einer `ForEach`.
enum CalendarSelection {
    /// Ein Tag mit seinen Veröffentlichungen.
    struct Day: Identifiable, Hashable {
        let key: String
        let date: Date
        var releases: [CalendarRelease]
        var id: String { key }
    }

    /// Passt der Eintrag zum Filter?
    static func matches(
        _ release: CalendarRelease,
        filter: CalendarFilter,
        favorites: Set<String>,
        started: Set<String>
    ) -> Bool {
        if let code = filter.language.code, !release.languages.contains(code) {
            return false
        }
        switch filter.source {
        case .catalog: break
        case .watchlist: if !favorites.contains(release.slug) { return false }
        case .started: if !started.contains(release.slug) { return false }
        }
        return true
    }

    static func filtered(
        _ releases: [CalendarRelease],
        filter: CalendarFilter,
        favorites: Set<String>,
        started: Set<String>
    ) -> [CalendarRelease] {
        releases.filter { matches($0, filter: filter, favorites: favorites, started: started) }
    }

    /// Die Veröffentlichungen eines einzelnen Tages.
    static func releases(_ releases: [CalendarRelease], on day: Date, calendar: Calendar) -> [CalendarRelease] {
        let key = CalendarRelease.dayKey(for: day, calendar: calendar)
        return releases.filter { $0.dayKey == key }
    }

    /// Nach Tagen gebündelt, chronologisch — für die Wochen- und Monatsliste.
    static func days(_ releases: [CalendarRelease], calendar: Calendar) -> [Day] {
        var order: [String] = []
        var map: [String: [CalendarRelease]] = [:]
        for release in releases {
            if map[release.dayKey] == nil { order.append(release.dayKey) }
            map[release.dayKey, default: []].append(release)
        }
        return order.sorted().compactMap { key in
            guard let date = date(fromDayKey: key, calendar: calendar) else { return nil }
            return Day(key: key, date: date, releases: map[key] ?? [])
        }
    }

    /// Wie viele Veröffentlichungen je Tagesschlüssel — für die Punkte im
    /// Monatsraster.
    static func counts(_ releases: [CalendarRelease]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for release in releases { counts[release.dayKey, default: 0] += 1 }
        return counts
    }

    /// Einen Tagesschlüssel („2026-09-15") zurück in ein Datum.
    static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    /// Montag bis Sonntag der Woche, in der `date` liegt.
    ///
    /// Ausdrücklich Montag als erster Tag, unabhängig von der Systemvorgabe:
    /// die Vorlage zeigt Mo–So, und ein Kalender, der in den USA sonntags
    /// beginnt und hier montags, hätte zwei verschiedene „Diese Woche".
    static func week(containing date: Date, calendar: Calendar) -> [Date] {
        var german = calendar
        german.firstWeekday = 2
        guard let start = german.dateInterval(of: .weekOfYear, for: date)?.start else { return [date] }
        return (0 ..< 7).compactMap { german.date(byAdding: .day, value: $0, to: start) }
    }

    /// Alle Tage des Monats, in dem `date` liegt, mit den Leerfeldern davor,
    /// damit die erste Woche an der richtigen Spalte beginnt.
    ///
    /// `nil` steht für ein Leerfeld. Dadurch braucht das Raster keine
    /// Sonderbehandlung für den Monatsanfang.
    static func monthGrid(containing date: Date, calendar: Calendar) -> [Date?] {
        var german = calendar
        german.firstWeekday = 2
        guard let interval = german.dateInterval(of: .month, for: date),
              let count = german.range(of: .day, in: .month, for: date)?.count
        else { return [] }

        // Wie viele Spalten bis zum Ersten frei bleiben. `weekday` zählt ab
        // Sonntag = 1; mit Montag als erstem Tag verschiebt sich das um eins.
        let weekday = german.component(.weekday, from: interval.start)
        let leading = (weekday - german.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0 ..< count {
            cells.append(german.date(byAdding: .day, value: offset, to: interval.start))
        }
        // Die letzte Zeile auffüllen, damit das Raster nicht ausfranst.
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}
