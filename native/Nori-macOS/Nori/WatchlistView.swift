import SwiftUI

struct WatchlistView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]

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
            } else {
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
        }
        .navigationTitle("Merkliste")
        .navigationSubtitle("\(library.favorites.count) gemerkt")
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
