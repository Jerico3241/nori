import SwiftUI

/// Die untere Leiste: links die Folge, rechts alle Wiedergabeoptionen, darunter
/// der Fortschritt.
///
/// Die Optionen stehen als **eine** Glaskapsel zusammen, nicht als Reihe
/// einzelner Kapseln. Sie gehören zusammen — es sind alles Entscheidungen über
/// denselben Stream —, und als Gruppe brauchen sie weniger Breite, was im
/// Querformat eines iPhones zählt.
///
/// Es gibt genau eine Hosterauswahl, und sie steht hier. Früher schwebte
/// zusätzlich eine eigene Hosterleiste über dem Bild; zeitweise waren beide
/// gleichzeitig sichtbar und überlappten sich.
struct PlayerBottomBar: View {
    /// „Folge 7" — die kleine Zeile. `nil`, wenn die Folge keinen eigenen
    /// Titel hat; dann steht die Nummer allein und groß darunter.
    let episodeNumber: String?
    /// Der Titel der Folge, sonst die Nummer.
    let episodeTitle: String

    let position: Double
    let duration: Double
    let buffered: Double
    let speed: Float

    let hosters: [PlayerChoice]
    let activeHoster: String?
    let qualities: [PlayerChoice]
    let activeQuality: String?
    let languages: [PlayerChoice]
    let activeLanguage: String?
    let subtitles: [PlayerChoice]
    let activeSubtitle: String?
    let hasNextEpisode: Bool
    let isFilled: Bool

    var onScrub: (Double) -> Void
    var onSeek: (Double) -> Void
    var onScrubbing: (Bool) -> Void
    var onSpeed: (Float) -> Void
    var onHoster: (String) -> Void
    var onQuality: (String) -> Void
    var onLanguage: (String) -> Void
    var onSubtitle: (String) -> Void
    var onNextEpisode: () -> Void
    var onToggleFill: () -> Void
    var onMenuOpen: () -> Void

    @AppStorage(NoriGlassSetting.key) private var glass = true
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var pad: Bool { sizeClass == .regular }
    private var buttonWidth: CGFloat { pad ? 46 : 36 }
    private var buttonHeight: CGFloat { pad ? 44 : 34 }
    private var iconSize: CGFloat { pad ? 18 : 15 }

    private static let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(alignment: .leading, spacing: pad ? 12 : 8) {
            HStack(alignment: .bottom, spacing: 10) {
                // Hier steht die **Folge**, nicht die Serie: der Serienname
                // steht schon oben, und zweimal dasselbe auf einem Bild ist
                // eine Zeile verschenkt. Der Folgentitel kommt sonst nirgends
                // im Player vor.
                VStack(alignment: .leading, spacing: 1) {
                    if let episodeNumber {
                        Text(episodeNumber)
                            .font(.system(size: pad ? 14 : 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Text(episodeTitle)
                        .font(.system(size: pad ? 21 : 17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                // Ohne das gewinnt die Knopfgruppe den Wettstreit um die
                // Breite, und der Titel schrumpft auf ein paar Zeichen,
                // obwohl die halbe Leiste leer ist.
                .layoutPriority(1)
                .shadow(color: .black.opacity(0.5), radius: 5, y: 1)

                Spacer(minLength: 8)

                optionGroup
            }

            PlayerProgressSlider(
                position: position,
                duration: duration,
                buffered: buffered,
                onScrub: onScrub,
                onSeek: onSeek,
                onScrubbing: onScrubbing
            )
        }
    }

    // MARK: - Die Optionsgruppe

    @ViewBuilder
    private var optionGroup: some View {
        HStack(spacing: 0) {
            // Nur was es wirklich gibt. Eine Auswahl mit einem einzigen
            // Eintrag ist keine Auswahl, und ein Menü, das nichts zu wählen
            // hat, ist ein toter Knopf.
            menu("Hoster", symbol: "server.rack", options: hosters, active: activeHoster, action: onHoster)
            menu("Qualität", symbol: "4k.tv", options: qualities, active: activeQuality, action: onQuality)
            menu("Sprache", symbol: "globe", options: languages, active: activeLanguage, action: onLanguage)
            menu("Untertitel", symbol: "captions.bubble", options: subtitles, active: activeSubtitle, action: onSubtitle)

            Button(action: onToggleFill) {
                Image(systemName: isFilled
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: iconSize - 1, weight: .medium))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: buttonWidth, height: buttonHeight)
            }
            .buttonStyle(NoriPressStyle())
            .accessibilityLabel(isFilled ? "Bild einpassen" : "Bild füllen")

            PlayerMenuButton(
                menuTitle: "Geschwindigkeit",
                label: .text(Self.speedLabel(speed), size: pad ? 16 : 14),
                items: speedItems,
                onOpen: onMenuOpen
            )
            .frame(height: buttonHeight)
            .padding(.horizontal, pad ? 12 : 9)
            .contentShape(Rectangle())
            .accessibilityLabel("Geschwindigkeit")

            if hasNextEpisode {
                Button(action: onNextEpisode) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: buttonWidth, height: buttonHeight)
                }
                .buttonStyle(NoriPressStyle())
                .accessibilityLabel("Nächste Folge")
            }
        }
        .padding(.horizontal, pad ? 6 : 4)
        .padding(.vertical, 2)
        .noriGlass(Capsule(), enabled: glass, off: Color.white.opacity(0.2))
    }

    @ViewBuilder
    private func menu(
        _ title: String,
        symbol: String,
        options: [PlayerChoice],
        active: String?,
        action: @escaping (String) -> Void
    ) -> some View {
        if options.count > 1 {
            PlayerMenuButton(
                menuTitle: title,
                label: .symbol(symbol, size: iconSize),
                items: { menuItems(options, active: active, action: action) },
                onOpen: onMenuOpen
            )
            .frame(width: buttonWidth, height: buttonHeight)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel(title, options: options, active: active))
        }
    }

    private func menuItems(
        _ options: [PlayerChoice],
        active: String?,
        action: @escaping (String) -> Void
    ) -> [PlayerMenuItem] {
        options.map { option in
            PlayerMenuItem(
                title: option.label,
                isOn: option.id.caseInsensitiveCompare(active ?? "") == .orderedSame
            ) { action(option.id) }
        }
    }

    private func accessibilityLabel(_ title: String, options: [PlayerChoice], active: String?) -> String {
        guard let active,
              let label = options.first(where: { $0.id.caseInsensitiveCompare(active) == .orderedSame })?.label
        else { return title }
        return "\(title): \(label)"
    }

    private func speedItems() -> [PlayerMenuItem] {
        Self.speeds.map { value in
            PlayerMenuItem(
                title: value == 1 ? "Normal (1×)" : Self.speedLabel(value),
                isOn: abs(value - speed) < 0.01
            ) { onSpeed(value) }
        }
    }

    static func speedLabel(_ value: Float) -> String {
        if abs(value - 1) < 0.01 { return "1×" }
        return String(format: "%g×", value)
    }
}
