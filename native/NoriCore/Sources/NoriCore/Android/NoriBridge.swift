// Der Übergang von NoriCore nach Kotlin.
//
// Diese Datei ist der einzige Ort im geteilten Kern, der Android kennt, und
// sie steht deshalb vollständig in `#if os(Android)`. Für iOS und macOS ist
// sie leer — die Xcode-Projekte listen ihre Quellen einzeln auf und sehen sie
// ohnehin nicht.
//
// ## Warum eine Zeichenkette und kein Objektgraph
//
// Über JNI ließen sich auch Objekte reichen. Das hieße: für jedes Modell eine
// Java-Klasse, für jedes Feld ein Getter, und bei jeder Änderung an
// `Models.swift` dieselbe Änderung noch zweimal. Genau das soll die
// Portierung vermeiden.
//
// Die Modelle sind bereits `Codable`. Damit ist die billigste tragfähige
// Grenze eine einzige C-Funktion, die JSON hinein und JSON heraus reicht:
//
//     const char *nori_bridge_call(const char *request);
//     void        nori_bridge_free(char *response);
//
// Kotlin dekodiert mit kotlinx.serialization dieselben Felder. Kommt in
// `Models.swift` ein optionales Feld dazu, baut beide Seiten weiter.
//
// ## Warum blockierend
//
// Der Kern ist durchgängig `async`. Eine C-Funktion ist es nicht. Der Aufruf
// startet deshalb eine Task und wartet auf einem Semaphor. Das ist erlaubt,
// weil der aufrufende Thread ein JNI-Thread aus Kotlins `Dispatchers.IO` ist
// und nicht zum kooperativen Pool von Swift Concurrency gehört: die Task
// läuft auf einem anderen Thread weiter, blockiert wird nur der Anrufer.
// Auf Kotlin-Seite steht der Aufruf grundsätzlich in `withContext(IO)`.
#if os(Android)

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - C-Schnittstelle

/// Einziger Einstiegspunkt. Nimmt eine JSON-Anfrage, gibt eine JSON-Antwort
/// zurück. Der Rückgabepuffer gehört danach dem Aufrufer und muss über
/// `nori_bridge_free` freigegeben werden.
@_cdecl("nori_bridge_call")
public func nori_bridge_call(_ request: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let text = request.map { String(cString: $0) } ?? ""
    return NoriBridge.copyToC(NoriBridge.callBlocking(text))
}

/// Gibt frei, was `nori_bridge_call` zurückgegeben hat.
@_cdecl("nori_bridge_free")
public func nori_bridge_free(_ pointer: UnsafeMutablePointer<CChar>?) {
    pointer?.deallocate()
}

// MARK: - Vermittlung

enum NoriBridge {
    /// Fehler der Brücke selbst — nicht die des Kerns.
    struct BridgeError: Error {
        let kind: String
        let message: String
    }

    // Der Store ist eine Klasse ohne eigene Isolation und wird von jedem
    // JNI-Thread erreicht. Ein Schloss reicht: die Zugriffe sind kurz und
    // enden in einem Dateischreibvorgang.
    private static let lock = NSLock()
    private nonisolated(unsafe) static var store: LibraryStore?

    // MARK: Puffer

    /// Kopiert eine Zeichenkette in einen nullterminierten C-Puffer.
    ///
    /// Bewusst ohne `strdup`: das käme aus Bionic und macht die Datei von
    /// einem weiteren Modulimport abhängig, den es auf Apple nicht gibt.
    static func copyToC(_ text: String) -> UnsafeMutablePointer<CChar>? {
        let bytes = Array(text.utf8)
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count + 1)
        bytes.withUnsafeBufferPointer { source in
            buffer.withMemoryRebound(to: UInt8.self, capacity: bytes.count + 1) { target in
                if let base = source.baseAddress { target.update(from: base, count: bytes.count) }
            }
        }
        buffer[bytes.count] = 0
        return buffer
    }

    // MARK: Ablauf

    /// Ablage für das Ergebnis der Task.
    ///
    /// Eine lokale `var` täte es nicht: sie über eine `Task`-Grenze zu
    /// beschreiben ist genau das Muster, das der Nebenläufigkeitsprüfer
    /// bemängelt. Der Kasten macht die Zuweisung eindeutig, und der Semaphor
    /// ist die Synchronisation — geschrieben wird einmal, gelesen erst danach.
    private final class Result: @unchecked Sendable {
        var value = ""
    }

    static func callBlocking(_ requestJSON: String) -> String {
        let semaphore = DispatchSemaphore(value: 0)
        let result = Result()
        Task.detached(priority: .userInitiated) {
            result.value = await handle(requestJSON)
            semaphore.signal()
        }
        semaphore.wait()
        return result.value
    }

    static func handle(_ requestJSON: String) async -> String {
        do {
            let args = try Args(requestJSON)
            let op = try args.string("op")
            return try await dispatch(op: op, args: args)
        } catch let error as BridgeError {
            return failure(kind: error.kind, message: error.message)
        } catch let error as NoriError {
            return failure(kind: error.bridgeKind, message: error.errorDescription ?? "Unbekannter Fehler")
        } catch {
            return failure(kind: "unknown", message: error.localizedDescription)
        }
    }

    // MARK: Antworten

    static func success(_ payload: Data) -> String {
        "{\"ok\":true,\"data\":\(String(decoding: payload, as: UTF8.self))}"
    }

    static func success<T: Encodable>(_ value: T) throws -> String {
        success(try encoder.encode(value))
    }

    static func successRaw(_ json: String) -> String {
        "{\"ok\":true,\"data\":\(json)}"
    }

    static func failure(kind: String, message: String) -> String {
        let escaped = escape(message)
        return "{\"ok\":false,\"error\":{\"kind\":\"\(kind)\",\"message\":\"\(escaped)\"}}"
    }

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count + 8)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
}

