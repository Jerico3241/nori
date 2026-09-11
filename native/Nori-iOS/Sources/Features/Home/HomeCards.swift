import SwiftUI

// Die Bausteine der neuen Startseite: Maße, Abschnittsüberschrift und die
// drei Kachelformen.
//
// Die Zahlen stammen aus `nori-home-v2.html` und sind bewusst andere als die
// der vorherigen Startseite: größere Poster, breitere Weiterschauen-Kacheln,
// Titel **unter** dem Bild statt darin, weichere Radien. Wo die Vorlage und
// Noris bestehendes System auseinanderlaufen, gewinnt das System — der
// Seitenrand etwa bleibt `NoriSpacing.screen`, damit Startseite und
// Detailseite links auf derselben Linie beginnen.

// MARK: - Maße

/// Die Maße der Startseite an einer Stelle.
///
/// Getrennt von `NoriSpacing` und `NoriRadius`, weil es Maße sind, die es nur
/// hier gibt: eine 278 Punkte breite Weiterschauen-Kachel kommt auf keinem
/// anderen Bildschirm vor. Was die ganze App teilt, steht weiter in
/// `NoriDesign.swift`.
enum HomeMetrics {
    /// Seitenrand — derselbe wie überall in Nori.
    static let screen: CGFloat = NoriSpacing.screen
    /// Abstand zweier Kacheln in einer Reihe.
    static let rail: CGFloat = 12
    /// Abstand zweier Abschnitte.
    static let section: CGFloat = 28

    /// Höhe der drei Kopfbereich-Knöpfe.
    static let action: CGFloat = 58
    static let actionRadius: CGFloat = 29
    /// Breite des „Mehr"-Knopfes. Quadratisch, damit die drei Punkte mittig
    /// stehen.
    static let actionSquare: CGFloat = 58

    static let posterRadius: CGFloat = 17
    static let landscapeRadius: CGFloat = 18
    static let thumbRadius: CGFloat = 12
    /// Durchmesser des Fortschrittsrings neben einer Folgenzeile.
    static let ring: CGFloat = 32
    /// Breite des Standbilds in einer Folgenzeile. Die Höhe ergibt sich aus
    /// 16:9 und liegt damit bei rund 66 Punkten.
    static let episodeThumb: CGFloat = 118

    /// Platz unter dem letzten Abschnitt.
    ///
    /// Die Tab-Leiste schwebt über dem Inhalt; ohne Reserve endet die letzte
    /// Reihe dahinter. Die Vorlage rechnet mit 150 Pixeln, hier kommt die
    /// tatsächliche Sicherheitszone hinzu, weil ein iPhone ohne Home-Taste
    /// mehr Rand hat als eines mit.
    static let bottom: CGFloat = 96

    /// Breite einer Posterkachel.
    ///
    /// Auf dem iPhone drei Kacheln plus Anschnitt — der Anschnitt ist die
    /// Einladung zum Wischen. Auf dem iPad nicht einfach breiter, sondern
    /// **mehr**: Kacheln über eine 1300 Punkte breite Reihe zu ziehen ergäbe
    /// Plakate, keine Übersicht.
    static func posterWidth(screen: CGFloat, regular: Bool) -> CGFloat {
        if regular { return 168 }
        return screen <= 380 ? 122 : 132
    }

    /// Breite einer Weiterschauen-Kachel. Breitbild, also deutlich breiter.
    static func landscapeWidth(screen: CGFloat, regular: Bool) -> CGFloat {
        if regular { return 320 }
        return screen <= 380 ? 250 : 278
    }

    /// Höhe des Kopfbereichs.
    ///
    /// Drei Fälle, und der dritte ist der, an dem eine feste Zahl scheitert:
    ///
    /// - **iPhone hochkant:** rund drei Viertel des Bildschirms, wie auf der
    ///   Vorlage. Hoch genug, dass das Artwork als Bild wirkt und nicht als
    ///   Banner; niedrig genug, dass die erste Reihe darunter angeschnitten zu
    ///   sehen ist und klar wird, dass es weitergeht.
    /// - **iPhone quer:** dort sind es nur rund 400 Punkte Höhe insgesamt.
    ///   Drei Viertel davon wären der ganze Bildschirm, und die Startseite
    ///   sähe aus wie ein einzelnes Bild.
    /// - **iPad und breite Fenster:** die Breite entscheidet mit, sonst
    ///   entsteht ein Kopfbereich, der höher ist als breit.
    static func heroHeight(screen: CGSize, regular: Bool) -> CGFloat {
        if regular { return min(max(screen.width * 0.5, 460), screen.height * 0.62) }
        if screen.height < 520 { return min(screen.width * 9 / 16, screen.height * 0.82) }
        return min(max(screen.height * 0.74, 500), 700)
    }
}

