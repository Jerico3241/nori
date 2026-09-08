import SwiftUI

/// Der Fortschrittsregler.
///
/// Ein eigener Regler statt `Slider`: der Systemregler bringt eine eigene Spur
/// und einen großen Griff mit. Hinter ihm lag zusätzlich die Pufferanzeige —
/// sichtbar waren dadurch zwei Spuren übereinander und ein Griff, der über den
/// linken Rand hinausstand.
///
/// Drei Spuren übereinander: Grund, Puffer, Abgespieltes. Beim Ziehen wächst
/// die Spur, der Griff wird größer, und die Zeiten treten hervor — dieselbe
/// Rückmeldung wie in Shirox, dort über eine reine Skalierung der ganzen
/// Gruppe gelöst, hier über die tatsächlichen Maße, damit der Text nicht
/// mitverzerrt wird.
struct PlayerProgressSlider: View {
    let position: Double
    let duration: Double
    let buffered: Double

    /// Läuft während des Ziehens mit — der Player folgt dem Finger, statt
    /// erst beim Loslassen zu springen.
    var onScrub: (Double) -> Void
    /// Der endgültige, genaue Sprung beim Loslassen.
    var onSeek: (Double) -> Void
    /// Meldet Anfang und Ende des Ziehens, damit die Bedienung so lange
    /// stehen bleibt.
    var onScrubbing: (Bool) -> Void

    @AppStorage(NoriGlassSetting.key) private var glass = true

    /// Während des Ziehens gilt der lokale Wert. Ohne das zöge die laufende
    /// Wiedergabe den Regler unter dem Finger weg.
    @State private var dragging = false
    @State private var dragValue: Double = 0

    private var shown: Double { dragging ? dragValue : position }
    private var total: Double { duration.isFinite && duration > 0 ? duration : 0 }
    private var trackHeight: CGFloat { dragging ? 8 : 5 }
    private var knob: CGFloat { dragging ? 17 : 11 }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let width = geo.size.width
                let played = total > 0 ? min(max(shown / total, 0), 1) : 0
                let loaded = total > 0 ? min(max(buffered / total, 0), 1) : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.clear)
                        .frame(height: trackHeight)
                        .noriGlass(Capsule(), enabled: glass, off: Color.white.opacity(0.22))
                    Capsule()
                        .fill(.white.opacity(0.4))
                        .frame(width: width * loaded, height: trackHeight)
                    Capsule()
                        .fill(NoriTheme.accent)
                        .frame(width: width * played, height: trackHeight)
                    Circle()
                        .fill(.white)
                        .frame(width: knob, height: knob)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .offset(x: width * played - knob / 2)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                // Die Trefferfläche ist die ganze Höhe, nicht die fünf Punkte
                // der Spur.
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard total > 0, width > 0 else { return }
                            if !dragging {
                                dragging = true
                                onScrubbing(true)
                            }
                            let ratio = min(max(Double(value.location.x / width), 0), 1)
                            dragValue = ratio * total
                            onScrub(dragValue)
                        }
                        .onEnded { _ in
                            guard total > 0 else {
                                dragging = false
                                onScrubbing(false)
                                return
                            }
                            onSeek(dragValue)
                            dragging = false
                            onScrubbing(false)
                        }
                )
            }
            .frame(height: 26)

            HStack {
                Text(formatClock(shown))
                Spacer()
                Text(total > 0 ? "−" + formatClock(max(total - shown, 0)) : "live")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(dragging ? 1 : 0.75))
        }
        .noriAnimation(NoriMotion.scrub, value: dragging)
        // Die Position selbst nicht animieren: sie ändert sich viermal pro
        // Sekunde, eine Feder darauf ließe den Regler dauerhaft hinterherlaufen.
        .accessibilityElement()
        .accessibilityLabel("Fortschritt")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard total > 0 else { return }
            let step = max(total / 20, 10)
            switch direction {
            case .increment: onSeek(min(position + step, total))
            case .decrement: onSeek(max(position - step, 0))
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        guard total > 0 else { return "Live" }
        return "\(formatClock(shown)) von \(formatClock(total))"
    }
}
