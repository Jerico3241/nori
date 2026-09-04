import SwiftUI

struct GenreRow: Identifiable, Hashable {
    let title: String
    let items: [CatalogItem]
    var id: String { title }
}

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]
    let loading: Bool
    let error: String?
    let reload: () async -> Void

    @State private var genreRows: [GenreRow] = []

    private let grid = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 18)]

    var body: some View {
        NoriScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    if let error {
                        ErrorBanner(message: error) { Task { await reload() } }
                    }

                    if loading && catalog.isEmpty {
                        ProgressView("Nori wird geladen")
                            .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        let watching = library.continueWatching()

                        if let hero = watching.first {
                            ExploreHero(progress: hero)
                        } else if let featured = catalog.first {
                            ExploreHero(item: featured, kind: library.provider)
                        }

                        if watching.count > 1 {
                            ContinueRow(items: Array(watching.dropFirst()))
                        }

                        ForEach(genreRows) { row in
                            PosterRow(title: row.title, items: row.items)
                        }

                        if !catalog.isEmpty {
                            NoriSectionHeader(
                                "Alle \(library.provider.kind)",
                                trailing: "\(catalog.count) Titel"
                            )
                            LazyVGrid(columns: grid, alignment: .leading, spacing: 20) {
                                ForEach(catalog.prefix(60)) { item in
                                    PosterCell(item: item)
                                }
                            }
                        } else {
                            ContentUnavailableView(
                                "Nichts geladen",
                                systemImage: "tray",
                                description: Text("Der Katalog von \(library.provider.label) ist gerade leer.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 200)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Entdecken")
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
        .task(id: rowsKey) {
            genreRows = Self.buildRows(from: catalog)
        }
    }

    /// Neu gruppieren, wenn sich Quelle oder Katalogumfang ändert. Ein
    /// `onChange` auf dem Array selbst würde bei jedem Rendern tausende
    /// Einträge vergleichen.
    private var rowsKey: String {
        "\(library.provider.rawValue)|\(catalog.count)"
    }

    static func buildRows(from catalog: [CatalogItem]) -> [GenreRow] {
        guard catalog.count > 12 else { return [] }
        var counts: [String: Int] = [:]
        for item in catalog {
            for genre in item.genres.prefix(3) where !genre.isEmpty {
                counts[genre, default: 0] += 1
            }
        }
        let top = counts
            .filter { $0.value >= 8 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(6)
            .map(\.key)

        var used: Set<String> = []
        var rows: [GenreRow] = []
        for genre in top {
            let items = catalog
                .filter { $0.genres.contains(genre) && !used.contains($0.slug) }
                .prefix(18)
                .map { $0 }
            guard items.count >= 6 else { continue }
            used.formUnion(items.map(\.slug))
            rows.append(GenreRow(title: genre, items: items))
        }
        return rows
    }
}

// MARK: - Bausteine

struct ExploreHero: View {
    private let title: String
    private let slug: String
    private let kind: CatalogProvider
    private let progress: WatchProgress?
    private let subtitle: String

    init(progress: WatchProgress) {
        self.title = progress.title
        self.slug = progress.slug
        self.kind = progress.provider ?? providerFromPath(progress.episodePath)
        self.progress = progress
        let episode = progress.germanTitle.isEmpty ? "" : " · \(progress.germanTitle)"
        self.subtitle = "Staffel \(progress.season) · Folge \(progress.episode)\(episode)"
    }

    init(item: CatalogItem, kind: CatalogProvider) {
        self.title = item.title
        self.slug = item.slug
        self.kind = kind
        self.progress = nil
        self.subtitle = item.genres.prefix(4).joined(separator: " · ")
    }

    var body: some View {
        NoriSeriesLink(slug: slug, titleHint: title, provider: kind) {
            HStack(alignment: .top, spacing: 22) {
                PosterTile(title: title, slug: slug, kind: kind)
                    .frame(width: 150)

                VStack(alignment: .leading, spacing: 10) {
                    Text(progress == nil ? "Vorgeschlagen" : "Weiterschauen")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NoriTheme.accent)
                        .textCase(.uppercase)

                    Text(title)
                        .font(.title.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(NoriTheme.muted)
                            .lineLimit(2)
                    }

                    if let progress {
                        HStack(spacing: 10) {
                            ProgressView(value: watchRatio(progress))
                                .frame(width: 200)
                            Text("\(formatClock(progress.positionSec)) von \(formatClock(progress.durationSec))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(NoriTheme.muted)
                        }
                    }

                    Label(progress == nil ? "Ansehen" : "Fortsetzen", systemImage: "play.fill")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(NoriTheme.accent, in: Capsule())
                        .foregroundStyle(NoriTheme.onAccent)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: 860, alignment: .leading)
            .background(NoriTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(NoriTheme.border)
            }
        }
        .help(title)
    }
}

struct PosterCell: View {
    let item: CatalogItem
    var width: CGFloat?

    var body: some View {
        NoriSeriesLink(slug: item.slug, titleHint: item.title) {
            VStack(alignment: .leading, spacing: 7) {
                PosterTile(title: item.title, slug: item.slug)
                Text(item.title)
                    .font(.caption)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                if !item.genres.isEmpty {
                    Text(item.genres.prefix(2).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(NoriTheme.muted)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .help(item.title)
    }
}

struct PosterRow: View {
    let title: String
    let items: [CatalogItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NoriSectionHeader(title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        PosterCell(item: item, width: 124)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct ContinueRow: View {
    let items: [WatchProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NoriSectionHeader("Weiterschauen")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
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
    }
}

struct ContinueCard: View {
    let item: WatchProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PosterTile(
                title: item.title,
                slug: item.slug,
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
        .frame(width: 124)
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
