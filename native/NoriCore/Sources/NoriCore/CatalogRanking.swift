import Foundation

// Die Rechnungen des Katalogs: was „neu" heißt, was „beliebt" heißt, wie
// bewertet wird, wie gesucht, gefiltert und sortiert wird.
//
// Alles rein: gleiche Eingabe, gleiche Ausgabe, keine Uhr und kein Netz im
// Inneren. `now` wird deshalb übergeben und nicht gelesen.

// MARK: - Bewertung und Reihenfolge

enum CatalogRanking {
    // MARK: „Neu"

    /// Wie lange eine neue Folge bei Nori als „neu" zählt.
    ///
    /// Kürzer als TMDBs Fenster, weil dieses Signal genauer ist: Der Kalender
    /// der Quelle sagt nicht „irgendwann in den letzten Wochen", sondern
    /// nennt den Tag, an dem die Folge bei Nori abrufbar wurde.
    static let freshEpisodeWindow: TimeInterval = 30 * 86_400

    /// Ist der Titel neu?
    ///
    /// Zwei Wege, beide belegt:
    ///
    /// - **Neu bei Nori.** Der Kalender der Quelle führt in den letzten
    ///   `freshEpisodeWindow` eine Folge zu diesem Titel. Das ist der
    ///   direkteste Beweis, dass es hier und heute etwas Neues gibt.
    /// - **Neu laut TMDB.** Ausstrahlung im Aktualitätsfenster der
    ///   Startseite — dieselbe Regel wie dort (`HomeRanking.isNew`), damit
    ///   derselbe Titel nicht auf einem Bildschirm neu ist und auf dem
    ///   anderen nicht.
    ///
    /// Was ausdrücklich **nicht** zählt: dass der Titel zufällig ausgewählt
    /// wurde oder dass er noch kein Cover hat.
    static func isNew(_ entry: CatalogEntry, now: Date) -> Bool {
        if entry.hasFreshEpisode { return true }
        return HomeRanking.isNew(entry.signals, now: now)
    }

    // MARK: „Beliebt"

    /// Der Punktwert für „Beliebt".
    ///
    /// Drei Signale, absichtlich keins davon `vote_average`:
    ///
    /// - **Trend (0–140).** TMDBs Wochenliste. Das einzige Signal, das sagt,
    ///   was *gerade jetzt* gesucht wird.
    /// - **Beliebtheit (0–70), logarithmisch.** TMDBs `popularity` ist nach
    ///   oben offen und extrem schief verteilt; linear gewichtet schöbe ein
    ///   einziger Ausreißer alles andere aus der Liste.
    /// - **Stimmenzahl (0–30), logarithmisch.** Wie viele Menschen den Titel
    ///   überhaupt kennen. Nicht wie gut sie ihn finden — das ist die andere
    ///   Sortierung.
    static func popularityScore(_ entry: CatalogEntry) -> Double {
        var score: Double = 0
        if let rank = entry.signals.trendingRank, rank > 0 {
            score += max(0, 140 - Double(rank - 1) * 3.5)
        }
        if let popularity = entry.signals.popularity, popularity > 0 {
            score += min(70, 9 * log2(1 + popularity))
        }
        if let votes = entry.signals.voteCount, votes > 0 {
            score += min(30, 3 * log2(Double(1 + votes)))
        }
        return score
    }

    /// Hat der Titel überhaupt ein Beliebtheitssignal?
    ///
    /// Der Schnellfilter „Beliebt" zeigt nur solche Titel. Ohne diese Hürde
    /// stünden dahinter tausende Einträge mit null Punkten in beliebiger
    /// Reihenfolge — eine Liste, die nichts behauptet und trotzdem so heißt.
    static func hasPopularitySignal(_ entry: CatalogEntry) -> Bool {
        if entry.signals.trendingRank != nil { return true }
        if let popularity = entry.signals.popularity, popularity > 0 { return true }
        return false
    }

