import SwiftUI

/// Noris Katalog.
///
/// Aufbau: ein durchgehender senkrechter Lauf. Oben „Entdecken / Katalog" mit
/// dem Verlauf, darunter Suchfeld und Filterknopf, darunter die
/// Schnellfilterleiste — diese beiden bleiben beim Scrollen stehen. Es folgen
/// der Discovery-Bereich, die Ergebnisüberschrift mit Sortierung und
/// Rasterumschalter, die aktiven Filter und das Posterraster.
///
/// ## Was hier **nicht** mehr steht
///
/// - Der Umschalter „Anime | Serien" in der Navigationsleiste. Anime und
///   Serien werden gemeinsam katalogisiert; wer nur eines sehen will, sagt
///   das im Filter (`CatalogFilters.mediaType`). Entsprechend bekommt diese
///   Ansicht den **vollständigen** Katalog beider Quellen und nicht den nach
///   `LibraryScope` ausgeschnittenen — ein Ausschnitt, den der Betrachter hier
///   weder sieht noch ändern kann, ließe den Katalog ohne ersichtlichen Grund
///   halb leer wirken. Kalender und Merkliste schneiden weiterhin zu und
///   tragen den Umschalter auch weiterhin.
/// - Die Liste-gegen-Kacheln-Leiste. Der Katalog zeigt Poster, in zwei
///   Dichten; die Liste war eine dritte Darstellung derselben Daten mit
///   44 Punkten Bild.
/// - Die Suche in der Navigationsleiste.
///
/// ## Was diese Ansicht nicht tut
///
/// Sie filtert und sortiert nichts selbst. Was „neu", „beliebt" und „top
/// bewertet" heißt, rechnet `CatalogService` aus geprüften Bausteinen in
/// `NoriCore`. Die vorherige Ansicht filterte in einer berechneten
/// Eigenschaft — das lief bei jedem Neuzeichnen und konnte nur eine
/// Teilzeichenkette im Titel.
struct CatalogView: View {
    @Environment(LibraryStore.self) private var library
    /// Der vollständige Katalog beider Quellen.
    let catalog: [CatalogItem]
    let loading: Bool
    let error: String?
    let reload: () async -> Void

    @State private var service = CatalogService()
    @State private var history = CatalogHistory()

    /// Was im Suchfeld steht.
    @State private var text = ""
    /// Wonach tatsächlich gesucht wird. Läuft dem Feld um die Entprellzeit
    /// hinterher — siehe `scheduleSearch`.
    @State private var committedText = ""
    @State private var quick: CatalogQuickFilter = .all
    @State private var filters: CatalogFilters = .none
    @State private var sort: CatalogSort = .popular

    /// Rasterdichte und der ausgeblendete Discovery-Bereich überleben den
    /// Programmlauf: Beides ist eine Einstellung und keine Momentaufnahme.
    @AppStorage("nori.catalog.density") private var density: CatalogDensity = .comfortable
    @AppStorage("nori.catalog.discovery.hidden") private var discoveryHidden = false

    @State private var showFilters = false
    /// Der zuletzt über „Titel entdecken" gezogene Titel.
    @State private var discovered: CatalogEntry?
    @State private var searchTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Alles, was die Ergebnisliste bestimmt — an einer Stelle, damit genau
    /// eine Beobachtung genügt.
    private var query: CatalogQuery {
        CatalogQuery(text: committedText, quick: quick, filters: filters, sort: sort)
    }

    var body: some View {
        GeometryReader { proxy in
            screen(width: proxy.size.width)
        }
        .background(NoriTheme.bg.ignoresSafeArea())
        .foregroundStyle(NoriTheme.fg)
        // Der Kopfbereich bringt Überschrift und Suche selbst mit; eine
        // zweite Leiste darüber wäre doppelt.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showFilters) { filterSheet }
        .navigationDestination(item: $discovered) { entry in
            SeriesView(slug: entry.slug, titleHint: entry.title, providerOverride: entry.provider)
        }
        .task(id: catalog.count) { await rebuild() }
        .onChange(of: text) { _, value in scheduleSearch(value) }
        .onChange(of: query) { _, value in service.apply(value) }
        .onChange(of: library.recents.count) { _, _ in syncHistory() }
        .onAppear { syncHistory() }
    }

