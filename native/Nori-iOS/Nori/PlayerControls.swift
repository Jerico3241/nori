import AVKit
import SwiftUI

// Warum Nori die Bedienung selbst trägt.
//
// Bisher lag hier `AVPlayerViewController` mit Apples fertiger Bedienung. Die
// lässt sich auf iOS nicht erweitern: `transportBarCustomMenuItems` gibt es
// nur auf tvOS, und einen anderen dokumentierten Weg in die native Leiste gibt
// es nicht. Die Hosterwahl musste deshalb als eigener Knopf darüberschweben —
// und sah aus wie angeklebt, weil sie es war.
//
// Der Preis: AirPlay und Bild-in-Bild kommen nicht mehr geschenkt. Beides ist
// unten ausdrücklich eingebaut, `AVRoutePickerView` und
// `AVPictureInPictureController`.

/// Die Videofläche — nur Bild, keine Bedienung.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    /// Der Layer wird für Bild-in-Bild gebraucht; ohne ihn gibt es keinen
    /// `AVPictureInPictureController`.
    let onLayer: (AVPlayerLayer) -> Void

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        onLayer(view.playerLayer)
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
            onLayer(view.playerLayer)
        }
    }
}

/// `AVPlayerLayer` als Layer der View selbst — so wächst er von allein mit und
/// muss nicht bei jeder Größenänderung nachgeführt werden.
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer {
        // Der Typ steht über `layerClass` fest.
        layer as! AVPlayerLayer
    }
}

/// AirPlay. Ein Systembauteil; nachbauen ließe es sich ohnehin nicht, die
/// Geräteauswahl gehört dem System.
struct RoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(NoriTheme.accent)
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

/// Hält den Bild-in-Bild-Regler am Leben und sagt, ob er benutzbar ist.
@Observable
final class PictureInPicture {
    private(set) var possible = false
    private(set) var active = false
    private var controller: AVPictureInPictureController?
    private var delegate: Delegate?

    func attach(to layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard controller?.playerLayer !== layer else { return }
        let controller = AVPictureInPictureController(playerLayer: layer)
        let delegate = Delegate(owner: self)
        controller?.delegate = delegate
        self.controller = controller
        self.delegate = delegate
        // `isPictureInPicturePossible` wird erst wahr, wenn der Layer Bild
        // hat. Einmal nachfassen genügt; der Knopf erscheint dann.
        possible = controller?.isPictureInPicturePossible ?? false
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            possible = self.controller?.isPictureInPicturePossible ?? false
        }
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    private final class Delegate: NSObject, AVPictureInPictureControllerDelegate {
        weak var owner: PictureInPicture?
        init(owner: PictureInPicture) { self.owner = owner }

        func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
            owner?.active = true
        }

        func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
            owner?.active = false
        }
    }
}

/// Eine Auswahlmöglichkeit in der Bedienleiste — Hoster, Sprache, Untertitel.
struct PlayerChoice: Identifiable, Hashable {
    let id: String
    let label: String
}

/// Die Bedienung. Alles in einer Leiste, alles im selben Stil, alles
/// gemeinsam ein- und ausgeblendet.
struct PlayerControls: View {
    let title: String
    let subtitle: String

    let isPlaying: Bool
    let position: Double
    let duration: Double
    let buffered: Double
    let speed: Float

    let hosters: [PlayerChoice]
    let activeHoster: String?
    let languages: [PlayerChoice]
    let activeLanguage: String?
    let subtitles: [PlayerChoice]
    let activeSubtitle: String?

    let pip: PictureInPicture

    var onClose: () -> Void
    var onPlayPause: () -> Void
    var onSkip: (Double) -> Void
    var onSeek: (Double) -> Void
    var onScrubbing: (Bool) -> Void
    var onSpeed: (Float) -> Void
    var onHoster: (String) -> Void
    var onLanguage: (String) -> Void
    var onSubtitle: (String) -> Void

