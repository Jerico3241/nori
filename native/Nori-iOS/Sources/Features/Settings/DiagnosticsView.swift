import SwiftUI

/// Die Diagnoseseite.
///
/// Sie prüft wirklich: jede Zeile hier ist das Ergebnis eines Abrufs oder einer
/// Messung, die beim Öffnen der Seite stattfindet. Nichts ist vorberechnet, und
/// nichts davon ist dauerhaft grün.
///
/// Was sie **nicht** anzeigt: Schlüssel, Token, Kekse, Sitzungskennungen oder
/// vollständige Hoster-Adressen. Auch nicht gekürzt und auch nicht in einer
/// Fehlermeldung — eine Diagnoseseite wird abfotografiert und weitergegeben,
/// und was hier steht, ist damit veröffentlicht.
struct DiagnosticsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var checks: [NoriDiagnostics.Check] = []
    @State private var running = false
    @State private var finishedAt: Date?

    var body: some View {
        NoriGradientScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if checks.isEmpty, running {
                        ProgressView("Prüfungen laufen")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        SettingsGroup(title: "Befund", footnote: footnote) {
                            ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                                row(check)
                                if index < checks.count - 1 { SettingsDivider() }
                            }
                        }
                    }

                    SettingsGroup(title: "Prüfung") {
                        SettingsButtonRow(
                            symbol: "arrow.clockwise",
                            title: "Erneut prüfen",
                            subtitle: "Fragt Quellen und Metadaten jetzt",
                            action: { Task { await run() } }
                        ) {
                            if running { ProgressView().controlSize(.small) } else { EmptyView() }
                        }
                        .disabled(running)
                    }

                    Text("""
                         Diese Seite zeigt keine Schlüssel, Token oder \
                         Sitzungsdaten — nur Erreichbarkeit, gelesene Anzahlen \
                         und Fehlermeldungen der Dienste.
                         """)
                        .font(.caption2)
                        .foregroundStyle(NoriTheme.muted)
                        .padding(.horizontal, NoriSpacing.screen + 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
                .padding(.bottom, NoriPanel.bottom)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Diagnose")
        .navigationBarTitleDisplayMode(.inline)
        .task { if checks.isEmpty { await run() } }
    }

    private func row(_ check: NoriDiagnostics.Check) -> some View {
        HStack(spacing: 10) {
            Image(systemName: check.status.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(check.status.color)
                .frame(width: NoriPanel.iconSize, height: NoriPanel.iconSize)
                .background(
                    check.status.color.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(check.title)
                    .font(.footnote.weight(.semibold))
                Text(check.detail)
                    .font(.caption2)
                    .foregroundStyle(NoriTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)

            Text(check.status.label)
                .font(.system(size: 9, weight: .heavy))
                .textCase(.uppercase)
                .foregroundStyle(check.status.color)
                .fixedSize()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .frame(minHeight: NoriPanel.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(check.title): \(check.status.label). \(check.detail)")
    }

    private var footnote: String {
        guard let finishedAt else { return "Die Quellen werden über ihren Kalender geprüft — damit ist auch der Aufbau der Seite getestet, nicht nur die Erreichbarkeit." }
        return "Geprüft " + finishedAt.formatted(.relative(presentation: .named))
            + ". Die Quellen werden über ihren Kalender geprüft — damit ist auch der Aufbau der Seite getestet, nicht nur die Erreichbarkeit."
    }

    private func run() async {
        running = true
        checks = await NoriDiagnostics.runAll(
            progressCount: library.progress.count,
            favorites: library.favorites.count,
            syncName: library.syncProvider?.name
        )
        finishedAt = Date()
        running = false
    }
}
