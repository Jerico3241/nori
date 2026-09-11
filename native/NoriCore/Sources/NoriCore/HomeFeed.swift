import Foundation

// Was auf Noris Startseite steht, und warum es dort steht.
//
// Diese Datei enthält **keine** Oberfläche und kein Netz — nur Werte und
// Rechnungen. Das ist Absicht: die Reihenfolge der Titel ist der Teil der
// Startseite, der am ehesten falsch ist und sich am schwersten ansieht. Als
// reine Funktion lässt sie sich prüfen („ein alter, stark trendender Titel
// steht vor einem neuen, den niemand kennt"), als verstreute Sortierung in
// einem SwiftUI-Body nicht.
//
// Die Aufgabenteilung, die überall in dieser Datei gilt:
//
//     Nori-Provider  →  Was gibt es überhaupt?
//     TMDB           →  Was ist das, wie sieht es aus, wie aktuell/beliebt?
//
// Deshalb beginnt jede Reihe beim Nori-Katalog und wird von TMDB nur
// **angereichert und gewichtet**. Nie umgekehrt: eine TMDB-Liste, aus der
// Kacheln entstehen, könnte Titel zeigen, die Nori gar nicht abspielen kann.

// MARK: - Titel

/// Ein Titel, den Nori tatsächlich anbietet.
///
/// Entsteht ausschließlich aus `CatalogItem`, also aus dem, was AniWorld oder
/// Serienstream führen. Es gibt bewusst keinen Weg, einen `HomeTitle` aus
/// TMDB-Daten zu bauen.
struct HomeTitle: Identifiable, Hashable {
    var slug: String
    var title: String
    var provider: CatalogProvider
    var genres: [String]
    var alts: [String]

    /// Zwei Quellen können denselben Slug führen — die Kennung trägt deshalb
    /// beides. Dieselbe Regel wie bei `CatalogItem`.
    var id: String { "\(provider.rawValue)|\(slug)" }

    init(slug: String, title: String, provider: CatalogProvider, genres: [String] = [], alts: [String] = []) {
        self.slug = slug
        self.title = title
        self.provider = provider
        self.genres = genres
        self.alts = alts
    }

    init(_ item: CatalogItem, fallback: CatalogProvider = .aniworld) {
        self.init(
            slug: item.slug,
            title: item.title,
            provider: item.provider ?? fallback,
            genres: item.genres,
            alts: item.alts
        )
    }
}

// MARK: - Signale

/// Was TMDB über einen Nori-Titel weiß, soweit es für die Reihenfolge zählt.
///
/// Alles optional, und das ist der Normalfall, nicht die Ausnahme: ohne
/// Schlüssel, ohne Netz oder ohne sicheren Treffer bleibt die Struktur leer.
/// Die Startseite muss dann trotzdem stehen — jede Rechnung hier kommt mit
/// leeren Signalen zurecht.
struct TMDBSignals: Codable, Hashable {
    var tmdbID: Int?
    var popularity: Double?
    var voteAverage: Double?
    var voteCount: Int?
    /// Erstausstrahlung der Serie.
    var firstAirDate: Date?
    /// Letzte ausgestrahlte Folge. Sagt mehr über „neu" als die
    /// Erstausstrahlung: eine zehn Jahre alte Serie mit einer Staffel von
    /// letzter Woche ist neu, ihre Erstausstrahlung nicht.
    var lastAirDate: Date?
    /// Platz in TMDBs Trendliste dieser Woche, 1-basiert. `nil` heißt „steht
    /// nicht drauf" — das ist keine schlechte Platzierung, sondern keine.
    var trendingRank: Int?
    var genreIDs: [Int] = []
    var hasBackdrop: Bool = false

    static let empty = TMDBSignals()

    var isEmpty: Bool { tmdbID == nil && popularity == nil && trendingRank == nil }
}

/// Ein Titel mit allem, was die Reihenfolge braucht.
struct HomeCandidate: Identifiable, Hashable {
    var title: HomeTitle
    var signals: TMDBSignals = .empty
    /// Wie weit der Titel gesehen ist, 0 bis 1. Aus dem persönlichen
    /// Fortschritt, nicht aus TMDB.
    var watchedRatio: Double = 0
    var inWatchlist: Bool = false
    /// Hat Nori zu dem Titel in den letzten Tagen eine neue Folge gesehen?
    /// Kommt aus dem Kalender der Quelle, nicht aus TMDB.
    var hasFreshEpisode: Bool = false

