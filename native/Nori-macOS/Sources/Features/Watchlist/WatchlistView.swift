import SwiftUI

struct WatchlistView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]

    @AppStorage("nori.watchlist.layout") private var layoutRaw = NoriViewMode.grid.rawValue

    private var layout: NoriViewMode { NoriViewMode(rawValue: layoutRaw) ?? .grid }
    private let grid = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 18)]

    private var anime: [WatchlistEntry] { items(for: .aniworld) }
    private var serien: [WatchlistEntry] { items(for: .serienstream) }

    struct WatchlistEntry: Identifiable, Hashable {
        let slug: String
        let title: String
        var id: String { slug }
    }

    private func items(for provider: CatalogProvider) -> [WatchlistEntry] {
        library.favorites.compactMap { slug in
            guard library.source(of: slug) == provider else { return nil }
            let title = library.titles[slug]
                ?? catalog.first(where: { $0.slug == slug })?.title
                ?? slug
            return WatchlistEntry(slug: slug, title: title)
        }
    }

    var body: some View {
        Group {
            if library.favorites.isEmpty {
                ContentUnavailableView(
                    "Keine Merkliste",
                    systemImage: "heart",
                    description: Text("Titel über das Herz in der Detailansicht merken. Anime und Serien bleiben getrennt gespeichert.")
                )
            } else if layout == .grid {
                gridBody
            } else {
                listBody
            }
        }
        .navigationTitle("Merkliste")
        .navigationSubtitle("\(library.favorites.count) gemerkt")
        .toolbar {
            if !library.favorites.isEmpty {
                ToolbarItem(placement: .principal) {
                    NoriViewModePicker(raw: $layoutRaw)
                }
            }
        }
    }

    private var listBody: some View {
        List {
            if !anime.isEmpty {
                Section("Anime") {
                    ForEach(anime) { row($0, .aniworld) }
                }
            }
            if !serien.isEmpty {
                Section("Serien") {
                    ForEach(serien) { row($0, .serienstream) }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var gridBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !anime.isEmpty { section("Anime", items: anime, source: .aniworld) }
                if !serien.isEmpty { section("Serien", items: serien, source: .serienstream) }
            }
            .padding(20)
        }
        .background(NoriTheme.bg)
    }

    private func section(_ label: String, items: [WatchlistEntry], source: CatalogProvider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NoriSectionHeader(label, trailing: "\(items.count)")
            LazyVGrid(columns: grid, alignment: .leading, spacing: 20) {
                ForEach(items) { item in
                    NoriPosterCell(
                        title: item.title,
                        slug: item.slug,
                        kind: source,
                        // Wie in der Liste: beim Öffnen auf die Quelle des
                        // Eintrags umschalten, damit die Detailseite nicht in
                        // der falschen landet.
                        onOpen: { library.provider = source }
                    )
                    .contextMenu {
                        Button("Aus Merkliste entfernen") {
                            library.toggleFavorite(item.slug)
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: WatchlistEntry, _ src: CatalogProvider) -> some View {
        HStack(spacing: 10) {
            NoriSeriesLink(
                slug: item.slug,
                titleHint: item.title,
                provider: src,
                onOpen: { library.provider = src }
            ) {
                HStack(spacing: 10) {
                    PosterTile(title: item.title, slug: item.slug, compact: true, kind: src)
                        .frame(width: 32)
                    Text(item.title)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
            }
            .help(item.title)

            Button {
                library.toggleFavorite(item.slug)
            } label: {
                Image(systemName: "heart.slash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Aus Merkliste entfernen")
            .foregroundStyle(NoriTheme.muted)
            .help("Aus Merkliste entfernen")
        }
        .padding(.vertical, 3)
    }
}
