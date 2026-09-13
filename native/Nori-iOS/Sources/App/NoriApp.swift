import SwiftUI

@main
struct NoriApp: App {
    @State private var library: LibraryStore
    @State private var sync: GoogleDriveSync

    init() {
        #if DEBUG
        // Netzstörungen nachstellen: `-NoriNetworkSimulation offline` usw.
        // Ohne das Argument geschieht nichts.
        NoriNetworkSimulation.install()
        #endif
        let library = LibraryStore()
        // Landet als Metadatum im abgelegten Stand. Nützlich, wenn irgendwann
        // ein Gerät etwas schreibt, das die anderen nicht verstehen.
        library.appVersion = NoriBuild.version

        _library = State(initialValue: library)
        // Das Anmeldefenster wird erst gebaut, wenn eine Client-ID feststeht —
        // aus ihr entsteht die Rückleitungsadresse. Die ID kann aus der
        // Build-Einstellung kommen oder in den Einstellungen eingetragen
        // werden; beides landet hier.
        _sync = State(initialValue: GoogleDriveSync(store: library) { configuration in
            configuration.reversedClientId
                .map(WebAuthenticationSignInPresenter.init(reversedClientId:))
        })
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
    /// Zählt hoch, wenn sich der **Inhalt** des Katalogs ändert.
    ///
    /// Die Ansichten erkannten einen neuen Katalog vorher an seiner Anzahl.
    /// Liefert eine Quelle beim Aktualisieren dieselbe Zahl anderer Titel,
    /// blieben Startseite, Katalog und Merkliste beim alten Stand stehen; und
    /// ein erneutes Laden mit identischem Ergebnis rechnete trotzdem alles neu,
    /// sobald sich die Zahl nur zwischenzeitlich geändert hatte.
    @State private var catalogRevision = 0

    /// Die Slugs des Bereichs — oder `nil`, wenn er gar nicht nach Genre
    /// einschränkt. Nur der Kalender braucht das: seine Einträge kennen
    /// Slug und Quelle, aber keine Genres.
    ///
    /// Beim Laden gerechnet und abgelegt, nicht in `body`: dort lief bei jedem
    /// Neuzeichnen der Wurzelansicht ein `Set` über den ganzen Ausschnitt.
    @State private var scopeSlugs: Set<String>?
    @State private var scopeSlugsRevision = 0
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
                // Ausdrücklich `allItems` und nicht der Ausschnitt: die
                // Startseite hat keinen Bereichsumschalter und führt Anime und
                // Serien gemeinsam. Ein Ausschnitt, den der Betrachter dort
                // nicht sieht und nicht ändern kann, ließe die Seite ohne
                // ersichtlichen Grund halb leer wirken.
                NoriHomeView(
                    catalog: allItems,
                    catalogRevision: catalogRevision,
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
                // Wie die Startseite ausdrücklich `allItems`: Der Katalog hat
                // keinen Bereichsumschalter, sondern einen Inhaltsfilter
                // „Alle | Anime | Serien". Ein zusätzlicher Ausschnitt, den
                // der Betrachter dort weder sieht noch ändern kann, ließe den
                // Katalog ohne ersichtlichen Grund halb leer wirken. Kalender
                // und Merkliste schneiden weiterhin nach `LibraryScope` zu.
                CatalogView(
                    catalog: allItems,
                    catalogRevision: catalogRevision,
                    loading: loading,
                    error: error,
                    reload: load
                )
            }
            .tabItem { Label("Katalog", systemImage: "square.grid.2x2") }
            .tag(Tab.catalog)

            NavigationStack {
                CalendarView(slugs: scopeSlugs, slugsRevision: scopeSlugsRevision)
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
                WatchlistView(
                    catalog: allItems,
                    catalogRevision: catalogRevision,
                    openCatalog: { tab = .catalog }
                )
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
                // Beim Zurückkommen sehen, was die anderen Geräte inzwischen
                // geschrieben haben — sofern der letzte Versuch nicht gerade
                // eben war. Die Engine entscheidet das an einer Stelle.
                sync.appDidBecomeActive()
            case .background:
                // Der letzte verlässliche Moment. Auf ein „App wird beendet"
                // ist kein Verlass, und genau deshalb wird hier abgeglichen
                // statt dort — aber nur, wenn es etwas zu schreiben gibt.
                // Vorher der Fortschritt, der nur im Speicher steht.
                library.flush()
                sync.appDidEnterBackground()
            default:
                library.flush()
                sync.engine.stopPolling()
            }
        }
        // Bei knappem Speicher die Bilder im Arbeitsspeicher freigeben. Die
        // Dateien auf der Platte bleiben — Kacheln kommen ohne Netz zurück.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task { await CoverImageLoader.shared.trimMemory() }
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
    ///
    /// Sortiert, verglichen und zugeschnitten wird außerhalb des Hauptthreads.
    /// Zehntausend Titel mit `localizedCaseInsensitiveCompare` zu sortieren lag
    /// vorher bei jedem Start und jedem Bereichswechsel auf dem Hauptthread —
    /// genau in dem Moment, in dem die erste Oberfläche erscheinen soll.
    func load() async {
        loading = allItems.isEmpty
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

        let prepared = await CatalogPreparation.prepare(
            merged: merged,
            previous: allItems,
            previousSlugs: scopeSlugs,
            scope: library.scope
        )
        if prepared.changed {
            allItems = prepared.items
            catalogRevision &+= 1
        }
        if prepared.slugsChanged {
            scopeSlugs = prepared.slugs
            scopeSlugsRevision &+= 1
        }

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

/// Den geladenen Katalog für die Ansichten vorbereiten — abseits des
/// Hauptthreads.
enum CatalogPreparation {
    struct Result: Sendable {
        let items: [CatalogItem]
        /// Hat sich der Inhalt geändert? Nur dann zählt die Revision hoch.
        let changed: Bool
        let slugs: Set<String>?
        let slugsChanged: Bool
    }

    static func prepare(
        merged: [CatalogItem],
        previous: [CatalogItem],
        previousSlugs: Set<String>?,
        scope: LibraryScope
    ) async -> Result {
        await Task.detached(priority: .userInitiated) {
            // Kam gar nichts, bleibt der bisherige Stand — ein Ausfall beider
            // Quellen leert keine Liste, die schon dasteht.
            let items = merged.isEmpty
                ? previous
                : merged.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            let slugs: Set<String>? = scope.genre == nil
                ? nil
                : Set(items.lazy.filter { scope.includes(item: $0) }.map(\.slug))
            return Result(
                items: items,
                changed: items != previous,
                slugs: slugs,
                slugsChanged: slugs != previousSlugs
            )
        }.value
    }
}
