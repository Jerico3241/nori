import Foundation
@testable import NoriCore

// Die Brücke vom Kotlin- zum Swift-Kern.
//
// Bewusst **ohne** JNI-Typen: hier steht reines C-ABI, und der eigentliche
// JNI-Shim liegt als C-Datei im Android-Projekt, wo `jni.h` ohnehin zu Hause
// ist. Der Grund ist der Apple-Testlauf — ein C-Target mit `#include <jni.h>`
// in diesem Paket würde `swift test` auf dem Mac zerlegen, wo es kein NDK
// gibt.
//
// `@testable`, weil der geteilte Kern keine einzige `public`-Deklaration hat:
// er wurde bisher immer *in* die App übersetzt, nie als Bibliothek dagegen
// gelinkt. Ihn dafür durchgehend `public` zu machen hieße, fünf byte-gleiche
// Dateien anzufassen, die zwischen iOS und macOS identisch bleiben müssen —
// für eine Eigenschaft, die auf Apple niemand braucht.
//
// ## Warum hier blockiert wird
//
// JNI ist synchrones C. Der Kern ist ein `actor` mit `async throws`. Etwas
// muss die beiden Welten verbinden, und an dieser Stelle ist es ein
// Semaphor: der aufrufende Java-Thread wartet, bis die Task fertig ist.
//
// Das ist genau so lange richtig, wie Kotlin diese Funktionen **nicht** auf
// dem Main-Thread aufruft — sonst steht die Oberfläche. Die Kotlin-Seite ruft
// sie deshalb aus einem `Dispatchers.IO`-Kontext auf; das ist keine Feinheit,
// sondern Bedingung.
//
// ## Antwortformat
//
// Immer JSON, auch im Fehlerfall: `{"error":"…"}`. Kotlin unterscheidet am
// führenden Zeichen, ob eine Liste oder ein Fehlerobjekt kam. Eine
// Zeichenkette statt einer Struktur, weil jede weitere Typüberquerung über
// JNI eigene Konvertierung bräuchte — JSON kennt Kotlin von sich aus, und
// der Kern spricht es über `Codable` ohnehin.

// MARK: - Werkzeug

private let encoder: JSONEncoder = {
    let e = JSONEncoder()
    return e
}()

private func encode<T: Encodable>(_ value: T) -> String {
    guard let data = try? encoder.encode(value),
          let text = String(data: data, encoding: .utf8) else {
        return failure("Antwort ließ sich nicht kodieren")
    }
    return text
}

private func failure(_ message: String) -> String {
    let escaped = message
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
    return "{\"error\":\"\(escaped)\"}"
}

/// Eine `async`-Aufgabe von einem synchronen Thread aus zu Ende führen.
///
/// `DispatchSemaphore` und nicht `Task.sync` (das es nicht gibt): der Aufruf
/// kommt aus Java, dort läuft keine Swift-Concurrency-Umgebung, die man
/// betreten könnte.
private func blocking(_ work: @escaping () async -> String) -> String {
    let semaphore = DispatchSemaphore(value: 0)
    // `nonisolated(unsafe)`, weil der Zugriff durch das Semaphor bereits
    // geordnet ist: geschrieben wird vor `signal`, gelesen nach `wait`.
    nonisolated(unsafe) var output = failure("Aufruf ohne Ergebnis")
    Task {
        output = await work()
        semaphore.signal()
    }
    semaphore.wait()
    return output
}

private func cString(_ text: String) -> UnsafeMutablePointer<CChar>? { strdup(text) }

private func str(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.map { String(cString: $0) } ?? ""
}

private func provider(_ raw: String) -> CatalogProvider? {
    CatalogProvider(rawValue: raw)
}

// MARK: - Bibliothek
//
// `LibraryStore` ist `@Observable`, aber weder Actor noch `@MainActor` — auf
// Apple lebt sie im Hauptthread der App. Hier kommen die Aufrufe aus einem
// beliebigen Java-Thread, deshalb liegt jeder Zugriff auf einer eigenen
// seriellen Queue. Ohne das wären gleichzeitige Lese- und Schreibzugriffe aus
// zwei Kotlin-Coroutinen ein Datenrennen — und zwar eines, das erst als
// verlorener Fortschritt auffällt, nicht als Absturz.

private let libraryQueue = DispatchQueue(label: "to.nori.bridge.library")
nonisolated(unsafe) private var libraryStore: LibraryStore?

private func withLibrary<T>(_ body: (LibraryStore) -> T) -> T {
    libraryQueue.sync {
        if libraryStore == nil { libraryStore = LibraryStore() }
        return body(libraryStore!)
    }
}

/// Was die Oberfläche über die Bibliothek wissen muss, in einem Zug.
private struct LibrarySnapshot: Encodable {
    var favorites: [String]
    var titles: [String: String]
    var recents: [RecentItem]
    var continueWatching: [WatchProgress]
    var langPref: String
    var hosterPref: String
    var favoriteSource: [String: String]
}

