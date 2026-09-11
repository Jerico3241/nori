import Foundation

// Was Noris Katalog zeigt — und woher jede einzelne Angabe stammt.
//
// Diese Datei enthält **keine** Oberfläche und kein Netz, nur Werte und
// Rechnungen. Dieselbe Aufteilung wie bei der Startseite, und aus demselben
// Grund: Ob „Neu" wirklich neu ist, ob „Top bewertet" sinnvoll gewichtet ist
// und ob ein Filter tatsächlich filtert, sieht man einer Rasteransicht nicht
// an. Als reine Funktionen lässt sich das durchspielen (siehe
// `CatalogFeedTests`), als verstreute Sortierung in einem SwiftUI-Body nicht.
//
// Die Aufgabenteilung ist dieselbe wie überall in Nori:
//
//     Nori-Provider  →  Was gibt es überhaupt? Welche Sprachen? Was ist neu?
//     TMDB           →  Was ist das, wie sieht es aus, wie beliebt/bewertet?
//
// Ein Katalogeintrag entsteht deshalb ausschließlich aus `CatalogItem`, also
// aus dem, was AniWorld oder Serienstream tatsächlich führen. Es gibt bewusst
// keinen Weg, aus einer TMDB-Zeile einen Katalogeintrag zu **erzeugen** —
// sonst stünden Kacheln im Raster, die beim Antippen nichts öffnen.

// MARK: - Medientyp

/// Anime oder Serie.
///
/// Ergibt sich aus der Quelle und nicht aus TMDB: AniWorld führt Anime,
/// Serienstream Realserien, und `HTML.dropAnimeTitles` hält Anime aus der
/// Serienliste heraus. Das ist die verlässlichste Auskunft, die es gibt —
/// TMDBs Genre „Animation" träfe auch westliche Zeichentrickserien.
enum CatalogMediaType: String, Codable, CaseIterable, Hashable, Identifiable {
    case anime
    case series

    var id: String { rawValue }

    /// Beschriftung im Filter — Mehrzahl, weil sie dort eine Menge benennt.
    var label: String {
        switch self {
        case .anime: return "Anime"
        case .series: return "Serien"
        }
    }

    /// Beschriftung auf dem Poster — Einzahl, sie benennt diesen einen Titel.
    var badge: String {
        switch self {
        case .anime: return "ANIME"
        case .series: return "SERIE"
        }
    }

    init(_ provider: CatalogProvider) {
        switch provider {
        case .aniworld: self = .anime
        case .serienstream: self = .series
        }
    }
}

// MARK: - Status

/// Läuft die Serie noch?
///
/// `unknown` ist der Normalfall und kein Fehler. Die Katalogseiten beider
/// Quellen sind reine Titellisten ohne Statusangabe, und TMDBs Ranglisten
/// führen das Feld ebenfalls nicht mit. Wer es genau wissen will, müsste pro
/// Titel eine Detailseite laden — bei zehntausend Einträgen ausgeschlossen.
///
/// Deshalb gilt hier: **nur positive Belege zählen.** Ein Titel, über den
/// nichts bekannt ist, bekommt `unknown` und fällt aus dem Statusfilter
/// heraus, statt geraten zu werden. Der Filter bietet einen Status außerdem
/// nur an, wenn er im geladenen Katalog überhaupt vorkommt — siehe
/// `CatalogFacets`.
enum CatalogStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    /// Belegt durch Noris eigenen Kalender oder durch TMDBs Liste kürzlich
    /// ausgestrahlter Serien.
    case running
    /// Belegt durch TMDBs Liste abgeschlossener bzw. abgesetzter Serien.
    case completed
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .running: return "Laufend"
        case .completed: return "Abgeschlossen"
        case .unknown: return "Unbekannt"
        }
    }

    var isKnown: Bool { self != .unknown }
}

// MARK: - Sprache

/// Die Sprachfassungen, die Nori kennt.
///
/// Die Rohwerte sind dieselben Kürzel, die `HTML.langLabel` aus den
/// Seitenquellen liest, und dieselben, die `contract.json` unter `langOrder`
/// führt. Bewusst **nicht** TMDBs `original_language`: gefragt ist, in welcher
/// Fassung Nori die Folgen tatsächlich ausliefert, nicht in welcher Sprache
/// die Serie gedreht wurde.
enum CatalogLanguage: String, Codable, CaseIterable, Hashable, Identifiable {
    case german = "DE"
    case gerSub = "GerSub"
    case english = "EN"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .german: return "Deutsch"
        case .gerSub: return "GerSub"
        case .english: return "Englisch"
        }
    }

    /// Die Reihenfolge aus `contract.json`: DE, GerSub, EN.
    var order: Int {
        switch self {
        case .german: return 0
        case .gerSub: return 1
        case .english: return 2
        }
    }

    /// Aus einer Angabe der Quelle. Kalender und Folgenliste schreiben die
    /// Kürzel, ältere Stände gelegentlich ausgeschriebene Wörter.
    static func parse(_ raw: String) -> CatalogLanguage? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.isEmpty { return nil }
        if key.contains("gersub") || key.contains("untertitel") || key.contains("sub") { return .gerSub }
        if key.hasPrefix("de") || key.contains("deutsch") || key.contains("german") { return .german }
        if key.hasPrefix("en") || key.contains("englisch") || key.contains("english") { return .english }
        return nil
    }
}

