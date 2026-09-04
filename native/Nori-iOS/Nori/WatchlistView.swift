import SwiftUI

struct WatchlistView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]

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
        }
        .navigationTitle("Merkliste")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                KindSwitch(provider: Bindable(library).provider)
            }
        }
    }

    private func row(_ item: (slug: String, title: String), _ src: CatalogProvider) -> some View {
        NoriSeriesLink(slug: item.slug, titleHint: item.title, provider: src, onOpen: { library.provider = src }) {
            Text(item.title)
        }
        .listRowBackground(NoriTheme.surface)
    }
}
