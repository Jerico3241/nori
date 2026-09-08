import AVKit
import SwiftUI

// Die AVKit-Anbindung des Players: Bildfläche, AirPlay, Bild-in-Bild.
//
// Warum Nori die Bedienung selbst trägt: hier lag einmal
// `AVPlayerViewController` mit Apples fertiger Leiste. Die lässt sich auf iOS
// nicht erweitern — `transportBarCustomMenuItems` gibt es nur auf tvOS, einen
// anderen dokumentierten Weg in die native Leiste gibt es nicht. Die
// Hosterwahl musste deshalb als eigener Knopf darüberschweben und sah aus wie
// angeklebt, weil sie es war.
//
// Der Preis: AirPlay und Bild-in-Bild kommen nicht mehr geschenkt. Beides
// steht deshalb hier, `AVRoutePickerView` und `AVPictureInPictureController`
// — Systembauteile, keine Nachbauten.

/// Die Videofläche — nur Bild, keine Bedienung.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    /// Der Layer wird für Bild-in-Bild gebraucht; ohne ihn gibt es keinen
    /// `AVPictureInPictureController`.
    let onLayer: (AVPlayerLayer) -> Void
    /// Bild einpassen oder formatfüllend. Auf einem 16:9-Video an einem
    /// iPhone-Bildschirm bleiben sonst breite schwarze Balken stehen.
    var fill: Bool = false

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        onLayer(view.playerLayer)
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
            onLayer(view.playerLayer)
        }
        let wanted: AVLayerVideoGravity = fill ? .resizeAspectFill : .resizeAspect
        if view.playerLayer.videoGravity != wanted {
            // Über CATransaction animiert: der harte Sprung zwischen den
            // beiden Größen sieht nach einem Fehler aus.
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            view.playerLayer.videoGravity = wanted
            CATransaction.commit()
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
        // Ohne das zeichnet die View ihren eigenen grauen Grund in die
        // Glaskapsel hinein.
        view.backgroundColor = .clear
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

/// Eine Auswahlmöglichkeit in der Bedienleiste — Hoster, Sprache, Untertitel,
/// Qualität.
struct PlayerChoice: Identifiable, Hashable {
    let id: String
    let label: String
}
