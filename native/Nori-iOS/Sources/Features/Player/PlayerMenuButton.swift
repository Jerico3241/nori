import SwiftUI
import UIKit

// Adaptiert aus Shirox, `Shirox/Views/Player/PlayerMenuButton.swift`.
// Required Notice: Copyright 2026 xibrox (https://github.com/xibrox/Shirox)
// PolyForm Noncommercial License 1.0.0 — siehe THIRD-PARTY-NOTICES.md.
//
// Warum UIKit statt `Menu`:
//
// Der Player zeichnet seinen Rumpf viermal pro Sekunde neu — der periodische
// Zeitbeobachter schreibt Position, Dauer und Pufferstand. Ein SwiftUI-`Menu`
// wird bei jedem Neuzeichnen eines Vorfahren geschlossen und neu aufgeklappt
// und blitzt dabei. Wer die Hosterliste offen hielt und der Fortschritt lief
// weiter, sah das Menü flackern, bis es sich von selbst schloss.
//
// Ein `UIMenu` gehört nach dem Aufklappen UIKit. SwiftUI kann den Umschlag
// beliebig oft neu bauen, ohne es zu stören: `updateUIView` frischt nur die
// Beschriftung auf und fasst `button.menu` nie an.

/// Eine Zeile in einem Player-Menü. `isOn` zeichnet den System-Haken.
struct PlayerMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let isOn: Bool
    let action: () -> Void
}

/// Die Beschriftung eines Menüknopfs — beschreibend statt als View, weil sie
/// in einem `UIButton` landet und keine SwiftUI-View sein kann.
enum PlayerMenuLabel: Equatable {
    case symbol(String, size: CGFloat)
    case text(String, size: CGFloat)
}

struct PlayerMenuButton: UIViewRepresentable {
    let menuTitle: String
    let label: PlayerMenuLabel
    /// Wird bei jedem Aufklappen neu ausgewertet, damit die Haken den
    /// aktuellen Stand zeigen.
    let items: () -> [PlayerMenuItem]
    /// Feuert, sobald das Menü erscheint — der Player hält die Bedienung
    /// daraufhin offen, statt sie unter dem Menü wegzublenden.
    var onOpen: () -> Void = {}
    /// Feuert, sobald das Menü wieder zu ist — nach einer Auswahl ebenso wie
    /// nach einem Tipp daneben.
    var onClose: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(items: items, onOpen: onOpen, onClose: onClose) }

    func makeUIView(context: Context) -> MenuClosingButton {
        let button = MenuClosingButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        // Die Einträge in der gelieferten Reihenfolge. Standardmäßig legt
        // UIKit den ersten Eintrag an den Knopf — öffnet das Menü aus der
        // unteren Leiste nach oben, stand die Hosterliste damit auf dem Kopf:
        // der bevorzugte Hoster ganz unten, der schwächste oben.
        button.preferredMenuElementOrder = .fixed
        button.tintColor = .white
        button.backgroundColor = .clear
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        context.coordinator.apply(label, to: button)

        // Das Menü wird **einmal** gebaut. Das ungepufferte, verzögerte
        // Element ruft seinen Lieferanten bei jedem Aufklappen erneut auf —
        // die Einträge bleiben frisch, ohne dass `button.menu` je neu gesetzt
        // wird (was wieder blitzen würde).
        let coordinator = context.coordinator
        let deferred = UIDeferredMenuElement.uncached { [weak coordinator] completion in
            let actions = (coordinator?.items() ?? []).map { item in
                UIAction(title: item.title, state: item.isOn ? .on : .off) { _ in item.action() }
            }
            completion(actions)
            // Die Zustandsänderung aus dem Menüaufbau heraus verschieben,
            // sonst greift sie in den laufenden Aufbau hinein.
            DispatchQueue.main.async { coordinator?.onOpen() }
        }
        button.menu = UIMenu(title: menuTitle, children: [deferred])
        button.onClose = { [weak coordinator] in coordinator?.onClose() }
        return button
    }

    func updateUIView(_ button: MenuClosingButton, context: Context) {
        context.coordinator.items = items
        context.coordinator.onOpen = onOpen
        context.coordinator.onClose = onClose
        // Nur die Beschriftung — etwa der Geschwindigkeitswert, der sich
        // ändert, während das Menü zu ist.
        context.coordinator.apply(label, to: button)
    }

    final class Coordinator {
        var items: () -> [PlayerMenuItem]
        var onOpen: () -> Void
        var onClose: () -> Void
        private var applied: PlayerMenuLabel?

        init(items: @escaping () -> [PlayerMenuItem], onOpen: @escaping () -> Void, onClose: @escaping () -> Void) {
            self.items = items
            self.onOpen = onOpen
            self.onClose = onClose
        }

        func apply(_ label: PlayerMenuLabel, to button: UIButton) {
            // Viermal pro Sekunde dieselbe Beschriftung neu zu setzen kostet
            // jedes Mal einen Layoutdurchlauf im Button.
            guard applied != label else { return }
            applied = label
            switch label {
            case let .symbol(name, size):
                let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
                button.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
                button.setTitle(nil, for: .normal)
            case let .text(text, size):
                button.setImage(nil, for: .normal)
                button.setTitle(text, for: .normal)
                button.setTitleColor(.white, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: size, weight: .semibold)
            }
        }
    }
}

/// Ein Menüknopf, der meldet, wann sein Menü schließt.
///
/// Vorher galt „Noris Fenster wird wieder Schlüsselfenster" als Signal. Auf
/// iPadOS 26 kommt das nach einer Auswahl nicht: das Menü blieb für den Player
/// offen, und die Bedienung blendete danach während der Wiedergabe nie wieder
/// aus (gemessen: über 25 Sekunden nach einer Untertitelwahl). Das Ende der
/// Menü-Interaktion meldet UIKit dagegen verlässlich.
final class MenuClosingButton: UIButton {
    var onClose: (() -> Void)?

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        if let animator {
            animator.addCompletion { [weak self] in self?.onClose?() }
        } else {
            onClose?()
        }
    }
}
