// Die Aufrufe, die Kotlin über die Brücke erreichen kann.
//
// Ein Aufruf pro Zeile in `dispatch`. Neue Funktionen der Android-App kommen
// hier dazu — nicht als zweite Implementierung in Kotlin.
#if os(Android)

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension NoriBridge {
    static func dispatch(op: String, args: Args) async throws -> String {
        switch op {

        // MARK: Einrichtung

        case "init":
            // Muss vor allem anderen kommen: der Kern legt Bibliothek,
            // Cover-Index und Folgen-Index als JSON-Dateien ab, und wo das
            // auf Android ist, weiß nur die App.
            let directory = URL(fileURLWithPath: try args.string("dataDir"), isDirectory: true)
            NoriStorage.directoryOverride = directory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            lock.lock()
            if store == nil { store = LibraryStore(directory: directory) }
            lock.unlock()
            return successRaw("""
            {"schemaVersion":\(LibraryStore.schemaVersion),"hasTMDBKey":\(TMDBKeyStore.current != nil)}
            """)

        // MARK: Katalog und Metadaten

        case "catalog":
            let provider = try args.provider()
            let result = try await AniworldClient.shared.getCatalog(
                provider: provider,
                force: args.bool("force")
            )
            return try success(result)

        case "series":
            let provider = try args.provider()
            let slug = try args.string("slug")
            let detail = try await AniworldClient.shared.getSeries(
                provider: provider,
                slug: slug,
                season: args.optionalString("season")
            )
            return try success(detail)

        case "watch":
            let provider = try args.provider()
            let path = try args.string("path")
            let info = try await AniworldClient.shared.getWatch(provider: provider, path: path)
            return try success(info)

        case "calendar":
            let provider = try args.provider()
            let payload = try await AniworldClient.shared.getCalendar(
                provider: provider,
                force: args.bool("force")
            )
            return try success(payload)

        // MARK: Bilder und Beschreibungen

        case "coverDetails":
            let slug = try args.string("slug")
            let title = try args.string("title")
            let provider = try args.provider()
            let details = await CoverIndex.shared.detailsLoading(slug: slug, title: title, kind: provider)
            return try success(CoverDetailsDTO(details))

        case "coverCached":
            // Ohne Netz: was schon dasteht. Trägt den ersten Aufbau einer
            // Liste, damit Kacheln nicht leer beginnen.
            let slug = try args.string("slug")
            let details = await CoverIndex.shared.details(for: slug)
            return try success(CoverDetailsDTO(details))

        case "coverSource":
            // Letzter Ausweg wie auf Apple: die Detailseite der Quelle lesen.
            let slug = try args.string("slug")
            let provider = try args.provider()
            let url = await CoverIndex.shared.fetchSourceCover(slug: slug, provider: provider)
            return try success(["url": url?.absoluteString])

        case "coverCandidates":
            let title = try args.string("title")
            let provider = try args.provider()
            let list = await CoverIndex.shared.candidates(title: title, kind: provider)
            return try success(list.map { CoverCandidateDTO(url: $0.url.absoluteString, label: $0.label, source: $0.source) })

        case "coverOverride":
            let slug = try args.string("slug")
            await CoverIndex.shared.setOverride(
                slug: slug,
                url: args.optionalString("url").flatMap(URL.init(string:))
            )
            return successRaw("{}")

        case "episodeInfo":
            let slug = try args.string("slug")
            let title = try args.string("title")
            let season = try args.string("season")
            let provider = try args.provider()
            let infos = await EpisodeIndex.shared.load(
                slug: slug,
                title: title,
                alternates: args.strings("alternates"),
                season: season,
                kind: provider
            )
            var out: [String: EpisodeInfo] = [:]
            for (number, info) in infos { out[String(number)] = info }
            return try success(out)

        // MARK: Wiedergabequelle

        case "resolve":
            // Der eigentliche Beweis der Portierung: aus den Hostern einer
            // Folge wird eine abspielbare Adresse samt der Kopfzeilen, die
            // Media3 dafür mitschicken muss.
            let hosters = try args.decode([HosterOption].self, "hosters")
            let provider = try args.provider()
            let source = try await HosterResolver.resolveBest(
                hosters: hosters,
                preferredHoster: args.string("preferredHoster", default: ""),
                preferredLang: args.string("preferredLang", default: "DE"),
                episodePath: args.string("episodePath", default: ""),
                provider: provider
            )
            return try success(PlaySourceDTO(source))

        case "resolveOne":
            // Für den Hosterwechsel im Player: genau dieser Hoster, kein
            // Ausweichen auf einen anderen.
            let option = try args.decode(HosterOption.self, "hoster")
            let provider = try args.provider()
            let source = try await HosterResolver.resolve(
                option,
                episodePath: args.string("episodePath", default: ""),
                provider: provider
            )
            return try success(PlaySourceDTO(source))

        case "hosterOrder":
            // Reihenfolge und Sprachauswahl kommen aus dem Kern, damit die
            // Liste im Player dieselbe ist, die `resolveBest` durchgeht.
            let hosters = try args.decode([HosterOption].self, "hosters")
            let byLang = HosterResolver.pickLang(hosters, pref: args.string("preferredLang", default: "DE"))
            let ordered = HosterResolver.ordered(byLang, preferred: args.optionalString("preferredHoster"))
            return try success(ordered)

        // MARK: Bibliothek

        case "library.snapshot":
            return try success(try withStore { LibrarySnapshot($0) })

        case "library.toggleFavorite":
            let slug = try args.string("slug")
            let title = args.optionalString("title")
            return try success(try withStore { store in
                store.toggleFavorite(slug, title: title)
                return LibrarySnapshot(store)
            })

        case "library.remember":
            let slug = try args.string("slug")
            let title = try args.string("title")
            let provider = try args.provider()
            return try success(try withStore { store in
                store.remember(slug: slug, title: title, provider: provider)
                return LibrarySnapshot(store)
            })

        case "library.upsertProgress":
            let item = try args.decode(WatchProgress.self, "progress")
            return try success(try withStore { store in
                store.upsert(item)
                return LibrarySnapshot(store)
            })

        case "library.setPreferences":
            return try success(try withStore { store in
                if let lang = args.optionalString("langPref") { store.langPref = lang }
                if let hoster = args.optionalString("hosterPref") { store.hosterPref = hoster }
                if let resume = args.raw["resumeEnabled"] as? Bool { store.resumeEnabled = resume }
                if let autoplay = args.raw["autoplayNext"] as? Bool { store.autoplayNext = autoplay }
                if let speed = args.raw["playbackSpeed"] as? Double { store.playbackSpeed = Float(speed) }
                if let raw = args.optionalString("provider"), let value = CatalogProvider(rawValue: raw) {
                    store.provider = value
                }
                if let raw = args.optionalString("scope"), let value = LibraryScope(rawValue: raw) {
                    store.scope = value
                }
                return LibrarySnapshot(store)
            })

        case "library.clearHistory":
            return try success(try withStore { store in
                store.clearHistory()
                return LibrarySnapshot(store)
            })

        case "library.clearProgress":
            return try success(try withStore { store in
                store.clearProgress()
                return LibrarySnapshot(store)
            })

        case "library.continueWatching":
            return try success(try withStore { $0.continueWatching() })

        case "library.nextPlay":
            let slug = try args.string("slug")
            let season = try args.string("season")
            let episodes = try args.decode([Episode].self, "episodes")
            let provider = try args.provider()
            return try success(try withStore { store in
                store.provider = provider
                let next = store.nextPlay(slug: slug, season: season, episodes: episodes)
                return NextPlayDTO(episode: next.episode, resumeAt: next.resumeAt, kind: next.kind)
            })

        case "library.seasonStats":
            let slug = try args.string("slug")
            let season = try args.string("season")
            let episodes = try args.decode([Episode].self, "episodes")
            let provider = try args.provider()
            return try success(try withStore { store in
                store.provider = provider
                let stats = store.seasonStats(slug: slug, season: season, episodes: episodes)
                return SeasonStatsDTO(watched: stats.watched, total: stats.total, percent: stats.pct)
            })

        // MARK: Regeln

        case "rules.resume":
            // Fortschrittsregeln liegen im Kern und werden auf Android nicht
            // nachgebaut: „ab 90 % gilt als gesehen" darf nicht an zwei
            // Stellen stehen und auseinanderlaufen.
            let item = try? args.decode(WatchProgress.self, "progress")
            return try success(RulesDTO(
                complete: isEpisodeComplete(item),
                ratio: watchRatio(item),
                resumeAt: resumePosition(item)
            ))

        default:
            throw BridgeError(kind: "bridge", message: "Unbekannter Aufruf '\(op)'")
        }
    }

    /// Zugriff auf den Store unter Schloss. Wirft, wenn `init` fehlt — das ist
    /// ein Programmierfehler auf Kotlin-Seite und soll auffallen.
    private static func withStore<T>(_ body: (LibraryStore) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let store else {
            throw BridgeError(kind: "bridge", message: "Brücke nicht eingerichtet — 'init' fehlt")
        }
        return try body(store)
    }
}

