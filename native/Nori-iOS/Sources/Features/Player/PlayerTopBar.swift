import SwiftUI

/// Die obere Leiste: schließen links, Serie und Folge in der Mitte,
/// Systemfunktionen rechts.
///
/// Rechts stehen AirPlay und Bild-in-Bild als **eine** Glaskapsel, nicht als
/// zwei freistehende Knöpfe. Zusammengefasst lesen sie sich als das, was sie
/// sind — eine Gruppe von Ausgabezielen — und nehmen weniger Rand weg.
struct PlayerTopBar: View {
    let title: String
    let subtitle: String
    let pip: PictureInPicture
    var onClose: () -> Void

    @AppStorage(NoriGlassSetting.key) private var glass = true
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var pad: Bool { sizeClass == .regular }
    private var button: CGFloat { pad ? 52 : NoriControl.hit }
    private var icon: CGFloat { pad ? 20 : 17 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: icon, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: button, height: button)
                    .noriGlass(Circle(), enabled: glass, off: Color.white.opacity(0.22))
                    .shadow(color: .black.opacity(0.3), radius: 6)
            }
            .buttonStyle(NoriPressStyle())
            .accessibilityLabel("Wiedergabe schließen")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(pad ? .headline : .subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(pad ? .subheadline : .caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 5, y: 1)
            .frame(height: button, alignment: .center)

            Spacer(minLength: 8)

            HStack(spacing: pad ? 10 : 4) {
                RoutePickerButton()
                    .frame(width: button - 8, height: button - 8)
                    .accessibilityLabel("AirPlay")

                if pip.possible {
                    Button(action: pip.toggle) {
                        Image(systemName: pip.active ? "pip.exit" : "pip.enter")
                            .font(.system(size: icon, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: button - 8, height: button - 8)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(NoriPressStyle())
                    .accessibilityLabel("Bild in Bild")
                }
            }
            .padding(.horizontal, 4)
            .noriGlass(Capsule(), enabled: glass, off: Color.white.opacity(0.2))
        }
    }
}
