import XCTest
@testable import NoriCore

/// OAuth gegen Google, soweit es ohne Google prüfbar ist: PKCE, die gebaute
/// Adresse, die Auswertung der Rückleitung und der Tausch Code gegen Token.
final class GoogleOAuthTests: XCTestCase {

    private let config = GoogleOAuthConfiguration(
        clientId: "1234.apps.googleusercontent.com",
        redirectURI: "http://127.0.0.1:51234"
    )

    // MARK: - SHA-256

    /// Die Testvektoren aus RFC 6234. Eine selbst geschriebene Hashfunktion
    /// ohne sie wäre eine Behauptung.
    func testSha256MatchesTheKnownVectors() {
        func hash(_ text: String) -> String {
            sha256(Array(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        XCTAssertEqual(hash(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(hash("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(hash("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        // Länger als ein Block, damit auch die Schleife geprüft ist.
        XCTAssertEqual(hash(String(repeating: "a", count: 1000)),
            "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    /// Der Vektor aus RFC 7636, Anhang B — genau der Fall, um den es geht.
    func testPkceMatchesTheRfcVector() {
        let pkce = GoogleOAuth.makePKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(pkce.method, "S256")
    }

    func testVerifiersAreLongEnoughAndUnique() {
        let a = GoogleOAuth.randomVerifier()
        let b = GoogleOAuth.randomVerifier()
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThanOrEqual(a.count, 43)
        XCTAssertLessThanOrEqual(a.count, 128)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        XCTAssertTrue(a.unicodeScalars.allSatisfy(allowed.contains))
    }

    // MARK: - Anmeldeadresse

    func testAuthorizationURLAsksForTheSmallestScope() throws {
        let pkce = GoogleOAuth.makePKCE()
        let url = try XCTUnwrap(GoogleOAuth.authorizationURL(
            configuration: config, pkce: pkce, state: "zustand"))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(value("scope"), "https://www.googleapis.com/auth/drive.appdata",
                       "Nori fragt mehr ab als den versteckten Ordner")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge"), pkce.challenge)
        XCTAssertEqual(value("state"), "zustand")
        XCTAssertEqual(value("access_type"), "offline", "Ohne das hielte die Verbindung eine Stunde")
        XCTAssertEqual(value("redirect_uri"), "http://127.0.0.1:51234")
        XCTAssertNil(value("client_secret"), "Ein Client-Secret hat in einer App nichts zu suchen")
        XCTAssertTrue(url.absoluteString.hasPrefix("https://accounts.google.com/"))

        // `consent` kostet einen Bildschirm und bleibt trotzdem: Google gibt
        // den Auffrischungstoken nur heraus, wenn die Zustimmung in diesem
        // Durchlauf erteilt wird. Ohne ihn endete die Verbindung nach einer
        // Stunde von selbst.
        XCTAssertEqual(value("prompt"), "consent")
        // Kein `email`, kein `profile`, kein `openid`: für den Abgleich einer
        // Merkliste geht Google niemand etwas an.
        let scope = value("scope") ?? ""
        for unerwünscht in ["email", "profile", "openid", "drive.file"] {
            XCTAssertFalse(scope.contains(unerwünscht),
                           "Nori fragt \(unerwünscht) ab, ohne es zu brauchen")
        }
    }

    /// Der abgeschaltete Weg von 2022 darf nirgends auftauchen.
    func testNoOutOfBandRedirect() {
        XCTAssertFalse(config.redirectURI.contains("urn:ietf:wg:oauth:2.0:oob"))
        XCTAssertTrue(config.redirectURI.hasPrefix("http://127.0.0.1")
            || config.redirectURI.hasPrefix("https://"))
    }

    func testWithoutAClientIdThereIsNoURL() {
        let leer = GoogleOAuthConfiguration(clientId: "", redirectURI: "http://127.0.0.1:1")
        XCTAssertNil(GoogleOAuth.authorizationURL(
            configuration: leer, pkce: GoogleOAuth.makePKCE(), state: "x"))
    }

    // MARK: - Rückleitung

    func testCodeIsReadFromTheRedirect() throws {
        let url = URL(string: "http://127.0.0.1:51234/?code=4/abc&state=zustand")!
        XCTAssertEqual(try GoogleOAuth.code(from: url, expectedState: "zustand"), "4/abc")
    }

    /// Ein fremder `state` heißt: die Antwort gehört nicht zu dieser Anfrage.
    func testMismatchedStateIsRejected() {
        let url = URL(string: "http://127.0.0.1:51234/?code=4/abc&state=fremd")!
        XCTAssertThrowsError(try GoogleOAuth.code(from: url, expectedState: "zustand")) { error in
            XCTAssertEqual(error as? GoogleOAuthError, .stateMismatch)
        }
    }

    func testDeniedAccessIsACancellation() {
        let url = URL(string: "http://127.0.0.1:51234/?error=access_denied&state=zustand")!
        XCTAssertThrowsError(try GoogleOAuth.code(from: url, expectedState: "zustand")) { error in
            XCTAssertEqual(error as? GoogleOAuthError, .cancelled)
        }
    }

    // MARK: - Token

    private final class Reply: DriveTransport, @unchecked Sendable {
        let status: Int
        let body: Data
        private(set) var sent: URLRequest?
        init(status: Int = 200, json: String) {
            self.status = status
            self.body = Data(json.utf8)
        }
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            sent = request
            return (body, HTTPURLResponse(url: request.url!, statusCode: status,
                                          httpVersion: nil, headerFields: nil)!)
        }
        var form: String { String(decoding: sent?.httpBody ?? Data(), as: UTF8.self) }
    }

    func testCodeIsExchangedForTokens() async throws {
        let reply = Reply(json: #"{"access_token":"at","refresh_token":"rt","expires_in":3600,"scope":"x"}"#)
        let pkce = GoogleOAuth.makePKCE()

        let tokens = try await GoogleOAuth.exchange(
            code: "4/abc", configuration: config, pkce: pkce, transport: reply, now: 1_000_000)

        XCTAssertEqual(tokens.accessToken, "at")
        XCTAssertEqual(tokens.refreshToken, "rt")
        XCTAssertEqual(tokens.expiresAt, 1_000_000 + 3_600_000)
        XCTAssertTrue(reply.form.contains("code_verifier=\(pkce.verifier)"))
        XCTAssertTrue(reply.form.contains("grant_type=authorization_code"))
        XCTAssertFalse(reply.form.contains("client_secret"))
    }

    /// Beim Erneuern schickt Google keinen neuen Refresh-Token mit. Wer den
    /// alten nicht wieder einsetzt, ist nach einer Stunde abgemeldet.
    func testRefreshKeepsTheExistingRefreshToken() async throws {
        let reply = Reply(json: #"{"access_token":"neu","expires_in":3599}"#)

        let tokens = try await GoogleOAuth.refresh(
            refreshToken: "rt", configuration: config, transport: reply, now: 5_000)

        XCTAssertEqual(tokens.accessToken, "neu")
        XCTAssertEqual(tokens.refreshToken, "rt")
        XCTAssertTrue(reply.form.contains("grant_type=refresh_token"))
        XCTAssertFalse(reply.form.contains("client_secret"), "Der iOS-Client hat kein Secret")
    }

    /// Der macOS-Client ist vom Typ „Desktop-App". Googles Token-Endpunkt
    /// antwortet dort ohne Secret mit `client_secret is missing` — beim Tausch
    /// und beim Erneuern. Gemessen am echten Endpunkt, deshalb geprüft an
    /// beiden Stellen.
    func testTheDesktopClientSendsItsSecretOnExchangeAndRefresh() async throws {
        var desktop = config
        desktop.clientSecret = "nur-ein-testwert"

        let exchange = Reply(json: #"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#)
        _ = try await GoogleOAuth.exchange(
            code: "4/abc", configuration: desktop, pkce: GoogleOAuth.makePKCE(), transport: exchange, now: 0)
        XCTAssertTrue(exchange.form.contains("client_secret=nur-ein-testwert"))

        let refresh = Reply(json: #"{"access_token":"neu","expires_in":3599}"#)
        _ = try await GoogleOAuth.refresh(
            refreshToken: "rt", configuration: desktop, transport: refresh, now: 0)
        XCTAssertTrue(refresh.form.contains("client_secret=nur-ein-testwert"))
    }

    /// Ein leeres Secret ist keines und wird nicht als leeres Feld geschickt.
    func testAnEmptySecretIsNotSent() async throws {
        var leer = config
        leer.clientSecret = ""
        let reply = Reply(json: #"{"access_token":"neu","expires_in":3599}"#)
        _ = try await GoogleOAuth.refresh(refreshToken: "rt", configuration: leer, transport: reply, now: 0)
        XCTAssertFalse(reply.form.contains("client_secret"))
    }

    func testServerErrorsAreReported() async {
        let reply = Reply(status: 400, json: #"{"error":"invalid_grant"}"#)
        do {
            _ = try await GoogleOAuth.refresh(
                refreshToken: "alt", configuration: config, transport: reply, now: 0)
            XCTFail("Erwartet: Fehler")
        } catch let error as GoogleOAuthError {
            XCTAssertEqual(error, .server("invalid_grant"))
        } catch {
            XCTFail("Falscher Fehler: \(error)")
        }
    }

    /// Ein Token, das gleich abläuft, ist praktisch abgelaufen — die Anfrage
    /// ist noch unterwegs, wenn es so weit ist.
    func testTokensExpireWithSomeLeeway() {
        let tokens = GoogleTokens(accessToken: "at", refreshToken: "rt", expiresAt: 100_000, scope: nil)
        XCTAssertTrue(tokens.isValid(at: 0))
        XCTAssertFalse(tokens.isValid(at: 99_000), "Zehn Sekunden Restlaufzeit gelten noch als gültig")
        XCTAssertFalse(tokens.isValid(at: 200_000))
        XCTAssertFalse(GoogleTokens(accessToken: "", refreshToken: nil, expiresAt: .greatestFiniteMagnitude, scope: nil)
            .isValid(at: 0))
    }

    func testFormEncodingEscapesScopesAndCodes() {
        let encoded = GoogleOAuth.form(["scope": "https://www.googleapis.com/auth/drive.appdata", "code": "4/a+b"])
        XCTAssertTrue(encoded.contains("scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive.appdata"))
        XCTAssertTrue(encoded.contains("code=4%2Fa%2Bb"))
    }
}
