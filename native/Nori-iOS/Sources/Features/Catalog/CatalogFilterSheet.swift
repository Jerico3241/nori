import SwiftUI

/// Das Filter-Blatt.
///
/// Ein natives `sheet` mit `presentationDetents` und Griff — kein
/// nachgebautes CSS-Glas. Die Vorlage zeigt die Idee (Gruppen aus Pillen,
/// „Zurücksetzen" oben, „Ergebnisse anzeigen" unten); die Umsetzung benutzt
/// Systembauteile, damit Aufziehen, Wischen und VoiceOver das tun, was
/// überall sonst im System.
///
/// ## Entwurf, dann anwenden
///
/// Die Auswahl wird in einem **Entwurf** gehalten und erst mit „Ergebnisse
/// anzeigen" übernommen. Sonst rechnete jeder Tipp im Blatt das Raster
/// dahinter neu — bei zehntausend Einträgen sichtbar, und die
/// Ergebniszählung zappelte, während man noch auswählt.
///
/// ## Nur, was es gibt
///
/// Jede Gruppe erscheint nur, wenn der geladene Katalog dazu etwas hergibt
/// (`CatalogFacets`). Ohne belegte Status gibt es keinen Statusfilter, ohne
/// belegte Sprachen keine Sprachauswahl, und die Jahresspanne stammt aus den
/// tatsächlich vorhandenen Jahren statt aus einer festen Demo-Spanne.
struct CatalogFilterSheet: View {
    let facets: CatalogFacets
    let applied: CatalogFilters
    let appliedSort: CatalogSort
    let apply: (CatalogFilters, CatalogSort) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = CatalogFilters()
    @State private var sort: CatalogSort = .popular

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    contentGroup
                    statusGroup
                    genreGroup
                    yearGroup
                    languageGroup
                    sortGroup
                }
                .padding(.horizontal, CatalogMetrics.screen)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(NoriTheme.bg.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zurücksetzen") {
                        draft = .none
                        sort = .popular
                    }
                    .foregroundStyle(NoriTheme.highlight)
                    .disabled(draft.isEmpty && sort == .popular)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { commit() }
                        .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) { applyBar }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(NoriTheme.bg)
        .onAppear {
            draft = applied
            sort = appliedSort
        }
    }

    private func commit() {
        apply(draft, sort)
        dismiss()
    }

    // MARK: - Gruppen

    @ViewBuilder
    private var contentGroup: some View {
        if facets.mediaTypes.count > 1 {
            CatalogFilterGroup("Inhalt") {
                CatalogOption(label: "Alle", selected: draft.mediaType == nil) {
                    draft.mediaType = nil
                }
                ForEach(facets.mediaTypes) { type in
                    CatalogOption(label: type.label, selected: draft.mediaType == type) {
                        draft.mediaType = type
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusGroup: some View {
        if !facets.statuses.isEmpty {
            CatalogFilterGroup("Status", note: statusNote) {
                CatalogOption(label: "Alle", selected: draft.status == nil) {
                    draft.status = nil
                }
                ForEach(facets.statuses) { status in
                    CatalogOption(label: status.label, selected: draft.status == status) {
                        draft.status = status
                    }
                }
            }
        }
    }

    /// Der Hinweis ist keine Entschuldigung, sondern eine Auskunft: Der Status
    /// steht auf keiner Katalogseite und in keiner TMDB-Rangliste. Nori kann
    /// ihn nur dort belegen, wo eine Liste oder der eigene Kalender es
    /// hergibt — und filtert dann ausschließlich nach Belegtem.
    private var statusNote: String {
        "Nur Titel, deren Status belegt ist."
    }

    @ViewBuilder
    private var genreGroup: some View {
        if !facets.genres.isEmpty {
            CatalogFilterGroup("Genre", note: draft.genres.isEmpty ? nil : "Mehrfachauswahl") {
                CatalogOption(label: "Alle", selected: draft.genres.isEmpty) {
                    draft.genres = []
                }
                ForEach(facets.genres.prefix(28)) { facet in
                    CatalogOption(
                        label: facet.label,
                        selected: draft.genres.contains(facet.label)
                    ) {
                        if draft.genres.contains(facet.label) {
                            draft.genres.remove(facet.label)
                        } else {
                            draft.genres.insert(facet.label)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var yearGroup: some View {
        if let range = facets.years, range.lowerBound < range.upperBound {
            CatalogYearRange(range: range, selection: $draft.years)
        }
    }

    @ViewBuilder
    private var languageGroup: some View {
        if !facets.languages.isEmpty {
            CatalogFilterGroup("Sprache", note: "Aus der Verfügbarkeit bei AniWorld und Serienstream.") {
                CatalogOption(label: "Alle", selected: draft.language == nil) {
                    draft.language = nil
                }
                ForEach(facets.languages) { language in
                    CatalogOption(label: language.label, selected: draft.language == language) {
                        draft.language = language
                    }
                }
            }
        }
    }

    private var sortGroup: some View {
        CatalogFilterGroup("Sortierung") {
            ForEach(CatalogSort.allCases) { option in
                CatalogOption(label: option.label, selected: sort == option) {
                    sort = option
                }
            }
        }
    }

    /// Der Knopf am unteren Rand.
    ///
    /// Ohne Trefferzahl, und das ist Absicht: Die Zahl des angewendeten
    /// Stands wäre hier falsch, sobald jemand etwas im Entwurf verstellt
    /// hat, und die Zahl des Entwurfs hieße, bei jedem Tipp im Blatt den
    /// ganzen Katalog neu zu filtern.
    private var applyBar: some View {
        Button(action: commit) {
            Text("Ergebnisse anzeigen")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(NoriTheme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background { Capsule().fill(NoriTheme.accent) }
        }
        .buttonStyle(NoriPressStyle(scale: 0.98))
        .padding(.horizontal, CatalogMetrics.screen)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Bausteine des Blatts

/// Eine Filtergruppe: Beschriftung, optional eine Erläuterung, darunter die
/// umbrechenden Optionen.
struct CatalogFilterGroup<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String, note: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.note = note
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(NoriTheme.muted)
            CatalogFlow(spacing: 7, rowSpacing: 7) {
                content()
            }
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(NoriTheme.muted.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Eine einzelne Option im Blatt.
struct CatalogOption: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? NoriTheme.bg : NoriTheme.fg.opacity(0.82))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background {
                    Capsule().fill(selected ? NoriTheme.accent : NoriTheme.elevated.opacity(0.9))
                }
                .overlay {
                    if !selected { Capsule().strokeBorder(NoriTheme.border) }
                }
        }
        .buttonStyle(NoriPressStyle(scale: 0.95))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Die Jahresspanne.
///
/// Zwei Auswahlmenüs statt eines Doppelreglers: Ein Regler mit zwei Griffen
/// ist auf einem Telefon schwer genau zu treffen, und die Menüs benennen die
/// Jahre, statt sie schätzen zu lassen. Die Grenzen kommen aus den
/// vorhandenen Daten — es gibt kein Jahr zur Auswahl, in dem nichts liegt.
struct CatalogYearRange: View {
    let range: ClosedRange<Int>
    @Binding var selection: ClosedRange<Int>?

    private var years: [Int] { Array(range).reversed() }
    private var from: Int { selection?.lowerBound ?? range.lowerBound }
    private var to: Int { selection?.upperBound ?? range.upperBound }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Erscheinungsjahr")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(NoriTheme.muted)
                Spacer()
                if selection != nil {
                    Button("Alle Jahre") { selection = nil }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NoriTheme.highlight)
                }
            }
            HStack(spacing: 8) {
                picker(title: "Von", value: from) { year in
                    // Die Untergrenze zieht die Obergrenze mit, statt eine
                    // leere Spanne zuzulassen.
                    selection = year ... max(year, to)
                }
                picker(title: "Bis", value: to) { year in
                    selection = min(from, year) ... year
                }
            }
        }
    }

    private func picker(title: String, value: Int, set: @escaping (Int) -> Void) -> some View {
        Menu {
            ForEach(years, id: \.self) { year in
                Button(String(year)) { set(year) }
            }
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(NoriTheme.muted)
                Spacer(minLength: 4)
                Text(String(value))
                    .foregroundStyle(NoriTheme.fg)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NoriTheme.muted)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background { Capsule().fill(NoriTheme.elevated.opacity(0.9)) }
            .overlay { Capsule().strokeBorder(NoriTheme.border) }
        }
        .accessibilityLabel("\(title) \(value)")
    }
}

/// Umbrechende Reihe.
///
/// SwiftUI hat dafür keinen fertigen Container: `HStack` bricht nicht um,
/// `LazyVGrid` gibt allen Spalten dieselbe Breite — bei Pillen von „Alle" bis
/// „Science Fiction" sähe das aus wie eine Tabelle mit Lücken. Das
/// `Layout`-Protokoll gibt es seit iOS 16, das Target steht auf 17.
struct CatalogFlow: Layout {
    var spacing: CGFloat = 7
    var rowSpacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(rows.count - 1, 0))
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
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, needed > width {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
