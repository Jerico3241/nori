import Foundation
import Observation

// Der Zusammenbau: aus Client-ID, Schlüsselbund, Drive und Store wird ein
// Abgleich.
//
// Diese Datei liegt im gemeinsamen Kern und nicht zweimal in den Apps. Der
// Unterschied zwischen iOS und macOS ist genau einer — wie das Anmeldefenster
// aufgeht —, und der steckt im `GoogleSignInPresenter`. Alles andere wäre
// doppelter Code, der beim nächsten Mal nur an einer der beiden Stellen
// repariert wird.

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

    private var authorization: GoogleAuthorization?
    private let store: LibraryStore
    private let tokenStore: GoogleTokenStore

    /// Wie das Anmeldefenster gebaut wird — als Fabrik, nicht als fertiges
    /// Objekt.
    ///
    /// Auf iOS hängt die Rückleitungsadresse an der Client-ID. Ein einmal
    /// gebautes Anmeldefenster wäre nach dem Eintragen einer ID also auf die
    /// alte geeicht — oder auf gar keine.
    private let makePresenter: (GoogleOAuthConfiguration) -> GoogleSignInPresenter?

    private(set) var isAuthorizing = false
    private(set) var authorizationError: String?

    var isConfigured: Bool { client != nil }

    /// Muss der Nutzer sich neu anmelden?
    ///
    /// Eigene Frage und nicht „ist ein Fehler aufgetreten": es ist nichts
    /// kaputt, es fehlt eine Anmeldung.
    var needsReauthorization: Bool { engine.status == .needsReauthorization }

    /// Was im Diagnosebereich steht, wenn der Build nicht eingerichtet ist.
    ///
    /// Ausdrücklich ein Entwicklertext und kein Nutzerhinweis: wer Nori nur
    /// benutzt, kann hier nichts tun, und ein Eingabefeld anzubieten wäre eine
    /// Sackgasse mit Tastatur.
    var buildConfigurationProblem: String? {
        if client != nil { return nil }
        return GoogleClientIDStore.validationError(for: GoogleClientIDStore.fromBuild ?? "")
    }

    var status: LibrarySyncStatus { engine.status }
    var lastSuccessfulSync: Double? { engine.lastSuccessfulSync }
    var lastWarning: String? { engine.lastWarning }

    init(
        store: LibraryStore,
        makePresenter: @escaping (GoogleOAuthConfiguration) -> GoogleSignInPresenter?,
        tokenStore: GoogleTokenStore = KeychainTokenStore(),
        bookkeeping: SyncBookkeeping = UserDefaultsBookkeeping()
    ) {
        self.store = store
        self.tokenStore = tokenStore
        self.makePresenter = makePresenter
        self.engine = LibrarySyncEngine(store: store, bookkeeping: bookkeeping)
        self.client = GoogleClientIDStore.resolved()
        rebuildAuthorization()

        // Der Store meldet Änderungen, der Zeitplan entscheidet, wann daraus
        // ein Upload wird. Ohne das müsste entweder jede Änderung sofort ins
        // Netz — bei laufender Wiedergabe im Sekundentakt — oder der Nutzer
        // müsste von Hand abgleichen.
        let engine = self.engine
        store.onChange = { [weak engine] in
            Task { @MainActor in engine?.noteChange() }
        }
    }

    private func rebuildAuthorization() {
        guard let client else {
            authorization = nil
            return
        }
        let configuration = GoogleOAuthConfiguration(clientId: client.clientId, redirectURI: "")
        authorization = GoogleAuthorization(
            configuration: configuration,
            tokenStore: tokenStore,
            presenter: makePresenter(configuration)
        )
    }

    /// Den von Hand eingetragenen Wert einer früheren Fassung vergessen.
    ///
    /// Nur im Diagnosebereich erreichbar. Danach gilt die Client-ID aus dem
    /// Build; weil die Tokens zur alten gehören, wird dieses Gerät gleich
    /// mitgetrennt. Die Bibliothek bleibt vollständig.
    func forgetMigratedClientId() async {
        await disconnectDevice()
        GoogleClientIDStore.forgetLegacy()
        client = GoogleClientIDStore.resolved()
        authorizationError = nil
        rebuildAuthorization()
    }

    /// Eine bestehende Verbindung nach dem Start wieder aufnehmen.
    ///
    /// Getrennt vom Anmelden: hier wird kein Fenster geöffnet und nichts
    /// gefragt. Liegen Tokens im Schlüsselbund, geht es weiter; sonst bleibt
    /// es bei „nicht verbunden".
    func restore() async {
        guard let authorization, await authorization.isConnected else { return }
        await attach(authorization)
    }

    /// Mit Google Drive verbinden.
    func connect() async {
        guard let authorization else {
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
            await attach(authorization)
        } catch GoogleOAuthError.cancelled {
            // Abgebrochen ist kein Fehler und bekommt keine Meldung.
            engine.setDisconnected()
        } catch {
            engine.setDisconnected()
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
    }

    func syncNow() { engine.syncNow() }

    /// Dieses Gerät trennen: Tokens weg, Abgleich aus.
    ///
    /// Die Bibliothek bleibt vollständig, die Dateien in Drive bleiben liegen,
    /// und die anderen Geräte gleichen weiter ab.
    func disconnectDevice() async {
        await authorization?.disconnectDevice()
        engine.disconnect()
    }

    /// Den Zugriff bei Google vollständig zurückziehen.
    ///
    /// Betrifft **alle** Geräte an diesem Konto. Gehört deshalb hinter eine
    /// eigene, deutlich benannte Aktion mit Rückfrage — nicht hinter
    /// „Abmelden".
    func revokeAccess() async {
        try? await authorization?.revokeAccess()
        engine.disconnect()
    }

    static func text(for error: Error) -> String {
        switch error {
        case GoogleOAuthError.notConfigured:
            return "Der Google-Abgleich ist in diesem Build nicht eingerichtet."
        case GoogleOAuthError.noRefreshToken:
            return "Google hat keine dauerhafte Berechtigung erteilt. Bitte erneut verbinden."
        case GoogleOAuthError.stateMismatch:
            return "Die Antwort von Google gehörte nicht zu dieser Anmeldung."
        case GoogleOAuthError.denied(let reason):
            return "Google hat die Anmeldung abgelehnt (\(reason))."
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
