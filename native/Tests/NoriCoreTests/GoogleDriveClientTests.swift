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

// MARK: - TV-Spiegel

extension GoogleDriveClientTests {

    private func mirrorClient(_ transport: ScriptedTransport) -> GoogleDriveClient {
        GoogleDriveClient(
            authorization: CountingAuthorization(), transport: transport, policy: DriveRetryPolicy(),
            sleep: { _ in }, random: { 0.5 }, space: .tvMirror)
    }

    private func decoded(_ request: URLRequest) -> String {
        request.url?.absoluteString.removingPercentEncoding ?? ""
    }

    func testTheSpacesKeepTheirOwnNamesAndMetadata() {
        XCTAssertEqual(DriveSpace.appData.fileName(deviceId: "abc"), "nori-sync-v1-abc.json")
        XCTAssertEqual(DriveSpace.tvMirror.fileName(deviceId: "abc"), "nori-tv-sync-v1-abc.json")
        XCTAssertNil(DriveSpace.appData.query)
        let query = DriveSpace.tvMirror.query ?? ""
        XCTAssertTrue(query.contains("value='library-mirror'"))
        XCTAssertTrue(query.contains("trashed=false"))
        XCTAssertFalse(query.contains("name"), "Erkannt wird nie am Namen")
        XCTAssertFalse(query.contains("parents"), "Erkannt wird nie am Ordner")
        XCTAssertEqual(DriveSpace.tvMirror.properties(deviceId: "abc"),
                       ["app": "nori", "type": "library-mirror", "syncVersion": "1", "deviceId": "abc", "mirror": "tv"])
        XCTAssertEqual(DriveSpace.appData.properties(deviceId: "abc"),
                       ["app": "nori", "type": "library-snapshot", "syncVersion": "1", "deviceId": "abc"])
        XCTAssertEqual(GoogleDriveClient.fileScope, "https://www.googleapis.com/auth/drive.file")
    }

