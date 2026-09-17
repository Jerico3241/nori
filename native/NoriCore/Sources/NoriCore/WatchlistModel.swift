import Foundation

// Die Merkliste als Rechnung, getrennt von ihrer Darstellung.
//
// Alles, was die Merkliste an Entscheidungen trifft — welche Titel bleiben
// nach Suche und Filtern übrig, in welcher Reihenfolge stehen sie — steht
// hier und nirgends sonst. Die SwiftUI-Ansicht liest das Ergebnis.
//
// Ob ein Titel ungesehen, angefangen oder gesehen ist, steht in
// `WatchMarks.swift`: dort wird der Sehstand auch gesetzt, und beides gehört
// zusammen. Die Mac-App baut diese Datei hier nicht — sie hat eine eigene,
// schlankere Merkliste —, den Sehstand braucht sie trotzdem.
//
// Der Grund ist nicht Ordnungsliebe: der Status stand vorher an keiner
// Stelle, und eine Ansicht, die ihn selbst herleitet, leitet ihn an der
// nächsten Stelle wieder ein bisschen anders her. Die Zusammenfassung („3
// angefangen") und die Kacheln darunter kämen dann zu verschiedenen
// Antworten, ohne dass eine davon falsch aussähe.
//
// Hier statt im iOS-Target, weil `swift test` nur diesen Kern erreicht.

// MARK: - Eintrag

/// Ein Titel der Merkliste, so wie ihn die Oberfläche braucht.
///
/// Eine reine Zusammenführung: Merkliste (was ist gespeichert), Katalog (wie
/// heißt es, welche Genres), Fortschritt (wie weit). Keine dieser Angaben
/// entsteht hier neu, und nichts davon wird zusätzlich abgelegt — die
/// Merkliste bleibt `LibraryStore.favorites`.
struct WatchlistItem: Identifiable, Hashable {
    var slug: String
    var provider: CatalogProvider
    var title: String
    /// Weitere Schreibweisen aus dem Katalog. Nur für die Suche.
    var alternateTitles: [String]
    var genres: [String]
    /// Wann gemerkt, in Millisekunden seit 1970.
    var addedAt: Double
    var watch: WatchSummary

    /// Wie bei `CatalogItem`: zwei Quellen können denselben Slug führen.
    var id: String { "\(provider.rawValue)|\(slug)" }

    init(
        slug: String,
        provider: CatalogProvider,
        title: String,
        alternateTitles: [String] = [],
        genres: [String] = [],
        addedAt: Double,
        watch: WatchSummary = .none
    ) {
        self.slug = slug
        self.provider = provider
        self.title = title
        self.alternateTitles = alternateTitles
        self.genres = genres
        self.addedAt = addedAt
        self.watch = watch
    }

    /// Die Zeile unter dem Titel: Genres und Quelle, soweit bekannt.
    ///
    /// Ausdrücklich **ohne** „Anime"/„Serie" als Abzeichen auf dem Poster —
    /// der Medientyp steht hier in derselben ruhigen Zeile wie das Genre,
    /// wenn er überhaupt gebraucht wird.
    var metaText: String {
        var parts = Array(genres.prefix(2))
        if parts.isEmpty { parts.append(provider.kind) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Filter, Suche, Sortierung

/// Die Schnellfilter über der Liste. Ausschließlich der persönliche Stand —
/// „Anime" und „Serien" stehen hier bewusst nicht, die gehören in den
/// erweiterten Filter.
enum WatchlistQuickFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case unseen
    case started
    case seen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Alle"
        case .unseen: return WatchState.unseen.label
        case .started: return WatchState.started.label
        case .seen: return WatchState.seen.label
        }
    }

    /// Die Überschrift über den Ergebnissen.
    var headline: String {
        switch self {
        case .all: return "Alle Titel"
        default: return label
        }
    }

    var state: WatchState? {
        switch self {
        case .all: return nil
        case .unseen: return .unseen
        case .started: return .started
        case .seen: return .seen
        }
    }
}

/// Der Medientyp — nur im erweiterten Filter erreichbar.
enum WatchlistKind: String, CaseIterable, Identifiable, Hashable {
    case all
    case anime
    case serien

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Alle"
        case .anime: return "Anime"
        case .serien: return "Serien"
        }
    }

    var provider: CatalogProvider? {
        switch self {
        case .all: return nil
        case .anime: return .aniworld
        case .serien: return .serienstream
        }
    }
}

enum WatchlistSort: String, CaseIterable, Identifiable, Hashable {
    case added
    case title
    case progress
    case lastWatched

    var id: String { rawValue }

    var label: String {
        switch self {
        case .added: return "Zuletzt hinzugefügt"
        case .title: return "A–Z"
        case .progress: return "Fortschritt"
        case .lastWatched: return "Zuletzt angesehen"
        }
    }

