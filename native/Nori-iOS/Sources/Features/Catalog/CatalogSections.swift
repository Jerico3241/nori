import SwiftUI

// Die Abschnitte zwischen Kopfbereich und Raster: Discovery, Werkzeugzeile,
// aktive Filter — und die Zustände, in denen es nichts zu zeigen gibt.

// MARK: - Discovery

/// „Du weißt nicht, was du schauen willst?"
///
/// Der Knopf wählt aus der **aktuellen Ergebnismenge** und nicht aus dem
/// ganzen Katalog: Wer auf „Anime + Fantasy + abgeschlossen" gefiltert hat,
/// will keinen Vorschlag, der nichts davon erfüllt. Genau das macht den
/// Bereich zu einer Funktion statt zu einem Banner.
struct CatalogDiscovery: View {
    let count: Int
    let discover: () -> Void
    let hide: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            backdrop
            VStack(alignment: .leading, spacing: 6) {
                Text("Nori Discovery")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(NoriTheme.fg.opacity(0.62))
                Text("Du weißt nicht, was du schauen willst?")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(NoriTheme.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(NoriTheme.fg.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                actions
                    .padding(.top, 7)
            }
            .padding(20)
            .frame(maxWidth: 420, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: CatalogMetrics.discoveryRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CatalogMetrics.discoveryRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.07))
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
        .padding(.horizontal, CatalogMetrics.screen)
    }

