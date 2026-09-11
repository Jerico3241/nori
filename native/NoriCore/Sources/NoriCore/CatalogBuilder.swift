import Foundation

/// Aus rohen Providerlisten und TMDB-Ranglisten die Katalogeinträge bauen.
///
/// Rein und ohne Netz — alles kommt fertig herein. Damit lässt sich in einem
/// Test durchspielen, was sonst nur mit einem TMDB-Schlüssel, zwei erreichbaren
/// Quellseiten und der Laune der Ratenbegrenzung zu sehen wäre.
///
/// ## Die Grundregel
///
/// Ein Eintrag entsteht **ausschließlich** aus `CatalogItem`. TMDB kann jeden
/// Eintrag anreichern, aber keinen erzeugen: Was Nori nicht abspielen kann,
/// steht nicht im Katalog. Deshalb beginnt `build` bei den Providerlisten und
/// schlägt TMDB von dort aus nach — nie umgekehrt.
enum CatalogBuilder {
    /// Alles, was von außen dazukommt.
    ///
    /// Jedes Feld darf leer sein. Ohne TMDB-Schlüssel, ohne Netz oder im
    /// Flugmodus bleibt alles leer, und `build` liefert trotzdem einen
    /// vollständigen Katalog — nur ohne Bewertungen, ohne Jahreszahlen aus
    /// TMDB und ohne Beliebtheitsreihenfolge. Das ist der Normalbetrieb ohne
    /// Netz, kein Sonderfall.
    struct Context {
        /// TMDBs Wochenliste, in ihrer Reihenfolge. Nur hier ist der Platz
        /// selbst ein Signal.
        var trending: [TMDBCandidate] = []
        /// Dauerhaft beliebte Titel. Reihenfolge ohne Bedeutung.
        var popular: [TMDBCandidate] = []
        /// Titel mit Folgen aus den letzten Wochen.
        var airing: [TMDBCandidate] = []
        /// Titel, die TMDB als abgeschlossen oder abgesetzt führt.
        var ended: [TMDBCandidate] = []
        /// Noris eigener Kalender, beide Quellen, gelaufen und kommend.
        var calendar: [AiringEntry] = []
        /// TMDB-Kennungen, die von der Cover-Suche her schon vorliegen
        /// (Slug → Kennung). Kostet keine Anfrage.
        var knownIDs: [String: Int] = [:]
        /// Bewertungen aus derselben Quelle (Slug → TMDB-Wert 0–10).
        var knownRatings: [String: Double] = [:]
        /// Sprachen, in denen tatsächlich schon abgespielt wurde
        /// (Slug → Sprachen). Der belastbarste Sprachbeleg, den es gibt.
        var playedLanguages: [String: Set<CatalogLanguage>] = [:]
    }

    /// Was zu einem Nori-Titel aus TMDB zusammengetragen wurde.
    private struct Facts {
        var signals = TMDBSignals()
        var originalTitle: String?
        var alternateNames: [String] = []
        var endedByTMDB = false
    }

    static func build(_ items: [CatalogItem], context: Context, now: Date) -> [CatalogEntry] {
        guard !items.isEmpty else { return [] }

        let titles = items.map { HomeTitle($0, fallback: .aniworld) }
        let index = HomeCatalogIndex(titles)
        let facts = absorb(context: context, index: index, now: now)
        let live = calendarEvidence(context.calendar, now: now)

        var raw: [CatalogEntry] = []
        raw.reserveCapacity(items.count)
        for item in items {
            let provider = item.provider ?? .aniworld
            let key = "\(provider.rawValue)|\(item.slug)"
            raw.append(entry(
                item: item,
                provider: provider,
                facts: facts[key],
                live: live[key],
                context: context
            ))
        }
        return merge(raw)
    }

    // MARK: - TMDB

