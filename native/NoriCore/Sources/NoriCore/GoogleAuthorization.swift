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

    /// Die zuletzt erteilten Bereiche — aus Googles Tokenantwort, nie geraten.
    var grantedScopes: [String] {
        (tokenStore.read()?.scope ?? "").split(separator: " ").map(String.init)
    }

    /// Anmelden. `additionalScopes` nur für „Mit Fernseher teilen" — dann mit
    /// `include_granted_scopes`, damit `drive.appdata` erhalten bleibt. Ohne
    /// zusätzliche Bereiche ist die Anfrage genau die bisherige.
    func signIn(additionalScopes: [String] = []) async throws {
        guard configuration.isConfigured else { throw GoogleOAuthError.notConfigured }
        guard let presenter else { throw GoogleOAuthError.notConfigured }

        var config = configuration
        config.redirectURI = try await presenter.beginRedirect()
        let extra = additionalScopes.filter { !configuration.scopes.contains($0) }
        config.scopes = configuration.scopes + extra

        let pkce = GoogleOAuth.makePKCE()
        let state = GoogleOAuth.randomState()
        guard let url = GoogleOAuth.authorizationURL(
            configuration: config, pkce: pkce, state: state, includeGrantedScopes: !extra.isEmpty) else {
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
        // Zurücklesen statt vertrauen. Ein Schlüsselbund, der die Ablage
        // verweigert — etwa bei einer App ohne Signatur —, meldet das nicht
        // laut; ohne diese Prüfung sähe die Anmeldung erfolgreich aus und wäre
        // beim ersten Abgleich wieder weg.
        guard tokenStore.read()?.refreshToken == tokens.refreshToken else {
            throw GoogleOAuthError.tokenStorageFailed
        }
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
            var fresh = try await task.value
            // Schickt Google beim Erneuern keine Bereiche mit, gelten die
            // bisherigen. Sonst sähe „Mit Fernseher teilen" nach jeder
            // Erneuerung aus, als fehlte die Zustimmung.
            if fresh.scope == nil { fresh.scope = tokens.scope }
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
/// **Aus dem Build.** Die Build-Einstellung `GOOGLE_CLIENT_ID` landet über die
/// `Info.plist` als `GoogleClientID` in der App — genau wie `TMDB_API_KEY`.
/// Sie steht nicht im Quelltext und nicht im Repository; sie gehört zum
/// Google-Cloud-Projekt des Betreibers.
///
/// **Nicht mehr über die Oberfläche.** Frühere Fassungen von Nori liessen die
/// Client-ID in den Einstellungen eintragen. Das war ein Eingabefeld für einen
/// Wert, den niemand hat, der die App nur benutzt — und eine Anmeldung, die
/// erst nach einem Besuch in der Google Cloud Console möglich war. Die
/// Anmeldung ist jetzt ein Knopf, und die Client-ID ist Sache des Builds.
///
/// Fehlt sie, ist das ein **Build-Fehler** und keine Nutzeraufgabe: die
/// Oberfläche sagt das im Diagnosebereich und bietet kein Feld an, in dem
/// niemand etwas Sinnvolles eintragen könnte.
///
/// **Was von früher übrig ist, wird nur für eine bestehende Verbindung
/// weiter gelesen.** Wer schon verbunden ist, hat seine Tokens zu einer von
/// Hand eingetragenen Client-ID bekommen. Würde die jetzt ignoriert, wäre die
/// Verbindung nach dem Update weg — ohne Grund und ohne Meldung. Sie hat
/// deshalb Vorrang, **solange Tokens dazu vorliegen**. Ohne Tokens hält an dem
/// alten Wert nichts fest: dann gilt wie bei jeder neuen Installation
/// ausschliesslich der Build, und die Kopie im Gerät wird aufgeräumt — ebenso,
/// wenn sie mit der aus dem Build übereinstimmt.
///
/// Einen eingebauten Rückfall gibt es hier **nicht**. Beim TMDB-Schlüssel ist
/// einer vertretbar, weil er nur Bilder holt; eine Google-Client-ID gehört zu
/// einem bestimmten Cloud-Projekt und einem bestimmten Zustimmungsbildschirm.
/// Eine fremde einzubauen hiesse, den Nutzer beim Anmelden den Namen eines
/// fremden Projekts sehen zu lassen.
enum GoogleClientIDStore {
    private static let service = "de.nori.google"
    private static let account = "client_id"
    private static let defaultsKey = "nori.google.clientId"

    /// Woher der benutzte Wert stammt. Für die Diagnose, nie für die Logik.
    enum Origin: Equatable {
        /// Aus `GOOGLE_CLIENT_ID` — der Normalfall.
        case build
        /// Aus einer früheren Fassung, von Hand eingetragen. Wird
        /// weiterbenutzt, damit eine bestehende Verbindung hält.
        case migrated
    }

    /// Die Client-ID aus dem Build, oder `nil`.
    ///
    /// Bei fehlender Build-Einstellung bleibt in der `Info.plist` der
    /// unaufgelöste Platzhalter `$(…)` stehen — der ist keine Client-ID.
    static var fromBuild: String? { infoValue("GoogleClientID") }

    /// Das Client-Secret aus dem Build, oder `nil`.
    ///
    /// Gesetzt wird es nur auf macOS (`GOOGLE_CLIENT_SECRET`, aus einer nicht
    /// eingecheckten `Config/Google.local.xcconfig`): der macOS-Client ist vom
    /// Typ „Desktop-App", und dessen Token-Endpunkt verlangt es. Die
    /// `Info.plist` von iOS hat den Schlüssel gar nicht.
    ///
    /// Nie protokollieren, nie anzeigen.
    static var secretFromBuild: String? { infoValue("GoogleClientSecret") }

    /// Ein Wert aus der `Info.plist` — ohne unaufgelösten Platzhalter `$(…)`.
    private static func infoValue(_ key: String) -> String? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
        return raw
    }

    /// Die Projektnummer vor dem ersten Bindestrich einer Client-ID.
    ///
    /// Der `appDataFolder` gehört zu Projekt **und** Konto. Eine übernommene
    /// Client-ID aus einem anderen Projekt gleicht deshalb in einen anderen
    /// versteckten Ordner ab — die Diagnose soll das sagen können.
    static func projectNumber(of clientId: String) -> String? {
        guard let dash = clientId.firstIndex(of: "-") else { return nil }
        let number = clientId[..<dash]
        return number.isEmpty || !number.allSatisfy(\.isNumber) ? nil : String(number)
    }

    /// Die zu verwendende Client-ID samt Herkunft, oder `nil`.
    ///
    /// Räumt dabei auf: ein alter Wert im Gerät, der mit dem aus dem Build
    /// übereinstimmt oder zu dem keine Tokens mehr gehören, wird entfernt.
    /// Danach gibt es nur noch eine Quelle, und die Diagnose zeigt nicht
    /// länger „übernommen" für etwas, das inzwischen aus dem Build kommt.
    static func resolved(hasTokens: Bool) -> (clientId: String, origin: Origin)? {
        let decision = resolve(build: fromBuild, stored: readLegacy(), hasTokens: hasTokens)
        if decision?.cleanUpStored == true { forgetLegacy() }
        return decision.map { ($0.clientId, $0.origin) }
    }

    /// Die Entscheidung selbst — ohne Schlüsselbund, ohne `Bundle`.
    ///
    /// Eigene Funktion, damit sie prüfbar ist. Ein Test, der dafür in den
    /// Schlüsselbund und in die Voreinstellungen des Entwicklers schreiben
    /// müsste, prüft am Ende die Umgebung und nicht die Regel.
    static func resolve(
        build rawBuild: String?,
        stored: String?,
        hasTokens: Bool
    ) -> (clientId: String, origin: Origin, cleanUpStored: Bool)? {
        let build = rawBuild?.isEmpty == false ? rawBuild : nil
        if let stored, !stored.isEmpty {
            if let build, build == stored { return (build, .build, true) }
            // Der Wert im Gerät hat nur Vorrang, wenn Tokens zu ihm
            // ausgestellt sind. Ihn dann zu übergehen hiesse, eine bestehende
            // Verbindung ohne Grund zu beenden — und die Client-ID eines
            // verbundenen Geräts unkontrolliert auszutauschen.
            if hasTokens { return (stored, .migrated, false) }
            // Ohne Tokens verbindet ihn nichts mehr mit diesem Gerät. Dann gilt
            // wie bei einer neuen Installation ausschliesslich der Build.
            if let build { return (build, .build, true) }
            return nil
        }
        guard let build else { return nil }
        return (build, .build, false)
    }

    /// Sieht der Wert überhaupt nach einer Google-Client-ID aus?
    ///
    /// Die Prüfung ist keine Förmlichkeit: auf iOS wird aus der Client-ID die
    /// Rückleitungsadresse abgeleitet. Steht dort etwas anderes, öffnet sich
    /// das Anmeldefenster und kommt nie zurück — ein Fehler, der aussieht wie
    /// „Google ist kaputt". Geprüft wird damit jetzt die **Build-Einstellung**,
    /// und der Befund landet in der Diagnose.
    static func validationError(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Es ist keine Client-ID hinterlegt." }
        guard trimmed.hasSuffix(".apps.googleusercontent.com") else {
            return "Eine Google-Client-ID endet auf „.apps.googleusercontent.com\"."
        }
        guard trimmed.count > ".apps.googleusercontent.com".count else {
            return "Die Client-ID ist unvollständig."
        }
        return nil
    }

    /// Den von Hand eingetragenen Wert vergessen.
    ///
    /// Danach gilt der aus dem Build. Weil die Tokens zur alten Client-ID
    /// gehören, trennt der Aufrufer das Gerät gleich mit.
    static func forgetLegacy() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        #endif
    }

    /// Der Wert aus einer früheren Fassung: Schlüsselbund, dann
    /// Voreinstellungen.
    ///
    /// Beide Orte, weil beide beschrieben wurden — ohne Signierteam lehnte der
    /// Schlüsselbund die Ablage ab, und die alte Fassung wich auf die
    /// Voreinstellungen aus.
    private static func readLegacy() -> String? {
        if let stored = readKeychain(), !stored.isEmpty { return stored }
        let stored = UserDefaults.standard.string(forKey: defaultsKey)
        return stored?.isEmpty == false ? stored : nil
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
    /// Die zu verwendende Konfiguration: Client-ID aus dem Build, sonst die
    /// migrierte einer bestehenden Verbindung.
    ///
    /// Das Secret nur, wenn der Aufrufer es verlangt (macOS) **und** die
    /// Client-ID aus dem Build stammt — es gehört zu genau diesem Client. Einer
    /// übernommenen ID ein fremdes Secret mitzugeben, ergäbe `invalid_client`.
    static func resolved(hasTokens: Bool, includeSecret: Bool) -> (
        configuration: GoogleOAuthConfiguration, origin: GoogleClientIDStore.Origin
    )? {
        guard let client = GoogleClientIDStore.resolved(hasTokens: hasTokens) else { return nil }
        let secret = includeSecret && client.origin == .build ? GoogleClientIDStore.secretFromBuild : nil
        return (GoogleOAuthConfiguration(clientId: client.clientId, redirectURI: "", clientSecret: secret),
                client.origin)
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
