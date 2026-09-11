import SwiftUI

/// Der Filterbogen des Kalenders.
///
/// Ein natives Sheet mit mittlerer Rasthöhe — Apple zeichnet Griff, Rundung und
/// Material selbst, nachgebaut wird nur die Pillenreihe, für die es kein
/// Systembedienelement gibt.
///
/// ## Warum der Bereich hier mitsteht
///
/// „Inhalt" ist in Nori `LibraryScope`: derselbe Bereich, den Katalog und
/// Merkliste verwenden. Er wird hier eingestellt statt daneben noch einmal
/// erfunden — zwei Anime/Serien-Schalter, die verschiedene Dinge meinen, sind
/// schlimmer als einer an der ungewohnten Stelle. Die Änderung wirkt deshalb
/// auch über den Kalender hinaus, was die Fußnote unter der Gruppe sagt.
///
/// Alles wird **sofort** übernommen. Der Knopf unten schließt den Bogen, er
/// bestätigt nichts — eine Auswahl, die erst nach dem Antippen von „Anwenden"
/// gilt, verträgt sich nicht damit, dass die Liste darunter sichtbar ist.
struct CalendarFilterSheet: View {
    @Binding var scope: LibraryScope
    @Binding var filter: CalendarFilter
    /// Wie viele Veröffentlichungen der aktuelle Stand übrig lässt — damit
    /// sichtbar ist, was eine Einschränkung kostet.
    let matching: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    group("Inhalt", note: "Gilt auch für Katalog und Merkliste.") {
                        options(LibraryScope.allCases, selected: scope, label: \.label) { scope = $0 }
                    }
                    group("Sprache", note: "Nach der Verfügbarkeit bei der Quelle.") {
                        options(
                            CalendarFilter.Language.allCases,
                            selected: filter.language,
                            label: \.label
                        ) { filter.language = $0 }
                    }
                    group("Quelle", note: filter.source.note) {
                        options(
                            CalendarFilter.Source.allCases,
                            selected: filter.source,
                            label: \.label
                        ) { filter.source = $0 }
                    }

                    Text(matching == 1 ? "1 Veröffentlichung im Zeitraum." : "\(matching) Veröffentlichungen im Zeitraum.")
                        .font(.footnote)
                        .foregroundStyle(NoriTheme.muted)
                }
                .padding(.horizontal, CalendarMetrics.screen)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(NoriBackdrop())
            .foregroundStyle(NoriTheme.fg)
            .navigationTitle("Kalender filtern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zurücksetzen") {
                        scope = .all
                        filter = CalendarFilter()
                    }
                    .disabled(filter.isDefault && scope == .all)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Bausteine

    private func group<Content: View>(
        _ title: String,
        note: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption2.weight(.heavy))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(NoriTheme.muted)
            content()
            Text(note)
                .font(.caption2)
                .foregroundStyle(NoriTheme.muted.opacity(0.8))
        }
    }

    /// Eine Reihe Pillen, die umbricht, wenn sie nicht in eine Zeile passt.
    ///
    /// `ViewThatFits` oder ein eigenes Flow-Layout wären der saubere Weg, aber
    /// beide brauchen mehr Code als das Problem wert ist: die längste Gruppe hat
    /// vier Einträge, und ein `LazyVGrid` mit anpassender Spaltenbreite bricht
    /// genauso um — ohne eigenes Layout.
    private func options<Item: Identifiable & Equatable>(
        _ items: [Item],
        selected: Item,
        label: KeyPath<Item, String>,
        onPick: @escaping (Item) -> Void
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104, maximum: 220), spacing: 7, alignment: .leading)],
            alignment: .leading,
            spacing: 7
        ) {
            ForEach(items) { item in
                let active = item == selected
                Button {
                    onPick(item)
                } label: {
                    Text(item[keyPath: label])
                        .font(.footnote.weight(active ? .semibold : .regular))
                        .foregroundStyle(active ? NoriTheme.bg : NoriTheme.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: NoriControl.hit)
                        .background {
                            if active {
                                Capsule().fill(NoriTheme.accent)
                            } else {
                                Capsule().fill(NoriTheme.elevated.opacity(0.72))
                                Capsule().strokeBorder(NoriTheme.border)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(NoriPressStyle(scale: 0.97))
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            }
        }
        .noriHaptic(.selection, trigger: selected)
    }
}