    /// TMDBs Zeilen auf Noris Titel zurückführen.
    ///
    /// Dieselbe Bewegungsrichtung wie auf der Startseite: Der Index kennt nur
    /// Nori-Titel, und `match` gibt entweder einen davon zurück oder nichts.
    /// Eine Zeile, die zu keinem Nori-Titel gehört, fällt hier heraus und
    /// kann nie in einer Kachel landen.
    private static func absorb(
        context: Context,
        index: HomeCatalogIndex,
        now: Date
    ) -> [String: Facts] {
        var out: [String: Facts] = [:]

        func take(_ rows: [TMDBCandidate], rank: Bool, recentlyAired: Bool, ended: Bool) {
            for (offset, row) in rows.enumerated() {
                guard let title = index.match(row) else { continue }
                var entry = out[title.id] ?? Facts()
                entry.signals.tmdbID = entry.signals.tmdbID ?? row.id
                entry.signals.popularity = max(entry.signals.popularity ?? 0, row.popularity)
                // Die belastbarere Bewertung gewinnt, nicht die höhere.
                if row.voteCount > (entry.signals.voteCount ?? 0) {
                    entry.signals.voteCount = row.voteCount
                    entry.signals.voteAverage = row.voteAverage
                }
                entry.signals.firstAirDate = entry.signals.firstAirDate ?? row.firstAirDate
                if recentlyAired {
                    // Die Liste ist über `air_date` gefiltert — die Serie hat
                    // also nachweislich in den letzten Wochen gesendet. Das
                    // genaue Datum kostete einen Abruf pro Titel; für „ist das
                    // neu" reicht die Zugehörigkeit.
                    entry.signals.lastAirDate = max(
                        entry.signals.lastAirDate ?? .distantPast,
                        now.addingTimeInterval(-14 * 86_400)
                    )
                }
                if rank, entry.signals.trendingRank == nil {
                    entry.signals.trendingRank = offset + 1
                }
                if entry.signals.genreIDs.isEmpty { entry.signals.genreIDs = row.genreIDs }
                entry.signals.hasBackdrop = entry.signals.hasBackdrop || row.hasBackdrop
                if entry.originalTitle == nil, !row.originalName.isEmpty {
                    entry.originalTitle = row.originalName
                }
                for name in [row.name] + row.alternateNames
                where !name.isEmpty && !entry.alternateNames.contains(name) {
                    entry.alternateNames.append(name)
                }
                if ended { entry.endedByTMDB = true }
                out[title.id] = entry
            }
        }

        take(context.trending, rank: true, recentlyAired: false, ended: false)
        take(context.popular, rank: false, recentlyAired: false, ended: false)
        take(context.airing, rank: false, recentlyAired: true, ended: false)
        take(context.ended, rank: false, recentlyAired: false, ended: true)
        return out
    }

    // MARK: - Noris eigener Kalender

    /// Was der Kalender über einen Titel sagt.
    private struct Live {
        var languages: Set<CatalogLanguage> = []
        /// Folge in den letzten `freshEpisodeWindow` erschienen.
        var fresh = false
        /// Folge kommt noch oder kam kürzlich — die Serie läuft.
        var running = false
    }

    /// Wie lange eine gelaufene Folge den Titel als „läuft" ausweist.
    ///
    /// Großzügiger als das Neu-Fenster: Eine Serie mit einer Folge von vor
    /// zwei Monaten ist nicht mehr neu, läuft aber sehr wohl noch.
    private static let runningWindow: TimeInterval = 60 * 86_400

    private static func calendarEvidence(_ entries: [AiringEntry], now: Date) -> [String: Live] {
        var out: [String: Live] = [:]
        let nowMs = now.timeIntervalSince1970 * 1000
        let freshFloor = nowMs - CatalogRanking.freshEpisodeWindow * 1000
        let runningFloor = nowMs - runningWindow * 1000

        for entry in entries {
            // Ältere Kalendereinträge tragen die Quelle nicht als Feld;
            // AniWorld ist dieselbe Vorgabe wie überall im Kern.
            let provider = entry.provider ?? .aniworld
            let key = "\(provider.rawValue)|\(entry.slug)"
            var live = out[key] ?? Live()
            for raw in entry.languages {
                if let language = CatalogLanguage.parse(raw) { live.languages.insert(language) }
            }
            // Eine angekündigte Folge liegt in der Zukunft und ist damit der
            // stärkste Beleg überhaupt, dass die Serie läuft — sie ist aber
            // noch nicht abrufbar und deshalb nicht „neu".
            if entry.airingAt > nowMs {
                live.running = true
            } else {
                if entry.airingAt >= freshFloor { live.fresh = true }
                if entry.airingAt >= runningFloor { live.running = true }
            }
            out[key] = live
        }
        return out
    }

