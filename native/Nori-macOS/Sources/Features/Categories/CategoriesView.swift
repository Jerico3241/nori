import SwiftUI

/// Genre-Übersicht: erst alle Kategorien als Kacheln, nach Auswahl das Raster
/// der Titel dieser Kategorie.
struct CategoriesView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]
    let loading: Bool

    @State private var selected: String?

    private let genreGrid = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 16)]
    private let posterGrid = [GridItem(.adaptive(minimum: 158, maximum: 200), spacing: 18)]

    private var genres: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in catalog {
            for genre in item.genres where !genre.isEmpty {
                counts[genre, default: 0] += 1
            }
        }
        return counts
            .filter { $0.value >= 3 }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { (name: $0.key, count: $0.value) }
    }

    private var items: [CatalogItem] {
        guard let selected else { return [] }
        return catalog.filter { $0.genres.contains(selected) }
    }

    var body: some View {
        NoriScreen {
            if loading && catalog.isEmpty {
                ProgressView("Katalog wird geladen")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }

    private var overview: some View {
        ScrollView {
            LazyVGrid(columns: genreGrid, alignment: .leading, spacing: 16) {
                ForEach(genres, id: \.name) { genre in
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
