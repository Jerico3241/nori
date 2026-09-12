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

    /// `nil`, solange keine Client-ID hinterlegt ist. Dann bietet die
    /// Oberfläche keine Anmeldung an, statt eine anzubieten, die sicher
    /// scheitert.
    private let configuration: GoogleOAuthConfiguration?
    private let authorization: GoogleAuthorization?
    private let store: LibraryStore
    private let tokenStore: GoogleTokenStore

    private(set) var isAuthorizing = false
    private(set) var authorizationError: String?

    var isConfigured: Bool { configuration != nil }
    var status: LibrarySyncStatus { engine.status }
    var lastSuccessfulSync: Double? { engine.lastSuccessfulSync }
    var lastWarning: String? { engine.lastWarning }

    init(
        store: LibraryStore,
        presenter: GoogleSignInPresenter?,
        configuration: GoogleOAuthConfiguration? = .fromBundle(),
        tokenStore: GoogleTokenStore = KeychainTokenStore(),
        bookkeeping: SyncBookkeeping = UserDefaultsBookkeeping()
    ) {
        self.store = store
        self.tokenStore = tokenStore
        self.configuration = configuration
        self.engine = LibrarySyncEngine(store: store, bookkeeping: bookkeeping)
        self.authorization = configuration.map {
            GoogleAuthorization(configuration: $0, tokenStore: tokenStore, presenter: presenter)
        }

        // Der Store meldet Änderungen, der Zeitplan entscheidet, wann daraus
        // ein Upload wird. Ohne das müsste entweder jede Änderung sofort ins
        // Netz — bei laufender Wiedergabe im Sekundentakt — oder der Nutzer
        // müsste von Hand abgleichen.
        let engine = self.engine
        store.onChange = { [weak engine] in
            Task { @MainActor in engine?.noteChange() }
        }
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
            authorizationError = "Für diese Nori-Fassung ist keine Google-Client-ID hinterlegt."
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
        let client = GoogleDriveClient(authorization: authorization)
        let fingerprint = await authorization.accountFingerprint
        engine.connect(to: GoogleDriveSnapshotStore(client: client), accountId: fingerprint)
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
            return "Für diese Nori-Fassung ist keine Google-Client-ID hinterlegt."
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
