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

/// Wo die Google-Client-ID herkommt.
///
/// Zwei Quellen, in dieser Reihenfolge: der Schlüsselbund, dann die
/// Build-Einstellung aus der `Info.plist`. Genau wie beim TMDB-Schlüssel — und
/// aus demselben Grund.
///
/// Ohne den Schlüsselbund-Weg wäre der Abgleich nur für den einrichtbar, der
/// Nori selbst übersetzt: eine fertig installierte App hätte keine
/// Client-ID und böte gar keine Anmeldung an. Das ist kein theoretischer Fall,
/// sondern der Normalfall.
///
/// Einen eingebauten Rückfall gibt es hier **nicht**. Beim TMDB-Schlüssel ist
/// einer vertretbar, weil er nur Bilder holt; eine Google-Client-ID gehört zu
/// einem bestimmten Cloud-Projekt und einem bestimmten Zustimmungsbildschirm.
/// Eine fremde einzubauen hieße, den Nutzer beim Anmelden den Namen eines
/// fremden Projekts sehen zu lassen.
enum GoogleClientIDStore {
    private static let service = "de.nori.google"
    private static let account = "client_id"
    private static let defaultsKey = "nori.google.clientId"

    /// Die zu verwendende Client-ID oder `nil`, wenn keine hinterlegt ist.
    static var current: String? {
        if let stored = readUserProvided(), !stored.isEmpty { return stored }
        let bundled = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String
        // Bei fehlender Build-Einstellung bleibt in der Info.plist der
        // unaufgelöste Platzhalter stehen — der ist keine Client-ID.
        if let bundled, !bundled.isEmpty, !bundled.hasPrefix("$(") { return bundled }
        return nil
    }

    /// Wurde sie von Hand eingetragen — und lässt sich damit auch entfernen?
    static var isUserProvided: Bool { readUserProvided()?.isEmpty == false }

    /// Schlüsselbund zuerst, danach die Voreinstellungen.
    ///
    /// Der zweite Weg ist kein Versehen. Ohne Signierteam bekommt eine
    /// iOS-App keine `application-identifier`-Berechtigung, und dann lehnt der
    /// Schlüsselbund **jede** Ablage ab — die Einrichtung endete mit „Der
    /// Schlüsselbund hat die Ablage abgelehnt", und der Abgleich wäre wieder
    /// unerreichbar.
    ///
    /// Vertretbar ist das nur, weil eine Client-ID kein Geheimnis ist: sie
    /// steht in jeder Anmeldeadresse, die Nori öffnet, und lässt sich ohne die
    /// Zustimmung eines Nutzers zu nichts verwenden.
    ///
    /// Für **Tokens** gilt das ausdrücklich nicht. Die liegen in
    /// `KeychainTokenStore` und bekommen keinen solchen Rückfall; wo der
    /// Schlüsselbund fehlt, gibt es eben keine gespeicherte Anmeldung.
    private static func readUserProvided() -> String? {
        if let stored = readKeychain(), !stored.isEmpty { return stored }
        let stored = UserDefaults.standard.string(forKey: defaultsKey)
        return stored?.isEmpty == false ? stored : nil
    }

    /// Sieht der Wert überhaupt nach einer Google-Client-ID aus?
    ///
    /// Die Prüfung ist keine Förmlichkeit: auf iOS wird aus der Client-ID die
    /// Rückleitungsadresse abgeleitet. Steht dort etwas anderes, öffnet sich
    /// das Anmeldefenster und kommt nie zurück — ein Fehler, der aussieht wie
    /// „Google ist kaputt".
    static func validationError(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Bitte eine Client-ID eintragen." }
        guard trimmed.hasSuffix(".apps.googleusercontent.com") else {
            return "Eine Google-Client-ID endet auf „.apps.googleusercontent.com\"."
        }
        guard trimmed.count > ".apps.googleusercontent.com".count else {
            return "Die Client-ID ist unvollständig."
        }
        return nil
    }

    @discardableResult
    static func save(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return clear() }
        if saveToKeychain(trimmed) { return true }
        // Der Schlüsselbund steht nicht zur Verfügung. Siehe
        // `readUserProvided` — für eine Client-ID ist das tragbar.
        UserDefaults.standard.set(trimmed, forKey: defaultsKey)
        return true
    }

    private static func saveToKeychain(_ value: String) -> Bool {
        #if canImport(Security)
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess { return true }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        #else
        return false
        #endif
    }

    @discardableResult
    static func clear() -> Bool {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
        #else
        return true
        #endif
    }

    private static func readKeychain() -> String? {
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
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }
}

extension GoogleOAuthConfiguration {
    /// Die Client-ID aus dem Schlüsselbund oder der `Info.plist`.
    static func resolved() -> GoogleOAuthConfiguration? {
        GoogleClientIDStore.current.map { GoogleOAuthConfiguration(clientId: $0, redirectURI: "") }
    }

    /// Die Client-ID aus der `Info.plist`.
    ///
    /// Wie der TMDB-Schlüssel: nicht im Quelltext, sondern über eine
    /// Build-Einstellung. Eine Client-ID ist zwar kein Geheimnis — sie steht in
    /// jeder Anmeldeadresse —, aber sie gehört zum Google-Cloud-Projekt des
    /// Betreibers und nicht in ein Repository.
    ///
    /// Fehlt die Build-Einstellung, bleibt in der `Info.plist` der unaufgelöste
    /// Platzhalter `$(…)` stehen. Der ist keine Client-ID, und die Oberfläche
    /// sagt dann „nicht eingerichtet" statt eine Anmeldung anzubieten, die
    /// sicher scheitert.
    static func fromBundle(key: String = "GoogleClientID") -> GoogleOAuthConfiguration? {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String
        guard let raw, !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
        return GoogleOAuthConfiguration(clientId: raw, redirectURI: "")
    }

    /// Das umgedrehte Client-Kürzel, wie iOS es als Rückleitungsschema
    /// erwartet: aus `1234-abc.apps.googleusercontent.com` wird
    /// `com.googleusercontent.apps.1234-abc`.
    var reversedClientId: String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientId.hasSuffix(suffix) else { return nil }
        return "com.googleusercontent.apps." + String(clientId.dropLast(suffix.count))
    }
}
