import SwiftUI

struct KindSwitch: View {
    @Binding var provider: CatalogProvider
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let width: CGFloat = 132
    private let height: CGFloat = 30
    private let pad: CGFloat = 3
    private var thumb: CGFloat { (width / 2) - pad }
    private var travelMax: CGFloat { width - thumb - pad * 2 }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(NoriTheme.elevated)
            Capsule()
                .fill(NoriTheme.fg.opacity(0.14))
                .frame(width: thumb, height: height - pad * 2)
                .offset(x: pad + travel)
            HStack(spacing: 0) {
                ForEach(CatalogProvider.allCases) { item in
                    Text(item.kind)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(provider == item ? NoriTheme.fg : NoriTheme.muted)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard provider != item else { return }
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                                provider = item
                            }
                        }
                }
            }
            .padding(.horizontal, pad)
        }
        .frame(width: width, height: height)
        .overlay {
            Capsule().strokeBorder(NoriTheme.border)
        }
        // Ziehen fühlt sich auf dem Schalter natürlich an, ist aber nur eine
        // Zugabe: getippt wird häufiger, und das läuft über die Textfelder.
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    let toRight = value.translation.width > 0
                    let target: CatalogProvider = toRight ? .serienstream : .aniworld
                    guard provider != target else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                        provider = target
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quelle")
        .accessibilityValue(provider.kind)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: provider = .serienstream
            case .decrement: provider = .aniworld
            default: break
            }
        }
    }

    private var travelBase: CGFloat {
        provider == .aniworld ? 0 : travelMax
    }

    private var travel: CGFloat { travelBase }
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

    var body: some View {
        NoriScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
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

                    let watching = library.continueWatching()
                    if !watching.isEmpty {
                        PosterRow(title: "Weiterschauen") {
                            ForEach(watching) { item in
                                NoriSeriesLink(
                                    slug: item.slug,
                                    titleHint: item.title,
                                    scaleOnPress: true,
                                    provider: providerFromPath(item.episodePath)
                                ) {
                                    ContinueCard(item: item)
                                }
                            }
                        }
                    }

                    if !catalog.isEmpty {
                        PosterRow(title: "Beliebte \(library.provider.kind)") {
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
            // Der Kopfbereich läuft bis unter die Statusleiste. Ohne das säße
            // er unter einem grauen Streifen und wäre kein Kopfbereich mehr,
            // sondern eine Karte.
            .ignoresSafeArea(edges: .top)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                KindSwitch(provider: Bindable(library).provider)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: rowsKey) {
            genreRows = Self.buildRows(from: catalog)
            heroItems = buildHero()
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
        "\(library.provider.rawValue)|\(catalog.count)"
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

    private var height: CGFloat { 520 }

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

    private var progress: WatchProgress? {
        library.continueWatching().first { $0.slug == item.slug }
    }

    private var meta: String {
        var parts = [item.kind.label]
        parts.append(contentsOf: item.genres.prefix(3))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)

            Text(item.title)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(meta)
                .font(.caption)
                .foregroundStyle(NoriTheme.muted)
                .lineLimit(1)

            if let overview = details.overview, !overview.isEmpty {
                Text(overview)
                    .font(.footnote)
                    .foregroundStyle(NoriTheme.fg.opacity(0.85))
                    .lineLimit(3)
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
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        // Platz für die Seitenpunkte des TabView, die sonst auf den Knöpfen
        // liegen.
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Das Bild als Hintergrund, nicht als Ebene im Stapel: ein
        // `scaledToFill`-Bild meldet nach außen eine größere Größe, als ihm
        // angeboten wurde, und würde den Kopfbereich aufblähen. Als
        // Hintergrund beeinflusst es die Größe nicht.
        .background(alignment: .bottom) {
            backdrop
        }
        .task(id: item.slug) {
            details = await CoverIndex.shared.detailsLoading(
                slug: item.slug,
                title: item.title,
                kind: item.kind
            )
        }
    }

    private var playLabel: String {
        guard let progress else { return "Jetzt ansehen" }
        return "F\(progress.episode) weiterschauen"
    }

    @ViewBuilder
    private var backdrop: some View {
        ZStack(alignment: .bottom) {
            if let url = details.backdrop ?? details.poster {
                NoriCoverImage(url: url, referer: item.kind.origin + "/") {
                    NoriTheme.elevated
                }
            } else {
                NoriTheme.elevated
            }

            // Zwei Verläufe: einer trägt die Schrift unten, der andere nimmt
            // dem Bild oben die Härte gegen die Statusleiste.
            LinearGradient(
                colors: [.clear, NoriTheme.bg.opacity(0.75), NoriTheme.bg],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .allowsHitTesting(false)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PosterTile(
                title: item.title,
                slug: item.slug,
                kind: providerFromPath(item.episodePath)
            )
            Text(item.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("S\(item.season) · F\(item.episode) · \(formatClock(item.positionSec))")
                .font(.caption2)
                .foregroundStyle(NoriTheme.muted)
                .lineLimit(1)
            ProgressView(value: watchRatio(item))
                .tint(NoriTheme.accent)
        }
        .frame(width: 124, alignment: .leading)
    }
}
