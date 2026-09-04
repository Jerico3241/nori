import SwiftUI

struct CatalogView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]
    let loading: Bool
    let error: String?
    let reload: () async -> Void
    @State private var q = ""

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
            Group {
                if loading && catalog.isEmpty {
                    ProgressView("Katalog wird geladen").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let error {
                            Text(error).foregroundStyle(.red)
                        }
                        ForEach(filtered) { item in
                            NoriSeriesLink(slug: item.slug, titleHint: item.title) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                    if !item.genres.isEmpty {
                                        Text(item.genres.prefix(3).joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(NoriTheme.muted)
                                    }
                                }
                            }
                            .listRowBackground(NoriTheme.surface)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Katalog")
        .searchable(text: $q, prompt: "Suchen")
        .refreshable { await reload() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                KindSwitch(provider: Bindable(library).provider)
            }
        }
    }
}