    var id: String { title.id }
}

// MARK: - Ranking

/// Die Reihenfolge der Startseite.
///
/// Jede Funktion hier ist rein: gleiche Eingabe, gleiche Ausgabe, keine Uhr
/// und kein Netz im Inneren. `now` wird deshalb übergeben und nicht gelesen.
enum HomeRanking {
    /// Was „neu" heißt.
    ///
    /// Neunzig Tage, und nicht weniger, weil beide Quellen Serien verzögert
    /// aufnehmen: eine Staffel, die in Japan im Januar lief, steht hier oft
    /// erst im Februar oder März vollständig. Ein Fenster von dreißig Tagen
    /// hätte die Reihe regelmäßig leer laufen lassen.
    static let newWindow: TimeInterval = 90 * 86_400

    /// Ist der Titel im Sinne der Reihe „neu"?
    ///
    /// Maßgeblich ist die **letzte** Ausstrahlung, ersatzweise die erste.
    /// Eine laufende Staffel einer alten Serie ist neu; eine alte Serie ohne
    /// neue Folgen nicht, egal wie beliebt sie ist.
    static func isNew(_ signals: TMDBSignals, now: Date) -> Bool {
        guard let reference = signals.lastAirDate ?? signals.firstAirDate else { return false }
        let age = now.timeIntervalSince(reference)
        return age >= -14 * 86_400 && age <= newWindow
    }

    /// Der Punktwert für „Neu & beliebt".
    ///
    /// Vier Beiträge, bewusst in dieser Größenordnung:
    ///
    /// - **Trend (0–140).** TMDBs Wochenliste. Das stärkste Signal, weil es
    ///   als einziges sagt, was *gerade jetzt* gesucht wird.
    /// - **Beliebtheit (0–60), logarithmisch.** TMDBs `popularity` ist nach
    ///   oben offen und extrem schief verteilt — linear gewichtet schöbe ein
    ///   einziger Ausreißer alles andere aus der Reihe.
    /// - **Aktualität (0–90).** Fällt über das Fenster linear ab. Eine neue
    ///   Folge aus Noris eigenem Kalender zählt zusätzlich: sie ist der
    ///   direkteste Beweis, dass es hier und heute etwas Neues gibt.
    /// - **Bewertung (−12…+24), nur mit Grundlage.** Unter 50 Stimmen zählt
    ///   sie gar nicht. Sonst stünde ein Titel mit 10,0 aus zwei Stimmen vor
    ///   einer weltweit laufenden Serie — genau der Fall, den die Aufgabe
    ///   ausschließt.
    ///
    /// Ein durchgesehener Titel wird gedämpft: „Neu & beliebt" soll etwas
    /// zeigen, das man noch vor sich hat.
    static func newAndPopularScore(_ candidate: HomeCandidate, now: Date) -> Double {
        let signals = candidate.signals
        var score: Double = 0

        if let rank = signals.trendingRank, rank > 0 {
            score += max(0, 140 - Double(rank - 1) * 3.5)
        }

        if let popularity = signals.popularity, popularity > 0 {
            score += min(60, 9 * log2(1 + popularity))
        }

        if let reference = signals.lastAirDate ?? signals.firstAirDate {
            let age = now.timeIntervalSince(reference)
            if age <= newWindow {
                // Auch noch nicht ausgestrahlte Folgen („age" negativ) zählen
                // voll: eine Serie, die diese Woche anläuft, ist das Neueste,
                // was es gibt.
                let fresh = 1 - max(0, age) / newWindow
                score += 90 * fresh
            }
        }
        if candidate.hasFreshEpisode { score += 35 }

        if let average = signals.voteAverage, let votes = signals.voteCount, votes >= 50 {
            let confidence = min(1, Double(votes) / 500)
            score += max(-12, min(24, (average - 6.5) * 8)) * confidence
        }

        // Schon gesehen heißt nicht „uninteressant", aber es gehört nach
        // hinten. Vollständig gesehen kostet mehr als angefangen.
        score *= 1 - 0.45 * min(1, candidate.watchedRatio)

        return score
    }

