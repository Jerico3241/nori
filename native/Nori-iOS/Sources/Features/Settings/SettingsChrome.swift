import SwiftUI

// Die Bausteine des Mehr-Bereichs: Gruppe, Zeile, Schalterzeile, Wertzeile,
// Profilkarte, Abgleichkarte.
//
// Die Maße stammen aus `nori-settings-v1.html`: 22 Punkte Radius für eine
// Gruppe, 58 Punkte Mindesthöhe je Zeile, ein 32 Punkte großes getöntes
// Quadrat für das Symbol. Der Seitenrand bleibt `NoriSpacing.screen`, damit
// „Mehr" links auf derselben Linie beginnt wie Startseite und Kalender.
//
// Innen sind es überall native Bedienelemente — `Toggle`, `NavigationLink`,
// `Button`. Nachgebaut ist nur der Rahmen, nicht die Mechanik.

// MARK: - Symbolfarben

/// Die Tönung des Symbolquadrats.
///
/// Vier Farben mit fester Bedeutung, damit sich eine Gruppe auf einen Blick
/// einordnen lässt: Blau ist Wiedergabe und Auskunft, Violett ist Darstellung,
/// Grün ist Bibliothek und Abgleich, Orange ist Speicher, Rot ist Prüfung und
/// Löschung.
enum SettingsTint {
    case blue
    case violet
    case green
    case orange
    case red

    var background: Color {
        switch self {
        case .blue: return Color(red: 0.47, green: 0.77, blue: 1).opacity(0.13)
        case .violet: return Color(red: 0.63, green: 0.44, blue: 0.86).opacity(0.15)
        case .green: return Color(red: 0.52, green: 0.85, blue: 0.70).opacity(0.15)
        case .orange: return Color(red: 0.95, green: 0.67, blue: 0.40).opacity(0.15)
        case .red: return Color(red: 0.93, green: 0.44, blue: 0.47).opacity(0.15)
        }
    }

    var foreground: Color {
        switch self {
        case .blue: return Color(red: 0.80, green: 0.92, blue: 1)
        case .violet: return Color(red: 0.85, green: 0.78, blue: 1)
        case .green: return Color(red: 0.75, green: 0.95, blue: 0.85)
        case .orange: return Color(red: 1, green: 0.82, blue: 0.63)
        case .red: return Color(red: 1, green: 0.76, blue: 0.78)
        }
    }
}

// MARK: - Gruppe

/// Eine Überschrift und darunter eine Karte mit Zeilen.
struct SettingsGroup<Content: View>: View {
    let title: String
    /// Erklärung unter der Gruppe. Für alles, was eine Zeile nicht in ihrer
    /// zweiten Textzeile unterbringt — etwa warum eine Möglichkeit fehlt.
    var footnote: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.heavy))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(NoriTheme.muted)
                .padding(.horizontal, 8)
            VStack(spacing: 0) {
                content()
            }
            .noriPanel()
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(NoriTheme.muted)
                    .padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, NoriSpacing.screen)
    }
}

/// Die Trennlinie zwischen zwei Zeilen.
///
/// Von Hand gesetzt statt aus der Gruppe heraus erzeugt: eine Gruppe weiß mit
/// `@ViewBuilder` nicht, wie viele Zeilen sie bekommen hat, und die letzte
/// Linie darf nicht stehen bleiben. Ein Umweg über `_VariadicView` wäre die
/// Alternative — mehr Mechanik, als eine Trennlinie wert ist.
struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(NoriTheme.border)
            .padding(.leading, 15 + NoriPanel.iconSize + 10)
    }
}

// MARK: - Zeileninhalt

/// Symbol, Beschriftung, zweite Zeile — der Inhalt jeder Zeile.
///
/// Eigene Ansicht, damit Schalter-, Wert- und Verweiszeile denselben Aufbau
/// benutzen: eine Zeile, die drei Punkte weiter links beginnt als die darüber,
/// fällt sofort auf.
struct SettingsRowContent<Trailing: View>: View {
    let symbol: String
    var tint: SettingsTint = .blue
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint.foreground)
                .frame(width: NoriPanel.iconSize, height: NoriPanel.iconSize)
                .background(tint.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NoriTheme.fg)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(NoriTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)

            trailing()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .frame(minHeight: NoriPanel.rowHeight)
    }
}

