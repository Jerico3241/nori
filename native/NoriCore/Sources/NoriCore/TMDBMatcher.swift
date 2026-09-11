import Foundation

/// Ein Trefferkandidat aus einer TMDB-Antwort.
///
/// Bewusst ein eigener Typ und nicht das rohe `[String: Any]` der Antwort.
/// Die Bewertung lag früher mitten im Netzcode und war damit nur über eine
/// echte HTTP-Antwort erreichbar — also gar nicht testbar. Hier ist sie ein
/// Wert, den ein Test in zwei Zeilen aufbaut.
struct TMDBCandidate: Codable, Hashable {
    var id: Int
    var name: String
    var originalName: String
    /// Weitere Schreibweisen, sofern bekannt. `/search/tv` liefert keine;
    /// `/tv/{id}/alternative_titles` schon.
    var alternateNames: [String] = []
    var firstAirYear: Int?
    /// Erstausstrahlung als Datum. Das Jahr allein reicht der Zuordnung, für
    /// „wie neu ist das" braucht es den Tag.
    var firstAirDate: Date?
    var popularity: Double = 0
    var voteAverage: Double = 0
    var voteCount: Int = 0
    var genreIDs: [Int] = []
    var originCountries: [String] = []
    var posterPath: String?
    var backdropPath: String?
    var overview: String?
    /// Staffelzahl. Steht nur in `/tv/{id}`, nicht in der Suche.
    var seasonCount: Int?

    var hasPoster: Bool { !(posterPath ?? "").isEmpty }
    var hasBackdrop: Bool { !(backdropPath ?? "").isEmpty }

    /// Aus einer Zeile der TMDB-Antwort.
    ///
    /// Gibt `nil` zurück, wenn die Zeile keine Kennung trägt — ohne die ist
    /// ein Treffer wertlos, weil sich nichts nachladen lässt.
    init?(json row: [String: Any]) {
        guard let id = row["id"] as? Int else { return nil }
        self.id = id
        name = row["name"] as? String ?? ""
        originalName = row["original_name"] as? String ?? ""
        let aired = row["first_air_date"] as? String
        firstAirYear = Self.year(aired)
        firstAirDate = Self.date(aired)
        popularity = row["popularity"] as? Double ?? 0
        voteAverage = row["vote_average"] as? Double ?? 0
        voteCount = row["vote_count"] as? Int ?? 0
        genreIDs = row["genre_ids"] as? [Int] ?? (row["genres"] as? [[String: Any]])?.compactMap { $0["id"] as? Int } ?? []
        originCountries = row["origin_country"] as? [String] ?? []
        posterPath = row["poster_path"] as? String
        backdropPath = row["backdrop_path"] as? String
        overview = row["overview"] as? String
        seasonCount = row["number_of_seasons"] as? Int
    }

    /// Für Tests und für von Hand gebaute Kandidaten.
    init(
        id: Int,
        name: String,
        originalName: String = "",
        alternateNames: [String] = [],
        firstAirYear: Int? = nil,
        firstAirDate: Date? = nil,
        popularity: Double = 0,
        voteAverage: Double = 0,
        voteCount: Int = 0,
        genreIDs: [Int] = [],
        originCountries: [String] = [],
        posterPath: String? = nil,
        backdropPath: String? = nil,
        overview: String? = nil,
        seasonCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.originalName = originalName.isEmpty ? name : originalName
        self.alternateNames = alternateNames
        self.firstAirYear = firstAirYear
        self.firstAirDate = firstAirDate
        self.popularity = popularity
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.genreIDs = genreIDs
        self.originCountries = originCountries
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.overview = overview
        self.seasonCount = seasonCount
    }

    static func year(_ date: String?) -> Int? {
        guard let date, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }

    /// TMDB schreibt Datumsangaben als `yyyy-MM-dd`, gelegentlich als leere
    /// Zeichenkette. Fest auf `en_US_POSIX` und UTC, damit die Auswertung
    /// nicht von der Gebietseinstellung des Geräts abhängt — in einem
    /// japanischen Kalender ergäbe `yyyy` ein anderes Jahr.
    static func date(_ raw: String?) -> Date? {
        guard let raw, raw.count >= 10 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(raw.prefix(10)))
    }
}

