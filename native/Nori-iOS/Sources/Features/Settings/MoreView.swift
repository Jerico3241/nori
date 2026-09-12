import SwiftUI

/// Noris Mehr-Bereich.
///
/// Aufbau nach `nori-settings-v1.html`: Titel, Bibliothekskarte, Abgleichkarte
/// und darunter vier Gruppen — Wiedergabe, Darstellung, Bibliothek & Daten,
/// Nori.
///
/// ## Jede Zeile tut etwas
///
/// Das ist die Regel, an der sich diese Seite messen lässt. Keine Zeile steht
/// hier, weil sie auf der Vorlage gut aussieht: jede ist eine Einstellung, eine
/// Auskunft oder ein Weg zu einer Seite. Wo Nori etwas nicht kann, steht das
/// auch so da — die Abgleichkarte zeigt „Nicht eingerichtet" statt eines grünen
/// „AKTIV", und die Zeile zum Erscheinungsbild sagt, dass Nori dunkel ist,
/// statt eine Wahl anzubieten, die nichts ändert.
///
/// ## Wo die Werte liegen
///
/// Wiedergabe in `LibraryStore` (und damit in `library.json`, mit dem Abgleich),
/// Darstellung in `@AppStorage` (auf diesem Gerät). Warum getrennt, steht in
/// `NoriSettings.swift`. Ein zweites Einstellungssystem gibt es nicht.
struct MoreView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(GoogleDriveSync.self) private var sync

    @AppStorage(NoriGlassSetting.key) private var liquidGlass = true
    @AppStorage(NoriLook.dynamicColorsKey) private var dynamicColors = true
    @AppStorage(NoriLook.reduceMotionKey) private var reduceMotionPreference = false

    /// Die Größe der Bildablage. Wird nachgetragen, nicht beim Aufbau
    /// berechnet — siehe `NoriImageCache.measure`.
    @State private var cacheSize: Int64?
    @State private var tmdbReachable: Bool?

    var body: some View {
        @Bindable var library = library
        NoriGradientScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header
                    SettingsProfileCard(
                        favorites: library.favorites.count,
                        inProgress: startedEpisodes,
                        syncName: isConnected ? "Google Drive" : nil
                    )
                    SettingsSyncCard(state: syncState)

                    playback(library: library)
                    appearance
                    data
                    about

                    attribution
                }
                .padding(.top, 6)
                .padding(.bottom, NoriPanel.bottom)
            }
            .scrollIndicators(.hidden)
            .noriSoftScrollEdges(.bottom)
        }
        // Der Kopfbereich bringt den Titel selbst mit; eine zweite Leiste
        // darüber wäre doppelt.
        .toolbar(.hidden, for: .navigationBar)
        // Beides kostet Zeit und darf den Aufbau nicht aufhalten: die
        // Cachegröße liest Verzeichnisse, die TMDB-Prüfung geht ans Netz.
        .task { await measureCache() }
        .task { tmdbReachable = await NoriDiagnostics.checkTMDB().isHealthy }
    }

    // MARK: - Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Nori")
                .font(.caption2.weight(.heavy))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(NoriTheme.muted)
            Text("Mehr")
                .font(.system(size: 38, weight: .bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(.horizontal, NoriSpacing.screen)
    }

    // MARK: - Wiedergabe

    private func playback(library: LibraryStore) -> some View {
        @Bindable var library = library
        return SettingsGroup(title: "Wiedergabe") {
            SettingsToggleRow(
                symbol: "play.fill",
                title: "Autoplay",
                subtitle: "Nächste Episode automatisch starten",
                isOn: $library.autoplayNext
            )
            SettingsDivider()
            SettingsLinkRow(
                symbol: "character.bubble",
                title: "Bevorzugte Sprache",
                subtitle: "Standard für neue Wiedergaben",
                value: NoriLanguageOption.from(library.langPref).label
            ) {
                LanguageSettingsView()
            }
            SettingsDivider()
            SettingsLinkRow(
                symbol: "rectangle.on.rectangle",
                title: "Videoqualität",
                subtitle: "Obergrenze, wo der Hoster Stufen anbietet",
                value: NoriQualityOption.from(library.preferredQuality).label
            ) {
                QualitySettingsView()
            }
            SettingsDivider()
            SettingsToggleRow(
                symbol: "arrow.clockwise",
                title: "Resume automatisch",
                subtitle: "An gespeicherter Position fortsetzen",
                isOn: $library.resumeEnabled
            )
            SettingsDivider()
            SettingsLinkRow(
                symbol: "slider.horizontal.3",
                title: "Hoster und Geschwindigkeit",
                subtitle: "Bevorzugter Hoster, Abspielgeschwindigkeit"
            ) {
                PlaybackSettingsView()
            }
        }
    }

    // MARK: - Darstellung

    private var appearance: some View {
        SettingsGroup(
            title: "Darstellung",
            footnote: """
            Nori ist durchgehend dunkel gestaltet — Poster, Breitbilder und der \
            Player rechnen damit. Eine helle Fassung gibt es deshalb nicht; ein \
            Schalter dafür würde hier nichts ändern.
            """
        ) {
            SettingsInfoRow(
                symbol: "circle.lefthalf.filled",
                tint: .violet,
                title: "Erscheinungsbild",
                subtitle: "App-Darstellung",
                value: "Dunkel"
            )
            SettingsDivider()
            SettingsToggleRow(
                symbol: "drop.halffull",
                tint: .violet,
                title: "Liquid Glass",
                subtitle: glassNote,
                isOn: $liquidGlass
            )
            SettingsDivider()
            SettingsToggleRow(
                symbol: "sparkles",
                tint: .violet,
                title: "Dynamische Farben",
                subtitle: "Artwork-Farben in Hintergründen verwenden",
                isOn: $dynamicColors
            )
            SettingsDivider()
            SettingsToggleRow(
                symbol: "wave.3.right",
                tint: .violet,
                title: "Animationen reduzieren",
                subtitle: reduceMotionNote,
                isOn: $reduceMotionPreference
            )
        }
    }

    private var glassNote: String {
        NoriGlassChip<EmptyView>.systemHasGlass
            ? "Schwebende Bedienelemente aus Glas statt getönter Flächen"
            : "Braucht iOS 26 — auf diesem System getönte Flächen"
    }

    private var reduceMotionNote: String {
        // Ist die Systemeinstellung an, ist Noris Schalter wirkungslos — er
        // kann Bewegung nur zusätzlich abschalten, nie wieder einschalten.
        systemReduceMotion
            ? "Bereits über die Systemeinstellungen aktiv"
            : "Weniger Bewegungen in der Oberfläche"
    }

    // MARK: - Bibliothek & Daten

    private var data: some View {
        SettingsGroup(title: "Bibliothek & Daten") {
            SettingsLinkRow(
                symbol: "arrow.triangle.2.circlepath",
                tint: .green,
                title: "Synchronisation",
                subtitle: "Merkliste, Verlauf und Fortschritt über Google Drive",
                value: cardState.pill
            ) {
                SyncSettingsView()
            }
            SettingsDivider()
            SettingsLinkRow(
                symbol: "clock.arrow.circlepath",
                tint: .green,
                title: "Verlauf",
                subtitle: "Zuletzt angesehene Titel verwalten",
                value: library.recents.isEmpty ? "leer" : "\(library.recents.count)"
            ) {
                HistoryView()
            }
            SettingsDivider()
            SettingsLinkRow(
                symbol: "photo.stack",
                tint: .orange,
                title: "Bild-Cache",
                subtitle: "Poster, Breitbilder und Folgenbilder",
                value: cacheSize.map(NoriImageCache.format) ?? "…"
            ) {
                CacheSettingsView()
            }
        }
    }

    // MARK: - Nori

    private var about: some View {
        SettingsGroup(title: "Nori") {
            SettingsLinkRow(
                symbol: "info.circle",
                title: "Über Nori",
                subtitle: "Version, Build und verwendete Dienste",
                value: NoriBuild.version
            ) {
                AboutView()
            }
            SettingsDivider()
            SettingsLinkRow(
                symbol: "square.stack.3d.up",
                title: "TMDB",
                subtitle: "Metadaten und Artwork",
                value: tmdbValue
            ) {
                MetadataSettingsView()
            }
            SettingsDivider()
            SettingsLinkRow(
                symbol: "stethoscope",
                tint: .red,
                title: "Diagnose",
                subtitle: "Provider- und Metadatenstatus prüfen"
            ) {
                DiagnosticsView()
            }
        }
    }

    /// Der TMDB-Zustand in drei Stufen — ohne Schlüssel gibt es nichts zu
    /// erreichen, und „Verbunden" wäre dann falsch.
    private var tmdbValue: String {
        guard TMDBKeyStore.current != nil else { return "Kein Schlüssel" }
        switch tmdbReachable {
        case .none: return "…"
        case .some(true): return "Verbunden"
        case .some(false): return "Nicht erreichbar"
        }
    }

    private var attribution: some View {
        VStack(spacing: 3) {
            Text("Nori \(NoriBuild.version)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(NoriTheme.muted)
            Text("Metadaten durch TMDB · Streams über AniWorld und Serienstream")
                .font(.caption2)
                .foregroundStyle(NoriTheme.muted.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, NoriSpacing.screen)
        .padding(.top, 4)
    }

    // MARK: - Abgeleitetes

    /// Der Zustand, den die Abgleichkarte zeigt — aus dem Store, nicht
    /// geschrieben.
    private var syncState: SettingsSyncCard.State { cardState }

    private var isConnected: Bool {
        if case .disconnected = sync.status { return false }
        return sync.isConfigured
    }

    /// Der Zustand, den die Abgleichkarte zeigt — aus der Engine, nicht
    /// geschrieben.
    private var cardState: SettingsSyncCard.State {
        guard sync.isConfigured else { return .notConfigured }
        let name = "Google Drive"
        let lastRun = sync.lastSuccessfulSync.map { Date(timeIntervalSince1970: $0 / 1000) }
        switch sync.status {
        case .disconnected: return .disconnected(name: name)
        case .authorizing: return .authorizing(name: name)
        case .idle: return .idle(name: name, lastRun: lastRun)
        case .syncing: return .running(name: name)
        case .offline: return .offline(name: name, lastRun: lastRun)
        case .error(let message): return .failed(name: name, message: message)
        case .unsupportedRemoteVersion: return .needsUpdate(name: name)
        }
    }

    /// Wie viele Folgen angefangen und nicht abgeschlossen sind.
    private var startedEpisodes: Int {
        library.progress.values.filter { $0.positionSec > 0 && $0.completed != true }.count
    }

    /// Apples Systemeinstellung. Nur für den Hinweistext — wirksam wird sie in
    /// `RootView`, wo sie mit Noris Schalter verodert wird.
    private var systemReduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    private func measureCache() async {
        cacheSize = await NoriImageCache.measure()
    }
}