    /// Beschriftung des Knopfes in der Werkzeugleiste, mit Richtungspfeil wie
    /// in der Vorlage.
    var buttonLabel: String {
        switch self {
        case .title: return label
        default: return label + " ↓"
        }
    }
}

enum WatchlistViewMode: String, CaseIterable, Identifiable, Hashable {
    case grid
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grid: return "Kacheln"
        case .list: return "Liste"
        }
    }

    var symbol: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

/// Was im Filter-Sheet steht. Getrennt von den Schnellfiltern, weil beides
/// gleichzeitig gilt und der Nutzer beides einzeln zurücknehmen können soll.
struct WatchlistFilters: Hashable {
    var kind: WatchlistKind
    var state: WatchState?
    var genre: String?
    var sort: WatchlistSort

    init(
        kind: WatchlistKind = .all,
        state: WatchState? = nil,
        genre: String? = nil,
        sort: WatchlistSort = .added
    ) {
        self.kind = kind
        self.state = state
        self.genre = genre
        self.sort = sort
    }

    static let none = WatchlistFilters()

    /// Ob der Filterknopf markiert wird. Die Sortierung zählt nicht dazu —
    /// sie versteckt keine Titel, und ein dauerhaft markierter Knopf ließe
    /// niemanden mehr erkennen, dass etwas ausgefiltert ist.
    var isActive: Bool { kind != .all || state != nil || genre != nil }

    /// Zurücksetzen betrifft nur die Filter. Suche, Schnellfilter, Merkliste
    /// und Fortschritt bleiben, wo sie sind.
    mutating func reset() {
        kind = .all
        state = nil
        genre = nil
        sort = .added
    }
}

/// Wie viele Titel gespeichert, angefangen und gesehen sind.
///
/// Bewusst über den **ganzen** Bestand gerechnet und nicht über die gerade
/// sichtbaren Treffer: „8 gespeichert" soll die Merkliste beschreiben, nicht
/// den Filter. Was der Filter übrig lässt, steht darunter als
/// Ergebnisanzahl.
struct WatchlistStats: Hashable {
    var saved: Int
    var unseen: Int
    var started: Int
    var seen: Int

    init(saved: Int = 0, unseen: Int = 0, started: Int = 0, seen: Int = 0) {
        self.saved = saved
        self.unseen = unseen
        self.started = started
        self.seen = seen
    }
}

func watchlistStats(_ items: [WatchlistItem]) -> WatchlistStats {
    WatchlistStats(
        saved: items.count,
        unseen: items.filter { $0.watch.state == .unseen }.count,
        started: items.filter { $0.watch.state == .started }.count,
        seen: items.filter { $0.watch.state == .seen }.count
    )
}

/// Suche, Filter und Sortierung in einem Durchgang.
///
/// Die Reihenfolge ist festgelegt: erst die Suche, dann Schnellfilter und
/// erweiterte Filter (die sich addieren, nicht ersetzen), zuletzt die
/// Sortierung.
func watchlistResults(
    _ items: [WatchlistItem],
    query: String,
    quick: WatchlistQuickFilter,
    filters: WatchlistFilters
) -> [WatchlistItem] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    let matched = items.filter { item in
        if !needle.isEmpty, !matches(item, needle: needle) { return false }
        if let provider = filters.kind.provider, item.provider != provider { return false }
        // Beide Statusquellen gelten gleichzeitig. Ein Widerspruch —
        // Schnellfilter „Gesehen" und im Sheet „Ungesehen" — ergibt
        // korrekterweise nichts, und die Ansicht sagt dann, dass die Filter
        // nichts übrig lassen.
        if let state = quick.state, item.watch.state != state { return false }
        if let state = filters.state, item.watch.state != state { return false }
        if let genre = filters.genre,
           !item.genres.contains(where: { $0.caseInsensitiveCompare(genre) == .orderedSame }) {
            return false
        }
        return true
    }

    return sortWatchlist(matched, by: filters.sort)
}

private func matches(_ item: WatchlistItem, needle: String) -> Bool {
    if item.title.lowercased().contains(needle) { return true }
    if item.slug.lowercased().contains(needle) { return true }
    if item.alternateTitles.contains(where: { $0.lowercased().contains(needle) }) { return true }
    // Genres zählen mit, sofern der Katalog welche mitgebracht hat. Sie sind
    // schon da; ein eigener Abruf entsteht dafür nicht.
    return item.genres.contains { $0.lowercased().contains(needle) }
}

