import Foundation

actor AniworldClient {
    static let shared = AniworldClient()

    private var catalogs: [CatalogProvider: (CatalogResult, Date)] = [:]
    private var seriesCache: [String: (SeriesDetail, Date)] = [:]
    private var calendars: [CatalogProvider: (CalendarPayload, Date)] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    func getCatalog(provider: CatalogProvider, force: Bool = false) async throws -> CatalogResult {
        if !force, let hit = catalogs[provider], hit.1 > Date() { return hit.0 }
        let html = try await fetchPage(provider.catalogPath, provider: provider)
        let items = provider == .serienstream
            ? try HTML.parseCatalogSerienstream(html)
            : try HTML.parseCatalog(html)
        // Anzahl mitgeben: 0 heißt blockiert oder Markup geändert, eine kleine
        // Zahl heißt, dass der Parser nur noch teilweise greift. Ohne die Zahl
        // war beides dieselbe Meldung.
        guard items.count >= 20 else {
            throw NoriError.parse("\(provider.label): Katalog unvollständig, nur \(items.count) Einträge gelesen")
        }
        let result = CatalogResult(items: items, source: "live", fetchedAt: Date().timeIntervalSince1970 * 1000)
        catalogs[provider] = (result, Date().addingTimeInterval(30 * 60))
        return result
    }

    func getSeries(provider: CatalogProvider, slug: String, season: String? = nil) async throws -> SeriesDetail {
        let key = "\(provider.rawValue)::\(slug)::\(season ?? "default")"
        if let hit = seriesCache[key], hit.1 > Date() { return hit.0 }
        let path = provider.seriesPath(slug: slug, season: season)
        let html = try await fetchPage(path, provider: provider)
        let hasSeries = html.contains("series-title")
            || html.contains("seasonEpisodesList")
            || html.contains("episode-row")
            || html.contains("seriesCoverBox")
        if !hasSeries { throw NoriError.notFound("Serie nicht gefunden") }
        let detail = provider == .serienstream
            ? try HTML.parseSeriesSerienstream(html, slug: slug, requestedSeason: season)
            : try HTML.parseSeries(html, slug: slug, requestedSeason: season)
        if detail.title.lowercased() == "alle animes" || detail.title.lowercased() == "alle serien" {
            throw NoriError.notFound("Serie nicht gefunden")
        }
        seriesCache[key] = (detail, Date().addingTimeInterval(10 * 60))
        return detail
    }

    func getWatch(provider: CatalogProvider, path: String) async throws -> WatchInfo {
        let clean = HTML.toAniworldPath(path)
        let ok = provider == .serienstream ? clean.hasPrefix("/serie/") : clean.hasPrefix("/anime/stream/")
        guard ok else { throw NoriError.parse("Ungültiger Pfad") }
        let html = try await fetchPage(clean, provider: provider)
        let info = provider == .serienstream
            ? try HTML.parseWatchSerienstream(html, path: clean)
            : try HTML.parseWatch(html, path: clean)
        if info.hosters.isEmpty { throw NoriError.parse("Keine Hoster gefunden") }
        return info
    }

    func getCalendar(provider: CatalogProvider, force: Bool = false) async throws -> CalendarPayload {
        if !force, let hit = calendars[provider], hit.1 > Date() { return hit.0 }
        let payload: CalendarPayload
        if provider == .serienstream {
            let data = try await fetchData(provider.calendarPath, provider: provider, accept: "application/json")
            payload = try HTML.parseSerienstreamCalendar(data)
        } else {
            let html = try await fetchPage(provider.calendarPath, provider: provider)
            payload = try HTML.parseAniworldCalendar(html)
        }
        if payload.upcoming.count + payload.recent.count < 3 {
            throw NoriError.parse("Kalender unvollständig")
        }
        calendars[provider] = (payload, Date().addingTimeInterval(20 * 60))
        return payload
    }

    func fetchPage(_ path: String, provider: CatalogProvider) async throws -> String {
        let data = try await fetchData(path, provider: provider, accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        if looksBlocked(html) { throw NoriError.blocked("\(provider.label) nicht erreichbar") }
        return html
    }

    func fetchData(_ path: String, provider: CatalogProvider, accept: String) async throws -> Data {
        let url = path.hasPrefix("http") ? URL(string: path)! : URL(string: provider.origin + path)!
        var req = URLRequest(url: url)
        req.setValue(NoriOrigin.ua, forHTTPHeaderField: "User-Agent")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("de-DE,de;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NoriError.network("HTTP \(http.statusCode)")
        }
        return data
    }

    func fetchExternal(_ url: URL, referer: String?) async throws -> String {
        var req = URLRequest(url: url)
        req.setValue(NoriOrigin.ua, forHTTPHeaderField: "User-Agent")
        req.setValue(referer ?? "https://voe.sx/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NoriError.network("HTTP \(http.statusCode)")
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    static func coverURL(_ path: String?, provider: CatalogProvider) -> URL? {
        guard let path else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        guard path.hasPrefix("/") else { return URL(string: path) }
        var raw = provider.origin + path
        if provider == .serienstream, !raw.contains("format=") {
            raw += raw.contains("?") ? "&format=jpg" : "?format=jpg"
        }
        return URL(string: raw)
    }

    private func looksBlocked(_ html: String) -> Bool {
        let head = html.prefix(800).lowercased()
        return html.count < 800
            || head.contains("ddos-guard")
            || head.contains("just a moment")
            || head.contains("cf-turnstile")
    }
}

enum NoriError: LocalizedError {
    case network(String)
    case parse(String)
    case blocked(String)
    case notFound(String)
    case hoster(String)

    var errorDescription: String? {
        switch self {
        case .network(let m), .parse(let m), .blocked(let m), .notFound(let m), .hoster(let m):
            return m
        }
    }
}

actor CoverIndex {
    static let shared = CoverIndex()
    private var cache: [String: URL] = [:]
    private var missed: Set<String> = []
    private var sourceCovers: [String: URL] = [:]
    private var overrides: [String: URL] = [:]
    /// Breitbild aus demselben TMDB-Treffer. Trägt den Hero-Bereich der
    /// Startseite, für den ein 2:3-Poster die falsche Form hat.
    private var backdrops: [String: URL] = [:]
    private let key = "8265bd1679663a7ea12ac168da84d2e8"

    // Der Cover-Index lag bisher nur im Arbeitsspeicher: nach jedem Start
    // musste jede Kachel erneut bei TMDB nachfragen, weshalb Listen lange
    // ohne Bild blieben. Jetzt landet er auf der Platte und ist beim nächsten
    // Start sofort da.
    private let storeURL: URL
    private var saveTask: Task<Void, Never>?
    private static let maxEntries = 4000
    /// Erhöhen, wenn sich die automatische Zuordnung ändert — verwirft die
    /// gecachten TMDB-Treffer, ohne manuelle Auswahl anzutasten.
    private static let storeVersion = 2

    /// Laufende Anfragen je Slug. Dieselbe Serie steht oft gleichzeitig in
    /// Startseite, Katalog und Kalender; ohne das ginge pro Kachel eine eigene
    /// TMDB-Anfrage raus.
    private var inFlight: [String: Task<URL?, Never>] = [:]
    private var activeLookups = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private static let maxConcurrentLookups = 4

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("Nori", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appendingPathComponent("covers.json")

        if let data = try? Data(contentsOf: storeURL),
           let bag = try? JSONDecoder().decode(Bag.self, from: data) {
            sourceCovers = (bag.sourceCovers ?? [:]).compactMapValues(URL.init(string:))
            overrides = (bag.overrides ?? [:]).compactMapValues(URL.init(string:))
            // Die automatischen TMDB-Treffer aus älteren Ständen entstanden mit
            // einer Bewertung, die Beliebtheit als Treffer zählte, und sind
            // deshalb teilweise falsch. Sie werden verworfen und neu gesucht;
            // manuelle Auswahl und Quellcover bleiben erhalten.
            if (bag.version ?? 1) >= Self.storeVersion {
                cache = bag.covers.compactMapValues(URL.init(string:))
                missed = Set(bag.missed)
                backdrops = (bag.backdrops ?? [:]).compactMapValues(URL.init(string:))
            }
        }
    }

    /// Reihenfolge: manuelle Auswahl, dann TMDB, dann das Cover der Quelle.
    /// TMDB liefert die besseren Bilder, trifft aber nicht immer den richtigen
    /// Titel — deshalb die Möglichkeit, von Hand zu überschreiben.
    func url(for slug: String) -> URL? {
        overrides[slug] ?? cache[slug] ?? sourceCovers[slug]
    }

    func override(for slug: String) -> URL? { overrides[slug] }

    func setOverride(slug: String, url: URL?) {
        if let url {
            overrides[slug] = url
        } else {
            overrides.removeValue(forKey: slug)
        }
        scheduleSave()
    }

    /// Cover, das AniWorld beziehungsweise Serienstream selbst zur Serie
    /// ausliefert. Es ist immer das richtige und dient als Rückfallebene, wenn
    /// TMDB nichts findet.
    func rememberSource(slug: String, url: URL) {
        guard sourceCovers[slug] != url else { return }
        sourceCovers[slug] = url
        scheduleSave()
    }

    func sourceCover(for slug: String) -> URL? { sourceCovers[slug] }

    func backdrop(for slug: String) -> URL? { backdrops[slug] }

    private struct Bag: Codable {
        var covers: [String: String]
        var missed: [String]
        // Ab Cover-Index v2. Optional, damit ältere covers.json weiter lesbar bleibt.
        var sourceCovers: [String: String]?
        var overrides: [String: String]?
        var backdrops: [String: String]?
        var version: Int?
    }

    /// Sammelt Änderungen und schreibt sie gebündelt, damit ein Scroll durch
    /// den Katalog nicht pro Kachel eine Datei schreibt.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.persist()
        }
    }

    private func persist() {
        var covers = cache
        var misses = missed
        if covers.count > Self.maxEntries {
            covers = Dictionary(uniqueKeysWithValues: covers.prefix(Self.maxEntries).map { ($0.key, $0.value) })
        }
        if misses.count > Self.maxEntries {
            misses = Set(misses.prefix(Self.maxEntries))
        }
        let bag = Bag(
            covers: covers.mapValues(\.absoluteString),
            missed: Array(misses),
            sourceCovers: sourceCovers.mapValues(\.absoluteString),
            // Manuelle Auswahl nie deckeln — die hat der Nutzer selbst getroffen.
            overrides: overrides.mapValues(\.absoluteString),
            backdrops: backdrops.mapValues(\.absoluteString),
            version: Self.storeVersion
        )
        guard let data = try? JSONEncoder().encode(bag) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    func lookup(slug: String, title: String, kind: CatalogProvider) async -> URL? {
        if let chosen = overrides[slug] { return chosen }
        if let hit = cache[slug] { return hit }
        // Bekannter Fehlschlag: nicht erneut anfragen, aber das Cover der Quelle
        // anbieten, statt die Kachel leer zu lassen.
        if missed.contains(slug) { return sourceCovers[slug] }

        if let running = inFlight[slug] { return await running.value }
        let task = Task<URL?, Never> {
            await self.search(slug: slug, title: title, kind: kind)
        }
        inFlight[slug] = task
        let result = await task.value
        inFlight.removeValue(forKey: slug)
        return result
    }

    /// Begrenzt, wie viele TMDB-Anfragen gleichzeitig laufen. Ein Raster mit
    /// sechzig Kacheln würde sonst sechzig Anfragen auf einmal auslösen und
    /// dabei in die Ratenbegrenzung laufen — Kacheln blieben dann leer.
    private func acquireSlot() async {
        if activeLookups < Self.maxConcurrentLookups {
            activeLookups += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiting.append(continuation)
        }
        activeLookups += 1
    }

    private func releaseSlot() {
        activeLookups -= 1
        if !waiting.isEmpty {
            let next = waiting.removeFirst()
            next.resume()
        }
    }

    private func search(slug: String, title: String, kind: CatalogProvider) async -> URL? {
        await acquireSlot()
        defer { releaseSlot() }
        let cleaned = title
            .replacingOccurrences(of: #"\s*\(\d{4}\)\s*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let q = cleaned.count >= 2 ? cleaned : title
        guard var comps = URLComponents(string: "https://api.themoviedb.org/3/search/tv") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "language", value: "de-DE"),
            URLQueryItem(name: "query", value: q),
            URLQueryItem(name: "include_adult", value: "false"),
        ]
        guard let url = comps.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = json["results"] as? [[String: Any]]
            else { return nil }
            var best: (score: Double, path: String, titleBonus: Double, backdrop: String?)?
            let nq = q.lowercased()
            for row in results {
                guard let path = row["poster_path"] as? String, !path.isEmpty else { continue }
                let name = (row["name"] as? String ?? "").lowercased()
                let orig = (row["original_name"] as? String ?? "").lowercased()
                // Beliebtheit ist nur Stichentscheid, kein Treffer. Vorher ging
                // sie voll in die Wertung ein, weshalb eine bekannte, völlig
                // andere Serie die 45-Punkte-Schwelle allein durch Popularität
                // riss — genau so entstanden die falschen Cover.
                var titleBonus: Double = 0
                if name == nq || orig == nq { titleBonus = 400 }
                else if name.hasPrefix(nq) || orig.hasPrefix(nq) { titleBonus = 180 }
                else if name.contains(nq) || orig.contains(nq) { titleBonus = 80 }
                else if nq.contains(name) && name.count >= 4 { titleBonus = 60 }
                var score = titleBonus + min(row["popularity"] as? Double ?? 0, 40)
                let genres = row["genre_ids"] as? [Int] ?? []
                let countries = row["origin_country"] as? [String] ?? []
                if kind == .aniworld {
                    if genres.contains(16) { score += 120 }
                    if countries.contains("JP") { score += 60 }
                } else {
                    if genres.contains(16) && countries.contains("JP") { score -= 90 }
                    else if countries.contains("JP") { score -= 20 }
                    if countries.contains("US") || countries.contains("GB") || countries.contains("DE") { score += 40 }
                }
                if best == nil || score > best!.score {
                    best = (score, path, titleBonus, row["backdrop_path"] as? String)
                }
            }
            // Ohne echte Titelübereinstimmung lieber kein Cover als ein
            // falsches — dann greift das Cover der Quelle.
            if let best, best.titleBonus >= 80,
               let poster = URL(string: "https://image.tmdb.org/t/p/w780\(best.path)") {
                cache[slug] = poster
                if let backdropPath = best.backdrop, !backdropPath.isEmpty,
                   let wide = URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)") {
                    backdrops[slug] = wide
                }
                scheduleSave()
                return poster
            }
            missed.insert(slug)
            scheduleSave()
        } catch {
            return sourceCovers[slug]
        }
        return sourceCovers[slug]
    }

    /// Auswahlvorschläge für die manuelle Cover-Zuordnung: die Treffer aus
    /// TMDB in Rangfolge. Ohne Cache und ohne `missed`-Sperre, weil hier
    /// bewusst nach einer Alternative gesucht wird.
    func candidates(title: String, kind: CatalogProvider, limit: Int = 12) async -> [CoverCandidate] {
        let cleaned = title
            .replacingOccurrences(of: #"\s*\(\d{4}\)\s*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let q = cleaned.count >= 2 ? cleaned : title
        guard var comps = URLComponents(string: "https://api.themoviedb.org/3/search/tv") else { return [] }
        comps.queryItems = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "language", value: "de-DE"),
            URLQueryItem(name: "query", value: q),
            URLQueryItem(name: "include_adult", value: "false"),
        ]
        guard let url = comps.url else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = json["results"] as? [[String: Any]]
            else { return [] }
            var out: [CoverCandidate] = []
            for row in results {
                guard let path = row["poster_path"] as? String, !path.isEmpty,
                      let poster = URL(string: "https://image.tmdb.org/t/p/w780\(path)")
                else { continue }
                let name = (row["name"] as? String) ?? (row["original_name"] as? String) ?? title
                let year = (row["first_air_date"] as? String)?.prefix(4)
                let label = year.map { "\(name) (\($0))" } ?? name
                out.append(CoverCandidate(url: poster, label: label, source: "TMDB"))
                if out.count >= limit { break }
            }
            return out
        } catch {
            return []
        }
    }
}

struct CoverCandidate: Identifiable, Hashable {
    let url: URL
    let label: String
    let source: String
    var id: URL { url }
}