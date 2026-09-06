import Foundation
import Security
import ImageIO

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
        guard let data = trimmed.data(using: .utf8) else { return false }
        defer { cached = nil }

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
    }

    @discardableResult
    static func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        defer { cached = nil }
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func readKeychain() -> String? {
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
        session = URLSession(configuration: config)
    }

    func getCatalog(provider: CatalogProvider, force: Bool = false) async throws -> CatalogResult {
        if !force, let hit = catalogs[provider], hit.1 > Date() { return hit.0 }
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
actor CoverImageLoader {
    static let shared = CoverImageLoader()

    /// Ein paar Bildschirme Katalog. Groß genug, dass Zurückscrollen nichts
    /// nachlädt, klein genug, dass der Speicher nicht unbemerkt wächst.
    private let capacity = 240
    /// Fehlschläge sind billiger zu merken als Bilder, aber bei zehntausend
    /// Titeln wächst auch diese Menge. Bei Überlauf wird sie geleert statt
    /// gepflegt — im schlimmsten Fall wird ein Cover einmal zu viel probiert.
    private let failureCapacity = 4000

    private var cache: [URL: Data] = [:]
    private var order: [URL] = []
    private var failed: [URL: Date] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        // Der Katalog fragt viele Kacheln auf einmal. Ohne Deckel schickt das
        // eine Lawine an eine Quelle, die ohnehin empfindlich reagiert.
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
    }

    /// Bilddaten zur Adresse. `nil` heißt: nichts Verwertbares — dann bleibt
    /// es beim Buchstaben.
    func data(for url: URL, referer: String) async -> Data? {
        if let hit = cache[url] { return hit }
        if let until = failed[url], until > Date() { return nil }
        failed[url] = nil
        return await load(url, referer: referer)
    }

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
            return nil
        }
        // Auch HTTP 200 kann HTML enthalten. Nur decodierbare Bilder cachen;
        // eine willkürliche Mindestgröße erkennt keine Fehlerseite.
        guard let imageSource = CGImageSourceCreateWithData(result.0 as CFData, nil),
              CGImageSourceCreateImageAtIndex(imageSource, 0, nil) != nil else {
            remember(failure: url)
            return nil
        }
        remember(url, result.0)
        return result.0
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
    private static let storeVersion = 3

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
            rating: ratings[slug]
        )
    }

    /// Wie `details`, sucht bei Bedarf aber erst nach. Die Abfrage darf sich
    /// nicht am Cover orientieren: ein Titel kann ein Cover aus einem älteren
    /// Stand haben, aber noch keine Beschreibung.
    func detailsLoading(slug: String, title: String, kind: CatalogProvider) async -> CoverDetails {
        if overviews[slug] == nil, !missed.contains(slug) {
            _ = await deduplicatedSearch(slug: slug, title: title, kind: kind)
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

        // Erst der reguläre Weg: er füllt nebenbei Cover, Beschreibung und
        // Bewertung. Nur wenn der nichts hergibt, die Alternativtitel.
        if !missed.contains(slug) {
            _ = await deduplicatedSearch(slug: slug, title: title, kind: kind)
            if let found = tvIDs[slug] { return found }
        }

        for query in Self.queries(for: title, alternates: alternates).dropFirst() {
            if let found = await searchID(query: query, kind: kind) {
                tvIDs[slug] = found
                scheduleSave()
                return found
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

        return await deduplicatedSearch(slug: slug, title: title, kind: kind)
    }

    /// Dieselbe Serie steht oft gleichzeitig in Startseite, Katalog und
    /// Kalender; ohne Bündelung ginge pro Kachel eine eigene TMDB-Anfrage raus.
    private func deduplicatedSearch(slug: String, title: String, kind: CatalogProvider) async -> URL? {
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

    /// Den passendsten Treffer aus einer TMDB-Antwort wählen.
    ///
    /// Lag bisher mitten in `search` und war damit nur für die Cover-Suche zu
    /// haben. Die Kennungssuche braucht dieselbe Bewertung, darf aber kein
    /// Poster verlangen: eine Serie ohne Poster hat trotzdem Folgen mit Bild
    /// und Text.
    ///
    /// Gibt `nil` zurück, wenn kein Treffer wirklich am Titel hängt — lieber
    /// nichts als das Falsche.
    private static func bestRow(
        in results: [[String: Any]],
        query: String,
        kind: CatalogProvider,
        requirePoster: Bool
    ) -> [String: Any]? {
        var best: (score: Double, bonus: Double, row: [String: Any])?
        let nq = query.lowercased()
        for row in results {
            if requirePoster {
                guard let path = row["poster_path"] as? String, !path.isEmpty else { continue }
            }
            let name = (row["name"] as? String ?? "").lowercased()
            let orig = (row["original_name"] as? String ?? "").lowercased()
            // Beliebtheit ist nur Stichentscheid, kein Treffer. Vorher ging
            // sie voll in die Wertung ein, weshalb eine bekannte, völlig
            // andere Serie die Schwelle allein durch Popularität riss —
            // genau so entstanden die falschen Cover.
            var bonus: Double = 0
            if name == nq || orig == nq { bonus = 400 }
            else if name.hasPrefix(nq) || orig.hasPrefix(nq) { bonus = 180 }
            else if name.contains(nq) || orig.contains(nq) { bonus = 80 }
            else if nq.contains(name) && name.count >= 4 { bonus = 60 }
            var score = bonus + min(row["popularity"] as? Double ?? 0, 40)
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
                best = (score, bonus, row)
            }
        }
        guard let best, best.bonus >= 80 else { return nil }
        return best.row
    }

    /// Suchbegriffe zu einem Titel, in absteigender Güte.
    ///
    /// AniWorld und Serienstream führen Serien häufig unter einem eingedeutschten
    /// oder verkürzten Namen, den TMDB nicht kennt. Die Seite nennt daneben aber
    /// Alternativtitel — original, englisch, japanisch —, und einer davon trifft
    /// meist. Dazu kommt der Teil vor einem Doppelpunkt: „Titel: Untertitel"
    /// steht bei TMDB oft nur als „Titel".
    private static func queries(for title: String, alternates: [String]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []

        func add(_ raw: String) {
            let cleaned = raw
                .replacingOccurrences(of: #"\s*\(\d{4}\)\s*"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count >= 2 else { return }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            out.append(cleaned)
        }

        add(title)
        for alt in alternates { add(alt) }
        for candidate in [title] + alternates {
            if let colon = candidate.firstIndex(of: ":") {
                add(String(candidate[candidate.startIndex ..< colon]))
            }
        }
        return out
    }

    /// Eine einzelne TMDB-Suche, die nur die Kennung zurückgibt.
    private func searchID(query: String, kind: CatalogProvider) async -> Int? {
        guard let key = key else { return nil }
        await acquireSlot()
        defer { releaseSlot() }
        guard var comps = URLComponents(string: "https://api.themoviedb.org/3/search/tv") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "language", value: "de-DE"),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false"),
        ]
        guard let url = comps.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = json["results"] as? [[String: Any]]
            else { return nil }
            // Ohne Posterzwang: für die Folgendaten zählt die Serie, nicht ihr
            // Titelbild.
            return Self.bestRow(in: results, query: query, kind: kind, requirePoster: false)?["id"] as? Int
        } catch {
            return nil
        }
    }

    private func search(slug: String, title: String, kind: CatalogProvider) async -> URL? {
        // Ohne Schlüssel gar nicht erst anfragen: TMDB antwortet sonst mit 401,
        // und das Quellcover ist die richtige Antwort.
        guard let key = key else { return sourceCovers[slug] }
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
            // Ohne echte Titelübereinstimmung lieber kein Cover als ein
            // falsches — dann greift das Cover der Quelle.
            if let best = Self.bestRow(in: results, query: q, kind: kind, requirePoster: true),
               let path = best["poster_path"] as? String,
               let poster = URL(string: "https://image.tmdb.org/t/p/w780\(path)") {
                cache[slug] = poster
                if let backdropPath = best["backdrop_path"] as? String, !backdropPath.isEmpty,
                   let wide = URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)") {
                    backdrops[slug] = wide
                }
                // Auch ohne Text eintragen: der leere Eintrag merkt sich, dass
                // nachgeschlagen wurde, und verhindert dieselbe Suche bei jedem
                // Aufbau der Ansicht.
                overviews[slug] = (best["overview"] as? String) ?? ""
                if let vote = best["vote_average"] as? Double, vote > 0 {
                    ratings[slug] = vote
                }
                if let id = best["id"] as? Int {
                    tvIDs[slug] = id
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

/// Was der Cover-Index über einen Titel weiß. Kommt komplett aus der ohnehin
/// nötigen TMDB-Suche — keine zusätzlichen Anfragen.
struct CoverDetails: Hashable {
    var poster: URL?
    var backdrop: URL?
    var overview: String?
    var rating: Double?

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
    var title: String?
    var overview: String?
    var still: String?
    var airDate: String?

    var stillURL: URL? { still.flatMap(URL.init(string:)) }
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
    private var missed: Set<String> = []
    private var inFlight: [String: Task<[Int: EpisodeInfo], Never>] = [:]

    private let storeURL: URL
    private var saveTask: Task<Void, Never>?
    private static let maxSeasons = 600
    private static let storeVersion = 1

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
            missed = Set(bag.missed)
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
    /// Gibt bei jedem Fehlschlag ein leeres Ergebnis zurück — ohne Schlüssel,
    /// ohne TMDB-Treffer, bei einer Staffel ohne Nummer („Filme") oder bei
    /// einem Netzfehler. Die Folgenliste steht dann so da wie bisher.
    func load(
        slug: String,
        title: String,
        alternates: [String] = [],
        season: String,
        kind: CatalogProvider
    ) async -> [Int: EpisodeInfo] {
        let key = Self.key(slug, season)
        if let known = seasons[key] { return unpack(known) }
        if missed.contains(key) { return [:] }
        if let running = inFlight[key] { return await running.value }

        let task = Task<[Int: EpisodeInfo], Never> {
            await self.fetch(slug: slug, title: title, alternates: alternates, season: season, kind: kind)
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
        kind: CatalogProvider
    ) async -> [Int: EpisodeInfo] {
        let key = Self.key(slug, season)
        // „Filme" und andere Sonderabschnitte tragen keine Staffelnummer.
        // TMDB kennt zwar Staffel 0 für Specials, aber die Zuordnung wäre
        // geraten — dann lieber nichts anzeigen als das Falsche.
        guard let number = Int(season), number > 0 else {
            missed.insert(key)
            return [:]
        }
        guard let apiKey = TMDBKeyStore.current else { return [:] }
        // Ohne Kennung **nicht** dauerhaft merken: der `missed`-Satz wandert
        // auf die Platte, und ein Titel, den TMDB heute nicht führt, wäre
        // damit für immer abgeschrieben. Die Sperre gegen wiederholte
        // Anfragen hält im Cover-Index, nur für diese Sitzung.
        guard let id = await CoverIndex.shared.tvIDLoading(
            slug: slug,
            title: title,
            alternates: alternates,
            kind: kind
        ) else { return [:] }

        var found = await request(id: id, season: number, apiKey: apiKey, language: "de-DE")
        // TMDB pflegt die deutschen Texte lückenhaft, bei Anime fast gar
        // nicht. Fehlt mehr als die Hälfte, wird die englische Fassung
        // nachgeholt und füllt nur die Lücken — deutsche Texte bleiben stehen.
        if found.isEmpty || found.values.filter({ !($0.overview ?? "").isEmpty }).count * 2 < found.count {
            let english = await request(id: id, season: number, apiKey: apiKey, language: "en-US")
            for (n, info) in english {
                if var mine = found[n] {
                    if (mine.title ?? "").isEmpty { mine.title = info.title }
                    if (mine.overview ?? "").isEmpty { mine.overview = info.overview }
                    if (mine.still ?? "").isEmpty { mine.still = info.still }
                    found[n] = mine
                } else {
                    found[n] = info
                }
            }
        }

        guard !found.isEmpty else {
            missed.insert(key)
            scheduleSave()
            return [:]
        }
        seasons[key] = Dictionary(uniqueKeysWithValues: found.map { (String($0.key), $0.value) })
        scheduleSave()
        return found
    }

    private func request(id: Int, season: Int, apiKey: String, language: String) async -> [Int: EpisodeInfo] {
        guard var comps = URLComponents(string: "https://api.themoviedb.org/3/tv/\(id)/season/\(season)") else { return [:] }
        comps.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "language", value: language),
        ]
        guard let url = comps.url else { return [:] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            // 404 heißt: die Serie stimmt, diese Staffel gibt es dort nicht.
            // Das ist kein Fehler, nur ein leeres Ergebnis.
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return [:] }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let rows = json["episodes"] as? [[String: Any]]
            else { return [:] }
            var out: [Int: EpisodeInfo] = [:]
            for row in rows {
                guard let n = row["episode_number"] as? Int else { continue }
                var still: String?
                if let path = row["still_path"] as? String, !path.isEmpty {
                    // Das Zuschnittsformat von TMDB selbst: 454×254, also
                    // 16:9 — genau die Form, in der die Folgenliste es zeigt.
                    still = "https://image.tmdb.org/t/p/w454_and_h254_bestv2\(path)"
                }
                out[n] = EpisodeInfo(
                    title: row["name"] as? String,
                    overview: row["overview"] as? String,
                    still: still,
                    airDate: row["air_date"] as? String
                )
            }
            return out
        } catch {
            return [:]
        }
    }

    private struct Bag: Codable {
        var seasons: [String: [String: EpisodeInfo]]
        var missed: [String]
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
        var misses = missed
        if misses.count > Self.maxSeasons {
            misses = Set(misses.prefix(Self.maxSeasons))
        }
        let bag = Bag(seasons: kept, missed: Array(misses), version: Self.storeVersion)
        guard let data = try? JSONEncoder().encode(bag) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
