import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// OAuth gegen Google — der Teil, der auf jeder Plattform gleich ist.
//
// Was hier steht: Adressen bauen, PKCE rechnen, Code gegen Token tauschen,
// Token erneuern, Zugriff widerrufen. Alles mit Foundation und sonst nichts,
// damit es auch für Android übersetzt.
//
// Was hier **nicht** steht: wie ein Anmeldefenster aufgeht. Das ist auf jeder
// Plattform etwas anderes — `ASWebAuthenticationSession` auf iOS, ein
// Loopback-Server auf macOS, der Gerätecode auf dem Fernseher — und gehört
// deshalb in die jeweilige App-Schicht.
//
// Kein Client-Secret. Native Apps sind öffentliche Clients: sie werden auf
// Geräte verteilt und können nichts geheim halten. Google sieht
// `client_secret` für den Installed-App-Fluss deshalb als optional vor, und
// PKCE ersetzt, wofür es einmal gedacht war.
//
// Ausnahme mit Ansage: Googles Fluss für Fernseher verlangt den Wert doch.
// Siehe `docs/google-drive-sync.md` — er betrifft nur webOS und liegt nicht in
// diesem Kern.

struct GoogleOAuthConfiguration: Sendable, Equatable {
    var clientId: String
    /// Wohin Google nach der Zustimmung zurückschickt.
    ///
    /// Auf macOS ein Loopback (`http://127.0.0.1:<port>`), auf iOS das
    /// umgedrehte Client-Kürzel. **Nicht** `urn:ietf:wg:oauth:2.0:oob` — den
    /// Weg hat Google 2022 abgeschaltet.
    var redirectURI: String
    /// Nur, was gebraucht wird. Kein `email`, kein `profile`: für den
    /// Abgleich einer Bibliothek geht Google niemand etwas an.
    var scopes: [String] = [GoogleDriveClient.scope]

    var isConfigured: Bool { !clientId.isEmpty }
}

/// Was nach einer erfolgreichen Anmeldung übrig bleibt.
///
/// Gehört in den Schlüsselbund und **nirgendwo sonst**: nicht in
/// `library.json`, nicht ins Protokoll, nicht in einen Absturzbericht und
/// schon gar nicht in die Cloud.
struct GoogleTokens: Codable, Equatable, Sendable {
    var accessToken: String
    /// Nur beim ersten Mal dabei. Wer ihn beim Erneuern überschreibt, verliert
    /// ihn — Google schickt ihn dann nicht erneut.
    var refreshToken: String?
    /// Millisekunden seit 1970.
    var expiresAt: Double
    var scope: String?

    /// Eine Minute Vorlauf.
    ///
    /// Ein Token, das in fünf Sekunden abläuft, ist praktisch abgelaufen: die
    /// Anfrage ist noch unterwegs, wenn es so weit ist. Der Vorlauf spart den
    /// `401`, der sonst regelmäßig als erstes zurückkäme.
    func isValid(at now: Double, leeway: Double = 60_000) -> Bool {
        !accessToken.isEmpty && expiresAt - leeway > now
    }
}

enum GoogleOAuthError: Error, Equatable {
    case notConfigured
    case cancelled
    /// Der `state` der Antwort passt nicht zu dem der Anfrage. Entweder ein
    /// Fehler — oder jemand hat eine fremde Antwort untergeschoben.
    case stateMismatch
    case denied(String)
    case noRefreshToken
    case server(String)
    case transport(String)
}

enum GoogleOAuth {
    static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    static let revocationEndpoint = "https://oauth2.googleapis.com/revoke"
    static let deviceCodeEndpoint = "https://oauth2.googleapis.com/device/code"

    // MARK: - PKCE

    /// Der Nachweis, dass derselbe hier fragt, der vorher gefragt hat.
    ///
    /// Ohne PKCE reichte es, den Autorisierungscode abzufangen — bei einem
    /// öffentlichen Client ist er sonst durch nichts geschützt. Mit PKCE ist er
    /// ohne den `verifier` wertlos, und der hat das Gerät nie verlassen.
    struct PKCE: Equatable, Sendable {
        let verifier: String
        let challenge: String
        let method = "S256"
    }

    static func makePKCE(verifier: String? = nil) -> PKCE {
        let value = verifier ?? randomVerifier()
        return PKCE(verifier: value, challenge: base64URL(sha256(Array(value.utf8))))
    }