// MARK: - Überschrift

/// Die Überschrift eines Abschnitts: Titel links, optionaler Verweis rechts.
///
/// Anders als `NoriRowHeader` ohne Akzentbalken und mit größerer Schrift —
/// die Vorlage setzt die Überschriften deutlich kräftiger, weil die Reihen
/// darunter größer sind und ein zarter Titel dazwischen untergeht.
struct HomeSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(NoriTheme.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            trailing()
                .font(.footnote)
                .foregroundStyle(NoriTheme.muted)
        }
        .padding(.horizontal, HomeMetrics.screen)
        .padding(.bottom, 12)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Eine waagerecht scrollende Reihe — die Grundform der Startseite.
struct HomeRail<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: HomeMetrics.rail) {
                content()
            }
            .padding(.horizontal, HomeMetrics.screen)
        }
        // Ohne das beschneidet der Scrollbereich Schatten und gedrückte
        // Kachel an seinen Rändern.
        .scrollClipDisabled()
    }
}

// MARK: - Posterkachel

/// Das Abzeichen oben links auf einem Poster.
///
/// Nur aus echten Signalen: „NEU" heißt, dass TMDB eine Ausstrahlung im
/// Aktualitätsfenster führt, „TOP 10" bezeichnet einen Platz in TMDBs
/// Wochenliste. Ohne Signal gibt es kein Abzeichen — ein dekoratives „NEU"
/// auf jeder zweiten Kachel wäre eine Behauptung.
enum HomeBadge: Equatable {
    case fresh
    case top(Int)

    static func of(_ candidate: HomeCandidate, now: Date) -> HomeBadge? {
        if let rank = candidate.signals.trendingRank, rank <= 10 { return .top(rank) }
        if HomeRanking.isNew(candidate.signals, now: now) { return .fresh }
        return nil
    }

    var label: String {
        switch self {
        case .fresh: return "NEU"
        case .top: return "TOP 10"
        }
    }

    var spoken: String {
        switch self {
        case .fresh: return "Neu"
        case .top(let rank): return "Platz \(rank) der Trendliste"
        }
    }
}

/// Eine Posterkachel in einer Reihe der Startseite.
///
/// Der Titel steht **unter** dem Bild, nicht darin. Auf der vorherigen
/// Startseite lag er im Artwork, damit alle Kacheln gleich hoch bleiben; die
/// Vorlage setzt ihn darunter, weil die Poster größer sind und ein Titel auf
/// dem Bild dann mitten im Motiv steht. Gleich hoch bleiben die Kacheln
/// trotzdem — der Titelbereich hat eine feste Höhe für zwei Zeilen.
struct HomePosterCard: View {
    let candidate: HomeCandidate
    let width: CGFloat
    var badge: HomeBadge?

    private var subtitle: String {
        let genres = candidate.title.genres.prefix(2).filter { !$0.isEmpty }
        if !genres.isEmpty { return genres.joined(separator: " · ") }
        return candidate.title.provider.kind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            poster
            Text(candidate.title.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NoriTheme.fg)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(NoriTheme.muted)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        // Alle Kacheln einer Reihe gleich hoch: ohne feste Höhe verschiebt
        // ein zweizeiliger Titel neben einem einzeiligen die ganze Reihe.
        .frame(height: width * 1.5 + 60, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleLabel)
    }

