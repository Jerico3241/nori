import SwiftUI

// Die Bausteine der Merkliste: Maße, Posterkachel, Listenzeile, Fortschritt.
//
// Die Zahlen stammen aus `nori-watchlist-v3.html`. Wo die Vorlage und Noris
// bestehendes System auseinanderlaufen, gewinnt das System: der Seitenrand
// bleibt `NoriSpacing.screen`, damit Merkliste, Startseite und Detailseite
// links auf derselben Linie beginnen, und Bewegung sowie Druck kommen aus
// `NoriDesign.swift`.

// MARK: - Maße

/// Die Maße der Merkliste an einer Stelle.
///
/// Getrennt von `NoriSpacing` und `NoriRadius` aus demselben Grund wie
/// `HomeMetrics`: eine Posterkachel mit 18 Punkten Radius und 11 Punkten
/// Spaltenabstand gibt es nur hier.
enum WatchlistMetrics {
    static let screen: CGFloat = NoriSpacing.screen
    /// Waagerechter Abstand zweier Kacheln. Enger als der senkrechte — so
    /// steht es in der Vorlage, und es lässt die Poster größer werden.
    static let columnGap: CGFloat = 11
    static let rowGap: CGFloat = 20
    static let posterRadius: CGFloat = 18
    static let cardRadius: CGFloat = 23
    static let rowRadius: CGFloat = 18
    static let thumbRadius: CGFloat = 13
    /// Höhe des Fortschrittsbalkens auf dem Poster.
    static let progressHeight: CGFloat = 4
    /// Platz unter dem letzten Eintrag. Die Tab-Leiste schwebt über dem
    /// Inhalt; ohne Reserve endet die letzte Reihe dahinter.
    static let bottom: CGFloat = 96
    /// Wie hoch der Rückgängig-Streifen über dem unteren Rand steht.
    /// Dieselbe Überlegung, nur knapper: er soll die Leiste freilassen,
    /// aber nicht mitten im Inhalt schweben.
    static let undoLift: CGFloat = 86

    /// Spaltenzahl des Rasters.
    ///
    /// Auf dem iPhone zwei — große Poster, wie in der Vorlage, und
    /// ausdrücklich nicht die kleinen Kacheln der alten Merkliste. Auf dem
    /// iPad richtet sie sich nach der Breite: drei bis fünf, damit die
    /// Poster nicht zu Plakaten werden. Gerechnet wird aus der tatsächlichen
    /// Breite und nicht aus dem Gerät, weil ein iPad im Splitview so breit
    /// sein kann wie ein iPhone.
    static func columns(width: CGFloat, regular: Bool) -> Int {
        guard regular else { return 2 }
        if width >= 1180 { return 5 }
        if width >= 900 { return 4 }
        if width >= 620 { return 3 }
        return 2
    }

    static func grid(width: CGFloat, regular: Bool) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: columnGap, alignment: .top),
            count: columns(width: width, regular: regular)
        )
    }
}

// MARK: - Fortschritt

/// Der Balken am unteren Rand des Posters.
///
/// Steht nur da, wo es etwas zu zeigen gibt: bei einem ungesehenen Titel
/// bleibt das Poster leer statt einen leeren Balken zu tragen. Ein Balken auf
/// null ist keine Information, sondern nur ein Strich.
struct WatchlistProgressBar: View {
    let ratio: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.17))
                Capsule()
                    .fill(NoriTheme.accent)
                    .frame(width: max(3, proxy.size.width * min(max(ratio, 0), 1)))
            }
        }
        .frame(height: WatchlistMetrics.progressHeight)
        .accessibilityHidden(true)
    }
}

/// Das Abzeichen „GESEHEN" oben links auf dem Poster.
///
/// Das einzige Abzeichen, das die Merkliste kennt. „ANIME" und „SERIE" gibt
/// es hier bewusst nicht: der Medientyp ist auf einem Poster keine
/// Information, die eine Ecke wert wäre, und er steht ohnehin in der Zeile
/// unter dem Titel.
struct WatchlistSeenBadge: View {
    var body: some View {
        Text("GESEHEN")
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(Color(red: 0.78, green: 0.96, blue: 0.87))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(red: 0.11, green: 0.33, blue: 0.24).opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.09))
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Posterkachel

