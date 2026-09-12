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
    var provider: CatalogProvider

    var id: String { "\(provider.rawValue)|\(series.slug)|\(season)|\(episode.number)|\(Int(resumeAt))" }
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
    /// Beide Kataloge, zusammengeführt und alphabetisch.
    var items: [CatalogItem] = []
    /// Die zuletzt gewählte Quelle. Entscheidet, welche Seite ein Titel ohne
    /// eigene Quellangabe öffnet — nicht mehr, was in den Listen steht.
    var provider: CatalogProvider = .aniworld

    /// Der Ausschnitt für einen Bereich.
    ///
    /// Die Abkürzung prüft `provider` **und** `genre`: seit es `.kdrama` gibt,
    /// ist ein Bereich nicht mehr dasselbe wie eine Quelle. Fragte hier nur
    /// `provider != nil`, käme `.kdrama` zwar durch — der Ausschnitt wäre aber
    /// der ungefilterte Serienstream-Katalog gewesen.
    func items(for scope: LibraryScope) -> [CatalogItem] {
        guard scope.provider != nil || scope.genre != nil else { return items }
        return items.filter { scope.includes(item: $0) }
    }

    /// Die Slugs, die in einem Bereich stehen — oder `nil`, wenn der Bereich
    /// gar nicht nach Genre einschränkt.
    ///
    /// Für Listen, deren Einträge kein Genre mitbringen: der Kalender kennt zu
    /// einer Folge nur Slug und Quelle. Ohne diesen Umweg zeigte der Kalender
    /// unter „K-Drama" den vollständigen Serienstream-Kalender.
    func slugs(for scope: LibraryScope) -> Set<String>? {
        guard scope.genre != nil else { return nil }
        return Set(items(for: scope).map(\.slug))
    }

    /// Titel mit den meisten gemeinsamen Genres, ohne den Titel selbst.
    func similar(to slug: String, genres: [String], provider: CatalogProvider? = nil, limit: Int = 18) -> [CatalogItem] {
        guard !genres.isEmpty else { return [] }
        let wanted = Set(genres)
        // Innerhalb derselben Quelle bleiben: ein Vorschlag, der auf die
        // andere Seite führt, ist zwar abspielbar, wirkt an einer Anime-Seite
        // aber wie ein Fehler.
        return items
            .filter { $0.slug != slug && (provider == nil || $0.provider == nil || $0.provider == provider) }
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
    @State private var library: LibraryStore
    @State private var sync: GoogleDriveSync
    @State private var playerHost = PlayerHost()
    @State private var catalogStore = CatalogStore()

    init() {
        let library = LibraryStore()
        // Landet als Metadatum im abgelegten Stand. Nützlich, wenn irgendwann
        // ein Gerät etwas schreibt, das die anderen nicht verstehen.
        library.appVersion = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        _library = State(initialValue: library)
        // Der Loopback-Server hängt nicht an der Client-ID, wohl aber daran,
        // dass überhaupt eine hinterlegt ist. Gebaut wird er deshalb erst,
        // wenn eine feststeht — aus der Build-Einstellung oder aus den
        // Einstellungen.
        _sync = State(initialValue: GoogleDriveSync(store: library) { _ in
            LoopbackSignInPresenter()
        })
    }

    var body: some Scene {
        WindowGroup("Nori") {
            RootView()
                .environment(library)
                .environment(sync)
                .environment(playerHost)
                .environment(catalogStore)
                // Eine bestehende Verbindung wieder aufnehmen und danach im
                // Vordergrund regelmäßig nach fremden Änderungen sehen. Hier
                // wird nichts gefragt: liegen Tokens im Schlüsselbund, geht es
                // weiter, sonst bleibt es bei „nicht verbunden".
                .task {
                    await sync.restore()
                    sync.engine.startPolling()
                }
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
                .environment(sync)
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
        .task(id: library.scope) { await load() }
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
                ScopePicker()
                    .padding(.horizontal, 10)
                HStack(spacing: 6) {
                    Text(library.scope.label)
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

    /// Beide Kataloge, nebenläufig.
    ///
    /// Scheitert eine Quelle, bleibt die andere stehen: eine gemeinsame
    /// Bibliothek, die bei einem Ausfall komplett leer ist, wäre ein
    /// Rückschritt gegenüber dem alten Umschalter. Gemeldet wird nur, wenn
    /// **beide** ausfallen — oder wenn die eine ausfällt, die gerade gefragt
    /// ist.
    func load(force: Bool = false) async {
        loading = catalog.isEmpty
        error = nil

        async let anime = Self.fetch(.aniworld, force: force)
        async let serien = Self.fetch(.serienstream, force: force)
        let results = await [anime, serien]

        var merged: [CatalogItem] = []
        var failures: [CatalogProvider: String] = [:]
        for (provider, outcome) in zip([CatalogProvider.aniworld, .serienstream], results) {
            switch outcome {
            case .success(let items): merged.append(contentsOf: items)
            case .failure(let message): failures[provider] = message
            }
        }

        if !merged.isEmpty {
            catalogStore.items = merged.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        catalogStore.provider = library.provider
        catalog = catalogStore.items(for: library.scope)

        if let named = library.scope.provider {
            error = failures[named]
        } else {
            error = failures.count == 2
                ? failures.values.sorted().joined(separator: " · ")
                : nil
        }
        loading = false
    }

    private enum Outcome {
        case success([CatalogItem])
        case failure(String)
    }

    private static func fetch(_ provider: CatalogProvider, force: Bool) async -> Outcome {
        do {
            return .success(try await AniworldClient.shared.getCatalog(provider: provider, force: force).items)
        } catch {
            return .failure(error.localizedDescription)
        }
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

