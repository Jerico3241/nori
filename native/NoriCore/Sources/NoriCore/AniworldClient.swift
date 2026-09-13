import Foundation
// `URLSession` und alles, was daran hängt — `URLRequest`, `HTTPURLResponse`,
// `HTTPCookieStorage` —, liegt außerhalb von Apple in einem eigenen Modul.
// Auf Apple ist dieser Import wirkungslos: dort gibt es FoundationNetworking
// nicht, und `canImport` ist schlicht falsch. Ohne ihn scheitert der
// Android-Durchbau an dutzenden Fehlern, die alle dasselbe sagen —
// „'URLSession' is unavailable: This type has moved to the
// FoundationNetworking module."
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
// Die beiden einzigen Darwin-Bindungen im geteilten Kern. Alles andere in
// dieser Datei ist Foundation und SwiftSoup und baut damit auch für Android
// durch — siehe docs/android.md. Ohne die Kapselung wäre schon der Import
// ein Übersetzungsfehler.
#if canImport(Security)
import Security
#endif
#if canImport(ImageIO)
import ImageIO
#endif

/// Zugang zum TMDB-Schlüssel.
///
/// Der Schlüssel stand früher als Zeichenkette in dieser Datei. Ein Schlüssel
/// im Quelltext liegt in jedem Klon, in jedem Build und in der Git-Historie;
/// wer ihn sperrt, sperrt ihn für alle Installationen zugleich. Er kommt jetzt
/// aus zwei Quellen, in dieser Reihenfolge:
///
/// 1. **Schlüsselbund** — was in den Einstellungen eingetragen wurde.
/// 2. **`TMDBAPIKey` aus der Info.plist** — für Builds, die den Schlüssel über
///    die Build-Einstellung `TMDB_API_KEY` mitbekommen (etwa aus einem
///    GitHub-Secret). Fehlt die Einstellung, bleibt der Eintrag leer.
///
/// Ohne Schlüssel fragt die App TMDB gar nicht erst — sie zeigt dann die Cover
/// von AniWorld und Serienstream, die sie ohnehin schon einliest.
enum TMDBKeyStore {
    private static let service = "de.nori.tmdb"
    private static let account = "api_key"

    /// Gepuffert, weil `current` aus View-Bodies gelesen wird: ohne Puffer
    /// ginge bei jedem Neuzeichnen eine Schlüsselbund-Abfrage raus.
    /// `nil` heißt „noch nicht gelesen", `.some(nil)` heißt „kein Schlüssel".
    private static var cached: String??

    /// Der zu verwendende Schlüssel oder `nil`, wenn keiner hinterlegt ist.
    static var current: String? {
        if let cached { return cached }
        let resolved = resolve()
        cached = .some(resolved)
        return resolved
    }

    /// Mitgelieferter Schlüssel, damit Cover und Beschreibungen ohne
    /// Einrichtung da sind.
    ///
    /// Das ist bewusst gegen die sonst hier geltende Regel „keine Schlüssel im
    /// Quelltext" entschieden — vom Betreiber, für eine private App in einem
    /// privaten Repository. Was das heißt, gehört trotzdem aufgeschrieben: der
    /// Schlüssel liegt damit in jedem Klon, in jedem Build und dauerhaft in
    /// der Git-Historie, und aus einer IPA lässt er sich herausziehen. Wird das
    /// Repository je öffentlich, ist er es auch.
    ///
    /// Der Schlüsselbund hat weiterhin Vorrang: wer einen eigenen Schlüssel
    /// einträgt, benutzt seinen eigenen.
    private static let builtIn = "30d39455d8ae27f049ab32c4b4bd608d"

    private static func resolve() -> String? {
        if let stored = readKeychain(), !stored.isEmpty { return stored }
        let bundled = Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String
        // Bei fehlender Build-Einstellung bleibt in der Info.plist der
        // unaufgelöste Platzhalter stehen — der ist kein Schlüssel.
        if let bundled, !bundled.isEmpty, !bundled.hasPrefix("$(") { return bundled }
        return builtIn
    }

    /// Wurde der Schlüssel von Hand eingetragen (und lässt sich damit löschen)?
    /// Nicht gepuffert: wird nur beim Aufbau der Einstellungen gelesen.
    static var isUserProvided: Bool {
        (readKeychain()?.isEmpty == false)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return clear() }
        defer { cached = nil }

        #if canImport(Security)
        guard let data = trimmed.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        #else
        // Android hat keinen Schlüsselbund dieser Art. Ein eigener Ablageort
        // gehört in die Android-App, nicht in den geteilten Kern — dort wäre
        // er auf Apple toter Code. Bis dahin trägt der eingebaute Schlüssel.
        return false
        #endif
    }

    @discardableResult
    static func clear() -> Bool {
        defer { cached = nil }
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
        #else
        return false
        #endif
    }

    private static func readKeychain() -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }
}

#if DEBUG
/// Netzstörungen zum Nachstellen — nur in Debug-Builds.
///
/// Gestartet mit `-NoriNetworkSimulation <modus>` (oder der Umgebungsvariable
/// `NORI_NETWORK_SIMULATION`) laufen alle Abrufe der App durch
/// `SimulatedNetworkProtocol`. So lässt sich ohne Eingriff in die
/// Systemeinstellungen prüfen, was die Oberfläche bei fehlendem Netz, einem
/// hängenden TMDB oder nur einer erreichbaren Quelle zeigt.
enum NoriNetworkSimulation: String, CaseIterable {
    /// Nichts ist erreichbar.
    case offline
    /// Alles kommt an, aber vier Sekunden später.
    case slow
    /// TMDB antwortet nicht, bis das Zeitlimit greift.
    case tmdbTimeout = "tmdb-timeout"
    /// AniWorld und Serienstream antworten nicht.
    case providerTimeout = "provider-timeout"
    /// Serienstream ist nicht erreichbar.
    case onlyAniworld = "only-aniworld"
    /// AniWorld ist nicht erreichbar.
    case onlySerienstream = "only-serienstream"
    /// Google ist nicht erreichbar — Anmeldung, Token und Drive.
    case driveOffline = "drive-offline"

    enum Effect: Equatable {
        case pass
        case fail(URLError.Code)
        case delay(TimeInterval)
        /// Nicht antworten und nach der Frist mit `timedOut` scheitern.
        case hang(TimeInterval)
    }

    static let active: NoriNetworkSimulation? = {
        let raw = ProcessInfo.processInfo.environment["NORI_NETWORK_SIMULATION"]
            ?? UserDefaults.standard.string(forKey: "NoriNetworkSimulation")
        return raw.flatMap(NoriNetworkSimulation.init(rawValue:))
    }()

    /// Für Tests: ein Modus ohne Startargument.
    nonisolated(unsafe) static var forced: NoriNetworkSimulation?

    static var current: NoriNetworkSimulation? { forced ?? active }

    /// Die Zwischenspeicher der simulierten Sitzungen.
    ///
    /// Übernimmt ein eigenes `URLProtocol` eine Anfrage, schlägt das System
    /// den Zwischenspeicher der Sitzung nicht mehr selbst nach. Ohne diese
    /// Liste zeigte „offline" deshalb leere Kacheln, obwohl die Cover auf der
    /// Platte liegen — strenger als ein echtes Gerät ohne Netz.
    ///
    /// Gemerkt wird auch die Richtlinie der Sitzung: `CoverImageLoader` setzt
    /// „Zwischenspeicher zuerst" an der Sitzung, die einzelne Anfrage trägt
    /// weiter `.useProtocolCachePolicy`. Nach der Anfrage allein gefragt, kam
    /// offline deshalb nie etwas aus dem Speicher.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var caches: [(cache: URLCache, policy: URLRequest.CachePolicy)] = []

    static func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        for entry in caches where allowsCache(entry.policy) || allowsCache(request.cachePolicy) {
            if let hit = entry.cache.cachedResponse(for: request) { return hit }
        }
        return allowsCache(request.cachePolicy) ? URLCache.shared.cachedResponse(for: request) : nil
    }

    static func allowsCache(_ policy: URLRequest.CachePolicy) -> Bool {
        policy == .returnCacheDataElseLoad || policy == .returnCacheDataDontLoad
    }

    /// Rein: was mit einer Anfrage an diesen Host geschieht.
    func effect(host: String) -> Effect {
        let host = host.lowercased()
        func matches(_ domains: [String]) -> Bool {
            domains.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        let tmdb = ["themoviedb.org", "tmdb.org"]
        let aniworld = ["aniworld.to"]
        let serienstream = ["serienstream.to", "s.to"]
        let google = ["googleapis.com", "google.com"]
        switch self {
        case .offline: return .fail(.notConnectedToInternet)
        case .slow: return .delay(4)
        case .tmdbTimeout: return matches(tmdb) ? .hang(12) : .pass
        case .providerTimeout: return matches(aniworld + serienstream) ? .hang(20) : .pass
        case .onlyAniworld: return matches(serienstream) ? .fail(.cannotConnectToHost) : .pass
        case .onlySerienstream: return matches(aniworld) ? .fail(.cannotConnectToHost) : .pass
        case .driveOffline: return matches(google) ? .fail(.notConnectedToInternet) : .pass
        }
    }

    /// Für `URLSession.shared` und alles, was darauf läuft.
    static func install() {
        guard current != nil else { return }
        URLProtocol.registerClass(SimulatedNetworkProtocol.self)
    }

    /// Für Sitzungen mit eigener Konfiguration — die sehen eine global
    /// registrierte Klasse nicht.
    static func configure(_ config: URLSessionConfiguration) {
        guard current != nil else { return }
        config.protocolClasses = [SimulatedNetworkProtocol.self] + (config.protocolClasses ?? [])
        if let cache = config.urlCache {
            cacheLock.lock()
            if !caches.contains(where: { $0.cache === cache }) {
                caches.append((cache, config.requestCachePolicy))
            }
            cacheLock.unlock()
        }
    }
}