// MARK: - Datenübergabeformen

/// Was Media3 zum Abspielen braucht.
///
/// `PlaySource` aus dem Kern trägt Adresse, Art, Hoster, Sprache und Referer.
/// Für Android kommen die Kopfzeilen dazu, mit denen der Abruf tatsächlich
/// rausgeht — viele Hoster liefern das Video sonst nicht aus. Sie werden hier
/// gebildet und nicht in Kotlin, damit User-Agent und Referer aus derselben
/// Quelle stammen wie beim Auflösen.
struct PlaySourceDTO: Encodable {
    let kind: String
    let url: String
    let hoster: String
    let lang: String
    let referer: String?
    let origin: String?
    let userAgent: String
    let headers: [String: String]

    init(_ source: PlaySource) {
        kind = source.kind.rawValue
        url = source.url
        hoster = source.hoster
        lang = source.lang
        referer = source.referer
        // Origin ist Schema plus Host des Referers, ohne Pfad. Manche Hoster
        // prüfen ihn zusätzlich, und er lässt sich nicht raten.
        if let referer, let parsed = URL(string: referer), let scheme = parsed.scheme, let host = parsed.host {
            origin = "\(scheme)://\(host)"
        } else {
            origin = nil
        }
        userAgent = NoriOrigin.ua
        var fields = ["User-Agent": NoriOrigin.ua, "Accept-Language": "de-DE,de;q=0.9,en;q=0.8"]
        if let referer { fields["Referer"] = referer }
        if let origin { fields["Origin"] = origin }
        headers = fields
    }
}

