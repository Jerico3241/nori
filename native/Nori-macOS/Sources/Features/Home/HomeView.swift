import SwiftUI

struct GenreRow: Identifiable, Hashable {
    let title: String
    let items: [CatalogItem]
    var id: String { title }
}

/// Ein Titel im Kopfkarussell — entweder angefangen oder vorgeschlagen.
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

    private let grid = [GridItem(.adaptive(minimum: 158, maximum: 200), spacing: 18)]

    /// Warum die Liste leer ist — in der Sprache des Bereichs.
    ///
    /// „Der Katalog von K-Drama ist leer" wäre falsch: K-Drama ist kein
    /// Katalog, sondern ein Ausschnitt aus dem von Serienstream. Leer heißt
    /// hier, dass der Katalog steht, aber kein Titel das Genre trägt.
    private var emptyHint: String {
        if library.scope == .all { return "Beide Kataloge sind gerade leer." }
        if let genre = library.scope.genre {
            return "Im Katalog von \(library.scope.provider?.label ?? "Serienstream") steht gerade kein Titel unter „\(genre)“."
        }
        return "Der Katalog von \(library.scope.label) ist gerade leer."
    }

    var body: some View {
        NoriScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 36) {
                    if let error {
                        ErrorBanner(message: error) { Task { await reload() } }
                            .padding(.horizontal, NoriLayout.gutter)
                    }

                    if loading && catalog.isEmpty {
                        ProgressView("Nori wird geladen")
                            .frame(maxWidth: .infinity, minHeight: 420)
                    } else {
                        let watching = library.continueWatching()

                        if !heroItems.isEmpty {
                            HeroCarousel(items: heroItems)
                        }

                        if !watching.isEmpty {
                            ContinueRow(items: watching)
                        }

                        ForEach(genreRows) { row in
                            PosterRow(title: row.title, items: row.items)
                        }

                        if !catalog.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                NoriSectionHeader(
                                    library.scope.headline,
                                    trailing: "\(catalog.count) Titel"
                                )
                                LazyVGrid(columns: grid, alignment: .leading, spacing: 24) {
                                    ForEach(catalog.prefix(60)) { item in
                                        PosterCell(item: item)
                                    }
                                }
                            }
                            .padding(.horizontal, NoriLayout.gutter)
                        } else {
                            ContentUnavailableView(
                                "Nichts geladen",
                                systemImage: "tray",
                                description: Text(emptyHint)
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                        }
                    }
                }
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Entdecken")
        .navigationSubtitle(library.scope.label)
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
            heroItems = buildHero()
        }
    }

    /// Sechs Empfehlungen fürs Banner.
    ///
    /// Angefangene Titel gehören hier **nicht** hinein: sie stehen direkt
    /// darunter in „Schau weiter". Im Banner wiederholten sie nur, was man
    /// ohnehin schon kennt, und ein „Folge 1 fortsetzen" ist keine Empfehlung.
    ///
    /// Läuft in einer Aufgabe statt bei jedem Rendern — die Auswahl geht durch
    /// den gesamten Katalog.
    private func buildHero() -> [HeroItem] {
        // Titel ohne Genre sagen im Banner nichts aus; nur wenn zu wenige mit
        // Genre da sind, wird der ganze Katalog genommen.
        let described = catalog.filter { !$0.genres.isEmpty }
        let source = described.count >= 6 ? described : catalog
        guard !source.isEmpty else { return [] }

        // Ohne das stünden dort immer dieselben sechs Titel vom Anfang des
        // Alphabets. Der Tag geht in die Reihenfolge ein, innerhalb eines Tages
        // bleibt sie gleich.
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        return source
            .sorted { Self.featureRank($0.slug, day: day) < Self.featureRank($1.slug, day: day) }
            .prefix(6)
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

    /// Neu gruppieren, wenn sich Quelle oder Katalogumfang ändert. Ein
    /// `onChange` auf dem Array selbst würde bei jedem Rendern tausende
    /// Einträge vergleichen.
    private var rowsKey: String {
        "\(library.scope.rawValue)|\(catalog.count)"
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
        // können denselben Slug führen, und in einer gemeinsamen Liste fiele
        // sonst einer der beiden Titel aus allen Zeilen heraus.
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

enum NoriLayout {
    static let gutter: CGFloat = 28
    static let cardWidth: CGFloat = 168
}

// MARK: - Hero-Karussell

struct HeroCarousel: View {
    let items: [HeroItem]

    @State private var index = 0
    @State private var tick = 0
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(NoriGlassSetting.key) private var glass = true

    /// Die Liste wechselt beim Quellenwechsel die Länge. Ohne Begrenzung
    /// zeigte das Karussell dann eine leere Fläche.
    private var safeIndex: Int { items.isEmpty ? 0 : min(index, items.count - 1) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                if position == safeIndex {
                    HeroSlide(item: item)
                        .transition(.opacity)
                }
            }

            // Als Knöpfe statt als Tap-Geste: nur so sind sie per Tastatur und
            // VoiceOver erreichbar und zeigen den richtigen Mauszeiger.
            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { position in
                    Button {
                        select(position)
                    } label: {
                        Capsule()
                            .fill(position == safeIndex ? NoriTheme.accent : Color.white.opacity(0.35))
                            .frame(width: position == safeIndex ? 26 : 12, height: 4)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Titel \(position + 1) von \(items.count)")
                    .help(items[position].title)
                }
            }
            .padding(.leading, NoriLayout.gutter)
            .padding(.bottom, 22)
        }
        .frame(height: 460)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .leading) { arrow(-1, symbol: "chevron.left") }
        .overlay(alignment: .trailing) { arrow(1, symbol: "chevron.right") }
        .animation(NoriMotion.allowed(NoriMotion.content, reduceMotion: reduceMotion), value: safeIndex)
        .onHover { hovering = $0 }
        // `tick` wird bei jedem Durchlauf erhöht, damit die Aufgabe auch dann
        // neu startet, wenn nicht weitergeblättert wurde. Vorher hing sie an
        // `index` allein und blieb für immer stehen, sobald der Zeiger beim
        // Ablauf der Wartezeit über dem Bereich lag.
        .task(id: "\(safeIndex)-\(tick)") {
            guard items.count > 1, !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled else { return }
            if !hovering { index = (safeIndex + 1) % items.count }
            tick &+= 1
        }
    }

    @ViewBuilder
    private func arrow(_ direction: Int, symbol: String) -> some View {
        if items.count > 1, hovering {
            Button {
                select((safeIndex + direction + items.count) % items.count)
            } label: {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .noriGlass(Circle(), enabled: glass, off: Color.black.opacity(0.4))
            }
            .buttonStyle(NoriPressStyle(scale: 0.94))
            .padding(.horizontal, 12)
            .transition(.opacity)
        }
    }

    private func select(_ position: Int) {
        index = position
    }
}

