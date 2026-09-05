import Foundation

enum CatalogProvider: String, Codable, CaseIterable, Identifiable {
    case aniworld
    case serienstream

    var id: String { rawValue }
    var label: String { self == .aniworld ? "AniWorld" : "Serienstream" }
    var kind: String { self == .aniworld ? "Anime" : "Serien" }
    var origin: String { self == .aniworld ? "https://aniworld.to" : "https://serienstream.to" }
    var catalogPath: String { self == .aniworld ? "/animes" : "/serien?by=genre" }
    var calendarPath: String { self == .aniworld ? "/animekalender" : "/api/calendar" }
    var streamPrefix: String { self == .aniworld ? "/anime/stream" : "/serie" }

    func seriesPath(slug: String, season: String? = nil) -> String {
        let base = "\(streamPrefix)/\(slug)"
        guard let season, !season.isEmpty else { return base }
        if season == "filme" { return "\(base)/filme" }
        return "\(base)/staffel-\(season)"
    }

    func episodePath(slug: String, season: String, episode: Int) -> String {
        if season == "filme" { return "\(streamPrefix)/\(slug)/filme/film-\(episode)" }
        return "\(streamPrefix)/\(slug)/staffel-\(season.isEmpty ? "1" : season)/episode-\(episode)"
    }

    /// Verzeichnis, in dem die Quelle ihre Cover ablegt.
    var coverDirectory: String {
        self == .aniworld ? "/public/img/cover/" : "/media/images/channel/desktop/"
    }

    /// Wahrscheinlicher Coverpfad, allein aus dem Slug gebildet.
    ///
    /// Warum das nötig ist: ein Katalogeintrag trägt kein Bild — die
    /// Katalogseite der Quellen ist eine reine Titelliste. Das Cover lernt Nori
    /// sonst erst, wenn die Serie geöffnet wird. Im Raster bleibt bis dahin nur
    /// TMDB, und findet TMDB nichts, ein Buchstabe. Genau das waren die leeren
    /// Kacheln.
    ///
    /// Dass der Dateiname der Slug ist, verlässt `HTML.slugFromPoster` bereits
    /// in der Gegenrichtung: dort wird aus dem Posternamen der Slug gewonnen.
    /// Trifft die Vermutung nicht, antwortet die Quelle mit 404 und es bleibt
    /// beim Buchstaben — also nicht schlechter als vorher.
    func guessedCoverPath(slug: String) -> String? {
        // Nur unauffällige Slugs. Ein Slug mit Schrägstrich oder Punkt würde
        // sonst aus dem Cover-Verzeichnis herausführen.
        guard !slug.isEmpty,
              slug.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return nil }
        return coverDirectory + slug + ".jpg"
    }
}

/// Was die Bibliothek zeigt.
///
/// Getrennt von `CatalogProvider`: der entscheidet weiter, wohin ein einzelner
/// Titel führt. Der Bereich entscheidet nur, was in den Listen steht. Vorher
/// war beides dasselbe — der Umschalter war ein Moduswechsel, und eine Liste
/// konnte nur Titel einer Quelle enthalten.
enum LibraryScope: String, Codable, CaseIterable, Identifiable {
    case all
    case aniworld
    case serienstream

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Alle"
        case .aniworld: return "Anime"
        case .serienstream: return "Serien"
        }
    }

    /// Überschrift der großen Liste auf der Startseite.
    var headline: String {
        switch self {
        case .all: return "Alle Titel"
        case .aniworld: return "Alle Anime"
        case .serienstream: return "Alle Serien"
        }
    }

    /// Die zugehörige Quelle, oder `nil` für „beide".
    var provider: CatalogProvider? {
        switch self {
        case .all: return nil
        case .aniworld: return .aniworld
        case .serienstream: return .serienstream
        }
    }

    /// Gehört ein Eintrag dieser Quelle in den Bereich?
    func includes(_ other: CatalogProvider?) -> Bool {
        guard let provider else { return true }
        // Einträge ohne Quelle stammen aus einem älteren gespeicherten Stand
        // und werden nicht ausgefiltert — sonst verschwänden sie ganz.
        guard let other else { return true }
        return provider == other
    }
}

struct CatalogItem: Codable, Identifiable, Hashable {
    var slug: String
    var title: String
    var alts: [String]
    var genres: [String]
    /// Woher der Eintrag stammt.
    ///
    /// Optional, damit ältere gespeicherte Kataloge weiter dekodieren, und
    /// vom Parser bewusst nicht gesetzt: der sieht nur HTML und weiß nicht,
    /// welche Seite er gerade liest. Gestempelt wird beim Laden in
    /// `AniworldClient.getCatalog`.
    ///
    /// Ohne dieses Feld kann eine Liste nur Titel **einer** Quelle enthalten —
    /// jede Kachel bräuchte sonst den globalen Umschalter, um zu wissen, wohin
    /// sie führt. Es ist die Voraussetzung für eine gemeinsame Bibliothek.
    var provider: CatalogProvider? = nil
    /// Zwei Quellen können denselben Slug führen. Die Kennung trägt deshalb
    /// beides, sonst fielen in einer gemeinsamen Liste Einträge weg.
    var id: String { "\(provider?.rawValue ?? "?")|\(slug)" }
}

struct CatalogResult: Codable {
    var items: [CatalogItem]
    var source: String
    var fetchedAt: Double
}