/// Die Zuordnung zwischen einem Nori-Titel und einem TMDB-Eintrag.
///
/// ## Warum das nicht „Titel gleich Titel" ist
///
/// AniWorld und Serienstream führen dieselbe Serie regelmäßig unter einem
/// anderen Namen als TMDB — eingedeutscht, verkürzt, mit Staffelzusatz, mit
/// Jahreszahl, mit oder ohne Untertitel. Ein Vergleich auf Gleichheit findet
/// deshalb nur einen Bruchteil. Umgekehrt ist eine unscharfe Suche gefährlich:
/// wer „Ein Stück" schreibt, darf nicht bei „One Piece" landen, und ein
/// weltweit bekannter Titel darf einen unbekannten gleichen Namens nicht
/// verdrängen.
///
/// Die Regel dagegen: **Der Titel entscheidet, alles andere gewichtet nur.**
/// Beliebtheit, Genre und Herkunftsland können einen Treffer vor einen anderen
/// ziehen, aber keinen Treffer *erzeugen*. Wer die Titelschwelle nicht reißt,
/// fällt raus — auch wenn er die bekannteste Serie der Welt ist. Genau dieser
/// Fehler hatte früher falsche Cover erzeugt.
enum TMDBMatcher {
    /// Ab dieser Titelnähe gilt ein Kandidat überhaupt als Treffer.
    /// Entspricht „der eine Titel steckt im anderen".
    static let titleFloor: Double = 80

    // MARK: - Normalisierung

