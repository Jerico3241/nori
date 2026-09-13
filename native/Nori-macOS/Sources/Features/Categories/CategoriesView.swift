import SwiftUI

/// Genre-Übersicht: erst alle Kategorien als Kacheln, nach Auswahl das Raster
/// der Titel dieser Kategorie.
///
/// Genres und Titel einer Kategorie werden je Katalogstand einmal gerechnet,
/// abseits des Hauptthreads. Vorher standen beide als berechnete
/// Eigenschaften in der Ansicht: `body` las `genres` dreimal und `items`
/// zweimal, und jedes Lesen lief über den ganzen Katalog.
struct CategoriesView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]
    /// Zählt hoch, wenn sich der Inhalt von `catalog` ändert.
    let catalogRevision: Int
    let loading: Bool

    @State private var selected: String?
    @State private var genres: [GenreCount] = []
    @State private var items: [CatalogItem] = []
    /// Zu welchem Katalogstand `genres` gehören.
    @State private var countedRevision: Int?

    struct GenreCount: Identifiable, Hashable, Sendable {
        let name: String
        let count: Int
        var id: String { name }
    }

    private let genreGrid = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 16)]
    private let posterGrid = [GridItem(.adaptive(minimum: 158, maximum: 200), spacing: 18)]

    var body: some View {
        NoriScreen {
            if countedRevision != catalogRevision && (loading || !catalog.isEmpty) {
                skeleton
            } else if genres.isEmpty {
                ContentUnavailableView(
                    "Keine Kategorien",
                    systemImage: "square.grid.2x2",
                    description: Text("Für diesen Katalog kommen keine Genres mit.")
                )
            } else if let selected {
                genreDetail(selected)
            } else {
                overview
            }
        }
        .navigationTitle("Kategorien")
        .navigationSubtitle(selected ?? "\(genres.count) Genres")
        .toolbar {
            if selected != nil {
                ToolbarItem(placement: .navigation) {
                    Button {
                        self.selected = nil
                    } label: {
                        Label("Alle Kategorien", systemImage: "chevron.left")
                    }
                    .help("Zurück zur Kategorienübersicht")
                }
            }
        }
        .task(id: catalogRevision) {
            let source = catalog
            let counted = await Task.detached(priority: .userInitiated) { Self.count(source) }.value
            guard !Task.isCancelled else { return }
            genres = counted
            countedRevision = catalogRevision
        }
        .task(id: "\(catalogRevision)|\(selected ?? "")") {
            guard let selected else {
                items = []
                return
            }
            let source = catalog
            let found = await Task.detached(priority: .userInitiated) {
                source.filter { $0.genres.contains(selected) }
            }.value
            guard !Task.isCancelled else { return }
            items = found
        }
    }

    nonisolated private static func count(_ catalog: [CatalogItem]) -> [GenreCount] {
        var counts: [String: Int] = [:]
        for item in catalog {
            for genre in item.genres where !genre.isEmpty {
                counts[genre, default: 0] += 1
            }
        }
        return counts
            .filter { $0.value >= 3 }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { GenreCount(name: $0.key, count: $0.value) }
    }

    private var skeleton: some View {
        ScrollView {
            NoriSkeletonGroup(label: "Kategorien werden geladen") {
                LazyVGrid(columns: genreGrid, alignment: .leading, spacing: 16) {
                    ForEach(0 ..< 18, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(NoriTheme.elevated)
                            .frame(height: 84)
                    }
                }
                .padding(NoriLayout.gutter)
            }
        }
        .scrollDisabled(true)
    }

    private var overview: some View {
        ScrollView {
            LazyVGrid(columns: genreGrid, alignment: .leading, spacing: 16) {
                ForEach(genres) { genre in
                    GenreTile(name: genre.name, count: genre.count) {
                        selected = genre.name
                    }
                }
            }
            .padding(NoriLayout.gutter)
        }
    }

    private func genreDetail(_ genre: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NoriSectionHeader(genre, trailing: "\(items.count) Titel")
                LazyVGrid(columns: posterGrid, alignment: .leading, spacing: 24) {
                    ForEach(items) { item in
                        PosterCell(item: item)
                    }
                }
            }
            .padding(NoriLayout.gutter)
        }
    }
}

struct GenreTile: View {
    let name: String
    let count: Int
    let action: () -> Void

    @State private var hovering = false

    /// Aus dem Namen abgeleitet, damit jede Kategorie wiedererkennbar bleibt,
    /// ohne dass dafür Bilder hinterlegt werden müssen.
    ///
    /// Bewusst nicht `hashValue`: Swift verwendet je Programmstart einen
    /// anderen Startwert, wodurch jede Kategorie bei jedem Öffnen der App eine
    /// andere Farbe bekommen hätte.
    private var tint: Color {
        var sum = 0
        for scalar in name.unicodeScalars {
            sum = (sum &* 31 &+ Int(scalar.value)) % 360_000
        }
        return Color(hue: Double(sum % 360) / 360, saturation: 0.52, brightness: 0.5)
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(count) Titel")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(16)
            .frame(height: 84)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [tint, tint.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(hovering ? NoriTheme.accent : .clear, lineWidth: 2)
            }
            .scaleEffect(hovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .noriAnimation(NoriMotion.hover, value: hovering)
        .onHover { hovering = $0 }
        .help("\(name) – \(count) Titel")
    }
}