struct SeasonRef: Codable, Identifiable, Hashable {
    var id: String
    var label: String
}

struct Episode: Codable, Identifiable, Hashable {
    var number: Int
    var germanTitle: String
    var englishTitle: String
    var path: String
    var hosters: [String]
    var languages: [String]
    var id: String { path.isEmpty ? "\(number)" : path }
}

struct SeriesDetail: Codable, Hashable {
    var slug: String
    var title: String
    var alts: [String]
    var description: String
    var coverPath: String?
    var yearStart: String?
    var yearEnd: String?
    var fsk: String?
    var imdb: String?
    var genres: [String]
    var seasons: [SeasonRef]
    var activeSeason: String
    var episodes: [Episode]
}

struct HosterOption: Codable, Hashable {
    var name: String
    var lang: String
    var langKey: String
    var redirectPath: String
}

struct WatchInfo: Codable {
    var path: String
    var title: String
    var germanTitle: String
    var englishTitle: String
    var hosters: [HosterOption]
}

enum PlayKind: String, Codable {
    case hls
    case mp4
}

struct PlaySource: Codable {
    var kind: PlayKind
    var url: String
    var hoster: String
    var lang: String
    /// Seite, von der der Stream stammt. Viele Hoster liefern das Video nur
    /// aus, wenn der Abruf diesen Referer mitschickt — AVPlayer muss ihn
    /// deshalb am Asset gesetzt bekommen.
    var referer: String?
}

struct WatchProgress: Codable, Identifiable, Hashable {
    var slug: String
    var title: String
    var season: String
    var episode: Int
    var episodePath: String
    var germanTitle: String
    var englishTitle: String
    var positionSec: Double
    var durationSec: Double
    var updatedAt: Double
    var lang: String?
    var completed: Bool?
    // Added in library schema v2. Optional so existing 1.x library.json files decode cleanly.
    var provider: CatalogProvider?
    var id: String { "\(provider?.rawValue ?? providerFromPath(episodePath).rawValue)|\(episodePath)" }
}

struct RecentItem: Codable, Hashable {
    var slug: String
    var title: String
    var viewedAt: Double
    var provider: CatalogProvider?
}

struct AiringEntry: Codable, Identifiable, Hashable {
    var airingAt: Double
    var episode: Int
    var season: String
    var title: String
    var english: String?
    var slug: String
    var languages: [String]
    var dayKey: String
    var dayLabel: String
    /// Coverpfad, sofern die Quelle im Kalender einen mitliefert. Damit haben
    /// Kalendereinträge ein richtiges Bild, ohne dass die Serie erst geöffnet
    /// werden muss.
    var coverPath: String?
    /// Woher der Eintrag stammt. Wie bei `CatalogItem` beim Laden gestempelt,
    /// nicht im Parser. Ohne das könnte ein gemeinsamer Kalender nicht sagen,
    /// welche Seite ein Eintrag öffnet.
    var provider: CatalogProvider? = nil
    var id: String { "\(provider?.rawValue ?? "?")|\(slug)|\(season)|\(episode)|\(dayKey)" }
}

struct CalendarPayload: Codable {
    var upcoming: [AiringEntry]
    var recent: [AiringEntry]
    var fetchedAt: Double
}

enum NoriOrigin {
    static let aniworld = "https://aniworld.to"
    static let serienstream = "https://serienstream.to"
    static let ua =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}

func guessEpisodePath(slug: String, season: String, episode: Int, provider: CatalogProvider = .aniworld) -> String {
    provider.episodePath(slug: slug, season: season, episode: episode)
}

func providerFromPath(_ path: String) -> CatalogProvider {
    path.contains("/serie/") ? .serienstream : .aniworld
}

func normalizeEpisodePath(_ raw: String) -> String {
    var path = raw
    if path.hasPrefix("http"), let url = URL(string: path) {
        path = url.path
    }
    while path.hasSuffix("/") { path.removeLast() }
    return path
}

func progressKey(path: String, provider: CatalogProvider? = nil) -> String {
    let clean = normalizeEpisodePath(path)
    guard let provider else { return clean }
    return "\(provider.rawValue)|\(clean)"
}

func isEpisodeComplete(_ item: WatchProgress?) -> Bool {
    guard let item else { return false }
    if item.completed == true { return true }
    return item.durationSec >= 20 && item.positionSec >= item.durationSec * 0.9
}

func watchRatio(_ item: WatchProgress?) -> Double {
    guard let item else { return 0 }
    if isEpisodeComplete(item) { return 1 }
    if item.durationSec < 8 { return 0 }
    return min(1, max(0, item.positionSec / item.durationSec))
}

func resumePosition(_ item: WatchProgress?) -> Double {
    guard let item, !isEpisodeComplete(item) else { return 0 }
    if item.positionSec < 8 { return 0 }
    return item.positionSec
}

func formatClock(_ sec: Double) -> String {
    let s = max(0, Int(sec.rounded(.down)))
    let h = s / 3600
    let m = (s % 3600) / 60
    let r = s % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, r) }
    return String(format: "%d:%02d", m, r)
}

func berlinDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    var parts = DateComponents()
    parts.calendar = Calendar(identifier: .gregorian)
    parts.timeZone = TimeZone(identifier: "Europe/Berlin")
    parts.year = year
    parts.month = month
    parts.day = day
    parts.hour = hour
    parts.minute = minute
    return parts.date ?? Date()
}