import SwiftUI

// Liquid Glass für Nori auf dem Mac.
//
// Adaptiert aus Shirox, `Shirox/Views/Shared/View+GlassChrome.swift`.
// Required Notice: Copyright 2026 xibrox (https://github.com/xibrox/Shirox)
// PolyForm Noncommercial License 1.0.0 — siehe THIRD-PARTY-NOTICES.md.
//
// Gleiche Aufgabe wie die iOS-Fassung, nur gegen macOS 26 statt iOS 26
// geprüft: eine einzige Stelle, an der `glassEffect` vorkommt, mit
// klassischem Rückfall darunter.
//
// Das Deployment-Target ist macOS 14. Der Glaszweig steht deshalb hinter
// `#available`; übersetzt wird er trotzdem, weshalb der Build ein SDK ab
// Xcode 26 braucht — `tools/require-xcode.sh 26` erzwingt das in der CI.

enum NoriGlassSetting {
    static let key = "noriLiquidGlass"
}

extension View {
    /// Liquid Glass auf macOS 26 und neuer, sonst der klassische Hintergrund.
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
        if enabled, #available(macOS 26.0, *) {
            // Glas bringt keine Trefferfläche mit: ohne eigene
            // `contentShape` nehmen nur die gezeichneten Pixel der
            // Beschriftung Klicks an.
            glassEffect(.regular.tint(tint).interactive(), in: shape)
                .contentShape(shape)
        } else {
            background(shape.fill(off))
        }
    }

    /// Der weiche Scrollrand von macOS 26; darunter wirkungslos.
    @ViewBuilder
    func noriSoftScrollEdges(_ edges: Edge.Set = .all) -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }
}

/// Eine Kapsel im Glasstil.
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
                off: active ? AnyShapeStyle(NoriTheme.accent.opacity(0.25)) : AnyShapeStyle(NoriTheme.elevated)
            )
            .overlay {
                if !glassEnabled || !NoriGlassChip.systemHasGlass {
                    Capsule().strokeBorder(NoriTheme.border)
                }
            }
    }

    static var systemHasGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}
