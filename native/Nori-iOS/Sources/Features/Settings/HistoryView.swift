import SwiftUI

/// Die zuletzt angesehenen Titel.
///
/// Der Verlauf stand bisher nur als Zahl in den Einstellungen und ließ sich
/// ausschließlich vollständig löschen. Hier ist er einsehbar, einzelne Einträge
/// lassen sich entfernen, und beide Löschwege fragen vorher.
///
/// Verlauf und Fortschritt sind absichtlich zwei Dinge: „aus dem Verlauf
/// nehmen" streicht den Titel aus dieser Liste, „Fortschritt löschen" vergisst,
/// wie weit die Folgen liefen. Wer nur aufräumen will, verliert dadurch nicht
/// seine Weiterschauen-Reihe.
struct HistoryView: View {
    @Environment(LibraryStore.self) private var library
    @State private var confirm: Confirmation?

    private enum Confirmation: String, Identifiable {
        case history
        case progress

        var id: String { rawValue }

        var title: String {
            switch self {
            case .history: return "Verlauf löschen?"
            case .progress: return "Fortschritt löschen?"
            }
        }

        var message: String {
            switch self {
            case .history:
                return "Die Liste der zuletzt angesehenen Titel wird geleert. Der Wiedergabefortschritt bleibt erhalten."
            case .progress:
                return "Nori vergisst, wie weit jede Folge gelaufen ist. Merkliste und Verlauf bleiben erhalten."
            }
        }
    }

    var body: some View {
        NoriGradientScreen {
            if library.recents.isEmpty {
                ContentUnavailableView(
                    "Kein Verlauf",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Sobald du eine Serie öffnest, steht sie hier.")
                )
            } else {
                list
            }
        }
        .navigationTitle("Verlauf")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !library.recents.isEmpty || !library.progress.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !library.recents.isEmpty {
                            Button("Verlauf löschen", systemImage: "trash", role: .destructive) {
                                confirm = .history
                            }
                        }
                        if !library.progress.isEmpty {
                            Button("Fortschritt löschen", systemImage: "gauge.with.dots.needle.0percent", role: .destructive) {
                                confirm = .progress
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Weitere Aktionen")
                }
            }
        }
        .confirmationDialog(
            confirm?.title ?? "",
            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
            titleVisibility: .visible,
            presenting: confirm
        ) { item in
            Button("Löschen", role: .destructive) {
                switch item {
                case .history: library.clearHistory()
                case .progress: library.clearProgress()
                }
                confirm = nil
            }
            Button("Abbrechen", role: .cancel) { confirm = nil }
        } message: { item in
            Text(item.message)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 0) {
                    ForEach(Array(library.recents.enumerated()), id: \.element.slug) { index, item in
                        row(item)
                        if index < library.recents.count - 1 { SettingsDivider() }
                    }
                }
                .noriPanel()

                Text("""
                     Alles davon liegt auf diesem Gerät. Zum Entfernen eines \
                     einzelnen Eintrags nach links wischen.
                     """)
                    .font(.caption2)
                    .foregroundStyle(NoriTheme.muted)
                    .padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, NoriSpacing.screen)
            .padding(.top, 10)
            .padding(.bottom, NoriPanel.bottom)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ item: RecentItem) -> some View {
        let provider = item.provider ?? library.provider
        return NoriSeriesLink(slug: item.slug, titleHint: item.title, provider: provider) {
            SettingsRowContent(
                symbol: provider == .aniworld ? "sparkles.tv" : "tv",
                tint: .green,
                title: item.title,
                subtitle: subtitle(item, provider: provider)
            ) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NoriTheme.muted)
            }
            .contentShape(Rectangle())
        }
        // Wischen statt eines Löschknopfes in jeder Zeile: die Zeile führt zur
        // Serie, und zwei Trefferflächen nebeneinander treffen sich gegenseitig.
        .swipeActions(edge: .trailing) {
            Button("Entfernen", systemImage: "trash", role: .destructive) {
                library.forgetRecent(slug: item.slug)
            }
        }
    }

    /// Quelle und Zeitpunkt — der Zeitpunkt relativ, weil „vor 2 Stunden"
    /// schneller zu lesen ist als ein Datum.
    private func subtitle(_ item: RecentItem, provider: CatalogProvider) -> String {
        let when = Date(timeIntervalSince1970: item.viewedAt / 1000)
        return provider.label + " · " + when.formatted(.relative(presentation: .named))
    }
}
