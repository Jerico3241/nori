import SwiftUI

/// Umschalter für den Bereich der Bibliothek.
///
/// Hieß einmal `KindSwitch` und schaltete zwischen zwei Quellen um. Seit es
/// `LibraryScope` gibt, wählt er einen **Ausschnitt**: „Alle", „Anime",
/// „Serien" oder „K-Drama". Die Quelle entscheidet weiter, wohin ein
/// einzelner Titel führt — nur nicht mehr, was in den Listen steht.
///
/// ## Warum ein Menü und kein segmentierter Regler
///
/// Auf dem Mac sitzt derselbe Umschalter als segmentierter `Picker` in der
/// Seitenleiste, wo Platz ist. In einer iPhone-Navigationsleiste sind vier
/// Segmente zu viel: „K-Drama" allein braucht mehr Breite als die beiden
/// alten Segmente zusammen, und mit Dynamic Type wird daraus Gedränge oder
/// abgeschnittener Text. Ein Menü zeigt stattdessen den aktuellen Bereich und
/// bleibt gleich breit, egal wie viele Bereiche dazukommen.
struct ScopeSwitch: View {
    @Binding var scope: LibraryScope

    var body: some View {
        Menu {
            Picker("Bereich", selection: $scope) {
                ForEach(LibraryScope.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(scope.label, systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.titleAndIcon)
        }
        .accessibilityLabel("Bereich: \(scope.label)")
    }
}

/// Die Bereiche als Pillenreihe.
///
/// Auf der Startseite steht der Umschalter direkt im Inhalt statt in der
/// Navigationsleiste: dort ist er sichtbar, ohne dass man ihn suchen muss,
/// und er hat Platz für vier Beschriftungen. In den übrigen Tabs bleibt es
/// beim Menü in der Leiste — dort wäre eine Pillenreihe über jeder Ansicht
/// nur Wiederholung.
///
/// Die Pillen sind aus Glas: sie liegen dicht unter dem Kopfbereich und
/// gehören zur Bedienung, nicht zum Inhalt. Der aktive Bereich bleibt
/// bewusst eine gefüllte Fläche — Glas gegen Glas ließe sich nicht
/// unterscheiden.
struct ScopeChips: View {
    @Binding var scope: LibraryScope
    @AppStorage(NoriGlassSetting.key) private var glass = true
    @Namespace private var pill

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(LibraryScope.allCases) { item in
                    let active = item == scope
                    Button {
                        scope = item
                    } label: {
                        Text(item.label)
                            .font(.subheadline.weight(active ? .bold : .medium))
                            .foregroundStyle(active ? NoriTheme.bg : NoriTheme.fg)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background {
                                if active {
                                    Capsule().fill(NoriTheme.fg)
                                }
                            }
                            .noriGlass(
                                Capsule(),
                                enabled: glass && !active,
                                off: active ? AnyShapeStyle(.clear) : AnyShapeStyle(NoriTheme.elevated)
                            )
                    }
                    .buttonStyle(NoriPressStyle())
                    .accessibilityAddTraits(active ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, NoriSpacing.screen)
        }
        .scrollClipDisabled()
        .noriAnimation(NoriMotion.ui, value: scope)
    }
}

struct GenreRow: Identifiable, Hashable {
    let title: String
    let items: [CatalogItem]
    var id: String { title }
}

/// Ein Titel im Kopfbereich.
struct HeroItem: Identifiable, Hashable {
    let slug: String
    let title: String
    let kind: CatalogProvider
    let genres: [String]
    var id: String { "\(kind.rawValue)|\(slug)" }
}

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]
    let loading: Bool
    let error: String?
    let reload: () async -> Void

    @State private var genreRows: [GenreRow] = []
    @State private var heroItems: [HeroItem] = []
    /// Läuft eine Folge, die direkt aus „Schau weiter" gestartet wurde.
    @State private var play: SeriesView.PlayTarget?
    /// Der Folgenpfad, dessen Serie gerade geladen wird — die Kachel zeigt
    /// so lange einen Fortschrittsring. Ohne das wirkt das Antippen tot: die
    /// Detailseite muss erst geholt werden, bevor klar ist, welche Folge
    /// überhaupt läuft.
    @State private var preparing: String?
    /// Fehler der Direktwiedergabe. Getrennt von `error`, das von außen kommt
    /// und den Katalog betrifft.
    @State private var playError: String?

    var body: some View {
        NoriScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: NoriSpacing.section) {
                    hero

                    ScopeChips(scope: Bindable(library).scope)

                    if let error {
                        errorBanner(error)
                            .padding(.horizontal, NoriSpacing.screen)
                    }

                    continueSection

                    if !catalog.isEmpty {
                        PosterRow(title: "Beliebte Titel") {
                            ForEach(catalog.prefix(20)) { item in
                                catalogCard(item)
                            }
                        }
                    }

                    ForEach(genreRows) { row in
                        PosterRow(title: row.title) {
                            ForEach(row.items) { item in
                                catalogCard(item)
                            }
                        }
                    }
                }
                .padding(.bottom, 28)
            }
            .coordinateSpace(name: HeroCarousel.scrollSpace)
            .noriSoftScrollEdges()
            // Nur der Kopfbereich darf unter die Statusleiste — das ist sein
            // Sinn. Gibt es keinen, bliebe sonst die erste Reihe unter der
            // Uhr stehen.
            .ignoresSafeArea(edges: heroItems.isEmpty ? [] : .top)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $play) { target in
            PlayerScreen(
                series: target.series,
                episode: target.episode,
                season: target.series.activeSeason,
                resumeAt: target.resumeAt,
                provider: target.provider
            )
        }
        .task(id: rowsKey) {
            genreRows = Self.buildRows(from: catalog)
            heroItems = buildHero()
        }
    }

    @ViewBuilder
    private var hero: some View {
        if !heroItems.isEmpty {
            HeroCarousel(items: heroItems)
        } else if loading && catalog.isEmpty {
            ProgressView("Nori wird geladen")
                .frame(maxWidth: .infinity, minHeight: 260)
        }
    }

    /// Aus „Schau weiter" heraus direkt abspielen.
    ///
    /// Welche Folge, entscheidet `nextPlay` im Kern: die zuletzt angefangene,
    /// solange sie nicht zu Ende gesehen ist — sonst die nächste unfertige.
    /// Genau deshalb muss die Detailseite vorher geholt werden: ohne die
    /// Folgenliste ist „die nächste" nicht bestimmbar.
    ///
    /// Die Quelle wird ausdrücklich mitgegeben. Ohne sie nähme `nextPlay` die
    /// Vorgabequelle, und die passt bei einer gemeinsamen Bibliothek regelmäßig
    /// nicht zum angetippten Titel.
    private func resume(_ item: WatchProgress) async {
        let source = item.provider ?? providerFromPath(item.episodePath)
        preparing = item.episodePath
        playError = nil
        defer { preparing = nil }
        do {
            let detail = try await AniworldClient.shared.getSeries(
                provider: source,
                slug: item.slug,
                season: item.season
            )
            let target = library.nextPlay(
                slug: item.slug,
                season: item.season,
                episodes: detail.episodes,
                source: source
            )
            guard let episode = detail.episodes.first(where: { $0.number == target.episode }) else {
                playError = "Folge \(target.episode) ist in dieser Staffel nicht mehr eingetragen."
                return
            }
            play = SeriesView.PlayTarget(
                series: detail,
                episode: episode,
                resumeAt: library.resumeEnabled ? target.resumeAt : 0,
                provider: source
            )
        } catch {
            playError = error.localizedDescription
        }
    }

    /// Die Weiterschauen-Zeile als eigene Teilansicht.
    ///
    /// Ausgelagert, weil der Typechecker beim Aufbau als Ganzes aufgab:
    /// `failed to produce diagnostic for expression` — die Variante von
    /// `unable to type-check this expression in reasonable time`, bei der
    /// nicht einmal mehr eine brauchbare Meldung herauskommt. Jede weitere
    /// Verschachtelung im `LazyVStack` kostet den Prüfer überproportional
    /// viel; kleine Teilansichten kosten nichts.
    /// Ausserhalb des ViewBuilders berechnet: eine `let`-Bindung im Builder
    /// selbst hat den Typechecker erneut aussteigen lassen.
    private var watching: [WatchProgress] { library.continueWatching() }

    @ViewBuilder
    private var continueSection: some View {
        if !watching.isEmpty {
            PosterRow(title: "Schau weiter") {
                ForEach(watching) { item in
                    continueButton(item)
                }
            }
        }
        if let playError {
            Text(playError)
                .font(.footnote)
                .foregroundStyle(Color.red)
                .padding(.horizontal, NoriSpacing.screen)
        }
    }

    private func continueButton(_ item: WatchProgress) -> some View {
        Button {
            Task { await resume(item) }
        } label: {
            ContinueCard(item: item)
                .overlay { preparingVeil(for: item) }
        }
        .buttonStyle(NoriPressStyle(scale: 0.97))
        .accessibilityLabel(item.title + " weiterschauen")
    }

    /// Der Schleier, solange die Serie geholt wird. Ohne ihn wirkt das
    /// Antippen tot: bis feststeht, welche Folge laeuft, muss erst die
    /// Detailseite da sein.
    @ViewBuilder
    private func preparingVeil(for item: WatchProgress) -> some View {
        if preparing == item.episodePath {
            ZStack {
                Color.black.opacity(0.45)
                ProgressView().tint(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: NoriRadius.small, style: .continuous))
            .transition(.opacity)
        }
    }

    private func errorBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.subheadline).foregroundStyle(.red)
            Button("Erneut laden") { Task { await reload() } }
                .buttonStyle(.bordered)
        }
    }

    private func catalogCard(_ item: CatalogItem) -> some View {
        NoriSeriesLink(
            slug: item.slug,
            titleHint: item.title,
            scaleOnPress: true,
            provider: item.provider
        ) {
            CatalogCard(item: item)
        }
    }

    /// Neu gruppieren, wenn sich Quelle oder Katalogumfang ändert. Ein
    /// `onChange` auf dem Array selbst würde bei jedem Rendern tausende
    /// Einträge vergleichen.
    private var rowsKey: String {
        "\(library.scope.rawValue)|\(catalog.count)"
    }

    private func buildHero() -> [HeroItem] {
        // Titel ohne Genre sagen im Kopfbereich nichts aus; nur wenn zu wenige
        // mit Genre da sind, wird der ganze Katalog genommen.
        let described = catalog.filter { !$0.genres.isEmpty }
        let source = described.count >= 6 ? described : catalog
        guard !source.isEmpty else { return [] }

        // Ohne das stünden dort immer dieselben fünf Titel vom Anfang des
        // Alphabets. Der Tag geht in die Reihenfolge ein, innerhalb eines Tages
        // bleibt sie gleich.
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        return source
            .sorted { Self.featureRank($0.slug, day: day) < Self.featureRank($1.slug, day: day) }
            .prefix(5)
            .map {
                HeroItem(
                    slug: $0.slug,
                    title: $0.title,
                    kind: $0.provider ?? library.provider,
                    genres: $0.genres
                )
            }
    }

    /// `hashValue` ist pro Prozess anders gesalzen — die Reihenfolge wechselte
    /// damit bei jedem Start der App. Diese Streuung ist es nicht.
    static func featureRank(_ slug: String, day: Int) -> Int {
        var acc = day &* 2_654_435_761
        for scalar in slug.unicodeScalars {
            acc = (acc &* 31 &+ Int(scalar.value)) % 1_000_003
        }
        return acc < 0 ? -acc : acc
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

        // Über die Kennung entdoppeln, nicht über den Slug: beide Quellen
        // können denselben Slug führen.
        var used: Set<String> = []
        var rows: [GenreRow] = []
        for genre in top {
            let items = catalog
                .filter { $0.genres.contains(genre) && !used.contains($0.id) }
                .prefix(18)
                .map { $0 }
            guard items.count >= 6 else { continue }
            used.formUnion(items.map(\.id))
            rows.append(GenreRow(title: genre, items: items))
        }
        return rows
    }
}

