import SwiftUI

/// Der erweiterte Filter — Inhalt, Status, Genre, Sortierung.
///
/// Hier und nur hier steht die Wahl zwischen Anime und Serien. Sie ist
/// damit nicht verschwunden, sondern dorthin gerückt, wo sie hingehört:
/// hinter einen Knopf, den man drückt, wenn man sie braucht, statt dauerhaft
/// über eine Liste, in der man nach dem eigenen Stand sucht.
///
/// Das Sheet arbeitet auf einer **Kopie**. Erst „Ergebnisse anzeigen"
/// übernimmt sie. Ohne das würde die Liste dahinter bei jedem Antippen
/// umspringen, und „Abbrechen" hätte nichts mehr, wohin es zurückkehren
/// könnte.
struct WatchlistFilterSheet: View {
    /// Die geltenden Filter. Werden erst beim Anwenden beschrieben.
    @Binding var filters: WatchlistFilters
    /// Die Genres, die in der Merkliste tatsächlich vorkommen.
    let genres: [String]
    /// Wie viele Titel die Auswahl gerade übrig ließe — die Vorschau auf dem
    /// Knopf. Ohne sie tippt man auf „Ergebnisse anzeigen" und findet eine
    /// leere Liste vor.
    let preview: (WatchlistFilters) -> Int

    @Environment(\.dismiss) private var dismiss
    @State private var draft: WatchlistFilters

    init(
        filters: Binding<WatchlistFilters>,
        genres: [String],
        preview: @escaping (WatchlistFilters) -> Int
    ) {
        _filters = filters
        self.genres = genres
        self.preview = preview
        _draft = State(initialValue: filters.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    group("Inhalt") {
                        ForEach(WatchlistKind.allCases) { kind in
                            option(kind.label, selected: draft.kind == kind) { draft.kind = kind }
                        }
                    }

                    group("Status") {
                        option("Alle", selected: draft.state == nil) { draft.state = nil }
                        ForEach(WatchState.allCases, id: \.self) { state in
                            option(state.label, selected: draft.state == state) { draft.state = state }
                        }
                    }

                    if !genres.isEmpty {
                        group("Genre") {
                            option("Alle", selected: draft.genre == nil) { draft.genre = nil }
                            ForEach(genres, id: \.self) { genre in
                                option(genre, selected: draft.genre?.caseInsensitiveCompare(genre) == .orderedSame) {
                                    draft.genre = genre
                                }
                            }
                        }
                    }

                    group("Sortierung") {
                        ForEach(WatchlistSort.allCases) { sort in
                            option(sort.label, selected: draft.sort == sort) { draft.sort = sort }
                        }
                    }

                    apply
                }
                .padding(.horizontal, WatchlistMetrics.screen)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(NoriTheme.bg.ignoresSafeArea())
            .navigationTitle("Merkliste filtern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundStyle(NoriTheme.muted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Setzt nur die Filter zurück. Suche, Schnellfilter,
                    // Merkliste und Fortschritt bleiben unberührt — das ist
                    // ein Filterknopf, kein Aufräumknopf.
                    Button("Zurücksetzen") { draft.reset() }
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(NoriTheme.accent)
                        .disabled(draft == .none)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(NoriTheme.bg)
    }

    private var apply: some View {
        let count = preview(draft)
        return Button {
            filters = draft
            dismiss()
        } label: {
            Text(count == 0 ? "Keine Treffer" : "\(count) \(count == 1 ? "Ergebnis" : "Ergebnisse") anzeigen")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(NoriTheme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(NoriTheme.fg, in: Capsule())
        }
        .buttonStyle(NoriPressStyle(scale: 0.98))
        .padding(.top, 4)
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(NoriTheme.muted)
            // `WrappingOptions` statt eines `HStack`: „Genre" kann ein
            // Dutzend Einträge haben, und die sollen umbrechen statt zu
            // schrumpfen oder seitlich zu verschwinden.
            WatchlistOptionFlow { content() }
        }
        .accessibilityElement(children: .contain)
    }

    private func option(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? NoriTheme.bg : NoriTheme.fg.opacity(0.82))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    selected ? AnyShapeStyle(NoriTheme.fg) : AnyShapeStyle(NoriTheme.elevated.opacity(0.72)),
                    in: Capsule()
                )
                .overlay {
                    if !selected { Capsule().strokeBorder(NoriTheme.border) }
                }
        }
        .buttonStyle(NoriPressStyle(scale: 0.94))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Ein Fluss aus Kapseln, der am Rand umbricht.
///
/// SwiftUI hat dafür seit iOS 16 kein eigenes Layout; `Layout` selbst zu
/// schreiben ist hier weniger Aufwand als ein `LazyVGrid` mit
/// Spaltenschätzung, und es bricht nach der tatsächlichen Breite der
/// Beschriftung um statt nach einer geratenen.
struct WatchlistOptionFlow: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, max(widest, 0)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