/// Eine Kachel der Rasteransicht: Poster, Titel, Eckdaten, Stand.
///
/// Das Poster selbst zeichnet `PosterTile` — es bringt die Auflösung der
/// Bildquelle schon mit (manuelle Auswahl, dann TMDB, dann das Cover der
/// Quelle, zuletzt der Buchstabe), lädt asynchron, bricht beim Scrollen ab
/// und legt Ergebnisse dauerhaft ab. Ein eigener Ladeweg für die Merkliste
/// wäre eine zweite Fassung derselben Kette, die bei der ersten TMDB-Störung
/// anders reagiert.
struct WatchlistPosterCard: View {
    let item: WatchlistItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            poster
            Text(item.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NoriTheme.fg)
                .lineLimit(1)
                .padding(.top, 8)
            Text(item.metaText)
                .font(.system(size: 10.5))
                .foregroundStyle(NoriTheme.muted)
                .lineLimit(1)
                .padding(.top, 4)
            Text(item.watch.stateText)
                .font(.system(size: 10))
                .foregroundStyle(stateColor)
                .lineLimit(1)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(watchlistAccessibilityLabel(item))
    }

    private var poster: some View {
        PosterTile(
            title: item.title,
            slug: item.slug,
            kind: item.provider,
            cornerRadius: WatchlistMetrics.posterRadius
        )
        .overlay(alignment: .topLeading) {
            if item.watch.state == .seen {
                WatchlistSeenBadge().padding(8)
            }
        }
        .overlay(alignment: .bottom) {
            if item.watch.state != .unseen {
                WatchlistProgressBar(ratio: item.watch.ratio)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 9)
            }
        }
    }

    private var stateColor: Color {
        switch item.watch.state {
        case .unseen: return NoriTheme.muted
        case .started: return Color(red: 0.75, green: 0.91, blue: 1.0)
        case .seen: return Color(red: 0.75, green: 0.92, blue: 0.83)
        }
    }
}

// MARK: - Listenzeile

/// Eine Zeile der Listenansicht.
///
/// Ausdrücklich nicht die alte Merklistenzeile: die war ein 44 Punkte
/// breites Bildchen neben einem Titel in einer `List` mit Systemhintergrund.
/// Diese Zeile ist eine eigene Karte im Stil der Vorlage — größeres Bild,
/// Eckdaten, Stand, eigener Grund und Rand — und gehört damit sichtbar zur
/// selben Oberfläche wie das Raster daneben.
struct WatchlistListRow: View {
    let item: WatchlistItem

    var body: some View {
        HStack(spacing: 12) {
            PosterTile(
                title: item.title,
                slug: item.slug,
                compact: true,
                kind: item.provider,
                cornerRadius: WatchlistMetrics.thumbRadius
            )
            .frame(width: 76)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NoriTheme.fg)
                    .lineLimit(2)
                Text(item.metaText)
                    .font(.system(size: 10))
                    .foregroundStyle(NoriTheme.muted)
                    .lineLimit(1)
                if item.watch.state != .unseen {
                    WatchlistProgressBar(ratio: item.watch.ratio)
                        .frame(maxWidth: 160)
                        .padding(.top, 3)
                }
                Text(item.watch.stateText)
                    .font(.system(size: 10))
                    .foregroundStyle(item.watch.state == .unseen ? NoriTheme.muted : Color(red: 0.75, green: 0.91, blue: 1.0))
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Der Pfeil gehört zur Karte, nicht zur Zeile: die Liste zeichnet
            // ihren eigenen außerhalb des Kartengrunds, weshalb die Merkliste
            // dort einen Knopf statt eines `NavigationLink` benutzt.
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(NoriTheme.muted)
        }
        .padding(9)
        .frame(minHeight: 100)
        .background(NoriTheme.elevated.opacity(0.72), in: RoundedRectangle(cornerRadius: WatchlistMetrics.rowRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WatchlistMetrics.rowRadius, style: .continuous)
                .strokeBorder(NoriTheme.border)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(watchlistAccessibilityLabel(item))
    }
}

/// Was VoiceOver vorliest.
///
/// „Bild" wäre die Vorgabe für eine Kachel, deren Inhalt ein Cover ist — und
/// damit wäre die ganze Merkliste für VoiceOver eine Folge gleich lautender
/// Bilder. Vorgelesen wird deshalb dasselbe, was daneben steht: Titel, Stand,
/// Staffel und Folge, Prozent.
func watchlistAccessibilityLabel(_ item: WatchlistItem) -> String {
    var parts = [item.title]
    switch item.watch.state {
    case .unseen:
        parts.append("noch nicht begonnen")
    case .seen:
        parts.append("komplett gesehen")
    case .started:
        parts.append("angefangen")
        if let season = item.watch.season, let episode = item.watch.episode {
            parts.append(season == "filme" ? "Filme, Folge \(episode)" : "Staffel \(season), Folge \(episode)")
        }
        parts.append("\(Int((item.watch.ratio * 100).rounded())) Prozent")
    }
    if !item.metaText.isEmpty { parts.append(item.metaText) }
    return parts.joined(separator: ", ")
}
