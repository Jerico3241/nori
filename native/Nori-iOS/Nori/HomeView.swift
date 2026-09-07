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

/// Die Bereiche als Pillenreihe über dem Inhalt.
///
/// Auf der Startseite steht der Umschalter direkt im Inhalt statt in der
/// Navigationsleiste: dort ist er sichtbar, ohne dass man ihn suchen muss,
/// und er hat Platz für vier Beschriftungen. In den übrigen Tabs bleibt es
/// beim Menü in der Leiste — dort wäre eine Pillenreihe über jeder Ansicht
/// nur Wiederholung.
struct ScopeChips: View {
    @Binding var scope: LibraryScope

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LibraryScope.allCases) { item in
                    let active = item == scope
                    Button {
                        scope = item
                    } label: {
                        Text(item.label)
                            .font(.subheadline.weight(active ? .bold : .medium))
                            .foregroundStyle(active ? NoriTheme.bg : NoriTheme.fg)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(active ? NoriTheme.fg : NoriTheme.elevated)
                            )
                            .overlay {
                                Capsule().strokeBorder(active ? .clear : NoriTheme.border)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 20)
        }
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
                LazyVStack(alignment: .leading, spacing: 26) {
                    ScopeChips(scope: Bindable(library).scope)
                        .padding(.top, 8)

                    if let error {
                        errorBanner(error)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }

                    if !heroItems.isEmpty {
                        HeroCarousel(items: heroItems)
                    } else if loading && catalog.isEmpty {
                        ProgressView("Nori wird geladen")
                            .frame(maxWidth: .infinity, minHeight: 260)
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
                .padding(.horizontal, 20)
        }
    }

    private func continueButton(_ item: WatchProgress) -> some View {
        Button {
            Task { await resume(item) }
        } label: {
            ContinueCard(item: item)
                .overlay { preparingVeil(for: item) }
        }
        .buttonStyle(.plain)
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

/// Vollflächiger Kopfbereich mit Seitenpunkten.
///
/// `TabView` im Seitenstil bringt Wischen und Punkte mit; von Hand nachgebaut
/// wäre beides schlechter. Die feste Höhe ist nötig, weil ein `TabView` in
/// einem `ScrollView` sonst keine bekommt und auf null zusammenfällt.
struct HeroCarousel: View {
    let items: [HeroItem]
    @State private var current: String = ""

    /// Bildkarte im Breitbild plus Zeile, Beschreibung und Knöpfe darunter.
    ///
    /// Früher standen hier 560 Punkte für ein hochkantes Poster. Seit das
    /// Backdrop trägt, ist die Karte bei rund 350 Punkten Breite nur noch
    /// etwa 197 Punkte hoch — der Rest ist Text, und die Startseite zeigt
    /// wieder mehr als nur den Kopfbereich.
    private var height: CGFloat { 430 }

    var body: some View {
        TabView(selection: $current) {
            ForEach(items) { item in
                HeroSlide(item: item).tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        .frame(height: height)
        .task(id: items.first?.id) {
            // Ohne gesetzte Auswahl zeigt das TabView bei einer Auswahl, die
            // zu keiner Seite gehört, eine leere Fläche.
            if !items.contains(where: { $0.id == current }) {
                current = items.first?.id ?? ""
            }
        }
    }
}

struct HeroSlide: View {
    @Environment(LibraryStore.self) private var library
    let item: HeroItem

    @State private var details = CoverDetails(poster: nil, backdrop: nil, overview: nil, rating: nil)
    @State private var logo: URL?

    private var progress: WatchProgress? {
        library.continueWatching().first { $0.slug == item.slug }
    }

    private var meta: String {
        var parts = [item.kind.label]
        parts.append(contentsOf: item.genres.prefix(3))
        return parts.joined(separator: " · ")
    }

    private var playLabel: String {
        progress == nil ? "Jetzt ansehen" : "Weiterschauen"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            banner
            Text(meta)
                .font(.caption)
                .foregroundStyle(NoriTheme.muted)
                .lineLimit(1)

            if let overview = details.overview, !overview.isEmpty {
                Text(overview)
                    .font(.footnote)
                    .foregroundStyle(NoriTheme.fg.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                NoriSeriesLink(
                    slug: item.slug,
                    titleHint: item.title,
                    provider: item.kind
                ) {
                    Label(playLabel, systemImage: "play.fill")
                        .font(.callout.weight(.bold))
                        // Der Akzent ist hell — Schrift darauf muss dunkel
                        // sein, sonst steht Weiß auf Weiß.
                        .foregroundStyle(NoriTheme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(NoriTheme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button {
                    library.toggleFavorite(item.slug, title: item.title)
                } label: {
                    Image(systemName: library.isFavorite(item.slug) ? "bookmark.fill" : "bookmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(NoriTheme.fg)
                        .frame(width: 48, height: 46)
                        .background(NoriTheme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(NoriTheme.border)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(library.isFavorite(item.slug) ? "Von der Merkliste nehmen" : "Auf die Merkliste")
            }
        }
        .padding(.horizontal, 20)
        // Platz für die Seitenpunkte des TabView, die sonst auf den Knöpfen
        // liegen.
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: item.slug) {
            details = await CoverIndex.shared.detailsLoading(
                slug: item.slug,
                title: item.title,
                kind: item.kind
            )
            // Ohne TMDB-Treffer hat `details` weder Breitbild noch Poster, und
            // der Kopfbereich bliebe schwarz. Das Cover der Quelle steht nur
            // auf der Detailseite; die Kacheln holen es sich längst so.
            if details.backdrop == nil, details.poster == nil {
                details.poster = await CoverIndex.shared.fetchSourceCover(
                    slug: item.slug,
                    provider: item.kind
                )
            }
            // Das Logo kostet einen eigenen Abruf und wird deshalb erst hier
            // geholt — nicht bei jeder Kachel im Katalog.
            logo = await CoverIndex.shared.logoLoading(
                slug: item.slug,
                title: item.title,
                alternates: [],
                kind: item.kind
            )
        }
    }

    /// Die Bildkarte: Breitbild, darüber unten links der Schriftzug.
    ///
    /// Anders als vorher trägt hier das **Backdrop** und nicht das Poster.
    /// Der Kopfbereich stand früher hochkant, wo ein 16:9-Bild nur einen
    /// schmalen Streifen aus der Mitte gezeigt hätte; jetzt ist die Fläche
    /// selbst 16:9, und das Poster wäre das falsche Format.
    private var banner: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let url = details.backdrop ?? details.poster {
                    NoriCoverImage(url: url, referer: item.kind.origin + "/") {
                        NoriTheme.elevated
                    }
                } else {
                    NoriTheme.elevated
                }
            }
            .overlay {
                // Trägt den Schriftzug unten. Ohne den Verlauf steht ein
                // weißes Logo auf einem womöglich hellen Bild.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.15), .black.opacity(0.75)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                titleArt.padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Der Schriftzug — das TMDB-Logo, sonst der Titel als Text.
    ///
    /// Der Rückfall ist der Normalfall, nicht die Ausnahme: viele Serien
    /// haben bei TMDB gar kein Logo, und für die soll der Kopfbereich nicht
    /// namenlos bleiben.
    @ViewBuilder
    private var titleArt: some View {
        if let logo {
            // `AsyncImage` und nicht `NoriCoverImage`: letzteres zeichnet
            // immer mit `scaledToFill`, was ein Cover füllen soll — ein
            // freigestellter Schriftzug würde dabei beschnitten. Und TMDB
            // braucht keinen Referer, anders als die Hoster-Bilder.
            AsyncImage(url: logo) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                EmptyView()
            }
            .frame(maxWidth: 210, maxHeight: 64, alignment: .bottomLeading)
            .accessibilityLabel(item.title)
        } else {
            Text(item.title)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                .frame(maxWidth: 260, alignment: .leading)
        }
    }
}

// MARK: - Zeilen

/// Eine waagerechte Zeile mit Überschrift — die Grundform der Startseite.
struct PosterRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.bold))
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    content()
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

struct CatalogCard: View {
    let item: CatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PosterTile(title: item.title, slug: item.slug, kind: item.provider)
            Text(item.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let genre = item.genres.first, !genre.isEmpty {
                Text(genre)
                    .font(.caption2)
                    .foregroundStyle(NoriTheme.muted)
                    .lineLimit(1)
            }
        }
        .frame(width: 124, alignment: .leading)
    }
}

struct ContinueCard: View {
    @Environment(LibraryStore.self) private var library
    let item: WatchProgress

    @State private var backdrop: URL?
    @State private var logo: URL?

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
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(caption)
                .font(.caption2)
                .foregroundStyle(NoriTheme.muted)
                .lineLimit(1)
        }
        .frame(width: 210, alignment: .leading)
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
                EmptyView()
            }
            .frame(maxWidth: 120, maxHeight: 34, alignment: .bottomLeading)
            .accessibilityLabel(item.title)
        } else {
            Text(item.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
                .frame(maxWidth: 150, alignment: .leading)
        }
    }
}

