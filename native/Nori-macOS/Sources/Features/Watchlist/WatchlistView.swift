import SwiftUI

/// Die Merkliste, getrennt nach Anime und Serien.
///
/// Die Einträge werden gerechnet, wenn sich Merkliste oder Katalog ändern —
/// nicht in `body`. Vorher suchte jede Zeile ihren Titel mit
/// `catalog.first(where:)` im ganzen Katalog, und `body` baute beide Listen
/// mehrfach: bei fünfzig gemerkten Titeln und zehntausend im Katalog einige
/// Millionen Vergleiche je Neuzeichnen.
struct WatchlistView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]
    /// Zählt hoch, wenn sich der Inhalt von `catalog` ändert.
    let catalogRevision: Int

    @AppStorage("nori.watchlist.layout") private var layoutRaw = NoriViewMode.grid.rawValue
    @State private var anime: [WatchlistEntry] = []
    @State private var serien: [WatchlistEntry] = []

    private var layout: NoriViewMode { NoriViewMode(rawValue: layoutRaw) ?? .grid }
    private let grid = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 18)]

    struct WatchlistEntry: Identifiable, Hashable {
        let slug: String
        let title: String
        /// Wie weit der Titel ist — dieselbe Rechnung wie auf iPhone und
        /// Fernseher (`watchSummary` im Kern). Bis hierher stand auf dem Mac
        /// gar kein Sehstand in der Merkliste.
        let watch: WatchSummary
        var id: String { slug }
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
        // An Revisionen, nicht an Anzahlen: ein entfernter und ein neu
        // gemerkter Titel ändern die Zahl nicht, wohl aber die Liste.
        // `watchRevision` kommt dazu, seit die Zeile den Sehstand zeigt: ohne
        // ihn stünde nach einer Wiedergabe im Nachbarfenster noch der alte
        // Stand. Ein Fünf-Sekunden-Takt zählt dafür bewusst nicht mit.
        .task(id: "\(library.favoritesRevision)|\(catalogRevision)|\(library.watchRevision)") { rebuild() }
    }

    private func rebuild() {
        // Einmal ein Verzeichnis statt je Eintrag eine Suche durch den Katalog.
        var known: [String: String] = [:]
        known.reserveCapacity(catalog.count)
        for item in catalog where known[item.slug] == nil {
            known[item.slug] = item.title
        }
        var nextAnime: [WatchlistEntry] = []
        var nextSerien: [WatchlistEntry] = []
        for slug in library.favorites {
            let source = library.source(of: slug)
            let entry = WatchlistEntry(
                slug: slug,
                title: library.titles[slug] ?? known[slug] ?? slug,
                watch: library.seriesWatchSummary(slug: slug, provider: source)
            )
            if source == .aniworld {
                nextAnime.append(entry)
            } else {
                nextSerien.append(entry)
            }
        }
        anime = nextAnime
        serien = nextSerien
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
                    // Die Quelle geht über `kind` an die Detailseite. Vorher
                    // schaltete das Öffnen zusätzlich die Vorgabequelle der
                    // ganzen Bibliothek um — eine Einstellung mit frischem
                    // Zeitstempel, die beim nächsten Abgleich auf alle Geräte
                    // wanderte.
                    VStack(alignment: .leading, spacing: 5) {
                        NoriPosterCell(
                            title: item.title,
                            slug: item.slug,
                            kind: source
                        )
                        Text(item.watch.stateText)
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                            .lineLimit(1)
                    }
                    .contextMenu {
                        Button("Aus Merkliste entfernen") {
                            library.toggleFavorite(item.slug)
                        }
                        if item.watch.state != .unseen {
                            Button("Fortschritt vergessen") {
                                library.resetSeriesProgress(slug: item.slug, provider: source)
                            }
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
                provider: src
            ) {
                HStack(spacing: 10) {
                    PosterTile(title: item.title, slug: item.slug, compact: true, kind: src)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .lineLimit(1)
                        Text(item.watch.stateText)
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                            .lineLimit(1)
                    }
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
