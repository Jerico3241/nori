import XCTest
@testable import NoriCore

// Der Drive-Client — ohne Google.
//
// Geprüft wird nicht, ob Drive antwortet, sondern was Nori mit den Antworten
// macht: genau eine Tokenerneuerung nach `401`, Backoff nach `429`, und kein
// zweiter Versuch, wo einer nichts bringt. Das sind Entscheidungen im
// Nori-Code; ein Test gegen das echte Google prüfte vor allem, ob gerade Netz
// da ist.

private final class ScriptedTransport: DriveTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [(status: Int, body: Data)]
    private(set) var sent: [URLRequest] = []

    init(_ script: [(status: Int, body: Data)]) { self.script = script }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        defer { lock.unlock() }
        sent.append(request)
        let next = script.isEmpty ? (status: 200, body: Data("{}".utf8)) : script.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
        return (next.body, response)
    }

    var authorizationHeaders: [String] {
        sent.compactMap { $0.value(forHTTPHeaderField: "Authorization") }
    }
}

private final class CountingAuthorization: GoogleAuthorizationProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var issued = 1
    private(set) var refreshes = 0

    func validAccessToken() async throws -> String {
        lock.lock(); defer { lock.unlock() }
        return "token-\(issued)"
    }

    func refreshAccessToken() async throws -> String {
        lock.lock(); defer { lock.unlock() }
        refreshes += 1
        issued += 1
        return "token-\(issued)"
    }
}

/// Zeichnet auf, wie lange gewartet worden wäre — statt tatsächlich zu warten.
private final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var delays: [Double] = []
    func record(_ seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        delays.append(seconds)
    }
}

final class GoogleDriveClientTests: XCTestCase {

    private func client(
        _ transport: ScriptedTransport,
        _ authorization: CountingAuthorization,
        _ log: SleepLog = SleepLog(),
        policy: DriveRetryPolicy = DriveRetryPolicy()
    ) -> GoogleDriveClient {
        GoogleDriveClient(
            authorization: authorization,
            transport: transport,
            policy: policy,
            // Ohne das dauerte dieser Test echte 15 Sekunden und wäre je nach
            // Streuung mal grün und mal rot.
            sleep: { seconds in log.record(seconds) },
            random: { 0.5 }
        )
    }