// MARK: - Kopfbereich

/// Die Höhe des Kopfbereichs beim Herunterziehen — gemessen im Scrollraum
/// der Startseite.
private struct HeroStretch: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Vollflächiger Kopfbereich mit Seitenpunkten.
///
/// `TabView` im Seitenstil bringt Wischen mit; von Hand nachgebaut wäre es
/// schlechter. Die Punkte kommen von Nori, weil die des `TabView` auf dem
/// Bild liegen und sich nicht bewegen lassen.
///
/// Zwei Bewegungen liegen darauf:
///
/// - **Parallaxe** beim Blättern. Das Bild ist breiter als die Seite und
///   wandert langsamer als sie; dadurch entsteht Tiefe, statt dass ein
///   Bildschirm gegen den nächsten geschoben wird.
/// - **Dehnung** beim Herunterziehen. Nur die Darstellung wird gedehnt,
///   nicht der Platz: die Größe im Layout bleibt gleich, sonst käme das
///   Nachfedern des Scrollbereichs durcheinander.
///
/// Beides fällt bei „Bewegung reduzieren" weg. Der Kopfbereich bleibt dann
/// stehen, alles andere funktioniert unverändert.
struct HeroCarousel: View {
    static let scrollSpace = "noriHomeScroll"

    let items: [HeroItem]

