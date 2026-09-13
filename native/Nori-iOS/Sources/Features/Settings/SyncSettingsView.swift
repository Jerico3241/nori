import SwiftUI

/// Der Abgleich in den Einstellungen.
///
/// Was hier steht, ist bewusst wenig: Zustand, anmelden, jetzt abgleichen,
/// trennen. Keine Client-ID, keine Tokens, keine Dateikennungen, keine
/// Bereiche — wer Nori benutzt, muss über OAuth nichts wissen und nichts
/// eintragen.
///
/// Das Eingabefeld für die Google-Client-ID, das hier früher stand, ist weg.
/// Es war ein Feld für einen Wert, den niemand hat, der die App nur benutzt:
/// eine Anmeldung, die erst nach einem Besuch in der Google Cloud Console
/// möglich war. Die Client-ID kommt jetzt aus dem Build; fehlt sie, ist das
/// ein Build-Fehler und steht in der Diagnose.
///
/// Zwei Dinge sind ausdrücklich **nicht** dasselbe und stehen deshalb
/// auseinander:
///
/// - **Dieses Gerät trennen** hört auf abzugleichen. Die Bibliothek bleibt
///   vollständig, die Daten in Drive bleiben liegen, die anderen Geräte
///   gleichen weiter ab.
/// - **Google-Zugriff widerrufen** zieht die Berechtigung für *alle* Geräte an
///   diesem Konto zurück.
///
/// Das Zweite hinter einem unscheinbaren „Abmelden" zu verstecken, wäre die
/// Art Fehler, die jemand erst bemerkt, wenn der Fernseher nicht mehr
/// mitkommt.
struct SyncSettingsView: View {
    @Environment(GoogleDriveSync.self) private var sync

    @State private var showRevokeConfirmation = false
    /// Der Diagnosebereich ist standardmässig zu. Er richtet sich an den, der
    /// Nori baut — nicht an den, der sie benutzt.
    @State private var showDiagnostics = false
    /// Die Erklärung vor „Mit Fernseher teilen". Steht vor jedem Einschalten,
    /// nicht nur vor dem ersten: danach fragt Google ohnehin nach, und wer den
    /// Schalter umlegt, soll wissen, wofür.
    @State private var showTVExplanation = false

    var body: some View {
        NoriGradientScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    SettingsSyncCard(state: cardState)

                    if sync.isConfigured {
                        connection
                        if isConnected {
                            television
                            advanced
                        }
                    } else {
                        notConfigured
                    }

                    explanation
                    diagnostics
                }
                .padding(.top, 6)
                .padding(.bottom, NoriPanel.bottom)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Synchronisation")
        .navigationBarTitleDisplayMode(.inline)
        .task { await sync.restore() }
        .alert("Mit Fernseher teilen", isPresented: $showTVExplanation) {
            Button("Weiter zu Google") { Task { await sync.enableTVMirror() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(GoogleDriveSync.tvMirrorExplanation)
        }
        .confirmationDialog(
            "Google-Zugriff widerrufen?",
            isPresented: $showRevokeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Zugriff widerrufen", role: .destructive) {
                Task { await sync.revokeAccess() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("""
            Dadurch kann Nori auf deinen Geräten nicht mehr auf die \
            Google-Drive-Synchronisierung zugreifen — auch nicht auf Mac und \
            Fernseher. Deine lokale Bibliothek bleibt erhalten.
            """)
        }
    }

    // MARK: - Verbindung

    /// Die eine Gruppe, die ein normaler Nutzer je braucht.
    ///
    /// Drei Zustände, und jeder hat genau eine naheliegende Handlung:
    /// verbinden, abgleichen, neu anmelden. Mehr steht hier nicht.
    private var connection: some View {
        SettingsGroup(title: "Google Drive") {
            if sync.needsReauthorization {
                reauthorize
            } else if isConnected {
                SettingsButtonRow(
                    symbol: "arrow.triangle.2.circlepath",
                    tint: .green,
                    title: "Jetzt synchronisieren",
                    subtitle: lastRunText,
                    action: { sync.syncNow() }
                ) {
                    if sync.status == .syncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NoriTheme.muted)
                    }
                }
                .disabled(sync.status == .syncing)
                SettingsDivider()
                SettingsButtonRow(
                    symbol: "minus.circle",
                    tint: .orange,
                    title: "Dieses Gerät trennen",
                    subtitle: "Bibliothek bleibt, andere Geräte bleiben verbunden",
                    action: { Task { await sync.disconnectDevice() } }
                ) { EmptyView() }
            } else {
                signIn
            }

            if let message = sync.authorizationError {
                SettingsDivider()
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(NoriTheme.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var signIn: some View {
        SettingsButtonRow(
            symbol: "person.crop.circle.badge.checkmark",
            tint: .blue,
            title: "Mit Google anmelden",
            subtitle: "Merkliste, Verlauf und Fortschritt auf allen Geräten",
            action: { Task { await sync.connect() } }
        ) {
            if sync.isAuthorizing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NoriTheme.muted)
            }
        }
        .disabled(sync.isAuthorizing)
    }

    /// Was zu tun ist, wenn Google die Berechtigung nicht mehr anerkennt.
    ///
    /// Kein technischer Text. Dass dahinter ein abgelaufener
    /// Auffrischungstoken steckt, ist für die Handlung ohne Belang: es fehlt
    /// eine Anmeldung, und die gibt es hier.
    private var reauthorize: some View {
        SettingsButtonRow(
            symbol: "person.badge.key",
            tint: .orange,
            title: "Erneut anmelden",
            subtitle: "Google Drive muss erneut verbunden werden",
            action: { Task { await sync.connect() } }
        ) {
            if sync.isAuthorizing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NoriTheme.muted)
            }
        }
        .disabled(sync.isAuthorizing)
    }

