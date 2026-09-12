import XCTest
@testable import NoriCore

/// Der Tokenlebenszyklus: erneuern, genau einmal, und aufräumen, wenn der
/// Auffrischungstoken nicht mehr gilt.
final class GoogleAuthorizationTests: XCTestCase {

    private let config = GoogleOAuthConfiguration(
        clientId: "1234.apps.googleusercontent.com",
        redirectURI: "http://127.0.0.1:51234"
    )

    private final class CountingTransport: DriveTransport, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var calls = 0
        var status = 200
        var json = #"{"access_token":"frisch","expires_in":3600}"#
        /// Bremst die Antwort, damit sich zwei Erneuerungen überhaupt
        /// überlappen können.
        var delayNanoseconds: UInt64 = 0

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
            lock.lock()
            calls += 1
            lock.unlock()
            return (Data(json.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private func tokens(expiresAt: Double, refresh: String? = "rt") -> GoogleTokens {
        GoogleTokens(accessToken: "alt", refreshToken: refresh, expiresAt: expiresAt, scope: nil)
    }

    func testAValidTokenIsUsedAsIs() async throws {
        let transport = CountingTransport()
        let auth = GoogleAuthorization(
            configuration: config, tokenStore: MemoryTokenStore(tokens(expiresAt: 10_000_000)),
            transport: transport, clock: { 0 })

        let token = try await auth.validAccessToken()
        XCTAssertEqual(token, "alt")
        XCTAssertEqual(transport.calls, 0, "Ein gültiges Token wurde ohne Not erneuert")
    }

    func testAnExpiredTokenIsRefreshed() async throws {
        let transport = CountingTransport()
        let store = MemoryTokenStore(tokens(expiresAt: 1_000))
        let auth = GoogleAuthorization(
            configuration: config, tokenStore: store, transport: transport, clock: { 500_000 })

        let token = try await auth.validAccessToken()
        XCTAssertEqual(token, "frisch")
        XCTAssertEqual(transport.calls, 1)
        XCTAssertEqual(store.read()?.accessToken, "frisch")
        XCTAssertEqual(store.read()?.refreshToken, "rt", "Der Auffrischungstoken ist verloren gegangen")
    }

    /// Zwei gleichzeitige Erneuerungen desselben Tokens beantwortet Google mit
    /// `invalid_grant` — und dann ist die Verbindung weg, mitten im Abgleich
    /// und ohne erkennbaren Grund.
    func testConcurrentRefreshesShareOneRequest() async throws {
        let transport = CountingTransport()
        transport.delayNanoseconds = 30_000_000
        let auth = GoogleAuthorization(
            configuration: config, tokenStore: MemoryTokenStore(tokens(expiresAt: 0)),
            transport: transport, clock: { 500_000 })

        async let a = auth.validAccessToken()
        async let b = auth.validAccessToken()
        async let c = auth.validAccessToken()
        let results = try await [a, b, c]

        XCTAssertEqual(results, ["frisch", "frisch", "frisch"])
        XCTAssertEqual(transport.calls, 1, "Drei Anfragen haben den Token dreimal erneuert")
    }

    /// Ein nicht mehr gültiger Auffrischungstoken wird weggeräumt. Sonst
    /// scheiterte jeder weitere Abgleich an demselben wertlosen Wert, und die
    /// Oberfläche könnte nie „neu verbinden" anbieten.
    func testAnInvalidGrantClearsTheStoredTokens() async {
        let transport = CountingTransport()
        transport.status = 400
        transport.json = #"{"error":"invalid_grant"}"#
        let store = MemoryTokenStore(tokens(expiresAt: 0))
        let auth = GoogleAuthorization(
            configuration: config, tokenStore: store, transport: transport, clock: { 500_000 })

        do {
            _ = try await auth.validAccessToken()
            XCTFail("Erwartet: notAuthorized")
        } catch let error as GoogleDriveError {
            XCTAssertEqual(error, .notAuthorized)
        } catch {
            XCTFail("Falscher Fehler: \(error)")
        }
        XCTAssertNil(store.read(), "Der wertlose Token liegt noch im Schlüsselbund")
    }

    /// Ein vorübergehender Serverfehler räumt **nicht** auf — sonst wäre eine
    /// Google-Störung gleichbedeutend mit „abgemeldet".
    func testAServerErrorKeepsTheTokens() async {
        let transport = CountingTransport()
        transport.status = 500
        transport.json = #"{"error":"backendError"}"#
        let store = MemoryTokenStore(tokens(expiresAt: 0))
        let auth = GoogleAuthorization(
            configuration: config, tokenStore: store, transport: transport, clock: { 500_000 })

        _ = try? await auth.validAccessToken()

        XCTAssertNotNil(store.read(), "Eine Google-Störung hat die Anmeldung gelöscht")
    }

    func testWithoutTokensThereIsNoAccess() async {
        let auth = GoogleAuthorization(
            configuration: config, tokenStore: MemoryTokenStore(), clock: { 0 })
        do {
            _ = try await auth.validAccessToken()
            XCTFail("Erwartet: notAuthorized")
        } catch let error as GoogleDriveError {
            XCTAssertEqual(error, .notAuthorized)
        } catch {
            XCTFail("Falscher Fehler: \(error)")
        }
    }

    /// Trennen löscht die Tokens — und sonst nichts.
    func testDisconnectOnlyClearsTheTokens() async {
        let store = MemoryTokenStore(tokens(expiresAt: 10_000_000))
        let auth = GoogleAuthorization(configuration: config, tokenStore: store, clock: { 0 })

        await auth.disconnectDevice()

        XCTAssertNil(store.read())
    }

    /// Der Kontofingerabdruck verrät den Token nicht.
    func testTheAccountFingerprintIsAHash() async {
        let store = MemoryTokenStore(tokens(expiresAt: 0, refresh: "geheim"))
        let auth = GoogleAuthorization(configuration: config, tokenStore: store, clock: { 0 })

        let fingerprint = await auth.accountFingerprint
        XCTAssertNotNil(fingerprint)
        XCTAssertFalse(fingerprint!.contains("geheim"))
        XCTAssertEqual(fingerprint, base64URL(sha256(Array("geheim".utf8))))

        let ohne = GoogleAuthorization(configuration: config, tokenStore: MemoryTokenStore(), clock: { 0 })
        let leer = await ohne.accountFingerprint
        XCTAssertNil(leer)
    }

    // MARK: - Anmeldung

    private final class FakePresenter: GoogleSignInPresenter, @unchecked Sendable {
        var redirect = "http://127.0.0.1:51234"
        private(set) var shown: URL?
        var failure: Error?

        func beginRedirect() async throws -> String { redirect }

        func awaitRedirect(authorizationURL: URL) async throws -> URL {
            if let failure { throw failure }
            shown = authorizationURL
            let items = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let state = items.first { $0.name == "state" }?.value ?? ""
            return URL(string: "\(redirect)/?code=4/abc&state=\(state)")!
        }

        func cancel() {}
    }

    func testSignInStoresTheTokens() async throws {
        let transport = CountingTransport()
        transport.json = #"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#
        let store = MemoryTokenStore()
        let presenter = FakePresenter()
        let auth = GoogleAuthorization(
            configuration: config, tokenStore: store, presenter: presenter,
            transport: transport, clock: { 1_000 })

        try await auth.signIn()

        XCTAssertEqual(store.read()?.accessToken, "at")
        XCTAssertEqual(store.read()?.refreshToken, "rt")
        let shown = try XCTUnwrap(presenter.shown)
        XCTAssertTrue(shown.absoluteString.contains("code_challenge_method=S256"))
        XCTAssertTrue(shown.absoluteString.contains("drive.appdata"))
    }

    /// Ohne Auffrischungstoken hielte die Verbindung eine Stunde und wäre danach
    /// ohne Zutun weg. Das ist kein Erfolg und wird auch nicht als einer
    /// abgelegt.
    func testSignInWithoutARefreshTokenFails() async {
        let transport = CountingTransport()
        transport.json = #"{"access_token":"at","expires_in":3600}"#
        let store = MemoryTokenStore()
        let auth = GoogleAuthorization(
            configuration: config, tokenStore: store, presenter: FakePresenter(),
            transport: transport, clock: { 0 })

        do {
            try await auth.signIn()
            XCTFail("Erwartet: noRefreshToken")
        } catch let error as GoogleOAuthError {
            XCTAssertEqual(error, .noRefreshToken)
        } catch {
            XCTFail("Falscher Fehler: \(error)")
        }
        XCTAssertNil(store.read())
    }

    /// Ein Schlüsselbund, der die Ablage verweigert, meldet das nicht laut.
    /// Die Anmeldung darf dann nicht als gelungen gelten.
    func testSignInFailsWhenTheTokensCannotBeStored() async {
        final class RefusingStore: GoogleTokenStore, @unchecked Sendable {
            func read() -> GoogleTokens? { nil }
            func write(_ tokens: GoogleTokens?) {}
        }
        let transport = CountingTransport()
        transport.json = #"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#
        let auth = GoogleAuthorization(
            configuration: config, tokenStore: RefusingStore(), presenter: FakePresenter(),
            transport: transport, clock: { 0 })
        do {
            try await auth.signIn()
            XCTFail("Erwartet: tokenStorageFailed")
        } catch let error as GoogleOAuthError {
            XCTAssertEqual(error, .tokenStorageFailed)
        } catch {
            XCTFail("Falscher Fehler: \(error)")
        }
    }

    /// Der Desktop-Client (macOS) schickt sein Secret beim Tausch mit — die
    /// Anmeldung selbst bleibt PKCE mit `state`.
    func testSignInSendsTheClientSecretOnlyWhenConfigured() async throws {
        final class FormTransport: DriveTransport, @unchecked Sendable {
            var forms: [String] = []
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                forms.append(String(decoding: request.httpBody ?? Data(), as: UTF8.self))
                return (Data(#"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        var desktop = config
        desktop.clientSecret = "nur-ein-testwert"
        let transport = FormTransport()
        let auth = GoogleAuthorization(
            configuration: desktop, tokenStore: MemoryTokenStore(), presenter: FakePresenter(),
            transport: transport, clock: { 0 })

        try await auth.signIn()

        let form = try XCTUnwrap(transport.forms.first)
        XCTAssertTrue(form.contains("client_secret=nur-ein-testwert"))
        XCTAssertTrue(form.contains("code_verifier="))
    }

    func testWithoutAClientIdSignInIsRefused() async {
        let auth = GoogleAuthorization(
            configuration: GoogleOAuthConfiguration(clientId: "", redirectURI: "x"),
            tokenStore: MemoryTokenStore(), presenter: FakePresenter(), clock: { 0 })
        do {
            try await auth.signIn()
            XCTFail("Erwartet: notConfigured")
        } catch let error as GoogleOAuthError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Falscher Fehler: \(error)")
        }
    }
}

/// Die Prüfung der eingetragenen Client-ID.
///
/// Sie ist keine Förmlichkeit: auf iOS wird aus der Client-ID die
/// Rückleitungsadresse abgeleitet. Steht dort etwas anderes, öffnet sich das
/// Anmeldefenster und kommt nie zurück — ein Fehler, der aussieht wie „Google
/// ist kaputt" und in Wahrheit ein Tippfehler ist.
final class GoogleClientIDTests: XCTestCase {

    func testAWellFormedClientIdIsAccepted() {
        XCTAssertNil(GoogleClientIDStore.validationError(
            for: "123456-abc.apps.googleusercontent.com"))
        // Umschließende Leerzeichen kommen beim Einfügen ständig mit.
        XCTAssertNil(GoogleClientIDStore.validationError(
            for: "  123456-abc.apps.googleusercontent.com \n"))
    }

    func testTheEmptyValueIsRejected() {
        XCTAssertNotNil(GoogleClientIDStore.validationError(for: ""))
        XCTAssertNotNil(GoogleClientIDStore.validationError(for: "   "))
    }

    func testSomethingThatIsNotAClientIdIsRejected() {
        XCTAssertNotNil(GoogleClientIDStore.validationError(for: "falsche-eingabe"))
        XCTAssertNotNil(GoogleClientIDStore.validationError(for: "1234.apps.google.com"))
        // Der reine Suffix ohne Kennung davor ist keine Client-ID.
        XCTAssertNotNil(GoogleClientIDStore.validationError(
            for: ".apps.googleusercontent.com"))
    }

    // MARK: - Woher die Client-ID kommt

    /// Der Normalfall: aus dem Build.
    ///
    /// Ein Eingabefeld gibt es nicht mehr. Es war ein Feld für einen Wert, den
    /// niemand hat, der die App nur benutzt — und eine Anmeldung, die erst
    /// nach einem Besuch in der Google Cloud Console möglich war.
    func testTheClientIdComesFromTheBuild() {
        let decision = GoogleClientIDStore.resolve(
            build: "123456-abc.apps.googleusercontent.com", stored: nil, hasTokens: false)
        XCTAssertEqual(decision?.clientId, "123456-abc.apps.googleusercontent.com")
        XCTAssertEqual(decision?.origin, .build)
        XCTAssertEqual(decision?.cleanUpStored, false)
    }

    /// Ohne Build-Einstellung gibt es nichts anzubieten — und kein Eingabefeld.
    func testWithoutABuildSettingThereIsNoClientId() {
        XCTAssertNil(GoogleClientIDStore.resolve(build: nil, stored: nil, hasTokens: false))
        XCTAssertNil(GoogleClientIDStore.resolve(build: "", stored: "", hasTokens: false))
    }

    /// Wer schon verbunden ist, bleibt es.
    ///
    /// Die Tokens im Schlüsselbund sind zu der von Hand eingetragenen
    /// Client-ID ausgestellt. Würde sie jetzt ignoriert, wäre die Verbindung
    /// nach dem Update weg — ohne Grund und ohne Meldung.
    func testAnEnteredClientIdKeepsWorkingAfterTheUpdate() {
        let decision = GoogleClientIDStore.resolve(
            build: "neu-aus-dem-build.apps.googleusercontent.com",
            stored: "alt-von-hand.apps.googleusercontent.com",
            hasTokens: true)
        XCTAssertEqual(decision?.clientId, "alt-von-hand.apps.googleusercontent.com")
        XCTAssertEqual(decision?.origin, .migrated)
        XCTAssertEqual(decision?.cleanUpStored, false,
                       "Der Wert, zu dem die Tokens gehören, wurde weggeräumt")
    }

    /// Und ohne Build-Einstellung gilt er erst recht.
    func testAnEnteredClientIdAlsoWorksWithoutABuildSetting() {
        let decision = GoogleClientIDStore.resolve(
            build: nil, stored: "alt-von-hand.apps.googleusercontent.com", hasTokens: true)
        XCTAssertEqual(decision?.clientId, "alt-von-hand.apps.googleusercontent.com")
        XCTAssertEqual(decision?.origin, .migrated)
    }

    /// Ohne Tokens hält an einem alten Wert nichts fest.
    ///
    /// Wer früher eine Client-ID eingetragen, sich aber nie verbunden hat — oder
    /// dessen Verbindung inzwischen getrennt ist —, ist in Wahrheit eine neue
    /// Installation. Dann gilt ausschliesslich der Build, und der alte Wert
    /// wird aufgeräumt. Sonst bliebe ein Tippfehler von damals für immer die
    /// benutzte Client-ID.
    func testAnEnteredClientIdWithoutTokensGivesWayToTheBuild() {
        let decision = GoogleClientIDStore.resolve(
            build: "neu-aus-dem-build.apps.googleusercontent.com",
            stored: "alt-von-hand.apps.googleusercontent.com",
            hasTokens: false)
        XCTAssertEqual(decision?.clientId, "neu-aus-dem-build.apps.googleusercontent.com")
        XCTAssertEqual(decision?.origin, .build)
        XCTAssertEqual(decision?.cleanUpStored, true)
    }

    /// Und ohne Tokens und ohne Build gibt es nichts — auch nicht den alten Wert.
    func testAnEnteredClientIdWithoutTokensAndWithoutABuildIsNotUsed() {
        XCTAssertNil(GoogleClientIDStore.resolve(
            build: nil, stored: "alt-von-hand.apps.googleusercontent.com", hasTokens: false))
    }

    /// Die Projektnummer entscheidet, welchen `appDataFolder` ein Gerät sieht.
    func testTheProjectNumberIsReadFromTheClientId() {
        XCTAssertEqual(GoogleClientIDStore.projectNumber(of: "123456-abc.apps.googleusercontent.com"), "123456")
        XCTAssertNil(GoogleClientIDStore.projectNumber(of: "abc-def.apps.googleusercontent.com"))
        XCTAssertNil(GoogleClientIDStore.projectNumber(of: "ohne.apps.googleusercontent.com"))
    }

    /// Zweimal derselbe Wert: einer reicht, und der aus dem Build ist der
    /// bessere.
    func testADuplicateEntryIsTidiedAway() {
        let decision = GoogleClientIDStore.resolve(
            build: "123456-abc.apps.googleusercontent.com",
            stored: "123456-abc.apps.googleusercontent.com",
            hasTokens: true)
        XCTAssertEqual(decision?.origin, .build)
        XCTAssertEqual(decision?.cleanUpStored, true)
    }

    /// Aus der Client-ID entsteht die Rückleitungsadresse für iOS. Genau
    /// deshalb muss die Form stimmen.
    func testTheRedirectSchemeIsDerivedFromTheClientId() {
        let configuration = GoogleOAuthConfiguration(
            clientId: "123456-abc.apps.googleusercontent.com", redirectURI: "")
        XCTAssertEqual(configuration.reversedClientId, "com.googleusercontent.apps.123456-abc")

        let unsinn = GoogleOAuthConfiguration(clientId: "falsch", redirectURI: "")
        XCTAssertNil(unsinn.reversedClientId,
                     "Ohne erkennbare Client-ID darf keine Rückleitung entstehen")
    }
}