    /// Ein Titel auf seine vergleichbare Form.
    ///
    /// Kleingeschrieben, ohne Akzente, ohne Satzzeichen, ohne Mehrfach-
    /// Leerzeichen. Damit sind „Re:ZERO – Starting Life in Another World" und
    /// „Re Zero Starting Life in Another World" dasselbe, und „Pokémon" trifft
    /// „Pokemon".
    ///
    /// Nicht entfernt werden Ziffern: „86" und „91 Days" sind Titel, keine
    /// Zählung.
    static func normalize(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
        var out = ""
        out.reserveCapacity(folded.count)
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            let char = Character(scalar)
            if char.isLetter || char.isNumber {
                out.append(char)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        while out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    /// Was nach dem Abziehen von Jahres- und Staffelangaben übrig bleibt.
    ///
    /// AniWorld hängt „(2024)" an, Serienstream „Staffel 2", und bei Anime
    /// steht regelmäßig „2nd Season" oder „Final Season" im Titel. TMDB führt
    /// alle diese Fassungen unter **einem** Serieneintrag — die Zusätze
    /// müssen also weg, sonst findet die Suche gar nichts.
    ///
    /// Das Ergebnis ist bereits normalisiert.
    static func stripVariants(_ raw: String) -> String {
        var text = normalize(raw)
        let patterns = [
            #"\s*\b(19|20)\d{2}\b\s*$"#,
            #"\s*\b(staffel|season|saison|serie|part|teil|cour)\s+\d+\b"#,
            #"\s*\b\d+\s*(staffel|season)\b"#,
            #"\s*\b(final|last|second|third|fourth|fifth|zweite|dritte|vierte)\s+(staffel|season)\b"#,
            #"\s*\b(the\s+)?final\s+season\b"#,
            #"\s*\b\d+(st|nd|rd|th)\s+season\b"#,
        ]
        for pattern in patterns {
            text = text.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return normalize(text)
    }

    /// Suchbegriffe zu einem Titel, in absteigender Güte.
    ///
    /// Die Reihenfolge ist die Reihenfolge der Versuche: erst der Titel, wie
    /// die Quelle ihn führt, dann seine Alternativtitel, dann die verkürzten
    /// Fassungen. Der erste Begriff, der einen Treffer über der Schwelle
    /// liefert, gewinnt — deshalb steht der genaueste vorn.
    ///
    /// Rohform, nicht normalisiert: TMDB sucht selbst unscharf und kommt mit
    /// Satzzeichen besser zurecht als mit einer entkernten Zeichenkette.
    static func queries(for title: String, alternates: [String] = []) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []

        func add(_ raw: String) {
            let cleaned = raw
                .replacingOccurrences(of: #"\s*\(\d{4}\)\s*"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count >= 2 else { return }
            let key = normalize(cleaned)
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            out.append(cleaned)
        }

        add(title)
        for alt in alternates { add(alt) }
        // „Titel: Untertitel" steht bei TMDB oft nur als „Titel".
        for candidate in [title] + alternates {
            if let colon = candidate.firstIndex(of: ":") {
                add(String(candidate[candidate.startIndex ..< colon]))
            }
        }
        // Zuletzt die um Staffel- und Jahresangaben bereinigte Fassung. Sie
        // steht hinten, weil sie am meisten weglässt und damit am ehesten
        // einen falschen Nachbarn trifft.
        for candidate in [title] + alternates {
            add(stripVariants(candidate))
        }
        return out
    }

    // MARK: - Titelnähe

    /// Wie nah zwei Titel beieinander liegen: 0 (nichts) bis 400 (identisch).
    ///
    /// Die Stufen sind grob und absichtlich nicht stetig. Eine feinkörnige
    /// Ähnlichkeit — Levenshtein etwa — verleitet dazu, knappe Werte doch
    /// noch zu nehmen; hier gibt es „gleich", „steckt drin", „fängt an mit",
    /// „gemeinsame Wörter" und „nein".
    static func titleScore(query: String, against candidate: TMDBCandidate) -> Double {
        let names = ([candidate.name, candidate.originalName] + candidate.alternateNames)
            .filter { !$0.isEmpty }
        var best: Double = 0
        for form in [normalize(query), stripVariants(query)] where !form.isEmpty {
            for name in names {
                for variant in [normalize(name), stripVariants(name)] where !variant.isEmpty {
                    best = max(best, pairScore(form, variant))
                }
            }
        }
        return best
    }

    private static func pairScore(_ a: String, _ b: String) -> Double {
        if a == b { return 400 }
        // Enthalten, aber ähnlich lang: „Attack on Titan" in „Attack on Titan
        // Final Season" ist derselbe Titel, „Bleach" in „Bleach Thousand-Year
        // Blood War" auch. „One" in „One Piece" dagegen nicht — deshalb das
        // Längenverhältnis.
        let longer = a.count >= b.count ? a : b
        let shorter = a.count >= b.count ? b : a
        guard shorter.count >= 3 else { return 0 }
        let ratio = Double(shorter.count) / Double(longer.count)
        if longer.contains(shorter) {
            if ratio >= 0.7 { return 260 }
            // Der Anfang zählt nur bei einem Wort, das für sich steht.
            // „One" steckt am Anfang von „One Piece", ist aber kein Titel,
            // sondern ein Zahlwort — fünf Zeichen sind die Grenze, an der
            // die Verwechslungsgefahr abreißt.
            if longer.hasPrefix(shorter), shorter.count >= 5 { return 180 }
            return ratio >= 0.4 ? 110 : 0
        }
        // Gemeinsame Wörter. Fängt die Fälle, in denen dieselbe Serie in
        // beiden Fassungen dieselben Hauptwörter trägt, nur anders verbunden.
        let wordsA = Set(a.split(separator: " ").filter { $0.count >= 3 })
        let wordsB = Set(b.split(separator: " ").filter { $0.count >= 3 })
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0 }
        let overlap = Double(wordsA.intersection(wordsB).count)
        let jaccard = overlap / Double(wordsA.union(wordsB).count)
        if jaccard >= 0.8 { return 150 }
        if jaccard >= 0.6 { return 95 }
        return 0
    }

    // MARK: - Gesamtbewertung

    /// Wie gut ein Kandidat zu einer Suche passt.
    ///
    /// Gibt `nil` zurück, wenn der Titel die Schwelle nicht erreicht. Ein
    /// `nil` ist hier eine Antwort, kein Fehler: lieber gar kein Cover als
    /// das einer fremden Serie.
    ///
    /// - Parameters:
    ///   - kind: Die Quelle des Nori-Titels. AniWorld führt Anime, Serienstream
    ///     Realserien — das ist ein starkes Signal, wenn zwei Einträge gleich
    ///     heißen.
    ///   - expectedYear: Erscheinungsjahr laut Quelle, sofern bekannt.
    ///   - expectedSeasons: Staffelzahl laut Quelle, sofern bekannt.
    static func score(
        candidate: TMDBCandidate,
        query: String,
        kind: CatalogProvider,
        expectedYear: Int? = nil,
        expectedSeasons: Int? = nil
    ) -> Double? {
        let title = titleScore(query: query, against: candidate)
        guard title >= titleFloor else { return nil }

        var score = title

        // Medientyp. Die Genre-Kennung 16 ist bei TMDB „Animation".
        let animated = candidate.genreIDs.contains(16)
        let japanese = candidate.originCountries.contains("JP")
        switch kind {
        case .aniworld:
            if animated { score += 120 }
            if japanese { score += 60 }
        case .serienstream:
            // Ein japanischer Zeichentrick unter den Realserien ist fast
            // immer der falsche Eintrag — dieselbe Marke gibt es oft als
            // Anime **und** als Realverfilmung.
            if animated && japanese { score -= 90 }
            else if japanese { score -= 20 }
            if candidate.originCountries.contains(where: { ["US", "GB", "DE", "CA", "AU", "KR"].contains($0) }) {
                score += 40
            }
        }

        // Jahr. Ein Treffer im selben Jahr ist ein starkes Zeichen, ein
        // weit entferntes Jahr ein Warnzeichen — aber kein Ausschluss:
        // Neuverfilmungen tragen denselben Namen, und die Quellen führen
        // das Jahr oft gar nicht.
        if let expectedYear, let actual = candidate.firstAirYear {
            let gap = abs(expectedYear - actual)
            if gap == 0 { score += 60 }
            else if gap == 1 { score += 25 }
            else if gap >= 4 { score -= 70 }
        }

        // Staffelzahl. Schwach gewichtet: die Quellen zählen Specials und
        // Filme mal mit, mal nicht.
        if let expectedSeasons, let actual = candidate.seasonCount, expectedSeasons > 0, actual > 0 {
            score += abs(expectedSeasons - actual) <= 1 ? 15 : -15
        }

        // Beliebtheit nur als Stichentscheid. Gedeckelt, damit sie einen
        // schwächeren Titeltreffer nie überholen kann: der Abstand zwischen
        // zwei Titelstufen ist stets größer als dieser Deckel.
        score += min(candidate.popularity, 40)

        return score
    }

    /// Der beste Kandidat, oder `nil`.
    ///
    /// - Parameter requirePoster: Für die Cover-Suche zwingend — ein Treffer
    ///   ohne Poster liefert kein Cover. Für die Kennungssuche nicht: eine
    ///   Serie ohne Poster hat trotzdem Folgen mit Bild und Text.
    static func best(
        in candidates: [TMDBCandidate],
        query: String,
        kind: CatalogProvider,
        expectedYear: Int? = nil,
        expectedSeasons: Int? = nil,
        requirePoster: Bool = false
    ) -> TMDBCandidate? {
        var winner: (score: Double, candidate: TMDBCandidate)?
        for candidate in candidates {
            if requirePoster && !candidate.hasPoster { continue }
            guard let score = score(
                candidate: candidate,
                query: query,
                kind: kind,
                expectedYear: expectedYear,
                expectedSeasons: expectedSeasons
            ) else { continue }
            if winner == nil || score > winner!.score {
                winner = (score, candidate)
            }
        }
        return winner?.candidate
    }

    /// Dieselbe Auswahl auf den rohen Zeilen einer TMDB-Antwort.
    static func best(
        in rows: [[String: Any]],
        query: String,
        kind: CatalogProvider,
        expectedYear: Int? = nil,
        requirePoster: Bool = false
    ) -> TMDBCandidate? {
        best(
            in: rows.compactMap(TMDBCandidate.init(json:)),
            query: query,
            kind: kind,
            expectedYear: expectedYear,
            requirePoster: requirePoster
        )
    }
}
