import Foundation
#if canImport(Security)
import Security
#endif

// Wo die Tokens liegen und wer sie erneuert.
//
// Zugriffs- und Auffrischungstoken sind das Empfindlichste, was Nori je in die
// Hand bekommt. Sie gehören in den Schlüsselbund und **nirgendwo sonst**:
// nicht in `library.json`, nicht ins Protokoll, nicht in einen Absturzbericht
// und schon gar nicht in die Cloud, die sie gerade aufschließen.

/// Wohin die Tokens gelegt werden.
///
/// Austauschbar, weil „sicherer Speicher" auf jeder Plattform etwas anderes
/// heißt — und damit die Tests nicht in den Schlüsselbund des Entwicklers
/// schreiben.
protocol GoogleTokenStore: AnyObject, Sendable {
    func read() -> GoogleTokens?
    func write(_ tokens: GoogleTokens?)
}

/// Der Schlüsselbund. Auf Apple die richtige Antwort, sonst gar keine.
final class KeychainTokenStore: GoogleTokenStore, @unchecked Sendable {
    private let service: String
    private let account: String

    init(service: String = "de.nori.google", account: String = "oauth_tokens") {
        self.service = service
        self.account = account
    }

    func read() -> GoogleTokens? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: data)
        #else
        // Android hat keinen Schlüsselbund dieser Art. Ein eigener Ablageort
        // gehört in die Android-App, nicht in den geteilten Kern — dort wäre er
        // auf Apple toter Code.
        return nil
        #endif
    }

    func write(_ tokens: GoogleTokens?) {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess { return }
        var insert = query
        insert[kSecValueData as String] = data
        // Nicht `WhenUnlocked`: der Abgleich läuft auch, während das Gerät in
        // der Tasche steckt.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
        #endif
    }
}

/// Nur für Tests.
final class MemoryTokenStore: GoogleTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: GoogleTokens?

    init(_ tokens: GoogleTokens? = nil) { self.tokens = tokens }

    func read() -> GoogleTokens? {
        lock.lock(); defer { lock.unlock() }
        return tokens
    }

    func write(_ tokens: GoogleTokens?) {
        lock.lock(); defer { lock.unlock() }
        self.tokens = tokens
    }
}

/// Wie das Anmeldefenster aufgeht.
///
/// Auf jeder Plattform anders — `ASWebAuthenticationSession` auf iOS, ein
/// Loopback-Server auf macOS — und deshalb hier nur als Loch in der Wand.
protocol GoogleSignInPresenter: AnyObject, Sendable {
    /// Die Rückleitungsadresse für diese Anmeldung.
    ///
    /// Ein eigener Aufruf, weil sie auf macOS erst feststeht, wenn der
    /// Loopback-Server läuft und seinen Port kennt.
    func beginRedirect() async throws -> String
    /// Anmeldung zeigen und auf die Rückleitung warten.
    func awaitRedirect(authorizationURL: URL) async throws -> URL
    func cancel()
}

