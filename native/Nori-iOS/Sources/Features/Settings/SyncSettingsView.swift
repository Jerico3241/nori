import SwiftUI

/// Der Abgleich in den Einstellungen.
///
/// Was hier steht, ist bewusst wenig: Zustand, verbinden, jetzt abgleichen,
/// trennen. Keine Tokens, keine Dateikennungen, keine Bereiche — wer Nori
/// benutzt, muss über OAuth nichts wissen.
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
    @Environment(LibraryStore.self) private var library
    @Environment(GoogleDriveSync.self) private var sync

    @State private var showRevokeConfirmation = false

    var body: some View {
        NoriGradientScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    SettingsSyncCard(state: cardState)

                    if sync.isConfigured {
                        connection
                        if isConnected { advanced }
                    } else {
                        notConfiguredNote
                    }

                    explanation
                }
                .padding(.top, 6)
                .padding(.bottom, NoriPanel.bottom)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Synchronisation")
        .navigationBarTitleDisplayMode(.inline)
        .task { await sync.restore() }
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
            Damit verlieren **alle** Geräte an diesem Google-Konto den Zugriff — \
            auch Mac und Fernseher. Die Bibliothek auf diesem Gerät bleibt \
            vollständig erhalten.
            """)
        }
    }

    // MARK: - Verbindung

    private var connection: some View {
        SettingsGroup(title: "Google Drive") {
            if isConnected {
                SettingsButtonRow(
                    symbol: "arrow.triangle.2.circlepath",
                    tint: .green,
                    title: "Jetzt synchronisieren",
                    subtitle: "Holen, zusammenführen, zurückschreiben",
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
                SettingsButtonRow(
                    symbol: "link",
                    tint: .blue,
                    title: "Mit Google Drive verbinden",
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

            if let message = sync.authorizationError {
                SettingsDivider()
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(NoriTheme.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
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

    private var notConfiguredNote: some View {
        SettingsGroup(title: "Google Drive") {
            Text("""
            Für diese Nori-Fassung ist keine Google-Client-ID hinterlegt. Der \
            Abgleich lässt sich damit nicht einrichten — die Bibliothek \
            funktioniert weiterhin vollständig, nur eben auf diesem Gerät.
            """)
            .font(.footnote)
            .foregroundStyle(NoriTheme.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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

    // MARK: - Abgeleitetes

    private var isConnected: Bool {
        switch sync.status {
        case .disconnected: return false
        default: return true
        }
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
        case .unsupportedRemoteVersion: return .needsUpdate(name: name)
        }
    }
}