    // MARK: „Top bewertet"

    /// Der Mittelwert, gegen den wenig beachtete Titel gezogen werden.
    static let ratingPrior: Double = 6.5
    /// Wie viele Stimmen ein Titel braucht, damit seine eigene Bewertung
    /// gegenüber dem Mittelwert überwiegt.
    static let ratingConfidence: Double = 300
    /// Untergrenze für den Schnellfilter „Top bewertet".
    static let ratingMinimumVotes = 50

    /// Gewichtete Bewertung nach dem Bayes-Mittel.
    ///
    ///     (v / (v + m)) * R  +  (m / (v + m)) * C
    ///
    /// Ohne diese Gewichtung gewinnt jede Sortierung nach Bewertung ein Titel
    /// mit 10,0 aus zwei Stimmen — und zwar immer, denn davon gibt es in
    /// TMDB tausende. Mit ihr landet derselbe Titel bei 6,5 und eine weltweit
    /// gesehene Serie mit 9,0 aus 50 000 Stimmen bei 9,0.
    ///
    /// `nil` heißt „keine Grundlage": keine Bewertung oder keine Stimmen.
    static func weightedRating(_ entry: CatalogEntry) -> Double? {
        guard let average = entry.signals.voteAverage, average > 0 else { return nil }
        guard let votes = entry.signals.voteCount, votes > 0 else { return nil }
        let v = Double(votes)
        return (v / (v + ratingConfidence)) * average
            + (ratingConfidence / (v + ratingConfidence)) * ratingPrior
    }

    /// Reicht die Stimmenzahl für den Schnellfilter „Top bewertet"?
    static func hasRatingBase(_ entry: CatalogEntry) -> Bool {
        guard let votes = entry.signals.voteCount, votes >= ratingMinimumVotes else { return false }
        guard let average = entry.signals.voteAverage, average > 0 else { return false }
        return true
    }

    // MARK: Alter

    /// Woran sich „neueste" und „älteste" bemessen.
    ///
    /// Die letzte Ausstrahlung vor der ersten vor dem Jahr aus dem Titel:
    /// eine zwanzig Jahre alte Serie mit einer Staffel von letzter Woche ist
    /// in einer Liste „Neueste" weiter oben richtig aufgehoben als eine
    /// Serie, die 2019 angefangen und aufgehört hat.
    static func releaseReference(_ entry: CatalogEntry) -> Date? {
        if let last = entry.signals.lastAirDate { return last }
        if let first = entry.signals.firstAirDate { return first }
        guard let year = entry.year else { return nil }
        return berlinDate(year: year, month: 1, day: 1)
    }

    // MARK: Sortierung

    /// Ein bewerteter Eintrag.
    ///
    /// Ein benannter Typ statt eines Tupels, aus demselben Grund wie bei
    /// `HomeRanking.Scored`: eine durchgehende Kette aus `filter`, `map`,
    /// `sorted` und `prefix` bringt den Typechecker zum Aufgeben.
    struct Scored {
        var entry: CatalogEntry
        var score: Double
        /// Einträge ohne Grundlage stehen hinten, egal wie sortiert wird.
        var ranked: Bool
        /// Der zweite Punktwert, falls der erste gleich ist.
        ///
        /// Gebraucht, weil einer der Werte von TMDB **grob** ist: Die Listen
        /// kürzlich ausgestrahlter Serien führen kein Datum, nur die
        /// Zugehörigkeit, und `CatalogBuilder` setzt deshalb für alle
        /// dieselbe Ersatzzeit. Ohne zweiten Schlüssel landen damit
        /// sämtliche Titel mit laufender Staffel auf demselben Punktwert und
        /// die Liste „Neueste" fällt in ihre alphabetische Rückfallordnung —
        /// im Raster war das gut zu sehen: eine lange Strecke von A bis D,
        /// mit Jahreszahlen, die von 2026 bis 1996 sprangen.
        var secondary: Double = 0
    }