    @State private var current: String = ""
    @State private var stretch: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var index: Int {
        items.firstIndex { $0.id == current } ?? 0
    }

    var body: some View {
        GeometryReader { outer in
            let width = outer.size.width
            let height = Self.height(for: outer.size, regular: sizeClass == .regular)

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    // Der Messfühler liegt neben dem TabView, nicht darin:
                    // eine Neubewertung darf nicht in dessen Layout
                    // durchschlagen. `max(0, …)` heißt, dass sich der Wert
                    // beim normalen Scrollen gar nicht ändert.
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: HeroStretch.self,
                            value: max(0, proxy.frame(in: .named(HeroCarousel.scrollSpace)).minY)
                        )
                    }

                    TabView(selection: $current) {
                        ForEach(items) { item in
                            HeroSlide(item: item, parallax: !reduceMotion)
                                .tag(item.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(width: width, height: height)

                    NoriPageIndicator(count: items.count, current: index)
                        .padding(.bottom, 14)
                }
                .frame(width: width, height: height)
                .clipped()
                // Reine Darstellungsänderung: die Größe im Layout bleibt,
                // damit das Nachfedern des Scrollbereichs unangetastet ist.
                // `scaleEffect` vom oberen Rand aus vergrößert, `offset`
                // hebt die Verschiebung durch das Nachfedern wieder auf, damit
                // die Oberkante am Bildschirmrand stehen bleibt.
                .scaleEffect(reduceMotion ? 1 : 1 + stretch / max(height, 1), anchor: .top)
                .offset(y: reduceMotion ? 0 : -stretch)
            }
            .frame(width: width, height: height)
        }
        .frame(height: Self.height(for: nil, regular: sizeClass == .regular))
        .onPreferenceChange(HeroStretch.self) { value in stretch = value }
        .task(id: items.first?.id) {
            // Ohne gesetzte Auswahl zeigt das TabView bei einer Auswahl, die
            // zu keiner Seite gehört, eine leere Fläche.
            if !items.contains(where: { $0.id == current }) {
                current = items.first?.id ?? ""
            }
        }
    }

    /// Wie hoch der Kopfbereich wird.
    ///
    /// Drei Fälle, und der dritte ist der, an dem eine feste Zahl scheitert:
    ///
    /// - **iPad und breite Fenster:** die Breite entscheidet, 16:9 ist die
    ///   richtige Form. Gedeckelt, damit der Kopfbereich auf einem großen
    ///   Bildschirm nicht das ganze Fenster einnimmt.
    /// - **iPhone hochkant:** gut die Hälfte des Bildschirms — hoch genug,
    ///   dass ein Breitbild wirkt, niedrig genug, dass die erste Reihe
    ///   darunter angeschnitten zu sehen ist und klar wird, dass es
    ///   weitergeht.
    /// - **iPhone quer:** hier sind es nur rund 400 Punkte Höhe insgesamt.
    ///   Ein Kopfbereich nach der Hochkantregel füllte den Bildschirm
    ///   vollständig aus, und die Startseite sah aus wie ein einzelnes Bild.
    static func height(for size: CGSize?, regular: Bool) -> CGFloat {
        let screen = NoriScreenMetrics.size
        let width = size?.width ?? screen.width
        let wide = width * 9 / 16
        if regular { return min(wide, screen.height * 0.6) }
        if screen.height < 520 { return min(wide, screen.height * 0.76) }
        return min(max(screen.height * 0.54, 380), 560)
    }
}

