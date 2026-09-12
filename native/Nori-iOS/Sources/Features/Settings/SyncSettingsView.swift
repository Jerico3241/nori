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
    @State private var clientDraft = ""
    @State private var clientNote: String?

    var body: some View {
        NoriGradientScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    SettingsSyncCard(state: cardState)

                    if sync.isConfigured {
                        connection
                        if isConnected { advanced }
                        clientIdSection
                    } else {
                        setup
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

    /// Die Einrichtung — das, was ohne hinterlegte Client-ID zu tun ist.
    ///
    /// Hier stand vorher nur ein Satz, dass nichts hinterlegt sei. Das war
    /// zutreffend und trotzdem eine Sackgasse: wer die App fertig installiert
    /// bekommt, hat keine Build-Einstellung, und damit gab es auf dem iPhone
    /// schlicht keinen Weg, sich jemals anzumelden.
    private var setup: some View {
        SettingsGroup(
            title: "Einrichten",
            footnote: """
            Die Client-ID stammt aus einem eigenen Google-Cloud-Projekt mit \
            aktivierter Drive-API und einem OAuth-Client vom Typ „iOS\". Die \
            Schritte stehen in docs/google-drive-sync.md. Sie ist kein \
            Geheimnis — sie steht in jeder Anmeldeadresse — und wird im \
            Schlüsselbund dieses Geräts gesichert.
            """
        ) {
            SettingsRowContent(
                symbol: "key",
                title: "Google-Client-ID",
                subtitle: "Endet auf .apps.googleusercontent.com"
            ) {
                EmptyView()
            }
            // Kein `SecureField` wie beim TMDB-Schlüssel: eine Client-ID ist
            // öffentlich, und sie zu sehen ist der einzige Weg zu bemerken,
            // dass beim Einfügen etwas verrutscht ist.
            TextField("123456-abc.apps.googleusercontent.com", text: $clientDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.footnote)
                .padding(.horizontal, 15)
                .padding(.bottom, 12)
            SettingsDivider()
            SettingsButtonRow(
                symbol: "checkmark.circle",
                tint: .green,
                title: "Sichern",
                subtitle: "Danach lässt sich Google Drive verbinden",
                action: saveClientId
            ) { EmptyView() }
            .disabled(clientDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let clientNote {
                SettingsDivider()
                Text(clientNote)
                    .font(.caption2)
                    .foregroundStyle(NoriTheme.muted)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Die hinterlegte Client-ID, wenn es eine gibt.
    private var clientIdSection: some View {
        SettingsGroup(title: "Google-Client-ID") {
            SettingsInfoRow(
                symbol: "key.fill",
                tint: .green,
                title: "Client-ID",
                subtitle: sync.clientId ?? "—",
                value: sync.clientIdIsUserProvided ? "eingetragen" : "aus dem Build"
            )
            if sync.clientIdIsUserProvided {
                SettingsDivider()
                SettingsButtonRow(
                    symbol: "trash",
                    tint: .red,
                    title: "Client-ID entfernen",
                    subtitle: "Trennt dieses Gerät; die Bibliothek bleibt",
                    role: .destructive,
                    action: { Task { await sync.clearClientId() } }
                ) { EmptyView() }
            }
        }
    }

    private func saveClientId() {
        if let problem = sync.saveClientId(clientDraft) {
            clientNote = problem
        } else {
            clientDraft = ""
            clientNote = nil
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