/// Ein Bild über die volle Breite, von unten und links abgedunkelt, mit Titel,
/// Metazeile, Beschreibung und Abspielknopf.
struct HeroSlide: View {
    let item: HeroItem

    @State private var details = CoverDetails()

    var body: some View {
        // Hintergrund und Text sind bewusst nicht anklickbar: Knopf und
        // Merken-Symbol liegen darin und dürfen nicht in einem umschließenden
        // NavigationLink stecken, sonst schluckt der äußere Link die Klicks.
        Color.clear
            .overlay {
                GeometryReader { geometry in
                    background
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .allowsHitTesting(false)
            }
            .overlay {
            LinearGradient(
                colors: [.black.opacity(0.92), .black.opacity(0.55), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            }
            .overlay {
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )
            }
            .overlay(alignment: .bottomLeading) { text }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: item.id) {
            details = await CoverIndex.shared.detailsLoading(
                slug: item.slug,
                title: item.title,
                kind: item.kind
            )
            if details.poster == nil {
                let poster = await CoverIndex.shared.fetchSourceCover(slug: item.slug, provider: item.kind)
                guard !Task.isCancelled else { return }
                details.poster = poster
            }
        }
    }

    /// Vollflächig darf nur ein Breitbild.
    ///
    /// Vorher stand hier `details.backdrop ?? details.poster`. Fehlt das
    /// Breitbild, landete damit ein 2:3-Poster in einer etwa 2:1 breiten
    /// Fläche: `scaledToFill` zeigte dann einen winzigen Ausschnitt aus der
    /// Bildmitte — meist ein Stück Kleidung, und der Titel ging darin unter.
    /// Ein Poster wird deshalb nur noch unscharf und abgedunkelt als Untergrund
    /// verwendet, wo der Ausschnitt keine Rolle spielt.
    @ViewBuilder
    private var background: some View {
        if let wide = details.backdrop {
            NoriCoverImage(url: wide, referer: item.kind.origin + "/") { fallback }
        } else if let poster = details.poster {
            NoriCoverImage(url: poster, referer: item.kind.origin + "/") { fallback }
                .blur(radius: 44)
                .overlay(NoriTheme.bg.opacity(0.45))
        } else {
            fallback
        }
    }

    private var fallback: some View {
        LinearGradient(
            colors: [NoriTheme.elevated, NoriTheme.bg],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 12) {
            NoriSeriesLink(slug: item.slug, titleHint: item.title, provider: item.kind) {
                Text(item.title)
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 3)
            }
            .help(item.title)

            MetaLine(kind: item.kind, genres: item.genres, stars: details.stars)

            if let overview = details.overview, !overview.isEmpty {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(4)
                    .frame(maxWidth: 620, alignment: .leading)
            }

            HStack(spacing: 10) {
                NoriSeriesLink(slug: item.slug, titleHint: item.title, provider: item.kind) {
                    Label("Jetzt ansehen", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .frame(height: NoriControl.hit)
                    .background(NoriTheme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(NoriTheme.onAccent)
                }

                BookmarkButton(slug: item.slug, title: item.title, large: true)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, NoriLayout.gutter)
        .padding(.bottom, 54)
        .frame(maxWidth: 720, alignment: .leading)
    }
}

/// „16+ • Untertitel | Synchro • Drama, Thriller" plus Sternebewertung.
struct MetaLine: View {
    var kind: CatalogProvider
    var genres: [String]
    var stars: Double?

    var body: some View {
        HStack(spacing: 8) {
            if let stars {
                HStack(spacing: 2) {
                    ForEach(0 ..< 5, id: \.self) { i in
                        Image(systemName: Double(i) + 0.5 < stars ? "star.fill" : "star")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(NoriTheme.accent)
                Text(String(format: "%.1f", stars))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("•").foregroundStyle(.white.opacity(0.4))
            }
            Text(kind.label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            if !genres.isEmpty {
                Text("•").foregroundStyle(.white.opacity(0.4))
                Text(genres.prefix(3).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
    }
}

struct BookmarkButton: View {
    @Environment(LibraryStore.self) private var library
    let slug: String
    let title: String
    var large = false
    @AppStorage(NoriGlassSetting.key) private var glass = true

    var body: some View {
        Button {
            library.toggleFavorite(slug, title: title)
        } label: {
            let marked = library.isFavorite(slug)
            Image(systemName: marked ? "bookmark.fill" : "bookmark")
                .font(large ? .body.weight(.semibold) : .caption)
                .foregroundStyle(marked ? NoriTheme.accent : .white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: large ? 44 : 26, height: large ? 44 : 26)
                .noriGlass(
                    RoundedRectangle(cornerRadius: large ? 10 : 6, style: .continuous),
                    enabled: glass,
                    off: Color.black.opacity(0.45)
                )
        }
        .buttonStyle(NoriPressStyle(scale: 0.94))
        .help(library.isFavorite(slug) ? "Aus Merkliste entfernen" : "Zur Merkliste hinzufügen")
    }
}

// MARK: - Kacheln mit Hover-Infofeld

struct PosterCell: View {
    @Environment(LibraryStore.self) private var library
    let item: CatalogItem
    var width: CGFloat = NoriLayout.cardWidth

    @State private var hovering = false
    @State private var details = CoverDetails()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Die Quelle kommt aus dem Eintrag, nicht aus dem globalen
            // Umschalter: nur so führt eine Kachel auch dann richtig, wenn die
            // Liste Titel beider Quellen enthält.
            NoriSeriesLink(slug: item.slug, titleHint: item.title, provider: item.provider) {
                VStack(alignment: .leading, spacing: 8) {
                    PosterTile(title: item.title, slug: item.slug, kind: item.provider)
                        .overlay {
                            if hovering {
                                HoverInfo(
                                    title: item.title,
                                    genres: item.genres,
                                    details: details
                                )
                                .allowsHitTesting(false)
                                .transition(.opacity)
                            }
                        }
                    Text(item.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    Text(item.genres.prefix(2).joined(separator: " | "))
                        .font(.caption2)
                        .foregroundStyle(NoriTheme.muted)
                        .lineLimit(1)
                }
                .frame(width: width, alignment: .leading)
            }
            .help(item.title)

            if hovering {
                BookmarkButton(slug: item.slug, title: item.title)
                    .padding(8)
            }
        }
        .noriAnimation(NoriMotion.hover, value: hovering)
        .onHover { inside in
            hovering = inside
            if inside, details.overview == nil {
                Task {
                    details = await CoverIndex.shared.detailsLoading(
                        slug: item.slug,
                        title: item.title,
                        kind: item.provider ?? library.provider
                    )
                }
            }
        }
    }
}

/// Legt sich beim Überfahren über das Poster und zeigt, was wir über den Titel
/// wissen — wie die aufklappende Kachel auf gängigen Streaming-Startseiten.
struct HoverInfo: View {
    let title: String
    let genres: [String]
    let details: CoverDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            if let stars = details.stars {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(NoriTheme.accent)
                    Text(String(format: "%.1f", stars))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            if !genres.isEmpty {
                Text(genres.prefix(3).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            if let overview = details.overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(7)
            } else {
                Text("Keine Beschreibung hinterlegt.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)

            Label("Öffnen", systemImage: "play.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NoriTheme.accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Deckend, nicht durchscheinend: mit 86 % Schwarz stand die Schrift auf
        // dem Poster und war kaum zu lesen. Das Feld ersetzt die Kachel, es
        // liegt nicht darüber.
        .background(NoriTheme.elevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NoriTheme.accent)
                .frame(height: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Zeilen

struct PosterRow: View {
    let title: String
    let items: [CatalogItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NoriSectionHeader(title)
                .padding(.horizontal, NoriLayout.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(items) { item in
                        PosterCell(item: item)
                    }
                }
                .padding(.horizontal, NoriLayout.gutter)
                .padding(.vertical, 6)
            }
        }
    }
}

struct ContinueRow: View {
    let items: [WatchProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NoriSectionHeader("Schau weiter")
                .padding(.horizontal, NoriLayout.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(items) { item in
                        ContinueCard(item: item)
                    }
                }
                .padding(.horizontal, NoriLayout.gutter)
                .padding(.vertical, 6)
            }
        }
    }
}

/// Querformat wie bei Streaming-Diensten üblich: Standbild, Abspielsymbol,
/// Fortschrittsbalken und Restzeit. Als Bild dient das Breitbild aus TMDB —
/// die Quellen liefern keine Standbilder je Folge.
struct ContinueCard: View {
    let item: WatchProgress

    @State private var details = CoverDetails()
    @State private var hovering = false

    private var kind: CatalogProvider { item.provider ?? providerFromPath(item.episodePath) }
    private var remaining: Double { max(0, item.durationSec - item.positionSec) }

    var body: some View {
        NoriSeriesLink(slug: item.slug, titleHint: item.title, provider: kind) {
            VStack(alignment: .leading, spacing: 8) {
                NoriTheme.elevated
                    .frame(width: 284, height: 160)
                    .overlay {
                        still.frame(width: 284, height: 160).clipped()
                    }
                    .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                        .shadow(color: .black.opacity(0.5), radius: 6)
                }
                .frame(width: 284, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if remaining > 60, item.durationSec > 0 {
                        Text("\(Int(remaining / 60)) min verbleibend")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottom) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.25))
                            Rectangle()
                                .fill(NoriTheme.accent)
                                .frame(width: geo.size.width * watchRatio(item))
                        }
                    }
                    .frame(height: 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(hovering ? NoriTheme.accent.opacity(0.8) : .clear, lineWidth: 2)
                }

                Text(item.title.uppercased())
                    .font(.caption2)
                    .foregroundStyle(NoriTheme.muted)
                    .lineLimit(1)
                Text("S\(item.season) E\(item.episode)\(item.germanTitle.isEmpty ? "" : " – \(item.germanTitle)")")
                    .font(.callout.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 284, alignment: .leading)
        }
        .help(item.title)
        .onHover { hovering = $0 }
        .task(id: item.id) {
            details = await CoverIndex.shared.detailsLoading(
                slug: item.slug,
                title: item.title,
                kind: kind
            )
            if details.poster == nil {
                let poster = await CoverIndex.shared.fetchSourceCover(slug: item.slug, provider: kind)
                guard !Task.isCancelled else { return }
                details.poster = poster
            }
        }
    }

    /// Die Karte ist quer, ein Poster ist hochkant. `scaledToFill` schnitt
    /// daraus einen schmalen Streifen aus der Bildmitte — bei einfarbigen
    /// Covern eine leere Fläche. Ohne Breitbild steht das Poster deshalb
    /// vollständig in der Mitte, davor ein unscharfer Untergrund aus demselben
    /// Bild, damit die Karte gefüllt wirkt.
    @ViewBuilder
    private var still: some View {
        if let wide = details.backdrop {
            NoriCoverImage(url: wide, referer: kind.origin + "/") { NoriTheme.elevated }
        } else if let poster = details.poster {
            NoriTheme.elevated
                .overlay {
                    NoriCoverImage(url: poster, referer: kind.origin + "/") { NoriTheme.elevated }
                        .blur(radius: 28)
                        .overlay(NoriTheme.bg.opacity(0.35))
                }
                .overlay {
                    NoriCoverImage(url: poster, referer: kind.origin + "/", contentMode: .fit) {
                        Color.clear
                    }
                }
        } else {
            NoriTheme.elevated
        }
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

