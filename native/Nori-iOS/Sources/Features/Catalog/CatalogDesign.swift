import SwiftUI

// Die Bausteine des Katalogs: Maße, Pillen, Tags, Abzeichen.
//
// Die Zahlen stammen aus `nori-catalog-v2.html`. Wo Vorlage und Nori-System
// auseinanderlaufen, gewinnt das System — dieselbe Regel wie beim Umbau der
// Startseite: Der Seitenrand bleibt `NoriSpacing.screen`, damit Startseite,
// Katalog und Detailseite links auf derselben Linie beginnen, und Farben
// kommen aus `NoriTheme` statt als Zahlenwerte aus dem CSS.

enum CatalogMetrics {
    /// Seitenrand — derselbe wie überall in Nori.
    static let screen: CGFloat = NoriSpacing.screen

    /// Höhe von Suchfeld und Filterknopf.
    static let search: CGFloat = 50
    /// Größe der runden Knöpfe im Kopfbereich.
    static let circle: CGFloat = 44

    /// Eckenradius einer Posterkachel im komfortablen Raster.
    static let poster: CGFloat = 18
    /// Derselbe Radius im kompakten Raster — kleinere Flächen vertragen
    /// weniger Rundung, sonst wirkt die Kachel wie eine Kapsel.
    static let posterCompact: CGFloat = 14

    /// Abstände im Raster: Zeilen deutlich weiter als Spalten, weil unter
    /// jeder Kachel zwei Textzeilen stehen.
    static let gridRow: CGFloat = 20
    static let gridColumn: CGFloat = 11
    static let gridRowCompact: CGFloat = 16
    static let gridColumnCompact: CGFloat = 8

    /// Größte Breite einer Kachel je Dichte. Sie bestimmt auf breiten
    /// Fenstern die Spaltenzahl: Poster über eine iPad-Breite zu ziehen
    /// ergäbe Plakate, keine Übersicht.
    static let posterMaxWidth: CGFloat = 210
    static let posterMaxWidthCompact: CGFloat = 148

    static let discoveryRadius: CGFloat = 22
    static let sheetCorner: CGFloat = 28

    /// Platz unter der letzten Kachelreihe.
    ///
    /// Die Tab-Leiste schwebt über dem Inhalt; ohne Reserve endet die letzte
    /// Reihe dahinter. Die tatsächliche Sicherheitszone kommt vom System
    /// dazu — ein iPhone ohne Home-Taste hat mehr Rand als eines mit.
    static let bottom: CGFloat = 96

    /// Wie viele Kacheln auf einmal gebaut werden.
    ///
    /// `LazyVGrid` baut zwar nur sichtbare Zeilen, legt aber für jeden
    /// Eintrag eine Identität an. Bei zehntausend Titeln ist das spürbar,
    /// und niemand scrollt so weit. Nachgeladen wird, sobald das Ende der
    /// aktuellen Ladung in Sicht kommt.
    static let batch = 120
}

/// Wie dicht das Raster steht.
///
/// Eigener Typ statt `NoriLayout`: Der Katalog kennt keine Listenansicht mehr
/// — er zeigt Poster, in zwei Dichten. `NoriLayout` bleibt für Kalender und
/// Merkliste, wo Liste gegen Kacheln die richtige Frage ist.
enum CatalogDensity: String, CaseIterable, Identifiable {
    case comfortable
    case compact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .comfortable: return "Große Kacheln"
        case .compact: return "Kompakt"
        }
    }

    var symbol: String {
        switch self {
        case .comfortable: return "square.grid.2x2"
        case .compact: return "square.grid.3x3"
        }
    }

    var posterRadius: CGFloat {
        switch self {
        case .comfortable: return CatalogMetrics.poster
        case .compact: return CatalogMetrics.posterCompact
        }
    }

    var maxPosterWidth: CGFloat {
        switch self {
        case .comfortable: return CatalogMetrics.posterMaxWidth
        case .compact: return CatalogMetrics.posterMaxWidthCompact
        }
    }

    var rowSpacing: CGFloat {
        switch self {
        case .comfortable: return CatalogMetrics.gridRow
        case .compact: return CatalogMetrics.gridRowCompact
        }
    }

    var columnSpacing: CGFloat {
        switch self {
        case .comfortable: return CatalogMetrics.gridColumn
        case .compact: return CatalogMetrics.gridColumnCompact
        }
    }

    /// Spalten für eine gegebene Breite.
    ///
    /// Auf dem iPhone zwei beziehungsweise drei, wie auf der Vorlage. Auf
    /// einem iPad wächst die **Zahl** und nicht die Kachel: Zwei Poster über
    /// 1300 Punkte wären zwei Plakate, und der Katalog soll übersehbar sein.
    func columns(for width: CGFloat) -> Int {
        let usable = max(width - 2 * CatalogMetrics.screen, 1)
        let minimum = self == .compact ? 3 : 2
        let fitting = Int(floor((usable + columnSpacing) / (maxPosterWidth + columnSpacing)))
        return max(minimum, fitting)
    }
}