    /// „Neu & beliebt", fertig sortiert.
    ///
    /// - Parameter excluding: Kennungen, die schon woanders stehen — der
    ///   Kopfbereich vor allem. Dieselben fünf Titel in Hero und erster Reihe
    ///   lassen die Seite kürzer wirken, als sie ist.
    static func newAndPopular(
        _ candidates: [HomeCandidate],
        now: Date,
        excluding: Set<String> = [],
        limit: Int = 20
    ) -> [HomeCandidate] {
        var scored: [Scored] = []
        for candidate in candidates {
            if excluding.contains(candidate.id) { continue }
            if candidate.signals.isEmpty { continue }
            let score = newAndPopularScore(candidate, now: now)
            if score <= 0 { continue }
            scored.append(Scored(candidate: candidate, score: score))
        }
        return Array(Self.ordered(scored).prefix(limit))
    }

    /// Ein bewerteter Kandidat.
    ///
    /// Ein benannter Typ statt eines Tupels, und die Sortierung als eigene
    /// Funktion: als eine durchgehende Kette aus `filter`, `map`, `sorted`
    /// und `prefix` gab der Typechecker auf („unable to type-check this
    /// expression in reasonable time"). Jede Stufe einer solchen Kette
    /// vervielfacht die Zahl der zu prüfenden Überladungen.
    struct Scored {
        var candidate: HomeCandidate
        var score: Double
    }

    /// Absteigend nach Punkten, bei Gleichstand nach Kennung.
    ///
    /// Der zweite Schlüssel ist kein Schönheitsfehler: ohne ihn ist die
    /// Reihenfolge gleichwertiger Titel unbestimmt, und die Startseite würde
    /// sich bei jedem Neuaufbau anders sortieren.
    static func ordered(_ scored: [Scored]) -> [HomeCandidate] {
        let sorted = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.candidate.id < rhs.candidate.id
        }
        return sorted.map { $0.candidate }
    }

    /// Reine Trendreihe: was diese Woche läuft, ohne Aktualitätsanteil.
    ///
    /// Eigene Reihe nur dort, wo sie sich von „Neu & beliebt" wirklich
    /// unterscheidet — sonst stünde zweimal dasselbe untereinander. Der
    /// Aufrufer prüft das über `excluding`.
    static func trending(
        _ candidates: [HomeCandidate],
        excluding: Set<String> = [],
        limit: Int = 20
    ) -> [HomeCandidate] {
        var scored: [Scored] = []
        for candidate in candidates {
            if excluding.contains(candidate.id) { continue }
            guard let rank = candidate.signals.trendingRank else { continue }
            // Negativ, damit dieselbe absteigende Sortierung greift: Platz 1
            // ist der beste, nicht der schlechteste.
            scored.append(Scored(candidate: candidate, score: -Double(rank)))
        }
        return Array(ordered(scored).prefix(limit))
    }

    /// Top bewertet — aber nur mit belastbarer Stimmenzahl.
    static func topRated(
        _ candidates: [HomeCandidate],
        excluding: Set<String> = [],
        minimumVotes: Int = 300,
        limit: Int = 20
    ) -> [HomeCandidate] {
        var scored: [Scored] = []
        for candidate in candidates {
            if excluding.contains(candidate.id) { continue }
            guard let average = candidate.signals.voteAverage,
                  let votes = candidate.signals.voteCount,
                  votes >= minimumVotes, average > 0
            else { continue }
            scored.append(Scored(candidate: candidate, score: average))
        }
        return Array(ordered(scored).prefix(limit))
    }

    /// Die Titel, aus denen der Kopfbereich wählt.
    ///
    /// Zwei Bedingungen, die für die übrigen Reihen nicht gelten:
    ///
    /// - **Es muss ein Breitbild geben.** Der Kopfbereich ist fast ein halber
    ///   Bildschirm. Ein 2:3-Poster darin ist entweder zerschnitten oder von
    ///   Balken umgeben; ohne jedes Bild bleibt eine schwarze Fläche.
    /// - **Nicht durchgesehen.** „Jetzt ansehen" auf einer Serie, die man
    ///   beendet hat, ist ein leeres Versprechen.
    ///
    /// Die Auswahl **rotiert** über `day`: aus den besten Kandidaten wird
    /// abhängig vom Tag gewählt, innerhalb eines Tages stabil. Ohne das stünde
    /// dort wochenlang derselbe Titel; mit Zufall stünde bei jedem Neuzeichnen
    /// ein anderer, was beim Scrollen aussieht wie ein Fehler.
    static func heroPicks(
        _ candidates: [HomeCandidate],
        now: Date,
        day: Int,
        poolSize: Int = 8,
        limit: Int = 5
    ) -> [HomeCandidate] {
        var scored: [Scored] = []
        for candidate in candidates {
            if !candidate.signals.hasBackdrop { continue }
            if candidate.watchedRatio >= 0.95 { continue }
            let score = newAndPopularScore(candidate, now: now)
            if score <= 0 { continue }
            scored.append(Scored(candidate: candidate, score: score))
        }
        let pool = Array(ordered(scored).prefix(poolSize))

        guard !pool.isEmpty else { return [] }
        let offset = ((day % pool.count) + pool.count) % pool.count
        return Array((pool[offset...] + pool[..<offset]).prefix(limit))
    }
}