// MARK: - Fehlerklassen für Kotlin

extension NoriError {
    /// Damit die Oberfläche „kein Netz" von „Hoster liefert nichts"
    /// unterscheiden kann, ohne die Meldung zu lesen.
    var bridgeKind: String {
        switch self {
        case .network: return "network"
        case .parse: return "parse"
        case .blocked: return "blocked"
        case .notFound: return "notFound"
        case .hoster: return "hoster"
        }
    }
}

// MARK: - Argumente

extension NoriBridge {
    /// Schmaler Zugriff auf die Anfrage.
    ///
    /// `JSONSerialization` statt eines `Codable`-Typs je Aufruf: die Anfragen
    /// unterscheiden sich stark, und ein Typ pro Aufruf wäre dreimal so viel
    /// Text für dieselbe Wirkung. Getippt wird dort, wo es zählt — bei den
    /// Modellen, die in beide Richtungen gehen.
    struct Args {
        let raw: [String: Any]

        init(_ json: String) throws {
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw BridgeError(kind: "bridge", message: "Anfrage ist kein JSON-Objekt") }
            raw = object
        }

        func string(_ key: String) throws -> String {
            guard let value = raw[key] as? String else {
                throw BridgeError(kind: "bridge", message: "Feld '\(key)' fehlt oder ist kein Text")
            }
            return value
        }

        func string(_ key: String, default fallback: String) -> String {
            (raw[key] as? String) ?? fallback
        }

        func optionalString(_ key: String) -> String? {
            guard let value = raw[key] as? String, !value.isEmpty else { return nil }
            return value
        }

        func bool(_ key: String, default fallback: Bool = false) -> Bool {
            (raw[key] as? Bool) ?? fallback
        }

        func int(_ key: String, default fallback: Int = 0) -> Int {
            (raw[key] as? Int) ?? (raw[key] as? NSNumber)?.intValue ?? fallback
        }

        func double(_ key: String, default fallback: Double = 0) -> Double {
            (raw[key] as? Double) ?? (raw[key] as? NSNumber)?.doubleValue ?? fallback
        }

        func ints(_ key: String) -> [Int] {
            (raw[key] as? [Any])?.compactMap { $0 as? Int ?? ($0 as? NSNumber)?.intValue } ?? []
        }

        func strings(_ key: String) -> [String] {
            (raw[key] as? [Any])?.compactMap { $0 as? String } ?? []
        }

        /// Ein Teilobjekt als Modell. Geht über JSON zurück, damit dieselben
        /// `Codable`-Regeln gelten wie bei der Antwort.
        func decode<T: Decodable>(_ type: T.Type, _ key: String) throws -> T {
            guard let value = raw[key] else {
                throw BridgeError(kind: "bridge", message: "Feld '\(key)' fehlt")
            }
            let data = try JSONSerialization.data(withJSONObject: value)
            do {
                return try NoriBridge.decoder.decode(T.self, from: data)
            } catch {
                throw BridgeError(kind: "bridge", message: "Feld '\(key)' passt nicht zu \(T.self): \(error)")
            }
        }

        func provider(_ key: String = "provider") throws -> CatalogProvider {
            let raw = try string(key)
            guard let provider = CatalogProvider(rawValue: raw) else {
                throw BridgeError(kind: "bridge", message: "Unbekannte Quelle '\(raw)'")
            }
            return provider
        }
    }
}