// MARK: - Genres

/// Ein gemeinsamer Genre-Wortschatz für beide Quellen und TMDB.
///
/// AniWorld schreibt „Sci-Fi", Serienstream „Science Fiction", TMDB liefert
/// die Kennung 10765 („Sci-Fi & Fantasy"). Ohne Zusammenführung wären das drei
/// Filter, von denen jeder ein Drittel der Treffer zeigt — genau der Fall, den
/// die Aufgabe ausschließt.
///
/// Unbekannte Bezeichnungen werden **nicht** verworfen, sondern in ihrer
/// Schreibweise aus der Quelle übernommen. Eine feste Liste erlaubter Genres
/// würde still alles ausblenden, was die Quellen morgen dazunehmen.
enum CatalogGenres {
    /// Gleichbedeutende Schreibweisen, normalisiert als Schlüssel.
    private static let aliases: [String: String] = [
        "action": "Action",
        "abenteuer": "Abenteuer",
        "adventure": "Abenteuer",
        "animation": "Animation",
        "zeichentrick": "Animation",
        "comedy": "Comedy",
        "komodie": "Comedy",
        "komoedie": "Comedy",
        "drama": "Drama",
        "dokumentation": "Dokumentation",
        "dokumentarfilm": "Dokumentation",
        "documentary": "Dokumentation",
        "doku": "Dokumentation",
        "familie": "Familie",
        "family": "Familie",
        "fantasy": "Fantasy",
        "historisch": "Historisch",
        "history": "Historisch",
        "geschichte": "Historisch",
        "horror": "Horror",
        "kinder": "Kinder",
        "kids": "Kinder",
        "krieg": "Krieg",
        "war": "Krieg",
        "war politics": "Krieg",
        "krimi": "Krimi",
        "crime": "Krimi",
        "kriminalitat": "Krimi",
        "magie": "Magie",
        "magic": "Magie",
        "musik": "Musik",
        "music": "Musik",
        "mystery": "Mystery",
        "mysterie": "Mystery",
        "romance": "Romance",
        "romanze": "Romance",
        "romantik": "Romance",
        "sci fi": "Sci-Fi",
        "scifi": "Sci-Fi",
        "science fiction": "Sci-Fi",
        "sci fi fantasy": "Sci-Fi",
        "schule": "Schule",
        "school": "Schule",
        "slice of life": "Slice of Life",
        "sport": "Sport",
        "thriller": "Thriller",
        "western": "Western",
        "reality": "Reality",
        "talk": "Talk",
        "news": "News",
        "soap": "Soap",
        "k drama": "K-Drama",
        "kdrama": "K-Drama",
    ]

    /// TMDBs Fernsehgenres. Zwei davon fassen je zwei Nori-Genres zusammen und
    /// werden deshalb auf beide abgebildet — „Sci-Fi & Fantasy" ist bei TMDB
    /// eine Kennung, in jedem Katalog der Welt aber zwei Genres.
    private static let tmdb: [Int: [String]] = [
        10759: ["Action", "Abenteuer"],
        16: ["Animation"],
        35: ["Comedy"],
        80: ["Krimi"],
        99: ["Dokumentation"],
        18: ["Drama"],
        10751: ["Familie"],
        10762: ["Kinder"],
        9648: ["Mystery"],
        10763: ["News"],
        10764: ["Reality"],
        10765: ["Sci-Fi", "Fantasy"],
        10766: ["Soap"],
        10767: ["Talk"],
        10768: ["Krieg"],
        37: ["Western"],
    ]

    /// Die gemeinsame Schreibweise zu einer Angabe der Quelle.
    ///
    /// Gibt `nil` zurück, wenn nichts Brauchbares übrig bleibt — ein leeres
    /// Genre ist kein Genre.
    static func canonical(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = TMDBMatcher.normalize(trimmed)
        guard !key.isEmpty else { return nil }
        if let known = aliases[key] { return known }
        return trimmed
    }

