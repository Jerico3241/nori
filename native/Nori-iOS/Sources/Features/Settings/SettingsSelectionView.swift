import SwiftUI

/// Eine Seite, auf der genau ein Wert gewählt wird.
///
/// Die Vorlage öffnet dafür ein Sheet mit einer Liste und einem Häkchen. Auf
/// iOS ist eine geschobene Seite die gewohntere Form — der Wert steht in der
/// Zeile, von der man kam, und der Rückweg ist der Zurück-Knopf. Die Mechanik
/// ist dieselbe, und zu jeder Möglichkeit steht eine Zeile, die sagt, was sie
/// bedeutet; eine Liste aus „1080p / 720p / 480p" ohne Erklärung lässt offen,
/// was passiert, wenn der Hoster die Stufe nicht hat.
///
/// Die Auswahl wirkt **sofort**. Es gibt kein „Anwenden": die Bindung zeigt in
/// den `LibraryStore`, und der schreibt bei jeder Änderung.
struct SettingsSelectionView<Option: Identifiable & Equatable>: View {
    let title: String
    let options: [Option]
    let label: (Option) -> String
    let note: (Option) -> String
    @Binding var selection: Option
    /// Was sonst noch über die Auswahl zu sagen ist — etwa der Rückfall, wenn
    /// die gewünschte Sprache bei einer Folge fehlt.
    var footnote: String?

    var body: some View {
        NoriGradientScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            row(option)
                            if index < options.count - 1 { SettingsDivider() }
                        }
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
                .padding(.top, 10)
                .padding(.bottom, NoriPanel.bottom)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ option: Option) -> some View {
        let active = option == selection
        return Button {
            selection = option
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label(option))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(NoriTheme.fg)
                    Text(note(option))
                        .font(.caption2)
                        .foregroundStyle(NoriTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(NoriTheme.accent)
                    .opacity(active ? 1 : 0)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(minHeight: NoriPanel.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Sprache

/// Die bevorzugte Sprache neuer Wiedergaben.
struct LanguageSettingsView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        SettingsSelectionView(
            title: "Bevorzugte Sprache",
            options: NoriLanguageOption.allCases,
            label: \.label,
            note: \.note,
            selection: Binding(
                get: { NoriLanguageOption.from(library.langPref) },
                set: { library.langPref = $0.rawValue }
            ),
            footnote: """
            Hat eine Folge die gewünschte Sprache nicht, nimmt Nori die nächste \
            verfügbare — in der Reihenfolge Deutsch, GerSub, Englisch. Die \
            Wiedergabe wird nie verhindert. Wird im Player eine andere Sprache \
            gewählt, merkt Nori sie sich hier, damit die nächste Folge genauso \
            startet.
            """
        )
    }
}

// MARK: - Qualität

/// Die Obergrenze der Bildhöhe.
struct SubtitlePrefSettingsView: View {
    @Environment(LibraryStore.self) private var library
    var body: some View {
        SettingsSelectionView(
            title: "Untertitelsprache",
            options: NoriSubtitleOption.allCases,
            label: \.label,
            note: \.note,
            selection: Binding(
                get: { NoriSubtitleOption.from(library.subtitlePref) },
                set: { library.subtitlePref = $0.rawValue }
            ),
            footnote: """
            Untertitel erscheinen nur, wo der Stream sie anbietet — viele Hoster \n            liefern gar keine. Ist die gewünschte Spur nicht vorhanden, nimmt Nori \n            eine andere, statt die Wiedergabe zu verhindern.
            """
        )
    }
}

/// Die Untertitel-Optionen — dieselben Sprachen wie die Tonspur plus „aus“.
enum NoriSubtitleOption: String, CaseIterable, Identifiable {
    case off
    case german = "DE"
    case english = "EN"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Aus"
        case .german: return "Deutsch"
        case .english: return "Englisch"
        }
    }
    var note: String {
        switch self {
        case .off: return "Keine Untertitel zeigen."
        case .german: return "Deutsche Untertitel, sofern vorhanden."
        case .english: return "Englische Untertitel, sofern vorhanden."
        }
    }
    static func from(_ raw: String) -> NoriSubtitleOption {
        NoriSubtitleOption(rawValue: raw) ?? .off
    }
}

struct QualitySettingsView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        SettingsSelectionView(
            title: "Videoqualität",
            options: NoriQualityOption.allCases,
            label: \.label,
            note: \.note,
            selection: Binding(
                get: { NoriQualityOption.from(library.preferredQuality) },
                set: { library.preferredQuality = $0.rawValue }
            ),
            footnote: """
            Die Stufen stammen aus der Playlist des Hosters. Liefert er nur eine \
            einzelne Datei — bei MP4 der Normalfall —, gibt es nichts zu wählen, \
            und Nori spielt, was da ist. Die Auswahl ist deshalb eine Obergrenze, \
            keine Garantie. Im Player lässt sich die Stufe für die laufende Folge \
            weiterhin einzeln umstellen.
            """
        )
    }
}

// MARK: - Hoster und Geschwindigkeit

/// Was in der Wiedergabe-Gruppe keinen Platz hat, aber seit Langem da ist und
/// wirkt: der bevorzugte Hoster und die Abspielgeschwindigkeit.
struct PlaybackSettingsView: View {
    @Environment(LibraryStore.self) private var library

    /// Dieselbe Reihenfolge wie `config/contract.json` unter `hosterOrder` —
    /// sie ist die Rangfolge, in der `HosterResolver` es versucht.
    private static let hosters = ["VOE", "Vidmoly", "Vidoza", "Lulustream", "SpeedFiles", "Filemoon", "Doodstream"]
    private static let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        @Bindable var library = library
        NoriGradientScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsGroup(
                        title: "Hoster",
                        footnote: """
                        Der gewünschte Hoster wird zuerst versucht. Antwortet er \
                        nicht, geht Nori die übrigen in der festgelegten \
                        Rangfolge durch — eine Folge bleibt deshalb abspielbar, \
                        auch wenn ein Hoster ausfällt.
                        """
                    ) {
                        SettingsRowContent(
                            symbol: "server.rack",
                            title: "Bevorzugter Hoster",
                            subtitle: "Wird zuerst versucht"
                        ) {
                            Picker("Bevorzugter Hoster", selection: $library.hosterPref) {
                                ForEach(Self.hosters, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                            .tint(NoriTheme.muted)
                        }
                    }

                    SettingsGroup(title: "Geschwindigkeit") {
                        SettingsRowContent(
                            symbol: "speedometer",
                            title: "Abspielgeschwindigkeit",
                            subtitle: "Gilt für neue Wiedergaben"
                        ) {
                            Picker("Abspielgeschwindigkeit", selection: $library.playbackSpeed) {
                                ForEach(Self.speeds, id: \.self) { speed in
                                    Text(Self.label(speed)).tag(speed)
                                }
                            }
                            .labelsHidden()
                            .tint(NoriTheme.muted)
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, NoriPanel.bottom)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Hoster und Geschwindigkeit")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// „1,25×" mit Komma — deutsche Schreibweise, wie überall in der App.
    private static func label(_ speed: Float) -> String {
        let text = String(format: "%g", speed).replacingOccurrences(of: ".", with: ",")
        return "\(text)×"
    }
}
