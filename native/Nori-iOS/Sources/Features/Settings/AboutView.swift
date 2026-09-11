import SwiftUI

/// Was läuft — Version, Build, Plattform, Schema.
///
/// Alles aus dem Bundle bzw. dem Kern gelesen. Kein Schlüssel, kein Token, kein
/// Gerätename: die Seite soll beim Einordnen eines Fehlerberichts helfen, nicht
/// beim Ausforschen des Geräts.
struct AboutView: View {
    var body: some View {
        NoriGradientScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsGroup(
                        title: "App",
                        footnote: "Die Version stammt aus MARKETING_VERSION des Xcode-Projekts — sie ist die einzige Quelle dieser Angabe."
                    ) {
                        SettingsInfoRow(symbol: "app.badge", title: "Version", value: NoriBuild.version)
                        SettingsDivider()
                        SettingsInfoRow(symbol: "hammer", title: "Build", value: NoriBuild.build)
                        SettingsDivider()
                        SettingsInfoRow(symbol: "iphone", title: "Plattform", value: NoriBuild.platform)
                        SettingsDivider()
                        SettingsInfoRow(
                            symbol: "shippingbox",
                            title: "Bundle",
                            subtitle: "Hilft, wenn mehrere Nori-Installationen auf dem Gerät sind",
                            value: NoriBuild.bundleID
                        )
                    }

                    SettingsGroup(
                        title: "Daten",
                        footnote: "Merkliste, Verlauf und Wiedergabefortschritt liegen in library.json im Anwendungsunterstützungsordner dieser App — und nur dort, solange kein Abgleich eingerichtet ist."
                    ) {
                        SettingsInfoRow(
                            symbol: "externaldrive",
                            tint: .green,
                            title: "Bibliotheksschema",
                            subtitle: "Version des gespeicherten Aufbaus",
                            value: "v\(LibraryStore.schemaVersion)"
                        )
                    }

                    SettingsGroup(title: "Dienste") {
                        SettingsInfoRow(
                            symbol: "sparkles.tv",
                            title: CatalogProvider.aniworld.label,
                            subtitle: "Katalog, Kalender und Streams",
                            value: "Quelle"
                        )
                        SettingsDivider()
                        SettingsInfoRow(
                            symbol: "tv",
                            title: CatalogProvider.serienstream.label,
                            subtitle: "Katalog, Kalender und Streams",
                            value: "Quelle"
                        )
                        SettingsDivider()
                        SettingsInfoRow(
                            symbol: "square.stack.3d.up",
                            title: "TMDB",
                            subtitle: "Metadaten und Artwork",
                            value: "Metadaten"
                        )
                    }

                    Text("""
                         Dieses Produkt verwendet die TMDB-API, ist aber von TMDB \
                         weder unterstützt noch zertifiziert. Streams stammen \
                         ausschließlich von den oben genannten Quellen; Nori \
                         betreibt selbst keine.
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
        .navigationTitle("Über Nori")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Der TMDB-Schlüssel und der Zustand der Metadatenquelle.
///
/// Der Schlüssel liegt im Schlüsselbund und wird **nie** angezeigt — auch nicht
/// gekürzt. Die Seite sagt nur, ob einer hinterlegt ist und ob TMDB ihn
/// annimmt.
struct MetadataSettingsView: View {
    @State private var draft = ""
    @State private var stored = TMDBKeyStore.isUserProvided
    @State private var note: String?
    @State private var check: NoriDiagnostics.Check?
    @State private var checking = false

    var body: some View {
        NoriGradientScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsGroup(title: "Zustand") {
                        if let check {
                            SettingsInfoRow(
                                symbol: check.status.symbol,
                                tint: check.status == .ok ? .green : (check.status == .warning ? .orange : .red),
                                title: "Metadatenquelle",
                                subtitle: check.detail,
                                value: check.status.label
                            )
                        } else {
                            SettingsInfoRow(
                                symbol: "arrow.triangle.2.circlepath",
                                title: "Metadatenquelle",
                                subtitle: "Wird geprüft …",
                                value: "…"
                            )
                        }
                        SettingsDivider()
                        SettingsButtonRow(
                            symbol: "arrow.clockwise",
                            title: "Erneut prüfen",
                            subtitle: "Fragt TMDB jetzt",
                            action: { Task { await runCheck() } }
                        ) {
                            if checking { ProgressView().controlSize(.small) } else { EmptyView() }
                        }
                        .disabled(checking)
                    }

                    SettingsGroup(
                        title: "Eigener Schlüssel",
                        footnote: """
                        Ein eigener Schlüssel (kostenlos bei themoviedb.org) liefert \
                        Breitbilder, Folgentitel, Folgenbilder und Bewertungen. Er \
                        liegt im Schlüsselbund, nicht im Programm, und wird hier \
                        nie angezeigt. Ohne ihn zeigt Nori die Cover der Quellen.
                        """
                    ) {
                        if stored {
                            SettingsInfoRow(
                                symbol: "key.fill",
                                tint: .green,
                                title: "Schlüssel",
                                subtitle: "Im Schlüsselbund dieses Geräts",
                                value: "hinterlegt"
                            )
                            SettingsDivider()
                            SettingsButtonRow(
                                symbol: "trash",
                                tint: .red,
                                title: "Schlüssel entfernen",
                                subtitle: "Nori nutzt danach die Cover der Quellen",
                                role: .destructive,
                                action: remove
                            ) { EmptyView() }
                        } else {
                            SettingsRowContent(
                                symbol: "key",
                                title: "TMDB-Schlüssel",
                                subtitle: "Wird im Schlüsselbund gesichert"
                            ) {
                                EmptyView()
                            }
                            SecureField("Schlüssel eingeben", text: $draft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.footnote)
                                .padding(.horizontal, 15)
                                .padding(.bottom, 12)
                            SettingsDivider()
                            SettingsButtonRow(
                                symbol: "checkmark.circle",
                                tint: .green,
                                title: "Sichern",
                                subtitle: "Neue Cover werden danach bei TMDB gesucht",
                                action: save
                            ) { EmptyView() }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if let note {
                            SettingsDivider()
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(NoriTheme.muted)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, NoriPanel.bottom)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("TMDB")
        .navigationBarTitleDisplayMode(.inline)
        .task { await runCheck() }
    }

    private func runCheck() async {
        checking = true
        check = await NoriDiagnostics.checkTMDB()
        checking = false
    }

    private func save() {
        if TMDBKeyStore.save(draft) {
            stored = TMDBKeyStore.isUserProvided
            draft = ""
            note = "Gesichert."
            Task { await runCheck() }
        } else {
            note = "Der Schlüsselbund hat die Ablage abgelehnt."
        }
    }

    private func remove() {
        TMDBKeyStore.clear()
        stored = false
        draft = ""
        note = "Entfernt."
        Task { await runCheck() }
    }
}
