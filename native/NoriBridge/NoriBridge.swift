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

/// Ergebnis eines Aufrufs, immer als JSON — auch der Fehlerfall.
///
/// Eine Zeichenkette statt einer Struktur, weil jede weitere Typüberquerung
/// über JNI eigene Konvertierung bräuchte. JSON kennt Kotlin von sich aus,
/// und der Kern spricht es über `Codable` ohnehin.
private func encode<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(value),
          let text = String(data: data, encoding: .utf8) else {
        return #"{"error":"Antwort ließ sich nicht kodieren"}"#
    }
    return text
}

private func failure(_ message: String) -> String {
    let escaped = message
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: " ")
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

/// Frei zu gebender C-String. Die Kotlin-Seite ruft dafür `nori_free`.
private func cString(_ text: String) -> UnsafeMutablePointer<CChar>? {
    strdup(text)
}

// MARK: - Exportierte C-Schnittstelle

/// Den Katalog einer Quelle laden und als JSON zurückgeben.
///
/// - Parameter providerRaw: `"aniworld"` oder `"serienstream"`.
@_cdecl("nori_catalog_json")
public func nori_catalog_json(_ providerRaw: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let raw = providerRaw.map { String(cString: $0) } ?? CatalogProvider.aniworld.rawValue
    guard let provider = CatalogProvider(rawValue: raw) else {
        return cString(failure("Unbekannte Quelle: \(raw)"))
    }
    let json = blocking {
        do {
            let result = try await AniworldClient.shared.getCatalog(provider: provider)
            // Die Quelle stempeln — der Parser tut das bewusst nicht, und ohne
            // sie wüsste eine Kachel nicht, wohin sie führt.
            let items = result.items.map { item -> CatalogItem in
                var copy = item
                copy.provider = provider
                return copy
            }
            return encode(items)
        } catch {
            return failure(error.localizedDescription)
        }
    }
    return cString(json)
}

/// Die Version des Kerns — der billigste mögliche Aufruf.
///
/// Dient als Lebenszeichen: geht der durch, sind Bibliothek, Swift-Laufzeit
/// und JNI-Anbindung in Ordnung, ohne dass ein Netzzugriff im Spiel wäre.
/// Genau das will man zuerst wissen, wenn eine App mit
/// `UnsatisfiedLinkError` abbricht.
@_cdecl("nori_ping")
public func nori_ping() -> UnsafeMutablePointer<CChar>? {
    let scopes = LibraryScope.allCases.map(\.rawValue).joined(separator: ",")
    return cString("{\"ok\":true,\"scopes\":\"\(scopes)\"}")
}

/// Speicher freigeben, den die Funktionen oben mit `strdup` geholt haben.
///
/// Ohne das leckt jeder Aufruf. Die Kotlin-Seite ruft es im `finally`.
@_cdecl("nori_free")
public func nori_free(_ pointer: UnsafeMutablePointer<CChar>?) {
    free(pointer)
}
