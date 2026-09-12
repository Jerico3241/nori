import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Google Drive, aber nur der versteckte `appDataFolder`.
//
// Was hier steht, ist HTTP und sonst nichts: keine Anmeldung, keine
// Bibliothek, keine Oberfläche. Wer ein Zugriffstoken liefern kann, kann diese
// Klasse benutzen — das ist der Grund, warum sie sich ohne Google testen
// lässt.
//
// Der `appDataFolder` ist ein versteckter Ordner je App und Konto. Der Nutzer
// sieht ihn in „Meine Ablage" nicht, andere Apps kommen nicht heran, und mit
// der App verschwindet er. Nori braucht deshalb genau einen Bereich:
//
//     https://www.googleapis.com/auth/drive.appdata
//
// Nicht `drive`, nicht `drive.file`, keine sichtbaren Dateien. Was Nori nicht
// anfordert, kann Nori auch nicht verlieren.

/// Woher das Zugriffstoken kommt.
///
/// Der Rest der App enthält keine OAuth-Logik. Das ist Absicht: ein Token, das
/// an fünf Stellen erneuert wird, wird an vier davon falsch erneuert.
protocol GoogleAuthorizationProvider: AnyObject, Sendable {
    /// Ein gültiges Token — bei Bedarf vorher erneuert.
    func validAccessToken() async throws -> String
    /// Erzwingt eine Erneuerung, auch wenn das Token noch nicht abgelaufen
    /// scheint. Für den einen Versuch nach einem `401`.
    func refreshAccessToken() async throws -> String
}

enum GoogleDriveError: Error, Equatable {
    /// Der Nutzer ist nicht (mehr) verbunden.
    case notAuthorized
    /// Google hat die Berechtigung verweigert — Bereich entzogen, Zugriff
    /// widerrufen. Kein Fall für einen erneuten Versuch.
    case forbidden(String)
    /// Die Datei gibt es nicht mehr. Die gemerkte `fileId` ist damit wertlos.
    case notFound
    case conflict
    /// Nach allen erlaubten Versuchen immer noch daneben.
    case http(status: Int, message: String)
    case transport(String)
    /// Größer als `LibrarySyncLimits.maxSnapshotBytes`. Wird gar nicht erst
    /// geladen.
    case tooLarge(Int)

    var isRetryable: Bool {
        switch self {
        case .http(let status, _): return status == 429 || (500...599).contains(status)
        case .transport: return true
        case .notAuthorized, .forbidden, .notFound, .conflict, .tooLarge: return false
        }
    }
}

/// Was der Client zum Senden benutzt.
///
/// Austauschbar, damit die Tests ohne Netz und ohne Google-Konto laufen:
/// Wiederholungen, Backoff und die Behandlung von `401` sind Logik und keine
/// Netzwerkeigenschaft, und genau die soll geprüft werden.
protocol DriveTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionDriveTransport: DriveTransport {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleDriveError.transport("Keine HTTP-Antwort")
        }
        return (data, http)
    }
}

/// Eine Datei im `appDataFolder`.
struct DriveFile: Equatable {
    var id: String
    var name: String
    /// RFC-3339, wie Drive es liefert. Wird nur verglichen, nicht gerechnet —
    /// deshalb bleibt es eine Zeichenkette und wird nicht in eine Uhrzeit
    /// übersetzt, die von der Zeitzone des Geräts abhängt.
    var modifiedTime: String
    var size: Int
    var deviceId: String?
}

/// Wie oft und wie lange wiederholt wird.
///
/// An einer Stelle und nicht in jedem Aufruf. Sonst hat jeder Endpunkt seine
/// eigene Schleife, und eine davon läuft endlos.
struct DriveRetryPolicy: Sendable {
    var maxAttempts: Int = 5
    var baseDelay: Double = 1.0
    var maxDelay: Double = 16.0
    /// Streuung, damit vier Geräte nach einem `429` nicht im Gleichschritt
    /// zurückkommen und sich gegenseitig erneut ausbremsen.
    var jitter: Double = 0.3

    func delay(forAttempt attempt: Int, random: Double) -> Double {
        let raw = min(maxDelay, baseDelay * pow(2, Double(attempt)))
        return raw * (1 - jitter + 2 * jitter * random)
    }
}

