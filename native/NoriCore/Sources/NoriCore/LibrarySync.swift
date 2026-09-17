import Foundation

// Der Geräteabgleich — Ablageform, Konfliktregeln, Zusammenführung.
//
// Hier steht bewusst *keine* Netzwerklogik und kein OAuth. Was in dieser Datei
// liegt, ist reine Rechnung: aus mehreren Ständen wird einer. Genau deshalb
// lässt sie sich testen, und genau deshalb kann `shared/nori-core/src/sync.ts`
// Zeile für Zeile dasselbe tun. Die gemeinsamen Fälle liegen in
// `native/Tests/NoriCoreTests/SyncFixtures.swift` beziehungsweise
// `shared/nori-core/test/sync-fixtures.ts` und sind identisch.
//
// Warum nicht eine Datei mit einem `modifiedAt`, wie es `docs/synchronisation.md`
// ursprünglich vorsah: weil das bei zwei Geräten schon verliert. Der Fernseher
// schreibt den Fortschritt, das iPhone gleichzeitig die Merkliste, beide haben
// denselben älteren Stand geladen — wer zuletzt hochlädt, löscht die Änderung
// des anderen. Deshalb schreibt **jedes Gerät nur seine eigene Datei**, und
// gelesen werden alle.

/// Version der Sync-Metadaten innerhalb einer Bibliotheksdatei.
///
/// Unabhängig von `LibraryStore.schemaVersion`: das Schema beschreibt die
/// Bibliothek, diese Zahl die Regeln, nach denen zwei davon verrechnet werden.
let librarySyncFormatVersion = 1

/// Schutzgrenzen. Keine davon soll im Alltag greifen — sie halten kaputte oder
/// böswillige Fremddateien davon ab, den lokalen Stand zu beschädigen.
enum LibrarySyncLimits {
    /// Eine normale Bibliothek liegt im zweistelligen Kilobyte-Bereich. Alles
    /// jenseits davon wird gar nicht erst geparst.
    static let maxSnapshotBytes = 2 * 1024 * 1024
    static let maxFavorites = 5_000
    /// Wie im Store: der Verlauf ist auf 100 Einträge begrenzt, und der
    /// Abgleich darf daraus keine Tausende machen.
    static let maxRecents = 100
    static let maxProgress = 20_000
    static let maxTitles = 50_000
    /// Wie viele eigene Listen ein Gerätestand höchstens mitbringen darf.
    static let maxLists = 200
    /// Wie weit ein Zeitstempel in der Zukunft liegen darf, bevor er als
    /// kaputte Uhr gilt: 24 Stunden.
    static let futureToleranceMs: Double = 24 * 60 * 60 * 1000
}

/// Wann eine einzelne Einstellung zuletzt geändert wurde.
///
/// Nur der Zeitpunkt, nicht der Wert. Der Wert steht weiterhin genau einmal
/// im Datensatz — `langPref`, `playbackSpeed` und so weiter. Ihn hier ein
/// zweites Mal abzulegen hieße, zwei Quellen für dieselbe Aussage zu führen,
/// die auseinanderlaufen können; stattdessen gewinnt ein Zeitstempel, und
/// genommen wird der Wert aus *derselben* Datei.
struct SyncStamp: Codable, Hashable {
    var updatedAt: Double

    init(updatedAt: Double) { self.updatedAt = updatedAt }
}

/// Ob ein Titel gemerkt ist — einschließlich „nicht mehr".
///
/// `isFavorite == false` ist der Grabstein. Ohne ihn taucht ein entfernter
/// Titel wieder auf, sobald ein Gerät mit älterem Stand synchronisiert: eine
/// Liste allein sagt nur, was da ist, nie, was absichtlich weg ist.
struct FavoriteMark: Codable, Hashable {
    var isFavorite: Bool
    var updatedAt: Double
    /// Wann gemerkt wurde. Trägt `favoriteAddedAt` über den Abgleich, damit
    /// die Sortierung „zuletzt hinzugefügt" auf allen Geräten dieselbe ist.
    var addedAt: Double?

