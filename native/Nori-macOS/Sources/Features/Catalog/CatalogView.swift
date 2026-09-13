import SwiftUI

/// Der Katalog des gewählten Bereichs, als Raster oder Liste, mit Suche.
///
/// ## Suche außerhalb von `body`
///
/// Vorher filterte die Ansicht in einer berechneten Eigenschaft `filtered`:
/// bei jedem Neuzeichnen — und `body` las sie dreimal (leer?, Raster,
/// Untertitel) — `lowercased()` über Titel, Alternativtitel und Slug von
/// zehntausend Einträgen, bei jedem Anschlag ohne Pause. Akzente blieben dabei
/// stehen: „pokemon" fand „Pokémon" nicht, auf dem iPhone schon.
///
/// Jetzt dieselbe Architektur wie auf iOS, ohne dessen Oberfläche: ein
/// vorbereiteter Index (`CatalogItemIndex` im Kern, dieselbe Normalisierung
/// wie die iPhone-Suche), eine entprellte Suche, gerechnet abseits des
/// Hauptthreads. Die Ansicht zeigt nur noch das Ergebnis.
struct CatalogView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]
    /// Zählt hoch, wenn sich der Inhalt von `catalog` ändert.
    let catalogRevision: Int
    let loading: Bool
    let error: String?
    let reload: () async -> Void

    @State private var q = ""
    @State private var model = MacCatalogModel()
    @AppStorage("nori.catalog.layout") private var layoutRaw = NoriViewMode.grid.rawValue

    private var layout: NoriViewMode { NoriViewMode(rawValue: layoutRaw) ?? .grid }
    private let grid = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 18)]

    var body: some View {
        Group {
            if let error, catalog.isEmpty, !loading {
                ContentUnavailableView(
                    "Katalog nicht geladen",
                    systemImage: "wifi.exclamationmark",
                    description: Text(error)
                )
            } else if !model.isReady(for: catalogRevision) && (loading || !catalog.isEmpty) {
                // Der Umriss des Rasters, solange der Katalog lädt oder der
                // Index das erste Mal gebaut wird. Toolbar und Suche stehen
                // schon da.
                skeleton
            } else if model.results.isEmpty {
                if model.appliedQuery.isEmpty {
                    ContentUnavailableView(
                        "Katalog leer",
                        systemImage: "tray",
                        description: Text("Für diesen Bereich kamen keine Titel zurück.")
                    )
                } else {
                    ContentUnavailableView.search(text: model.appliedQuery)
                }
            } else if layout == .grid {
                gridBody
            } else {
                listBody
            }
        }
        .navigationTitle("Katalog")
        .navigationSubtitle(subtitle)
        .searchable(text: $q, placement: .toolbar, prompt: "Titel suchen")
        .toolbar {
            ToolbarItem(placement: .principal) {
                NoriViewModePicker(raw: $layoutRaw)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await reload() }
                } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .help("Katalog neu laden (⌘R)")
                .disabled(loading)
            }
        }
        .task(id: catalogRevision) { await model.load(catalog, revision: catalogRevision) }
        .onChange(of: q) { _, value in model.search(value) }
    }

    private var subtitle: String {
        let count = model.results.count
        if model.appliedQuery.isEmpty { return "\(library.scope.label) · \(count) Titel" }
        return "\(count) Treffer für „\(model.appliedQuery)“"
    }

    private var skeleton: some View {
        ScrollView {
            NoriSkeletonGroup(label: "Katalog wird geladen") {
                LazyVGrid(columns: grid, alignment: .leading, spacing: 20) {
                    ForEach(0 ..< 24, id: \.self) { _ in
                        NoriPosterSkeleton(width: NoriLayout.cardWidth)
                    }
                }
                .padding(20)
            }
        }
        .scrollDisabled(true)
        .background(NoriTheme.bg)
    }

    private var listBody: some View {
        List {
            if let error {
                ErrorBanner(message: error) { Task { await reload() } }
                    .listRowSeparator(.hidden)
            }
            ForEach(model.results) { item in
                NoriSeriesLink(slug: item.slug, titleHint: item.title, provider: item.provider) {
                    HStack(spacing: 10) {
                        PosterTile(title: item.title, slug: item.slug, compact: true, kind: item.provider)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.body)
                                .lineLimit(1)
                            if !item.genres.isEmpty {
                                Text(item.genres.prefix(4).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(NoriTheme.muted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        CatalogFavoriteMark(slug: item.slug)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(NoriTheme.muted)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 3)
                }
                .help(item.title)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var gridBody: some View {
        ScrollView {
            LazyVGrid(columns: grid, alignment: .leading, spacing: 20) {
                ForEach(model.results) { item in
                    PosterCell(item: item)
                }
            }
            .padding(20)
        }
        .background(NoriTheme.bg)
    }
}

/// Das Herz einer gemerkten Zeile.
///
/// Eigene Ansicht, damit nur sie die Merkliste liest: stünde
/// `library.isFavorite` in der Zeile selbst, zeichnete jedes Merken die ganze
/// Liste neu.
private struct CatalogFavoriteMark: View {
    @Environment(LibraryStore.self) private var library
    let slug: String

    var body: some View {
        if library.isFavorite(slug) {
            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundStyle(NoriTheme.accent)
                .accessibilityLabel("Gemerkt")
        }
    }
}

/// Index und Ergebnis des Mac-Katalogs.
@MainActor
@Observable
final class MacCatalogModel {
    /// Was die Ansicht zeigt.
    private(set) var results: [CatalogItem] = []
    /// Die Suche, zu der `results` gehören — nicht, was gerade im Feld steht.
    private(set) var appliedQuery = ""
    /// Zu welchem Katalogstand der Index gebaut ist.
    private(set) var builtRevision: Int?

    @ObservationIgnored private var index = CatalogItemIndex([])
    @ObservationIgnored private var pendingQuery = ""
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Zählt je neu gebautem Index. Eine Suche, die auf einem älteren Index
    /// gerechnet wurde, wird verworfen und auf dem neuen wiederholt.
    @ObservationIgnored private var generation = 0

    func isReady(for revision: Int) -> Bool { builtRevision == revision }

    /// Den Index zu einem Katalogstand bauen — einmal je Stand.
    func load(_ items: [CatalogItem], revision: Int) async {
        guard builtRevision != revision else { return }
        let query = pendingQuery
        let built = await Task.detached(priority: .userInitiated) { () -> (CatalogItemIndex, [CatalogItem]) in
            let index = CatalogItemIndex(items)
            return (index, index.search(query))
        }.value
        guard !Task.isCancelled else { return }
        index = built.0
        generation &+= 1
        builtRevision = revision
        // Hat sich die Eingabe inzwischen geändert, gilt die neue.
        if query == pendingQuery {
            appliedQuery = query
            results = built.1
        } else {
            search(pendingQuery)
        }
    }

    /// Die Eingabe übernehmen — entprellt, und gerechnet abseits des
    /// Hauptthreads. Eine neue Taste bricht die vorige Suche ab.
    func search(_ text: String) {
        searchTask?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingQuery = query
        searchTask = Task { [weak self] in
            // Das Leeren des Feldes wirkt sofort; Tippen wartet einen Moment.
            if !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
            }
            guard let self else { return }
            let index = self.index
            let generation = self.generation
            let found = await Task.detached(priority: .userInitiated) { index.search(query) }.value
            guard !Task.isCancelled else { return }
            guard generation == self.generation else {
                self.search(query)
                return
            }
            self.appliedQuery = query
            self.results = found
        }
    }
}
