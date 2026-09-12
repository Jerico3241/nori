import Foundation
import Observation

// Der Zusammenbau: aus Client-ID, Schlüsselbund, Drive und Store wird ein
// Abgleich.
//
// Diese Datei liegt im gemeinsamen Kern und nicht zweimal in den Apps. Der
// Unterschied zwischen iOS und macOS ist genau zweierlei — wie das
// Anmeldefenster aufgeht (`GoogleSignInPresenter`) und ob der Client ein
// Secret braucht (`requiresClientSecret`). Alles andere wäre doppelter Code,
// der beim nächsten Mal nur an einer der beiden Stellen repariert wird.

/// Die Merkposten der Engine in den `UserDefaults`.
///
/// Ausdrücklich nicht in `library.json`: die Drive-Dateikennung gehört zu einem
/// Google-Konto und nicht zu den Daten. Stünde sie dort, wanderte sie beim
/// nächsten Abgleich auf alle anderen Geräte — und die schrieben dann in
/// *diese* Datei.
final class UserDefaultsBookkeeping: SyncBookkeeping {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func syncValue(forKey key: String) -> String? { defaults.string(forKey: key) }

    func setSyncValue(_ value: String?, forKey key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

/// Was die Einstellungen über den Abgleich wissen müssen.
@MainActor
@Observable
final class GoogleDriveSync {
    /// Der Zustandsautomat liegt in der Engine; hier steht nur, was die
    /// Anmeldung selbst gerade tut.
    let engine: LibrarySyncEngine

    /// Die benutzte Client-ID und woher sie stammt.
    ///
    /// Beobachtbar, weil sie sich im Betrieb noch ändern kann — nicht mehr
    /// durch eine Eingabe, sondern durch das Aufräumen eines Werts aus einer
    /// früheren Fassung.
    private(set) var client: (clientId: String, origin: GoogleClientIDStore.Origin)?

    /// Braucht dieser Client beim Token-Endpunkt ein Secret?
    ///
    /// Auf macOS ja: der Client ist vom Typ „Desktop-App", und Google antwortet
    /// ohne Secret mit `client_secret is missing`. Auf iOS nie — der iOS-Client
    /// kennt keines, und die `Info.plist` von iOS hat den Schlüssel gar nicht.
    let requiresClientSecret: Bool

    /// Das Secret selbst. Privat, nicht beobachtbar, nie in einer Ausgabe.
    private var clientSecret: String?

    /// Liegen Tokens im Schlüsselbund? Für die Diagnose — **nie** welche.
    private(set) var hasStoredTokens = false

    private var authorization: GoogleAuthorization?
    private let store: LibraryStore
    private let tokenStore: GoogleTokenStore

    /// Wie das Anmeldefenster gebaut wird — als Fabrik, nicht als fertiges
    /// Objekt.
    ///
    /// Auf iOS hängt die Rückleitungsadresse an der Client-ID. Ein einmal
    /// gebautes Anmeldefenster wäre nach einem Wechsel der ID also auf die
    /// alte geeicht — oder auf gar keine.
    private let makePresenter: (GoogleOAuthConfiguration) -> GoogleSignInPresenter?

    private(set) var isAuthorizing = false
    private(set) var authorizationError: String?

    var isConfigured: Bool { client != nil && (!requiresClientSecret || clientSecret != nil) }

    /// Ob ein Secret vorliegt — für die Diagnose, nie der Wert.
    var hasClientSecret: Bool { clientSecret != nil }

    /// Muss der Nutzer sich neu anmelden?
    ///
    /// Eigene Frage und nicht „ist ein Fehler aufgetreten": es ist nichts
    /// kaputt, es fehlt eine Anmeldung.
    var needsReauthorization: Bool { engine.status == .needsReauthorization }

    /// Welche Build-Einstellungen dieser Build erwartet. Für die Diagnose.
    var expectedBuildSettings: String {
        requiresClientSecret ? "GOOGLE_CLIENT_ID und GOOGLE_CLIENT_SECRET" : "GOOGLE_CLIENT_ID"
    }

    /// Was im Diagnosebereich steht, wenn der Build nicht eingerichtet ist.
    ///
    /// Ausdrücklich ein Entwicklertext und kein Nutzerhinweis: wer Nori nur
    /// benutzt, kann hier nichts tun, und ein Eingabefeld anzubieten wäre eine
    /// Sackgasse mit Tastatur.
    var buildConfigurationProblem: String? {
        guard let client else {
            return GoogleClientIDStore.validationError(for: GoogleClientIDStore.fromBuild ?? "")
        }
        if requiresClientSecret && clientSecret == nil {
            return client.origin == .migrated
                ? "Zur übernommenen Client-ID gibt es kein Client-Secret."
                : "Es ist kein Client-Secret hinterlegt."
        }
        return nil
    }

    /// Gehört eine übernommene Client-ID zu einem anderen Cloud-Projekt als
    /// die aus dem Build?
    ///
    /// Dann gleicht dieses Gerät in einen anderen `appDataFolder` ab und sieht
    /// die übrigen Geräte nicht. Automatisch umgestellt wird trotzdem nicht —
    /// die Tokens gehören zur alten ID —, aber die Diagnose sagt es.
    var migratedClientBelongsToAnotherProject: Bool {
        guard let client, client.origin == .migrated,
              let build = GoogleClientIDStore.fromBuild else { return false }
        return GoogleClientIDStore.projectNumber(of: client.clientId)
            != GoogleClientIDStore.projectNumber(of: build)
    }

    var status: LibrarySyncStatus { engine.status }
    var lastSuccessfulSync: Double? { engine.lastSuccessfulSync }
    var lastWarning: String? { engine.lastWarning }
    var lastError: String? { engine.lastError }

    init(
        store: LibraryStore,
        requiresClientSecret: Bool = false,
        makePresenter: @escaping (GoogleOAuthConfiguration) -> GoogleSignInPresenter?,
        tokenStore: GoogleTokenStore = KeychainTokenStore(),
        bookkeeping: SyncBookkeeping = UserDefaultsBookkeeping()
    ) {
        self.store = store
        self.tokenStore = tokenStore
        self.makePresenter = makePresenter
        self.requiresClientSecret = requiresClientSecret
        self.engine = LibrarySyncEngine(store: store, bookkeeping: bookkeeping)
        resolveClient()

        // Der Store meldet Änderungen, der Zeitplan entscheidet, wann daraus
        // ein Upload wird. Ohne das müsste entweder jede Änderung sofort ins
        // Netz — bei laufender Wiedergabe im Sekundentakt — oder der Nutzer
        // müsste von Hand abgleichen.
        let engine = self.engine
        store.onChange = { [weak engine] in
            Task { @MainActor in engine?.noteChange() }
        }
    }

    /// Client-ID, Herkunft und Secret neu bestimmen.
    ///
    /// Ob Tokens vorliegen, entscheidet mit: nur eine bestehende Verbindung
    /// hält eine von Hand eingetragene Client-ID einer früheren Fassung am
    /// Leben. Ohne Tokens gilt ausschliesslich der Build.
    private func resolveClient() {
        hasStoredTokens = tokenStore.read()?.refreshToken != nil
        let resolved = GoogleOAuthConfiguration.resolved(
            hasTokens: hasStoredTokens, includeSecret: requiresClientSecret)
        client = resolved.map { ($0.configuration.clientId, $0.origin) }
        clientSecret = resolved?.configuration.clientSecret
        authorization = resolved.map {
            GoogleAuthorization(
                configuration: $0.configuration,
                tokenStore: tokenStore,
                presenter: makePresenter($0.configuration)
            )
        }
    }

    /// Den von Hand eingetragenen Wert einer früheren Fassung vergessen.
    ///
    /// Nur im Diagnosebereich erreichbar. Danach gilt die Client-ID aus dem
    /// Build; weil die Tokens zur alten gehören, wird dieses Gerät gleich
    /// mitgetrennt. Die Bibliothek bleibt vollständig.
    func forgetMigratedClientId() async {
        await disconnectDevice()
        GoogleClientIDStore.forgetLegacy()
        authorizationError = nil
        resolveClient()
    }

    /// Eine bestehende Verbindung nach dem Start wieder aufnehmen.
    ///
    /// Getrennt vom Anmelden: hier wird kein Fenster geöffnet und nichts
    /// gefragt. Liegen Tokens im Schlüsselbund, geht es weiter; sonst bleibt
    /// es bei „nicht verbunden".
    ///
    /// Ist die Engine schon angebunden, passiert nichts. Aufgerufen wird das
    /// beim Start **und** beim Öffnen der Einstellungen; ohne diese Prüfung
    /// löste jeder Blick in die Einstellungen einen vollständigen Abgleich aus.
    func restore() async {
        guard !engine.isConnected, let authorization, await authorization.isConnected else { return }
        hasStoredTokens = true
        await attach(authorization)
    }

    /// Mit Google Drive verbinden.
    func connect() async {
        guard let authorization, isConfigured else {
            // Kein Nutzerproblem: der Build ist nicht eingerichtet. Der Text
            // steht deshalb so knapp wie möglich und ausführlich in der
            // Diagnose.
            authorizationError = "Der Google-Abgleich ist in diesem Build nicht eingerichtet."
            return
        }
        isAuthorizing = true
        engine.setAuthorizing()
        authorizationError = nil
        defer { isAuthorizing = false }

        do {
            try await authorization.signIn()
            hasStoredTokens = true
            await attach(authorization)
        } catch GoogleOAuthError.cancelled {
            // Abgebrochen ist kein Fehler und bekommt keine Meldung.
            engine.setDisconnected()
        } catch {
            engine.setDisconnected()
            hasStoredTokens = tokenStore.read()?.refreshToken != nil
            authorizationError = Self.text(for: error)
        }
    }

    private func attach(_ authorization: GoogleAuthorization) async {
        let drive = GoogleDriveClient(authorization: authorization)
        let fingerprint = await authorization.accountFingerprint
        // `startSync` steht voreingestellt auf `true`: nach einer Anmeldung
        // läuft der erste Abgleich von selbst. Wer sich gerade verbunden hat,
        // soll seine Merkliste sehen und nicht erst einen Knopf suchen.
        engine.connect(to: GoogleDriveSnapshotStore(client: drive), accountId: fingerprint)
        // Und danach im Vordergrund nachsehen. Vorher lief der Zeitgeber nach
        // einer frischen Anmeldung erst beim nächsten Wechsel in den
        // Vordergrund an — bis dahin kamen Änderungen der anderen Geräte nicht.
        engine.startPolling()
    }

    func syncNow() { engine.syncNow() }

    /// Die App kommt nach vorn: abgleichen, wenn es sich lohnt, und wieder
    /// regelmäßig nachsehen.
    func appDidBecomeActive() {
        engine.syncOnForeground()
        engine.startPolling()
    }

    /// Die App geht weg: nicht mehr nachsehen, Offenes noch schreiben.
    func appDidEnterBackground() {
        engine.stopPolling()
        engine.syncOnBackground()
    }

    /// Dieses Gerät trennen: Tokens weg, Abgleich aus.
    ///
    /// Die Bibliothek bleibt vollständig, die Dateien in Drive bleiben liegen,
    /// und die anderen Geräte gleichen weiter ab.
    func disconnectDevice() async {
        await authorization?.disconnectDevice()
        hasStoredTokens = false
        engine.disconnect()
    }

    /// Den Zugriff bei Google vollständig zurückziehen.
    ///
    /// Betrifft **alle** Geräte an diesem Konto. Gehört deshalb hinter eine
    /// eigene, deutlich benannte Aktion mit Rückfrage — nicht hinter
    /// „Abmelden".
    func revokeAccess() async {
        try? await authorization?.revokeAccess()
        hasStoredTokens = false
        engine.disconnect()
    }

    static func text(for error: Error) -> String {
        switch error {
        case GoogleOAuthError.notConfigured:
            return "Der Google-Abgleich ist in diesem Build nicht eingerichtet."
        case GoogleOAuthError.noRefreshToken:
            return "Google hat keine dauerhafte Berechtigung erteilt. Bitte erneut verbinden."
        case GoogleOAuthError.tokenStorageFailed:
            return "Die Anmeldung ließ sich nicht im Schlüsselbund ablegen. Diese Nori-Fassung ist vermutlich ohne Signatur gebaut."
        case GoogleOAuthError.stateMismatch:
            return "Die Antwort von Google gehörte nicht zu dieser Anmeldung."
        case GoogleOAuthError.denied(let reason):
            return "Google hat die Anmeldung abgelehnt (\(reason))."
        case GoogleOAuthError.server(let reason) where reason == "invalid_client" || reason == "invalid_request":
            // Ein Fehler im Build, nicht beim Nutzer — etwa ein fehlendes oder
            // falsches Client-Secret auf dem Mac.
            return "Der Google-Zugang dieser Nori-Fassung stimmt nicht (\(reason)). Siehe Diagnose."
        case GoogleOAuthError.server(let reason):
            return "Google hat die Anmeldung abgelehnt (\(reason))."
        case GoogleOAuthError.transport(let message):
            return message
        default:
            return "Die Verbindung ist fehlgeschlagen."
        }
    }
}

extension LibrarySyncEngine {
    /// Für die Anmeldung, die außerhalb der Engine läuft.
    func setAuthorizing() { setStatus(.authorizing) }
    func setDisconnected() { if !isConnected { setStatus(.disconnected) } }
}
