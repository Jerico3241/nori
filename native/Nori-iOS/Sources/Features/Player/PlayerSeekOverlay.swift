import SwiftUI
import UIKit

// Adaptiert aus Shirox, `Shirox/Views/Player/PlayerDoubleTapSeek.swift`.
// Required Notice: Copyright 2026 xibrox (https://github.com/xibrox/Shirox)
// PolyForm Noncommercial License 1.0.0 — siehe THIRD-PARTY-NOTICES.md.
//
// Übernommen sind die beiden Punkte, an denen eine naive SwiftUI-Lösung
// scheitert: eine **einzige** Erkennerfläche über den ganzen Bildschirm statt
// zweier Hälften, damit `event.allTouches` Finger beider Seiten sieht, und
// `require(toFail:)`, damit der erste Tipp eines Doppeltipps nicht schon die
// Bedienung umschaltet.

/// Doppeltipp links und rechts zum Springen, einfacher Tipp für die Bedienung.
///
/// Die Sprünge zählen zusammen: wer viermal schnell rechts tippt, springt
/// 40 Sekunden und sieht „+40 s". Danach fällt die Anzeige zurück. Ohne das
/// Zusammenfassen blitzt bei jedem Tipp „+10 s" auf und die tatsächlich
/// gesprungene Strecke bleibt unklar.
struct PlayerSeekOverlay: View {
    let step: Double
    var onSingleTap: () -> Void
    var onSeek: (Double) -> Void

    @NoriReduceMotion private var reduceMotion

    /// Wie viele Sekunden die laufende Serie von Doppeltipps ergibt.
    /// Negativ links, positiv rechts, `0` heißt: nichts sichtbar.
    @State private var accumulated: Double = 0
    @State private var fadeTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            TapSurface(
                onSingleTap: onSingleTap,
                onDoubleTapLeft: { register(-step) },
                onDoubleTapRight: { register(step) }
            )

            HStack(spacing: 0) {
                feedback(forward: false)
                feedback(forward: true)
            }
            .allowsHitTesting(false)
        }
        .noriHaptic(.light, trigger: accumulated)
    }

    @ViewBuilder
    private func feedback(forward: Bool) -> some View {
        let showing = forward ? accumulated > 0 : accumulated < 0
        ZStack {
            if showing {
                VStack(spacing: 6) {
                    Image(systemName: forward ? "goforward" : "gobackward")
                        .font(.system(size: 27, weight: .semibold))
                    Text("\(forward ? "+" : "−")\(Int(abs(accumulated))) s")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.white)
                .frame(width: 116, height: 116)
                .background(.black.opacity(0.42), in: Circle())
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.82))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func register(_ delta: Double) {
        fadeTask?.cancel()
        // Richtungswechsel setzt zurück: „−10 s" nach „+30 s" soll nicht
        // „+20 s" anzeigen, sondern von vorn zählen.
        let sameDirection = accumulated == 0 || (accumulated > 0) == (delta > 0)
        withAnimation(NoriMotion.allowed(NoriMotion.micro, reduceMotion: reduceMotion)) {
            accumulated = sameDirection ? accumulated + delta : delta
        }
        onSeek(delta)

        fadeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            withAnimation(NoriMotion.allowed(NoriMotion.micro, reduceMotion: reduceMotion)) {
                accumulated = 0
            }
        }
    }
}

/// Die Erkennerfläche.
///
/// Eine UIView über den ganzen Bildschirm, nicht zwei nebeneinander: nur so
/// sieht `event.allTouches` auch den Finger auf der anderen Hälfte, und nur
/// so lässt sich ein Zweifingergriff zuverlässig ignorieren.
private struct TapSurface: UIViewRepresentable {
    var onSingleTap: () -> Void
    var onDoubleTapLeft: () -> Void
    var onDoubleTapRight: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(single: onSingleTap, left: onDoubleTapLeft, right: onDoubleTapRight)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let double = SingleTouchTap(target: context.coordinator, action: #selector(Coordinator.handleDouble(_:)))
        double.numberOfTapsRequired = 2

        let single = SingleTouchTap(target: context.coordinator, action: #selector(Coordinator.handleSingle(_:)))
        single.numberOfTapsRequired = 1

        // Der einfache Tipp wartet, bis der Doppeltipp durchgefallen ist.
        // Ohne das schaltet der erste Tipp eines Doppeltipps die Bedienung
        // ein, bevor der Sprung ausgelöst wird — die Oberfläche springt bei
        // jedem Springen auf. Der Preis sind die üblichen ~0,3 Sekunden, bis
        // die Bedienung auf einen einfachen Tipp erscheint.
        single.require(toFail: double)

        view.addGestureRecognizer(double)
        view.addGestureRecognizer(single)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.single = onSingleTap
        context.coordinator.left = onDoubleTapLeft
        context.coordinator.right = onDoubleTapRight
    }

    final class Coordinator: NSObject {
        var single: () -> Void
        var left: () -> Void
        var right: () -> Void

        init(single: @escaping () -> Void, left: @escaping () -> Void, right: @escaping () -> Void) {
            self.single = single
            self.left = left
            self.right = right
        }

        @objc func handleSingle(_ recognizer: UITapGestureRecognizer) { single() }

        @objc func handleDouble(_ recognizer: UITapGestureRecognizer) {
            let width = recognizer.view?.bounds.width ?? 0
            // Die Mitte bleibt frei: ein Doppeltipp genau auf das Bild soll
            // nicht springen, sondern nichts tun.
            let x = recognizer.location(in: recognizer.view).x
            if x < width * 0.4 {
                left()
            } else if x > width * 0.6 {
                right()
            }
        }
    }
}

/// Erkenner, der bei mehr als einem gleichzeitigen Finger sofort durchfällt.
/// Über den ganzen Bildschirm gelegt macht das Zwei-Finger-Gesten für ihn
/// unsichtbar, egal auf welchen Hälften die Finger liegen.
private final class SingleTouchTap: UITapGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard (event.allTouches?.count ?? 0) == 1 else {
            state = .failed
            return
        }
        super.touchesBegan(touches, with: event)
    }
}