actor GoogleDriveClient {
    static let scope = "https://www.googleapis.com/auth/drive.appdata"
    private static let filesEndpoint = "https://www.googleapis.com/drive/v3/files"
    private static let uploadEndpoint = "https://www.googleapis.com/upload/drive/v3/files"

    private let transport: DriveTransport
    private let authorization: GoogleAuthorizationProvider
    private let policy: DriveRetryPolicy
    private let sleep: @Sendable (Double) async -> Void
    private let random: @Sendable () -> Double

    /// `sleep` und `random` nur für Tests.
    ///
    /// Ohne sie dauerte ein Test der Backoff-Kette echte 31 Sekunden und wäre
    /// je nach Streuung mal grün und mal rot. Die App bekommt die Vorgaben.
    init(
        authorization: GoogleAuthorizationProvider,
        transport: DriveTransport = URLSessionDriveTransport(),
        policy: DriveRetryPolicy = DriveRetryPolicy(),
        sleep: @escaping @Sendable (Double) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
    ) {
        self.authorization = authorization
        self.transport = transport
        self.policy = policy
        self.sleep = sleep
        self.random = random
    }

    // MARK: - Öffentlich

    /// Alles, was im `appDataFolder` liegt.
    ///
    /// Ohne Suchausdruck: der Ordner gehört ausschließlich Nori, es liegt dort
    /// also nichts Fremdes. Ein `q=`-Ausdruck wäre eine zusätzliche Stelle, an
    /// der sich Drive-Syntax ändern kann, ohne etwas dafür zu leisten.
    func listSnapshots() async throws -> [DriveFile] {
        var components = URLComponents(string: Self.filesEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "fields", value: "files(id,name,modifiedTime,size,appProperties)"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        let (data, _) = try await perform(request)
        return try parseFileList(data)
    }

    /// Den Inhalt einer Datei holen.
    ///
    /// `expectedSize` kommt aus dem Verzeichnis und wird **vorher** geprüft.
    /// Eine Bibliothek ist ein paar Kilobyte groß; was um Größenordnungen
    /// darüber liegt, wird nicht heruntergeladen, sondern gemeldet.
    func download(id: String, expectedSize: Int? = nil) async throws -> Data {
        if let expectedSize, expectedSize > LibrarySyncLimits.maxSnapshotBytes {
            throw GoogleDriveError.tooLarge(expectedSize)
        }
        var components = URLComponents(string: "\(Self.filesEndpoint)/\(id)")!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        let (data, _) = try await perform(request)
        guard data.count <= LibrarySyncLimits.maxSnapshotBytes else {
            throw GoogleDriveError.tooLarge(data.count)
        }
        return data
    }

    /// Eine neue Datei anlegen.
    ///
    /// Zurück kommt auch der Änderungsstempel: damit kann der Aufrufer den
    /// gerade geschriebenen Stand merken und muss ihn beim nächsten Abgleich
    /// nicht von Drive zurückholen, um festzustellen, dass er ihn selbst
    /// geschrieben hat.
    func create(name: String, deviceId: String, content: Data) async throws -> (id: String, modifiedTime: String) {
        let metadata: [String: Any] = [
            "name": name,
            "parents": ["appDataFolder"],
            "appProperties": Self.properties(deviceId: deviceId),
        ]
        var components = URLComponents(string: Self.uploadEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "uploadType", value: "multipart"),
            URLQueryItem(name: "fields", value: "id,modifiedTime"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        let boundary = "nori-\(UUID().uuidString)"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.multipartBody(metadata: metadata, content: content, boundary: boundary)
        let (data, _) = try await perform(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String else {
            throw GoogleDriveError.http(status: 200, message: "Antwort ohne Dateikennung")
        }
        return (id, object["modifiedTime"] as? String ?? "")
    }

    /// Eine bestehende Datei überschreiben.
    ///
    /// `files.update` statt jedes Mal `files.create` — sonst entstünde bei
    /// jedem Abgleich eine weitere Datei mit demselben Namen, und der Ordner
    /// liefe voll.
    @discardableResult
    func update(id: String, content: Data) async throws -> String {
        var components = URLComponents(string: "\(Self.uploadEndpoint)/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "uploadType", value: "media"),
            URLQueryItem(name: "fields", value: "id,modifiedTime"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = content
        let (data, _) = try await perform(request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return object?["modifiedTime"] as? String ?? ""
    }

    func delete(id: String) async throws {
        var request = URLRequest(url: URL(string: "\(Self.filesEndpoint)/\(id)")!)
        request.httpMethod = "DELETE"
        _ = try await perform(request)
    }

    // MARK: - Innereien

    static func properties(deviceId: String) -> [String: String] {
        ["app": "nori", "type": "library-snapshot", "syncVersion": "\(librarySyncFormatVersion)", "deviceId": deviceId]
    }

    /// Der Dateiname eines Gerätestands.
    static func snapshotName(deviceId: String) -> String {
        "nori-sync-v\(librarySyncFormatVersion)-\(deviceId).json"
    }

    /// Gehört die Datei zu Nori?
    ///
    /// `appProperties` zuerst, Name als Rückfall. Der Ordner ist zwar
    /// ausschließlich Noris, aber eine ältere oder von Hand abgelegte Datei
    /// darf den Abgleich nicht durcheinanderbringen.
    static func isSnapshot(_ file: DriveFile) -> Bool {
        if file.deviceId != nil { return true }
        return file.name.hasPrefix("nori-sync-v") && file.name.hasSuffix(".json")
    }

    private func parseFileList(_ data: Data) throws -> [DriveFile] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = object["files"] as? [[String: Any]] else {
            throw GoogleDriveError.http(status: 200, message: "Verzeichnis nicht lesbar")
        }
        return files.compactMap { entry in
            guard let id = entry["id"] as? String, let name = entry["name"] as? String else { return nil }
            let properties = entry["appProperties"] as? [String: String]
            // Drive liefert `size` als Zeichenkette — es ist ein int64.
            let size = Int((entry["size"] as? String) ?? "") ?? (entry["size"] as? Int ?? 0)
            return DriveFile(
                id: id,
                name: name,
                modifiedTime: entry["modifiedTime"] as? String ?? "",
                size: size,
                deviceId: properties?["deviceId"]
            )
        }
    }

    static func multipartBody(metadata: [String: Any], content: Data, boundary: String) throws -> Data {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(try JSONSerialization.data(withJSONObject: metadata))
        append("\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n")
        body.append(content)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    /// Senden, mit genau einer Erneuerung nach `401` und begrenztem Backoff.
    ///
    /// Die eine Erneuerung ist wichtig: ein abgelaufenes Token darf den
    /// Abgleich nicht scheitern lassen, aber zwei Fehlschläge hintereinander
    /// heißen, dass das Problem nicht das Token ist. Wer es dann weiter
    /// versucht, baut eine Endlosschleife gegen Googles Rate Limit.
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var refreshed = false
        var attempt = 0

        while true {
            var signed = request
            let token = refreshed
                ? try await authorization.refreshAccessToken()
                : try await authorization.validAccessToken()
            signed.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let result: (Data, HTTPURLResponse)
            do {
                result = try await transport.send(signed)
            } catch let error as GoogleDriveError {
                guard error.isRetryable, attempt + 1 < policy.maxAttempts else { throw error }
                await sleep(policy.delay(forAttempt: attempt, random: random()))
                attempt += 1
                continue
            } catch {
                let wrapped = GoogleDriveError.transport(error.localizedDescription)
                guard attempt + 1 < policy.maxAttempts else { throw wrapped }
                await sleep(policy.delay(forAttempt: attempt, random: random()))
                attempt += 1
                continue
            }

            let (data, response) = result
            switch response.statusCode {
            case 200...299:
                return result

            case 401:
                // Genau einmal. Danach ist es kein Tokenproblem mehr.
                guard !refreshed else { throw GoogleDriveError.notAuthorized }
                refreshed = true
                continue

            case 403:
                // Drive benutzt 403 für zweierlei: „darfst du nicht" und „zu
                // schnell". Das eine ist endgültig, das andere nicht — sie
                // auseinanderzuhalten ist der Unterschied zwischen einer
                // Fehlermeldung und einer Endlosschleife.
                let message = Self.reason(in: data)
                if Self.isRateLimit(message), attempt + 1 < policy.maxAttempts {
                    await sleep(policy.delay(forAttempt: attempt, random: random()))
                    attempt += 1
                    continue
                }
                throw GoogleDriveError.forbidden(message)

            case 404:
                throw GoogleDriveError.notFound

            case 409:
                throw GoogleDriveError.conflict

            case 429, 500...599:
                guard attempt + 1 < policy.maxAttempts else {
                    throw GoogleDriveError.http(status: response.statusCode, message: Self.reason(in: data))
                }
                await sleep(policy.delay(forAttempt: attempt, random: random()))
                attempt += 1

            default:
                throw GoogleDriveError.http(status: response.statusCode, message: Self.reason(in: data))
            }
        }
    }

    static func reason(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return "" }
        if let errors = error["errors"] as? [[String: Any]], let reason = errors.first?["reason"] as? String {
            return reason
        }
        return error["message"] as? String ?? ""
    }

    static func isRateLimit(_ reason: String) -> Bool {
        reason == "rateLimitExceeded" || reason == "userRateLimitExceeded"
    }
}
