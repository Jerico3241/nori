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

/// Wo Nori in Drive liest und schreibt.
///
/// Zwei Ablagen. Beide werden **ausschliesslich** über `appProperties`
/// erkannt — nie über Dateiname, Ordner oder Pfad:
///
/// - `appData`: der versteckte `appDataFolder` (`drive.appdata`). Die primäre
///   Ablage der Apple-Apps, unverändert.
/// - `tvMirror`: der sichtbare Spiegel für Fernseher (`drive.file`). Nur nach
///   ausdrücklicher Freigabe „Mit Fernseher teilen" auf einem Apple-Gerät.
///   webOS benutzt ausschliesslich ihn, weil Googles Gerätefluss
///   `drive.appdata` reproduzierbar mit `invalid_scope` ablehnt.
///
/// Warum der Spiegel verschoben oder umbenannt werden darf: `drive.file`
/// gewährt den Zugriff je Datei und je Cloud-Projekt, nicht je Ort. Im Proof of
/// Concept fanden iPhone, Mac und Fernseher eine von Hand verschobene und
/// umbenannte Datei weiterhin über `appProperties`.
enum DriveSpace: String, Sendable, CaseIterable {
    case appData
    case tvMirror

    var isVisible: Bool { self == .tvMirror }
    var fileType: String { self == .appData ? "library-snapshot" : "library-mirror" }
    private var namePrefix: String { self == .appData ? "nori-sync" : "nori-tv-sync" }

    /// Der von Nori angelegte Ordner in „Meine Ablage". Nur für den Nutzer.
    static let folderName = "Nori"
    static let folderType = "mirror-folder"

    /// Der Suchausdruck. Der `appDataFolder` gehört Nori allein und wird wie
    /// bisher ohne Ausdruck gelistet — für Nutzer ohne Fernseher ändert sich
    /// hier nichts.
    var query: String? {
        guard isVisible else { return nil }
        return "appProperties has { key='app' and value='nori' } and "
            + "appProperties has { key='type' and value='\(fileType)' } and trashed=false"
    }

    func properties(deviceId: String) -> [String: String] {
        var result = ["app": "nori", "type": fileType, "syncVersion": "\(librarySyncFormatVersion)", "deviceId": deviceId]
        if isVisible { result["mirror"] = "tv" }
        return result
    }

    func fileName(deviceId: String) -> String {
        "\(namePrefix)-v\(librarySyncFormatVersion)-\(deviceId).json"
    }
}

actor GoogleDriveClient {
    static let scope = "https://www.googleapis.com/auth/drive.appdata"
    /// Nur für den TV-Spiegel, und nur nach ausdrücklicher Zustimmung.
    static let fileScope = "https://www.googleapis.com/auth/drive.file"
    private static let filesEndpoint = "https://www.googleapis.com/drive/v3/files"
    private static let uploadEndpoint = "https://www.googleapis.com/upload/drive/v3/files"

    private let transport: DriveTransport
    private let authorization: GoogleAuthorizationProvider
    private let policy: DriveRetryPolicy
    private let sleep: @Sendable (Double) async -> Void
    private let random: @Sendable () -> Double
    /// In welcher Ablage dieser Client arbeitet. Fest je Client: eine
    /// Dateikennung aus der einen Ablage kann damit nie in der anderen landen.
    let space: DriveSpace

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
        random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
        space: DriveSpace = .appData
    ) {
        self.space = space
        self.authorization = authorization
        self.transport = transport
        self.policy = policy
        self.sleep = sleep
        self.random = random
    }

    // MARK: - Öffentlich

    /// Alle Gerätestände dieser Ablage.
    ///
    /// Im `appDataFolder` ohne Suchausdruck: der Ordner gehört ausschließlich
    /// Nori, es liegt dort also nichts Fremdes. Im sichtbaren Spiegel dagegen
    /// über `appProperties` — Name und Ordner kann der Nutzer ändern.
    func listSnapshots() async throws -> [DriveFile] {
        var components = URLComponents(string: Self.filesEndpoint)!
        var items = [
            URLQueryItem(name: "spaces", value: space.isVisible ? "drive" : "appDataFolder"),
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "fields", value: "files(id,name,modifiedTime,size,appProperties)"),
        ]
        if let query = space.query { items.append(URLQueryItem(name: "q", value: query)) }
        components.queryItems = items
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
        var metadata: [String: Any] = [
            "name": name,
            "appProperties": space.properties(deviceId: deviceId),
        ]
        if space.isVisible {
            // Der Ordner ist nur UX. Lässt er sich nicht finden oder anlegen,
            // landet die Datei in „Meine Ablage" und wird trotzdem gefunden.
            if let folder = try? await mirrorFolder() { metadata["parents"] = [folder] }
        } else {
            metadata["parents"] = ["appDataFolder"]
        }
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

    nonisolated func fileName(deviceId: String) -> String { space.fileName(deviceId: deviceId) }

    /// Den sichtbaren Ordner über `appProperties` finden oder anlegen.
    ///
    /// Bewusst ohne Zwischenspeicher: angelegt wird nur, wenn ein Gerät noch
    /// keine eigene Datei hat, also selten. Ein gemerkter Ordner, den der Nutzer
    /// inzwischen in den Papierkorb gelegt hat, bekäme sonst neue Dateien, die
    /// mit ihm im Papierkorb landen — und die Suche fände sie nie.
    ///
    /// Liegen mehrere Ordner vor (zwei Geräte gleichzeitig), gilt
    /// deterministisch der älteste. Dateien werden ohnehin nicht über den Ordner
    /// gefunden.
    func mirrorFolder() async throws -> String {
        var components = URLComponents(string: Self.filesEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "q", value: "appProperties has { key='app' and value='nori' } and "
                + "appProperties has { key='type' and value='\(DriveSpace.folderType)' } and trashed=false"),
            URLQueryItem(name: "fields", value: "files(id,createdTime)"),
        ]
        var list = URLRequest(url: components.url!)
        list.httpMethod = "GET"
        let (data, _) = try await perform(list)
        let folders = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["files"] as? [[String: Any]] ?? []
        let existing = folders
            .compactMap { entry -> (id: String, created: String)? in
                guard let id = entry["id"] as? String else { return nil }
                return (id, entry["createdTime"] as? String ?? "")
            }
            .sorted { ($0.created, $0.id) < ($1.created, $1.id) }
            .first
        if let existing { return existing.id }

        var create = URLRequest(url: URL(string: "\(Self.filesEndpoint)?fields=id")!)
        create.httpMethod = "POST"
        create.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        create.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": DriveSpace.folderName,
            "mimeType": "application/vnd.google-apps.folder",
            "appProperties": ["app": "nori", "type": DriveSpace.folderType],
        ])
        let (created, _) = try await perform(create)
        guard let object = try JSONSerialization.jsonObject(with: created) as? [String: Any],
              let id = object["id"] as? String else {
            throw GoogleDriveError.http(status: 200, message: "Ordner ohne Kennung")
        }
        return id
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
