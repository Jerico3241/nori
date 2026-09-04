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
        guard items.count >= 20 else { throw NoriError.parse("Katalog unvollständig") }
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
    private let key = "8265bd1679663a7ea12ac168da84d2e8"

    func url(for slug: String) -> URL? { cache[slug] }

    func lookup(slug: String, title: String, kind: CatalogProvider) async -> URL? {
        if let hit = cache[slug] { return hit }
        if missed.contains(slug) { return nil }
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
            var best: (score: Double, path: String)?
            let nq = q.lowercased()
            for row in results {
                guard let path = row["poster_path"] as? String, !path.isEmpty else { continue }
                let name = (row["name"] as? String ?? "").lowercased()
                let orig = (row["original_name"] as? String ?? "").lowercased()
                var score = row["popularity"] as? Double ?? 0
                if name == nq || orig == nq { score += 400 }
                else if name.hasPrefix(nq) || orig.hasPrefix(nq) { score += 180 }
                else if name.contains(nq) || orig.contains(nq) { score += 80 }
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
                if best == nil || score > best!.score { best = (score, path) }
            }
            if let path = best?.path, (best?.score ?? 0) >= 45, let poster = URL(string: "https://image.tmdb.org/t/p/w780\(path)") {
                cache[slug] = poster
                return poster
            }
            missed.insert(slug)
        } catch {
            return nil
        }
        return nil
    }
}