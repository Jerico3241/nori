import SwiftUI

enum CatalogLayout: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }
    var symbol: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    var label: String { self == .list ? "Liste" : "Raster" }
}

struct CatalogView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]
    let loading: Bool
    let error: String?
    let reload: () async -> Void

    @State private var q = ""
    @AppStorage("nori.catalog.layout") private var layoutRaw = CatalogLayout.list.rawValue

    private var layout: CatalogLayout { CatalogLayout(rawValue: layoutRaw) ?? .list }
    private let grid = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 18)]

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
        Group {
            if loading && catalog.isEmpty {
                ProgressView("Katalog wird geladen")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, catalog.isEmpty {
                ContentUnavailableView(
                    "Katalog nicht geladen",
                    systemImage: "wifi.exclamationmark",
                    description: Text(error)
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: q)
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
                Picker("Darstellung", selection: $layoutRaw) {
                    ForEach(CatalogLayout.allCases) { option in
                        Label(option.label, systemImage: option.symbol).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Zwischen Liste und Raster wechseln")
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
    }

    private var subtitle: String {
        let count = filtered.count
        if q.isEmpty { return "\(library.provider.label) · \(count) Titel" }
        return "\(count) Treffer für „\(q)“"
    }

    private var listBody: some View {
        List {
            if let error {
                ErrorBanner(message: error) { Task { await reload() } }
                    .listRowSeparator(.hidden)
            }
            ForEach(filtered) { item in
                NoriSeriesLink(slug: item.slug, titleHint: item.title) {
                    HStack(spacing: 10) {
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
                        if library.isFavorite(item.slug) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(NoriTheme.accent)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(NoriTheme.muted)
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
                ForEach(filtered) { item in
                    NoriSeriesLink(slug: item.slug, titleHint: item.title) {
                        VStack(alignment: .leading, spacing: 7) {
                            PosterTile(title: item.title, slug: item.slug)
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(2, reservesSpace: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .help(item.title)
                }
            }
            .padding(20)
        }
        .background(NoriTheme.bg)
    }
}