    init(isFavorite: Bool, updatedAt: Double, addedAt: Double? = nil) {
        self.isFavorite = isFavorite
        self.updatedAt = updatedAt
        self.addedAt = addedAt
    }
}

/// Was eine Bibliotheksdatei über ihre Herkunft und ihre Änderungen weiß.
///
/// Alles optional: eine Datei aus Schema v5 hat den Block nicht, und sie muss
/// weiter lesbar bleiben. Fehlende Angaben werden beim Laden ergänzt
/// (`LibraryStore.adoptSyncMeta`), nicht erzwungen.
struct SyncMeta: Codable, Hashable {
    var formatVersion: Int?
    /// Zufällige UUID je Installation. Keine Hardwarekennung, kein Name, kein
    /// Konto — sie dient nur dazu, Dateien auseinanderzuhalten und bei
    /// gleichen Zeitstempeln deterministisch zu entscheiden.
    var deviceId: String?
    var platform: String?
    var appVersion: String?
    var generatedAt: Double?
    /// Wann der Verlauf zuletzt vollständig gelöscht wurde. Fremde Einträge
    /// mit `viewedAt <= historyClearedAt` sind damit erledigt und kommen nicht
    /// zurück.
    var historyClearedAt: Double?
    /// Dasselbe für „Fortschritt löschen".
    var progressClearedAt: Double?
    /// Änderungszeitpunkt je Einstellung, Schlüssel siehe `SyncPreference`.
    var preferences: [String: SyncStamp]?
    /// Merkliste als Zustand statt als Liste, Schlüssel `provider|slug`.
    var favorites: [String: FavoriteMark]?
    /// Einzeln aus dem Verlauf entfernte Titel, Schlüssel `provider|slug`,
    /// Wert der Zeitpunkt des Entfernens. `clearHistory` braucht das nicht —
    /// dafür gibt es `historyClearedAt` —, „aus dem Verlauf nehmen" schon.
    var recentsRemoved: [String: Double]?

    init(
        formatVersion: Int? = nil,
        deviceId: String? = nil,
        platform: String? = nil,
        appVersion: String? = nil,
        generatedAt: Double? = nil,
        historyClearedAt: Double? = nil,
        progressClearedAt: Double? = nil,
        preferences: [String: SyncStamp]? = nil,
        favorites: [String: FavoriteMark]? = nil,
        recentsRemoved: [String: Double]? = nil
    ) {
        self.formatVersion = formatVersion
        self.deviceId = deviceId
        self.platform = platform
        self.appVersion = appVersion
        self.generatedAt = generatedAt
        self.historyClearedAt = historyClearedAt
        self.progressClearedAt = progressClearedAt
        self.preferences = preferences
        self.favorites = favorites
        self.recentsRemoved = recentsRemoved
    }
}

/// Welche Einstellungen abgeglichen werden.
///
/// Nicht abgeglichen wird alles, was zum Gerät gehört und nicht zur Person:
/// Serveradresse, TMDB-Schlüssel, Effektstufe des Fernsehers. Die liegen auf
/// webOS ohnehin in einem eigenen Speicher.
enum SyncPreference: String, CaseIterable {
    case langPref
    case hosterPref
    case resumeEnabled
    case preferredQuality
    case autoplayNext
    case playbackSpeed
    case subtitlePref
    case subtitlesEnabled
    case provider
    case scope
}