    private var poster: some View {
        PosterTile(
            title: candidate.title.title,
            slug: candidate.title.slug,
            kind: candidate.title.provider,
            cornerRadius: HomeMetrics.posterRadius
        )
        .frame(width: width)
        .overlay(alignment: .topLeading) { badgeView }
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            Text(badge.label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(NoriTheme.fg)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.62))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.12))
                }
                .padding(9)
        }
    }

    private var accessibleLabel: String {
        var parts = [candidate.title.title, subtitle]
        if let badge { parts.append(badge.spoken) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Weiterschauen-Kachel

/// Eine Kachel in „Weiterschauen": Breitbild, Fortschritt, Restzeit.
///
/// Bildwahl in dieser Reihenfolge — Standbild der Folge, Breitbild der Serie,
/// Poster. Das Standbild steht vorn, weil es zeigt, wo man stehen geblieben
/// ist, und nicht bloß, um welche Serie es geht. Es kommt aus `EpisodeIndex`
/// und damit aus demselben Zwischenspeicher, den die Folgenliste der
/// Detailseite füllt: wer eine Folge angefangen hat, hat die Seite offen
/// gehabt, und das Bild liegt meist schon da.
struct HomeLandscapeCard: View {
    let item: WatchProgress
    let width: CGFloat

    @State private var artwork: URL?

    private var source: CatalogProvider {
        item.provider ?? providerFromPath(item.episodePath)
    }

    /// „Noch 21 Min." statt einer Prozentzahl.
    ///
    /// Die Restzeit sagt, worauf man sich einlässt; ein Prozentwert nicht.
    /// Fehlt die Dauer — etwa weil der Fortschritt aus einem älteren Stand
    /// stammt —, tritt Staffel und Folge allein an die Stelle.
    private var caption: String {
        let base = "S\(item.season) · F\(item.episode)"
        let left = item.durationSec - item.positionSec
        guard item.durationSec > 0, left > 30 else { return base }
        return "\(base) · noch \(Int(left / 60)) Min."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            thumbnail
            Text(item.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NoriTheme.fg)
                .lineLimit(1)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(NoriTheme.muted)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .task(id: item.id) { await loadArtwork() }
    }

    private var thumbnail: some View {
        Color.clear
            .frame(width: width, height: width * 9 / 16)
            .overlay { image }
            .overlay { veil }
            .overlay(alignment: .topTrailing) { playMark }
            .overlay(alignment: .bottom) { progressBar }
            .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.landscapeRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HomeMetrics.landscapeRadius, style: .continuous)
                    .strokeBorder(NoriTheme.border)
            }
            .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
    }

    @ViewBuilder
    private var image: some View {
        if let artwork {
            NoriCoverImage(url: artwork, referer: HomeArtwork.referer(for: artwork, provider: source)) {
                NoriTheme.elevated
            }
        } else {
            NoriTheme.elevated
        }
    }

    /// Ein schwacher Verlauf nach unten. Ohne ihn verschwindet der
    /// Fortschrittsbalken auf einem hellen Standbild.
    private var veil: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.45)],
            startPoint: .center,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    /// Ein Abspielzeichen: diese Kachel startet als einzige der Startseite
    /// unmittelbar die Wiedergabe, statt zur Serie zu führen. Ohne Zeichen
    /// sieht sie aus wie jede andere.
    private var playMark: some View {
        Image(systemName: "play.circle.fill")
            .font(.title3)
            .foregroundStyle(.white, .black.opacity(0.35))
            .padding(9)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.22))
                Rectangle()
                    .fill(NoriTheme.accent)
                    .frame(width: geo.size.width * watchRatio(item))
                    .shadow(color: NoriTheme.accent.opacity(0.5), radius: 5)
            }
        }
        .frame(height: 4)
    }

    private func loadArtwork() async {
        // Erst das Standbild der Folge — es zeigt, wo man stehen geblieben
        // ist. `cached` fragt kein Netz; der Abruf danach ist in `EpisodeIndex`
        // gebündelt und trifft für dieselbe Staffel nur einmal.
        let known = await EpisodeIndex.shared.cached(slug: item.slug, season: item.season)
        if let still = known[item.episode]?.stillURL {
            artwork = still
            return
        }

        let details = await CoverIndex.shared.detailsLoading(
            slug: item.slug,
            title: item.title,
            kind: source
        )
        artwork = details.backdrop ?? details.poster
        guard !Task.isCancelled else { return }

        let loaded = await EpisodeIndex.shared.load(
            slug: item.slug,
            title: item.title,
            season: item.season,
            kind: source
        )
        if let still = loaded[item.episode]?.stillURL, !Task.isCancelled {
            artwork = still
        }
    }
}