// MARK: - Persönliche Empfehlung

/// Was der Nutzer offenbar mag.
///
/// Ausschließlich aus lokalen Daten: Fortschritt, Merkliste, Verlauf. Es geht
/// nichts an TMDB heraus, um ein Profil zu bilden — TMDB wird nur gefragt,
/// welche Titel zu einer bereits gesehenen Serie passen.
struct TasteProfile: Hashable {
    /// Genrename (normalisiert) → Gewicht.
    var genreWeights: [String: Double] = [:]
    /// TMDB-Genrekennung → Gewicht. Getrennt, weil die Quellen ihre Genres
    /// anders benennen als TMDB und eine Übersetzungstabelle nur eine weitere
    /// Fehlerquelle wäre.
    var tmdbGenreWeights: [Int: Double] = [:]
    /// Alles, womit der Nutzer schon zu tun hatte — `provider|slug`.
    var touched: Set<String> = []
    /// Was abgeschlossen ist. Wird härter ausgefiltert als bloß Angefangenes.
    var completed: Set<String> = []
    /// TMDB-Kennungen der meistgesehenen Titel, absteigend. Daraus holt der
    /// Dienst „ähnliche Titel" — je Kennung ein Abruf, deshalb wenige.
    var seeds: [Int] = []

    /// Reicht das für eine echte Empfehlung?
    ///
    /// Zwei angefangene Titel sind kein Geschmack. Darunter zeigt die
    /// Startseite ausdrücklich etwas anderes, statt „Für dich" mit einer
    /// zweiten Beliebtheitsliste zu füllen.
    var isMeaningful: Bool { touched.count >= 3 && !genreWeights.isEmpty }
}

