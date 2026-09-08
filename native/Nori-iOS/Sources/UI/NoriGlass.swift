import SwiftUI

// Liquid Glass für Nori.
//
// Adaptiert aus Shirox, `Shirox/Views/Shared/View+GlassChrome.swift`.
// Required Notice: Copyright 2026 xibrox (https://github.com/xibrox/Shirox)
// PolyForm Noncommercial License 1.0.0 — siehe THIRD-PARTY-NOTICES.md.
//
// Übernommen ist der Aufbau: eine einzige Stelle, an der `glassEffect`
// vorkommt, mit klassischem Rückfall darunter, und der Hinweis, dass Glas
// keine Trefferfläche mitbringt. Angepasst wurde die Signatur an Noris
// Farbwerte und die Einstellung, über die sich das Glas abschalten lässt.

/// Der Schlüssel, unter dem die Einstellung liegt. `@AppStorage` braucht ihn
/// an mehreren Stellen; eine Zeichenkette an drei Orten wäre ein Tippfehler
/// im Wartezustand.
enum NoriGlassSetting {
    static let key = "noriLiquidGlass"
}

extension View {
    /// Liquid Glass auf iOS 26 und neuer, sonst der klassische Hintergrund.
    ///
    /// Unterhalb von iOS 26 ist der Glaszweig unerreichbar; `off` gilt dann
    /// unabhängig von `enabled`.
    ///
    /// - Parameters:
    ///   - shape: Form, auf die Glas bzw. Hintergrund beschnitten wird.
    ///   - enabled: ob Glas gewünscht ist (aus der Einstellung).
    ///   - tint: optionale Einfärbung — für aktive Zustände.
    ///   - off: der Hintergrund ohne Glas.
    @ViewBuilder
    func noriGlass(
        _ shape: some Shape,
        enabled: Bool = true,
        tint: Color? = nil,
        off: some ShapeStyle
    ) -> some View {
        if enabled, #available(iOS 26.0, *) {
            // Glas ist im Gegensatz zu einer Hintergrundfüllung **kein**
            // trefferbarer Inhalt: ohne eigene `contentShape` nehmen nur die
            // gezeichneten Pixel der Beschriftung Tipper an, alles daneben
            // fällt auf die Ebene darunter durch. Im Player ist das die
            // Sprungfläche — der Knopf blendet dann die Bedienung aus,
            // statt zu tun, was daraufsteht.
            glassEffect(.regular.tint(tint).interactive(), in: shape)
                .contentShape(shape)
        } else {
            background(shape.fill(off))
        }
    }

    /// Der weiche Scrollrand von iOS 26; darunter wirkungslos.
    ///
    /// `.soft` blendet Inhalt beim Durchlaufen unter einer Leiste allmählich
    /// aus, wo der Standard `.hard` ihn an einer scharfen Kante abschneidet.
    @ViewBuilder
    func noriSoftScrollEdges(_ edges: Edge.Set = .all) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }
}

/// Eine Kapsel im Glasstil — die Grundform aller schwebenden Bedienelemente.
///
/// Ohne Glas ein getönter Grund mit feinem Rand: ein reines Material ohne
/// Kante verschwindet auf einem hellen Videobild.
struct NoriGlassChip<Content: View>: View {
    var active: Bool = false
    var tint: Color? = nil
    @ViewBuilder let content: () -> Content

    @AppStorage(NoriGlassSetting.key) private var glassEnabled = true

    var body: some View {
        content()
            .noriGlass(
                Capsule(),
                enabled: glassEnabled,
                tint: tint ?? (active ? NoriTheme.accent.opacity(0.55) : nil),
                off: active ? AnyShapeStyle(NoriTheme.accent.opacity(0.30)) : AnyShapeStyle(.white.opacity(0.18))
            )
            .overlay {
                if !glassEnabled || !NoriGlassChip.systemHasGlass {
                    Capsule().strokeBorder(.white.opacity(0.16))
                }
            }
    }

    /// Ob das laufende System überhaupt Glas kennt. Nur für den Rand
    /// gebraucht: Glas bringt seine eigene Kante mit, der Rückfall nicht.
    static var systemHasGlass: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}