/// Die Ablageform der Bibliothek — `library.json` auf Apple, `nori.library`
/// im Speicher des Fernsehers, und dieselbe Form auch in Google Drive.
///
/// Feldnamen sind Vertrag: `shared/nori-core/src/library.ts` legt exakt
/// dieselben ab, und `config/contract.json` führt sie auf.
struct LibraryData: Codable {
    var version: Int?
    var modifiedAt: Double?
    var favorites: [String]
    var recents: [RecentItem]
    var titles: [String: String]
    var progress: [String: WatchProgress]
    var langPref: String?
    var hosterPref: String?
    var resumeEnabled: Bool?
    var autoplayNext: Bool?
    var playbackSpeed: Float?
    var preferredQuality: String?
    /// Bevorzugte Untertitelsprache, z. B. „DE“ oder „EN“. Leer oder „off“ heißt aus.
    /// Neu; ältere Dateien ohne das Feld dekodieren mit „off“.
    var subtitlePref: String?
    /// Ob Untertitel angezeigt werden. Neu; Voreinstellung aus.
    var subtitlesEnabled: Bool?
    var provider: String?
    var scope: String?
    var favoriteSource: [String: String]?
    /// Neu in v5. Optional, damit ältere library.json weiter dekodieren;
    /// fehlt der Eintrag, leitet `backfillAddedAt` ihn aus `favorites` ab.
    var favoriteAddedAt: [String: Double]?
    /// Eigene Listen neben der Merkliste. Optional — eine Bibliothek ohne
    /// `lists` ist gültig. Die bestehende Merkliste (favorites) bleibt der
    /// Sonderfall und wird nicht zu einer dieser Listen.
    var lists: [String: CustomList]?
    /// Neu in v6. Fehlt in jeder älteren Datei und wird beim Laden ergänzt.
    var sync: SyncMeta?
    // `cloudSyncEnabled` und `cloudLastSync` standen hier, solange iCloud
    // eingebaut war. Ältere library.json tragen die Schlüssel weiter;
    // JSONDecoder überliest, was der Typ nicht kennt.

    init(
        version: Int? = nil,
        modifiedAt: Double? = nil,
        favorites: [String] = [],
        recents: [RecentItem] = [],
        titles: [String: String] = [:],
        progress: [String: WatchProgress] = [:],
        langPref: String? = nil,
        hosterPref: String? = nil,
        resumeEnabled: Bool? = nil,
        autoplayNext: Bool? = nil,
        playbackSpeed: Float? = nil,
        preferredQuality: String? = nil,
        subtitlePref: String? = nil,
        subtitlesEnabled: Bool? = nil,
        provider: String? = nil,
        scope: String? = nil,
        favoriteSource: [String: String]? = nil,
        favoriteAddedAt: [String: Double]? = nil,
        lists: [String: CustomList]? = nil,
        sync: SyncMeta? = nil
    ) {
        self.version = version
        self.modifiedAt = modifiedAt
        self.favorites = favorites
        self.recents = recents
        self.titles = titles
        self.progress = progress
        self.langPref = langPref
        self.hosterPref = hosterPref
        self.resumeEnabled = resumeEnabled
        self.autoplayNext = autoplayNext
        self.playbackSpeed = playbackSpeed
        self.preferredQuality = preferredQuality
        self.subtitlePref = subtitlePref
        self.subtitlesEnabled = subtitlesEnabled
        self.provider = provider
        self.scope = scope
        self.favoriteSource = favoriteSource
        self.favoriteAddedAt = favoriteAddedAt
        self.lists = lists
        self.sync = sync
    }
}

/// Ein Wert, der auch fehlen darf, ohne die ganze Datei mitzureißen.
///
/// JSON aus der Cloud ist Fremdmaterial. Ein einziger Fortschrittseintrag mit
/// einem Feld vom falschen Typ würde das synthetisierte `init(from:)` werfen
/// lassen — und damit wäre nicht ein Eintrag verloren, sondern der komplette
/// Stand dieses Geräts. Also wird jeder Eintrag einzeln versucht.
private struct Skippable<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

