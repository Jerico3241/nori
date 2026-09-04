import Observation
import SwiftUI

// MARK: - Navigation

enum NoriSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case catalog
    case categories
    case calendar
    case watchlist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Entdecken"
        case .catalog: return "Katalog"
        case .categories: return "Kategorien"
        case .calendar: return "Kalender"
        case .watchlist: return "Merkliste"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .catalog: return "square.grid.2x2"
        case .categories: return "rectangle.grid.3x2"
        case .calendar: return "calendar"
        case .watchlist: return "bookmark"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .home: return "1"
        case .catalog: return "2"
        case .categories: return "3"
        case .calendar: return "4"
        case .watchlist: return "5"
        }
    }
}

// MARK: - Wiedergabe-Fenster

/// Beschreibt, was im Player-Fenster laufen soll.
struct PlayerRequest: Hashable, Identifiable {
    var series: SeriesDetail
    var episode: Episode
    var season: String
    var resumeAt: Double

    var id: String { "\(series.slug)|\(season)|\(episode.number)|\(Int(resumeAt))" }
}

/// Der Player ist auf dem Mac ein eigenes Fenster statt eines Sheets: eigene
/// Titelleiste, Vollbild über den grünen Knopf, ⌘W zum Schließen.
@Observable
final class PlayerHost {
    var request: PlayerRequest?
}

/// Der geladene Katalog, damit auch Ansichten außerhalb der Hauptnavigation
/// darauf zugreifen können — die Detailseite baut daraus ihre Empfehlungen.
@Observable
final class CatalogStore {
    var items: [CatalogItem] = []
    var provider: CatalogProvider = .aniworld

    /// Titel mit den meisten gemeinsamen Genres, ohne den Titel selbst.
    func similar(to slug: String, genres: [String], limit: Int = 18) -> [CatalogItem] {
        guard !genres.isEmpty else { return [] }
        let wanted = Set(genres)
        return items
            .filter { $0.slug != slug }
            .map { (item: $0, shared: wanted.intersection($0.genres).count) }
            .filter { $0.shared > 0 }
            .sorted { $0.shared > $1.shared }
            .prefix(limit)
            .map(\.item)
    }
}

enum NoriWindow {
    static let player = "nori.player"
}

// MARK: - App

@main
struct NoriApp: App {
    @State private var library = LibraryStore()
    @State private var playerHost = PlayerHost()
    @State private var catalogStore = CatalogStore()

    var body: some Scene {
        WindowGroup("Nori") {
            RootView()
                .environment(library)
                .environment(playerHost)
                .environment(catalogStore)
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified)
        .commands { NoriCommands() }

        Window("Wiedergabe", id: NoriWindow.player) {
            PlayerWindowView()
                .environment(library)
                .environment(playerHost)
        }
        .defaultSize(width: 1100, height: 660)

        Settings {
            SettingsView()
                .environment(library)
        }
    }
}

// MARK: - Menübefehle

/// Menübefehle wirken auf das gerade aktive Fenster, deshalb laufen sie über
/// `focusedSceneValue` und nicht über globalen Zustand.
struct NoriCommands: Commands {
    @FocusedBinding(\.noriSection) private var section
    @FocusedValue(\.noriReload) private var reload

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            ForEach(NoriSection.allCases) { item in
                Button(item.title) { section = item }
                    .keyboardShortcut(item.shortcut, modifiers: [.command])
                    .disabled(section == nil)
            }
            Divider()
            Button("Aktualisieren") { reload?.run() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(reload == nil)
            Divider()
        }
    }
}

struct NoriReloadAction {
    var run: () -> Void
}

private struct NoriSectionKey: FocusedValueKey {
    typealias Value = Binding<NoriSection>
}

private struct NoriReloadKey: FocusedValueKey {
    typealias Value = NoriReloadAction
}

extension FocusedValues {
    var noriSection: Binding<NoriSection>? {
        get { self[NoriSectionKey.self] }
        set { self[NoriSectionKey.self] = newValue }
    }

    var noriReload: NoriReloadAction? {
        get { self[NoriReloadKey.self] }
        set { self[NoriReloadKey.self] = newValue }
    }
}

// MARK: - Hauptfenster

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(CatalogStore.self) private var catalogStore

    @State private var section: NoriSection = .home
    @State private var catalog: [CatalogItem] = []
    @State private var error: String?
    @State private var loading = true
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
        } detail: {
            NavigationStack {
                detail
            }
            .id(section)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 460)
        .task(id: library.provider) { await load() }
        .focusedSceneValue(\.noriSection, $section)
        .focusedSceneValue(\.noriReload, NoriReloadAction {
            Task { await load(force: true) }
            NotificationCenter.default.post(name: .noriRefreshRequested, object: nil)
        })
    }

    private var sidebar: some View {
        List(selection: Binding<NoriSection?>(
            get: { section },
            set: { if let next = $0 { section = next } }
        )) {
            Section("Mediathek") {
                ForEach(NoriSection.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 176, ideal: 208, max: 280)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Divider()
                ProviderPicker()
                    .padding(.horizontal, 10)
                HStack(spacing: 6) {
                    Text(library.provider.label)
                        .font(.caption2)
                        .foregroundStyle(NoriTheme.muted)
                    Spacer()
                    SettingsLink {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help("Einstellungen (⌘,)")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .home:
            HomeView(catalog: catalog, loading: loading, error: error, reload: { await load(force: true) })
        case .catalog:
            CatalogView(catalog: catalog, loading: loading, error: error, reload: { await load(force: true) })
        case .categories:
            CategoriesView(catalog: catalog, loading: loading)
        case .calendar:
            CalendarView()
        case .watchlist:
            WatchlistView(catalog: catalog)
        }
    }

    func load(force: Bool = false) async {
        loading = catalog.isEmpty
        error = nil
        do {
            let result = try await AniworldClient.shared.getCatalog(provider: library.provider, force: force)
            catalog = result.items
            catalogStore.items = result.items
            catalogStore.provider = library.provider
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Wiedergabefenster-Inhalt

struct PlayerWindowView: View {
    @Environment(PlayerHost.self) private var host

    var body: some View {
        Group {
            if let request = host.request {
                PlayerScreen(request: request)
                    .id(request.id)
            } else {
                ContentUnavailableView(
                    "Keine Wiedergabe",
                    systemImage: "play.slash",
                    description: Text("Wähle im Hauptfenster eine Folge aus.")
                )
            }
        }
        .frame(minWidth: 560, minHeight: 340)
        // Beim Schließen des Fensters die Wiedergabe wirklich beenden, damit
        // kein Stream im Hintergrund weiterläuft.
        .onDisappear { host.request = nil }
    }
}