    private static let emptyList = Data(#"{"files":[]}"#.utf8)

    // MARK: - N: abgelaufenes Token

    func testExpiredTokenIsRefreshedOnceAndTheRequestRepeated() async throws {
        let transport = ScriptedTransport([(401, Data()), (200, Self.emptyList)])
        let auth = CountingAuthorization()

        let files = try await client(transport, auth).listSnapshots()

        XCTAssertEqual(files, [])
        XCTAssertEqual(auth.refreshes, 1)
        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertEqual(transport.authorizationHeaders, ["Bearer token-1", "Bearer token-2"])
    }

    /// Zweimal `401` heißt: es liegt nicht am Token. Wer dann weiter erneuert,
    /// baut eine Endlosschleife gegen Googles Rate Limit.
    func testASecondUnauthorizedGivesUp() async {
        let transport = ScriptedTransport([(401, Data()), (401, Data())])
        let auth = CountingAuthorization()

        do {
            _ = try await client(transport, auth).listSnapshots()
            XCTFail("Erwartet: notAuthorized")
        } catch let error as GoogleDriveError {
            XCTAssertEqual(error, .notAuthorized)
        } catch {
            XCTFail("Falscher Fehler: \(error)")
        }
        XCTAssertEqual(auth.refreshes, 1)
        XCTAssertEqual(transport.sent.count, 2)
    }

    // MARK: - O: Rate Limit

    func testRateLimitBacksOffAndSucceeds() async throws {
        let transport = ScriptedTransport([(429, Data()), (429, Data()), (200, Self.emptyList)])
        let log = SleepLog()

        _ = try await client(transport, CountingAuthorization(), log).listSnapshots()

        XCTAssertEqual(transport.sent.count, 3)
        XCTAssertEqual(log.delays.count, 2)
        XCTAssertEqual(log.delays[0], 1.0, accuracy: 0.001, "Erster Aufschub: eine Sekunde")
        XCTAssertEqual(log.delays[1], 2.0, accuracy: 0.001, "Danach das Doppelte")
    }

    /// Der Aufschub wird gestreut. Ohne das kämen vier Geräte nach einem `429`
    /// im Gleichschritt zurück und bremsten sich gegenseitig erneut aus.
    func testBackoffIsJittered() {
        let policy = DriveRetryPolicy()
        XCTAssertEqual(policy.delay(forAttempt: 0, random: 0), 0.7, accuracy: 0.001)
        XCTAssertEqual(policy.delay(forAttempt: 0, random: 1), 1.3, accuracy: 0.001)
        // Und er wächst nicht über die Obergrenze hinaus.
        XCTAssertLessThanOrEqual(policy.delay(forAttempt: 20, random: 1), policy.maxDelay * 1.3)
    }

    func testGivesUpAfterTheAllowedAttempts() async {
        let transport = ScriptedTransport(Array(repeating: (503, Data()), count: 10))
        let log = SleepLog()
        let policy = DriveRetryPolicy(maxAttempts: 3, baseDelay: 1, maxDelay: 8, jitter: 0)

        do {
            _ = try await client(transport, CountingAuthorization(), log, policy: policy).listSnapshots()
            XCTFail("Erwartet: Fehler nach drei Versuchen")
        } catch let error as GoogleDriveError {
            guard case .http(let status, _) = error else { return XCTFail("Falscher Fehler: \(error)") }
            XCTAssertEqual(status, 503)
        } catch {
            XCTFail("Falscher Fehler: \(error)")
        }
        XCTAssertEqual(transport.sent.count, 3, "Keine Endlosschleife")
        XCTAssertEqual(log.delays.count, 2)
    }

    // MARK: - 403: zweierlei

    /// Drive benutzt 403 für „darfst du nicht" und für „zu schnell". Das eine
    /// ist endgültig, das andere nicht.
    func testForbiddenIsNotRetried() async {
        let body = Data(#"{"error":{"errors":[{"reason":"insufficientPermissions"}],"message":"nope"}}"#.utf8)
        let transport = ScriptedTransport([(403, body), (200, Self.emptyList)])

        do {
            _ = try await client(transport, CountingAuthorization()).listSnapshots()
            XCTFail("Erwartet: forbidden")
        } catch let error as GoogleDriveError {
            XCTAssertEqual(error, .forbidden("insufficientPermissions"))
        } catch {
            XCTFail("Falscher Fehler: \(error)")
        }
        XCTAssertEqual(transport.sent.count, 1, "Eine entzogene Berechtigung wurde erneut versucht")
    }

    func testRateLimitDisguisedAsForbiddenIsRetried() async throws {
        let body = Data(#"{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}"#.utf8)
        let transport = ScriptedTransport([(403, body), (200, Self.emptyList)])

        _ = try await client(transport, CountingAuthorization()).listSnapshots()

        XCTAssertEqual(transport.sent.count, 2)
    }

    // MARK: - Einzelne Endpunkte

    func testNotFoundIsItsOwnError() async {
        let transport = ScriptedTransport([(404, Data())])
        do {
            _ = try await client(transport, CountingAuthorization()).download(id: "weg")
            XCTFail("Erwartet: notFound")
        } catch let error as GoogleDriveError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("Falscher Fehler: \(error)")
        }
    }

    /// Zu große Dateien werden gar nicht erst geholt.
    func testOversizedFileIsNotDownloaded() async {
        let transport = ScriptedTransport([(200, Data())])
        do {
            _ = try await client(transport, CountingAuthorization())
                .download(id: "riesig", expectedSize: LibrarySyncLimits.maxSnapshotBytes + 1)
            XCTFail("Erwartet: tooLarge")
        } catch let error as GoogleDriveError {
            XCTAssertEqual(error, .tooLarge(LibrarySyncLimits.maxSnapshotBytes + 1))
        } catch {
            XCTFail("Falscher Fehler: \(error)")
        }
        XCTAssertTrue(transport.sent.isEmpty, "Die Datei wurde trotzdem angefragt")
    }

    func testListingReadsIdNameSizeAndDeviceId() async throws {
        let body = Data("""
        {"files":[{"id":"1","name":"nori-sync-v1-abc.json","modifiedTime":"2026-09-12T01:02:03.000Z",
        "size":"1234","appProperties":{"app":"nori","deviceId":"abc"}}]}
        """.utf8)
        let transport = ScriptedTransport([(200, body)])

        let files = try await client(transport, CountingAuthorization()).listSnapshots()

        XCTAssertEqual(files, [DriveFile(
            id: "1", name: "nori-sync-v1-abc.json",
            modifiedTime: "2026-09-12T01:02:03.000Z", size: 1234, deviceId: "abc")])
        XCTAssertTrue(GoogleDriveClient.isSnapshot(files[0]))
    }

    /// Nur der versteckte Ordner, nie „Meine Ablage".
    func testListingStaysInsideTheAppDataFolder() async throws {
        let transport = ScriptedTransport([(200, Self.emptyList)])
        _ = try await client(transport, CountingAuthorization()).listSnapshots()

        let query = transport.sent[0].url!.query ?? ""
        XCTAssertTrue(query.contains("spaces=appDataFolder"), "Abfrage ohne spaces=appDataFolder: \(query)")
    }

    func testCreateSendsMetadataAndContentAsMultipart() async throws {
        let transport = ScriptedTransport([(200, Data(#"{"id":"neu","modifiedTime":"jetzt"}"#.utf8))])

        let created = try await client(transport, CountingAuthorization())
            .create(name: "nori-sync-v1-abc.json", deviceId: "abc", content: Data(#"{"favorites":[]}"#.utf8))

        XCTAssertEqual(created.id, "neu")
        XCTAssertEqual(created.modifiedTime, "jetzt")
        let body = String(decoding: transport.sent[0].httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("appDataFolder"), "Die Datei landete nicht im versteckten Ordner")
        XCTAssertTrue(body.contains("nori-sync-v1-abc.json"))
        XCTAssertTrue(body.contains(#""deviceId":"abc""#) || body.contains(#""deviceId": "abc""#))
        XCTAssertTrue(body.contains(#"{"favorites":[]}"#))
    }

    func testUpdateWritesToTheKnownFile() async throws {
        let transport = ScriptedTransport([(200, Data(#"{"id":"alt","modifiedTime":"später"}"#.utf8))])

        let stamp = try await client(transport, CountingAuthorization())
            .update(id: "alt", content: Data("{}".utf8))

        XCTAssertEqual(stamp, "später")
        XCTAssertEqual(transport.sent[0].httpMethod, "PATCH")
        XCTAssertTrue(transport.sent[0].url!.absoluteString.contains("/files/alt"))
    }

    /// Nori fordert genau einen Bereich an — den kleinsten, der reicht.
    func testTheScopeIsAppDataOnly() {
        XCTAssertEqual(GoogleDriveClient.scope, "https://www.googleapis.com/auth/drive.appdata")
    }

    func testSnapshotNameCarriesTheDeviceId() {
        XCTAssertEqual(GoogleDriveClient.snapshotName(deviceId: "abc"), "nori-sync-v1-abc.json")
        XCTAssertTrue(GoogleDriveClient.isSnapshot(
            DriveFile(id: "1", name: "nori-sync-v1-abc.json", modifiedTime: "", size: 0, deviceId: nil)))
        XCTAssertFalse(GoogleDriveClient.isSnapshot(
            DriveFile(id: "2", name: "irgendwas.txt", modifiedTime: "", size: 0, deviceId: nil)))
    }
}