// MARK: - Exportierte C-Schnittstelle

/// Lebenszeichen ohne Netzzugriff.
///
/// Der billigste mögliche Aufruf: geht der durch, sind Bibliothek,
/// Swift-Laufzeit und JNI-Anbindung in Ordnung. Genau das will man zuerst
/// wissen, wenn eine App mit `UnsatisfiedLinkError` abbricht.
@_cdecl("nori_ping")
public func nori_ping() -> UnsafeMutablePointer<CChar>? {
    let scopes = LibraryScope.allCases.map(\.rawValue).joined(separator: ",")
    return cString("{\"ok\":true,\"scopes\":\"\(scopes)\"}")
}

/// Wohin der Kern seine Bibliothek schreibt.
///
/// Auf Apple ist das „Application Support"; auf Android löst
/// `FileManager` denselben Aufruf in die App-Sandbox auf. Diagnose, damit ein
/// verlorener Merkzettel nicht geraten werden muss.
@_cdecl("nori_storage_path")
public func nori_storage_path() -> UnsafeMutablePointer<CChar>? {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    return cString("{\"path\":\"\(dir.appendingPathComponent("Nori").path)\"}")
}

/// Den Katalog einer Quelle laden.
@_cdecl("nori_catalog_json")
public func nori_catalog_json(_ providerRaw: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let raw = str(providerRaw)
    guard let source = provider(raw) else { return cString(failure("Unbekannte Quelle: \(raw)")) }
    return cString(blocking {
        do {
            let result = try await AniworldClient.shared.getCatalog(provider: source)
            // Die Quelle stempeln — der Parser tut das bewusst nicht, und ohne
            // sie wüsste eine Kachel nicht, wohin sie führt.
            let items = result.items.map { item -> CatalogItem in
                var copy = item
                copy.provider = source
                return copy
            }
            return encode(items)
        } catch {
            return failure(error.localizedDescription)
        }
    })
}

/// Die Detailseite einer Serie: Beschreibung, Staffeln, Folgen.
@_cdecl("nori_series_json")
public func nori_series_json(
    _ providerRaw: UnsafePointer<CChar>?,
    _ slugRaw: UnsafePointer<CChar>?,
    _ seasonRaw: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let raw = str(providerRaw)
    guard let source = provider(raw) else { return cString(failure("Unbekannte Quelle: \(raw)")) }
    let slug = str(slugRaw)
    let season = str(seasonRaw)
    return cString(blocking {
        do {
            let detail = try await AniworldClient.shared.getSeries(
                provider: source,
                slug: slug,
                season: season.isEmpty ? nil : season
            )
            return encode(detail)
        } catch {
            return failure(error.localizedDescription)
        }
    })
}

/// Der Kalender einer Quelle.
@_cdecl("nori_calendar_json")
public func nori_calendar_json(_ providerRaw: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let raw = str(providerRaw)
    guard let source = provider(raw) else { return cString(failure("Unbekannte Quelle: \(raw)")) }
    return cString(blocking {
        do {
            let payload = try await AniworldClient.shared.getCalendar(provider: source)
            let stamped = { (rows: [AiringEntry]) -> [AiringEntry] in
                rows.map { row in
                    var copy = row
                    copy.provider = source
                    return copy
                }
            }
            return encode(CalendarPayload(
                upcoming: stamped(payload.upcoming),
                recent: stamped(payload.recent),
                fetchedAt: payload.fetchedAt
            ))
        } catch {
            return failure(error.localizedDescription)
        }
    })
}

/// Einen abspielbaren Stream für eine Folge besorgen.
///
/// Der teuerste Aufruf der Brücke: erst die Folgenseite holen, dann jeden
/// Hoster der Reihe nach probieren, bis einer ein Video liefert. Hoster
/// ändern ihre Seiten jederzeit — schlägt das fehl, liegt es häufig dort und
/// nicht am Nori-Code.
@_cdecl("nori_resolve_json")
public func nori_resolve_json(
    _ providerRaw: UnsafePointer<CChar>?,
    _ pathRaw: UnsafePointer<CChar>?,
    _ langRaw: UnsafePointer<CChar>?,
    _ hosterRaw: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let raw = str(providerRaw)
    guard let source = provider(raw) else { return cString(failure("Unbekannte Quelle: \(raw)")) }
    let path = normalizeEpisodePath(str(pathRaw))
    let lang = str(langRaw).isEmpty ? "DE" : str(langRaw)
    let hoster = str(hosterRaw).isEmpty ? "VOE" : str(hosterRaw)
    return cString(blocking {
        do {
            let info = try await AniworldClient.shared.getWatch(provider: source, path: path)
            let play = try await HosterResolver.resolveBest(
                hosters: info.hosters,
                preferredHoster: hoster,
                preferredLang: lang,
                episodePath: path,
                provider: source
            )
            return encode(play)
        } catch {
            return failure(error.localizedDescription)
        }
    })
}