enum HomeTaste {
    /// Das Profil aus dem, was lokal vorliegt.
    ///
    /// Gewichtet nach Nähe und Menge:
    ///
    /// - Ein **abgeschlossener** Titel wiegt am schwersten — jemand ist
    ///   dabeigeblieben.
    /// - Ein **angefangener** Titel wiegt nach Sehanteil.
    /// - Ein Titel auf der **Merkliste** wiegt fest, aber weniger: gemerkt
    ///   ist nicht gesehen.
    /// - Kürzlich Gesehenes wiegt mehr als lange Zurückliegendes.
    static func profile(
        progress: [WatchProgress],
        favorites: [String],
        favoriteSource: [String: CatalogProvider],
        catalog: [HomeTitle],
        signals: [String: TMDBSignals],
        now: Date
    ) -> TasteProfile {
        var out = TasteProfile()
        var seedWeights: [Int: Double] = [:]
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func add(_ title: HomeTitle, weight: Double) {
            guard weight > 0 else { return }
            for genre in title.genres.prefix(4) {
                let key = TMDBMatcher.normalize(genre)
                guard !key.isEmpty else { continue }
                out.genreWeights[key, default: 0] += weight
            }
            if let signal = signals[title.id] {
                for genre in signal.genreIDs.prefix(4) {
                    out.tmdbGenreWeights[genre, default: 0] += weight
                }
                if let id = signal.tmdbID {
                    seedWeights[id, default: 0] += weight
                }
            }
        }

        // Fortschritt, je Serie zusammengefasst: zehn Folgen derselben Serie
        // sind ein Interesse, nicht zehn.
        var perSeries: [String: (ratio: Double, updated: Double)] = [:]
        for item in progress {
            let provider = item.provider ?? providerFromPath(item.episodePath)
            let key = "\(provider.rawValue)|\(item.slug)"
            let ratio = watchRatio(item)
            let existing = perSeries[key]
            perSeries[key] = (
                max(existing?.ratio ?? 0, ratio),
                max(existing?.updated ?? 0, item.updatedAt)
            )
        }

        for (key, entry) in perSeries {
            out.touched.insert(key)
            if entry.ratio >= 0.9 { out.completed.insert(key) }
            guard let title = byID[key] else { continue }
            // `updatedAt` liegt in Millisekunden — dieselbe Einheit wie
            // überall im gespeicherten Stand.
            let days = max(0, now.timeIntervalSince1970 - entry.updated / 1000) / 86_400
            let recency = 1 / (1 + days / 60)
            add(title, weight: (0.6 + entry.ratio) * recency)
        }

        for slug in favorites {
            let provider = favoriteSource[slug]
            let match = byID["\(provider?.rawValue ?? "")|\(slug)"]
                ?? catalog.first { $0.slug == slug }
            guard let title = match else { continue }
            out.touched.insert(title.id)
            add(title, weight: 0.7)
        }

        out.seeds = seedWeights
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(6)
            .map(\.key)
        return out
    }

    /// Wie gut ein Titel zum Profil passt.
    ///
    /// - Parameter recommended: TMDB-Kennungen, die TMDB selbst als ähnlich
    ///   zu den Seed-Titeln genannt hat. Das ist das stärkste Einzelsignal —
    ///   es kennt Zusammenhänge, die kein Genre abbildet (dieselben Macher,
    ///   dieselbe Vorlage, dieselbe Zuschauerschaft).
    static func score(
        _ candidate: HomeCandidate,
        profile: TasteProfile,
        recommended: [Int: Int] = [:]
    ) -> Double {
        var score: Double = 0

        if let id = candidate.signals.tmdbID, let hits = recommended[id] {
            // Von mehreren Seed-Titeln empfohlen zu werden wiegt mehr als von
            // einem, aber nicht linear — sonst gewinnt immer derselbe große
            // Nachbar.
            score += 120 + 40 * log2(Double(hits) + 1)
        }

        let total = profile.genreWeights.values.reduce(0, +)
        if total > 0 {
            var overlap: Double = 0
            for genre in candidate.title.genres.prefix(4) {
                overlap += profile.genreWeights[TMDBMatcher.normalize(genre)] ?? 0
            }
            score += 100 * min(1, overlap / total)
        }

        let tmdbTotal = profile.tmdbGenreWeights.values.reduce(0, +)
        if tmdbTotal > 0 {
            var overlap: Double = 0
            for genre in candidate.signals.genreIDs.prefix(4) {
                overlap += profile.tmdbGenreWeights[genre] ?? 0
            }
            score += 60 * min(1, overlap / tmdbTotal)
        }

        // Qualität als Beimischung, nicht als Hauptsache: eine Empfehlung
        // soll passen, nicht bloß gut bewertet sein.
        if let average = candidate.signals.voteAverage, let votes = candidate.signals.voteCount, votes >= 100 {
            score += max(0, (average - 6) * 6)
        }
        if let popularity = candidate.signals.popularity, popularity > 0 {
            score += min(20, 3 * log2(1 + popularity))
        }

        return score
    }

    /// „Für dich", fertig sortiert.
    ///
    /// Was ausdrücklich **nicht** darin steht:
    ///
    /// - Abgeschlossene Serien. Sie sind vorbei.
    /// - Angefangene Serien. Die stehen in „Weiterschauen", und zweimal
    ///   dasselbe auf einem Bildschirm ist einmal zu viel.
    /// - Titel ohne jede Verbindung zum Profil. Eine Empfehlung mit null
    ///   Punkten ist keine Empfehlung, sondern ein Lückenfüller.
    static func recommend(
        _ candidates: [HomeCandidate],
        profile: TasteProfile,
        recommended: [Int: Int] = [:],
        excluding: Set<String> = [],
        limit: Int = 20
    ) -> [HomeCandidate] {
        var scored: [HomeRanking.Scored] = []
        for candidate in candidates {
            if excluding.contains(candidate.id) { continue }
            if profile.touched.contains(candidate.id) { continue }
            let value = score(candidate, profile: profile, recommended: recommended)
            if value <= 25 { continue }
            scored.append(HomeRanking.Scored(candidate: candidate, score: value))
        }
        return Array(HomeRanking.ordered(scored).prefix(limit))
    }
}

