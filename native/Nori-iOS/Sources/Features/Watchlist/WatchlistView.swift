import SwiftUI

/// Noris Merkliste.
///
/// Aufbau: ein feststehender Kopfbereich — Eyebrow, Titel, Anzahl, Suche,
/// Filterknopf, Schnellfilter —, darunter ein durchgehender Lauf aus
/// Zusammenfassung, Ergebniszeile und den Titeln als Raster oder Liste.
///
/// ## Was diese Ansicht ersetzt
///
/// Die vorherige Merkliste war eine `List` mit zwei Abschnitten „Anime" und
/// „Serien", 44 Punkte breiten Bildchen und einem Quellenumschalter in der
/// Navigationsleiste. Sie beantwortete damit die Frage, die man selten hat
/// (welcher Medientyp), und keine der Fragen, die man ständig hat: was habe
/// ich angefangen, was steht noch aus, wie weit bin ich. Davon ist nichts
/// übernommen; die Vorlage ist `nori-watchlist-v3.html`.
///
/// Was **geblieben** ist, ist alles, was funktioniert hat: `LibraryStore`
/// als einzige Quelle dafür, was gemerkt ist, `WatchProgress` für den Stand,
/// `PosterTile` für die Bildkette samt TMDB, und `SeriesView` als Ziel eines
/// Tipps.
///
/// ## Was sie nicht rechnet
///
/// Nichts. Status, Filterung und Sortierung stehen in `WatchlistModel.swift`
/// im gemeinsamen Kern, der Zustand in `WatchlistViewModel`. Diese Datei
/// setzt zusammen und zeichnet.
struct WatchlistView: View {
    @Environment(LibraryStore.self) private var library
    /// Der Katalog liefert Genres und Alternativtitel. Er entscheidet
    /// **nicht**, was in der Merkliste steht — das tut allein `favorites`.
    let catalog: [CatalogItem]
    /// Wechselt in den Katalog-Tab. Für den leeren Zustand.
    var openCatalog: (() -> Void)?

