import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]
    let loading: Bool
    let error: String?
    let reload: () async -> Void

    private let grid = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 18)]

    var body: some View {
        NoriScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let error {
                        ErrorBanner(message: error) { Task { await reload() } }
                    }

                    let watching = library.continueWatching()
                    if !watching.isEmpty {
                        NoriSectionHeader("Weiterschauen")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(watching) { item in
                                    NoriSeriesLink(
                                        slug: item.slug,
                                        titleHint: item.title,
                                        provider: item.provider ?? providerFromPath(item.episodePath)
                                    ) {
                                        ContinueCard(item: item)
                                    }
                                    .help(item.title)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    NoriSectionHeader(
                        "Beliebte \(library.provider.kind)",
                        trailing: catalog.isEmpty ? nil : "\(catalog.count) Titel"
                    )

                    if loading && catalog.isEmpty {
                        ProgressView("Nori wird geladen")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if catalog.isEmpty {
                        ContentUnavailableView(
                            "Nichts geladen",
                            systemImage: "tray",
                            description: Text("Der Katalog von \(library.provider.label) ist gerade leer.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        LazyVGrid(columns: grid, alignment: .leading, spacing: 20) {
                            ForEach(catalog.prefix(48)) { item in
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
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Start")
        .navigationSubtitle(library.provider.label)
        .toolbar {
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
}

struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
            Spacer(minLength: 12)
            Button("Erneut laden", action: retry)
        }
        .padding(12)
        .background(NoriTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(NoriTheme.border)
        }
    }
}

struct ContinueCard: View {
    let item: WatchProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PosterTile(
                title: item.title,
                slug: item.slug,
                compact: true,
                kind: item.provider ?? providerFromPath(item.episodePath)
            )
            Text(item.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Text("S\(item.season) · F\(item.episode) · \(formatClock(item.positionSec))")
                .font(.caption2)
                .foregroundStyle(NoriTheme.muted)
            ProgressView(value: watchRatio(item))
                .progressViewStyle(.linear)
                .controlSize(.small)
        }
        .frame(width: 132)
    }
}