// MARK: - Neue Folgen

/// Eine neu verfügbare Folge, wie sie die Startseite zeigt.
///
/// Quelle ist ausschließlich der Kalender der Provider — TMDB weiß nicht, was
/// AniWorld heute hochgeladen hat. TMDB steuert nur Standbild und Folgentitel
/// bei, und auch das nur, wenn es die Serie sicher zuordnen kann.
struct HomeEpisode: Identifiable, Hashable {
    var entry: AiringEntry
    var provider: CatalogProvider
    /// Standbild aus TMDB. Rückfall ist das Cover aus dem Kalendereintrag.
    var still: URL?
    var episodeTitle: String?

    var id: String { entry.id }
    /// Zeitpunkt als `Date`. `airingAt` steht in Millisekunden.
    var airing: Date { Date(timeIntervalSince1970: entry.airingAt / 1000) }
}

enum HomeEpisodes {
    /// Die neuen Folgen, chronologisch — die neueste zuerst.
    ///
    /// Ausdrücklich **nicht** nach Beliebtheit: „Neue Episoden" beantwortet
    /// die Frage „was ist seit gestern dazugekommen", und darauf ist die
    /// einzige richtige Antwort eine Zeitachse. Beliebtheit entscheidet nur
    /// bei exakt gleicher Zeit, damit die Reihenfolge stabil bleibt.
    ///
    /// - Parameter entries: Der `recent`-Teil des Kalenders, also bereits
    ///   ausgestrahlte Folgen. Kommendes gehört in den Kalender-Tab, nicht
    ///   hierher.
    /// - Parameter availableSlugs: Nur Serien, die im geladenen Nori-Katalog
    ///   stehen. Ein Kalendereintrag zu einem Titel, den der Katalog nicht
    ///   führt, ließe sich antippen und liefe ins Leere.
    static func recent(
        entries: [AiringEntry],
        now: Date,
        availableSlugs: Set<String>? = nil,
        limit: Int = 12
    ) -> [AiringEntry] {
        let nowMs = now.timeIntervalSince1970 * 1000
        var usable: [AiringEntry] = []
        for entry in entries {
            if entry.airingAt > nowMs { continue }
            if let availableSlugs {
                let key = "\(entry.provider?.rawValue ?? "")|\(entry.slug)"
                if !availableSlugs.contains(key) { continue }
            }
            usable.append(entry)
        }

        let sorted = usable.sorted { lhs, rhs in
            if lhs.airingAt != rhs.airingAt { return lhs.airingAt > rhs.airingAt }
            return lhs.id < rhs.id
        }

        // Eine Serie, die heute vier Folgen in vier Sprachen bekommen hat,
        // füllt sonst die ganze Reihe allein.
        var seen: Set<String> = []
        var out: [AiringEntry] = []
        for entry in sorted {
            let key = "\(entry.provider?.rawValue ?? "")|\(entry.slug)|\(entry.season)|\(entry.episode)"
            guard seen.insert(key).inserted else { continue }
            out.append(entry)
            if out.count >= limit { break }
        }
        return out
    }
}

// MARK: - Rückweg von TMDB zu Nori

/// Nachschlagewerk: zu einer TMDB-Zeile den Nori-Titel finden, falls es ihn gibt.
///
/// Das ist die Stelle, an der die Grundregel durchgesetzt wird. TMDBs
/// Ranglisten enthalten überwiegend Titel, die Nori **nicht** anbietet — sie
/// ungefiltert zu zeigen, hieße Kacheln zu bauen, die beim Antippen nichts
/// öffnen. Hier fällt alles heraus, was nicht im geladenen Katalog steht.
///
/// Umgekehrt wird nie gesucht: es gibt keinen Weg, aus einer TMDB-Zeile einen
/// Nori-Titel zu *erzeugen*.
struct HomeCatalogIndex {
    /// Normalisierter Titel → Nori-Titel. Mehrere, weil zwei Quellen dieselbe
    /// Serie führen können und weil Titel selten, aber doch doppelt vorkommen.
    private var buckets: [String: [HomeTitle]] = [:]