    /// Die gemeinsamen Schreibweisen zu TMDBs Genrekennungen.
    static func canonical(tmdbIDs: [Int]) -> [String] {
        var out: [String] = []
        for id in tmdbIDs {
            for name in tmdb[id] ?? [] where !out.contains(name) {
                out.append(name)
            }
        }
        return out
    }

    /// Mehrere Angaben auf einmal, entdoppelt und in Reihenfolge des Auftretens.
    static func canonical(_ raws: [String]) -> [String] {
        var out: [String] = []
        for raw in raws {
            guard let name = canonical(raw), !out.contains(name) else { continue }
            out.append(name)
        }
        return out
    }
}

// MARK: - Eintrag

/// Wo ein Katalogtitel herkommt: Quelle und Slug.
///
/// Ein Eintrag kann mehrere davon haben, wenn beide Seiten denselben Titel
/// führen. Die Oberfläche zeigt ihn dann **einmal**; welche Quelle beim
/// Antippen geöffnet wird, entscheidet `primary`.
struct CatalogSource: Codable, Hashable, Identifiable {
    var provider: CatalogProvider
    var slug: String
    var title: String

    /// Dieselbe Kennung wie bei `CatalogItem` und `HomeTitle`: zwei Quellen
    /// können denselben Slug führen.
    var id: String { "\(provider.rawValue)|\(slug)" }
}

/// Ein Titel im Katalog — normalisiert, zusammengeführt, angereichert.
///
/// Die Ansicht bekommt genau diesen Typ und setzt sich nichts mehr aus
/// Providerstrukturen zusammen. Alles, was TMDB beisteuert, steckt in
/// `signals` und ist durchgehend optional: ohne Schlüssel, ohne Netz und ohne
/// sicheren Treffer bleibt es leer, und der Katalog steht trotzdem.
struct CatalogEntry: Identifiable, Hashable {
    /// Die Quelle, die beim Antippen geöffnet wird.
    var primary: CatalogSource
    /// Weitere Quellen, die denselben Titel führen.
    var alternates: [CatalogSource] = []

    var title: String = ""
    /// Originaltitel laut TMDB, sofern zugeordnet.
    var originalTitle: String?
    /// Alternativtitel der Quelle und weitere Schreibweisen von TMDB.
    var alternativeTitles: [String] = []
    var year: Int?
    var genres: [String] = []
    var status: CatalogStatus = .unknown
    /// Sprachfassungen, die Nori für diesen Titel belegen kann.
    var languages: [CatalogLanguage] = []
    /// Was TMDB beisteuert. Leer ist der Normalfall.
    var signals: TMDBSignals = .empty
    /// Hat Nori in den letzten Tagen eine neue Folge dazu gesehen? Aus dem
    /// eigenen Kalender, nicht aus TMDB.
    var hasFreshEpisode: Bool = false
    /// Vorbereitete Suchfelder — normalisiert, damit die Suche bei jeder
    /// Eingabe nur noch vergleicht und nicht erneut entkernt.
    var searchKey: String = ""
    /// Der Titel, normalisiert — kleingeschrieben, ohne Akzente, ohne
    /// Satzzeichen. Das Bündelungsmerkmal beim Zusammenführen zweier Quellen.
    ///
    /// Ausdrücklich **ohne** `stripVariants`: Das Abziehen von Staffel- und
    /// Jahresangaben ist für eine TMDB-Suche richtig, für eine Zusammenführung
    /// aber zu grob. „Titel 1999" und „Titel 2000" ergäben denselben
    /// Schlüssel, und das Zusammenführen entfernt einen Titel aus dem
    /// Katalog — ein Fehler, der sich nicht aus der Ansicht heraus bemerken
    /// lässt.
    var titleKey: String = ""

    /// Weitere Formen, unter denen derselbe Titel geführt wird — die
    /// normalisierten Alternativtitel.
    ///
    /// AniWorld führt „Dämonenjäger", Serienstream „Demon Slayer"; verbunden
    /// sind die beiden allein über den Alternativtitel der einen Seite. Nur
    /// vollständige Titel, nicht Wortteile: ein Teiltreffer würde Titel
    /// zusammenwerfen, die nichts miteinander zu tun haben.
    var mergeKeys: [String] = []

    var id: String { primary.id }
    var slug: String { primary.slug }
    var provider: CatalogProvider { primary.provider }
    var sources: [CatalogSource] { [primary] + alternates }