extension LibraryData {
    /// Nachsichtig dekodieren: fehlende und falsch getippte Felder fallen auf
    /// ihren Vorgabewert zurück, statt die Datei unlesbar zu machen.
    ///
    /// Die synthetisierte Fassung tut das nicht — sie verlangt jedes
    /// nicht-optionale Feld, Vorgabewerte hin oder her. Für die eigene
    /// `library.json` wäre das zu verschmerzen; für vier fremde Dateien aus
    /// Drive nicht: dort entscheidet genau das darüber, ob ein Tippfehler in
    /// einer alten Datei den Abgleich eines ganzen Kontos blockiert.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) -> T? {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? nil
        }

        version = value(.version)
        modifiedAt = value(.modifiedAt)
        favorites = value(.favorites) ?? []
        recents = ((try? container.decodeIfPresent([Skippable<RecentItem>].self, forKey: .recents)) ?? nil)?
            .compactMap(\.value) ?? []
        titles = value(.titles) ?? [:]
        progress = ((try? container.decodeIfPresent([String: Skippable<WatchProgress>].self, forKey: .progress)) ?? nil)?
            .compactMapValues(\.value) ?? [:]
        langPref = value(.langPref)
        hosterPref = value(.hosterPref)
        resumeEnabled = value(.resumeEnabled)
        autoplayNext = value(.autoplayNext)
        playbackSpeed = value(.playbackSpeed)
        preferredQuality = value(.preferredQuality)
        subtitlePref = value(.subtitlePref)
        subtitlesEnabled = value(.subtitlesEnabled)
        provider = value(.provider)
        scope = value(.scope)
        favoriteSource = value(.favoriteSource)
        favoriteAddedAt = value(.favoriteAddedAt)
        lists = ((try? container.decodeIfPresent([String: Skippable<CustomList>].self, forKey: .lists)) ?? nil)?
            .compactMapValues(\.value)
        sync = value(.sync)
    }
}

// MARK: - Schlüssel

/// Schlüssel eines Merklisteneintrags: `provider|slug`.
///
/// Mit Quelle, nicht nur mit Slug. Dieselbe Serie gibt es bei AniWorld und bei
/// Serienstream, und „gemerkt" ist eine Aussage über eine davon — genau wie
/// beim Fortschritt, der seit v2 nach `provider|episodePath` getrennt ist.
func favoriteKey(slug: String, provider: CatalogProvider) -> String {
    "\(provider.rawValue)|\(slug)"
}

/// Schlüssel eines Verlaufseintrags: `provider|slug`.
func recentKey(slug: String, provider: CatalogProvider) -> String {
    "\(provider.rawValue)|\(slug)"
}

/// Den Slug aus einem `provider|slug`-Schlüssel zurückholen.
func slugFromSyncKey(_ key: String) -> String {
    guard let index = key.firstIndex(of: "|") else { return key }
    return String(key[key.index(after: index)...])
}

/// Die Quelle aus einem `provider|slug`-Schlüssel zurückholen.
func providerFromSyncKey(_ key: String) -> CatalogProvider? {
    guard let index = key.firstIndex(of: "|") else { return nil }
    return CatalogProvider(rawValue: String(key[key.startIndex..<index]))
}

// MARK: - Zeitstempel

/// Einen Zeitstempel auf etwas Verwendbares zurechtstutzen.
///
/// Uhren laufen auseinander, und auf einem Fernseher, der ohne Netz startet,
/// laufen sie auch mal auf 1970 oder ins Jahr 2106. Beides ist gefährlich:
/// eine Zukunft von Jahren würde jede echte Änderung für Jahre schlagen und
/// den Abgleich damit einfrieren.
///
/// Deshalb: kein `NaN`, nichts Negatives, und höchstens einen Tag in der
/// Zukunft. Was darüber liegt, gilt als „gerade eben" — das ist die
/// großzügigste Lesart, die trotzdem nicht blockiert.
func sanitizedStamp(_ value: Double?, now: Double) -> Double {
    guard let value, value.isFinite, value > 0 else { return 0 }
    if value > now + LibrarySyncLimits.futureToleranceMs { return now }
    return value
}

// MARK: - Zusammenführen

/// Ein Kandidat mit seinem Rang. Der Rang ist immer ein Paar: Zeitstempel
/// zuerst, danach die Gerätekennung.
///
/// Die zweite Hälfte ist der Grund, warum dieselben Dateien immer dasselbe
/// Ergebnis liefern — egal, in welcher Reihenfolge Google Drive sie
/// herausgibt. Ohne sie entschiede bei gleichem Zeitstempel der Zufall, und
/// zwei Geräte kämen zu verschiedenen Ergebnissen und überschrieben sich
/// gegenseitig endlos.
private struct Ranked<Value> {
    var value: Value
    var stamp: Double
    var deviceId: String
}

