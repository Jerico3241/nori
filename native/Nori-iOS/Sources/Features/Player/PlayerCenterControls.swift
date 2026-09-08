import SwiftUI

/// Zehn Sekunden zurück, Play/Pause, zehn Sekunden vor.
///
/// Play/Pause wechselt über `contentTransition(.symbolEffect(.replace))`: das
/// Symbol verwandelt sich, statt ausgetauscht zu werden. Shirox schaltet die
/// Animation an dieser Stelle ausdrücklich ab (`.animation(nil, value:)`);
/// die native Symbolanimation kostet nichts und ist genau die Rückmeldung,
/// die ein Druck auf Pause braucht.
struct PlayerCenterControls: View {
    let isPlaying: Bool
    var onSkip: (Double) -> Void
    var onPlayPause: () -> Void

    @AppStorage(NoriGlassSetting.key) private var glass = true
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var pad: Bool { sizeClass == .regular }
    private var main: CGFloat { pad ? 96 : NoriControl.transport }
    private var side: CGFloat { pad ? 76 : NoriControl.transportSmall }

    var body: some View {
        HStack(spacing: pad ? 56 : 36) {
            skipButton("gobackward.10", label: "10 Sekunden zurück") { onSkip(-10) }

            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: pad ? 44 : 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: main, height: main)
                    .noriGlass(Circle(), enabled: glass, off: Color.white.opacity(0.22))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            }
            .buttonStyle(NoriPressStyle())
            .accessibilityLabel(isPlaying ? "Pause" : "Abspielen")

            skipButton("goforward.10", label: "10 Sekunden vor") { onSkip(10) }
        }
        .noriHaptic(.light, trigger: isPlaying)
    }

    private func skipButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: pad ? 30 : 24, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .noriGlass(Circle(), enabled: glass, off: Color.white.opacity(0.22))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        }
        .buttonStyle(NoriPressStyle())
        .accessibilityLabel(label)
    }
}