// MARK: - Pillen und Tags

/// Eine Pille der Schnellfilterleiste.
///
/// Aktiv ist sie hell gefüllt mit dunkler Schrift — der stärkste Kontrast,
/// den die dunkle Oberfläche hergibt, und derselbe, den die Vorlage setzt.
struct CatalogChip: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(active ? NoriTheme.bg : NoriTheme.fg.opacity(0.72))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background {
                    Capsule().fill(active ? NoriTheme.accent : NoriTheme.elevated.opacity(0.9))
                }
                .overlay {
                    if !active { Capsule().strokeBorder(NoriTheme.border) }
                }
        }
        .buttonStyle(NoriPressStyle(scale: 0.94))
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

/// Eine Pille der Werkzeugzeile über dem Raster — Sortierung, Rasterdichte.
struct CatalogPill<Content: View>: View {
    var square: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(NoriTheme.fg.opacity(0.8))
            .frame(height: 36)
            .frame(minWidth: square ? 36 : 0)
            .padding(.horizontal, square ? 0 : 12)
            .background { Capsule().fill(NoriTheme.elevated.opacity(0.85)) }
            .overlay { Capsule().strokeBorder(NoriTheme.border) }
    }
}

/// Ein aktiver Filter über dem Raster — „Warum sehe ich diese Ergebnisse?"
struct CatalogTag: View {
    let label: String
    let remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
            if remove != nil {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(NoriTheme.highlight)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background { Capsule().fill(NoriTheme.highlightSoft) }
        .overlay { Capsule().strokeBorder(NoriTheme.highlight.opacity(0.22)) }
        .contentShape(Capsule())
        .onTapGesture { remove?() }
        .accessibilityLabel(remove == nil ? label : "Filter \(label) entfernen")
    }
}

// MARK: - Abzeichen

/// Ein Abzeichen auf dem Poster.
///
/// Was darauf stehen darf, entscheidet `CatalogRanking.badges` — hier wird
/// nur gezeichnet. „NEU" ist hell gefüllt, weil es das einzige Abzeichen ist,
/// das zum Hinsehen auffordert; die übrigen benennen nur.
struct CatalogBadgeView: View {
    let badge: CatalogBadge

    private var filled: Bool {
        if case .fresh = badge { return true }
        return false
    }

    private var tinted: Bool {
        if case .complete = badge { return true }
        return false
    }

    var body: some View {
        Text(badge.label)
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(foreground)
            // Ohne beides bricht „KOMPLETT" im kompakten Raster mitten im
            // Wort um — die Kachel ist dort rund 115 Punkte breit, und ein
            // Abzeichen, das sich zwei Zeilen nimmt, sieht aus wie ein
            // Darstellungsfehler.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(background)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(filled ? 0 : 0.12))
            }
    }

    private var foreground: Color {
        if filled { return NoriTheme.bg }
        if tinted { return Color(red: 0.74, green: 0.95, blue: 0.85) }
        return NoriTheme.fg
    }

    private var background: Color {
        if filled { return NoriTheme.accent }
        if tinted { return Color(red: 0.07, green: 0.22, blue: 0.18).opacity(0.85) }
        return Color.black.opacity(0.68)
    }
}

/// Die Bewertung unten rechts auf dem Poster.
///
/// Fünf-Sterne-Skala, wie auf der Detailseite. Zwei Skalen in einer App wären
/// eine Falle: „8,7" auf der einen Seite und „4,4" auf der anderen sähe nach
/// einem Fehler aus, obwohl es derselbe Wert ist.
struct CatalogRatingBadge: View {
    let stars: Double

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 7.5))
            Text(String(format: "%.1f", stars))
                .font(.system(size: 10, weight: .heavy))
        }
        .foregroundStyle(NoriTheme.star)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.66))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.white.opacity(0.1))
        }
    }
}