private func prefer<Value>(_ current: Ranked<Value>?, _ next: Ranked<Value>) -> Ranked<Value> {
    guard let current else { return next }
    if next.stamp != current.stamp { return next.stamp > current.stamp ? next : current }
    return next.deviceId > current.deviceId ? next : current
}

/// Mehrere Gerätestände zu einem verrechnen.
///
/// Rein: keine Uhr außer `now`, kein Netz, keine Ablage, kein Zustand. Die
/// Reihenfolge der Eingaben ist ohne Bedeutung — `merge(A, B, C)` ist
/// `merge(C, A, B)`. Das ist kein Nebenaspekt, sondern die Eigenschaft, die
/// den Abgleich überhaupt erst verlässlich macht: Drive gibt Dateien in
/// beliebiger Reihenfolge heraus.
///
/// Der lokale Stand ist einer der Eingaben und hat keinen Sonderstatus. Wer
/// zusammenführt, übergibt ihn als erstes Element; das Ergebnis ist trotzdem
/// dasselbe, wenn er als letztes käme.
func mergeLibrarySnapshots(_ snapshots: [LibraryData], now: Double) -> LibraryData {
    let inputs = snapshots.map { normalizedSnapshot($0, now: now) }
    guard !inputs.isEmpty else { return LibraryData(version: LibraryStore.schemaVersion, modifiedAt: 0) }

    // Löschmarken zuerst: sie filtern alles Weitere.
    let historyClearedAt = inputs.compactMap { $0.sync?.historyClearedAt }.max() ?? 0
    let progressClearedAt = inputs.compactMap { $0.sync?.progressClearedAt }.max() ?? 0

    var out = LibraryData(version: LibraryStore.schemaVersion)

    // --- Einstellungen -----------------------------------------------------
    //
    // Je Einstellung gewinnt der jüngste Änderungszeitpunkt, und der Wert
    // kommt aus derselben Datei. Ein globales `modifiedAt` reicht dafür nicht:
    // wer auf dem Mac die Sprache umstellt und auf dem iPhone Autoplay,
    // verlöre sonst eine der beiden Änderungen komplett.
    var preferences: [String: SyncStamp] = [:]
    for preference in SyncPreference.allCases {
        var best: Ranked<LibraryData>?
        for input in inputs {
            // Ohne eigenen Zeitstempel zählt der Stand der ganzen Datei. Das
            // betrifft nur Dateien aus Schema v5, die den Block nicht kennen.
            let stamp = input.sync?.preferences?[preference.rawValue]?.updatedAt ?? input.modifiedAt ?? 0
            best = prefer(best, Ranked(value: input, stamp: stamp, deviceId: input.sync?.deviceId ?? ""))
        }
        guard let winner = best else { continue }
        apply(preference, from: winner.value, to: &out)
        preferences[preference.rawValue] = SyncStamp(updatedAt: winner.stamp)
    }

    // --- Merkliste ---------------------------------------------------------
    var marks: [String: Ranked<FavoriteMark>] = [:]
    for input in inputs {
        let deviceId = input.sync?.deviceId ?? ""
        for (key, mark) in favoriteMarks(of: input) {
            marks[key] = prefer(marks[key], Ranked(value: mark, stamp: mark.updatedAt, deviceId: deviceId))
        }
    }

    var favoriteMarksOut: [String: FavoriteMark] = [:]
    var favoriteEntries: [(slug: String, provider: CatalogProvider, addedAt: Double, updatedAt: Double, deviceId: String)] = []
    for (key, ranked) in marks {
        favoriteMarksOut[key] = ranked.value
        guard ranked.value.isFavorite, let provider = providerFromSyncKey(key) else { continue }
        favoriteEntries.append((
            slug: slugFromSyncKey(key),
            provider: provider,
            addedAt: ranked.value.addedAt ?? ranked.value.updatedAt,
            updatedAt: ranked.value.updatedAt,
            deviceId: ranked.deviceId
        ))
    }

    // Ein Slug kann nur eine Quelle tragen — `favoriteSource` ist nach Slug
    // geschlüsselt, nicht nach Slug und Quelle. Stehen beide Quellen auf
    // „gemerkt", entscheidet der jüngere Eintrag.
    var bySlug: [String: (provider: CatalogProvider, addedAt: Double, updatedAt: Double, deviceId: String)] = [:]
    for entry in favoriteEntries {
        if let existing = bySlug[entry.slug] {
            let keepExisting = existing.updatedAt > entry.updatedAt
                || (existing.updatedAt == entry.updatedAt && existing.deviceId >= entry.deviceId)
            if keepExisting { continue }
        }
        bySlug[entry.slug] = (entry.provider, entry.addedAt, entry.updatedAt, entry.deviceId)
    }

    // Sortiert wie im Store: zuletzt Gemerktes vorn. Bei gleichem Zeitpunkt
    // entscheidet der Slug, damit die Reihenfolge nicht von der Hash-Ordnung
    // eines Dictionaries abhängt.
    let ordered = bySlug
        .map { (slug: $0.key, info: $0.value) }
        .sorted { lhs, rhs in
            lhs.info.addedAt != rhs.info.addedAt ? lhs.info.addedAt > rhs.info.addedAt : lhs.slug < rhs.slug
        }
        .prefix(LibrarySyncLimits.maxFavorites)

    out.favorites = ordered.map(\.slug)
    out.favoriteSource = Dictionary(uniqueKeysWithValues: ordered.map { ($0.slug, $0.info.provider.rawValue) })
    out.favoriteAddedAt = Dictionary(uniqueKeysWithValues: ordered.map { ($0.slug, $0.info.addedAt) })

    // --- Fortschritt -------------------------------------------------------
    //
    // Identität wie überall sonst: `provider|normalisierter episodePath`.
    // Jüngstes `updatedAt` gewinnt, bei Gleichstand die größere Gerätekennung.
    var progress: [String: Ranked<WatchProgress>] = [:]
    for input in inputs {
        let deviceId = input.sync?.deviceId ?? ""
        for item in input.progress.values {
            guard item.updatedAt > progressClearedAt else { continue }
            let key = progressKey(path: item.episodePath, provider: item.provider)
            progress[key] = prefer(progress[key], Ranked(value: item, stamp: item.updatedAt, deviceId: deviceId))
        }
    }
    out.progress = progress
        .sorted { $0.value.stamp > $1.value.stamp }
        .prefix(LibrarySyncLimits.maxProgress)
        .reduce(into: [String: WatchProgress]()) { $0[$1.key] = $1.value.value }

    // --- Verlauf -----------------------------------------------------------
    var removed: [String: Double] = [:]
    for input in inputs {
        for (key, stamp) in input.sync?.recentsRemoved ?? [:] {
            removed[key] = max(removed[key] ?? 0, stamp)
        }
    }

    var recents: [String: Ranked<RecentItem>] = [:]
    for input in inputs {
        let deviceId = input.sync?.deviceId ?? ""
        let fallback = input.provider.flatMap(CatalogProvider.init(rawValue:)) ?? .aniworld
        for item in input.recents {
            let key = recentKey(slug: item.slug, provider: item.provider ?? fallback)
            guard item.viewedAt > historyClearedAt, item.viewedAt > (removed[key] ?? 0) else { continue }
            recents[key] = prefer(recents[key], Ranked(value: item, stamp: item.viewedAt, deviceId: deviceId))
        }
    }
    out.recents = recents
        .sorted { lhs, rhs in
            lhs.value.stamp != rhs.value.stamp ? lhs.value.stamp > rhs.value.stamp : lhs.key < rhs.key
        }
        .prefix(LibrarySyncLimits.maxRecents)
        .map(\.value.value)

    // Grabsteine, die `historyClearedAt` ohnehin schon erschlägt, fallen weg.
    // Sonst wüchse die Datei mit jedem einzeln entfernten Eintrag für immer.
    removed = removed.filter { $0.value > historyClearedAt }

    // --- Titel -------------------------------------------------------------
    //
    // Die Zuordnung Slug → Anzeigename. Keine Konfliktquelle im engeren Sinn;
    // bei zwei Schreibweisen gewinnt die aus der jüngeren Datei.
    var titles: [String: Ranked<String>] = [:]
    for input in inputs {
        let deviceId = input.sync?.deviceId ?? ""
        let stamp = input.sync?.generatedAt ?? input.modifiedAt ?? 0
        for (slug, title) in input.titles where !title.isEmpty {
            titles[slug] = prefer(titles[slug], Ranked(value: title, stamp: stamp, deviceId: deviceId))
        }
    }
    out.titles = titles.prefix(LibrarySyncLimits.maxTitles).reduce(into: [String: String]()) { $0[$1.key] = $1.value.value }

    // --- Eigene Listen -------------------------------------------------------
    //
    // Je Liste gewinnt der jüngste updatedAt; bei Gleichstand die größere
    // deviceId. Die Listeneinträge werden als Ganzes übernommen — eine Liste
    // ist eine geordnete Menge, und ein Mischen einzelner Einträge zweier
    // Geräte würde die Reihenfolge zerstören. Wer auf zwei Geräten dieselbe
    // Liste pflegt, gewinnt der jüngste Stand.
    var lists: [String: Ranked<CustomList>] = [:]
    for input in inputs {
        let deviceId = input.sync?.deviceId ?? ""
        for (id, list) in input.lists ?? [:] {
            let stamp = sanitizedStamp(list.updatedAt, now: now)
            lists[id] = prefer(lists[id], Ranked(value: list, stamp: stamp, deviceId: deviceId))
        }
    }
    out.lists = lists
        .sorted { lhs, rhs in
            lhs.value.stamp != rhs.value.stamp ? lhs.value.stamp > rhs.value.stamp : lhs.key < rhs.key
        }
        .prefix(LibrarySyncLimits.maxLists)
        .reduce(into: [String: CustomList]()) { $0[$1.key] = $1.value.value }

    out.modifiedAt = inputs.compactMap(\.modifiedAt).max() ?? 0
    out.sync = SyncMeta(
        formatVersion: librarySyncFormatVersion,
        historyClearedAt: historyClearedAt,
        progressClearedAt: progressClearedAt,
        preferences: preferences,
        favorites: favoriteMarksOut,
        recentsRemoved: removed
    )
    return out
}