/// Die Hoster-Auswahl einer Folge, ohne aufzulösen — für den Umschalter im
/// Player.
@_cdecl("nori_watch_json")
public func nori_watch_json(
    _ providerRaw: UnsafePointer<CChar>?,
    _ pathRaw: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let raw = str(providerRaw)
    guard let source = provider(raw) else { return cString(failure("Unbekannte Quelle: \(raw)")) }
    let path = normalizeEpisodePath(str(pathRaw))
    return cString(blocking {
        do {
            return encode(try await AniworldClient.shared.getWatch(provider: source, path: path))
        } catch {
            return failure(error.localizedDescription)
        }
    })
}

/// Die vollständige Adresse eines Covers aus dem Pfad, den die Quelle nennt.
@_cdecl("nori_cover_url")
public func nori_cover_url(
    _ providerRaw: UnsafePointer<CChar>?,
    _ pathRaw: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    guard let source = provider(str(providerRaw)) else { return cString("") }
    let url = AniworldClient.coverURL(str(pathRaw), provider: source)
    return cString(url?.absoluteString ?? "")
}

// MARK: - Bibliothek

@_cdecl("nori_library_json")
public func nori_library_json() -> UnsafeMutablePointer<CChar>? {
    let snapshot = withLibrary { store in
        LibrarySnapshot(
            favorites: store.favorites,
            titles: store.titles,
            recents: store.recents,
            continueWatching: store.continueWatching(),
            langPref: store.langPref,
            hosterPref: store.hosterPref,
            favoriteSource: store.favoriteSource.mapValues(\.rawValue)
        )
    }
    return cString(encode(snapshot))
}

/// Merkliste umschalten. Gibt den neuen Zustand zurück, damit die Oberfläche
/// nicht raten muss.
@_cdecl("nori_favorite_toggle")
public func nori_favorite_toggle(
    _ slugRaw: UnsafePointer<CChar>?,
    _ titleRaw: UnsafePointer<CChar>?,
    _ providerRaw: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let slug = str(slugRaw)
    let title = str(titleRaw)
    let source = provider(str(providerRaw))
    let isFavorite = withLibrary { store in
        if let source { store.provider = source }
        store.toggleFavorite(slug, title: title.isEmpty ? nil : title)
        return store.isFavorite(slug)
    }
    return cString("{\"favorite\":\(isFavorite)}")
}

/// Einen Titel im Verlauf vermerken.
@_cdecl("nori_remember")
public func nori_remember(
    _ slugRaw: UnsafePointer<CChar>?,
    _ titleRaw: UnsafePointer<CChar>?,
    _ providerRaw: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let slug = str(slugRaw)
    let title = str(titleRaw)
    let source = provider(str(providerRaw))
    withLibrary { $0.remember(slug: slug, title: title, provider: source) }
    return cString("{\"ok\":true}")
}

/// Wiedergabefortschritt schreiben. Erwartet einen kodierten `WatchProgress`.
@_cdecl("nori_progress_put")
public func nori_progress_put(_ jsonRaw: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let json = str(jsonRaw)
    guard let data = json.data(using: .utf8),
          let item = try? JSONDecoder().decode(WatchProgress.self, from: data) else {
        return cString(failure("Fortschritt nicht lesbar"))
    }
    withLibrary { $0.upsert(item) }
    return cString("{\"ok\":true}")
}

/// Den Fortschritt zu einer Folge lesen.
@_cdecl("nori_progress_get")
public func nori_progress_get(
    _ pathRaw: UnsafePointer<CChar>?,
    _ providerRaw: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let path = str(pathRaw)
    let source = provider(str(providerRaw))
    let found = withLibrary { $0.progress(forPath: path, provider: source) }
    guard let found else { return cString("null") }
    return cString(encode(found))
}

/// Sprach- und Hoster-Vorgabe setzen.
@_cdecl("nori_prefs_put")
public func nori_prefs_put(
    _ langRaw: UnsafePointer<CChar>?,
    _ hosterRaw: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let lang = str(langRaw)
    let hoster = str(hosterRaw)
    withLibrary { store in
        if !lang.isEmpty { store.langPref = lang }
        if !hoster.isEmpty { store.hosterPref = hoster }
    }
    return cString("{\"ok\":true}")
}

/// Verlauf beziehungsweise Fortschritt leeren — für die Einstellungen.
@_cdecl("nori_library_clear")
public func nori_library_clear(_ whatRaw: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let what = str(whatRaw)
    withLibrary { store in
        switch what {
        case "history": store.clearHistory()
        case "progress": store.clearProgress()
        default: break
        }
    }
    return cString("{\"ok\":true}")
}

/// Speicher freigeben, den die Funktionen oben mit `strdup` geholt haben.
///
/// Ohne das leckt jeder Aufruf. Die Kotlin-Seite ruft es im `finally`.
@_cdecl("nori_free")
public func nori_free(_ pointer: UnsafeMutablePointer<CChar>?) {
    free(pointer)
}