    // MARK: - Ein einzelner Eintrag

    private static func entry(
        item: CatalogItem,
        provider: CatalogProvider,
        facts: Facts?,
        live: Live?,
        context: Context
    ) -> CatalogEntry {
        var signals = facts?.signals ?? TMDBSignals()
        // Kennung und Bewertung aus dem Cover-Index: Sie liegen von der
        // Cover-Suche her vor und kosten keine Anfrage. Für Titel, die auf
        // keiner Rangliste stehen, sind sie die einzige TMDB-Auskunft
        // überhaupt — ohne sie bliebe der halbe Katalog ohne Bewertung.
        if signals.tmdbID == nil { signals.tmdbID = context.knownIDs[item.slug] }
        if signals.voteAverage == nil, let rating = context.knownRatings[item.slug] {
            signals.voteAverage = rating
        }

        let source = CatalogSource(provider: provider, slug: item.slug, title: item.title)
        let title = cleanTitle(item.title)
        let year = signals.firstAirDate.map { calendarYear($0) } ?? yearInTitle(item.title)

        var genres = CatalogGenres.canonical(item.genres)
        for name in CatalogGenres.canonical(tmdbIDs: signals.genreIDs) where !genres.contains(name) {
            genres.append(name)
        }

        var alternates = item.alts
        for name in facts?.alternateNames ?? [] where !alternates.contains(name) && name != title {
            alternates.append(name)
        }

        var languages = live?.languages ?? []
        languages.formUnion(context.playedLanguages[item.slug] ?? [])

        var status: CatalogStatus = .unknown
        if live?.running == true {
            status = .running
        } else if signals.lastAirDate != nil {
            // In TMDBs Liste kürzlich ausgestrahlter Serien — gesendet hat
            // sie also.
            status = .running
        } else if facts?.endedByTMDB == true {
            status = .completed
        }

        var entry = CatalogEntry(primary: source)
        entry.title = title
        entry.originalTitle = facts?.originalTitle
        entry.alternativeTitles = Array(alternates.prefix(10))
        entry.year = year
        entry.genres = genres
        entry.status = status
        entry.languages = languages.sorted { $0.order < $1.order }
        entry.signals = signals
        entry.hasFreshEpisode = live?.fresh ?? false
        entry.titleKey = TMDBMatcher.normalize(title)
        entry.mergeKeys = mergeKeys(title: title, alternates: entry.alternativeTitles)
        entry.searchKey = CatalogSearch.key(
            title: title,
            originalTitle: entry.originalTitle,
            alternates: entry.alternativeTitles,
            genres: genres,
            year: year
        )
        return entry
    }

    /// Die Formen, unter denen ein Eintrag zum Zusammenführen gefunden wird.
    ///
    /// Der Haupttitel und die Alternativtitel, jeweils vollständig
    /// normalisiert. Sehr kurze Formen fallen heraus: „Bee" als
    /// Alternativtitel würde sonst jeden anderen Titel „Bee" an sich ziehen.
    static func mergeKeys(title: String, alternates: [String]) -> [String] {
        var out: [String] = []
        for raw in [title] + alternates {
            let key = TMDBMatcher.normalize(raw)
            guard key.count >= 4, !out.contains(key) else { continue }
            out.append(key)
        }
        return out
    }

    /// Der Titel ohne angehängte Jahreszahl.
    ///
    /// AniWorld führt Neuauflagen als „Titel (2024)". Die Jahreszahl gehört
    /// in das Feld `year`, nicht in die Überschrift der Kachel.
    static func cleanTitle(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(
            of: #"\s*\((19|20)\d{2}\)\s*$"#,
            with: "",
            options: .regularExpression
        )
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? raw : trimmed
    }

    /// Die Jahreszahl aus einem Titel wie „Battlestar Galactica (2003)".
    ///
    /// Nur als Rückfall, wenn TMDB den Titel nicht führt: Sie ist das Jahr,
    /// unter dem die Quelle den Titel einsortiert, nicht zwingend das der
    /// Erstausstrahlung.
    static func yearInTitle(_ raw: String) -> Int? {
        guard let match = raw.range(of: #"\((19|20)\d{2}\)\s*$"#, options: .regularExpression) else {
            return nil
        }
        let digits = raw[match].filter(\.isNumber)
        return Int(digits)
    }