/// Die Merkliste einer Datei als Zustandsabbildung — auch dann, wenn die Datei
/// den Block gar nicht hat.
///
/// Der zweite Fall ist der wichtige: eine Datei aus Schema v5 trägt nur eine
/// Liste. Sie wird hier zu lauter `isFavorite = true` mit dem Merkzeitpunkt
/// als Rang. Damit lässt sich ein alter Stand mit einem neuen verrechnen, ohne
/// dass die alte Liste jeden Grabstein des neuen überschreibt — ein
/// Grabstein von heute schlägt einen Merkzeitpunkt von gestern.
private func favoriteMarks(of input: LibraryData) -> [String: FavoriteMark] {
    if let marks = input.sync?.favorites, !marks.isEmpty { return marks }
    let fallbackProvider = input.provider.flatMap(CatalogProvider.init(rawValue:)) ?? .aniworld
    var out: [String: FavoriteMark] = [:]
    for slug in input.favorites {
        let provider = input.favoriteSource?[slug].flatMap(CatalogProvider.init(rawValue:)) ?? fallbackProvider
        let addedAt = input.favoriteAddedAt?[slug] ?? input.modifiedAt ?? 0
        out[favoriteKey(slug: slug, provider: provider)] = FavoriteMark(
            isFavorite: true,
            updatedAt: addedAt,
            addedAt: addedAt
        )
    }
    return out
}

