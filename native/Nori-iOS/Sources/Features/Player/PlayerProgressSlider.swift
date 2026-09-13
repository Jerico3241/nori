import SwiftUI

/// Stelle, Dauer und Puffer der laufenden Wiedergabe.
///
/// ## Warum ein eigenes Objekt
///
/// Die Stelle stand vorher als `@State` im `PlayerScreen`. Der Zeitbeobachter
/// setzt sie viermal pro Sekunde — und jedes Setzen zeichnete den **ganzen**
/// Player neu: Bedienung, Menüs, Hoster- und Sprachlisten (samt Sortierung),
/// auch dann, wenn die Bedienung ausgeblendet war und niemand hinsah.
///
/// Jetzt lesen genau die Ansichten die Stelle, die sie zeigen — der Regler
/// und seine Zeiten. Und solange die Bedienung ausgeblendet ist, wird sie nur
/// mitgeschrieben (`latestPosition`), ohne dass SwiftUI etwas davon erfährt.
/// Blendet die Bedienung ein, steht der Regler im selben Moment richtig.
@Observable
final class PlaybackClock {
    /// Die gezeigte Stelle.
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    /// Bis wohin gepuffert ist, auf halbe Sekunden gerundet — feiner sieht
    /// man es auf dem Regler nicht, und jede Änderung wäre ein Neuzeichnen.
    private(set) var buffered: Double = 0

    /// Die tatsächliche Stelle, auch wenn gerade niemand hinsieht. Für
    /// Sprünge und das Sichern.
    @ObservationIgnored private(set) var latestPosition: Double = 0
    @ObservationIgnored private var latestBuffered: Double = 0

    /// Ist die Bedienung zu sehen? Nur dann zieht der Regler mit.
    @ObservationIgnored var isShown = true {
        didSet { if isShown, !oldValue { publish() } }
    }

    /// Ein Takt des Zeitbeobachters.
    func tick(position: Double, duration: Double?, buffered: Double?) {
        guard position.isFinite else { return }
        latestPosition = position
        if let duration, duration.isFinite, duration > 0, duration != self.duration {
            self.duration = duration
        }
        if let buffered, buffered.isFinite {
            latestBuffered = (buffered * 2).rounded(.down) / 2
        }
        if isShown { publish() }
    }

    /// Ein Sprung: sofort sichtbar, auch bei ausgeblendeter Bedienung — der
    /// Doppeltipp zeigt seine eigene Rückmeldung, der Regler soll danach
    /// nicht an der alten Stelle aufblenden.
    func jump(to position: Double) {
        latestPosition = position
        self.position = position
    }

    /// Eine neue Wiedergabe. Beim Hosterwechsel bleibt die Dauer stehen, damit
    /// der Regler nicht auf null zusammenfällt und gleich wieder aufspringt.
    func reset(position: Double, keepDuration: Bool) {
        latestPosition = position
        latestBuffered = 0
        self.position = position
        buffered = 0
        if !keepDuration { duration = 0 }
    }

    private func publish() {
        if position != latestPosition { position = latestPosition }
        if buffered != latestBuffered { buffered = latestBuffered }
    }
}

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
    let clock: PlaybackClock

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

    private var shown: Double { dragging ? dragValue : clock.position }
    private var total: Double { clock.duration.isFinite && clock.duration > 0 ? clock.duration : 0 }
    private var trackHeight: CGFloat { dragging ? 8 : 5 }
    private var knob: CGFloat { dragging ? 17 : 11 }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let width = geo.size.width
                let played = total > 0 ? min(max(shown / total, 0), 1) : 0
                let loaded = total > 0 ? min(max(clock.buffered / total, 0), 1) : 0

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
            case .increment: onSeek(min(clock.latestPosition + step, total))
            case .decrement: onSeek(max(clock.latestPosition - step, 0))
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        guard total > 0 else { return "Live" }
        return "\(formatClock(shown)) von \(formatClock(total))"
    }
}