    private static func calendarYear(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.component(.year, from: date)
    }

    // MARK: - Dubletten

    /// Denselben Titel aus zwei Quellen zu **einem** Eintrag zusammenfassen.
    ///
    /// ## Warum nur über Quellgrenzen hinweg
    ///
    /// Innerhalb einer Quelle wird **nie** zusammengefasst, und das ist keine
    /// Vorsicht, sondern zwingend: AniWorld führt „Attack on Titan" und
    /// „Attack on Titan: Final Season" als zwei eigene Titel mit zwei eigenen
    /// Slugs und zwei eigenen Folgenlisten. Beide tragen dieselbe verkürzte
    /// Form und oft dieselbe TMDB-Kennung. Sie zusammenzufassen hieße, einen
    /// Titel aus dem Katalog zu entfernen, den der Nutzer öffnen können muss.
    ///
    /// Die Aufgabe der Entdopplung ist eine andere: Derselbe Stoff steht bei
    /// AniWorld **und** bei Serienstream. Genau dieser Fall wird
    /// zusammengeführt, alles andere bleibt, wie es ist.
    ///
    /// ## Woran zwei Einträge als derselbe Titel erkannt werden
    ///
    /// 1. **Gleiche TMDB-Kennung.** Das sicherste Merkmal, wenn es vorliegt.
    /// 2. **Gleiche verkürzte Titelform und verträgliche Jahre.** „Verträglich"
    ///    heißt: beide unbekannt, oder höchstens ein Jahr auseinander.
    ///    Neuverfilmungen tragen denselben Namen — ohne die Jahresprüfung
    ///    verschwände die Fassung von 2003 hinter der von 1978.
    ///
    /// Ein bloßer Zeichenkettenvergleich der Haupttitel reicht dafür nicht:
    /// die Quellen schreiben dieselbe Serie unterschiedlich. Deshalb
    /// `stripVariants`, dieselbe Normalisierung wie in der TMDB-Zuordnung,
    /// und zusätzlich die Alternativtitel.
    static func merge(_ entries: [CatalogEntry]) -> [CatalogEntry] {
        // Kennung → Sammelschlüssel. Zuerst über die TMDB-Kennung, danach
        // über die Titelform; so gewinnt das sicherere Merkmal.
        var byTMDB: [Int: Int] = [:]
        var byTitle: [String: [Int]] = [:]
        // Für jeden Eintrag die Nummer seiner Gruppe.
        var group = Array(repeating: -1, count: entries.count)
        var groups: [[Int]] = []

        func open(_ position: Int) -> Int {
            groups.append([position])
            group[position] = groups.count - 1
            return groups.count - 1
        }

        func join(_ position: Int, to slot: Int) -> Bool {
            // Nur zusammenlegen, wenn keine Quelle doppelt vorkäme.
            let providers = Set(groups[slot].map { entries[$0].provider })
            guard !providers.contains(entries[position].provider) else { return false }
            groups[slot].append(position)
            group[position] = slot
            return true
        }

        for (position, entry) in entries.enumerated() {
            var slot: Int?

            if let id = entry.tmdbID, let existing = byTMDB[id], join(position, to: existing) {
                slot = existing
            }

            if slot == nil {
                search: for key in entry.mergeKeys {
                    for candidate in byTitle[key] ?? [] {
                        guard yearsCompatible(entries, groups[candidate], entry) else { continue }
                        if join(position, to: candidate) {
                            slot = candidate
                            break search
                        }
                    }
                }
            }

            let chosen = slot ?? open(position)
            if let id = entry.tmdbID, byTMDB[id] == nil { byTMDB[id] = chosen }
            for key in entry.mergeKeys where !(byTitle[key] ?? []).contains(chosen) {
                byTitle[key, default: []].append(chosen)
            }
        }

        var out: [CatalogEntry] = []
        out.reserveCapacity(groups.count)
        for members in groups {
            out.append(combine(members.map { entries[$0] }))
        }
        return out
    }

