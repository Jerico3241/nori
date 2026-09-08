import SwiftUI

// Die gemeinsame Grundlage der Oberfläche: Radien, Abstände, Größen,
// Bewegungskurven und Haptik.
//
// Vorher setzte jede Ansicht ihre eigenen Zahlen — 10 hier, 14 dort, 16 im
// Kopfbereich, dreimal `easeOut` mit drei verschiedenen Dauern. Das ist keine
// Formsache: eine Kachel, die anders drückt als die daneben, fühlt sich
// kaputt an, auch wenn niemand sagen kann, warum.

// MARK: - Maße

enum NoriRadius {
    /// Folgenbild, Fortschrittskachel — alles, was kleiner als ein Poster ist.
    static let small: CGFloat = 10
    /// Poster und Katalogkacheln.
    static let card: CGFloat = 14
    /// Kopfbereich, große Flächen.
    static let hero: CGFloat = 18
    /// Flächen, die über dem Bild schweben.
    static let overlay: CGFloat = 20
}

enum NoriSpacing {
    /// Seitenrand aller Bildschirme. Eine einzige Zahl, damit Überschrift,
    /// Kachelreihe und Kopfbereich links auf derselben Linie beginnen.
    static let screen: CGFloat = 20
    /// Abstand zwischen zwei Kacheln einer Reihe.
    static let tile: CGFloat = 12
    /// Abstand zwischen zwei Abschnitten der Startseite.
    static let section: CGFloat = 28
}

enum NoriControl {
    /// Apples Mindestmaß für eine Trefferfläche. Nichts Antippbares darunter.
    static let hit: CGFloat = 44
    /// Symboltaste in einer Leiste.
    static let bar: CGFloat = 40
    /// Die Play/Pause-Taste in der Mitte.
    static let transport: CGFloat = 72
    /// Die beiden Sprungtasten daneben.
    static let transportSmall: CGFloat = 56
}

// MARK: - Bewegung

/// Alle Kurven der App an einer Stelle.
///
/// Ein- und Ausblenden sind absichtlich **unsymmetrisch**: lebendig hinein,
/// ruhig hinaus. Eine Feder auf dem Rückweg liest sich wie ein Fehler — das
/// Element wackelt beim Verschwinden nach.
enum NoriMotion {
    /// Kachel- und Knopfdruck. Kürzer als alles andere; ein Druck, der
    /// nachhängt, wirkt träge.
    static let press = Animation.easeOut(duration: 0.12)
    /// Zustandswechsel an einem einzelnen Element.
    static let micro = Animation.easeOut(duration: 0.18)
    /// Leisten, Kapseln, Menüs.
    static let ui = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// Die Bedienung des Players erscheint.
    static let controlsIn = Animation.spring(response: 0.34, dampingFraction: 0.78)
    /// Die Bedienung des Players verschwindet.
    static let controlsOut = Animation.easeOut(duration: 0.26)
    /// Inhaltswechsel im Kopfbereich, Wechsel zwischen Abschnitten.
    static let content = Animation.spring(response: 0.45, dampingFraction: 0.9)
    /// Der Regler unter dem Finger.
    static let scrub = Animation.interactiveSpring(response: 0.3, dampingFraction: 0.7)

    /// Die Kurve, sofern Bewegung erlaubt ist — sonst `nil`, was in SwiftUI
    /// „sofort, ohne Animation" bedeutet.
    static func allowed(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

extension View {
    /// Wie `.animation(_:value:)`, respektiert aber „Bewegung reduzieren".
    ///
    /// Die Systemeinstellung schaltet Bewegung ab, nicht Funktion: der
    /// Zustand wechselt weiterhin, nur ohne Weg dorthin.
    func noriAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(NoriAnimation(animation: animation, value: value))
    }
}

private struct NoriAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(NoriMotion.allowed(animation, reduceMotion: reduceMotion), value: value)
    }
}

// MARK: - Haptik

/// Dezentes haptisches Feedback.
///
/// Bewusst wenige Fälle: Merkliste, Folgenauswahl, Hosterwechsel,
/// Doppeltipp-Sprung. Jede Berührung mit einem Ruck zu quittieren macht das
/// Gerät nervös, nicht wertig.
enum NoriHaptic {
    case selection
    case success
    case light

    var feedback: SensoryFeedback {
        switch self {
        case .selection: return .selection
        case .success: return .success
        case .light: return .impact(weight: .light, intensity: 0.6)
        }
    }
}

extension View {
    /// Haptik, wenn sich `value` ändert.
    func noriHaptic<V: Equatable>(_ haptic: NoriHaptic, trigger value: V) -> some View {
        sensoryFeedback(haptic.feedback, trigger: value)
    }
}

// MARK: - Bausteine

/// Die Seitenpunkte unter dem Kopfbereich.
///
/// Der aktive Punkt wird zur Pille statt nur heller zu werden — auf einem
/// Bild ist eine Größenänderung deutlich besser zu erkennen als eine
/// Helligkeitsstufe.
struct NoriPageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0 ..< max(count, 0), id: \.self) { index in
                Capsule()
                    .fill(index == current ? NoriTheme.fg : NoriTheme.fg.opacity(0.25))
                    .frame(width: index == current ? 18 : 5, height: 5)
            }
        }
        .noriAnimation(NoriMotion.ui, value: current)
        .accessibilityHidden(true)
    }
}

/// Überschrift eines Abschnitts der Startseite — Titel mit Akzentbalken.
struct NoriRowHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Capsule()
                    .fill(NoriTheme.accent)
                    .frame(width: 30, height: 3)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, NoriSpacing.screen)
    }
}
