import SwiftUI

/// Der Grund, auf dem Kalender und „Mehr" stehen.
///
/// Noris Basisfarbe mit zwei sehr weichen Lichtern darüber — eines oben rechts
/// in Blau, eines links darunter in Violett. Beide Vorlagen (`nori-calendar-v1`
/// und `nori-settings-v1`) setzen genau diese zwei Lichter; ohne sie wirkt eine
/// Seite, die nur aus Karten besteht, wie ein Formular auf schwarzem Papier.
///
/// Die Deckkraft ist bewusst niedrig: der Verlauf soll den Karten Tiefe geben,
/// nicht selbst auffallen. Startseite und Detailseite bringen ihr Licht aus dem
/// Artwork mit und brauchen ihn deshalb nicht — er gehört den beiden
/// Bildschirmen, die kein großes Bild haben.
struct NoriBackdrop: View {
    var body: some View {
        NoriTheme.bg
            .overlay(alignment: .topTrailing) {
                glow(NoriBackdrop.blue)
                    .offset(x: 70, y: -150)
            }
            .overlay(alignment: .topLeading) {
                glow(NoriBackdrop.violet)
                    .offset(x: -120, y: 60)
            }
            .ignoresSafeArea()
    }

    private func glow(_ color: Color) -> some View {
        // Ein radialer Verlauf, der in Durchsichtigkeit ausläuft — kein Kreis
        // mit weichem Rand. Letzterer zeigt auf dunklem Grund eine sichtbare
        // Kante, weil der Übergang irgendwo enden muss.
        RadialGradient(
            gradient: Gradient(colors: [color, color.opacity(0)]),
            center: .center,
            startRadius: 0,
            endRadius: 260
        )
        .frame(width: 520, height: 520)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    private static let blue = Color(red: 0.28, green: 0.51, blue: 0.79).opacity(0.16)
    private static let violet = Color(red: 0.43, green: 0.25, blue: 0.53).opacity(0.11)
}

/// Ein Bildschirm auf `NoriBackdrop`, mit Noris Vordergrundfarbe.
///
/// Das Gegenstück zu `NoriScreen`, das die flache Basisfarbe setzt. Getrennt
/// gehalten, damit der Verlauf nicht unter Ansichten gerät, die ihr eigenes
/// Licht mitbringen.
struct NoriGradientScreen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NoriBackdrop())
            .foregroundStyle(NoriTheme.fg)
    }
}

// MARK: - Karten

/// Maße, die Kalender und „Mehr" teilen.
///
/// Beide Vorlagen arbeiten mit deutlich weicheren Ecken als die Rasteransichten
/// — 22 Punkte für eine Gruppe, 20 für eine einzelne Karte. Das ist kein
/// Selbstzweck: eine Einstellungsgruppe ist eine große, ruhige Fläche, und ein
/// Radius von 14 lässt sie kantig wirken neben den Postern, die daneben im
/// Katalog stehen.
enum NoriPanel {
    /// Eine Gruppe mehrerer Zeilen.
    static let groupRadius: CGFloat = 22
    /// Eine einzelne hervorgehobene Karte.
    static let cardRadius: CGFloat = 20
    /// Die große Karte am Kopf einer Seite.
    static let heroRadius: CGFloat = 24
    /// Mindesthöhe einer Zeile. Über Apples 44 Punkten, weil die Zeilen eine
    /// zweite, kleinere Textzeile tragen.
    static let rowHeight: CGFloat = 58
    /// Das getönte Quadrat, in dem das Symbol einer Zeile steht.
    static let iconSize: CGFloat = 32
    /// Platz unter dem letzten Abschnitt — die Tab-Leiste schwebt darüber.
    static let bottom: CGFloat = 96
}

extension View {
    /// Der Kartengrund von Kalender und „Mehr": getönte Fläche mit feinem Rand.
    ///
    /// Kein `Material`: ein durchscheinender Grund über einem Verlauf nimmt
    /// dessen Helligkeit an, und die Karten einer Seite sähen dann je nach Ort
    /// unterschiedlich hell aus. Die Flächen sollen gleich sein, schweben soll
    /// nur, was Apple selbst zeichnet — Tab-Leiste, Sheets, Menüs.
    func noriPanel(radius: CGFloat = NoriPanel.groupRadius) -> some View {
        background(NoriTheme.elevated.opacity(0.72), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(NoriTheme.border)
            }
    }
}