// MARK: - Folgenzeile

/// Eine Zeile in „Neue Episoden".
///
/// Eine Zeile und keine Kachel, weil hier die Angaben zählen — Serie, Staffel,
/// Folge, Sprache, wann. In einer Kachel stünde davon die Hälfte unter dem
/// Bild und die andere Hälfte gar nicht.
struct HomeEpisodeCard: View {
    @Environment(LibraryStore.self) private var library
    let entry: AiringEntry

    @State private var still: URL?

    private var source: CatalogProvider { entry.provider ?? .aniworld }

    /// Wie weit diese Folge gesehen ist. Aus dem persönlichen Fortschritt —
    /// der Ring sagt „angefangen", nicht „beliebt".
    private var progress: Double {
        let path = source.episodePath(slug: entry.slug, season: entry.season, episode: entry.episode)
        return watchRatio(library.progress(forPath: path, provider: source))
    }

    private var meta: String {
        var parts = ["S\(entry.season)", "F\(entry.episode)"]
        if let language = entry.languages.first, !language.isEmpty { parts.append(language) }
        parts.append(Self.when(entry.airingAt))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NoriTheme.fg)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundStyle(NoriTheme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            HomeProgressRing(value: progress)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 88)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.title), \(meta)")
        .task(id: entry.id) { await loadStill() }
    }

    private var thumbnail: some View {
        Color.clear
            .frame(width: HomeMetrics.episodeThumb, height: HomeMetrics.episodeThumb * 9 / 16)
            .overlay { image }
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(NoriTheme.bg)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.white.opacity(0.88)))
            }
            .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.thumbRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HomeMetrics.thumbRadius, style: .continuous)
                    .strokeBorder(NoriTheme.border)
            }
    }

    @ViewBuilder
    private var image: some View {
        if let still {
            NoriCoverImage(url: still, referer: HomeArtwork.referer(for: still, provider: source)) {
                NoriTheme.elevated
            }
        } else {
            NoriTheme.elevated
        }
    }

    private func loadStill() async {
        // Der Kalendereintrag bringt oft schon ein Cover mit — das steht
        // sofort da, ohne eine einzige Anfrage.
        still = AniworldClient.coverURL(entry.coverPath, provider: source)

        let known = await EpisodeIndex.shared.cached(slug: entry.slug, season: entry.season)
        if let cached = known[entry.episode]?.stillURL {
            still = cached
            return
        }
        guard !Task.isCancelled else { return }
        let loaded = await EpisodeIndex.shared.load(
            slug: entry.slug,
            title: entry.title,
            season: entry.season,
            kind: source
        )
        if let fresh = loaded[entry.episode]?.stillURL, !Task.isCancelled {
            still = fresh
        }
    }

    /// „heute", „gestern" oder das Datum.
    ///
    /// `airingAt` steht in Millisekunden — dieselbe Einheit wie überall im
    /// Kalender.
    static func when(_ airingAt: Double) -> String {
        let date = Date(timeIntervalSince1970: airingAt / 1000)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "heute" }
        if calendar.isDateInYesterday(date) { return "gestern" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }
}

/// Der Fortschrittsring neben einer Folgenzeile.
///
/// Auch bei null sichtbar: der leere Ring steht neben angefangenen Folgen und
/// sagt dort „diese noch nicht". Ein Ring, der erst ab Fortschritt erscheint,
/// ließe die Zeilen unterschiedlich breit werden.
struct HomeProgressRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(NoriTheme.muted.opacity(0.3), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(NoriTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: HomeMetrics.ring, height: HomeMetrics.ring)
        .accessibilityHidden(true)
    }
}

// MARK: - Bildquelle

enum HomeArtwork {
    /// Welchen Referer ein Bildabruf braucht.
    ///
    /// AniWorld und Serienstream liefern ihre Cover nur mit passender
    /// Kopfzeile aus, TMDB verlangt keine. Bisher stand an jeder Aufrufstelle
    /// entweder blind der Quellen-Referer oder eine leere Zeichenkette; welche
    /// Adresse gerade vorlag, wusste man dort nicht sicher.
    static func referer(for url: URL, provider: CatalogProvider) -> String {
        TMDBImages.isTMDB(url) ? "" : provider.origin + "/"
    }
}