    /// Absteigend nach Punkten, Einträge ohne Grundlage zuletzt, bei
    /// Gleichstand nach dem zweiten Punktwert, dann alphabetisch und zuletzt
    /// nach Kennung.
    ///
    /// Die hinteren Schlüssel sind kein Schönheitsfehler: ohne sie ist die
    /// Reihenfolge gleichwertiger Titel unbestimmt, und das Raster sortierte
    /// sich bei jedem Neuaufbau anders.
    static func ordered(_ scored: [Scored]) -> [CatalogEntry] {
        scored.sorted { lhs, rhs in
            if lhs.ranked != rhs.ranked { return lhs.ranked }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.secondary != rhs.secondary { return lhs.secondary > rhs.secondary }
            let byTitle = lhs.entry.title.localizedCaseInsensitiveCompare(rhs.entry.title)
            if byTitle != .orderedSame { return byTitle == .orderedAscending }
            return lhs.entry.id < rhs.entry.id
        }
        .map(\.entry)
    }

    /// Die Ergebnisliste in der gewählten Reihenfolge.
    static func sort(_ entries: [CatalogEntry], by sort: CatalogSort, now: Date) -> [CatalogEntry] {
        switch sort {
        case .titleAscending:
            return entries.sorted { byTitle($0, $1, ascending: true) }
        case .titleDescending:
            return entries.sorted { byTitle($0, $1, ascending: false) }
        case .popular:
            var scored: [Scored] = []
            for entry in entries {
                let value = popularityScore(entry)
                scored.append(Scored(entry: entry, score: value, ranked: value > 0))
            }
            return ordered(scored)
        case .rating:
            var scored: [Scored] = []
            for entry in entries {
                let value = weightedRating(entry)
                scored.append(Scored(entry: entry, score: value ?? 0, ranked: value != nil))
            }
            return ordered(scored)
        case .newest, .oldest:
            var scored: [Scored] = []
            for entry in entries {
                let reference = releaseReference(entry)
                let seconds = reference?.timeIntervalSince1970 ?? 0
                // Die Erstausstrahlung als zweiter Schlüssel. Sie ist immer
                // ein echtes Datum, während die letzte Ausstrahlung aus einer
                // Liste stammen kann, die nur „in den letzten Wochen" sagt.
                let premiere = entry.signals.firstAirDate?.timeIntervalSince1970 ?? 0
                // „Älteste" kehrt nur das Vorzeichen um; die Behandlung der
                // Einträge ohne Datum bleibt dieselbe — sie stehen hinten,
                // nicht am Anfang.
                let direction: Double = sort == .newest ? 1 : -1
                scored.append(Scored(
                    entry: entry,
                    score: direction * seconds,
                    ranked: reference != nil,
                    secondary: direction * premiere
                ))
            }
            return ordered(scored)
        }
    }

    private static func byTitle(_ lhs: CatalogEntry, _ rhs: CatalogEntry, ascending: Bool) -> Bool {
        let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if comparison == .orderedSame { return lhs.id < rhs.id }
        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    // MARK: Abzeichen

    /// Die Abzeichen eines Posters, höchstens zwei.
    ///
    /// - Parameter showsKind: Ob „ANIME"/„SERIE" dazugehört. Im gemischten
    ///   Raster ja — dort trägt die Angabe etwas bei. Sobald der Betrachter
    ///   auf einen Typ gefiltert hat, stünde auf jeder Kachel dasselbe Wort,
    ///   und dann ist es keine Auskunft mehr, sondern Rauschen.
    static func badges(for entry: CatalogEntry, now: Date, showsKind: Bool) -> [CatalogBadge] {
        var out: [CatalogBadge] = []
        if let rank = entry.signals.trendingRank, rank <= 10 {
            out.append(.top(rank))
        } else if isNew(entry, now: now) {
            out.append(.fresh)
        } else if entry.status == .completed {
            out.append(.complete)
        }
        if showsKind { out.append(.kind(entry.mediaType)) }
        return out
    }
}

// MARK: - Suche

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