    /// Welche Medientypen dieser Eintrag abdeckt.
    ///
    /// In aller Regel genau einer. Führen beide Seiten denselben Stoff — als
    /// Anime und als Realserie —, gehört der Eintrag in beide Filter, sonst
    /// verschwände er bei einer der beiden Auswahlen.
    var mediaTypes: Set<CatalogMediaType> {
        Set(sources.map { CatalogMediaType($0.provider) })
    }

    /// Der Typ, den die Kachel anzeigt.
    var mediaType: CatalogMediaType { CatalogMediaType(provider) }

    var tmdbID: Int? { signals.tmdbID }
    /// TMDBs Bewertung, 0–10.
    var rating: Double? {
        guard let value = signals.voteAverage, value > 0 else { return nil }
        return value
    }
    /// Dieselbe Bewertung als Fünf-Sterne-Wert — die Darstellung, die auch die
    /// Detailseite verwendet (`CoverDetails.stars`). Zwei Skalen in einer App
    /// wären eine Falle.
    var stars: Double? { rating.map { $0 / 2 } }
    var voteCount: Int? { signals.voteCount }
    var popularity: Double? { signals.popularity }

    /// Die Zeile unter dem Titel: Jahr · Genre · Status.
    func metaLine(status showStatus: Bool = true) -> String {
        var parts: [String] = []
        if let year { parts.append(String(year)) }
        if let genre = genres.first { parts.append(genre) }
        if showStatus, self.status.isKnown { parts.append(self.status.label) }
        if parts.isEmpty { parts.append(mediaType.label) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Abzeichen

/// Was auf einem Poster stehen darf.
///
/// Ausschließlich aus belegten Angaben. Ein dekoratives „NEU" auf jeder
/// zweiten Kachel wäre eine Behauptung, die der Katalog nicht einlöst — und
/// „TOP 10" auf einem Titel, der auf keiner Rangliste steht, eine Erfindung.
enum CatalogBadge: Hashable {
    /// Neu im Sinne von `CatalogRanking.isNew`.
    case fresh
    /// Platz in TMDBs Wochenliste. Dieselbe Regel wie auf der Startseite
    /// (`HomeBadge`), damit derselbe Titel nicht auf zwei Bildschirmen
    /// Unterschiedliches behauptet.
    case top(Int)
    /// Abgeschlossen — nur bei belegtem Status.
    case complete
    case kind(CatalogMediaType)

    var label: String {
        switch self {
        case .fresh: return "NEU"
        case .top: return "TOP 10"
        case .complete: return "KOMPLETT"
        case .kind(let type): return type.badge
        }
    }

    var spoken: String {
        switch self {
        case .fresh: return "Neu"
        case .top(let rank): return "Platz \(rank) der Trendliste"
        case .complete: return "Abgeschlossen"
        case .kind(let type): return type.label
        }
    }
}

// MARK: - Sortierung

enum CatalogSort: String, Codable, CaseIterable, Hashable, Identifiable {
    case popular
    case newest
    case oldest
    case rating
    case titleAscending
    case titleDescending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .popular: return "Beliebt"
        case .newest: return "Neueste"
        case .oldest: return "Älteste"
        case .rating: return "Bewertung"
        case .titleAscending: return "A–Z"
        case .titleDescending: return "Z–A"
        }
    }

    /// Beschriftung der Sortiertaste über dem Raster. Der Pfeil steht nur
    /// dort, wo „absteigend" überhaupt etwas bedeutet.
    var pillLabel: String {
        switch self {
        case .popular, .newest, .rating: return label + " ↓"
        case .oldest: return label + " ↑"
        case .titleAscending, .titleDescending: return label
        }
    }
}

// MARK: - Schnellfilter

/// Die Leiste unter der Suche.
///
/// Die Genre-Einträge werden **nicht** fest verdrahtet, sondern aus dem
/// geladenen Katalog abgeleitet (`CatalogFacets.genres`). Eine feste Liste
/// wäre entweder unvollständig oder enthielte Pillen ohne Treffer.
enum CatalogQuickFilter: Hashable, Identifiable {
    case all
    case fresh
    case popular
    case topRated
    case genre(String)

    var id: String {
        switch self {
        case .all: return "all"
        case .fresh: return "fresh"
        case .popular: return "popular"
        case .topRated: return "topRated"
        case .genre(let name): return "genre:" + name
        }
    }

    var label: String {
        switch self {
        case .all: return "Alle"
        case .fresh: return "Neu"
        case .popular: return "Beliebt"
        case .topRated: return "Top bewertet"
        case .genre(let name): return name
        }
    }

    /// Die Überschrift über dem Raster.
    var headline: String {
        switch self {
        case .all: return "Alle Titel"
        default: return label
        }
    }