    @State private var model = WatchlistViewModel()
    @State private var showingFilters = false
    /// Der zuletzt entfernte Titel, solange „Rückgängig" noch steht.
    @State private var undo: LibraryStore.FavoriteSnapshot?
    /// Blendet den Rückgängig-Streifen nach einer Weile wieder aus.
    @State private var undoTicket = 0
    /// Der Titel, dessen Detailseite die Liste gerade öffnet. Im Raster
    /// übernimmt das `NoriSeriesLink` selbst.
    @State private var open: WatchlistItem?

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NoriScreen {
            VStack(spacing: 0) {
                WatchlistHeaderView(
                    query: $model.query,
                    quick: $model.quick,
                    shownCount: model.results.count,
                    filtersActive: model.filters.isActive,
                    openFilters: { showingFilters = true }
                )
                .zIndex(1)

                content
            }
        }
        // Der Kopfbereich bringt Titel und Suche selbst mit; eine
        // Navigationsleiste darüber wäre dieselbe Überschrift ein zweites
        // Mal, in kleiner.
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { undoBar }
        .navigationDestination(item: $open) { item in
            SeriesView(slug: item.slug, titleHint: item.title, providerOverride: item.provider)
        }
        .sheet(isPresented: $showingFilters) {
            WatchlistFilterSheet(
                filters: $model.filters,
                genres: model.genres,
                preview: { model.preview($0) }
            )
        }
        // Läuft, wenn sich am Bestand etwas geändert hat — nicht bei jedem
        // Neuzeichnen. Der Schlüssel deckt Merkliste, Fortschritt und
        // Katalog ab.
        .task(id: sourceKey) {
            model.rebuild(library: library, catalog: catalog)
        }
        .task(id: model.query) {
            await model.settleQuery()
        }
    }

    // MARK: - Inhalt

    /// Raster und Liste haben bewusst **verschiedene** Behälter.
    ///
    /// Das Raster liegt in einem `ScrollView`, die Liste in einer `List`.
    /// Grund ist die Wischgeste: `swipeActions` gibt es nur in einer `List`,
    /// und sie von Hand nachzubauen hieße, mit dem Scrollen um jede
    /// Fingerbewegung zu streiten. Im Raster gäbe es ohnehin keine Richtung
    /// zum Wischen — dort führt das Kontextmenü zum selben Ziel.
    ///
    /// Zusammenfassung und Ergebniszeile stehen in beiden Fällen im
    /// scrollenden Inhalt, nicht im festen Kopfbereich: sie beschreiben, was
    /// darunter kommt, und sollen mit weglaufen.
    @ViewBuilder
    private var content: some View {
        // Beim Wechsel des Ausschnitts zurück nach oben.
        //
        // Ohne das bleibt die Ansicht stehen, wo sie war: wer bei Titel
        // sieben „Gesehen" antippt und nur noch zwei Treffer hat, sieht
        // danach einen leeren Bereich und hält die Liste für kaputt. Die
        // Ergebniszeile darüber sagt, was gerade gilt — sie muss dafür im
        // Bild sein.
        ScrollViewReader { scroll in
            Group {
                if model.mode == .grid {
                    gridScroll
                } else {
                    listScroll
                }
            }
            .onChange(of: scrollResetKey) {
                withAnimation(NoriMotion.ui) {
                    scroll.scrollTo(Self.topAnchor, anchor: .top)
                }
            }
        }
    }

    /// Woran die Ansicht merkt, dass ein anderer Ausschnitt gilt. Die
    /// Sortierung gehört dazu — sie stellt die Liste um, und der erste
    /// Treffer ist danach ein anderer.
    private var scrollResetKey: String {
        "\(model.quick.rawValue)|\(model.appliedQuery)|\(model.filters)"
    }

    /// Marke am oberen Ende beider Ansichten.
    private static let topAnchor = "nori.watchlist.top"

    private var gridScroll: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    listingHeader
                        .id(Self.topAnchor)

                    if model.results.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(
                            columns: WatchlistMetrics.grid(width: proxy.size.width, regular: sizeClass == .regular),
                            spacing: WatchlistMetrics.rowGap
                        ) {
                            ForEach(model.results) { item in
                                link(item, scaleOnPress: true) {
                                    WatchlistPosterCard(item: item)
                                }
                            }
                        }
                        .padding(.horizontal, WatchlistMetrics.screen)
                    }
                }
                .padding(.bottom, WatchlistMetrics.bottom)
                .noriAnimation(NoriMotion.ui, value: model.results.map(\.id))
            }
            .scrollIndicators(.hidden)
            .noriSoftScrollEdges()
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var listScroll: some View {
        List {
            listingHeader
                .id(Self.topAnchor)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if model.results.isEmpty {
                emptyState
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(model.results) { item in
                    // In der Liste ein Knopf statt `NoriSeriesLink`.
                    //
                    // Ein `NavigationLink` in einer `List` bekommt vom System
                    // einen eigenen Pfeil, und der steht **außerhalb** der
                    // Karte, weil die ihren eigenen Grund mitbringt. Neben dem
                    // Pfeil der Zeile sähe das nach zwei Zeilen aus. Das Ziel
                    // ist dasselbe: `navigationDestination` unten öffnet
                    // dieselbe `SeriesView`.
                    Button { open = item } label: {
                        WatchlistListRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { remove(item) } label: {
                            Label("Aus Merkliste entfernen", systemImage: "bookmark.slash")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4.5, leading: WatchlistMetrics.screen, bottom: 4.5, trailing: WatchlistMetrics.screen))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { remove(item) } label: {
                            Label("Entfernen", systemImage: "bookmark.slash")
                        }
                    }
                }
            }

            Color.clear
                .frame(height: WatchlistMetrics.bottom)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .noriSoftScrollEdges()
        .scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 0)
    }

    /// Zusammenfassung und Ergebniszeile — in beiden Ansichten dieselben.
    private var listingHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            WatchlistSummaryView(stats: model.stats)
                .padding(.top, 5)
                .padding(.bottom, 22)

            WatchlistToolbarView(
                headline: model.quick.headline,
                count: model.results.count,
                sort: $model.filters.sort,
                mode: $model.mode
            )
            .padding(.bottom, 13)
        }
        .padding(.horizontal, WatchlistMetrics.screen)
    }

    private var emptyState: some View {
        WatchlistEmptyState(
            reason: model.isEmpty ? .nothingSaved : .noMatches,
            openCatalog: model.isEmpty ? openCatalog : nil,
            clearFilters: model.isEmpty ? nil : { model.clearNarrowing() }
        )
    }

    /// Ein Eintrag als Verweis auf die Detailseite.
    ///
    /// `NoriSeriesLink` führt auf dieselbe `SeriesView` wie Startseite,
    /// Katalog und Kalender — samt Zoom-Übergang und Zeigerrückmeldung. Dort
    /// sieht der bestehende `WatchProgress` aus, wie er soll, und „Weiter
    /// ansehen" entsteht aus `LibraryStore.nextPlay`. Die Merkliste baut
    /// dafür nichts Eigenes; eine zweite Fortsetzungsregel wäre eine, die
    /// irgendwann eine andere Folge nennt als die Detailseite.
    ///
    /// Das eingebaute Kontextmenü ist abgeschaltet: hier heißt der Eintrag
    /// „Aus Merkliste entfernen" und läuft über `removeFavorite`, damit es
    /// danach etwas zurückzunehmen gibt.
    private func link<Content: View>(
        _ item: WatchlistItem,
        scaleOnPress: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        NoriSeriesLink(
            slug: item.slug,
            titleHint: item.title,
            scaleOnPress: scaleOnPress,
            provider: item.provider,
            showsDefaultMenu: false,
            label: content
        )
        .contextMenu {
            Button(role: .destructive) { remove(item) } label: {
                Label("Aus Merkliste entfernen", systemImage: "bookmark.slash")
            }
        }
    }

    // MARK: - Entfernen und zurücknehmen

    /// Aus der Merkliste nehmen.
    ///
    /// Ausdrücklich nur aus der Merkliste: `removeFavorite` rührt
    /// `progress` und `recents` nicht an. Wer einen Titel entfernt, wollte
    /// ihn nicht mehr in der Liste sehen — er wollte nicht vergessen, wo er
    /// stehen geblieben ist. Legt er ihn zurück, steht der Stand noch da.
    private func remove(_ item: WatchlistItem) {
        guard let snapshot = library.removeFavorite(item.slug) else { return }
        model.remove(item.id)
        withAnimation(NoriMotion.ui) { undo = snapshot }
        undoTicket &+= 1
        let ticket = undoTicket
        Task {
            try? await Task.sleep(for: .seconds(6))
            guard ticket == undoTicket else { return }
            withAnimation(NoriMotion.ui) { undo = nil }
        }
    }

    private func restore() {
        guard let snapshot = undo else { return }
        library.restoreFavorite(snapshot)
        undoTicket &+= 1
        withAnimation(NoriMotion.ui) { undo = nil }
        model.rebuild(library: library, catalog: catalog)
    }

    @ViewBuilder
    private var undoBar: some View {
        if let undo {
            HStack(spacing: 12) {
                Text("\u{201E}\(library.titles[undo.slug] ?? undo.slug)\u{201C} entfernt")
                    .font(.footnote)
                    .foregroundStyle(NoriTheme.fg)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button("Rückgängig", action: restore)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(NoriTheme.accent)
            }
            .padding(.horizontal, 16)
            .frame(height: NoriControl.hit)
            .background(NoriTheme.elevated, in: Capsule())
            .overlay { Capsule().strokeBorder(NoriTheme.border) }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            .padding(.horizontal, WatchlistMetrics.screen)
            // Über der Tab-Leiste, nicht dahinter.
            //
            // Die Leiste schwebt über dem Inhalt und liegt innerhalb der
            // Sicherheitszone; ein Überzug am unteren Rand landet sonst
            // darunter. Er war dort nicht nur halb verdeckt, sondern
            // unerreichbar — der Tipp auf „Rückgängig" ging an die Leiste.
            .padding(.bottom, WatchlistMetrics.undoLift)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Daten

    /// Woran die Ansicht merkt, dass die Merkliste neu zusammenzustellen ist.
    ///
    /// Der jüngste Fortschrittszeitpunkt gehört dazu, die Anzahl allein
    /// reichte nicht: kommt jemand aus dem Player zurück, ist dieselbe Folge
    /// weiter fortgeschritten, ohne dass ein Eintrag hinzugekommen wäre. Die
    /// Position selbst steht bewusst **nicht** im Schlüssel — sie ändert sich
    /// im Sekundentakt.
    private var sourceKey: String {
        let latest = library.progress.values.map(\.updatedAt).max() ?? 0
        return "\(library.favorites.count)|\(library.progress.count)|\(latest)|\(catalog.count)"
    }
}