// MARK: - Zeilenarten

/// Ein Schalter. `Toggle` mit `labelsHidden`, damit die Beschriftung links
/// steht wie in allen anderen Zeilen — der Schalter selbst bleibt Apples.
struct SettingsToggleRow: View {
    let symbol: String
    var tint: SettingsTint = .blue
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRowContent(symbol: symbol, tint: tint, title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(NoriTheme.accent)
        }
        .noriHaptic(.selection, trigger: isOn)
        .accessibilityElement(children: .combine)
    }
}

/// Ein Verweis auf eine weitere Seite, rechts wahlweise mit dem aktuellen Wert.
struct SettingsLinkRow<Destination: View>: View {
    let symbol: String
    var tint: SettingsTint = .blue
    let title: String
    var subtitle: String?
    var value: String?
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowContent(symbol: symbol, tint: tint, title: title, subtitle: subtitle) {
                HStack(spacing: 4) {
                    if let value {
                        Text(value)
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NoriTheme.muted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Eine Zeile, die etwas tut — „Jetzt synchronisieren", „Cache leeren".
struct SettingsButtonRow<Trailing: View>: View {
    let symbol: String
    var tint: SettingsTint = .blue
    let title: String
    var subtitle: String?
    var role: ButtonRole?
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(role: role, action: action) {
            SettingsRowContent(symbol: symbol, tint: tint, title: title, subtitle: subtitle, trailing: trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : NoriTheme.fg)
    }
}

/// Eine Zeile, die nur berichtet — Version, Plattform, Zustand eines Dienstes.
/// Kein Verweis und kein Schalter, weil es nichts zu öffnen und nichts zu
/// stellen gibt.
struct SettingsInfoRow: View {
    let symbol: String
    var tint: SettingsTint = .blue
    let title: String
    var subtitle: String?
    let value: String

    var body: some View {
        SettingsRowContent(symbol: symbol, tint: tint, title: title, subtitle: subtitle) {
            Text(value)
                .font(.caption)
                .foregroundStyle(NoriTheme.muted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Profilkarte

/// Die Karte am Kopf des Mehr-Bereichs.
///
/// Nori hat kein Konto — es gibt keine Anmeldung, keinen Server und keinen
/// Nutzernamen. Die Karte erfindet deshalb keinen: sie zeigt, was wirklich da
/// ist — wie viele Titel in der Merkliste stehen, wie viele Folgen angefangen
/// sind — und führt zur Bibliotheksgruppe. Ein Avatar mit „Dein Nori" und
/// darunter „nicht angemeldet" wäre eine Andeutung auf ein Konto, das es nicht
/// gibt.
struct SettingsProfileCard: View {
    let favorites: Int
    let inProgress: Int
    let syncName: String?

    var body: some View {
        HStack(spacing: 14) {
            Text("N")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(NoriTheme.bg)
                .frame(width: 60, height: 60)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.86, green: 0.93, blue: 1),
                            Color(red: 0.48, green: 0.74, blue: 0.94),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Deine Bibliothek")
                    .font(.callout.weight(.semibold))
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(NoriTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: NoriPanel.heroRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [NoriTheme.elevated, NoriTheme.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    RadialGradient(
                        gradient: Gradient(colors: [NoriTheme.accent.opacity(0.20), .clear]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 90
                    )
                    .frame(width: 180, height: 180)
                    .offset(x: 46, y: -64)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: NoriPanel.heroRadius, style: .continuous)
                        .strokeBorder(NoriTheme.border)
                }
                .clipShape(RoundedRectangle(cornerRadius: NoriPanel.heroRadius, style: .continuous))
        }
        .padding(.horizontal, NoriSpacing.screen)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        var parts: [String] = []
        parts.append(favorites == 1 ? "1 Titel gemerkt" : "\(favorites) Titel gemerkt")
        parts.append(inProgress == 1 ? "1 Folge angefangen" : "\(inProgress) Folgen angefangen")
        parts.append(syncName.map { "Abgleich über \($0)" } ?? "Nur auf diesem Gerät")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Abgleichkarte

/// Der Zustand des Abgleichs — und nur der echte.
///
/// Die Vorlage zeigt hier ein grünes „AKTIV" mit „zuletzt synchronisiert vor
/// 2 Min.". Beides wäre in Nori zurzeit gelogen: es ist kein Anbieter
/// eingerichtet, und ohne Anbieter findet kein Abgleich statt. Die Karte sagt
/// deshalb, was ist — und zeigt den Zeitstempel erst, wenn es einen gibt.
struct SettingsSyncCard: View {
    enum State: Equatable {
        /// Keine Client-ID hinterlegt — dann gibt es gar nichts anzubieten.
        case notConfigured
        /// Eingerichtet, aber dieses Gerät ist nicht verbunden.
        case disconnected(name: String)
        case authorizing(name: String)
        case idle(name: String, lastRun: Date?)
        case running(name: String)
        /// Kein Netz. Ein Zustand, kein Fehler: die Änderungen liegen lokal
        /// und gehen nicht verloren.
        case offline(name: String, lastRun: Date?)
        case failed(name: String, message: String)
        /// In der Cloud liegt ein Stand, den diese Fassung nicht kennt.
        case needsUpdate(name: String)

        var title: String {
            switch self {
            case .notConfigured: return "Abgleich"
            case .disconnected(let name), .authorizing(let name), .idle(let name, _),
                 .running(let name), .offline(let name, _), .failed(let name, _),
                 .needsUpdate(let name):
                return name
            }
        }

        var pill: String {
            switch self {
            case .notConfigured: return "Nicht eingerichtet"
            case .disconnected: return "Nicht verbunden"
            case .authorizing: return "Verbinden …"
            case .idle(_, let lastRun): return lastRun == nil ? "Bereit" : "Synchronisiert"
            case .running: return "Läuft"
            case .offline: return "Offline"
            case .failed: return "Fehler"
            case .needsUpdate: return "Update nötig"
            }
        }

        var symbol: String {
            switch self {
            case .notConfigured, .disconnected: return "icloud.slash"
            case .authorizing: return "person.badge.key"
            case .idle(_, let lastRun): return lastRun == nil ? "icloud" : "checkmark.icloud"
            case .running: return "arrow.triangle.2.circlepath"
            case .offline: return "bolt.horizontal.icloud"
            case .failed: return "exclamationmark.icloud"
            case .needsUpdate: return "arrow.up.circle"
            }
        }

        var tint: SettingsTint {
            switch self {
            case .notConfigured, .disconnected, .authorizing, .running: return .blue
            case .idle(_, let lastRun): return lastRun == nil ? .blue : .green
            case .offline, .needsUpdate: return .orange
            case .failed: return .red
            }
        }

        var detail: String {
            switch self {
            case .notConfigured:
                return "Merkliste, Verlauf und Fortschritt liegen nur auf diesem Gerät."
            case .disconnected:
                return "Verbinde Google Drive, um Merkliste, Verlauf und Fortschritt zu teilen."
            case .authorizing:
                return "Warten auf die Bestätigung bei Google …"
            case .idle(_, let lastRun):
                guard let lastRun else { return "Noch kein Abgleich gelaufen." }
                return "Zuletzt " + lastRun.formatted(.relative(presentation: .named)) + "."
            case .running:
                return "Wird abgeglichen …"
            case .offline(_, let lastRun):
                // Kein Alarm: lokal ist alles da, und beim nächsten Netz geht
                // es weiter.
                guard let lastRun else { return "Ohne Netz — wird später abgeglichen." }
                return "Ohne Netz. Zuletzt " + lastRun.formatted(.relative(presentation: .named)) + "."
            case .failed(_, let message):
                return message
            case .needsUpdate:
                return "In der Cloud liegt ein neuerer Stand. Bitte Nori aktualisieren."
            }
        }
    }

    let state: State

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(state.tint.foreground)
                .frame(width: 40, height: 40)
                .background(state.tint.background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.footnote.weight(.semibold))
                Text(state.detail)
                    .font(.caption2)
                    .foregroundStyle(NoriTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)

            Text(state.pill)
                .font(.system(size: 9, weight: .heavy))
                .textCase(.uppercase)
                .foregroundStyle(state.tint.foreground)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(state.tint.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(state.tint.foreground.opacity(0.18))
                }
                .fixedSize()
        }
        .padding(15)
        .noriPanel(radius: NoriPanel.cardRadius)
        .padding(.horizontal, NoriSpacing.screen)
        .accessibilityElement(children: .combine)
    }
}