/// Eine Seite des Kopfbereichs: Breitbild, Verlauf, Schriftzug, Genres,
/// zwei Knöpfe.
struct HeroSlide: View {
    let item: HeroItem
    var parallax: Bool = true

    @Environment(LibraryStore.self) private var library
    @State private var details = CoverDetails(poster: nil, backdrop: nil, overview: nil, rating: nil)
    @State private var logo: URL?

    var body: some View {
        ZStack(alignment: .bottom) {
            backdrop
            // Der Verlauf läuft in die Hintergrundfarbe aus, nicht nach
            // Schwarz: der Kopfbereich soll in die Seite übergehen, nicht auf
            // ihr liegen.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: NoriTheme.bg.opacity(0.35), location: 0.42),
                    .init(color: NoriTheme.bg.opacity(0.86), location: 0.72),
                    .init(color: NoriTheme.bg, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            caption
        }
        .task(id: item.slug) {
            details = await CoverIndex.shared.detailsLoading(
                slug: item.slug,
                title: item.title,
                kind: item.kind
            )
            // Ohne TMDB-Treffer hätte der Kopfbereich weder Breitbild noch
            // Poster und bliebe schwarz. Das Cover der Quelle steht nur auf
            // der Detailseite; die Kacheln holen es sich längst so.
            if details.backdrop == nil, details.poster == nil {
                details.poster = await CoverIndex.shared.fetchSourceCover(
                    slug: item.slug,
                    provider: item.kind
                )
            }
            logo = await CoverIndex.shared.logoLoading(
                slug: item.slug,
                title: item.title,
                alternates: [],
                kind: item.kind
            )
        }
    }

    /// Das Bild, breiter als die Seite und langsamer als sie.
    ///
    /// Der Versatz kommt aus der Lage der Seite im Bildschirm: beim Blättern
    /// wandert `minX` von der vollen Breite auf null, der Bildversatz mit
    /// einem Viertel davon. Der Überstand verhindert, dass dabei eine Kante
    /// sichtbar wird.
    private var backdrop: some View {
        GeometryReader { geo in
            let overshoot: CGFloat = parallax ? 90 : 0
            let shift = parallax ? -(overshoot / 2) - geo.frame(in: .global).minX * 0.22 : 0

            Group {
                if let url = details.backdrop ?? details.poster {
                    NoriCoverImage(url: url, referer: item.kind.origin + "/") {
                        NoriTheme.elevated
                    }
                } else {
                    NoriTheme.elevated
                }
            }
            .frame(width: geo.size.width + overshoot, height: geo.size.height)
            .offset(x: shift)
        }
        .clipped()
    }

    /// Schriftzug, Genres, Knöpfe.
    private var caption: some View {
        VStack(spacing: 12) {
            titleArt

            if !item.genres.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.genres.prefix(3), id: \.self) { genre in
                        Text(genre)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(NoriTheme.fg.opacity(0.9))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.14)))
                            .overlay { Capsule().strokeBorder(.white.opacity(0.18)) }
                    }
                }
            }

            HStack(spacing: 10) {
                NoriSeriesLink(
                    slug: item.slug,
                    titleHint: item.title,
                    scaleOnPress: true,
                    provider: item.kind
                ) {
                    Label("Ansehen", systemImage: "play.fill")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(NoriTheme.bg)
                        .padding(.horizontal, 26)
                        .frame(height: NoriControl.hit)
                        .background(Capsule().fill(NoriTheme.fg))
                }

                BookmarkChip(slug: item.slug, title: item.title)
            }
        }
        .padding(.horizontal, NoriSpacing.screen)
        // Platz für die Seitenpunkte darunter.
        .padding(.bottom, 40)
    }

    /// Der Schriftzug — das TMDB-Logo, sonst der Titel als Text.
    ///
    /// Der Rückfall ist der Normalfall, nicht die Ausnahme: viele Serien
    /// haben bei TMDB gar kein Logo, und für die darf der Kopfbereich nicht
    /// namenlos bleiben.
    @ViewBuilder
    private var titleArt: some View {
        if let logo {
            // `AsyncImage` und nicht `NoriCoverImage`: letzteres zeichnet
            // immer mit `scaledToFill`, was ein Cover füllen soll — ein
            // freigestellter Schriftzug würde dabei beschnitten. Und TMDB
            // braucht keinen Referer, anders als die Bilder der Quellen.
            AsyncImage(url: logo) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            .frame(maxWidth: 280, maxHeight: 88)
            .accessibilityLabel(item.title)
        } else {
            Text(item.title)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                .frame(maxWidth: 320)
        }
    }
}