    init(_ titles: [HomeTitle]) {
        for title in titles {
            var forms: Set<String> = []
            for raw in [title.title] + title.alts {
                let plain = TMDBMatcher.normalize(raw)
                if !plain.isEmpty { forms.insert(plain) }
                let stripped = TMDBMatcher.stripVariants(raw)
                if !stripped.isEmpty { forms.insert(stripped) }
            }
            for form in forms {
                buckets[form, default: []].append(title)
            }
        }
    }

    var isEmpty: Bool { buckets.isEmpty }

    /// Der passende Nori-Titel, oder `nil`.
    ///
    /// Zwei Stufen, und beide sind nötig: Der Eimer findet schnell die
    /// Handvoll Titel, die überhaupt in Frage kommen; `TMDBMatcher` entscheidet
    /// dann, ob einer davon wirklich passt. Ohne die zweite Stufe würde
    /// „Hunter" aus dem Eimer von „Hunter x Hunter" gezogen, nur weil beide
    /// dieselbe verkürzte Form haben.
    func match(_ candidate: TMDBCandidate) -> HomeTitle? {
        var forms: [String] = []
        for raw in [candidate.name, candidate.originalName] + candidate.alternateNames where !raw.isEmpty {
            forms.append(TMDBMatcher.normalize(raw))
            forms.append(TMDBMatcher.stripVariants(raw))
        }

        var best: (score: Double, title: HomeTitle)?
        var checked: Set<String> = []
        for form in forms where !form.isEmpty {
            guard let bucket = buckets[form] else { continue }
            for title in bucket {
                guard checked.insert(title.id).inserted else { continue }
                // Gegen **alle** Schreibweisen der Quelle prüfen, nicht nur
                // gegen ihren Haupttitel. Sonst scheitert genau der Fall, für
                // den der Eimer den Treffer überhaupt gefunden hat: AniWorld
                // führt „Dämonenjäger", TMDB „Demon Slayer" — verbunden sind
                // die beiden allein über den Alternativtitel.
                var score: Double?
                for query in [title.title] + title.alts {
                    guard let value = TMDBMatcher.score(
                        candidate: candidate,
                        query: query,
                        kind: title.provider
                    ) else { continue }
                    score = max(score ?? 0, value)
                }
                guard let score else { continue }
                if best == nil || score > best!.score {
                    best = (score, title)
                }
            }
        }
        return best?.title
    }
}