    /// Die Sortierung, die dieser Schnellfilter mitbringt.
    ///
    /// „Beliebt" ohne Beliebtheitssortierung wäre eine Überschrift ohne
    /// Deckung. `nil` heißt „ändert die Sortierung nicht".
    var impliedSort: CatalogSort? {
        switch self {
        case .popular: return .popular
        case .topRated: return .rating
        case .fresh: return .newest
        case .all, .genre: return nil
        }
    }
}

// MARK: - Filter

/// Die erweiterten Filter aus dem Filter-Blatt.
struct CatalogFilters: Hashable {
    /// `nil` heißt „alle".
    var mediaType: CatalogMediaType?
    /// `nil` heißt „alle". `unknown` kommt hier nie vor — „Status unbekannt"
    /// ist keine Auswahl, sondern das Fehlen einer Angabe.
    var status: CatalogStatus?
    var genres: Set<String> = []
    var language: CatalogLanguage?
    /// `nil` heißt „alle Jahre". Die Grenzen leitet die Oberfläche aus den
    /// tatsächlich vorhandenen Jahren ab, nicht aus einer festen Spanne.
    var years: ClosedRange<Int>?

    static let none = CatalogFilters()

    var isEmpty: Bool {
        mediaType == nil && status == nil && genres.isEmpty && language == nil && years == nil
    }

    /// Die sichtbaren Filter-Tags über dem Raster — „Warum sehe ich diese
    /// Ergebnisse?"
    func tags(fullYearRange: ClosedRange<Int>?) -> [String] {
        var out: [String] = []
        if let mediaType { out.append(mediaType.label) }
        if let status { out.append(status.label) }
        out.append(contentsOf: genres.sorted())
        if let language { out.append(language.label) }
        if let years, years != fullYearRange {
            out.append(years.lowerBound == years.upperBound
                ? String(years.lowerBound)
                : "\(years.lowerBound)–\(years.upperBound)")
        }
        return out
    }
}

/// Alles, was die Ergebnisliste bestimmt.
struct CatalogQuery: Hashable {
    var text: String = ""
    var quick: CatalogQuickFilter = .all
    var filters: CatalogFilters = .none
    var sort: CatalogSort = .popular

    var isPristine: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && quick == .all
            && filters.isEmpty
    }
}

// MARK: - Facetten

/// Ein Filterwert samt Anzahl.
struct CatalogFacet: Hashable, Identifiable {
    var label: String
    var count: Int
    var id: String { label }
}

/// Was der geladene Katalog überhaupt hergibt.
///
/// Der Filter bietet nur an, was vorkommt: kein Statusfilter ohne belegte
/// Status, keine Sprachauswahl ohne belegte Sprachen, keine Jahresspanne aus
/// einer ausgedachten Demo-Range. Ein Filter, der garantiert null Treffer
/// liefert, ist schlechter als kein Filter.
struct CatalogFacets: Hashable {
    var genres: [CatalogFacet] = []
    var years: ClosedRange<Int>?
    var statuses: [CatalogStatus] = []
    var languages: [CatalogLanguage] = []
    var mediaTypes: [CatalogMediaType] = []

    static func of(_ entries: [CatalogEntry]) -> CatalogFacets {
        var genreCounts: [String: Int] = [:]
        var statuses: Set<CatalogStatus> = []
        var languages: Set<CatalogLanguage> = []
        var types: Set<CatalogMediaType> = []
        var low: Int?
        var high: Int?

        for entry in entries {
            for genre in entry.genres {
                genreCounts[genre, default: 0] += 1
            }
            if entry.status.isKnown { statuses.insert(entry.status) }
            languages.formUnion(entry.languages)
            types.formUnion(entry.mediaTypes)
            if let year = entry.year {
                low = min(low ?? year, year)
                high = max(high ?? year, year)
            }
        }

        var facets = CatalogFacets()
        facets.genres = genreCounts
            .map { CatalogFacet(label: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.label < rhs.label : lhs.count > rhs.count
            }
        if let low, let high { facets.years = low ... high }
        facets.statuses = CatalogStatus.allCases.filter { statuses.contains($0) }
        facets.languages = languages.sorted { $0.order < $1.order }
        facets.mediaTypes = CatalogMediaType.allCases.filter { types.contains($0) }
        return facets
    }

    /// Die Genres der Schnellfilterleiste: die häufigsten, aber nur solche,
    /// die für eine eigene Pille genug Titel haben.
    func quickGenres(limit: Int = 6, minimum: Int = 8) -> [String] {
        genres.filter { $0.count >= minimum }.prefix(limit).map(\.label)
    }
}