/// Der Tokenlebenszyklus an einer Stelle.
///
/// `actor`, damit nicht zwei Anfragen gleichzeitig denselben abgelaufenen
/// Token erneuern. Ohne das schickte Google beim zweiten Versuch
/// `invalid_grant`, und die Verbindung wäre weg — mitten im Abgleich, ohne
/// erkennbaren Grund.
actor GoogleAuthorization: GoogleAuthorizationProvider {
    private let configuration: GoogleOAuthConfiguration
    private let tokenStore: GoogleTokenStore
    private let presenter: GoogleSignInPresenter?
    private let transport: DriveTransport
    private let clock: @Sendable () -> Double
    private var refreshTask: Task<GoogleTokens, Error>?

    init(
        configuration: GoogleOAuthConfiguration,
        tokenStore: GoogleTokenStore,
        presenter: GoogleSignInPresenter? = nil,
        transport: DriveTransport = URLSessionDriveTransport(),
        clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 * 1000 }
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.presenter = presenter
        self.transport = transport
        self.clock = clock
    }

    var isConnected: Bool { tokenStore.read()?.refreshToken != nil }

    /// Womit sich ein Kontowechsel erkennen lässt, ohne nach dem Konto zu
    /// fragen.
    ///
    /// Nori fordert weder `email` noch `profile` an — für den Abgleich einer
    /// Merkliste geht Google niemand etwas an. Damit gibt es aber auch keine
    /// Kontokennung. Genommen wird deshalb ein Hash des Auffrischungstokens:
    /// ein anderes Konto hat einen anderen, und der Hash selbst verrät nichts.
    ///
    /// Er ändert sich auch, wenn dasselbe Konto erneut zustimmt. Das ist
    /// verkraftbar: die Engine sucht die eigene Datei notfalls über die
    /// Gerätekennung wieder, statt eine zweite anzulegen.
    var accountFingerprint: String? {
        guard let refresh = tokenStore.read()?.refreshToken else { return nil }
        return base64URL(sha256(Array(refresh.utf8)))
    }

    // MARK: - Anmelden

    func signIn() async throws {
        guard configuration.isConfigured else { throw GoogleOAuthError.notConfigured }
        guard let presenter else { throw GoogleOAuthError.notConfigured }

        var config = configuration
        config.redirectURI = try await presenter.beginRedirect()

        let pkce = GoogleOAuth.makePKCE()
        let state = GoogleOAuth.randomState()
        guard let url = GoogleOAuth.authorizationURL(configuration: config, pkce: pkce, state: state) else {
            throw GoogleOAuthError.notConfigured
        }

        let callback = try await presenter.awaitRedirect(authorizationURL: url)
        let code = try GoogleOAuth.code(from: callback, expectedState: state)
        let tokens = try await GoogleOAuth.exchange(
            code: code, configuration: config, pkce: pkce, transport: transport, now: clock())
        guard tokens.refreshToken != nil else {
            // Ohne Auffrischungstoken hielte die Verbindung eine Stunde und
            // wäre danach ohne Zutun weg. Das ist kein Erfolg.
            throw GoogleOAuthError.noRefreshToken
        }
        tokenStore.write(tokens)
    }

    // MARK: - Token

    func validAccessToken() async throws -> String {
        guard let tokens = tokenStore.read() else { throw GoogleDriveError.notAuthorized }
        if tokens.isValid(at: clock()) { return tokens.accessToken }
        return try await refreshAccessToken()
    }

    func refreshAccessToken() async throws -> String {
        // Läuft schon eine Erneuerung, wird deren Ergebnis abgewartet. Zwei
        // gleichzeitige Erneuerungen desselben Tokens beantwortet Google mit
        // `invalid_grant` — und dann ist die Verbindung weg.
        if let refreshTask { return try await refreshTask.value.accessToken }

        guard let tokens = tokenStore.read(), let refreshToken = tokens.refreshToken else {
            throw GoogleDriveError.notAuthorized
        }

        let task = Task { [configuration, transport, clock] in
            try await GoogleOAuth.refresh(
                refreshToken: refreshToken, configuration: configuration,
                transport: transport, now: clock())
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let fresh = try await task.value
            tokenStore.write(fresh)
            return fresh.accessToken
        } catch let error as GoogleOAuthError {
            if case .server(let reason) = error, reason == "invalid_grant" {
                // Der Auffrischungstoken gilt nicht mehr: widerrufen, Passwort
                // geändert, zu lange nicht benutzt. Er ist wertlos und wird
                // weggeräumt, damit die Oberfläche „neu verbinden" anbieten
                // kann statt endlos zu scheitern.
                tokenStore.write(nil)
                throw GoogleDriveError.notAuthorized
            }
            throw error
        }
    }

    // MARK: - Trennen

    /// Dieses Gerät trennen: Tokens weg, sonst nichts.
    ///
    /// Die Bibliothek bleibt, die Drive-Dateien bleiben, die anderen Geräte
    /// gleichen weiter ab.
    func disconnectDevice() {
        tokenStore.write(nil)
    }

    /// Den Zugriff bei Google vollständig zurückziehen.
    ///
    /// Betrifft **alle** Geräte an diesem Konto. Gehört deshalb hinter eine
    /// eigene, deutlich benannte Aktion — nicht hinter „Abmelden".
    func revokeAccess() async throws {
        guard let tokens = tokenStore.read() else { return }
        defer { tokenStore.write(nil) }
        try await GoogleOAuth.revoke(token: tokens.refreshToken ?? tokens.accessToken, transport: transport)
    }
}