    /// Während des Ziehens gilt der lokale Wert. Ohne das zöge die laufende
    /// Wiedergabe den Regler unter dem Finger weg.
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var shown: Double { scrubbing ? scrubValue : position }
    private var total: Double { duration.isFinite && duration > 0 ? duration : 0 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            transport
            Spacer(minLength: 0)
            bottomBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background {
            // Zwei Verläufe statt einer Fläche: das Bild bleibt in der Mitte
            // frei, die Schrift steht oben und unten trotzdem auf Grund.
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 190)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Oben

    private var topBar: some View {
        HStack(spacing: 14) {
            controlButton("xmark", label: "Wiedergabe schließen", action: onClose)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            RoutePickerButton()
                .frame(width: 40, height: 40)
                .accessibilityLabel("AirPlay")

            if pip.possible {
                controlButton(
                    pip.active ? "pip.exit" : "pip.enter",
                    label: "Bild in Bild",
                    action: pip.toggle
                )
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Mitte

    private var transport: some View {
        HStack(spacing: 44) {
            controlButton("gobackward.10", label: "10 Sekunden zurück", size: 26) { onSkip(-10) }

            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Abspielen")

            controlButton("goforward.10", label: "10 Sekunden vor", size: 26) { onSkip(10) }
        }
    }

    // MARK: - Unten

    private var bottomBar: some View {
        VStack(spacing: 10) {
            scrubber

            HStack(spacing: 10) {
                menu(
                    title: "Hoster",
                    systemImage: "server.rack",
                    options: hosters,
                    active: activeHoster,
                    action: onHoster
                )
                menu(
                    title: "Sprache",
                    systemImage: "globe",
                    options: languages,
                    active: activeLanguage,
                    action: onLanguage
                )
                menu(
                    title: "Untertitel",
                    systemImage: "captions.bubble",
                    options: subtitles,
                    active: activeSubtitle,
                    action: onSubtitle
                )

                Spacer(minLength: 0)

                speedMenu
            }
        }
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .leading) {
                // Der Puffer liegt hinter dem Regler und zeigt, wie weit
                // vorgeladen ist — sonst sieht ein Sprung nach vorn aus wie
                // ein Hänger.
                GeometryReader { geo in
                    Capsule()
                        .fill(.white.opacity(0.18))
                        .frame(height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.3))
                                .frame(width: total > 0 ? geo.size.width * min(buffered / total, 1) : 0, height: 3)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 20)
                .allowsHitTesting(false)

                Slider(
                    value: Binding(
                        get: { shown },
                        set: { scrubValue = $0 }
                    ),
                    in: 0 ... max(total, 1)
                ) { editing in
                    scrubbing = editing
                    onScrubbing(editing)
                    if editing {
                        scrubValue = position
                    } else {
                        onSeek(scrubValue)
                    }
                }
                .tint(NoriTheme.accent)
                .disabled(total <= 0)
            }

            HStack {
                Text(formatClock(shown))
                Spacer()
                Text(total > 0 ? "−" + formatClock(max(total - shown, 0)) : "live")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                Button {
                    onSpeed(Float(value))
                } label: {
                    if abs(Double(speed) - value) < 0.01 {
                        Label(speedLabel(Float(value)), systemImage: "checkmark")
                    } else {
                        Text(speedLabel(Float(value)))
                    }
                }
            }
        } label: {
            chip(text: speedLabel(speed), systemImage: "speedometer")
        }
        .accessibilityLabel("Geschwindigkeit")
    }

    @ViewBuilder
    private func menu(
        title: String,
        systemImage: String,
        options: [PlayerChoice],
        active: String?,
        action: @escaping (String) -> Void
    ) -> some View {
        // Eine Auswahl mit einem einzigen Eintrag ist keine Auswahl.
        if options.count > 1 {
            Menu {
                ForEach(options) { option in
                    Button {
                        action(option.id)
                    } label: {
                        if option.id.caseInsensitiveCompare(active ?? "") == .orderedSame {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                chip(text: activeLabel(in: options, active: active) ?? title, systemImage: systemImage)
            }
            .accessibilityLabel(title)
        }
    }

    private func activeLabel(in options: [PlayerChoice], active: String?) -> String? {
        guard let active else { return nil }
        return options.first { $0.id.caseInsensitiveCompare(active) == .orderedSame }?.label
    }

    private func chip(text: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.caption)
            Text(text).font(.caption.weight(.medium)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.white.opacity(0.16), in: Capsule())
    }

    private func controlButton(
        _ systemImage: String,
        label: String,
        size: CGFloat = 17,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func speedLabel(_ value: Float) -> String {
        if abs(value - 1) < 0.01 { return "1×" }
        return String(format: "%g×", value)
    }
}