    static func matches(_ entry: CatalogEntry, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        for term in terms where !entry.searchKey.contains(term) {
            return false
        }
        return true
    }
}

// MARK: - Die Ergebnisliste

/// Filter und Sortierung an einer Stelle.
///
/// Die Ansicht ruft genau diese Funktion und rechnet selbst nichts mehr.
/// Solange sie in einem `body` stünde, liefe sie bei jedem Neuzeichnen —
/// bei zehntausend Einträgen sichtbar.
enum CatalogEngine {
    static func results(for query: CatalogQuery, in entries: [CatalogEntry], now: Date) -> [CatalogEntry] {
        let terms = CatalogSearch.terms(query.text)
        var kept: [CatalogEntry] = []
        kept.reserveCapacity(entries.count)

        for entry in entries {
            guard CatalogSearch.matches(entry, terms: terms) else { continue }
            guard passesFilters(entry, query.filters) else { continue }
            guard passesQuick(entry, query.quick, now: now) else { continue }
            kept.append(entry)
        }

        return CatalogRanking.sort(kept, by: query.sort, now: now)
    }

    /// Die erweiterten Filter. Alle sind **und**-verknüpft: „Anime + Fantasy +
    /// abgeschlossen + ab 2020" heißt alles davon zugleich.
    static func passesFilters(_ entry: CatalogEntry, _ filters: CatalogFilters) -> Bool {
        if let mediaType = filters.mediaType, !entry.mediaTypes.contains(mediaType) {
            return false
        }
        if let status = filters.status, entry.status != status {
            return false
        }
        if !filters.genres.isEmpty {
            // Mehrere Genres sind eine **Oder**-Verknüpfung. Eine Und-Regel
            // liefe hier fast immer leer: kaum ein Titel trägt bei beiden
            // Quellen dieselben drei Genres.
            let hit = entry.genres.contains { filters.genres.contains($0) }
            if !hit { return false }
        }
        if let language = filters.language, !entry.languages.contains(language) {
            return false
        }
        if let years = filters.years {
            guard let year = entry.year, years.contains(year) else { return false }
        }
        return true
    }

    static func passesQuick(_ entry: CatalogEntry, _ quick: CatalogQuickFilter, now: Date) -> Bool {
        switch quick {
        case .all:
            return true
        case .fresh:
            return CatalogRanking.isNew(entry, now: now)
        case .popular:
            return CatalogRanking.hasPopularitySignal(entry)
        case .topRated:
            return CatalogRanking.hasRatingBase(entry)
        case .genre(let name):
            return entry.genres.contains(name)
        }
    }

    /// Ein zufälliger Titel aus einer bereits gefilterten Liste.
    ///
    /// Ausdrücklich aus der **Ergebnismenge** und nicht aus dem ganzen
    /// Katalog: wer auf „Anime + Fantasy + abgeschlossen" gefiltert hat, will
    /// keinen Vorschlag, der nichts davon erfüllt.
    ///
    /// `generator` wird hereingereicht, damit sich die Auswahl prüfen lässt —
    /// eine Funktion mit eingebautem Zufall ist kein Testgegenstand.
    static func discover<G: RandomNumberGenerator>(
        in results: [CatalogEntry],
        excluding: String? = nil,
        using generator: inout G
    ) -> CatalogEntry? {
        guard !results.isEmpty else { return nil }
        if results.count == 1 { return results[0] }
        // Denselben Titel nicht zweimal hintereinander vorschlagen — sonst
        // sieht der zweite Druck auf „Titel entdecken" aus wie ein Fehler.
        let pool = excluding.map { id in results.filter { $0.id != id } } ?? results
        guard !pool.isEmpty else { return results.randomElement(using: &generator) }
        return pool.randomElement(using: &generator)
    }
}