    // MARK: - Aufbau

    private func screen(width: CGFloat) -> some View {
        let columns = density.columns(for: width)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                CatalogTitleBlock(history: history) { term in
                    text = term
                    committedText = term
                }
                .padding(.top, 6)
                .padding(.bottom, 16)

                Section {
                    content(columns: columns)
                } header: {
                    stickyHeader
                }
            }
            .padding(.bottom, CatalogMetrics.bottom)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .noriSoftScrollEdges()
        .refreshable { await refresh() }
    }

    /// Suche, Filterknopf und Schnellfilter — der Teil, der stehen bleibt.
    ///
    /// Die Überschrift scrollt bewusst weg: Auf einem iPhone sind Titel,
    /// Suche und Pillenreihe zusammen rund ein Viertel des Bildschirms, und
    /// das dauerhaft. Die Vorlage heftet den ganzen Kopf fest; hier bleibt
    /// das, was man beim Scrollen braucht — dieselbe Bewegung wie bei einem
    /// großen Systemtitel.
    private var stickyHeader: some View {
        VStack(spacing: 11) {
            CatalogSearchBar(
                text: $text,
                filtersActive: !filters.isEmpty,
                openFilters: { showFilters = true }
            )
            CatalogQuickFilterBar(
                filters: service.quickFilters,
                selected: quick,
                onSelect: select
            )
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
        .background { NoriTheme.bg }
        .overlay(alignment: .bottom) { headerFade }
    }

    /// Der weiche Abschluss unter der festgehefteten Leiste: ohne ihn
    /// schneidet sie durchlaufende Kacheln an einer scharfen Kante ab.
    private var headerFade: some View {
        LinearGradient(
            colors: [NoriTheme.bg, NoriTheme.bg.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 14)
        .offset(y: 14)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func content(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error {
                CatalogErrorBanner(text: error) { Task { await reload() } }
                    .padding(.top, 14)
                    .padding(.bottom, 6)
            }

            if !discoveryHidden {
                CatalogDiscovery(
                    count: service.results.count,
                    discover: discover,
                    hide: hideDiscovery
                )
                .padding(.top, 12)
                .padding(.bottom, 20)
            } else {
                Color.clear.frame(height: 12)
            }

            CatalogToolbar(
                headline: headline,
                count: service.results.count,
                sort: $sort,
                density: $density
            )
            .padding(.bottom, 12)

            CatalogActiveFilters(
                tags: CatalogFilterTag.all(filters, fullYearRange: service.facets.years),
                onRemove: { filters = $0.removed(from: filters) },
                onClear: { filters = .none }
            )
            .padding(.bottom, 12)

            results(columns: columns)
        }
    }

    @ViewBuilder
    private func results(columns: Int) -> some View {
        if service.results.isEmpty, isBusy {
            CatalogSkeleton(columns: columns, density: density)
        } else if service.results.isEmpty {
            CatalogEmptyState(
                hasQuery: !committedText.isEmpty,
                hasFilters: !filters.isEmpty || quick != .all,
                reset: resetAll
            )
        } else {
            CatalogGrid(
                entries: service.results,
                density: density,
                columns: columns,
                // Das Typ-Abzeichen trägt nur im gemischten Raster etwas bei.
                showsKind: filters.mediaType == nil && service.facets.mediaTypes.count > 1,
                highlighted: discovered?.id,
                now: Date()
            )
        }
    }

    private var isBusy: Bool {
        service.phase != .ready || (loading && catalog.isEmpty)
    }

    /// Die Überschrift über dem Raster.
    ///
    /// Sie benennt, wonach gerade gesehen wird — sonst steht „Alle Titel"
    /// über zweiundvierzig Fantasy-Serien.
    private var headline: String {
        if !committedText.isEmpty { return "Suchergebnisse" }
        if quick != .all { return quick.headline }
        if filters.genres.count == 1, let genre = filters.genres.first { return genre }
        if let mediaType = filters.mediaType { return mediaType.label }
        return "Alle Titel"
    }

    private var filterSheet: some View {
        CatalogFilterSheet(
            facets: service.facets,
            applied: filters,
            appliedSort: sort
        ) { nextFilters, nextSort in
            filters = nextFilters
            sort = nextSort
        }
    }

    // MARK: - Bedienung

    private func select(_ filter: CatalogQuickFilter) {
        withAnimation(NoriMotion.allowed(NoriMotion.micro, reduceMotion: reduceMotion)) {
            quick = filter
        }
        // „Beliebt" ohne Beliebtheitssortierung wäre eine Überschrift ohne
        // Deckung.
        if let implied = filter.impliedSort { sort = implied }
    }

    private func resetAll() {
        text = ""
        committedText = ""
        quick = .all
        filters = .none
        sort = .popular
    }

    private func hideDiscovery() {
        withAnimation(NoriMotion.allowed(NoriMotion.ui, reduceMotion: reduceMotion)) {
            discoveryHidden = true
        }
    }

    /// „Titel entdecken".
    ///
    /// Zieht aus der **aktuellen Ergebnismenge** und öffnet den Titel. Die
    /// Vorlage scrollt stattdessen zur Kachel; das geht hier nicht ehrlich:
    /// Das Raster baut aus gutem Grund nur die ersten Kacheln, und um zu
    /// einem zufälligen Platz unter zehntausend zu scrollen, müsste erst
    /// alles dazwischen gebaut werden. „Entdecken" heißt ohnehin, den Titel
    /// zu sehen zu bekommen — und nicht, ihn irgendwo im Raster zu suchen.
    private func discover() {
        var generator = SystemRandomNumberGenerator()
        let pick = CatalogEngine.discover(
            in: service.results,
            excluding: discovered?.id,
            using: &generator
        )
        guard let pick else { return }
        discovered = pick
    }

    // MARK: - Suche

    /// Eingabe entprellen.
    ///
    /// Ohne das liefe bei jedem Anschlag ein vollständiger Durchlauf über den
    /// Katalog. Die Aufgabe wird bei der nächsten Taste abgebrochen — es
    /// rechnet immer nur die letzte.
    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            committedText = ""
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            committedText = trimmed
            // Erst merken, wenn die Suche etwas getroffen hat. Ein Verlauf
            // aus Fehlschlägen hilft niemandem.
            if !service.results.isEmpty { history.remember(trimmed) }
        }
    }

    // MARK: - Daten

    private func rebuild(force: Bool = false) async {
        await service.load(items: catalog, local: localState, force: force)
        service.apply(query)
    }

    private func refresh() async {
        await reload()
        await rebuild(force: true)
    }

    /// Der lokale Stand als Kopie.
    ///
    /// Der Dienst bekommt Werte und keine Referenz auf den Store: läse er ihn
    /// selbst, würde jeder Tick des laufenden Players den ganzen Katalog neu
    /// bauen.
    private var localState: CatalogService.LocalState {
        CatalogService.LocalState(progress: Array(library.progress.values))
    }

    /// Die zuletzt geöffneten Titel für den Verlaufsknopf.
    ///
    /// Aus `LibraryStore.recents`, das die Detailseite beim Öffnen füllt —
    /// nichts, was der Katalog selbst erfindet.
    private func syncHistory() {
        history.opened = Array(
            library.recents
                .sorted { $0.viewedAt > $1.viewedAt }
                .map(\.title)
                .prefix(6)
        )
    }
}
