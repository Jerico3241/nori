import SwiftUI

// Das Raster und seine Kachel.

/// Das Posterraster.
///
/// Zwei Spalten auf dem iPhone, drei im kompakten Raster, auf breiteren
/// Fenstern mehr — die Zahl ergibt sich aus der Breite (`CatalogDensity`).
///
/// Gerendert wird in Ladungen: `LazyVGrid` baut zwar nur sichtbare Zeilen,
/// legt aber für jeden Eintrag eine Identität an, und der Katalog hat
/// zehntausend. Nachgeladen wird, sobald die letzte Reihe der aktuellen
/// Ladung in Sicht kommt — bis dahin gibt es weder Ansichten noch Arbeit.
struct CatalogGrid: View {
    let entries: [CatalogEntry]
    let density: CatalogDensity
    let columns: Int
    /// Ob „ANIME"/„SERIE" auf die Kachel gehört. Im gemischten Raster ja;
    /// sobald auf einen Typ gefiltert ist, stünde auf jeder Kachel dasselbe.
    let showsKind: Bool
    /// Der zuletzt per „Titel entdecken" gezogene Eintrag. Er bekommt kurz
    /// einen Rahmen, sonst wäre nach dem Scrollen nicht erkennbar, welche
    /// Kachel gemeint ist.
    let highlighted: String?
    let now: Date

    @State private var shown = CatalogMetrics.batch

    private var visible: ArraySlice<CatalogEntry> {
        entries.prefix(shown)
    }

    private var grid: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: density.columnSpacing, alignment: .top),
            count: max(columns, 1)
        )
    }

    var body: some View {
        LazyVGrid(columns: grid, spacing: density.rowSpacing) {
            ForEach(visible) { entry in
                link(entry)
                    .id(entry.id)
            }
        }
        .padding(.horizontal, CatalogMetrics.screen)
        .overlay(alignment: .bottom) { sentinel }
        // Wechselt die Ergebnisliste, beginnt das Nachladen von vorn — sonst
        // stünden nach einer neuen Suche dreihundert Kacheln bereit, von
        // denen niemand je eine sieht.
        .onChange(of: entries.count) { _, _ in shown = CatalogMetrics.batch }
        .onChange(of: density) { _, _ in shown = CatalogMetrics.batch }
    }

    /// Ein unsichtbarer Fühler am unteren Rand der geladenen Ladung.
    @ViewBuilder
    private var sentinel: some View {
        if shown < entries.count {
            Color.clear
                .frame(height: 1)
                .onAppear { shown = min(shown + CatalogMetrics.batch, entries.count) }
        }
    }

    private func link(_ entry: CatalogEntry) -> some View {
        NoriSeriesLink(
            slug: entry.slug,
            titleHint: entry.title,
            scaleOnPress: true,
            provider: entry.provider
        ) {
            CatalogPosterCard(
                entry: entry,
                density: density,
                showsKind: showsKind,
                highlighted: highlighted == entry.id,
                now: now
            )
        }
    }
}

/// Eine Kachel: Poster, Titel, eine Zeile Eckdaten.
///
/// Der Titel steht **unter** dem Bild, wie auf der Vorlage und wie auf der
/// Startseite. Unter das Poster gehören genau zwei Zeilen — Titel und
/// „Jahr · Genre · Status". Alles Weitere steht auf der Detailseite; eine
/// Kachel, die fünf Angaben quetscht, liest sich schlechter als eine, die
/// drei zeigt.
struct CatalogPosterCard: View {
    let entry: CatalogEntry
    let density: CatalogDensity
    let showsKind: Bool
    let highlighted: Bool
    let now: Date

    /// Im kompakten Raster nur **ein** Abzeichen.
    ///
    /// Nebeneinander brauchen „KOMPLETT" und „ANIME" mehr Platz, als eine
    /// 115 Punkte breite Kachel hat; das zweite würde am Posterrand
    /// abgeschnitten. Weggelassen wird das Typ-Abzeichen — es benennt nur,
    /// während das erste etwas aussagt.
    private var badges: [CatalogBadge] {
        let all = CatalogRanking.badges(for: entry, now: now, showsKind: showsKind)
        return density == .compact ? Array(all.prefix(1)) : all
    }

    private var meta: String {
        entry.metaLine(status: density == .comfortable)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 6 : 8) {
            poster
            Text(entry.title)
                .font(.system(size: density == .compact ? 12 : 14, weight: .semibold))
                .foregroundStyle(NoriTheme.fg)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(meta)
                .font(.system(size: density == .compact ? 9.5 : 11))
                .foregroundStyle(NoriTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var poster: some View {
        PosterTile(
            title: entry.title,
            slug: entry.slug,
            kind: entry.provider,
            cornerRadius: density.posterRadius
        )
        .overlay(alignment: .topLeading) { badgeStack }
        .overlay(alignment: .bottomTrailing) { rating }
        .overlay { ring }
    }

    @ViewBuilder
    private var badgeStack: some View {
        if !badges.isEmpty {
            HStack(spacing: 4) {
                ForEach(badges, id: \.self) { badge in
                    CatalogBadgeView(badge: badge)
                }
            }
            .padding(7)
        }
    }

    @ViewBuilder
    private var rating: some View {
        if let stars = entry.stars {
            CatalogRatingBadge(stars: stars)
                .padding(7)
        }
    }

    /// Der Rahmen nach „Titel entdecken".
    @ViewBuilder
    private var ring: some View {
        if highlighted {
            RoundedRectangle(cornerRadius: density.posterRadius, style: .continuous)
                .strokeBorder(NoriTheme.highlight, lineWidth: 2.5)
                .shadow(color: NoriTheme.highlight.opacity(0.5), radius: 10)
        }
    }

    /// „Echoes of Yoruka, Anime, Fantasy, Bewertung 4,8 von 5" statt „Bild".
    private var spoken: String {
        var parts = [entry.title, entry.mediaType.label]
        if let year = entry.year { parts.append(String(year)) }
        parts.append(contentsOf: entry.genres.prefix(2))
        if entry.status.isKnown { parts.append(entry.status.label) }
        if let stars = entry.stars {
            parts.append("Bewertung \(String(format: "%.1f", stars)) von 5")
        }
        for badge in badges {
            if case .kind = badge { continue }
            parts.append(badge.spoken)
        }
        return parts.joined(separator: ", ")
    }
}