/// Aus TMDB-Listen und lokalem Stand die bewertbaren Kandidaten bauen.
///
/// Rein und ohne Netz — die Listen kommen fertig herein. Damit lässt sich in
/// einem Test durchspielen, was sonst nur mit einem TMDB-Schlüssel und der
/// Laune der Ratenbegrenzung zu sehen wäre.
enum HomeSignals {
    /// - Parameters:
    ///   - trending: TMDBs Wochenliste, in ihrer Reihenfolge. Nur hier ist der
    ///     Platz ein Signal.
    ///   - popular: Dauerhaft beliebte Titel. Reihenfolge ohne Bedeutung.
    ///   - airing: Titel mit Folgen aus den letzten Wochen. Ihre bloße
    ///     Zugehörigkeit ist das Aktualitätssignal — die Listenzeilen von TMDB
    ///     führen kein `last_air_date`, nur die Einzelabfrage tut das, und die
    ///     wäre eine Anfrage pro Titel.
    ///   - watched: Sehanteil je `provider|slug`, 0 bis 1.
    ///   - freshEpisodes: Kennungen, zu denen Noris eigener Kalender in den
    ///     letzten Tagen eine Folge gemeldet hat.
    static func candidates(
        catalog: [HomeTitle],
        index: HomeCatalogIndex? = nil,
        trending: [TMDBCandidate] = [],
        popular: [TMDBCandidate] = [],
        airing: [TMDBCandidate] = [],
        watched: [String: Double] = [:],
        favorites: Set<String> = [],
        freshEpisodes: Set<String> = [],
        now: Date
    ) -> [HomeCandidate] {
        let lookup = index ?? HomeCatalogIndex(catalog)
        var signals: [String: TMDBSignals] = [:]

        func absorb(_ rows: [TMDBCandidate], rank: Bool, recentlyAired: Bool) {
            for (offset, row) in rows.enumerated() {
                guard let title = lookup.match(row) else { continue }
                var entry = signals[title.id] ?? TMDBSignals()
                entry.tmdbID = entry.tmdbID ?? row.id
                entry.popularity = max(entry.popularity ?? 0, row.popularity)
                if row.voteCount > (entry.voteCount ?? 0) {
                    entry.voteCount = row.voteCount
                    entry.voteAverage = row.voteAverage
                }
                entry.firstAirDate = entry.firstAirDate ?? row.firstAirDate
                if recentlyAired {
                    // Die Liste ist über `air_date` gefiltert — die Serie hat
                    // also nachweislich in den letzten Wochen gesendet. Das
                    // Datum genau zu kennen, bräuchte einen Abruf pro Titel;
                    // für „ist das neu" reicht die Zugehörigkeit.
                    entry.lastAirDate = max(entry.lastAirDate ?? .distantPast, now.addingTimeInterval(-14 * 86_400))
                }
                if rank, entry.trendingRank == nil {
                    entry.trendingRank = offset + 1
                }
                if entry.genreIDs.isEmpty { entry.genreIDs = row.genreIDs }
                entry.hasBackdrop = entry.hasBackdrop || row.hasBackdrop
                signals[title.id] = entry
            }
        }

        absorb(trending, rank: true, recentlyAired: false)
        absorb(popular, rank: false, recentlyAired: false)
        absorb(airing, rank: false, recentlyAired: true)

        return catalog.map { title in
            HomeCandidate(
                title: title,
                signals: signals[title.id] ?? .empty,
                watchedRatio: watched[title.id] ?? 0,
                inWatchlist: favorites.contains(title.slug),
                hasFreshEpisode: freshEpisodes.contains(title.id)
            )
        }
    }
}

// MARK: - Der fertige Feed

/// Eine benannte Reihe der Startseite.
struct HomeRow: Identifiable, Hashable {
    var title: String
    var items: [HomeCandidate]
    /// Wohin „Alle anzeigen" führt, sofern es dort etwas zu zeigen gibt.
    var id: String { title }
}

/// Was die Startseite darstellt — das Ergebnis aller Rechnungen dieser Datei.
///
/// Die Ansicht bekommt genau diese Struktur und sortiert nichts mehr selbst.
/// Das ist der Unterschied zur vorherigen Startseite, die ihre Reihen in
/// `body` und in einer `task` zusammensuchte: Rankinglogik in einem SwiftUI-
/// Body läuft bei jedem Neuzeichnen, ist nicht prüfbar und lässt sich nicht
/// ändern, ohne die Darstellung anzufassen.
///
/// Leere Reihen bleiben leer. Die Ansicht blendet sie aus, statt einen
/// Platzhalter zu zeigen — eine Überschrift ohne Inhalt ist ein Versprechen,
/// das die Seite nicht hält.
struct HomeFeed {
    var hero: [HomeCandidate] = []
    var continueWatching: [WatchProgress] = []
    var newAndPopular: [HomeCandidate] = []
    var newEpisodes: [AiringEntry] = []
    /// „Für dich" — oder der Ersatz beim Kaltstart. Die Überschrift steht
    /// daneben, weil sie sich mit dem Inhalt ändert: ohne Verlauf ist es
    /// keine Personalisierung und darf auch nicht so heißen.
    var recommendations: [HomeCandidate] = []
    var recommendationTitle: String = "Für dich"
    /// Weitere Reihen — Trend, Bestbewertetes, Genres. Nur, was sich vom
    /// bereits Gezeigten unterscheidet.
    var extraRows: [HomeRow] = []

    /// Steht außer dem Kopfbereich überhaupt etwas auf der Seite?
    var hasContent: Bool {
        !continueWatching.isEmpty
            || !newAndPopular.isEmpty
            || !newEpisodes.isEmpty
            || !recommendations.isEmpty
            || !extraRows.isEmpty
    }
}
