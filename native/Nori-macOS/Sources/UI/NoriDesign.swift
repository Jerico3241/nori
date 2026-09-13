import SwiftUI

// Die gemeinsame Grundlage der Oberfläche: Radien, Abstände, Größen und
// Bewegungskurven. Haptik gibt es hier bewusst nicht — auf dem Schreibtisch
// gibt es kein Gerät in der Hand.
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
    /// Mindestmaß einer Schaltfläche, auch mit Zeiger.
    static let hit: CGFloat = 32
    /// Symboltaste in einer Leiste.
    static let bar: CGFloat = 40
    /// Zeigergesteuerte Flächen dürfen kleiner sein als Fingerziele.
    static let pointer: CGFloat = 28
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
    /// Inhaltswechsel im Kopfbereich, Wechsel zwischen Abschnitten.
    static let content = Animation.spring(response: 0.45, dampingFraction: 0.9)
    /// Der Regler unter dem Zeiger.
    static let scrub = Animation.interactiveSpring(response: 0.3, dampingFraction: 0.7)
    /// Ein Element unter dem Mauszeiger.
    static let hover = Animation.easeOut(duration: 0.14)

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

// MARK: - Ladezustand

/// Der Rahmen eines Ladegerüsts: nicht bedienbar, für VoiceOver ein Satz.
///
/// Auf dem Mac stand beim ersten Laden ein `ProgressView("… wird geladen")`
/// mitten im leeren Fenster, und beim Eintreffen der Daten sprang die Fläche
/// von einem Rädchen auf ein volles Raster. Die Gerüste halten stattdessen den
/// Platz frei, den Kacheln und Zeilen später einnehmen. Ohne Schimmer: Bewegung
/// sagt hier nichts, was die Form nicht schon sagt, und über ein großes
/// Fenster gezogen kostet sie Leistung.
struct NoriSkeletonGroup<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .redacted(reason: .placeholder)
            .foregroundStyle(NoriTheme.elevated)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

/// Eine Posterkachel im Gerüst — dieselben Maße wie `PosterCell` und
/// `NoriPosterCell`: Poster 2 : 3, zwei reservierte Titelzeilen, eine Zeile
/// darunter.
struct NoriPosterSkeleton: View {
    var width: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NoriTheme.elevated)
                .aspectRatio(2 / 3, contentMode: .fit)
            Text("Titel eines Eintrags")
                .font(.callout.weight(.medium))
                .lineLimit(2, reservesSpace: true)
            Text("Genre")
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// Eine Listenzeile im Gerüst — Miniatur, Titel, Nebenzeile.
struct NoriRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(NoriTheme.elevated)
                .frame(width: 34, height: 51)
            VStack(alignment: .leading, spacing: 3) {
                Text("Titel eines Eintrags")
                    .font(.body.weight(.medium))
                Text("Nebenzeile")
                    .font(.caption)
            }
            Spacer(minLength: 8)
            Text("S1 · F1")
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