private func apply(_ preference: SyncPreference, from source: LibraryData, to target: inout LibraryData) {
    switch preference {
    case .langPref: target.langPref = source.langPref
    case .hosterPref: target.hosterPref = source.hosterPref
    case .resumeEnabled: target.resumeEnabled = source.resumeEnabled
    case .preferredQuality: target.preferredQuality = source.preferredQuality
    case .autoplayNext: target.autoplayNext = source.autoplayNext
    case .playbackSpeed: target.playbackSpeed = source.playbackSpeed
    case .subtitlePref: target.subtitlePref = source.subtitlePref
    case .subtitlesEnabled: target.subtitlesEnabled = source.subtitlesEnabled
    case .provider: target.provider = source.provider
    case .scope: target.scope = source.scope
    }
}

/// Eine Fremddatei auf brauchbare Werte zurechtstutzen, bevor sie in die
/// Rechnung geht.
///
/// Was hier durchfällt, ist einzeln unbrauchbar — nicht die ganze Datei. Ein
/// Fortschrittseintrag ohne Pfad verschwindet, der Rest bleibt. Eine Datei
/// komplett zu verwerfen, weil ein Feld nicht stimmt, wäre der teurere Fehler.
func normalizedSnapshot(_ raw: LibraryData, now: Double) -> LibraryData {
    var out = raw
    out.modifiedAt = sanitizedStamp(raw.modifiedAt, now: now)

    var progress: [String: WatchProgress] = [:]
    for value in raw.progress.values {
        var item = value
        item.episodePath = normalizeEpisodePath(item.episodePath)
        guard !item.episodePath.isEmpty, !item.slug.isEmpty else { continue }
        item.provider = item.provider ?? providerFromPath(item.episodePath)
        item.updatedAt = sanitizedStamp(item.updatedAt, now: now)
        item.positionSec = item.positionSec.isFinite ? max(0, item.positionSec) : 0
        item.durationSec = item.durationSec.isFinite ? max(0, item.durationSec) : 0
        let key = progressKey(path: item.episodePath, provider: item.provider)
        if let existing = progress[key], existing.updatedAt >= item.updatedAt { continue }
        progress[key] = item
    }
    out.progress = progress

    out.recents = raw.recents
        .filter { !$0.slug.isEmpty }
        .map { item in
            var next = item
            next.viewedAt = sanitizedStamp(item.viewedAt, now: now)
            return next
        }

    out.favorites = raw.favorites.filter { !$0.isEmpty }
    out.titles = raw.titles.filter { !$0.key.isEmpty && !$0.value.isEmpty }

    // Werte, die der Enum nicht kennt, fliegen raus statt die App auf einen
    // unbekannten Zustand zu setzen.
    if let provider = raw.provider, CatalogProvider(rawValue: provider) == nil { out.provider = nil }
    if let scope = raw.scope, LibraryScope(rawValue: scope) == nil { out.scope = nil }
    if let speed = raw.playbackSpeed, !speed.isFinite || speed <= 0 || speed > 4 { out.playbackSpeed = nil }

    var meta = raw.sync ?? SyncMeta()
    meta.generatedAt = sanitizedStamp(meta.generatedAt, now: now)
    meta.historyClearedAt = sanitizedStamp(meta.historyClearedAt, now: now)
    meta.progressClearedAt = sanitizedStamp(meta.progressClearedAt, now: now)
    meta.preferences = (meta.preferences ?? [:]).reduce(into: [String: SyncStamp]()) { acc, pair in
        guard SyncPreference(rawValue: pair.key) != nil else { return }
        acc[pair.key] = SyncStamp(updatedAt: sanitizedStamp(pair.value.updatedAt, now: now))
    }
    meta.favorites = (meta.favorites ?? [:]).reduce(into: [String: FavoriteMark]()) { acc, pair in
        guard providerFromSyncKey(pair.key) != nil, !slugFromSyncKey(pair.key).isEmpty else { return }
        var mark = pair.value
        mark.updatedAt = sanitizedStamp(mark.updatedAt, now: now)
        mark.addedAt = mark.addedAt.map { sanitizedStamp($0, now: now) }
        acc[pair.key] = mark
    }
    meta.recentsRemoved = (meta.recentsRemoved ?? [:]).reduce(into: [String: Double]()) { acc, pair in
        acc[pair.key] = sanitizedStamp(pair.value, now: now)
    }
    out.sync = meta
    return out
}
