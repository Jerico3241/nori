import SwiftUI

// Der Kopfbereich des Katalogs: Überschrift, Verlauf, Suche, Filterknopf und
// die Schnellfilterleiste.
//
// Aufgeteilt in vier kleine Ansichten, nicht weil es hübscher aussieht,
// sondern weil der Typechecker bei einem einzigen verschachtelten `body`
// dieser Größe aufgibt („unable to type-check this expression in reasonable
// time"). Dieselbe Erfahrung wie beim Umbau von Start- und Detailseite.

// MARK: - Überschrift

/// „Entdecken" über „Katalog", rechts der Verlauf.
///
/// Bewusst ohne weitere Bedienelemente: Der Kopfbereich der Vorlage ist ruhig,
/// und der Umschalter „Anime | Serien", der hier einmal stand, ist ersatzlos
/// verschwunden. Anime und Serien werden gemeinsam katalogisiert; wer nur
/// eines sehen will, sagt das im Filter.
struct CatalogTitleBlock: View {
    let history: CatalogHistory
    let onPick: (String) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Entdecken")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(NoriTheme.muted)
                    .textCase(.uppercase)
                Text("Katalog")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(NoriTheme.fg)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            CatalogHistoryButton(history: history, onPick: onPick)
        }
        .padding(.horizontal, CatalogMetrics.screen)
        .accessibilityElement(children: .contain)
    }
}

/// Der Verlaufsknopf.
///
/// Er erscheint **nur**, wenn es etwas zu zeigen gibt. Ein Knopf, der ein
/// leeres Menü öffnet, ist schlechter als kein Knopf — und ein Knopf ohne
/// Funktion hat auf dieser Seite nichts verloren.
struct CatalogHistoryButton: View {
    let history: CatalogHistory
    let onPick: (String) -> Void

    var body: some View {
        if !history.isEmpty {
            Menu {
                if !history.searches.isEmpty {
                    Section("Letzte Suchen") {
                        ForEach(history.searches, id: \.self) { term in
                            Button {
                                onPick(term)
                            } label: {
                                Label(term, systemImage: "magnifyingglass")
                            }
                        }
                    }
                }
                if !history.opened.isEmpty {
                    Section("Zuletzt geöffnet") {
                        ForEach(history.opened, id: \.self) { title in
                            Button {
                                onPick(title)
                            } label: {
                                Label(title, systemImage: "clock.arrow.circlepath")
                            }
                        }
                    }
                }
                if !history.searches.isEmpty {
                    Divider()
                    Button(role: .destructive) {
                        history.clearSearches()
                    } label: {
                        Label("Suchverlauf löschen", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(NoriTheme.fg)
                    .frame(width: CatalogMetrics.circle, height: CatalogMetrics.circle)
                    .background { Circle().fill(NoriTheme.elevated.opacity(0.85)) }
                    .overlay { Circle().strokeBorder(NoriTheme.border) }
            }
            .accessibilityLabel("Verlauf")
        }
    }
}

// MARK: - Suche

/// Suchfeld und Filterknopf.
///
/// Das Feld steht im Inhalt und nicht in der Navigationsleiste. `.searchable`
/// wäre die kürzere Schreibweise, setzt die Suche aber unter eine
/// Systemüberschrift und lässt die Vorlage nicht zu — dort ist die Suche das
/// erste, was man sieht, und der Filterknopf sitzt unmittelbar daneben.
struct CatalogSearchBar: View {
    @Binding var text: String
    let filtersActive: Bool
    let openFilters: () -> Void

    @FocusState private var focused: Bool
    @AppStorage(NoriGlassSetting.key) private var glassEnabled = true

    var body: some View {
        HStack(spacing: 9) {
            field
            filterButton
        }
        .padding(.horizontal, CatalogMetrics.screen)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NoriTheme.muted)
            TextField("Titel, Genre, Jahr …", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(NoriTheme.fg)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(NoriTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche löschen")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: CatalogMetrics.search)
        .noriGlass(Capsule(), enabled: glassEnabled, off: NoriTheme.elevated.opacity(0.9))
        .overlay { Capsule().strokeBorder(NoriTheme.border) }
        .contentShape(Capsule())
        .onTapGesture { focused = true }
    }

    private var filterButton: some View {
        Button(action: openFilters) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NoriTheme.fg)
                .frame(width: CatalogMetrics.search, height: CatalogMetrics.search)
                .noriGlass(Circle(), enabled: glassEnabled, off: NoriTheme.elevated.opacity(0.9))
                .overlay { Circle().strokeBorder(NoriTheme.border) }
                .overlay(alignment: .topTrailing) { dot }
        }
        .buttonStyle(NoriPressStyle(scale: 0.94))
        .accessibilityLabel(filtersActive ? "Filter, aktiv" : "Filter")
    }

    /// Der Punkt, der sagt: Hier ist gerade etwas eingestellt.
    ///
    /// Ohne ihn ist ein gesetzter Filter nur an der Ergebnisliste zu erkennen
    /// — und wer nicht weiß, dass er filtert, hält eine kurze Liste für einen
    /// leeren Katalog.
    @ViewBuilder
    private var dot: some View {
        if filtersActive {
            Circle()
                .fill(NoriTheme.highlight)
                .frame(width: 9, height: 9)
                .overlay { Circle().strokeBorder(NoriTheme.bg.opacity(0.9), lineWidth: 1.5) }
                .padding(7)
        }
    }
}

// MARK: - Schnellfilter

/// Die waagerecht scrollende Pillenreihe unter der Suche.
///
/// Die Genre-Pillen stammen aus den tatsächlich vorhandenen Genres
/// (`CatalogFacets.quickGenres`), nicht aus einer festen Liste. Eine Pille,
/// die garantiert null Treffer liefert, ist eine Falle.
struct CatalogQuickFilterBar: View {
    let filters: [CatalogQuickFilter]
    let selected: CatalogQuickFilter
    let onSelect: (CatalogQuickFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(filters) { filter in
                    CatalogChip(
                        label: filter.label,
                        active: filter == selected
                    ) {
                        onSelect(filter)
                    }
                }
            }
            .padding(.horizontal, CatalogMetrics.screen)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

// MARK: - Verlauf

/// Suchverlauf und zuletzt geöffnete Titel.
///
/// Zwei Quellen, beide echt: die letzten Suchbegriffe dieses Geräts und
/// `LibraryStore.recents`, das die Detailseite beim Öffnen füllt. Es gibt
/// hier bewusst nichts Erfundenes — der Knopf in der Vorlage bekommt eine
/// Funktion oder er verschwindet.
@Observable
final class CatalogHistory {
    private(set) var searches: [String] = []
    var opened: [String] = []

    private static let key = "nori.catalog.searches"
    private static let limit = 8

    init() {
        searches = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    var isEmpty: Bool { searches.isEmpty && opened.isEmpty }

    /// Einen Suchbegriff merken.
    ///
    /// Erst, wenn er etwas getroffen hat, und erst ab drei Zeichen: Jeder
    /// Tastendruck als eigener Verlaufseintrag wäre kein Verlauf, sondern ein
    /// Protokoll.
    func remember(_ raw: String) {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 3 else { return }
        var next = searches.filter { $0.localizedCaseInsensitiveCompare(term) != .orderedSame }
        next.insert(term, at: 0)
        searches = Array(next.prefix(Self.limit))
        UserDefaults.standard.set(searches, forKey: Self.key)
    }

    func clearSearches() {
        searches = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
