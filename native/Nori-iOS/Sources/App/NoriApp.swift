import SwiftUI

@main
struct NoriApp: App {
    @State private var library: LibraryStore
    @State private var sync: GoogleDriveSync

    init() {
        let library = LibraryStore()
        // Landet als Metadatum im abgelegten Stand. Nützlich, wenn irgendwann
        // ein Gerät etwas schreibt, das die anderen nicht verstehen.
        library.appVersion = NoriBuild.version

        // Ohne hinterlegte Client-ID gibt es keinen Anmeldeweg — und die
        // Einstellungen bieten dann auch keinen an, statt einen anzubieten,
        // der sicher scheitert.
        let configuration = GoogleOAuthConfiguration.fromBundle()
        let presenter = configuration?.reversedClientId
            .map(WebAuthenticationSignInPresenter.init(reversedClientId:))

        _library = State(initialValue: library)
        _sync = State(initialValue: GoogleDriveSync(
            store: library, presenter: presenter, configuration: configuration))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(sync)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(GoogleDriveSync.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    /// Beide Kataloge, zusammengeführt und alphabetisch. Bleibt beim
    /// Bereichswechsel stehen, damit nicht jedes Mal neu geladen wird.
    @State private var allItems: [CatalogItem] = []
    /// Der Ausschnitt, den die Ansichten sehen.
    @State private var catalog: [CatalogItem] = []

    /// Die Slugs des Bereichs — oder `nil`, wenn er gar nicht nach Genre
    /// einschränkt. Nur der Kalender braucht das: seine Einträge kennen
    /// Slug und Quelle, aber keine Genres.
    private var scopeSlugs: Set<String>? {
        guard library.scope.genre != nil else { return nil }
        return Set(catalog.map(\.slug))
    }
    @State private var error: String?
    @State private var loading = true

    /// Welcher Tab offen ist.
    ///
    /// Steht seit dem Umbau der Startseite unter Beobachtung, statt dem
    /// `TabView` überlassen zu bleiben: der Kopfbereich der Startseite hat
    /// einen Suchknopf, und Noris Suche liegt im Katalog. Der Knopf wechselt
    /// deshalb den Tab, statt auf der Startseite ein zweites Suchfeld
    /// aufzubauen — zwei Suchen wären zwei Filterregeln, die auseinanderlaufen
    /// können. Dasselbe gilt für „Kalender" über den neuen Episoden.
    @State private var tab: Tab = .home

    enum Tab: Hashable {
        case home, catalog, calendar, watchlist, more
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                // Ausdrücklich `allItems` und nicht `catalog`: die Startseite
                // hat keinen Bereichsumschalter und führt Anime und Serien
                // gemeinsam. Ein Ausschnitt, den der Betrachter dort nicht
                // sieht und nicht ändern kann, ließe die Seite ohne
                // ersichtlichen Grund halb leer wirken.
                NoriHomeView(
                    catalog: allItems,
                    loading: loading,
                    error: error,
                    reload: load,
                    openSearch: { tab = .catalog },
                    openCalendar: { tab = .calendar }
                )
            }
            .tabItem { Label("Start", systemImage: "house") }
            .tag(Tab.home)

            NavigationStack {
                // Wie die Startseite ausdrücklich `allItems` und nicht
                // `catalog`: Der neue Katalog hat keinen Bereichsumschalter
                // mehr, sondern einen Inhaltsfilter „Alle | Anime | Serien".
                // Ein zusätzlicher Ausschnitt, den der Betrachter dort weder
                // sieht noch ändern kann, ließe den Katalog ohne
                // ersichtlichen Grund halb leer wirken. Kalender und
                // Merkliste schneiden weiterhin nach `LibraryScope` zu und
                // tragen den Umschalter auch weiterhin.
                CatalogView(catalog: allItems, loading: loading, error: error, reload: load)
            }
            .tabItem { Label("Katalog", systemImage: "square.grid.2x2") }
            .tag(Tab.catalog)

            NavigationStack {
                CalendarView(slugs: scopeSlugs)
            }
            .tabItem { Label("Kalender", systemImage: "calendar") }
            .tag(Tab.calendar)

            NavigationStack {
                // Wie die Startseite bekommt die Merkliste den
                // **vollständigen** Katalog. Sie hat seit dem Umbau keinen
                // Bereichsumschalter mehr, und ein Ausschnitt, den der
                // Betrachter hier weder sieht noch ändern kann, ließe
                // gemerkte Titel ohne ersichtlichen Grund fehlen. Nach
                // Medientyp filtert sie selbst — im Filter-Sheet, wo die
                // Einstellung sichtbar bleibt und der Filterknopf sie
                // markiert. Der Katalog liefert hier ohnehin nur Genres und
                // Alternativtitel; was gemerkt ist, steht in `favorites`.
                WatchlistView(catalog: allItems, openCatalog: { tab = .catalog })
            }
            .tabItem { Label("Merkliste", systemImage: "heart") }
            .tag(Tab.watchlist)

            NavigationStack {
                MoreView()
            }
            .tabItem { Label("Mehr", systemImage: "gearshape") }
            .tag(Tab.more)
        }
        .tint(NoriTheme.accent)
        .task(id: library.scope) { await load() }
        // Eine bestehende Verbindung wieder aufnehmen. Hier wird nichts
        // gefragt und kein Fenster geöffnet — liegen Tokens im Schlüsselbund,
        // geht es weiter, sonst bleibt es bei „nicht verbunden".
        .task { await sync.restore() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Beim Zurückkommen sofort sehen, was die anderen Geräte
                // inzwischen geschrieben haben.
                sync.syncNow()
                sync.engine.startPolling()
            case .background:
                // Der letzte verlässliche Moment. Auf ein „App wird beendet"
                // ist kein Verlass, und genau deshalb wird hier abgeglichen
                // statt dort.
                sync.engine.stopPolling()
                sync.syncNow()
            default:
                sync.engine.stopPolling()
            }
        }
    }

    /// Beide Kataloge laden, zusammenführen, nach Bereich ausschneiden.
    ///
    /// Vorher lud iOS **nur** den Katalog der aktiven Quelle. Damit konnte
    /// eine Liste nie Titel beider Seiten enthalten — „Alle" wäre nicht
    /// darstellbar gewesen, und „K-Drama" erst recht nicht, weil der Bereich
    /// zwar an Serienstream hängt, aber als Ausschnitt daraus. Der Mac macht
    /// es seit dem Umbau genauso.
    ///
    /// Fehlschläge werden je Quelle festgehalten: fällt nur eine Seite aus,
    /// zeigt die App die andere weiter, statt leer zu bleiben.
    func load() async {
        loading = catalog.isEmpty
        error = nil

        async let anime = Self.fetch(.aniworld)
        async let serien = Self.fetch(.serienstream)
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
            allItems = merged.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
        catalog = allItems.filter { library.scope.includes(item: $0) }

        // Nur melden, was den gewählten Bereich betrifft. Fällt AniWorld aus,
        // während „Serien" gewählt ist, ist das keine Meldung wert.
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

    private static func fetch(_ provider: CatalogProvider) async -> Outcome {
        do {
            return .success(try await AniworldClient.shared.getCatalog(provider: provider).items)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}