final class SimulatedNetworkProtocol: URLProtocol, @unchecked Sendable {
    private static let passedKey = "nori.simulation.passed"
    /// Leitet durchgelassene Anfragen weiter — ohne diese Klasse, sonst liefe
    /// jede Anfrage endlos im Kreis.
    private static let forward = URLSession(configuration: .default)

    private var work: Task<Void, Never>?
    private var forwarding: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let mode = NoriNetworkSimulation.current, let host = request.url?.host,
              URLProtocol.property(forKey: passedKey, in: request) == nil
        else { return false }
        return mode.effect(host: host) != .pass
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let effect = NoriNetworkSimulation.current?.effect(host: request.url?.host ?? "") ?? .pass
        // Ohne Netz liefert ein echtes Gerät, was im Zwischenspeicher der
        // Sitzung liegt, sofern die Anfrage das erlaubt — die Cover etwa.
        // Die Simulation darf nicht strenger sein als die Wirklichkeit, sonst
        // zeigt sie leere Kacheln, die es ohne Netz gar nicht gäbe.
        let supplied = NoriNetworkSimulation.allowsCache(request.cachePolicy) ? cachedResponse : nil
        if effect != .pass, let cached = supplied ?? NoriNetworkSimulation.cachedResponse(for: request) {
            client?.urlProtocol(self, didReceive: cached.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: cached.data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        work = Task { [weak self] in
            switch effect {
            case .pass:
                self?.passThrough()
            case .fail(let code):
                self?.fail(code)
            case .delay(let seconds):
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.passThrough()
            case .hang(let seconds):
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.fail(.timedOut)
            }
        }
    }

    override func stopLoading() {
        work?.cancel()
        forwarding?.cancel()
    }


    private func fail(_ code: URLError.Code) {
        client?.urlProtocol(self, didFailWithError: URLError(code))
    }

    private func passThrough() {
        guard let marked = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            fail(.unknown)
            return
        }
        URLProtocol.setProperty(true, forKey: Self.passedKey, in: marked)
        forwarding = Self.forward.dataTask(with: marked as URLRequest) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            if let response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
            }
            if let data { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        forwarding?.resume()
    }
}
#endif

/// Der zuletzt vollständig geladene Katalog je Quelle, auf der Platte.
///
/// Vorher lag der Katalog nur im Arbeitsspeicher. Ohne Netz, bei einer
/// Schutzseite oder einem Zeitlimit stand nach einem Neustart deshalb gar
/// nichts da — Startseite, Katalog und Kategorien leer, obwohl der Stand von
/// gestern völlig genügt hätte. Jetzt dient die letzte gute Fassung als
/// Rückfall, wenn das Laden scheitert. Sie ist regenerierbar und liegt
/// deshalb unter Caches, nicht bei der Bibliothek.
struct CatalogDiskCache {
    let directory: URL?