/// Merken oder vergessen — der zweite Knopf im Kopfbereich.
///
/// Eigene Ansicht, damit nur dieser Knopf neu zeichnet, wenn sich die
/// Merkliste ändert, und nicht der ganze Kopfbereich mitsamt Bild.
struct BookmarkChip: View {
    @Environment(LibraryStore.self) private var library
    let slug: String
    let title: String

    @AppStorage(NoriGlassSetting.key) private var glass = true

    var body: some View {
        let marked = library.isFavorite(slug)
        Button {
            library.toggleFavorite(slug, title: title)
        } label: {
            Image(systemName: marked ? "bookmark.fill" : "bookmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(NoriTheme.fg)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: NoriControl.hit, height: NoriControl.hit)
                .noriGlass(Circle(), enabled: glass, off: Color.white.opacity(0.16))
                .overlay { Circle().strokeBorder(.white.opacity(glass ? 0 : 0.18)) }
        }
        .buttonStyle(NoriPressStyle(scale: 0.92))
        .noriHaptic(.selection, trigger: marked)
        .accessibilityLabel(marked ? "Aus der Merkliste entfernen" : "Zur Merkliste hinzufügen")
    }
}

// MARK: - Zeilen

/// Eine waagerechte Zeile mit Überschrift — die Grundform der Startseite.
struct PosterRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NoriRowHeader(title)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: NoriSpacing.tile) {
                    content()
                }
                .padding(.horizontal, NoriSpacing.screen)
            }
            // Ohne das beschneidet der Scrollbereich den Schatten und die
            // gedrückte Kachel an seinen Rändern.
            .scrollClipDisabled()
        }
    }
}

