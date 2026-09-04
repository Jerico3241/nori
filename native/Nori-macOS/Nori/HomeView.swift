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

    private let grid = [GridItem(.adaptive(minimum: 152, maximum: 196), spacing: 16)]

    var body: some View {
        NoriScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 34) {
                    if let error {
                        ErrorBanner(message: error) { Task { await reload() } }
                            .padding(.horizontal, 28)
                    }

                    if loading && catalog.isEmpty {
                        ProgressView("Nori wird geladen")
                            .frame(maxWidth: .infinity, minHeight: 360)
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
                            VStack(alignment: .leading, spacing: 14) {
                                NoriSectionHeader(
                                    "Alle \(library.provider.kind)",
                                    trailing: "\(catalog.count) Titel"
                                )
                                LazyVGrid(columns: grid, alignment: .leading, spacing: 22) {
                                    ForEach(catalog.prefix(60)) { item in
                                        PosterCell(item: item)
                                    }
                                }
                            }
                            .padding(.horizontal, 28)
                        } else {
                            ContentUnavailableView(
                                "Nichts geladen",
                                systemImage: "tray",
                                description: Text("Der Katalog von \(library.provider.label) ist gerade leer.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                        }
                    }
                }
                .padding(.bottom, 32)
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

// MARK: - Hero

/// Breiter Kopfbereich nach dem Vorbild gängiger Streaming-Startseiten:
/// Hintergrundbild über die volle Breite, von unten abgedunkelt, darauf Titel,
/// Metazeile und ein prominenter Abspielknopf.
struct ExploreHero: View {
    private let title: String
    private let slug: String
    private let kind: CatalogProvider
    private let progress: WatchProgress?
    private let subtitle: String
    private let badge: String

    @State private var backdrop: URL?
    @State private var poster: URL?

    init(progress: WatchProgress) {
        self.title = progress.title
        self.slug = progress.slug
        self.kind = progress.provider ?? providerFromPath(progress.episodePath)
        self.progress = progress
        let episode = progress.germanTitle.isEmpty ? "" : " · \(progress.germanTitle)"
        self.subtitle = "Staffel \(progress.season) · Folge \(progress.episode)\(episode)"
        self.badge = "Weiterschauen"
    }

    init(item: CatalogItem, kind: CatalogProvider) {
        self.title = item.title
        self.slug = item.slug
        self.kind = kind
        self.progress = nil
        self.subtitle = item.genres.prefix(4).joined(separator: " · ")
        self.badge = "Vorgeschlagen"
    }

    var body: some View {
        NoriSeriesLink(slug: slug, titleHint: title, provider: kind) {
            ZStack(alignment: .bottomLeading) {
                background
                LinearGradient(
                    colors: [.black.opacity(0.05), .black.opacity(0.55), .black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                content
            }
            .frame(height: 380)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .help(title)
        .task(id: slug) { await loadImages() }
    }

    @ViewBuilder
    private var background: some View {
        if let image = backdrop ?? poster {
            AsyncImage(url: image) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    NoriTheme.elevated
                }
            }
        } else {
            LinearGradient(
                colors: [NoriTheme.elevated, NoriTheme.bg],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(badge)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(NoriTheme.accent)

            Text(title)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }

            if let progress {
                HStack(spacing: 12) {
                    ProgressView(value: watchRatio(progress))
                        .frame(width: 220)
                        .tint(NoriTheme.accent)
                    Text("Noch \(formatClock(max(0, progress.durationSec - progress.positionSec)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            Label(progress == nil ? "Ansehen" : "Fortsetzen", systemImage: "play.fill")
                .font(.headline)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(NoriTheme.accent, in: Capsule())
                .foregroundStyle(NoriTheme.onAccent)
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: 720, alignment: .leading)
    }

    private func loadImages() async {
        backdrop = await CoverIndex.shared.backdrop(for: slug)
        poster = await CoverIndex.shared.url(for: slug)
        if backdrop == nil {
            // Noch kein Treffer im Index: einmal nachschlagen, damit der Hero
            // nicht dauerhaft grau bleibt.
            _ = await CoverIndex.shared.lookup(slug: slug, title: title, kind: kind)
            backdrop = await CoverIndex.shared.backdrop(for: slug)
            poster = await CoverIndex.shared.url(for: slug)
        }
    }
}

// MARK: - Zeilen und Kacheln

struct PosterCell: View {
    let item: CatalogItem
    var width: CGFloat?

    var body: some View {
        NoriSeriesLink(slug: item.slug, titleHint: item.title) {
            VStack(alignment: .leading, spacing: 8) {
                PosterTile(title: item.title, slug: item.slug)
                Text(item.title)
                    .font(.callout.weight(.medium))
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
        VStack(alignment: .leading, spacing: 14) {
            NoriSectionHeader(title)
                .padding(.horizontal, 28)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(items) { item in
                        PosterCell(item: item, width: 152)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 6)
            }
        }
    }
}

struct ContinueRow: View {
    let items: [WatchProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NoriSectionHeader("Weiterschauen")
                .padding(.horizontal, 28)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
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
                .padding(.horizontal, 28)
                .padding(.vertical, 6)
            }
        }
    }
}

struct ContinueCard: View {
    let item: WatchProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterTile(
                title: item.title,
                slug: item.slug,
                kind: item.provider ?? providerFromPath(item.episodePath)
            )
            .overlay(alignment: .bottom) {
                ProgressView(value: watchRatio(item))
                    .progressViewStyle(.linear)
                    .tint(NoriTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
            Text(item.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text("S\(item.season) · F\(item.episode) · \(formatClock(item.positionSec))")
                .font(.caption2)
                .foregroundStyle(NoriTheme.muted)
                .lineLimit(1)
        }
        .frame(width: 152)
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