func sortWatchlist(_ items: [WatchlistItem], by sort: WatchlistSort) -> [WatchlistItem] {
    switch sort {
    case .added:
        // Bei gleichem Zeitpunkt alphabetisch, damit die Reihenfolge nicht
        // zwischen zwei Aufbauten springt — abgeleitete Zeitpunkte aus einem
        // alten Stand können gleich ausfallen.
        return items.sorted { byTitle($0, $1, when: $0.addedAt == $1.addedAt) ?? ($0.addedAt > $1.addedAt) }
    case .title:
        return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    case .progress:
        return items.sorted {
            byTitle($0, $1, when: $0.watch.sortValue == $1.watch.sortValue)
                ?? ($0.watch.sortValue > $1.watch.sortValue)
        }
    case .lastWatched:
        // Nie Angesehenes ans Ende, dort nach Merkzeitpunkt.
        return items.sorted {
            let a = $0.watch.lastWatched
            let b = $1.watch.lastWatched
            if let a, let b { return a == b ? $0.addedAt > $1.addedAt : a > b }
            if a != nil { return true }
            if b != nil { return false }
            return $0.addedAt > $1.addedAt
        }
    }
}

/// Gleichstand alphabetisch auflösen, sonst `nil`.
private func byTitle(_ a: WatchlistItem, _ b: WatchlistItem, when tie: Bool) -> Bool? {
    guard tie else { return nil }
    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
}

/// Die Genres, die in der Merkliste tatsächlich vorkommen — für das
/// Filter-Sheet.
///
/// Nur aus den vorhandenen Titeln: eine Liste aller denkbaren Genres wäre
/// überwiegend leer und böte Filter an, die garantiert nichts finden.
func watchlistGenres(_ items: [WatchlistItem], limit: Int = 12) -> [String] {
    var counts: [String: Int] = [:]
    var display: [String: String] = [:]
    for item in items {
        for genre in item.genres {
            let key = genre.lowercased()
            counts[key, default: 0] += 1
            if display[key] == nil { display[key] = genre }
        }
    }
    return counts
        .sorted {
            $0.value == $1.value
                ? (display[$0.key] ?? "").localizedCaseInsensitiveCompare(display[$1.key] ?? "") == .orderedAscending
                : $0.value > $1.value
        }
        .prefix(limit)
        .compactMap { display[$0.key] }
}

// MARK: - Aus dem Store

extension LibraryStore {
    /// Die Merkliste als fertige Einträge.
    ///
    /// Eine Stelle, an der Merkliste, Katalog und Fortschritt
    /// zusammenkommen. Der Katalog ist dabei nur Beiwerk: er liefert Genres
    /// und Alternativtitel. Fehlt ein Titel darin — weil der Katalog noch
    /// lädt, weil die Quelle gerade nicht antwortet, weil der Eintrag dort
    /// verschwunden ist —, bleibt der Titel trotzdem in der Merkliste
    /// stehen, mit dem gemerkten Namen. Was gespeichert ist, entscheidet
    /// allein `favorites`.
    ///
    /// Der Fortschritt wird **einmal** nach Quelle und Slug gruppiert, statt
    /// je Eintrag über alle Werte zu laufen: bei einem gefüllten Verlauf und
    /// hundert gemerkten Titeln wäre das sonst ein Produkt aus beidem, bei
    /// jedem Neuzeichnen.
    func watchlistItems(catalog: [CatalogItem] = []) -> [WatchlistItem] {
        var byKey: [String: CatalogItem] = [:]
        var bySlug: [String: CatalogItem] = [:]
        for item in catalog {
            if let provider = item.provider { byKey["\(provider.rawValue)|\(item.slug)"] = item }
            if bySlug[item.slug] == nil { bySlug[item.slug] = item }
        }

        var episodes: [String: [WatchProgress]] = [:]
        for entry in progress.values {
            let provider = entry.provider ?? providerFromPath(entry.episodePath)
            episodes["\(provider.rawValue)|\(entry.slug)", default: []].append(entry)
        }

        return favorites.map { slug in
            let provider = source(of: slug)
            let key = "\(provider.rawValue)|\(slug)"
            // Der Eintrag der richtigen Quelle zuerst; sonst der gleichnamige
            // der anderen. Genres und Alternativtitel unterscheiden sich
            // zwischen den Seiten kaum, und ein Titel ohne jede Nebenangabe
            // wäre über die Suche schlechter zu finden.
            let entry = byKey[key] ?? bySlug[slug]
            return WatchlistItem(
                slug: slug,
                provider: provider,
                title: titles[slug] ?? entry?.title ?? slug,
                alternateTitles: entry?.alts ?? [],
                genres: entry?.genres ?? [],
                addedAt: favoriteAddedAt[slug] ?? 0,
                watch: watchSummary(for: episodes[key] ?? [])
            )
        }
    }
}
