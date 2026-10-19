import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// TMDBs Listen — Trend, Beliebtheit, kürzlich Ausgestrahltes, Empfehlungen.
///
/// ## Warum das nicht `CoverIndex` ist
///
/// `CoverIndex` beantwortet eine Frage pro Titel („welches Bild gehört zu
/// diesem Slug") und wächst mit dem Katalog. Hier geht es um das Gegenteil:
/// wenige Abrufe, die je hundert Zeilen mit vollständigen Angaben liefern.
/// Getrennt gehalten, weil `covers.json` bei jedem Scrollen durch den Katalog
/// geschrieben wird — die Listen hätten darin nur mitgewachsen.
///
/// ## Warum Listen und nicht Einzelabfragen
///
/// Die naheliegende Umsetzung von „Neu & beliebt" wäre: für jeden der
/// tausenden Nori-Titel `/tv/{id}` holen und nach Beliebtheit sortieren. Das
/// sind tausende Anfragen für eine Reihe mit zwanzig Kacheln, und die
/// Ratenbegrenzung von TMDB wäre nach Sekunden erreicht.
///
/// Stattdessen liefert TMDB seine Ranglisten in Seiten zu zwanzig Zeilen,
/// und **jede Zeile trägt schon alles**, was die Bewertung braucht:
/// `popularity`, `vote_average`, `vote_count`, `first_air_date`, `genre_ids`,
/// `backdrop_path`. Sechs Abrufe ergeben rund 120 bewertbare Titel. Die
/// Schnittmenge mit Noris Katalog bildet danach `HomeCatalogIndex` — und weil
/// diese Schnittmenge aus Nori-Titeln besteht, kann nichts auf der Startseite
/// landen, das Nori nicht abspielen kann.
///
/// ## Ausfall
///
/// Jeder Weg hier endet im Zweifel mit einer leeren Liste, nie mit einem
/// Fehler nach außen. Ohne Schlüssel, ohne Netz, bei Ratenbegrenzung oder bei
/// unerwarteten Daten bleiben die Signale leer; die Startseite zeigt dann die
/// Nori-Daten allein. Das ist der Normalbetrieb im Flugmodus, kein Sonderfall.
actor TMDBCatalog {
    static let shared = TMDBCatalog()

    /// Was ein Abruf liefert: Zeilen in der Reihenfolge, die TMDB vorgibt.
    struct Rows: Codable, Hashable {
        var candidates: [TMDBCandidate] = []
        var fetchedAt: Double = 0
    }

    /// Welche Liste. Der Rohwert ist zugleich der Schlüssel im Cache.
    enum Feed: String, CaseIterable, Codable {
        /// Was diese Woche gesucht wird. Das aktuellste Signal, das TMDB hat.
        case trendingWeek
        /// Dauerhaft beliebte Serien. Fängt die großen Titel, die gerade
        /// keinen Ausschlag haben.
        case popular
        /// Zeichentrick aus Japan, nach Beliebtheit — ohne das bestünden die
        /// Listen fast nur aus westlichen Realserien, und AniWorld ist die
        /// größere der beiden Quellen.
        case animePopular
        /// Serien mit Folgen aus den letzten Wochen. Die eigentliche Quelle
        /// für den „neu"-Anteil.
        case airingRecently
        /// Anime mit Folgen aus den letzten Wochen.
        case animeAiringRecently
        /// Serien, die TMDB als abgeschlossen oder abgesetzt führt. Die
        /// einzige Liste, aus der sich „abgeschlossen" überhaupt belegen
        /// lässt, ohne pro Titel eine Detailseite zu holen — die Zeilen der
        /// Ranglisten führen `status` nicht mit.
        case endedPopular
        /// Dasselbe für Anime.
        case endedAnime

        /// Wie lange die Liste gilt.
        ///
        /// Der Trend wechselt täglich, die Dauerliste kaum. Kürzere Fristen
        /// brächten nichts außer Anfragen: TMDB rechnet den Trend selbst nur
        /// einmal am Tag neu.
        var maxAge: TimeInterval {
            switch self {
            case .trendingWeek: return 6 * 3600
            case .airingRecently, .animeAiringRecently: return 12 * 3600
            case .popular, .animePopular: return 3 * 86_400
            // Ein abgeschlossener Titel wird nicht wieder unabgeschlossen.
            // Eine Woche ist hier eher zu kurz als zu lang.
            case .endedPopular, .endedAnime: return 7 * 86_400
            }
        }

        /// Wie viele Seiten zu je zwanzig Zeilen.
        var pages: Int {
            switch self {
            case .trendingWeek: return 2
            case .popular, .animePopular: return 2
            case .airingRecently, .animeAiringRecently: return 2
            // Mehr Seiten als bei den übrigen Listen: Diese hier ist die
            // einzige Quelle für den Statusfilter, und jede Seite, die
            // fehlt, ist ein Titel, dessen Status „unbekannt" bleibt.
            case .endedPopular, .endedAnime: return 3
            }
        }
    }

    /// Empfehlungen zu einem Titel. Eigene Frist: die ändern sich kaum.
    private static let recommendationMaxAge: TimeInterval = 7 * 86_400

    private var feeds: [String: Rows] = [:]
    private var recommendations: [Int: Rows] = [:]
    private var inFlight: [String: Task<Rows, Never>] = [:]

    private let storeURL: URL
    private var saveTask: Task<Void, Never>?
    /// Erhöhen, wenn sich Auswahl oder Felder der Listen ändern.
    private static let storeVersion = 1

    private var key: String? { TMDBKeyStore.current }
    nonisolated var hasKey: Bool { TMDBKeyStore.current != nil }

    init(directory: URL? = nil) {
        let folder = directory ?? NoriStorage.directory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appendingPathComponent("tmdb-lists.json")

        if let data = try? Data(contentsOf: storeURL),
           let bag = try? JSONDecoder().decode(Bag.self, from: data),
           (bag.version ?? 0) >= Self.storeVersion {
            feeds = bag.feeds
            recommendations = bag.recommendations
        }
    }

    // MARK: - Lesen ohne Netz

    /// Was schon dasteht. Für den ersten Aufbau der Startseite: sie erscheint
    /// mit dem Stand von vorhin, statt auf TMDB zu warten.
    func cached(_ feed: Feed) -> [TMDBCandidate] {
        feeds[feed.rawValue]?.candidates ?? []
    }

    func cachedRecommendations(for id: Int) -> [TMDBCandidate] {
        recommendations[id]?.candidates ?? []
    }

    /// Alle abgelegten Listen auf einmal, ohne einen einzigen Abruf.
    ///
    /// Damit steht die Startseite beim Öffnen sofort — mit dem Stand von
    /// vorhin statt mit einem Ladebalken. Der frische Stand kommt danach über
    /// `signals(now:force:)` nach und ersetzt sie.
    func cachedSignals() -> (trending: [TMDBCandidate], others: [TMDBCandidate], airing: [TMDBCandidate]) {
        (
            cached(.trendingWeek),
            cached(.popular) + cached(.animePopular),
            cached(.airingRecently) + cached(.animeAiringRecently)
        )
    }

    /// Die abgelegten Listen abgeschlossener Serien, ohne einen Abruf.
    ///
    /// Getrennt von `cachedSignals`, weil nur der Katalog sie braucht: die
    /// Startseite fragt nicht nach dem Status, und eine Liste, die niemand
    /// liest, soll auch niemand holen.
    func cachedEnded() -> [TMDBCandidate] {
        cached(.endedPopular) + cached(.endedAnime)
    }

    /// Dieselben Listen, notfalls frisch geholt.
    func ended(now: Date = Date(), force: Bool = false) async -> [TMDBCandidate] {
        async let general = load(.endedPopular, now: now, force: force)
        async let anime = load(.endedAnime, now: now, force: force)
        return await general + anime
    }

    /// Sind die abgelegten Listen noch frisch genug?
    func isFresh(_ feed: Feed, now: Date = Date()) -> Bool {
        guard let rows = feeds[feed.rawValue] else { return false }
        return now.timeIntervalSince1970 - rows.fetchedAt < feed.maxAge
    }

    // MARK: - Holen

    /// Eine Liste, notfalls frisch geholt.
    ///
    /// Gleichzeitige Aufrufe für dieselbe Liste teilen sich einen Abruf — die
    /// Startseite fragt beim Aufbau mehrere Reihen zugleich, und jede davon
    /// braucht dieselben Zeilen.
    func load(_ feed: Feed, now: Date = Date(), force: Bool = false) async -> [TMDBCandidate] {
        if !force, isFresh(feed, now: now) { return cached(feed) }
        guard hasKey else { return cached(feed) }

        if let running = inFlight[feed.rawValue] { return await running.value.candidates }
        let task = Task<Rows, Never> { [feed] in
            await self.fetch(feed)
        }
        inFlight[feed.rawValue] = task
        let rows = await task.value
        inFlight.removeValue(forKey: feed.rawValue)

        // Ein leerer Abruf überschreibt einen brauchbaren Stand nicht. Ohne
        // das leerte ein einzelner Netzfehler die halbe Startseite.
        guard !rows.candidates.isEmpty else { return cached(feed) }
        feeds[feed.rawValue] = rows
        scheduleSave()
        return rows.candidates
    }

    /// Alle Listen auf einmal — was die Startseite zum Ranken braucht.
    ///
    /// Gibt drei Bündel getrennt zurück, weil sie Unterschiedliches bedeuten:
    /// In der Trendliste ist die **Reihenfolge** das Signal (Platz 3 sagt
    /// etwas, Platz 3 in „beliebt" kaum), in den `airing`-Listen die bloße
    /// **Zugehörigkeit** (wer darin steht, hat kürzlich gesendet).
    func signals(
        now: Date = Date(),
        force: Bool = false
    ) async -> (trending: [TMDBCandidate], others: [TMDBCandidate], airing: [TMDBCandidate]) {
        async let trending = load(.trendingWeek, now: now, force: force)
        async let popular = load(.popular, now: now, force: force)
        async let anime = load(.animePopular, now: now, force: force)
        async let airing = load(.airingRecently, now: now, force: force)
        async let animeAiring = load(.animeAiringRecently, now: now, force: force)
        let others = await popular + anime
        let recent = await airing + animeAiring
        return (await trending, others, recent)
    }

    /// Was TMDB zu einem Titel als verwandt nennt.
    ///
    /// `/recommendations` und `/similar` beantworten unterschiedliche Fragen:
    /// das eine „was haben Leute außerdem gesehen", das andere „was ähnelt
    /// sich inhaltlich". Beides zusammen ist breiter als eines allein, und
    /// die Zeilen tragen dieselben Felder wie die Ranglisten.
    func related(to id: Int, now: Date = Date()) async -> [TMDBCandidate] {
        if let rows = recommendations[id],
           now.timeIntervalSince1970 - rows.fetchedAt < Self.recommendationMaxAge {
            return rows.candidates
        }
        guard hasKey else { return recommendations[id]?.candidates ?? [] }

        let cacheKey = "rec:\(id)"
        if let running = inFlight[cacheKey] { return await running.value.candidates }
        let task = Task<Rows, Never> { [id] in
            async let recommended = self.page("tv/\(id)/recommendations", extra: [], page: 1)
            async let similar = self.page("tv/\(id)/similar", extra: [], page: 1)
            var seen: Set<Int> = []
            let merged = (await recommended + similar).filter { seen.insert($0.id).inserted }
            return Rows(candidates: merged, fetchedAt: Date().timeIntervalSince1970)
        }
        inFlight[cacheKey] = task
        let rows = await task.value
        inFlight.removeValue(forKey: cacheKey)

        guard !rows.candidates.isEmpty else { return recommendations[id]?.candidates ?? [] }
        recommendations[id] = rows
        trimRecommendations()
        scheduleSave()
        return rows.candidates
    }

    // MARK: - Abruf

    private func fetch(_ feed: Feed) async -> Rows {
        var out: [TMDBCandidate] = []
        var seen: Set<Int> = []
        for page in 1 ... feed.pages {
            let rows = await self.page(feed.path, extra: feed.query(now: Date()), page: page)
            if rows.isEmpty { break }
            for row in rows where seen.insert(row.id).inserted {
                out.append(row)
            }
        }
        return Rows(candidates: out, fetchedAt: Date().timeIntervalSince1970)
    }

    /// Eigene Sitzung mit kurzer Frist.
    ///
    /// `URLSession.shared` wartet bis zu 60 Sekunden auf eine Antwort. Hängt
    /// TMDB, blieb der zweite Durchgang der Startseite so lange offen — je
    /// Seite einer Liste. TMDB ist eine Verbesserung, kein Grund zu warten.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        #if DEBUG
        NoriNetworkSimulation.configure(config)
        #endif
        return URLSession(configuration: config)
    }()

    private func page(_ path: String, extra: [URLQueryItem], page: Int) async -> [TMDBCandidate] {
        guard let key else { return [] }
        guard var comps = URLComponents(string: "https://api.themoviedb.org/3/" + path) else { return [] }
        comps.queryItems = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "language", value: "de-DE"),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "page", value: String(page)),
        ] + extra
        guard let url = comps.url else { return [] }
        do {
            let (data, response) = try await Self.session.data(from: url)
            // 429 ist die Ratenbegrenzung, 401 ein ungültiger Schlüssel.
            // Beides ist ein leeres Ergebnis, kein Grund, etwas zu verwerfen.
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return [] }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let rows = json["results"] as? [[String: Any]]
            else { return [] }
            return rows.compactMap(TMDBCandidate.init(json:))
        } catch {
            return []
        }
    }

    // MARK: - Ablage

    private struct Bag: Codable {
        var feeds: [String: Rows]
        var recommendations: [Int: Rows]
        var version: Int?
    }

    /// Empfehlungen wachsen mit jedem Seed-Titel. Ein Deckel reicht; bei
    /// Überlauf fliegt das Älteste.
    private func trimRecommendations() {
        guard recommendations.count > 60 else { return }
        let keep = recommendations
            .sorted { $0.value.fetchedAt > $1.value.fetchedAt }
            .prefix(40)
        recommendations = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.persist()
        }
    }

    private func persist() {
        let bag = Bag(feeds: feeds, recommendations: recommendations, version: Self.storeVersion)
        guard let data = try? JSONEncoder().encode(bag) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

private extension TMDBCatalog.Feed {
    var path: String {
        switch self {
        case .trendingWeek: return "trending/tv/week"
        case .popular: return "tv/popular"
        case .animePopular, .airingRecently, .animeAiringRecently: return "discover/tv"
        case .endedPopular, .endedAnime: return "discover/tv"
        }
    }

    /// Die zusätzlichen Parameter der Liste.
    ///
    /// `with_genres=16` ist bei TMDB „Animation", `with_origin_country=JP`
    /// grenzt es auf japanische Produktionen ein — zusammen ist das die
    /// brauchbarste Näherung an „Anime", die die Schnittstelle hergibt. Eine
    /// eigene Anime-Kennung gibt es dort nicht.
    func query(now: Date) -> [URLQueryItem] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        let from = formatter.string(from: now.addingTimeInterval(-45 * 86_400))
        let to = formatter.string(from: now)

        switch self {
        case .trendingWeek, .popular:
            return []
        case .animePopular:
            return [
                URLQueryItem(name: "with_genres", value: "16"),
                URLQueryItem(name: "with_origin_country", value: "JP"),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
            ]
        case .airingRecently:
            return [
                URLQueryItem(name: "air_date.gte", value: from),
                URLQueryItem(name: "air_date.lte", value: to),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "vote_count.gte", value: "20"),
            ]
        case .animeAiringRecently:
            return [
                URLQueryItem(name: "with_genres", value: "16"),
                URLQueryItem(name: "with_origin_country", value: "JP"),
                URLQueryItem(name: "air_date.gte", value: from),
                URLQueryItem(name: "air_date.lte", value: to),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
            ]
        // `with_status` kennt 3 („Ended") und 4 („Canceled"); der senkrechte
        // Strich ist TMDBs Oder. Für Nori sind beide dasselbe: es kommt
        // nichts mehr nach.
        case .endedPopular:
            return [
                URLQueryItem(name: "with_status", value: "3|4"),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "vote_count.gte", value: "20"),
            ]
        case .endedAnime:
            return [
                URLQueryItem(name: "with_status", value: "3|4"),
                URLQueryItem(name: "with_genres", value: "16"),
                URLQueryItem(name: "with_origin_country", value: "JP"),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
            ]
        }
    }
}