    /// Umbenannt und verschoben: gefunden wird trotzdem, über `appProperties`.
    func testTheMirrorIsListedByPropertiesOnly() async throws {
        let body = Data(#"""
        {"files":[{"id":"m1","name":"Von Hand umbenannt.json","modifiedTime":"2026-09-13T01:00:00.000Z",
        "size":"10","appProperties":{"app":"nori","type":"library-mirror","deviceId":"mac","mirror":"tv"}}]}
        """#.utf8)
        let transport = ScriptedTransport([(200, body)])

        let files = try await mirrorClient(transport).listSnapshots()

        XCTAssertEqual(files.map(\.id), ["m1"])
        XCTAssertEqual(files.first?.deviceId, "mac")
        let url = decoded(transport.sent[0])
        XCTAssertTrue(url.contains("spaces=drive"), url)
        XCTAssertFalse(url.contains("appDataFolder"), url)
        XCTAssertTrue(url.contains("value='library-mirror'"), url)
    }

    func testAMirrorFileGoesIntoTheOldestNoriFolder() async throws {
        let transport = ScriptedTransport([
            (200, Data(#"{"files":[{"id":"neuer","createdTime":"2026-09-13T00:00:00.000Z"},{"id":"aelter","createdTime":"2026-09-01T00:00:00.000Z"}]}"#.utf8)),
            (200, Data(#"{"id":"datei","modifiedTime":"jetzt"}"#.utf8)),
        ])

        let created = try await mirrorClient(transport)
            .create(name: DriveSpace.tvMirror.fileName(deviceId: "abc"), deviceId: "abc", content: Data("{}".utf8))

        XCTAssertEqual(created.id, "datei")
        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertTrue(decoded(transport.sent[0]).contains("value='mirror-folder'"))
        let body = String(decoding: transport.sent[1].httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("aelter"))
        XCTAssertFalse(body.contains("neuer"))
        XCTAssertFalse(body.contains("appDataFolder"), "Eine Spiegeldatei landete im versteckten Ordner")
        XCTAssertTrue(body.contains("nori-tv-sync-v1-abc.json"))
        XCTAssertTrue(body.contains("library-mirror"))
        XCTAssertTrue(body.contains(#""mirror":"tv""#))
    }

    /// Fehlt der Ordner — gelöscht oder nie angelegt —, legt Nori ihn an.
    func testAMissingNoriFolderIsCreated() async throws {
        let transport = ScriptedTransport([
            (200, Self.emptyList),
            (200, Data(#"{"id":"ordner"}"#.utf8)),
            (200, Data(#"{"id":"datei","modifiedTime":"jetzt"}"#.utf8)),
        ])

        _ = try await mirrorClient(transport)
            .create(name: DriveSpace.tvMirror.fileName(deviceId: "abc"), deviceId: "abc", content: Data("{}".utf8))

        XCTAssertEqual(transport.sent.count, 3)
        XCTAssertEqual(transport.sent[1].httpMethod, "POST")
        let folder = String(decoding: transport.sent[1].httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(folder.contains("vnd.google-apps.folder"))
        XCTAssertTrue(folder.contains("mirror-folder"))
        XCTAssertTrue(folder.contains(#""Nori""#))
        XCTAssertTrue(String(decoding: transport.sent[2].httpBody ?? Data(), as: UTF8.self).contains("ordner"))
    }

    /// Der Ordner ist nur UX. Scheitert er, wird die Datei trotzdem geschrieben.
    func testAFailingFolderDoesNotStopTheMirrorFile() async throws {
        let transport = ScriptedTransport([
            (403, Data(#"{"error":{"errors":[{"reason":"insufficientPermissions"}]}}"#.utf8)),
            (200, Data(#"{"id":"datei","modifiedTime":"jetzt"}"#.utf8)),
        ])

        let created = try await mirrorClient(transport)
            .create(name: DriveSpace.tvMirror.fileName(deviceId: "abc"), deviceId: "abc", content: Data("{}".utf8))

        XCTAssertEqual(created.id, "datei")
        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertFalse(String(decoding: transport.sent[1].httpBody ?? Data(), as: UTF8.self).contains("appDataFolder"))
    }

    /// Ohne Freigabe fragt der appDataFolder nie nach einem Ordner.
    func testTheAppDataFolderNeverLooksForAFolder() async throws {
        let transport = ScriptedTransport([(200, Data(#"{"id":"neu","modifiedTime":"jetzt"}"#.utf8))])
        _ = try await client(transport, CountingAuthorization())
            .create(name: "nori-sync-v1-abc.json", deviceId: "abc", content: Data("{}".utf8))
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertFalse(decoded(transport.sent[0]).contains("mirror-folder"))
    }

    /// Fehlt `drive.file`, antwortet Drive mit 403 — kein zweiter Versuch, und
    /// der Grund reicht, um die Zustimmung erneut anzubieten.
    func testAMissingFileScopeIsNotRetried() async {
        let transport = ScriptedTransport([
            (403, Data(#"{"error":{"errors":[{"reason":"insufficientScopes"}]}}"#.utf8)),
            (200, Self.emptyList),
        ])
        do {
            _ = try await mirrorClient(transport).listSnapshots()
            XCTFail("Erwartet: forbidden")
        } catch let error as GoogleDriveError {
            guard case .forbidden(let reason) = error else { return XCTFail("Falscher Fehler: \(error)") }
            XCTAssertEqual(TVMirrorState.resolve(enabled: true, grantedScopes: [GoogleDriveClient.fileScope], mirrorError: reason), .needsConsent)
        } catch {
            XCTFail("Falscher Fehler: \(error)")
        }
        XCTAssertEqual(transport.sent.count, 1)
    }

    func testTheMirrorBacksOffOnRateLimits() async throws {
        let transport = ScriptedTransport([(429, Data()), (401, Data()), (200, Self.emptyList)])
        _ = try await mirrorClient(transport).listSnapshots()
        XCTAssertEqual(transport.sent.count, 3)
    }
}
