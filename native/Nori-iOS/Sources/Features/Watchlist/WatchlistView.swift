import SwiftUI

struct WatchlistView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]
    @AppStorage("nori.layout.watchlist") private var layout: NoriLayout = .grid

    private var anime: [(slug: String, title: String)] {
        items(for: .aniworld)
    }

    private var serien: [(slug: String, title: String)] {
        items(for: .serienstream)
    }

    private func items(for provider: CatalogProvider) -> [(slug: String, title: String)] {
        library.favorites.compactMap { slug in
            let source = library.source(of: slug)
            if source != provider { return nil }
            let title = library.titles[slug]
                ?? catalog.first(where: { $0.slug == slug })?.title
                ?? slug
            return (slug, title)
        }
    }

    var body: some View {
        NoriScreen {
            if library.favorites.isEmpty {
                ContentUnavailableView(
                    "Keine Merkliste",
                    systemImage: "heart",
                    description: Text("Titel über das Herz merken. Anime und Serien bleiben getrennt gespeichert.")
                )
                .foregroundStyle(NoriTheme.muted)
            } else {
                VStack(spacing: 0) {
                    LayoutBar(layout: $layout)
                    if layout == .grid {
                        grid
                    } else {
                        list
                    }
                }
            }
        }
        .navigationTitle("Merkliste")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                KindSwitch(provider: Bindable(library).provider)
            }
        }
    }

    private var list: some View {
        List {
            if !anime.isEmpty {
                Section("Anime") {
                    ForEach(anime, id: \.slug) { item in row(item, .aniworld) }
                }
            }
            if !serien.isEmpty {
                Section("Serien") {
                    ForEach(serien, id: \.slug) { item in row(item, .serienstream) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !anime.isEmpty {
                    NoriGridHeader(title: "Anime")
                    section(anime, .aniworld)
                }
                if !serien.isEmpty {
                    NoriGridHeader(title: "Serien")
                    section(serien, .serienstream)
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 16)
        }
    }

    private func section(_ items: [(slug: String, title: String)], _ src: CatalogProvider) -> some View {
        LazyVGrid(columns: NoriLayout.columns, spacing: 18) {
            ForEach(items, id: \.slug) { item in
                NoriSeriesLink(
                    slug: item.slug,
                    titleHint: item.title,
                    scaleOnPress: true,
                    provider: src,
                    onOpen: { library.provider = src }
                ) {
                    NoriGridCard(title: item.title, slug: item.slug, kind: src)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func row(_ item: (slug: String, title: String), _ src: CatalogProvider) -> some View {
        NoriSeriesLink(slug: item.slug, titleHint: item.title, provider: src, onOpen: { library.provider = src }) {
            HStack(spacing: 12) {
                PosterTile(title: item.title, slug: item.slug, compact: true, kind: src)
                    .frame(width: 44)
                Text(item.title)
                    .lineLimit(2)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(NoriTheme.surface)
    }
}
