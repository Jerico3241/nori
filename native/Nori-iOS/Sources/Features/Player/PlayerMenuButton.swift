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

    func makeCoordinator() -> Coordinator { Coordinator(items: items, onOpen: onOpen) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
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
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.items = items
        context.coordinator.onOpen = onOpen
        // Nur die Beschriftung — etwa der Geschwindigkeitswert, der sich
        // ändert, während das Menü zu ist.
        context.coordinator.apply(label, to: button)
    }

    final class Coordinator {
        var items: () -> [PlayerMenuItem]
        var onOpen: () -> Void
        private var applied: PlayerMenuLabel?

        init(items: @escaping () -> [PlayerMenuItem], onOpen: @escaping () -> Void) {
            self.items = items
            self.onOpen = onOpen
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