    static let shared = CatalogDiskCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NoriCatalog", isDirectory: true)
    )

    /// Unter so vielen Einträgen gilt ein Katalog als unvollständig — dieselbe
    /// Schwelle wie beim Laden.
    static let minimumItems = 20

    private func file(for provider: CatalogProvider) -> URL? {
        directory?.appendingPathComponent("\(provider.rawValue).json")
    }

    func save(_ result: CatalogResult, provider: CatalogProvider) {
        guard let directory, let file = file(for: provider),
              result.items.count >= Self.minimumItems,
              let data = try? JSONEncoder().encode(result)
        else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// Die abgelegte Fassung, als `source: "cache"` gekennzeichnet — oder
    /// `nil`, wenn keine da ist oder die Datei nicht mehr lesbar ist.
    func load(provider: CatalogProvider) -> CatalogResult? {
        guard let file = file(for: provider),
              let data = try? Data(contentsOf: file),
              var result = try? JSONDecoder().decode(CatalogResult.self, from: data),
              result.items.count >= Self.minimumItems
        else { return nil }
        result.source = "cache"
        return result
    }
}

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
        #if DEBUG
        NoriNetworkSimulation.configure(config)
        #endif
        session = URLSession(configuration: config)
    }

    func getCatalog(provider: CatalogProvider, force: Bool = false) async throws -> CatalogResult {
        if !force, let hit = catalogs[provider], hit.1 > Date() { return hit.0 }
        do {
            let result = try await fetchCatalog(provider: provider)
            catalogs[provider] = (result, Date().addingTimeInterval(30 * 60))
            CatalogDiskCache.shared.save(result, provider: provider)
            return result
        } catch {
            // Kein Netz, Zeitlimit, Schutzseite: dann der letzte gute Stand.
            // Nur eine Minute gemerkt — beim nächsten Laden wird es wieder
            // live versucht.
            guard !Task.isCancelled, let stored = CatalogDiskCache.shared.load(provider: provider) else { throw error }
            catalogs[provider] = (stored, Date().addingTimeInterval(60))
            return stored
        }
    }

    private func fetchCatalog(provider: CatalogProvider) async throws -> CatalogResult {
        let html = try await fetchPage(provider.catalogPath, provider: provider)
        var items = provider == .serienstream
            ? try HTML.parseCatalogSerienstream(html)
            : try HTML.parseCatalog(html)
        // Der Parser sieht nur HTML und weiß nicht, welche Seite er liest.
        // Die Quelle kommt deshalb hier dazu — ab hier weiß jeder Eintrag,
        // wohin er führt, auch in einer gemeinsamen Liste.
        for index in items.indices { items[index].provider = provider }
        // Anzahl mitgeben: 0 heißt blockiert oder Markup geändert, eine kleine
        // Zahl heißt, dass der Parser nur noch teilweise greift. Ohne die Zahl
        // war beides dieselbe Meldung.
        guard items.count >= CatalogDiskCache.minimumItems else {
            throw NoriError.parse("\(provider.label): Katalog unvollständig, nur \(items.count) Einträge gelesen")
        }
        return CatalogResult(items: items, source: "live", fetchedAt: Date().timeIntervalSince1970 * 1000)
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
        var payload: CalendarPayload
        if provider == .serienstream {
            let data = try await fetchData(provider.calendarPath, provider: provider, accept: "application/json")
            payload = try HTML.parseSerienstreamCalendar(data)
        } else {
            let html = try await fetchPage(provider.calendarPath, provider: provider)
            payload = try HTML.parseAniworldCalendar(html)
        }
        // Wie beim Katalog: der Parser weiß nicht, welche Seite er liest.
        for index in payload.upcoming.indices { payload.upcoming[index].provider = provider }
        for index in payload.recent.indices { payload.recent[index].provider = provider }
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
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let url = URL(string: raw, relativeTo: URL(string: provider.origin + "/"))?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        // Host, Dateiendung und Query gehören zur vom Anbieter gelieferten Adresse.
        // Insbesondere AVIF nicht ungeprüft durch ein anderes Format ersetzen.
        return url
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

/// Lädt Coverbilder mit denselben Kopfzeilen wie jeder andere Abruf.
///
/// `AsyncImage` schickt weder User-Agent noch Referer. Bei diesen beiden
/// Quellen ist genau das der Unterschied zwischen einem Bild und einer leeren
/// Kachel — derselbe Grund, aus dem der Player Referer und User-Agent
/// mitschickt und `CoverToneSampler` seit jeher eine eigene `URLRequest`
/// baut. Die Kacheln blieben als einzige bei `AsyncImage`.
///
/// Der Lader merkt sich Fehlschläge, damit eine Kachel beim Scrollen nicht
/// immer wieder dieselbe 404 holt, und hält die zuletzt geladenen Bilder im
/// Speicher.
///
/// ## Was dazugekommen ist
///
/// - **Ein Plattenspeicher für Bilder** (`NoriImages` im Cache-Ordner, 256 MB).
///   Vorher lag nichts auf der Platte: nach jedem Start lud jede Kachel ihr
///   Cover neu, ohne Netz blieben alle leer. Bildadressen beider Quellen und
///   von TMDB ändern sich nicht, wenn sich das Bild ändert — ein neues Bild hat
///   eine neue Adresse. Deshalb gilt der gespeicherte Stand, bis das System
///   den Cache-Ordner räumt oder die Einstellungen ihn leeren.
/// - **Ein Abruf je Adresse.** Dasselbe Cover steht oft gleichzeitig in
///   Startseite, Katalog und Merkliste. Mehrere Kacheln warten jetzt auf
///   denselben Abruf; er wird erst abgebrochen, wenn keine mehr wartet —
///   wer an einer Kachel vorbeiscrollt, hält ihn nicht auf.
/// - **Entschlüsselt abseits des Hauptthreads** (`image(for:referer:)`).
///   Vorher entstand das Bild aus den Bytes auf dem Hauptthread, und
///   entschlüsselt wurde es erst beim ersten Zeichnen — also beim Scrollen.
actor CoverImageLoader {
    static let shared = CoverImageLoader()

    /// Ein paar Bildschirme Katalog. Groß genug, dass Zurückscrollen nichts
    /// nachlädt, klein genug, dass der Speicher nicht unbemerkt wächst.
    private let capacity = 240
    /// Fehlschläge sind billiger zu merken als Bilder, aber bei zehntausend
    /// Titeln wächst auch diese Menge. Bei Überlauf wird sie geleert statt
    /// gepflegt — im schlimmsten Fall wird ein Cover einmal zu viel probiert.
    private let failureCapacity = 4000
    /// Größte Kantenlänge eines entschlüsselten Bildes. Größer zeigt Nori
    /// nichts an; ein übergroßes Quellcover wird beim Entschlüsseln verkleinert
    /// statt in voller Auflösung im Speicher zu liegen.
    static let maxPixelSize = 1600

    private var cache: [URL: Data] = [:]
    private var order: [URL] = []
    private var failed: [URL: Date] = [:]
    private let session: URLSession
    private let diskCache: URLCache?

    /// Laufende Abrufe je Adresse, samt der Zahl der Wartenden.
    private struct Flight {
        let id: UUID
        let task: Task<Data?, Never>
        var waiters: Int
    }
    private var flights: [URL: Flight] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        // Der Katalog fragt viele Kacheln auf einmal. Ohne Deckel schickt das
        // eine Lawine an eine Quelle, die ohnehin empfindlich reagiert.
        config.httpMaximumConnectionsPerHost = 4
        #if canImport(Darwin)
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NoriImages", isDirectory: true)
        let images = URLCache(memoryCapacity: 0, diskCapacity: 256 * 1024 * 1024, directory: folder)
        config.urlCache = images
        config.requestCachePolicy = .returnCacheDataElseLoad
        diskCache = images
        #else
        diskCache = nil
        #endif
        #if DEBUG
        NoriNetworkSimulation.configure(config)
        #endif
        session = URLSession(configuration: config)
    }

    /// Bilddaten zur Adresse. `nil` heißt: nichts Verwertbares — dann bleibt
    /// es beim Buchstaben.
    func data(for url: URL, referer: String) async -> Data? {
        if let hit = cache[url] { return hit }
        if let until = failed[url], until > Date() { return nil }
        failed[url] = nil

        let id: UUID
        let task: Task<Data?, Never>
        if var flight = flights[url] {
            flight.waiters += 1
            flights[url] = flight
            id = flight.id
            task = flight.task
        } else {
            id = UUID()
            task = Task { await self.load(url, referer: referer) }
            flights[url] = Flight(id: id, task: task, waiters: 1)
        }

        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.abandon(url, id: id) }
        }
        if flights[url]?.id == id { flights[url] = nil }
        return result
    }

    /// Eine Kachel wartet nicht mehr. Wartet niemand mehr, wird der Abruf
    /// abgebrochen — beim schnellen Durchscrollen geht dann nichts raus.
    private func abandon(_ url: URL, id: UUID) {
        guard var flight = flights[url], flight.id == id else { return }
        flight.waiters -= 1
        if flight.waiters <= 0 {
            flight.task.cancel()
            flights[url] = nil
        } else {
            flights[url] = flight
        }
    }

    #if canImport(ImageIO)
    /// Das Bild fertig entschlüsselt, höchstens `maxPixelSize` groß.
    ///
    /// `nonisolated`: das Entschlüsseln läuft parallel auf dem allgemeinen
    /// Ausführer und nicht nacheinander im Actor. Ein bereits entschlüsseltes
    /// Bild kommt ohne Abruf und ohne Arbeit aus dem Zwischenspeicher.
    nonisolated func image(for url: URL, referer: String) async -> CGImage? {
        if let hit = DecodedImageCache.shared.image(for: url) { return hit }
        guard let data = await data(for: url, referer: referer) else { return nil }
        guard !Task.isCancelled else { return nil }
        if let hit = DecodedImageCache.shared.image(for: url) { return hit }
        guard let image = Self.decode(data, maxPixelSize: Self.maxPixelSize) else { return nil }
        DecodedImageCache.shared.store(image, for: url)
        return image
    }

    /// Entschlüsseln und dabei verkleinern — über ImageIO, das dafür nur die
    /// nötigen Pixel liest, statt erst das ganze Bild auszupacken.
    nonisolated static func decode(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
    #endif

    private func load(_ url: URL, referer: String) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(NoriOrigin.ua, forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/jpeg,image/png,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("de-DE,de;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        // Hotlink-Schutz: ohne Referer beantworten beide Quellen Bildanfragen
        // anders als im Browser.
        request.setValue(referer, forHTTPHeaderField: "Referer")

        guard let result = try? await session.data(for: request) else {
            if !Task.isCancelled { remember(failure: url) }
            return nil
        }
        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            remember(failure: url)
            // Eine Fehlerantwort gehört nicht in den Plattenspeicher: mit
            // `returnCacheDataElseLoad` käme sie sonst beim nächsten Mal ohne
            // Nachfrage wieder.
            diskCache?.removeCachedResponse(for: request)
            return nil
        }
        // Auch HTTP 200 kann HTML enthalten. Nur decodierbare Bilder cachen;
        // eine willkürliche Mindestgröße erkennt keine Fehlerseite.
        guard Self.isImage(result.0) else {
            remember(failure: url)
            diskCache?.removeCachedResponse(for: request)
            return nil
        }
        remember(url, result.0)
        return result.0
    }

    /// Sind das die Bytes eines Bildes?
    ///
    /// Auf Apple entscheidet das ImageIO, indem es das Bild tatsächlich
    /// aufmacht — die genaueste Auskunft, die zu haben ist. Android hat kein
    /// ImageIO; dort wird die Signatur am Dateianfang gelesen. Das erkennt
    /// eine als Bild ausgelieferte Fehlerseite genauso zuverlässig, nur ein
    /// abgeschnittenes Bild nicht. Für den Zweck — HTML aus dem Zwischen-
    /// speicher heraushalten — reicht das.
    private static func isImage(_ data: Data) -> Bool {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else { return false }
        return true
        #else
        let head = [UInt8](data.prefix(12))
        guard head.count >= 12 else { return false }
        // JPEG
        if head[0] == 0xFF, head[1] == 0xD8 { return true }
        // PNG
        if head[0] == 0x89, head[1] == 0x50, head[2] == 0x4E, head[3] == 0x47 { return true }
        // GIF
        if head[0] == 0x47, head[1] == 0x49, head[2] == 0x46 { return true }
        // RIFF-Container mit WEBP an Stelle 8
        if head[0] == 0x52, head[1] == 0x49, head[2] == 0x46, head[3] == 0x46,
           head[8] == 0x57, head[9] == 0x45, head[10] == 0x42, head[11] == 0x50 { return true }
        // ISO-BMFF: „ftyp" an Stelle 4 — deckt AVIF und HEIC ab, die
        // Serienstream ausliefert.
        if head[4] == 0x66, head[5] == 0x74, head[6] == 0x79, head[7] == 0x70 { return true }
        return false
        #endif
    }

    private func remember(_ url: URL, _ data: Data) {
        if cache[url] == nil { order.append(url) }
        cache[url] = data
        while order.count > capacity {
            let oldest = order.removeFirst()
            cache[oldest] = nil
        }
    }

    private func remember(failure url: URL) {
        if failed.count >= failureCapacity { failed.removeAll(keepingCapacity: true) }
        failed[url] = Date().addingTimeInterval(30)
    }

    /// Wie viele Bytes Bilddaten gerade im Speicher liegen.
    ///
    /// Für die Cache-Seite in den Einstellungen: sie soll eine **gemessene**
    /// Zahl zeigen. Gezählt werden die abgelegten Bilddaten, nicht die
    /// Schlüssel — die Adressen sind gegen ein Cover vernachlässigbar.
    func memoryBytes() -> Int64 {
        cache.values.reduce(into: Int64(0)) { $0 += Int64($1.count) }
    }

    /// Alles vergessen, was sich neu holen lässt: abgelegte Bilder und
    /// gemerkte Fehlschläge.
    ///
    /// Nur regenerierbares Material. Merkliste, Verlauf und Fortschritt liegen
    /// in `LibraryStore` und werden hier nicht berührt.
    func purge() {
        cache.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
        failed.removeAll(keepingCapacity: false)
        diskCache?.removeAllCachedResponses()
        #if canImport(ImageIO)
        DecodedImageCache.shared.removeAll()
        #endif
    }

    /// Speicherwarnung: alles aus dem Arbeitsspeicher, was auf der Platte
    /// ohnehin noch liegt.
    ///
    /// Anders als `purge` bleibt der Plattenspeicher stehen — die Kacheln sind
    /// danach ohne Netz sofort wieder da, nur neu entschlüsselt.
    func trimMemory() {
        cache.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
        #if canImport(ImageIO)
        DecodedImageCache.shared.removeAll()
        #endif
    }

    /// Wie viele Bytes Bilder auf der Platte liegen.
    func diskBytes() -> Int64 {
        Int64(diskCache?.currentDiskUsage ?? 0)
    }

    /// Wie `load`, aber mit Befund statt nur Ergebnis — für die Cover-Diagnose
    /// in den Einstellungen. Umgeht Zwischenspeicher und gemerkte Fehlschläge,
    /// damit die Messung den aktuellen Zustand zeigt und nicht den von vorhin.
    func probe(_ url: URL, referer: String) async -> String {
        var request = URLRequest(url: url)
        request.setValue(NoriOrigin.ua, forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/jpeg,image/png,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("de-DE,de;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(referer, forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "—"
            return "HTTP \(code), \(data.count) Byte, \(type)"
        } catch {
            return "Netzwerkfehler: \(error.localizedDescription)"
        }
    }
}


#if canImport(ImageIO)
/// Entschlüsselte Bilder im Speicher, nach Adresse.
///
/// Ein `NSCache`: er gibt unter Speicherdruck von selbst frei, und die
/// Obergrenze rechnet in Bytes der Pixel, nicht in Anzahl Bilder — ein
/// Breitbild zählt so viel wie zwanzig kleine Poster.
final class DecodedImageCache: @unchecked Sendable {
    static let shared = DecodedImageCache()

    private final class Entry {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let storage: NSCache<NSURL, Entry> = {
        let cache = NSCache<NSURL, Entry>()
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()

    func image(for url: URL) -> CGImage? {
        storage.object(forKey: url as NSURL)?.image
    }

    func store(_ image: CGImage, for url: URL) {
        storage.setObject(Entry(image), forKey: url as NSURL, cost: image.bytesPerRow * image.height)
    }

    func removeAll() {
        storage.removeAllObjects()
    }
}
#endif

actor CoverIndex {
    static let shared = CoverIndex()
    private var cache: [String: URL] = [:]
    private var missed: Set<String> = []
    private var sourceCovers: [String: URL] = [:]
    private var overrides: [String: URL] = [:]
    /// Breitbild aus demselben TMDB-Treffer. Trägt den Hero-Bereich der
    /// Startseite, für den ein 2:3-Poster die falsche Form hat.
    private var backdrops: [String: URL] = [:]
    /// Kurzbeschreibung und Bewertung fallen bei der Cover-Suche ohnehin an.
    /// Sie tragen den Hero-Text und das Hover-Infofeld, ohne dass dafür die
    /// Detailseite jeder Serie geladen werden müsste.
    private var overviews: [String: String] = [:]
    private var ratings: [String: Double] = [:]
    /// Das Schriftzug-Logo der Serie, freigestellt auf durchsichtigem Grund.
    ///
    /// Anders als Poster, Backdrop und Beschreibung fällt es bei der
    /// Cover-Suche **nicht** nebenbei ab: `/search/tv` liefert es nicht mit,
    /// es braucht einen eigenen Abruf auf `/tv/{id}/images`. Deshalb wird es
    /// nur dort geholt, wo es auch gezeigt wird — im Kopfbereich und auf den
    /// Weiterschauen-Kacheln.
    private var logos: [String: URL] = [:]
    /// Fehlschläge nur im Arbeitsspeicher: TMDB wächst, ein Neustart darf es
    /// erneut versuchen. Dieselbe Überlegung wie bei `tvIDMissed`.
    private var logoMissed: Set<String> = []
    /// Die TMDB-Kennung des Treffers. Sie fällt bei der Cover-Suche ohnehin an
    /// und ist der Einstieg zu allem, was unterhalb der Serie liegt — die
    /// Folgenbilder und -beschreibungen holt `EpisodeIndex` darüber.
    private var tvIDs: [String: Int] = [:]
    /// Slugs, zu denen auch die Alternativtitel keine Kennung ergaben. Nur im
    /// Arbeitsspeicher — TMDB wächst, ein Neustart darf es erneut versuchen.
    private var tvIDMissed: Set<String> = []
    /// Bei jedem Zugriff frisch aus dem Schlüsselbund gelesen, damit ein in
    /// den Einstellungen eingetragener Schlüssel sofort greift und die App
    /// dafür nicht neu gestartet werden muss.
    private var key: String? { TMDBKeyStore.current }

    /// Für die Oberfläche: ohne Schlüssel gibt es keine TMDB-Cover, und die
    /// manuelle Auswahl hat nichts anzubieten.
    nonisolated var hasKey: Bool { TMDBKeyStore.current != nil }

    // Der Cover-Index lag bisher nur im Arbeitsspeicher: nach jedem Start
    // musste jede Kachel erneut bei TMDB nachfragen, weshalb Listen lange
    // ohne Bild blieben. Jetzt landet er auf der Platte und ist beim nächsten
    // Start sofort da.
    private let storeURL: URL
    private var saveTask: Task<Void, Never>?
    private static let maxEntries = 4000
    /// Erhöhen, wenn sich die automatische Zuordnung ändert — verwirft die
    /// gecachten TMDB-Treffer, ohne manuelle Auswahl anzutasten.
    ///
    /// 4: seit der Kette aus Schreibweisen, der Nachbesserung über
    /// Alternativtitel und der Unterscheidung zwischen „TMDB kennt den Titel
    /// nicht" und „Abruf gescheitert". Der `missed`-Satz älterer Stände ist
    /// der Grund für die Erhöhung: Darin steht jeder Titel, den die eine alte
    /// Suche nicht fand — samt derer, die an einem Netzfehler scheiterten.
    /// Stehen zu lassen hieße, die Reparatur für genau die Titel nicht
    /// greifen zu lassen, für die sie gemacht ist.
    private static let storeVersion = 4

    /// Laufende Anfragen je Slug. Dieselbe Serie steht oft gleichzeitig in
    /// Startseite, Katalog und Kalender; ohne das ginge pro Kachel eine eigene
    /// TMDB-Anfrage raus.
    private var inFlight: [String: Task<URL?, Never>] = [:]
    /// Dasselbe für das Nachladen der Quellcover aus den Detailseiten.
    private var sourceInFlight: [String: Task<URL?, Never>] = [:]
    /// Slugs, deren Detailseite kein Cover hergab. Nur im Arbeitsspeicher: ein
    /// Neustart darf es erneut versuchen, die Seite kann sich geändert haben.
    private var missedSource: [String: Date] = [:]
    private var activeLookups = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private static let maxConcurrentLookups = 4
    /// Wie viele Schreibweisen höchstens gesucht werden, bevor ein Titel als
    /// nicht vorhanden gilt. Der erste Treffer beendet die Kette — im
    /// Regelfall bleibt es bei einer Anfrage.
    private static let maxQueriesPerTitle = 4
    /// Wie viele Zeilen im Fehlschlagfall ihre Alternativtitel nachgeladen
    /// bekommen. Je Zeile eine Anfrage, deshalb knapp gehalten.
    private static let maxAlternateLookups = 3

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("Nori", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appendingPathComponent("covers.json")

        if let data = try? Data(contentsOf: storeURL),
           let bag = try? JSONDecoder().decode(Bag.self, from: data) {
            // Alte Quelladressen hatten entfernte Queries bzw. erzwungenes JPG.
            if (bag.version ?? 1) >= Self.storeVersion {
                sourceCovers = (bag.sourceCovers ?? [:]).compactMapValues(URL.init(string:))
            }
            overrides = (bag.overrides ?? [:]).compactMapValues(URL.init(string:))
            // Die automatischen TMDB-Treffer aus älteren Ständen entstanden mit
            // einer Bewertung, die Beliebtheit als Treffer zählte, und sind
            // deshalb teilweise falsch. Sie werden verworfen und neu gesucht;
            // manuelle Auswahl und Quellcover bleiben erhalten.
            if (bag.version ?? 1) >= Self.storeVersion {
                cache = bag.covers.compactMapValues(URL.init(string:))
                missed = Set(bag.missed)
                backdrops = (bag.backdrops ?? [:]).compactMapValues(URL.init(string:))
                overviews = bag.overviews ?? [:]
                ratings = bag.ratings ?? [:]
                logos = (bag.logos ?? [:]).compactMapValues(URL.init(string:))
            }
            // Ohne Versionsprüfung: die Kennungen sind neu, ältere Dateien
            // haben sie schlicht nicht. Eine Erhöhung von `storeVersion` würde
            // dafür sämtliche Cover verwerfen — ein hoher Preis für ein Feld,
            // das sich beim nächsten Öffnen einer Detailseite von selbst füllt.
            tvIDs = bag.tvIDs ?? [:]
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

    /// Cover der Quelle beschaffen, indem die Detailseite gelesen wird.
    ///
    /// Nötig, weil die Katalogseiten reine Titellisten sind **und** sich die
    /// Adresse des Covers nicht aus dem Slug ergibt. Beide Quellen hängen
    /// einen Zufallsanteil an den Dateinamen:
    ///
    ///     /media/images/channel/desktop/black-mirror-7sqv7dhs
    ///     /public/img/cover/black-clover-stream-cover-WWoAujz6fnp…_220x330.jpg
    ///
    /// Eine geratene Adresse war deshalb ausnahmslos eine 404 — die einzige
    /// verlässliche Angabe steht auf der Detailseite selbst, die `parseSeries`
    /// ohnehin auswertet.
    ///
    /// Das kostet eine Seite pro Titel, aber nur einmal: das Ergebnis liegt
    /// danach in `covers.json` und übersteht den Neustart. Gleichzeitige
    /// Anfragen teilen sich denselben Deckel wie die TMDB-Suche.
    func fetchSourceCover(slug: String, provider: CatalogProvider) async -> URL? {
        if let known = sourceCovers[slug] { return known }
        // Ein Titel, dessen Detailseite kein Cover hergab, wird nicht bei
        // jedem Scrollen erneut geladen.
        if let until = missedSource[slug], until > Date() { return nil }
        missedSource[slug] = nil
        if let running = sourceInFlight[slug] { return await running.value }

        let task = Task<URL?, Never> {
            await self.loadSourceCover(slug: slug, provider: provider)
        }
        sourceInFlight[slug] = task
        let result = await task.value
        sourceInFlight.removeValue(forKey: slug)
        return result
    }

    private func loadSourceCover(slug: String, provider: CatalogProvider) async -> URL? {
        await acquireSlot()
        defer { releaseSlot() }
        guard let detail = try? await AniworldClient.shared.getSeries(provider: provider, slug: slug),
              let url = AniworldClient.coverURL(detail.coverPath, provider: provider)
        else {
            missedSource[slug] = Date().addingTimeInterval(30)
            return nil
        }
        sourceCovers[slug] = url
        scheduleSave()
        return url
    }

    func backdrop(for slug: String) -> URL? { backdrops[slug] }

    /// Die abgelegte TMDB-Kennung, ohne nachzuschlagen.
    ///
    /// Für die Startseite: sie bildet das Geschmacksprofil aus den gesehenen
    /// Serien und braucht dafür deren Kennungen. Ein Nachschlagen wäre hier
    /// falsch — der Aufbau der Seite darf nicht an einer Suche hängen, und
    /// eine Serie ohne Kennung fällt einfach aus dem Profil.
    func tvID(for slug: String) -> Int? { tvIDs[slug] }

    /// Dieselbe Auskunft für viele Slugs auf einmal.
    ///
    /// Die Startseite braucht die Kennungen aller angefangenen und gemerkten
    /// Titel, um daraus Empfehlungen zu holen. Einzeln abgefragt wäre das ein
    /// Sprung auf den Actor je Titel — bei einem gefüllten Verlauf zwei
    /// Dutzend Kontextwechsel für eine Handvoll Zahlen.
    func tvIDs(for slugs: [String]) -> [String: Int] {
        var out: [String: Int] = [:]
        for slug in slugs {
            if let id = tvIDs[slug] { out[slug] = id }
        }
        return out
    }

    /// Die abgelegten Bewertungen zu vielen Slugs auf einmal, ohne
    /// nachzuschlagen.
    ///
    /// Gegenstück zu `tvIDs(for:)` und aus demselben Grund gebündelt: Der
    /// Katalog braucht die Bewertungen des gesamten geladenen Bestands, um
    /// danach sortieren zu können. Einzeln abgefragt wäre das ein Sprung auf
    /// den Actor je Titel.
    ///
    /// Diese Werte fallen bei der Cover-Suche ohnehin an. Für Titel, die auf
    /// keiner TMDB-Rangliste stehen, sind sie die einzige Bewertung, die es
    /// gibt — ohne sie bliebe „Top bewertet" auf die wenigen Titel der
    /// Ranglisten beschränkt.
    func ratings(for slugs: [String]) -> [String: Double] {
        var out: [String: Double] = [:]
        for slug in slugs {
            if let value = ratings[slug] { out[slug] = value }
        }
        return out
    }

    /// Hat der Titel ein Breitbild? Nur der Kopfbereich fragt danach.
    func hasBackdrop(_ slug: String) -> Bool { backdrops[slug] != nil }

    func logo(for slug: String) -> URL? { logos[slug] }

    /// Das Logo, notfalls nachgeschlagen.
    ///
    /// Zwei Abrufe im Regelfall: erst die TMDB-Kennung (die meist schon von
    /// der Cover-Suche vorliegt), dann `/tv/{id}/images`. Deshalb nur
    /// aufrufen, wo das Logo auch sichtbar wird.
    func logoLoading(
        slug: String,
        title: String,
        alternates: [String] = [],
        kind: CatalogProvider
    ) async -> URL? {
        if let known = logos[slug] { return known }
        if logoMissed.contains(slug) { return nil }
        guard key != nil else { return nil }
        guard let id = await tvIDLoading(slug: slug, title: title, alternates: alternates, kind: kind) else {
            logoMissed.insert(slug)
            return nil
        }

        // `include_image_language` ist nicht optional: ohne den Parameter
        // filtert TMDB nach der Sprache der Anfrage und liefert für die
        // meisten Serien eine leere Liste. `null` steht für Logos ohne
        // Sprachkennzeichnung — bei Anime oft die einzigen.
        var rows = await logoRows(id: id, filter: "de,en,null")

        // Die zweite Runde ist der eigentliche Punkt: Der Filter kostet
        // messbar Logos. Gemessen an `/tv/{id}/images` — Jujutsu Kaisen 8
        // gefiltert gegen 30 ungefiltert, Naruto 3 gegen 20, Demon Slayer 13
        // gegen 49. Eine Serie, deren Logos sämtlich japanisch oder spanisch
        // ausgezeichnet sind, galt damit als „hat kein Logo", obwohl TMDB ein
        // Dutzend führt. Deshalb: ergibt der Filter nichts, ohne ihn fragen.
        if rows.isEmpty {
            rows = await logoRows(id: id, filter: nil)
        }

        guard let path = TMDBArtwork.bestLogoPath(rows), let logo = TMDBImages.url(path, .logo) else {
            if !rows.isEmpty { NoriLog.tmdb("\(slug): \(rows.count) Logos, keines verwendbar (nur SVG?)") }
            // Nur im Arbeitsspeicher gemerkt, siehe `logoMissed`.
            logoMissed.insert(slug)
            return nil
        }
        NoriLog.tmdb("\(slug): Logo aus \(rows.count) Kandidaten gewählt")
        logos[slug] = logo
        scheduleSave()
        return logo
    }

    private func logoRows(id: Int, filter: String?) async -> [[String: Any]] {
        var items: [URLQueryItem] = []
        if let filter { items.append(URLQueryItem(name: "include_image_language", value: filter)) }
        guard case .success(let body) = await json("tv/\(id)/images", items) else { return [] }
        return body["logos"] as? [[String: Any]] ?? []
    }

    /// Alles, was die Startseite über einen Titel zeigen kann, in einem Zug —
    /// spart pro Kachel mehrere Sprünge auf den Actor.
    func details(for slug: String) -> CoverDetails {
        let text = overviews[slug]
        return CoverDetails(
            poster: url(for: slug),
            backdrop: backdrops[slug],
            // Leerer Eintrag heißt „nachgeschlagen, TMDB hat keine
            // Beschreibung" — dann nicht bei jedem Aufruf erneut suchen.
            overview: (text?.isEmpty ?? true) ? nil : text,
            rating: ratings[slug],
            logo: logos[slug]
        )
    }

    /// Wie `details`, sucht bei Bedarf aber erst nach. Die Abfrage darf sich
    /// nicht am Cover orientieren: ein Titel kann ein Cover aus einem älteren
    /// Stand haben, aber noch keine Beschreibung.
    ///
    /// Nimmt die Alternativtitel der Quelle entgegen. Dass sie das vorher
    /// nicht tat, war eine der Ursachen für fehlende Poster: die Detailseite
    /// kennt die weiteren Schreibweisen einer Serie, gab sie aber nur an die
    /// Kennungs- und Logosuche weiter. Die Cover-Suche selbst lief immer nur
    /// mit dem einen Titel, unter dem die Quelle die Serie führt.
    func detailsLoading(
        slug: String,
        title: String,
        alternates: [String] = [],
        kind: CatalogProvider
    ) async -> CoverDetails {
        if overviews[slug] == nil, !missed.contains(slug) {
            _ = await deduplicatedSearch(slug: slug, title: title, alternates: alternates, kind: kind)
        }
        return details(for: slug)
    }

    /// Die TMDB-Kennung zu einem Slug, notfalls nachgeschlagen.
    ///
    /// Die Abfrage darf sich weder am Cover noch am `missed`-Satz orientieren.
    /// Am Cover nicht, weil ein Titel aus einem älteren Stand längst eines hat,
    /// aber noch keine Kennung — die kam später dazu. Am `missed`-Satz nicht,
    /// weil dort landet, was die Cover-Suche **unter dem Titel der Quelle**
    /// nicht gefunden hat: genau der Fall, in dem ein Alternativtitel hilft.
    /// Beides zusammen war der Grund, warum Folgen ohne Bild und Text blieben.
    ///
    /// Fehlschläge merkt deshalb ein eigener Satz, und der nur im Arbeits-
    /// speicher: TMDB wächst, ein Neustart darf es erneut versuchen.
    func tvIDLoading(
        slug: String,
        title: String,
        alternates: [String] = [],
        kind: CatalogProvider
    ) async -> Int? {
        if let known = tvIDs[slug] { return known }
        if tvIDMissed.contains(slug) { return nil }

        // Der reguläre Weg füllt nebenbei Cover, Beschreibung und Bewertung —
        // und kennt seit der Umstellung dieselbe Kette aus Schreibweisen samt
        // Nachbesserung über Alternativtitel. Ein zweiter, eigener Suchweg
        // nur für die Kennung ist dadurch entfallen; er lief mit anderen
        // Regeln als die Cover-Suche und fand deshalb teils anderes.
        if !missed.contains(slug) {
            _ = await deduplicatedSearch(slug: slug, title: title, alternates: alternates, kind: kind)
            if let found = tvIDs[slug] { return found }
        } else {
            // Der Titel steht als Fehlschlag der Cover-Suche vermerkt. Das
            // kann aus einem älteren Stand stammen, der weder die Kette noch
            // die Alternativtitel kannte — einmal neu fragen, aber ohne den
            // Vermerk zu löschen.
            switch await resolve(title: title, alternates: alternates, kind: kind) {
            case .matched(let hit):
                adopt(hit, for: slug)
                missed.remove(slug)
                return hit.id
            case .noMatch, .failed:
                break
            }
        }

        tvIDMissed.insert(slug)
        return nil
    }

    private struct Bag: Codable {
        var covers: [String: String]
        var missed: [String]
        // Ab Cover-Index v2. Optional, damit ältere covers.json weiter lesbar bleibt.
        var sourceCovers: [String: String]?
        var overrides: [String: String]?
        var backdrops: [String: String]?
        var overviews: [String: String]?
        var ratings: [String: Double]?
        var tvIDs: [String: Int]?
        // Ab Cover-Index v3. Optional, damit ältere covers.json weiter lesbar bleibt.
        var logos: [String: String]?
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
            overviews: overviews,
            ratings: ratings,
            tvIDs: tvIDs,
            logos: logos.mapValues(\.absoluteString),
            version: Self.storeVersion
        )
        guard let data = try? JSONEncoder().encode(bag) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    func lookup(slug: String, title: String, alternates: [String] = [], kind: CatalogProvider) async -> URL? {
        if let chosen = overrides[slug] { return chosen }
        if let hit = cache[slug] { return hit }
        // Bekannter Fehlschlag: nicht erneut anfragen, aber das Cover der Quelle
        // anbieten, statt die Kachel leer zu lassen.
        if missed.contains(slug) { return sourceCovers[slug] }

        return await deduplicatedSearch(slug: slug, title: title, alternates: alternates, kind: kind)
    }

    /// Dieselbe Serie steht oft gleichzeitig in Startseite, Katalog und
    /// Kalender; ohne Bündelung ginge pro Kachel eine eigene TMDB-Anfrage raus.
    private func deduplicatedSearch(slug: String, title: String, alternates: [String], kind: CatalogProvider) async -> URL? {
        if let running = inFlight[slug] { return await running.value }
        let task = Task<URL?, Never> {
            await self.search(slug: slug, title: title, alternates: alternates, kind: kind)
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
        // Zähler bleibt unverändert: der Slot wurde in releaseSlot direkt
        // übergeben, nicht neu vergeben.
    }

    private func releaseSlot() {
        // Den frei werdenden Slot unmittelbar an den nächsten Wartenden
        // weiterreichen. Erst herunterzuzählen und dann zu wecken ließ einen
        // neu hinzukommenden Aufrufer dazwischenrutschen, wodurch mehr
        // Anfragen gleichzeitig liefen als erlaubt.
        if waiting.isEmpty {
            activeLookups -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }

    /// Eine TMDB-Anfrage, die zwischen „nichts gefunden" und „nicht
    /// geantwortet" unterscheidet.
    ///
    /// Der Unterschied ist der Grund für diesen Typ: Vorher lieferte jeder
    /// Weg hier `nil`, und der Aufrufer legte das als „TMDB kennt den Titel
    /// nicht" dauerhaft ab. Eine Ratenbegrenzung reichte, um eine Serie bis
    /// zum Löschen des Caches abzuschreiben.
    private func json(_ path: String, _ items: [URLQueryItem]) async -> Result<[String: Any], TMDBFailure> {
        guard let key = key else { return .failure(.noKey) }
        guard var comps = URLComponents(string: "https://api.themoviedb.org/3/" + path) else {
            return .failure(.malformed)
        }
        comps.queryItems = [URLQueryItem(name: "api_key", value: key)] + items
        guard let url = comps.url else { return .failure(.malformed) }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 200
            if let failure = TMDBFailure.from(status: code) { return .failure(failure) }
            guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.malformed)
            }
            return .success(body)
        } catch {
            return .failure(.network)
        }
    }

    /// Eine einzelne Suche. Gibt die Zeilen zurück, nicht schon den Treffer —
    /// die Auswahl braucht sie später für die Nachbesserung über
    /// Alternativtitel.
    private func searchRows(query: String) async -> Result<[[String: Any]], TMDBFailure> {
        let outcome = await json("search/tv", [
            URLQueryItem(name: "language", value: "de-DE"),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false"),
        ])
        switch outcome {
        case .success(let body): return .success(body["results"] as? [[String: Any]] ?? [])
        case .failure(let failure): return .failure(failure)
        }
    }

    /// Die weiteren Schreibweisen, die TMDB zu einer Serie führt.
    ///
    /// `/search/tv` liefert je Zeile nur `name` und `original_name` — bei
    /// einem Anime also den deutschen bzw. den japanischen Titel in
    /// Originalschrift. Die Umschrift, unter der AniWorld die Serie oft
    /// führt, steht ausschließlich hier.
    ///
    /// Gemessen: `/search/tv?query=Shingeki no Kyojin` liefert genau eine
    /// Zeile, nämlich die richtige (#1429) — deren `name` „Attack on Titan"
    /// und deren `original_name` „進撃の巨人" ist. Die Bewertung verwarf sie,
    /// weil der Suchbegriff zu keinem der beiden passt. „Shingeki no Kyojin"
    /// steht in `/alternative_titles`.
    private func alternateNames(for id: Int) async -> [String] {
        guard case .success(let body) = await json("tv/\(id)/alternative_titles", []) else { return [] }
        let rows = body["results"] as? [[String: Any]] ?? []
        return rows.compactMap { $0["title"] as? String }.filter { !$0.isEmpty }
    }

    /// Was eine Auflösung über TMDB ergeben hat.
    private enum Resolution {
        case matched(TMDBCandidate)
        /// TMDB hat geantwortet, aber nichts passte. Darf gemerkt werden.
        case noMatch
        /// TMDB hat nicht brauchbar geantwortet. Darf **nicht** gemerkt werden.
        case failed(TMDBFailure)
    }

    /// Den TMDB-Eintrag zu einem Nori-Titel bestimmen.
    ///
    /// ## Warum mehrere Anläufe
    ///
    /// Vorher ging genau **eine** Suche mit dem Titel der Quelle raus, und
    /// wer damit nichts fand, fand nie etwas. `TMDBMatcher.queries` baut die
    /// Kette der Suchbegriffe seit jeher auf — benutzt hat sie nur die
    /// Kennungssuche, nicht die Cover-Suche. Zwei belegte Folgen davon:
    ///
    /// - „Attack on Titan Staffel 2" liefert bei TMDB **null** Zeilen,
    ///   „attack on titan" vier. Die Kette enthält die um den Staffelzusatz
    ///   bereinigte Fassung — sie wurde nur nie gefragt.
    /// - Alternativtitel von der Detailseite der Quelle erreichten die
    ///   Cover-Suche gar nicht, weil `detailsLoading` sie nicht annahm.
    ///
    /// Der erste Begriff, der einen Treffer über der Titelschwelle liefert,
    /// gewinnt — im Regelfall also der erste, und es bleibt bei einer
    /// Anfrage. Die weiteren Anläufe kosten nur dort etwas, wo bisher gar
    /// nichts herauskam.
    private func resolve(title: String, alternates: [String], kind: CatalogProvider) async -> Resolution {
        let queries = Array(TMDBMatcher.queries(for: title, alternates: alternates).prefix(Self.maxQueriesPerTitle))
        guard !queries.isEmpty else { return .noMatch }

        var firstRows: [[String: Any]] = []
        var firstQuery = queries[0]
        var sawAnswer = false
        var lastFailure: TMDBFailure = .network

        for query in queries {
            await acquireSlot()
            let outcome = await searchRows(query: query)
            releaseSlot()

            switch outcome {
            case .failure(let failure):
                lastFailure = failure
                // Ein ungültiger Schlüssel und eine Ratenbegrenzung gelten
                // für jede weitere Anfrage genauso — weiterprobieren hieße
                // nur, schneller in dieselbe Wand zu laufen.
                if failure == .unauthorized || failure == .rateLimited || failure == .noKey {
                    return .failed(failure)
                }
            case .success(let rows):
                sawAnswer = true
                if firstRows.isEmpty, !rows.isEmpty {
                    firstRows = rows
                    firstQuery = query
                }
                if let hit = TMDBMatcher.best(in: rows, query: query, kind: kind, requirePoster: false) {
                    NoriLog.tmdb("Treffer für \"\(query)\": #\(hit.id) \(hit.name)")
                    return .matched(hit)
                }
            }
        }

        // Nachbesserung: TMDB hat etwas geliefert, Noris Titelschwelle hat es
        // verworfen. Dass TMDB die Zeile auf diesen Begriff hin überhaupt
        // ausgibt, heißt, dass der Begriff zu **irgendeiner** Schreibweise
        // passt, die TMDB kennt — nur eben nicht zu `name` oder
        // `original_name`. Die fehlenden Schreibweisen werden jetzt geholt.
        //
        // Nur für die vordersten Zeilen und nur im Fehlschlagfall: das ist
        // eine zusätzliche Anfrage je Zeile, und im Regelfall passiert das
        // hier gar nicht.
        if !firstRows.isEmpty {
            var enriched = firstRows.compactMap(TMDBCandidate.init(json:))
            for index in enriched.indices.prefix(Self.maxAlternateLookups) {
                // Unter derselben Deckelung wie die Suche: ein Raster mit
                // sechzig Kacheln, deren Titel allesamt nachgebessert werden
                // müssen, liefe sonst an der Begrenzung vorbei.
                await acquireSlot()
                enriched[index].alternateNames = await alternateNames(for: enriched[index].id)
                releaseSlot()
            }
            if let hit = TMDBMatcher.best(in: enriched, query: firstQuery, kind: kind, requirePoster: false) {
                NoriLog.tmdb("Treffer über Alternativtitel für \"\(firstQuery)\": #\(hit.id) \(hit.name)")
                return .matched(hit)
            }
        }

        if sawAnswer {
            NoriLog.tmdb("Kein Treffer für \"\(title)\"")
            return .noMatch
        }
        return .failed(lastFailure)
    }

    /// Alles übernehmen, was der Treffer hergibt.
    ///
    /// Vorher hing **jedes** dieser Felder daran, dass der Treffer ein Poster
    /// trug: `requirePoster: true` verwarf die Zeile, und damit gingen
    /// Breitbild, Beschreibung, Bewertung und vor allem die **Kennung**
    /// mitsamt allem, was daran hängt, verloren — Logo und sämtliche
    /// Folgendaten. Eine Serie ohne Titelbild bei TMDB verlor so ihre ganzen
    /// Metadaten, obwohl nur das Poster fehlte.
    private func adopt(_ hit: TMDBCandidate, for slug: String) {
        tvIDs[slug] = hit.id
        if let poster = TMDBImages.url(hit.posterPath, .posterHero) {
            cache[slug] = poster
        }
        if let wide = TMDBImages.url(hit.backdropPath, .backdropHero) {
            backdrops[slug] = wide
        }
        // Auch ohne Text eintragen: der leere Eintrag merkt sich, dass
        // nachgeschlagen wurde, und verhindert dieselbe Suche bei jedem
        // Aufbau der Ansicht.
        overviews[slug] = hit.overview ?? ""
        if hit.voteAverage > 0 {
            ratings[slug] = hit.voteAverage
        }
        NoriLog.tmdb("\(slug): Poster \(hit.hasPoster ? "ja" : "nein"), Breitbild \(hit.hasBackdrop ? "ja" : "nein")")
        scheduleSave()
    }

    private func search(slug: String, title: String, alternates: [String], kind: CatalogProvider) async -> URL? {
        // Ohne Schlüssel gar nicht erst anfragen: TMDB antwortet sonst mit 401,
        // und das Quellcover ist die richtige Antwort.
        guard key != nil else { return sourceCovers[slug] }

        switch await resolve(title: title, alternates: alternates, kind: kind) {
        case .matched(let hit):
            adopt(hit, for: slug)
            return cache[slug] ?? sourceCovers[slug]
        case .noMatch:
            // Nur hier merken: TMDB hat geantwortet und führt den Titel nicht.
            missed.insert(slug)
            scheduleSave()
            return sourceCovers[slug]
        case .failed(let failure):
            // Nicht merken. Der nächste Aufbau darf es erneut versuchen.
            NoriLog.tmdb("\(slug): Abruf gescheitert (\(failure.label)), kein Eintrag gemerkt")
            return sourceCovers[slug]
        }
    }

    /// Auswahlvorschläge für die manuelle Cover-Zuordnung: die Treffer aus
    /// TMDB in Rangfolge. Ohne Cache und ohne `missed`-Sperre, weil hier
    /// bewusst nach einer Alternative gesucht wird.
    func candidates(title: String, kind: CatalogProvider, limit: Int = 12) async -> [CoverCandidate] {
        guard let key = key else { return [] }
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
                guard let path = row["poster_path"] as? String,
                      let poster = TMDBImages.url(path, .posterHero)
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

/// Was der Cover-Index über einen Titel weiß. Kommt komplett aus der ohnehin
/// nötigen TMDB-Suche — keine zusätzlichen Anfragen.
struct CoverDetails: Hashable {
    var poster: URL?
    var backdrop: URL?
    var overview: String?
    var rating: Double?
    /// Freigestellter Schriftzug. Nur gefüllt, wenn ihn jemand angefordert
    /// hat — er kostet einen eigenen Abruf, siehe `logoLoading`.
    var logo: URL? = nil

    /// Bewertung als Fünf-Sterne-Skala; TMDB liefert 0–10.
    var stars: Double? { rating.map { $0 / 2 } }
}

struct CoverCandidate: Identifiable, Hashable {
    let url: URL
    let label: String
    let source: String
    var id: URL { url }
}

/// Was TMDB zu einer einzelnen Folge weiß.
///
/// AniWorld und Serienstream liefern zu einer Folge nur zwei Titel und einen
/// Pfad — kein Bild, keine Beschreibung. Beides steht bei TMDB, hinter der
/// Kennung, die die Cover-Suche ohnehin schon ermittelt hat.
struct EpisodeInfo: Codable, Hashable {
    /// Der Folgentitel — oder ein Platzhalter. Siehe `namedTitle(for:)`.
    var title: String?
    var overview: String?
    var still: String?
    var airDate: String?
    /// Laufzeit in Minuten, sofern TMDB sie führt.
    ///
    /// Steht in derselben Antwort wie Titel und Standbild — es kostet keine
    /// zusätzliche Anfrage. Die Detailseite nennt sie in der Zeile unter dem
    /// Folgentitel; fehlt sie, entfällt der Teil ersatzlos.
    var runtime: Int? = nil

    var stillURL: URL? { still.flatMap(URL.init(string:)) }

    /// Der Folgentitel, sofern es einer ist.
    ///
    /// TMDB füllt unbenannte Folgen mit einem Platzhalter aus Wort und Nummer:
    /// „Folge 11" auf Deutsch, „Episode 11" auf Englisch. Das ist kein Titel,
    /// sondern dieselbe Nummer noch einmal — im Kalender stand dadurch
    /// „Staffel 3 · Folge 11 · Folge 11".
    ///
    /// Geprüft wird die **Form**, nicht die Übereinstimmung mit einer Nummer:
    /// eine Folge, die bei der Quelle als 11 und bei TMDB als 12 geführt wird,
    /// trüge sonst weiterhin „Folge 12" als vermeintlichen Titel.
    var namedTitle: String? {
        guard let raw = title?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let placeholder = raw.range(
            of: #"^(folge|episode)\s*\d+$"#,
            options: [.regularExpression, .caseInsensitive]
        )
        return placeholder == nil ? raw : nil
    }
}

/// Folgenbilder und -beschreibungen, eine Staffel auf einmal.
///
/// Staffelweise, weil TMDB genau das anbietet: ein Aufruf liefert alle Folgen
/// mit Bild, Titel, Text und Erstausstrahlung. Eine Anfrage je Folge wären bei
/// einer 24er-Staffel 24 Anfragen für dieselbe Antwort.
///
/// Der Aufbau entspricht `CoverIndex`: Cache auf der Platte, ein `missed`-Satz
/// gegen wiederholte Fehlschläge, Bündelung gleichzeitiger Anfragen. Getrennt
/// gehalten, weil `covers.json` bei jedem Scrollen durch den Katalog
/// geschrieben wird und die Folgendaten dort nur mitwachsen würden.
actor EpisodeIndex {
    static let shared = EpisodeIndex()

    /// Geschlüsselt nach `slug|staffel`, darin die Folgennummer als Text —
    /// JSON kennt keine Zahlen als Schlüssel.
    private var seasons: [String: [String: EpisodeInfo]] = [:]
    /// Fehlschläge **mit Zeitstempel**, und nur endgültige.
    ///
    /// Vorher war das ein `Set<String>` ohne Zeit und ohne Unterscheidung:
    /// Jede Antwort, die keine Folgen enthielt, landete darin — auch eine
    /// Zeitüberschreitung, ein 429 und ein 401. Der Satz wanderte auf die
    /// Platte, und damit galt eine Staffel, die TMDB in dem Moment nur nicht
    /// ausliefern konnte, dauerhaft als „hat TMDB nicht". Genau das war die
    /// Sorte Fehler, die sich nicht mehr von selbst erholt.
    ///
    /// Jetzt kommt nur ein HTTP 404 hier hinein, und auch das nur auf Zeit:
    /// TMDB wächst, Staffeln kommen nach.
    private var missedAt: [String: Miss] = [:]

    /// Ein endgültiger Fehlschlag — wann, und **mit welchem Wissen**.
    ///
    /// `hadAnchors` ist der entscheidende Teil. Startseite und Kalender rufen
    /// dieselbe Staffel ohne die Folgenliste der Quelle ab; die Detailseite
    /// ruft sie mit ab. Ohne diese Unterscheidung könnte eine Weiterschauen-
    /// Kachel eine Staffel als „nicht vorhanden" vermerken, bevor die
    /// Detailseite die Zuordnung über die Folgentitel überhaupt versuchen
    /// durfte — und die Detailseite käme dann nie mehr dazu.
    struct Miss: Codable, Hashable {
        var at: Double
        var hadAnchors: Bool
    }
    private var inFlight: [String: Task<[Int: EpisodeInfo], Never>] = [:]
    /// Die Staffelliste einer Serie, je Sitzung einmal geholt. Sie wird nur
    /// gebraucht, wenn die Zählung der Quelle nicht aufgeht.
    private var structure: [Int: [(number: Int, episodeCount: Int)]] = [:]

    private let storeURL: URL
    private var saveTask: Task<Void, Never>?
    private static let maxSeasons = 600
    /// Wie lange ein „gibt es dort nicht" gilt.
    private static let missMaxAge: TimeInterval = 14 * 86_400
    // 3: seit der Unterscheidung zwischen „TMDB hat nichts" und „Abruf
    // gescheitert". Ältere Stände enthalten Fehlschläge beider Sorten in
    // einem Topf und sind damit unbrauchbar — sie werden einmalig verworfen.
    private static let storeVersion = 3

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("Nori", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appendingPathComponent("episodes.json")

        if let data = try? Data(contentsOf: storeURL),
           let bag = try? JSONDecoder().decode(Bag.self, from: data),
           (bag.version ?? 1) >= Self.storeVersion {
            seasons = bag.seasons
            missedAt = bag.missedAt ?? [:]
        }
    }

    private static func key(_ slug: String, _ season: String) -> String { "\(slug)|\(season)" }

    /// Was schon dasteht, ohne Netz. Für den ersten Aufbau der Ansicht: die
    /// Folgenliste erscheint sofort, die Bilder tragen sich nach.
    func cached(slug: String, season: String) -> [Int: EpisodeInfo] {
        unpack(seasons[Self.key(slug, season)])
    }

    /// Staffel holen, notfalls über TMDB.
    ///
    /// - Parameter sourceEpisodes: Die Folgen, wie die **Quelle** sie führt.
    ///   Ohne sie bleibt nur die Zuordnung über gleiche Nummern; mit ihnen
    ///   lässt sich eine abweichende Staffelaufteilung auflösen (siehe
    ///   `TMDBSeasonMap`). Leer ist zulässig und schadet nicht.
    func load(
        slug: String,
        title: String,
        alternates: [String] = [],
        season: String,
        kind: CatalogProvider,
        sourceEpisodes: [TMDBSeasonMap.SourceEpisode] = []
    ) async -> [Int: EpisodeInfo] {
        let key = Self.key(slug, season)
        if let known = seasons[key] { return unpack(known) }
        if let miss = missedAt[key],
           Date().timeIntervalSince1970 - miss.at < Self.missMaxAge,
           miss.hadAnchors || sourceEpisodes.isEmpty {
            return [:]
        }
        if let running = inFlight[key] { return await running.value }

        let task = Task<[Int: EpisodeInfo], Never> {
            await self.fetch(
                slug: slug,
                title: title,
                alternates: alternates,
                season: season,
                kind: kind,
                sourceEpisodes: sourceEpisodes
            )
        }
        inFlight[key] = task
        let result = await task.value
        inFlight.removeValue(forKey: key)
        return result
    }

    private func unpack(_ raw: [String: EpisodeInfo]?) -> [Int: EpisodeInfo] {
        guard let raw else { return [:] }
        var out: [Int: EpisodeInfo] = [:]
        for (number, info) in raw {
            guard let n = Int(number) else { continue }
            out[n] = info
        }
        return out
    }

    private func fetch(
        slug: String,
        title: String,
        alternates: [String],
        season: String,
        kind: CatalogProvider,
        sourceEpisodes: [TMDBSeasonMap.SourceEpisode]
    ) async -> [Int: EpisodeInfo] {
        let key = Self.key(slug, season)
        // „Filme" und andere Sonderabschnitte tragen keine Staffelnummer.
        // TMDB kennt zwar Staffel 0 für Specials, aber welche Folge dort
        // welcher entspricht, wäre geraten — dann lieber nichts anzeigen als
        // das Falsche.
        guard let number = Int(season), number > 0 else {
            // Eine Staffel ohne Nummer wird durch keine Folgenliste zu einer
            // mit Nummer — das gilt unabhängig von den Ankern.
            missedAt[key] = Miss(at: Date().timeIntervalSince1970, hadAnchors: true)
            return [:]
        }
        guard TMDBKeyStore.current != nil else { return [:] }
        // Ohne Kennung **nicht** merken: der Vermerk wandert auf die Platte,
        // und ein Titel, den TMDB heute nicht führt, wäre damit abgeschrieben.
        // Die Sperre gegen wiederholte Anfragen hält im Cover-Index.
        guard let id = await CoverIndex.shared.tvIDLoading(
            slug: slug,
            title: title,
            alternates: alternates,
            kind: kind
        ) else { return [:] }

        switch await seasonEpisodes(id: id, number: number) {
        case .success(let direct):
            // Eine Antwort mit HTTP 200 ist noch nicht die richtige Staffel.
            // Führt die Quelle 48 Folgen und TMDB in derselben Staffel 24,
            // bleibt die Hälfte leer, obwohl TMDB sie hat — nur woanders.
            let covered = TMDBSeasonMap.coverage(source: sourceEpisodes, tmdb: direct)
            if sourceEpisodes.isEmpty || covered >= 0.5 {
                NoriLog.tmdb("\(slug) S\(number): \(direct.count) Folgen direkt übernommen")
                return store(direct, at: key)
            }
            NoriLog.tmdb("\(slug) S\(number): nur \(Int(covered * 100)) % abgedeckt, Staffelstruktur wird geprüft")
            if let mapped = await mapStructurally(id: id, slug: slug, source: sourceEpisodes), !mapped.isEmpty {
                return store(mapped, at: key)
            }
            return store(direct, at: key)

        case .failure(.notFound):
            // Die häufigste Ursache fehlender Folgendaten bei Anime: Die
            // Quelle teilt feiner als TMDB. Gemessen — Jujutsu Kaisen ist bei
            // TMDB **eine** Staffel mit 59 Folgen, AniWorld führt zwei;
            // `/tv/95479/season/2` antwortet mit 404. Dasselbe bei Detektiv
            // Conan (eine Staffel, 1213 Folgen) und Frieren.
            NoriLog.tmdb("\(slug) S\(number): 404, Zuordnung über Folgentitel wird versucht")
            if let mapped = await mapStructurally(id: id, slug: slug, source: sourceEpisodes), !mapped.isEmpty {
                return store(mapped, at: key)
            }
            // Jetzt ist es belegt: TMDB kennt diese Staffel nicht, und über
            // die Titel war nichts zuzuordnen. Auf Zeit merken.
            missedAt[key] = Miss(at: Date().timeIntervalSince1970, hadAnchors: !sourceEpisodes.isEmpty)
            scheduleSave()
            return [:]

        case .failure(let failure):
            // Kein Vermerk. Der nächste Aufruf darf es erneut versuchen.
            NoriLog.tmdb("\(slug) S\(number): Abruf gescheitert (\(failure.label)), kein Vermerk")
            return [:]
        }
    }

    private func store(_ episodes: [Int: EpisodeInfo], at key: String) -> [Int: EpisodeInfo] {
        guard !episodes.isEmpty else { return [:] }
        seasons[key] = Dictionary(uniqueKeysWithValues: episodes.map { (String($0.key), $0.value) })
        missedAt.removeValue(forKey: key)
        scheduleSave()
        return episodes
    }

    /// Die Folgen der Quelle über ihre **Titel** in TMDBs Staffelaufteilung
    /// wiederfinden.
    ///
    /// Nur wenn die Zuordnung über die Nummer nicht aufgeht. Kostet einen
    /// Abruf für die Staffelliste und je geprüfter Staffel einen weiteren,
    /// gedeckelt auf die drei umfangreichsten — die Zusammenfassung mehrerer
    /// Quellstaffeln steckt praktisch immer in der größten.
    private func mapStructurally(
        id: Int,
        slug: String,
        source: [TMDBSeasonMap.SourceEpisode]
    ) async -> [Int: EpisodeInfo]? {
        guard !source.isEmpty else { return nil }
        let list = await seasonList(id: id)
        guard !list.isEmpty else { return nil }

        for entry in list.sorted(by: { $0.episodeCount > $1.episodeCount }).prefix(3) {
            guard case .success(let episodes) = await seasonEpisodes(id: id, number: entry.number), !episodes.isEmpty else {
                continue
            }
            let titles = episodes.compactMapValues { $0.title }
            guard let offset = TMDBSeasonMap.offset(source: source, tmdb: titles) else { continue }
            let mapped = TMDBSeasonMap.remap(episodes, by: offset, to: source)
            guard !mapped.isEmpty else { continue }
            NoriLog.tmdb("\(slug): über Folgentitel auf TMDB-Staffel \(entry.number) abgebildet, Versatz \(offset), \(mapped.count) Folgen")
            return mapped
        }
        return nil
    }

    /// Welche Staffeln TMDB zu der Serie führt. Staffel 0 bleibt außen vor.
    private func seasonList(id: Int) async -> [(number: Int, episodeCount: Int)] {
        if let known = structure[id] { return known }
        guard case .success(let body) = await json("tv/\(id)", [URLQueryItem(name: "language", value: "de-DE")]) else {
            return []
        }
        let rows = body["seasons"] as? [[String: Any]] ?? []
        let list = rows.compactMap { row -> (number: Int, episodeCount: Int)? in
            guard let number = row["season_number"] as? Int, number > 0 else { return nil }
            return (number, row["episode_count"] as? Int ?? 0)
        }
        structure[id] = list
        return list
    }

    /// Eine Staffel in Deutsch, mit Englisch als Lückenfüller.
    private func seasonEpisodes(id: Int, number: Int) async -> Result<[Int: EpisodeInfo], TMDBFailure> {
        let german = await request(id: id, season: number, language: "de-DE")
        guard case .success(let primary) = german else { return german }

        // TMDB pflegt die deutschen Texte lückenhaft, bei Anime fast gar
        // nicht. Die zweite Fassung wird jetzt geholt, sobald **irgendetwas**
        // fehlt — vorher erst ab der Hälfte der Staffel, wodurch einzelne
        // Lücken nie gefüllt wurden.
        guard TMDBArtwork.hasGaps(primary) else { return .success(primary) }
        guard case .success(let english) = await request(id: id, season: number, language: "en-US") else {
            return .success(primary)
        }
        return .success(TMDBArtwork.merging(primary, with: english))
    }

    private func json(_ path: String, _ items: [URLQueryItem]) async -> Result<[String: Any], TMDBFailure> {
        guard let key = TMDBKeyStore.current else { return .failure(.noKey) }
        guard var comps = URLComponents(string: "https://api.themoviedb.org/3/" + path) else {
            return .failure(.malformed)
        }
        comps.queryItems = [URLQueryItem(name: "api_key", value: key)] + items
        guard let url = comps.url else { return .failure(.malformed) }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 200
            if let failure = TMDBFailure.from(status: code) { return .failure(failure) }
            guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.malformed)
            }
            return .success(body)
        } catch {
            return .failure(.network)
        }
    }

    private func request(id: Int, season: Int, language: String) async -> Result<[Int: EpisodeInfo], TMDBFailure> {
        let outcome = await json("tv/\(id)/season/\(season)", [URLQueryItem(name: "language", value: language)])
        let body: [String: Any]
        switch outcome {
        case .success(let value): body = value
        case .failure(let failure): return .failure(failure)
        }
        guard let rows = body["episodes"] as? [[String: Any]] else { return .failure(.malformed) }
        var out: [Int: EpisodeInfo] = [:]
        for row in rows {
            guard let n = row["episode_number"] as? Int else { continue }
            // Das Zuschnittsformat von TMDB selbst: 454×254, also 16:9 —
            // genau die Form, in der die Folgenliste es zeigt. `still_path`,
            // nicht `poster_path`: Folgen haben bei TMDB kein Poster.
            let still = TMDBImages.url(row["still_path"] as? String, .still)?.absoluteString
            // TMDB liefert die Laufzeit teils als 0, wenn sie unbekannt ist.
            // Null Minuten ist keine Auskunft, sondern eine Lücke.
            let minutes = (row["runtime"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            out[n] = EpisodeInfo(
                title: row["name"] as? String,
                overview: row["overview"] as? String,
                still: still,
                airDate: row["air_date"] as? String,
                runtime: minutes
            )
        }
        return .success(out)
    }

    private struct Bag: Codable {
        var seasons: [String: [String: EpisodeInfo]]
        /// Endgültige Fehlschläge mit Zeitstempel. Optional, weil ältere
        /// Stände stattdessen ein `missed`-Feld ohne Zeit hatten — die werden
        /// über `storeVersion` ohnehin verworfen.
        var missedAt: [String: Miss]?
        var version: Int?
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.persist()
        }
    }

    private func persist() {
        var kept = seasons
        if kept.count > Self.maxSeasons {
            kept = Dictionary(uniqueKeysWithValues: kept.prefix(Self.maxSeasons).map { ($0.key, $0.value) })
        }
        // Abgelaufene Vermerke fallen beim Schreiben heraus, nicht erst beim
        // Lesen: sonst wüchse die Datei mit jedem Titel, den TMDB je nicht
        // hatte.
        let now = Date().timeIntervalSince1970
        var misses = missedAt.filter { now - $0.value.at < Self.missMaxAge }
        if misses.count > Self.maxSeasons {
            misses = Dictionary(uniqueKeysWithValues: misses.sorted { $0.value.at > $1.value.at }.prefix(Self.maxSeasons).map { ($0.key, $0.value) })
        }
        let bag = Bag(seasons: kept, missedAt: misses, version: Self.storeVersion)
        guard let data = try? JSONEncoder().encode(bag) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