    /// „Mit Fernseher teilen" — je Gerät, und aus, bis jemand es einschaltet.
    ///
    /// Ohne diesen Schalter fragt Nori nur nach dem versteckten App-Ordner,
    /// genau wie vorher. Eingeschaltet wird erst nach der Erklärung **und** der
    /// Zustimmung bei Google; bricht jemand ab, bleibt der Schalter aus.
    private var television: some View {
        SettingsGroup(title: "Fernseher", footnote: tvFootnote) {
            SettingsToggleRow(
                symbol: "tv",
                tint: .blue,
                title: "Mit Fernseher teilen",
                subtitle: "Merkliste, Verlauf und Fortschritt auch auf dem LG-Fernseher",
                isOn: tvBinding
            )
            .disabled(sync.isAuthorizing)

            if sync.tvMirrorState == .needsConsent {
                SettingsDivider()
                SettingsButtonRow(
                    symbol: "person.badge.key",
                    tint: .orange,
                    title: "Zugriff für den Fernseher erlauben",
                    subtitle: "Google hat ihn nicht erteilt oder zurückgezogen",
                    action: { showTVExplanation = true }
                ) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NoriTheme.muted)
                }
                .disabled(sync.isAuthorizing)
            }
        }
    }

    private var advanced: some View {
        SettingsGroup(
            title: "Erweitert",
            footnote: "Betrifft alle Geräte an diesem Google-Konto."
        ) {
            SettingsButtonRow(
                symbol: "xmark.shield",
                tint: .red,
                title: "Google-Zugriff widerrufen",
                subtitle: "Berechtigung für alle Nori-Geräte zurückziehen",
                role: .destructive,
                action: { showRevokeConfirmation = true }
            ) { EmptyView() }
        }
    }

    /// Was zu sehen ist, wenn dieser Build keine Google-Client-ID mitbringt.
    ///
    /// Ein Satz für den Nutzer, damit er nicht auf eine Anmeldung wartet, die
    /// es nicht gibt — und kein Eingabefeld, in dem er nichts Sinnvolles
    /// eintragen könnte. Der Grund steht in der Diagnose.
    private var notConfigured: some View {
        SettingsGroup(title: "Google Drive") {
            SettingsInfoRow(
                symbol: "icloud.slash",
                tint: .orange,
                title: "Nicht verfügbar",
                subtitle: "Diese Nori-Fassung wurde ohne Google-Abgleich gebaut",
                value: ""
            )
            SettingsDivider()
            Text("""
            Merkliste, Verlauf und Fortschritt funktionieren vollständig weiter \
            — sie bleiben auf diesem Gerät.
            """)
            .font(.footnote)
            .foregroundStyle(NoriTheme.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var explanation: some View {
        SettingsGroup(title: "Wie das funktioniert") {
            VStack(alignment: .leading, spacing: 10) {
                Text("""
                Nori legt seinen Stand in einem versteckten Ordner deines \
                Google-Drive-Kontos ab. Er taucht in „Meine Ablage" nicht auf, \
                andere Apps kommen nicht heran, und beim Löschen der App \
                verschwindet er mit.
                """)
                Text("""
                Jedes Gerät schreibt nur seine eigene Datei und liest die der \
                anderen. Deshalb geht nichts verloren, wenn zwei Geräte \
                gleichzeitig etwas ändern.
                """)
                Text("""
                Nori sieht dabei weder deinen Namen noch deine E-Mail-Adresse: \
                gefragt wird nach dem versteckten App-Ordner — und nur mit „Mit \
                Fernseher teilen“ zusätzlich nach den Dateien, die Nori selbst \
                im Ordner „Nori“ anlegt.
                """)
                Text("""
                Ohne Netz funktioniert Nori vollständig weiter. Änderungen \
                werden abgeglichen, sobald wieder eine Verbindung da ist.
                """)
            }
            .font(.footnote)
            .foregroundStyle(NoriTheme.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Diagnose

    /// Der Bereich für den, der Nori baut.
    ///
    /// Zugeklappt, unscheinbar und ohne eine einzige Eingabemöglichkeit. Er
    /// beantwortet genau eine Frage — „welche Client-ID benutzt diese
    /// Installation und woher kommt sie?" —, und die lässt sich sonst nur
    /// durch Raten beantworten.
    @ViewBuilder
    private var diagnostics: some View {
        SettingsGroup(title: "Diagnose") {
            SettingsButtonRow(
                symbol: showDiagnostics ? "chevron.down" : "chevron.right",
                tint: .blue,
                title: "OAuth-Konfiguration",
                subtitle: "Für die Fehlersuche beim Bauen",
                action: { showDiagnostics.toggle() }
            ) { EmptyView() }

            if showDiagnostics {
                SettingsDivider()
                SettingsInfoRow(
                    symbol: "key.fill",
                    tint: sync.isConfigured ? .green : .red,
                    title: "Client-ID",
                    subtitle: sync.client?.clientId ?? "—",
                    value: originLabel
                )
                SettingsDivider()
                SettingsInfoRow(
                    symbol: "lock.shield",
                    tint: .green,
                    title: "Bereich",
                    subtitle: scopeText,
                    value: hasFileScope ? "appdata + file" : "nur appdata"
                )
                SettingsDivider()
                SettingsInfoRow(
                    symbol: "tv",
                    tint: sync.tvMirrorState == .needsConsent ? .orange : .blue,
                    title: "TV-Spiegel",
                    subtitle: mirrorDiagnosticsText,
                    value: mirrorStateLabel
                )
                if let error = sync.mirrorEngine.lastError {
                    SettingsDivider()
                    SettingsInfoRow(
                        symbol: "exclamationmark.triangle",
                        tint: .orange,
                        title: "Letzter Fehler im TV-Spiegel",
                        subtitle: error,
                        value: ""
                    )
                }
                // Ob — nie welche. Tokens stehen hier nicht, auch nicht
                // verkürzt.
                SettingsDivider()
                SettingsInfoRow(
                    symbol: "key.horizontal",
                    tint: sync.hasStoredTokens ? .green : .orange,
                    title: "Anmeldung im Schlüsselbund",
                    subtitle: "Tokens werden nie angezeigt",
                    value: sync.hasStoredTokens ? "ja" : "nein"
                )
                SettingsDivider()
                SettingsInfoRow(
                    symbol: "clock.arrow.circlepath",
                    tint: .blue,
                    title: "Letzter Abgleich",
                    subtitle: lastRunText,
                    value: ""
                )
                if let error = sync.lastError {
                    SettingsDivider()
                    SettingsInfoRow(
                        symbol: "exclamationmark.triangle",
                        tint: .orange,
                        title: "Letzter Fehler",
                        subtitle: error,
                        value: ""
                    )
                }
                if sync.migratedClientBelongsToAnotherProject {
                    SettingsDivider()
                    Text("""
                    Die übernommene Client-ID gehört zu einem anderen \
                    Google-Cloud-Projekt als die aus dem Build. Dieses Gerät \
                    gleicht deshalb in einen anderen versteckten Ordner ab.
                    """)
                    .font(.caption2)
                    .foregroundStyle(NoriTheme.muted)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let problem = sync.buildConfigurationProblem {
                    SettingsDivider()
                    Text("""
                    \(problem) Erwartet wird die Build-Einstellung \
                    \(sync.expectedBuildSettings); die Schritte stehen in \
                    docs/google-drive-sync.md.
                    """)
                    .font(.caption2)
                    .foregroundStyle(NoriTheme.muted)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if sync.client?.origin == .migrated {
                    SettingsDivider()
                    SettingsButtonRow(
                        symbol: "arrow.uturn.backward",
                        tint: .orange,
                        title: "Eingetragene Client-ID verwerfen",
                        subtitle: "Danach gilt die aus dem Build; trennt dieses Gerät",
                        role: .destructive,
                        action: { Task { await sync.forgetMigratedClientId() } }
                    ) { EmptyView() }
                }
            }
        }
    }

    private var originLabel: String {
        switch sync.client?.origin {
        case .build: return "aus dem Build"
        case .migrated: return "übernommen"
        case nil: return "fehlt"
        }
    }

    // MARK: - Fernseher

    /// Der Schalter springt nicht selbst um: eingeschaltet wird erst nach
    /// Erklärung und Zustimmung. Ausschalten geht sofort und löscht nichts.
    private var tvBinding: Binding<Bool> {
        Binding(
            get: { sync.isTVMirrorEnabled },
            set: { on in
                if on { showTVExplanation = true } else { sync.disableTVMirror() }
            }
        )
    }

    private var deviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    /// Der Fernseher kann `appDataFolder` nicht lesen. Er bekommt Änderungen
    /// nur über ein Apple-Gerät, das mit ihm teilt — das steht hier ohne
    /// Fachbegriffe.
    private var tvFootnote: String {
        let relay = """
        Der Fernseher bekommt Änderungen über ein iPhone, iPad oder Mac mit \
        eingeschaltetem „Mit Fernseher teilen“. Mindestens eines davon muss \
        regelmäßig synchronisieren — also ab und zu geöffnet werden.
        """
        return sync.isTVMirrorEnabled
            ? "Dieses \(deviceName) teilt mit dem Fernseher. \(relay)"
            : "Gilt nur für dieses \(deviceName); andere Geräte schalten es selbst ein. \(relay)"
    }

    private var hasFileScope: Bool { sync.grantedScopes.contains(GoogleDriveClient.fileScope) }

    private var scopeText: String {
        hasFileScope ? "\(GoogleDriveClient.scope)\n\(GoogleDriveClient.fileScope)" : GoogleDriveClient.scope
    }

    private var mirrorStateLabel: String {
        switch sync.tvMirrorState {
        case .off: return "aus"
        case .needsConsent: return "Zustimmung fehlt"
        case .active: return "aktiv"
        }
    }

    private var mirrorDiagnosticsText: String {
        guard sync.tvMirrorState == .active else { return "Nur mit „Mit Fernseher teilen“" }
        let run = sync.mirrorEngine.lastSuccessfulSync.map {
            "Zuletzt " + Date(timeIntervalSince1970: $0 / 1000).formatted(.relative(presentation: .named))
        } ?? "Noch kein Abgleich"
        let others = sync.mirrorEngine.remoteDeviceCount.map { " · andere Geräte im Spiegel: \($0)" } ?? ""
        return run + others
    }

    // MARK: - Abgeleitetes

    private var isConnected: Bool {
        switch sync.status {
        // Während der Anmeldung ist noch nichts verbunden — sonst stünden
        // „Jetzt synchronisieren" und „Trennen" schon da, solange Safari offen
        // ist.
        case .disconnected, .authorizing: return false
        default: return true
        }
    }

    private var lastRunText: String {
        guard let stamp = sync.lastSuccessfulSync else { return "Noch kein Abgleich gelaufen" }
        let date = Date(timeIntervalSince1970: stamp / 1000)
        return "Zuletzt " + date.formatted(.relative(presentation: .named))
    }

    private var cardState: SettingsSyncCard.State {
        guard sync.isConfigured else { return .notConfigured }
        let name = "Google Drive"
        let lastRun = sync.lastSuccessfulSync.map { Date(timeIntervalSince1970: $0 / 1000) }
        switch sync.status {
        case .disconnected: return .disconnected(name: name)
        case .authorizing: return .authorizing(name: name)
        case .idle: return .idle(name: name, lastRun: lastRun)
        case .syncing: return .running(name: name)
        case .offline: return .offline(name: name, lastRun: lastRun)
        case .error(let message): return .failed(name: name, message: message)
        case .needsReauthorization: return .needsReauth(name: name)
        case .unsupportedRemoteVersion: return .needsUpdate(name: name)
        }
    }
}
