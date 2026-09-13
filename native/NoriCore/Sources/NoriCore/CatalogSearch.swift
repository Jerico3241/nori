import Foundation

// Die Katalogsuche: Normalisierung, Suchbegriffe und ein vorbereiteter Index.
//
// Eine eigene Datei, weil beide Apple-Targets sie bauen: der iPhone-Katalog
// über `CatalogEntry` (`CatalogSearch.matches` in `CatalogRanking.swift`), der
// Mac-Katalog über `CatalogItem` (`CatalogItemIndex`). So gilt auf beiden
// Geräten dieselbe Regel für dieselbe Eingabe.

/// Die Katalogsuche.
///
/// Gesucht wird über einen **vorbereiteten** Schlüssel (`CatalogEntry.searchKey`),
/// nicht über die Rohfelder: bei jeder Taste zehntausend Titel, Alternativtitel
/// und Genres neu zu entkernen wäre pro Anschlag eine halbe Sekunde Arbeit.
///
/// Die Normalisierung ist dieselbe wie bei der TMDB-Zuordnung
/// (`TMDBMatcher.normalize`) — kleingeschrieben, ohne Akzente, ohne
/// Satzzeichen. Damit findet „pokemon" auch „Pokémon", „re zero" auch
/// „Re:ZERO" und „sci fi" auch „Sci-Fi".
enum CatalogSearch {
    /// Der Suchschlüssel eines Eintrags: Titel, Originaltitel, Alternativtitel,
    /// Genres und Jahr in einer normalisierten Zeichenkette.
    static func key(
        title: String,
        originalTitle: String?,
        alternates: [String],
        genres: [String],
        year: Int?
    ) -> String {
        var parts: [String] = []
        func add(_ raw: String) {
            let plain = TMDBMatcher.normalize(raw)
            guard !plain.isEmpty, !parts.contains(plain) else { return }
            parts.append(plain)
            // Zusätzlich die um Staffel- und Jahresangaben bereinigte Fassung:
            // wer „attack on titan" sucht, meint auch „Attack on Titan Final
            // Season".
            let stripped = TMDBMatcher.stripVariants(raw)
            if !stripped.isEmpty, stripped != plain, !parts.contains(stripped) {
                parts.append(stripped)
            }
        }
        add(title)
        if let originalTitle { add(originalTitle) }
        for alternate in alternates { add(alternate) }
        for genre in genres { add(genre) }
        if let year { parts.append(String(year)) }
        return parts.joined(separator: " ")
    }

    /// Die Suchbegriffe einer Eingabe.
    ///
    /// Mehrere Wörter sind eine **Und**-Verknüpfung: „fantasy 2024" meint
    /// beides, nicht eines von beiden.
    static func terms(_ raw: String) -> [String] {
        let plain = TMDBMatcher.normalize(raw)
        guard !plain.isEmpty else { return [] }
        return plain.split(separator: " ").map(String.init)
    }
}

/// Die Katalogsuche für Ansichten, die mit `CatalogItem` arbeiten.
///
/// Der Mac-Katalog braucht keinen vollständigen `CatalogEntry`-Aufbau mit
/// TMDB-Zusammenführung, er zeigt die Titel der Quellen. Gesucht hat er bisher
/// aber in einer berechneten Eigenschaft: bei jedem Neuzeichnen — und damit bei
/// jedem Anschlag mehrfach — `lowercased()` über Titel, Alternativtitel und Slug
/// von zehntausend Einträgen, ohne Akzente zu entfernen. „pokemon" fand
/// „Pokémon" nicht, auf dem iPhone schon.
///
/// Hier dieselbe Regel wie `CatalogSearch`: vorbereitete, normalisierte
/// Schlüssel, und mehrere Wörter sind eine Und-Verknüpfung. Aufbauen kostet
/// einmal je Katalogstand, suchen nur noch Vergleiche.
struct CatalogItemIndex: Sendable {
    let items: [CatalogItem]
    private let keys: [String]

    init(_ items: [CatalogItem]) {
        self.items = items
        keys = items.map { item in
            CatalogSearch.key(
                title: item.title,
                originalTitle: nil,
                // Der Slug zählt mit: in ihm steht bei manchen Titeln die
                // lateinische Umschrift, die weder Titel noch Alternativtitel
                // tragen.
                alternates: item.alts + [item.slug.replacingOccurrences(of: "-", with: " ")],
                genres: item.genres,
                year: nil
            )
        }
    }

    /// Alle Einträge, die jedes Wort der Eingabe enthalten — in der
    /// Reihenfolge des Index. Eine leere Eingabe liefert alles.
    func search(_ raw: String) -> [CatalogItem] {
        let terms = CatalogSearch.terms(raw)
        guard !terms.isEmpty else { return items }
        var out: [CatalogItem] = []
        for (position, key) in keys.enumerated() where terms.allSatisfy({ key.contains($0) }) {
            out.append(items[position])
        }
        return out
    }
}
