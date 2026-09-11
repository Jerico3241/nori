import SwiftUI

/// Der Bildzwischenspeicher: was er belegt und wie er geleert wird.
///
/// Die Zahlen werden gemessen, nicht geschrieben — siehe `NoriImageCache`. Sie
/// werden außerdem **nach** dem Aufbau geholt: `URLCache.currentDiskUsage` liest
/// ein Verzeichnis, und eine Seite, die darauf wartet, öffnet sich spürbar
/// langsam.
struct CacheSettingsView: View {
    @State private var images: Int64?
    @State private var metadata: Int64?
    @State private var clearing = false
    @State private var confirm = false

    var body: some View {
        NoriGradientScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsGroup(
                        title: "Belegt",
                        footnote: """
                        Bilder liegen im Zwischenspeicher der App, die Tabellen \
                        ordnen Serien ihren TMDB-Einträgen zu. Beides holt Nori \
                        bei Bedarf neu.
                        """
                    ) {
                        SettingsInfoRow(
                            symbol: "photo.stack",
                            tint: .orange,
                            title: "Bilder",
                            subtitle: "Poster, Breitbilder, Folgenbilder, Schriftzüge",
                            value: images.map(NoriImageCache.format) ?? "…"
                        )
                        SettingsDivider()
                        SettingsInfoRow(
                            symbol: "tablecells",
                            tint: .orange,
                            title: "Tabellen",
                            subtitle: "covers.json, episodes.json, tmdb-lists.json",
                            value: metadata.map(NoriImageCache.format) ?? "…"
                        )
                    }

                    SettingsGroup(
                        title: "Aufräumen",
                        footnote: """
                        Gelöscht wird nur, was sich wiederbeschaffen lässt. \
                        Merkliste, Verlauf und Wiedergabefortschritt stehen in \
                        library.json und werden nicht angefasst. Bereits \
                        geladene Bilder bleiben bis zum nächsten Start im \
                        Speicher — die Zahl oben fällt deshalb nicht zwingend \
                        auf null.
                        """
                    ) {
                        SettingsButtonRow(
                            symbol: "trash",
                            tint: .red,
                            title: "Bild-Cache leeren",
                            subtitle: "Bilder und Zuordnungstabellen entfernen",
                            role: .destructive,
                            action: { confirm = true }
                        ) {
                            if clearing {
                                ProgressView().controlSize(.small)
                            } else {
                                EmptyView()
                            }
                        }
                        .disabled(clearing)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, NoriPanel.bottom)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Bild-Cache")
        .navigationBarTitleDisplayMode(.inline)
        .task { await measure() }
        .confirmationDialog(
            "Bild-Cache leeren?",
            isPresented: $confirm,
            titleVisibility: .visible
        ) {
            Button("Leeren", role: .destructive) { Task { await clear() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Bilder und Zuordnungstabellen werden entfernt und bei Bedarf neu geladen. Merkliste, Verlauf und Fortschritt bleiben erhalten.")
        }
    }

    private func measure() async {
        images = await NoriImageCache.measure()
        metadata = NoriImageCache.metadataBytes()
    }

    private func clear() async {
        clearing = true
        await NoriImageCache.clear()
        await measure()
        clearing = false
    }
}
