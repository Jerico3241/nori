import SwiftUI

struct CatalogView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]
    let loading: Bool
    let error: String?
    let reload: () async -> Void
    @State private var q = ""
    @AppStorage("nori.layout.catalog") private var layout: NoriLayout = .grid

    var filtered: [CatalogItem] {
        let needle = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty { return catalog }
        return catalog.filter {
            $0.title.lowercased().contains(needle)
                || $0.alts.contains { $0.lowercased().contains(needle) }
                || $0.slug.lowercased().contains(needle)
        }
    }

    var body: some View {
        NoriScreen {
            VStack(spacing: 0) {
                if loading && catalog.isEmpty {
                    ProgressView("Katalog wird geladen").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LayoutBar(layout: $layout)
                    if layout == .grid {
                        grid
                    } else {
                        list
                    }
                }
            }
        }
        .navigationTitle("Katalog")
        .searchable(text: $q, prompt: "Suchen")
        .refreshable { await reload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                KindSwitch(provider: Bindable(library).provider)
            }
        }
    }

    private var list: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red)
            }
            ForEach(filtered) { item in
                NoriSeriesLink(slug: item.slug, titleHint: item.title, provider: item.provider) {
                    HStack(spacing: 12) {
                        // Dieselbe Kachel wie im Raster, nur klein:
                        // sie bringt Cover-Nachladen und
                        // Buchstaben-Rückfall schon mit.
                        PosterTile(
                            title: item.title,
                            slug: item.slug,
                            compact: true,
                            kind: item.provider
                        )
                        .frame(width: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                            if !item.genres.isEmpty {
                                Text(item.genres.prefix(3).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(NoriTheme.muted)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(NoriTheme.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var grid: some View {
        ScrollView {
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            LazyVGrid(columns: NoriLayout.columns, spacing: 18) {
                ForEach(filtered) { item in
                    NoriSeriesLink(
                        slug: item.slug,
                        titleHint: item.title,
                        scaleOnPress: true,
                        provider: item.provider
                    ) {
                        NoriGridCard(
                            title: item.title,
                            slug: item.slug,
                            subtitle: item.genres.first,
                            kind: item.provider
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}