struct CoverDetailsDTO: Encodable {
    let poster: String?
    let backdrop: String?
    let overview: String?
    let rating: Double?

    init(_ details: CoverDetails) {
        poster = details.poster?.absoluteString
        backdrop = details.backdrop?.absoluteString
        overview = details.overview
        rating = details.rating
    }
}

struct CoverCandidateDTO: Encodable {
    let url: String
    let label: String
    let source: String
}

struct NextPlayDTO: Encodable {
    let episode: Int
    let resumeAt: Double
    let kind: String
}

struct SeasonStatsDTO: Encodable {
    let watched: Int
    let total: Int
    let percent: Int
}

struct RulesDTO: Encodable {
    let complete: Bool
    let ratio: Double
    let resumeAt: Double
}

/// Der gesamte Bibliotheksstand in einem Zug.
///
/// Jede Änderung gibt ihn frisch zurück. Kotlin hält davon genau eine Kopie
/// in einem `StateFlow`; dadurch kann es zwischen Merkliste, Verlauf und
/// Detailseite keine zwei Wahrheiten geben.
struct LibrarySnapshot: Encodable {
    let schemaVersion: Int
    let favorites: [String]
    let favoriteSource: [String: String]
    let recents: [RecentItem]
    let titles: [String: String]
    let progress: [String: WatchProgress]
    let langPref: String
    let hosterPref: String
    let resumeEnabled: Bool
    let autoplayNext: Bool
    let playbackSpeed: Double
    let provider: String
    let scope: String

    init(_ store: LibraryStore) {
        schemaVersion = LibraryStore.schemaVersion
        favorites = store.favorites
        favoriteSource = store.favoriteSource.mapValues(\.rawValue)
        recents = store.recents
        titles = store.titles
        progress = store.progress
        langPref = store.langPref
        hosterPref = store.hosterPref
        resumeEnabled = store.resumeEnabled
        autoplayNext = store.autoplayNext
        playbackSpeed = Double(store.playbackSpeed)
        provider = store.provider.rawValue
        scope = store.scope.rawValue
    }
}

#endif