/// Eine Kachel in einer Zeile der Startseite.
///
/// Der Titel steht **im** Bild, nicht darunter. Zwei Gründe: die Kacheln
/// bleiben dadurch alle gleich hoch — ein zweizeiliger Titel neben einem
/// einzeiligen verschob vorher die ganze Reihe —, und das Artwork bekommt
/// die volle Fläche.
struct CatalogCard: View {
    let item: CatalogItem

    static let width: CGFloat = 132
    static let wideWidth: CGFloat = 168

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        PosterTile(
            title: item.title,
            slug: item.slug,
            kind: item.provider,
            titleInImage: true
        )
        .frame(width: sizeClass == .regular ? Self.wideWidth : Self.width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
    }
}

struct ContinueCard: View {
    @Environment(LibraryStore.self) private var library
    let item: WatchProgress

    @State private var backdrop: URL?
    @State private var logo: URL?

    static let width: CGFloat = 232

    private var source: CatalogProvider {
        item.provider ?? providerFromPath(item.episodePath)
    }

    /// „Noch 21 Min." statt einer Prozentzahl.
    ///
    /// Die Restzeit sagt, worauf man sich einlässt; ein Prozentwert nicht.
    /// Fehlt die Dauer — etwa weil der Fortschritt aus einem älteren Stand
    /// stammt —, tritt Staffel und Folge an die Stelle.
    private var caption: String {
        let left = item.durationSec - item.positionSec
        guard item.durationSec > 0, left > 30 else {
            return "S\(item.season) · F\(item.episode)"
        }
        return "Noch \(Int(left / 60)) Min.  ·  S\(item.season) F\(item.episode)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    if let backdrop {
                        NoriCoverImage(url: backdrop, referer: source.origin + "/") {
                            NoriTheme.elevated
                        }
                    } else {
                        NoriTheme.elevated
                    }
                }
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .bottomLeading) { titleArt.padding(10) }
                // Ein Abspielzeichen: die Kachel startet als einzige auf der
                // Startseite unmittelbar die Wiedergabe, statt zur Serie zu
                // führen. Ohne Zeichen sieht sie aus wie jede andere.
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .black.opacity(0.35))
                        .padding(8)
                }
                .overlay(alignment: .bottom) {
                    // Der Fortschritt liegt **im** Bild, nicht darunter: so
                    // bleibt unter der Kachel Platz für die Restzeit, und die
                    // Kachel wird nicht höher als das Bild plus eine Zeile.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.25))
                            Rectangle()
                                .fill(NoriTheme.accent)
                                .frame(width: geo.size.width * watchRatio(item))
                        }
                    }
                    .frame(height: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: NoriRadius.small, style: .continuous))

            Text(caption)
                .font(.caption2)
                .foregroundStyle(NoriTheme.muted)
                .lineLimit(1)
        }
        .frame(width: Self.width, alignment: .leading)
        .task(id: item.slug) {
            let details = await CoverIndex.shared.detailsLoading(
                slug: item.slug,
                title: item.title,
                kind: source
            )
            backdrop = details.backdrop ?? details.poster
            logo = await CoverIndex.shared.logoLoading(
                slug: item.slug,
                title: item.title,
                kind: source
            )
        }
    }

    /// Schriftzug im Bild — Logo, sonst der Titel.
    @ViewBuilder
    private var titleArt: some View {
        if let logo {
            AsyncImage(url: logo) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            .frame(maxWidth: 130, maxHeight: 36, alignment: .bottomLeading)
            .accessibilityLabel(item.title)
        } else {
            Text(item.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
                .frame(maxWidth: 160, alignment: .leading)
        }
    }
}
