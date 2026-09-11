import Foundation
import Observation

/// Der Zustand der Merkliste, getrennt von ihrer Darstellung.
///
/// Die Ansicht liest `results`, `stats` und `genres` und rechnet selbst
/// nichts aus. Das ist nicht nur Ordnung: `body` läuft bei jedem Tastendruck
/// im Suchfeld und bei jeder Bildschirmdrehung, und eine Filterung, die
/// dort steht, läuft dann mit. Hier läuft sie, wenn sich etwas geändert hat.
///
/// Die eigentlichen Regeln — was „angefangen" heißt, wie sortiert wird —
/// stehen nicht hier, sondern in `WatchlistModel.swift` im gemeinsamen Kern,
/// wo `swift test` sie erreicht. Diese Klasse hält den Zustand und ruft sie
/// auf.
@Observable
@MainActor
final class WatchlistViewModel {
    /// Was im Suchfeld steht. Ändert sich mit jedem Zeichen.
    var query: String = ""
    /// Wonach tatsächlich gefiltert wird. Läuft der Eingabe kurz hinterher,
    /// siehe `settleQuery`.
    private(set) var appliedQuery: String = ""

    var quick: WatchlistQuickFilter = .all {
        didSet { guard quick != oldValue else { return }; refilter() }
    }

    var filters: WatchlistFilters = .none {
        didSet {
            guard filters != oldValue else { return }
            defaults.set(filters.sort.rawValue, forKey: Keys.sort)
            refilter()
        }
    }

    /// Kacheln oder Liste. Die Wahl überlebt den Neustart — sie ist eine
    /// Vorliebe, keine Momentaufnahme.
    var mode: WatchlistViewMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Keys.mode)
        }
    }

    /// Die vollständige Merkliste.
    private(set) var items: [WatchlistItem] = []
    /// Was nach Suche, Schnellfilter und Filtern übrig bleibt, sortiert.
    private(set) var results: [WatchlistItem] = []
    /// Zahlen über den ganzen Bestand, nicht über die Treffer.
    private(set) var stats = WatchlistStats()
    /// Die Genres, die in der Merkliste vorkommen — für das Filter-Sheet.
    private(set) var genres: [String] = []

    private let defaults: UserDefaults

    private enum Keys {
        static let mode = "nori.watchlist.mode"
        static let sort = "nori.watchlist.sort"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Keys.mode).flatMap(WatchlistViewMode.init(rawValue:)) ?? .grid
        if let stored = defaults.string(forKey: Keys.sort).flatMap(WatchlistSort.init(rawValue:)) {
            filters.sort = stored
        }
    }

    /// Ob überhaupt etwas gemerkt ist. Entscheidet, welcher der beiden
    /// leeren Zustände gezeigt wird.
    var isEmpty: Bool { items.isEmpty }

    /// Ob gerade etwas ausgeblendet wird — Suche oder Filter.
    var isNarrowed: Bool {
        !appliedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || quick != .all
            || filters.isActive
    }

    /// Die Merkliste neu aus dem Store aufbauen.
    ///
    /// Wird über `.task(id:)` an einem Schlüssel aufgehängt, der sich genau
    /// dann ändert, wenn sich am Bestand etwas getan hat — nicht bei jedem
    /// Neuzeichnen.
    func rebuild(library: LibraryStore, catalog: [CatalogItem]) {
        items = library.watchlistItems(catalog: catalog)
        stats = watchlistStats(items)
        genres = watchlistGenres(items)
        refilter()
    }

    /// Die Eingabe übernehmen.
    ///
    /// Zwischen Tastendruck und Filterung liegt eine kurze Pause. Sie kostet
    /// nichts Sichtbares und verhindert, dass bei einer langen Merkliste
    /// jedes Zeichen einen vollständigen Durchlauf auslöst. Netzabrufe hängen
    /// ausdrücklich **nicht** an der Suche: gesucht wird in dem, was schon da
    /// ist, ein Buchstabe löst also auch ohne Pause keine Anfrage aus.
    func settleQuery() async {
        let pending = query
        if !pending.isEmpty {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
        }
        guard appliedQuery != pending else { return }
        appliedQuery = pending
        refilter()
    }

    func refilter() {
        results = watchlistResults(items, query: appliedQuery, quick: quick, filters: filters)
    }

    /// Wie viele Titel eine noch nicht angewendete Filterauswahl übrig ließe
    /// — die Vorschau auf dem Knopf im Sheet.
    func preview(_ candidate: WatchlistFilters) -> Int {
        watchlistResults(items, query: appliedQuery, quick: quick, filters: candidate).count
    }

    /// Suche und Filter zurücknehmen, wenn sie alles weggefiltert haben.
    /// Rührt die Merkliste selbst nicht an.
    func clearNarrowing() {
        query = ""
        appliedQuery = ""
        quick = .all
        var next = filters
        next.reset()
        // `sort` bleibt: sie versteckt nichts und ist eine Vorliebe.
        next.sort = filters.sort
        filters = next
        refilter()
    }

    /// Ein Titel ist entfernt oder zurückgelegt worden — den Bestand ohne
    /// vollständigen Neuaufbau nachziehen.
    func remove(_ id: String) {
        items.removeAll { $0.id == id }
        stats = watchlistStats(items)
        genres = watchlistGenres(items)
        refilter()
    }
}