    private static func yearsCompatible(
        _ entries: [CatalogEntry],
        _ members: [Int],
        _ candidate: CatalogEntry
    ) -> Bool {
        guard let year = candidate.year else { return true }
        for position in members {
            guard let other = entries[position].year else { continue }
            if abs(other - year) > 1 { return false }
        }
        return true
    }

    /// Zwei oder mehr Fassungen desselben Titels zu einem Eintrag verbinden.
    ///
    /// Die **führende** Quelle ist die mit der vollständigeren Auskunft: sie
    /// bestimmt, wohin ein Tipp führt, und liefert Titel und Medientyp. Bei
    /// Gleichstand entscheidet die Kennung, damit die Reihenfolge über
    /// Programmläufe hinweg dieselbe bleibt.
    private static func combine(_ group: [CatalogEntry]) -> CatalogEntry {
        guard group.count > 1 else { return group[0] }
        let ranked = group.sorted { lhs, rhs in
            let left = completeness(lhs)
            let right = completeness(rhs)
            if left != right { return left > right }
            return lhs.id < rhs.id
        }

        var winner = ranked[0]
        winner.alternates = Array(ranked.dropFirst().map(\.primary))

        for other in ranked.dropFirst() {
            if winner.year == nil { winner.year = other.year }
            if winner.originalTitle == nil { winner.originalTitle = other.originalTitle }
            for genre in other.genres where !winner.genres.contains(genre) {
                winner.genres.append(genre)
            }
            for name in other.alternativeTitles
            where !winner.alternativeTitles.contains(name) && name != winner.title {
                winner.alternativeTitles.append(name)
            }
            for language in other.languages where !winner.languages.contains(language) {
                winner.languages.append(language)
            }
            winner.hasFreshEpisode = winner.hasFreshEpisode || other.hasFreshEpisode
            // Ein belegter Status schlägt „unbekannt", und „läuft" schlägt
            // „abgeschlossen": Wenn eine der beiden Seiten noch Folgen
            // nachliefert, ist der Titel für Nori nicht abgeschlossen.
            if winner.status == .unknown || (other.status == .running && winner.status == .completed) {
                winner.status = other.status
            }
            winner.signals = richer(winner.signals, other.signals)
        }

        for other in ranked.dropFirst() {
            for key in other.mergeKeys where !winner.mergeKeys.contains(key) {
                winner.mergeKeys.append(key)
            }
        }
        winner.languages.sort { $0.order < $1.order }
        winner.alternativeTitles = Array(winner.alternativeTitles.prefix(12))
        winner.searchKey = CatalogSearch.key(
            title: winner.title,
            originalTitle: winner.originalTitle,
            alternates: winner.alternativeTitles,
            genres: winner.genres,
            year: winner.year
        )
        return winner
    }

    /// Wie viel über einen Eintrag bekannt ist. Entscheidet, welche Quelle
    /// die führende wird.
    private static func completeness(_ entry: CatalogEntry) -> Int {
        var score = 0
        if entry.tmdbID != nil { score += 4 }
        if entry.signals.trendingRank != nil { score += 2 }
        if (entry.signals.voteCount ?? 0) > 0 { score += 2 }
        if entry.year != nil { score += 1 }
        if !entry.genres.isEmpty { score += 1 }
        return score
    }

    private static func richer(_ lhs: TMDBSignals, _ rhs: TMDBSignals) -> TMDBSignals {
        var out = lhs
        out.tmdbID = out.tmdbID ?? rhs.tmdbID
        out.popularity = max(out.popularity ?? 0, rhs.popularity ?? 0)
        if (rhs.voteCount ?? 0) > (out.voteCount ?? 0) {
            out.voteCount = rhs.voteCount
            out.voteAverage = rhs.voteAverage
        }
        out.firstAirDate = out.firstAirDate ?? rhs.firstAirDate
        if let other = rhs.lastAirDate {
            out.lastAirDate = max(out.lastAirDate ?? .distantPast, other)
        }
        if out.trendingRank == nil { out.trendingRank = rhs.trendingRank }
        if out.genreIDs.isEmpty { out.genreIDs = rhs.genreIDs }
        out.hasBackdrop = out.hasBackdrop || rhs.hasBackdrop
        return out
    }
}