    /// Die Zeile sagt, worüber tatsächlich gewürfelt wird. „Aus deinem
    /// aktuellen Filter" allein wäre eine Behauptung; mit der Zahl ist es
    /// eine Auskunft.
    private var subtitle: String {
        if count <= 0 { return "Sobald deine Filter etwas übrig lassen, sucht Nori hier einen Titel aus." }
        if count == 1 { return "Aus deiner aktuellen Auswahl — genau ein Titel." }
        return "Lass Nori einen Titel aus deinen aktuellen \(count) Ergebnissen auswählen."
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: discover) {
                Text("Titel entdecken")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(NoriTheme.bg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background { Capsule().fill(NoriTheme.accent) }
            }
            .buttonStyle(NoriPressStyle(scale: 0.95))
            .disabled(count <= 0)
            .opacity(count <= 0 ? 0.5 : 1)

            Button(action: hide) {
                Text("Ausblenden")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NoriTheme.fg.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background { Capsule().fill(NoriTheme.elevated.opacity(0.7)) }
                    .overlay { Capsule().strokeBorder(NoriTheme.border) }
            }
            .buttonStyle(NoriPressStyle(scale: 0.95))
        }
    }

    /// Der Hintergrund: ein Farbverlauf mit zwei Lichtern, kein Bild.
    ///
    /// Ein echtes Artwork wäre hier falsch — es zeigte einen bestimmten
    /// Titel, und der Bereich verspricht gerade, ihn noch nicht zu kennen.
    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.14, blue: 0.23),
                    Color(red: 0.18, green: 0.15, blue: 0.25),
                    Color(red: 0.03, green: 0.06, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [NoriTheme.highlight.opacity(0.34), .clear],
                center: UnitPoint(x: 0.86, y: 0.16),
                startRadius: 2,
                endRadius: 190
            )
            RadialGradient(
                colors: [Color(red: 0.61, green: 0.30, blue: 0.57).opacity(0.28), .clear],
                center: UnitPoint(x: 0.6, y: 0.3),
                startRadius: 2,
                endRadius: 220
            )
            LinearGradient(
                colors: [Color.black.opacity(0.82), Color.black.opacity(0.28), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Werkzeugzeile

/// Ergebnisüberschrift links, Sortierung und Rasterdichte rechts.
struct CatalogToolbar: View {
    let headline: String
    let count: Int
    @Binding var sort: CatalogSort
    @Binding var density: CatalogDensity

    private var countLabel: String {
        count == 1 ? "1 Ergebnis" : "\(count) Ergebnisse"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(NoriTheme.fg)
                    .lineLimit(1)
                Text(countLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(NoriTheme.muted)
            }
            Spacer(minLength: 6)
            sortMenu
            densityButton
        }
        .padding(.horizontal, CatalogMetrics.screen)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sortierung", selection: $sort) {
                ForEach(CatalogSort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            CatalogPill {
                HStack(spacing: 4) {
                    Text(sort.pillLabel)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
        }
        .accessibilityLabel("Sortierung: \(sort.label)")
    }

    /// Ein Knopf und kein Menü: Es gibt genau zwei Dichten, und ein Menü für
    /// zwei Einträge ist ein Umweg.
    private var densityButton: some View {
        Button {
            withAnimation(NoriMotion.ui) {
                density = density == .comfortable ? .compact : .comfortable
            }
        } label: {
            CatalogPill(square: true) {
                Image(systemName: density.symbol)
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .buttonStyle(NoriPressStyle(scale: 0.94))
        .accessibilityLabel("Rasterdichte, aktuell \(density.label)")
    }
}

// MARK: - Aktive Filter

/// Die Tags unter der Werkzeugzeile.
///
/// Jeder Tag lässt sich antippen und entfernt dann genau seinen Filter. Sie
/// nur anzuzeigen wäre die halbe Sache: Wer sieht, warum die Liste kurz ist,
/// will es an Ort und Stelle ändern können.
struct CatalogActiveFilters: View {
    let tags: [CatalogFilterTag]
    let onRemove: (CatalogFilterTag) -> Void
    let onClear: () -> Void

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(tags) { tag in
                        CatalogTag(label: tag.label) { onRemove(tag) }
                    }
                    Button(action: onClear) {
                        Text("Alle entfernen")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(NoriTheme.muted)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .overlay { Capsule().strokeBorder(NoriTheme.border) }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, CatalogMetrics.screen)
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()
        }
    }
}

/// Ein einzelner aktiver Filter — Beschriftung plus die Angabe, was er
/// betrifft. Ohne das wüsste der Tag nicht, was er beim Antippen abräumen
/// soll.
struct CatalogFilterTag: Identifiable, Hashable {
    enum Kind: Hashable {
        case mediaType
        case status
        case genre(String)
        case language
        case years
    }

    let kind: Kind
    let label: String
    var id: String { label }

    /// Die Tags zu einem Filterstand.
    static func all(_ filters: CatalogFilters, fullYearRange: ClosedRange<Int>?) -> [CatalogFilterTag] {
        var out: [CatalogFilterTag] = []
        if let mediaType = filters.mediaType {
            out.append(CatalogFilterTag(kind: .mediaType, label: mediaType.label))
        }
        if let status = filters.status {
            out.append(CatalogFilterTag(kind: .status, label: status.label))
        }
        for genre in filters.genres.sorted() {
            out.append(CatalogFilterTag(kind: .genre(genre), label: genre))
        }
        if let language = filters.language {
            out.append(CatalogFilterTag(kind: .language, label: language.label))
        }
        if let years = filters.years, years != fullYearRange {
            let label = years.lowerBound == years.upperBound
                ? String(years.lowerBound)
                : "\(years.lowerBound)–\(years.upperBound)"
            out.append(CatalogFilterTag(kind: .years, label: label))
        }
        return out
    }

    /// Denselben Filter aus einem Stand herausnehmen.
    func removed(from filters: CatalogFilters) -> CatalogFilters {
        var next = filters
        switch kind {
        case .mediaType: next.mediaType = nil
        case .status: next.status = nil
        case .genre(let name): next.genres.remove(name)
        case .language: next.language = nil
        case .years: next.years = nil
        }
        return next
    }
}

// MARK: - Zustände

/// Null Treffer.
///
/// Mit dem Weg zurück, nicht nur mit der Feststellung: Eine leere Seite, die
/// „Keine Treffer" sagt und es dabei belässt, lässt den Betrachter in einer
/// Sackgasse stehen.
struct CatalogEmptyState: View {
    let hasQuery: Bool
    let hasFilters: Bool
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(NoriTheme.muted)
                .padding(.bottom, 2)
            Text("Keine Treffer")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(NoriTheme.fg)
            Text(hint)
                .font(.system(size: 13))
                .foregroundStyle(NoriTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if hasFilters || hasQuery {
                Button(action: reset) {
                    Text(hasFilters ? "Filter zurücksetzen" : "Suche löschen")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NoriTheme.bg)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background { Capsule().fill(NoriTheme.accent) }
                }
                .buttonStyle(NoriPressStyle(scale: 0.96))
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 44)
    }

    private var hint: String {
        if hasQuery && hasFilters { return "Passe deine Suche oder deine Filter an." }
        if hasQuery { return "Passe deine Suche an — Nori sucht in Titeln, Originaltiteln, Genres und Jahren." }
        if hasFilters { return "Diese Filterkombination lässt nichts übrig." }
        return "Der Katalog ist noch leer. Zieh die Liste nach unten, um ihn zu laden."
    }
}

/// Der erste Aufbau, solange noch kein Titel dasteht.
///
/// Ein Umriss der späteren Seite statt eines kreisenden Rädchens: So springt
/// das Layout nicht, wenn die Daten eintreffen, und es ist von Anfang an
/// erkennbar, was dort erscheinen wird.
struct CatalogSkeleton: View {
    let columns: Int
    let density: CatalogDensity

    private var grid: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: density.columnSpacing, alignment: .top),
            count: max(columns, 1)
        )
    }

    var body: some View {
        LazyVGrid(columns: grid, spacing: density.rowSpacing) {
            ForEach(0 ..< (columns * 4), id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: density.posterRadius, style: .continuous)
                        .fill(NoriTheme.elevated)
                        .aspectRatio(2 / 3, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 4).fill(NoriTheme.elevated).frame(height: 12)
                    RoundedRectangle(cornerRadius: 4).fill(NoriTheme.elevated).frame(width: 60, height: 9)
                }
            }
        }
        .padding(.horizontal, CatalogMetrics.screen)
        .redacted(reason: .placeholder)
        .accessibilityLabel("Katalog wird geladen")
    }
}

/// Die Meldung, wenn beide Kataloge nicht geladen werden konnten.
struct CatalogErrorBanner: View {
    let text: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(text, systemImage: "wifi.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.red)
            Button("Erneut laden", action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(NoriTheme.surface)
        }
        .padding(.horizontal, CatalogMetrics.screen)
    }
}
