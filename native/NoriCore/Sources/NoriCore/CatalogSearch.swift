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

    // MARK: - Stufen und Tippfehler

    /// Ab so vielen Zeichen wird überhaupt gesucht. Darunter trifft alles.
    static let minLength = 2

    /// Unter so vielen strengen Treffern wird zusätzlich auf Tippfehler geprüft.
    ///
    /// Nicht immer: Stufe 5 kostet ein Vielfaches der übrigen und verdünnte
    /// sonst gute Treffer mit schlechten. Wer „one piece" tippt, will nicht
    /// „One Pace" dazwischen.
    static let fuzzyThreshold = 12

    /// Eine Eingabe in ihre vergleichbare Form.
    static func needle(_ raw: String) -> String {
        TMDBMatcher.normalize(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Ein durchsuchbarer Eintrag — **schon normalisiert**.
    ///
    /// Beide Felder entstehen einmal je Katalogstand (`CatalogEntry.titleKey`
    /// und `CatalogEntry.searchKey`, `CatalogItemIndex`). Bei jedem Anschlag
    /// zehntausend Titel neu zu entkernen wäre eine halbe Sekunde Arbeit — das
    /// war der Grund für den vorbereiteten Schlüssel, und er gilt für die
    /// Stufen genauso.
    struct Prepared {
        /// Der Titel, normalisiert.
        var title: String
        /// Titel, Alternativtitel, Genres und Jahr in einer normalisierten Zeile.
        var haystack: String

        init(title: String, haystack: String) {
            self.title = title
            self.haystack = haystack
        }

        /// Aus Rohwerten — für kurze Listen, die keinen Index führen.
        init(rawTitle: String, alternates: [String] = []) {
            let plain = TMDBMatcher.normalize(rawTitle)
            self.title = plain
            self.haystack = ([plain] + alternates.map(TMDBMatcher.normalize))
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    /// Stufe 0–4, oder −1. `needle` ist bereits normalisiert.
    ///
    ///     0  Titel gleich
    ///     1  Titel beginnt mit dem Begriff
    ///     2  Titel enthält den Begriff
    ///     3  ein Alternativtitel oder Genre enthält ihn
    ///     4  jedes Wort des Begriffs steht irgendwo im Eintrag
    ///
    /// Dieselben Stufen wie `searchScore` in `shared/nori-core/src/search.ts`.
    /// Sie standen vorher nur dort, obwohl an ihnen nichts TV-spezifisch ist:
    /// ein Tippfehler auf einer Fernbedienung ist derselbe Tippfehler wie auf
    /// einem iPhone — nur seltener.
    static func score(_ entry: Prepared, needle: String) -> Int {
        if entry.title == needle { return 0 }
        if entry.title.hasPrefix(needle) { return 1 }
        if entry.title.contains(needle) { return 2 }
        if entry.haystack.contains(needle) { return 3 }
        let parts = needle.split(separator: " ")
        if parts.count > 1, parts.allSatisfy({ entry.haystack.contains($0) }) { return 4 }
        return -1
    }

    /// Stufe 5, oder −1. Teurer — nur, wenn die strengen Stufen wenig finden.
    ///
    /// Ab vier Buchstaben ist ein Tippfehler je Wort erlaubt, ab sieben zwei.
    /// Damit trifft „Damonenjager" den „Dämonenjäger": die Normalisierung hat
    /// die Umlaute schon abgetragen, die vertippten Buchstaben nicht.
    static func fuzzyScore(_ entry: Prepared, needle: String) -> Int {
        let parts = needle.split(separator: " ").map(String.init).filter { $0.count >= 3 }
        guard !parts.isEmpty else { return -1 }
        let pool = entry.haystack.split(separator: " ").map(String.init)
        guard !pool.isEmpty else { return -1 }
        let hit = parts.allSatisfy { part in
            let limit = tolerance(part)
            return pool.contains { word in
                if word.hasPrefix(part) { return true }
                guard limit > 0 else { return false }
                return withinDistance(part, String(word.prefix(part.count + limit)), limit: limit)
            }
        }
        return hit ? 5 : -1
    }

    /// Die Treffer mit ihrer Stufe, in der Reihenfolge der Eingabe je Stufe.
    ///
    /// Erst die strengen Stufen, und nur wenn die wenig finden, zusätzlich die
    /// teure. Eine zu kurze Eingabe trifft alles — Stufe 0 für jeden Eintrag,
    /// damit der Aufrufer keinen Sonderfall braucht.
    static func ranked<T>(
        _ items: [T],
        needle: String,
        prepared: (T) -> Prepared
    ) -> [(item: T, score: Int)] {
        guard needle.count >= minLength else { return items.map { ($0, 0) } }

        var scored: [(item: T, score: Int, index: Int)] = []
        var matched = Set<Int>()
        for (index, item) in items.enumerated() {
            let value = score(prepared(item), needle: needle)
            if value >= 0 {
                scored.append((item, value, index))
                matched.insert(index)
            }
        }
        if scored.count < fuzzyThreshold {
            for (index, item) in items.enumerated() where !matched.contains(index) {
                let value = fuzzyScore(prepared(item), needle: needle)
                if value >= 0 { scored.append((item, value, index)) }
            }
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score < $1.score : $0.index < $1.index }
            .map { ($0.item, $0.score) }
    }

    /// Wie `ranked`, aber ohne die Stufen — der übliche Fall.
    static func rank<T>(_ items: [T], query: String, prepared: (T) -> Prepared) -> [T] {
        ranked(items, needle: needle(query), prepared: prepared).map(\.item)
    }

    // MARK: - Intern

    /// Wie viele Tippfehler ein Wort verträgt.
    ///
    /// Ziffern vertragen **keinen**: „1998" ist kein Vertipper von „1999",
    /// sondern ein anderes Jahr, eine andere Folge, eine andere Staffel. Ohne
    /// diese Regel verdünnte eine Suche nach „Titel 1999" ihren einen
    /// richtigen Treffer mit einem Dutzend Nachbarzahlen — gemessen an einem
    /// Katalog aus durchnummerierten Titeln, und genauso wäre es bei
    /// „Staffel 2" oder „86".
    private static func tolerance(_ word: String) -> Int {
        if word.contains(where: { $0.isNumber }) { return 0 }
        if word.count >= 7 { return 2 }
        if word.count >= 4 { return 1 }
        return 0
    }

    /// Levenshtein mit Abbruch, sobald die Grenze sicher überschritten ist.
    private static func withinDistance(_ a: String, _ b: String, limit: Int) -> Bool {
        let left = Array(a)
        let right = Array(b)
        if abs(left.count - right.count) > limit { return false }
        if left.isEmpty { return right.count <= limit }
        if right.isEmpty { return left.count <= limit }

        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            current[0] = i
            var rowMin = i
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                let value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                current[j] = value
                if value < rowMin { rowMin = value }
            }
            if rowMin > limit { return false }
            swap(&previous, &current)
        }
        return previous[right.count] <= limit
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
    private let prepared: [CatalogSearch.Prepared]

    init(_ items: [CatalogItem]) {
        self.items = items
        prepared = items.map { item in
            CatalogSearch.Prepared(
                title: TMDBMatcher.normalize(item.title),
                haystack: CatalogSearch.key(
                    title: item.title,
                    originalTitle: nil,
                    // Der Slug zählt mit: in ihm steht bei manchen Titeln die
                    // lateinische Umschrift, die weder Titel noch
                    // Alternativtitel tragen.
                    alternates: item.alts + [item.slug.replacingOccurrences(of: "-", with: " ")],
                    genres: item.genres,
                    year: nil
                )
            )
        }
    }

    /// Die Treffer, nach Stufe sortiert — beste zuerst. Eine leere oder zu
    /// kurze Eingabe liefert alles in der Reihenfolge des Index.
    ///
    /// Seit die Stufen im Kern stehen, sucht der Mac genauso wie der Fernseher
    /// und das iPhone: „pokemon" trifft „Pokémon", „shingeki no kyojin" trifft
    /// den Eintrag, der bei der Quelle „Attack on Titan" heißt, und
    /// „Damonenjager" den „Dämonenjäger".
    func search(_ raw: String) -> [CatalogItem] {
        let needle = CatalogSearch.needle(raw)
        guard needle.count >= CatalogSearch.minLength else { return items }
        return CatalogSearch
            .ranked(Array(items.indices), needle: needle, prepared: { prepared[$0] })
            .map { items[$0.item] }
    }
}