    /// 43 bis 128 Zeichen aus dem in RFC 7636 erlaubten Vorrat.
    static func randomVerifier(length: Int = 64) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<max(43, min(128, length))).map { _ in
            alphabet[Int(generator.next(upperBound: UInt64(alphabet.count)))]
        })
    }

    static func randomState() -> String { randomVerifier(length: 43) }

    // MARK: - Adressen

    static func authorizationURL(
        configuration: GoogleOAuthConfiguration,
        pkce: PKCE,
        state: String,
        loginHint: String? = nil
    ) -> URL? {
        guard configuration.isConfigured else { return nil }
        var components = URLComponents(string: authorizationEndpoint)
        var items = [
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
            // Ohne `offline` gibt Google keinen Auffrischungstoken heraus, und
            // die Verbindung hielte eine Stunde.
            URLQueryItem(name: "access_type", value: "offline"),
            // `consent` bleibt, obwohl es einen Bildschirm mehr bedeutet:
            // Google gibt den Auffrischungstoken nur heraus, wenn die
            // Zustimmung in diesem Durchlauf tatsächlich erteilt wird. Hat der
            // Nutzer früher schon zugestimmt, überspringt Google den Schritt
            // sonst — und antwortet ohne `refresh_token`. Genau das prüft
            // `GoogleAuthorization.signIn` und wirft `noRefreshToken`; eine
            // Anmeldung, die nach einer Stunde ohne Zutun endet, ist kein
            // Erfolg.
            //
            // Es zwingt niemanden zu einer Passworteingabe: die
            // Browser-Sitzung ist auf beiden Apple-Plattformen die geteilte,
            // der Nutzer bleibt bei Google angemeldet und bestätigt einmal.
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        if let loginHint { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        components?.queryItems = items
        return components?.url
    }

    /// Den Code aus der Rückleitung holen — und prüfen, dass er zu uns gehört.
    static func code(from url: URL, expectedState: String) throws -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw error == "access_denied"
                ? GoogleOAuthError.cancelled
                : GoogleOAuthError.denied(error)
        }
        guard value("state") == expectedState else { throw GoogleOAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw GoogleOAuthError.denied("Kein Code in der Antwort") }
        return code
    }

    // MARK: - Token

    static func exchange(
        code: String,
        configuration: GoogleOAuthConfiguration,
        pkce: PKCE,
        transport: DriveTransport = URLSessionDriveTransport(),
        now: Double = Date().timeIntervalSince1970 * 1000
    ) async throws -> GoogleTokens {
        try await token(form: [
            "client_id": configuration.clientId,
            "code": code,
            "code_verifier": pkce.verifier,
            "grant_type": "authorization_code",
            "redirect_uri": configuration.redirectURI,
        ], transport: transport, now: now)
    }

    static func refresh(
        refreshToken: String,
        configuration: GoogleOAuthConfiguration,
        transport: DriveTransport = URLSessionDriveTransport(),
        now: Double = Date().timeIntervalSince1970 * 1000
    ) async throws -> GoogleTokens {
        var tokens = try await token(form: [
            "client_id": configuration.clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ], transport: transport, now: now)
        // Beim Erneuern schickt Google keinen neuen Refresh-Token. Wer den
        // alten hier nicht wieder einsetzt, hat nach einer Stunde keine
        // Verbindung mehr und weiß nicht, warum.
        tokens.refreshToken = tokens.refreshToken ?? refreshToken
        return tokens
    }

    /// Den Zugriff bei Google vollständig zurückziehen.
    ///
    /// Betrifft **alle** Geräte an diesem Konto, nicht nur dieses. Deshalb
    /// gehört das hinter eine eigene, deutlich benannte Aktion und nicht hinter
    /// „Abmelden".
    static func revoke(
        token: String,
        transport: DriveTransport = URLSessionDriveTransport()
    ) async throws {
        var request = URLRequest(url: URL(string: revocationEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form(["token": token]).utf8)
        let (data, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw GoogleOAuthError.server(errorText(in: data))
        }
    }

    private static func token(
        form fields: [String: String],
        transport: DriveTransport,
        now: Double
    ) async throws -> GoogleTokens {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form(fields).utf8)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw GoogleOAuthError.transport(error.localizedDescription)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleOAuthError.server("Antwort nicht lesbar")
        }
        guard (200...299).contains(response.statusCode) else {
            throw GoogleOAuthError.server((object["error"] as? String) ?? "HTTP \(response.statusCode)")
        }
        guard let accessToken = object["access_token"] as? String else {
            throw GoogleOAuthError.server("Antwort ohne Token")
        }
        let lifetime = (object["expires_in"] as? Double) ?? 3600
        return GoogleTokens(
            accessToken: accessToken,
            refreshToken: object["refresh_token"] as? String,
            expiresAt: now + lifetime * 1000,
            scope: object["scope"] as? String
        )
    }

    static func form(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.sorted { $0.key < $1.key }.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
    }

    static func errorText(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return (object["error_description"] as? String) ?? (object["error"] as? String) ?? ""
    }
}

// MARK: - SHA-256

/// SHA-256 von Hand, für PKCE.
///
/// `CryptoKit` gibt es nur auf Apple, und der Kern übersetzt auch für Android.
/// Zwei Zweige hießen zwei Implementierungen, von denen nur eine getestet wird;
/// eine reicht, sie ist knapp sechzig Zeilen und läuft genau einmal je
/// Anmeldung. Geprüft wird sie gegen die Testvektoren aus RFC 6234 und den
/// PKCE-Vektor aus RFC 7636.
func sha256(_ message: [UInt8]) -> [UInt8] {
    var h: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]
    let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    var padded = message
    let bitLength = UInt64(message.count) * 8
    padded.append(0x80)
    while padded.count % 64 != 56 { padded.append(0) }
    for shift in stride(from: 56, through: 0, by: -8) { padded.append(UInt8((bitLength >> UInt64(shift)) & 0xff)) }

    for chunk in stride(from: 0, to: padded.count, by: 64) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            let base = chunk + i * 4
            w[i] = (UInt32(padded[base]) << 24) | (UInt32(padded[base + 1]) << 16)
                | (UInt32(padded[base + 2]) << 8) | UInt32(padded[base + 3])
        }
        for i in 16..<64 {
            let s0 = rotate(w[i - 15], 7) ^ rotate(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotate(w[i - 2], 17) ^ rotate(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }

        var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
        for i in 0..<64 {
            let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
            let ch = (e & f) ^ (~e & g)
            let temp1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
            let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0 &+ maj
            hh = g; g = f; f = e; e = d &+ temp1
            d = c; c = b; b = a; a = temp1 &+ temp2
        }
        h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
        h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
    }

    return h.flatMap { word in
        [UInt8((word >> 24) & 0xff), UInt8((word >> 16) & 0xff), UInt8((word >> 8) & 0xff), UInt8(word & 0xff)]
    }
}

private func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
    (value >> count) | (value << (32 - count))
}

/// Base64 ohne Polsterung und ohne `+` und `/` — so verlangt es RFC 7636.
func base64URL(_ bytes: [UInt8]) -> String {
    Data(bytes).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
