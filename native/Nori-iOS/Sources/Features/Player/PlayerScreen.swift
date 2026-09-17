import AVKit
import SwiftUI

struct PlayerScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    let series: SeriesDetail
    let season: String
    // Die Quelle gehört zur Wiedergabe, nicht zur Navigation im Hauptfenster.
    let provider: CatalogProvider

    @State private var currentEpisode: Episode
    @State private var currentResumeAt: Double
    @State private var currentPath: String = ""
    @State private var player: AVPlayer?
    @State private var status = "Hoster wird gelöst…"
    @State private var error: String?
    @State private var observer: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var source: PlaySource?
    @State private var watchInfo: WatchInfo?
    @State private var autoplaySeconds: Int?
    @State private var autoplayTask: Task<Void, Never>?
    @State private var failureObserver: NSObjectProtocol?
    @State private var statusTask: Task<Void, Never>?
    @State private var playbackGeneration = UUID()
    @State private var isSwitching = false
    /// Es läuft ein Wechsel, bei dem die Bedienung stehen bleiben soll —
    /// Hoster, Sprache, erneuter Versuch. Der Player wird dabei kurz
    /// abgeräumt; ohne dieses Merkmal fiele die Ansicht auf den Ladebildschirm
    /// zurück, und die eben benutzte Auswahl wäre mitsamt Leiste weg.
    @State private var keepChrome = false
    /// Ist die Bedienung sichtbar. Wird nie hart gesetzt, immer über
    /// `setControlsVisible` — sonst blenden Tipp, Knopfdruck und Zeitablauf
    /// mit drei verschiedenen Kurven ein und aus.
    @State private var controlsVisible = true
    /// Aufgabe, die die Bedienung nach ein paar Sekunden wieder wegnimmt.
    @State private var hideTask: Task<Void, Never>?
    /// Ein Menü der unteren Leiste steht offen. Solange bleibt die Bedienung
    /// stehen — sie unter dem geöffneten Menü wegzublenden wäre grotesk.
    @State private var menuOpen = false
    /// Der Regler wird gerade gezogen.
    @State private var scrubbing = false
    /// Läuft gerade ein Sprung. Verhindert, dass das Ziehen den Player mit
    /// Sprüngen überschwemmt; der jeweils letzte Wunsch wird nachgeholt.
    @State private var seeking = false
    @State private var pendingSeek: Double?
    /// Bild formatfüllend statt eingepasst. Auf einem iPhone im Querformat
    /// bleiben sonst breite schwarze Balken.
    @State private var fillVideo = false
    /// Die tatsächlich angebotenen Qualitätsstufen des laufenden Streams.
    /// Leer, wenn der Hoster nur eine Spur liefert — dann erscheint die
    /// Auswahl gar nicht.
    @State private var variants: [HLSVariant] = []
    @State private var activeQuality = PlayerScreen.qualityAuto
    /// Für die eigene Bedienung: Stand, Position und Puffer kamen vorher von
    /// AVKit und wurden nirgends gebraucht.
    @State private var isPlaying = false
    /// Stelle, Dauer und Puffer — ein eigenes Objekt, damit ihr Fortschreiten
    /// nur den Regler neu zeichnet und nicht den ganzen Player.
    @State private var clock = PlaybackClock()
    @State private var lastSaved: Double = 0
    /// Wo die Wiedergabe steht, wenn gerade kein Player läuft.
    ///
    /// Nach einem gescheiterten Start oder Hosterwechsel gibt es keinen
    /// Player, und `currentPosition()` lieferte 0. „Anderen Hoster versuchen"
    /// und „Noch einmal versuchen" begannen die Folge dann von vorn — bei
    /// einer halb gesehenen Folge ging die Stelle verloren.
    @State private var standingPosition: Double = 0
    @State private var subtitleGroup: AVMediaSelectionGroup?
    @State private var subtitleChoices: [PlayerChoice] = []
    @State private var activeSubtitle: String = PlayerScreen.subtitleOff
    @State private var pip = PictureInPicture()

    /// Kennung für „keine Untertitel". Ein leerer Text wäre als Auswahl nicht
    /// von „noch nichts gewählt" zu unterscheiden.
    static let subtitleOff = "__aus__"
    /// Dasselbe für „Qualität automatisch".
    static let qualityAuto = "__auto__" 
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @NoriReduceMotion private var reduceMotion
    @AppStorage(NoriGlassSetting.key) private var glass = true

    init(series: SeriesDetail, episode: Episode, season: String, resumeAt: Double, provider: CatalogProvider) {
        self.series = series
        self.season = season
        self.provider = provider
        _currentEpisode = State(initialValue: episode)
        _currentResumeAt = State(initialValue: resumeAt)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoSurface(player: player, onLayer: { layer in pip.attach(to: layer) }, fill: fillVideo)
                    .ignoresSafeArea()

                // Die Sprungfläche liegt **unter** der Bedienung. Tipper auf
                // freie Stellen fallen durch und schalten die Bedienung um;
                // Tipper auf einen Knopf fängt die Bedienung ab, solange sie
                // sichtbar ist.
                PlayerSeekOverlay(
                    step: 10,
                    onSingleTap: { toggleControls() },
                    onSeek: { delta in
                        seek(to: clock.latestPosition + delta)
                        scheduleHide()
                    }
                )
                .ignoresSafeArea()
            } else if !keepChrome {
                if let error {
                    errorView(error)
                } else {
                    loadingView
                }
                VStack {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: NoriControl.hit, height: NoriControl.hit)
                                .noriGlass(Circle(), enabled: glass, off: Color.white.opacity(0.22))
                        }
                        .buttonStyle(NoriPressStyle())
                        .accessibilityLabel("Wiedergabe schließen")
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }

            // Die Bedienung überlebt den Hosterwechsel. Während des Wechsels
            // gibt es keinen Player, aber Leisten, Titel und Fortschritt
            // stehen weiter; an der Stelle der Mitteltasten dreht sich ein
            // Ring. Ohne das sprang die Ansicht auf den Ladebildschirm, und
            // die eben benutzte Hosterliste war mitsamt Leiste verschwunden.
            if player != nil || keepChrome {
                controls
            }

            if let seconds = autoplaySeconds,
               let next = library.nextEpisode(after: currentEpisode, in: series.episodes) {
                autoplayCard(seconds: seconds, next: next)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(NoriMotion.allowed(NoriMotion.ui, reduceMotion: reduceMotion), value: autoplaySeconds != nil)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        // Ein Menü der unteren Leiste liegt in einem eigenen Fenster des
        // Systems. Das Schließen meldet der Menüknopf selbst (`onMenuClose`);
        // dass Noris Fenster wieder Schlüsselfenster wird, bleibt als zweites
        // Signal — auf iPadOS 26 kommt es nach einer Auswahl nicht immer.
        .onReceive(NotificationCenter.default.publisher(for: UIWindow.didBecomeKeyNotification)) { _ in
            guard menuOpen else { return }
            menuOpen = false
            scheduleHide()
        }
        // VoiceOver hält die Bedienung sichtbar — dann zieht auch der Regler mit.
        .onChange(of: voiceOverEnabled) { _, enabled in
            clock.isShown = controlsVisible || enabled || scrubbing
        }
        .task { await startPlayback(resumeAt: currentResumeAt) }
        .onDisappear { teardown(saveCurrent: true) }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(status)
                .foregroundStyle(.white.opacity(0.8))
                .font(.subheadline)
        }
    }

    /// Was steht, wenn kein Stream zustande kommt.
    ///
    /// Hoster fallen aus, liefern Schutzseiten oder Adressen, die AVPlayer
    /// nicht abspielt — das ist der Normalfall bei diesen Quellen, nicht die
    /// Ausnahme. Deshalb stehen hier die beiden Wege, die tatsächlich helfen,
    /// als gleichwertige Knöpfe: noch einmal versuchen und den nächsten
    /// Hoster nehmen. Welcher Hoster gescheitert ist, steht in der Meldung.
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.white.opacity(0.85))
                .symbolRenderingMode(.hierarchical)

            Text(message)
                .font(.callout)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            VStack(spacing: 10) {
                Button {
                    Task { await tryAlternativeHoster() }
                } label: {
                    Label("Anderen Hoster versuchen", systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(NoriTheme.bg)
                        .padding(.horizontal, 22)
                        .frame(height: NoriControl.hit)
                        .background(Capsule().fill(NoriTheme.fg))
                }
                .buttonStyle(NoriPressStyle(scale: 0.97))

                Button {
                    Task { await retry() }
                } label: {
                    Text("Noch einmal versuchen")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(height: NoriControl.hit)
                        .noriGlass(Capsule(), enabled: glass, off: Color.white.opacity(0.18))
                }
                .buttonStyle(NoriPressStyle(scale: 0.97))
            }
        }
        .padding(28)
    }

    /// Die Bedienung. Alle Auswahlmöglichkeiten liegen darin — Hoster,
    /// Qualität, Sprache, Untertitel, Geschwindigkeit —, statt dass eine
    /// davon als eigener Knopf über dem Bild schwebt.
    ///
    /// Jeder Rückruf über `Task { @MainActor in … }`: `controls` ist eine
    /// ausgelagerte View-Hilfe und damit **nicht** an den Main-Actor
    /// gebunden, `var body` dagegen schon. Ein direkter Aufruf einer
    /// @MainActor-Methode von hier aus ist ein Übersetzungsfehler — im
    /// iOS-Build schon zweimal passiert.
    private var controls: some View {
        PlayerControls(
            // Bei VoiceOver bleibt die Bedienung stehen: eine Leiste, die
            // sich nach vier Sekunden selbst entfernt, ist nicht bedienbar,
            // wenn man sie erst antippen und vorlesen lassen muss.
            visible: controlsVisible || voiceOverEnabled,
            seriesTitle: series.title,
            episodeSubtitle: "Staffel \(season) · Folge \(currentEpisode.number)",
            episodeNumber: episodeTitleText == nil ? nil : "Folge \(currentEpisode.number)",
            episodeTitle: episodeTitleText ?? "Folge \(currentEpisode.number)",
            isPlaying: isPlaying,
            clock: clock,
            speed: library.playbackSpeed,
            hosters: hosterChoices,
            activeHoster: source?.hoster,
            qualities: qualityChoices,
            activeQuality: activeQuality,
            languages: languageChoices,
            activeLanguage: source?.lang,
            subtitles: subtitleChoices,
            activeSubtitle: activeSubtitle,
            hasNextEpisode: library.nextEpisode(after: currentEpisode, in: series.episodes) != nil,
            isFilled: fillVideo,
            isSwitching: isSwitching,
            pip: pip,
            onClose: {
                Task { @MainActor in
                    save(forceComplete: false)
                    dismiss()
                }
            },
            onPlayPause: { Task { @MainActor in togglePlayback() } },
            onSkip: { seconds in
                Task { @MainActor in
                    seek(to: clock.latestPosition + seconds)
                    scheduleHide()
                }
            },
            onScrub: { target in Task { @MainActor in scrubSeek(to: target) } },
            onSeek: { target in Task { @MainActor in seek(to: target) } },
            onScrubbing: { active in
                Task { @MainActor in
                    scrubbing = active
                    clock.isShown = controlsVisible || voiceOverEnabled || active
                    if active {
                        hideTask?.cancel()
                        setControlsVisible(true)
                    } else {
                        scheduleHide()
                    }
                }
            },
            onSpeed: { value in
                Task { @MainActor in
                    library.playbackSpeed = value
                    player?.defaultRate = value
                    if isPlaying { player?.rate = value }
                    scheduleHide()
                }
            },
            onHoster: { hoster in
                Task { @MainActor in
                    scheduleHide()
                    await switchHoster(to: hoster)
                }
            },
            onQuality: { id in Task { @MainActor in selectQuality(id) } },
            onLanguage: { lang in
                Task { @MainActor in
                    scheduleHide()
                    await switchLanguage(to: lang)
                }
            },
            onSubtitle: { id in Task { @MainActor in selectSubtitle(id) } },
            onNextEpisode: { Task { @MainActor in await playNextEpisode() } },
            onToggleFill: {
                Task { @MainActor in
                    fillVideo.toggle()
                    scheduleHide()
                }
            },
            onMenuOpen: {
                Task { @MainActor in
                    menuOpen = true
                    hideTask?.cancel()
                }
            },
            onMenuClose: {
                Task { @MainActor in
                    guard menuOpen else { return }
                    menuOpen = false
                    scheduleHide()
                }
            }
        )
    }

    /// Der Titel der laufenden Folge, falls es einen gibt.
    ///
    /// „Episode 7" ist keiner, sondern die Nummer in Worten — beide Quellen
    /// setzen das ein, wo sie nichts Besseres haben. Dann steht unten nur
    /// „Folge 7", und die kleine Zeile darüber entfällt.
    private var episodeTitleText: String? {
        for candidate in [currentEpisode.germanTitle, currentEpisode.englishTitle] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let placeholder = trimmed.range(
                of: #"^\s*(episode|folge|ep\.?)\s*\d+\s*$"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
            if !placeholder { return trimmed }
        }
        return nil
    }

    private var hosterChoices: [PlayerChoice] {
        guard let info = watchInfo else { return [] }
        let available = HosterResolver.matching(info.hosters, language: source?.lang ?? library.langPref)
        return Array(Set(available.map(\.name)))
            .sorted { HosterResolver.rank($0) < HosterResolver.rank($1) }
            .map { PlayerChoice(id: $0, label: $0) }
    }

    private var languageChoices: [PlayerChoice] {
        guard let info = watchInfo else { return [] }
        return Array(Set(info.hosters.map(\.lang)))
            .sorted()
            .map { PlayerChoice(id: $0, label: languageLabel($0)) }
    }

    @MainActor
    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            // Angehalten ist der Moment, den Stand wirklich abzulegen: wer
            // danach das iPhone weglegt, soll genau dort weitermachen.
            save(forceComplete: false)
            library.flush()
            // Beim Anhalten sichtbar bleiben, sonst verschwindet die
            // Bedienung genau dann, wenn man sie sucht.
            hideTask?.cancel()
            setControlsVisible(true)
        } else {
            player.playImmediately(atRate: library.playbackSpeed)
            isPlaying = true
            scheduleHide()
        }
    }

    @MainActor
    private func seek(to seconds: Double) {
        guard let player, clock.duration > 0 else { return }
        let target = min(max(seconds, 0), clock.duration)
        clock.jump(to: target)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        savePosition(target, duration: clock.duration)
    }

    /// Ein Sprung während des Ziehens.
    ///
    /// Grob und mit Toleranz: das Bild soll dem Finger folgen, und ein
    /// bildgenauer Sprung viermal pro Sekunde bringt jeden Stream ins
    /// Stocken. Solange einer läuft, wird der nächste Wunsch nur gemerkt und
    /// danach nachgeholt — sonst stapeln sich beim Ziehen Dutzende Sprünge.
    @MainActor
    private func scrubSeek(to seconds: Double) {
        guard let player, clock.duration > 0 else { return }
        let target = min(max(seconds, 0), clock.duration)
        clock.jump(to: target)
        guard !seeking else {
            pendingSeek = target
            return
        }
        seeking = true
        let tolerance = CMTime(seconds: 0.6, preferredTimescale: 600)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { _ in
            Task { @MainActor in
                seeking = false
                if let next = pendingSeek {
                    pendingSeek = nil
                    scrubSeek(to: next)
                }
            }
        }
    }

    // MARK: - Sichtbarkeit der Bedienung

    /// Die einzige Stelle, an der sich die Sichtbarkeit ändert.
    ///
    /// Damit erscheint und verschwindet die Bedienung immer mit derselben
    /// Kurve, egal ob Tipp, Knopfdruck oder Zeitablauf sie ausgelöst hat.
    /// Hinein lebendig, hinaus ruhig — eine Feder auf dem Rückweg liest sich
    /// wie ein Fehler.
    @MainActor
    private func setControlsVisible(_ visible: Bool) {
        clock.isShown = visible || voiceOverEnabled || scrubbing
        let curve = visible ? NoriMotion.controlsIn : NoriMotion.controlsOut
        withAnimation(NoriMotion.allowed(curve, reduceMotion: reduceMotion)) {
            controlsVisible = visible
        }
    }

    @MainActor
    private func toggleControls() {
        // Ein Tipp aufs Bild heißt, dass kein Menü offen steht — ein offenes
        // hätte ihn geschluckt. Also auch hier zurücksetzen, falls das
        // Schließsignal einmal ausbleibt.
        menuOpen = false
        setControlsVisible(!controlsVisible)
        if controlsVisible { scheduleHide() }
    }

    /// Die Bedienung nach vier Sekunden wieder wegnehmen.
    ///
    /// Nicht ausgeblendet wird, solange etwas angehalten ist, ein Menü offen
    /// steht, der Regler gezogen wird oder VoiceOver läuft. Im Stehen die
    /// Bedienung wegzunehmen wäre die Zeit, in der man sie am ehesten
    /// braucht.
    @MainActor
    private func scheduleHide() {
        hideTask?.cancel()
        setControlsVisible(true)
        // Während eines Hosterwechsels gibt es keine Sprungfläche, über die
        // sich die Bedienung zurückholen ließe. Sie darf deshalb nicht
        // weggeblendet werden, sonst steht man vor einem schwarzen Bild ohne
        // jede Handhabe.
        guard isPlaying, !keepChrome, !menuOpen, !scrubbing, !voiceOverEnabled else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, isPlaying, !keepChrome, !menuOpen, !scrubbing, !voiceOverEnabled else { return }
            setControlsVisible(false)
        }
    }

    // MARK: - Qualität

    /// Die Stufen, die der laufende Stream wirklich anbietet.
    ///
    /// Nur bei einer HLS-Master-Playlist mit mehreren Spuren. Liefert der
    /// Hoster eine einzelne Datei — der Normalfall bei MP4 —, bleibt die
    /// Liste leer und die Auswahl erscheint nicht.
    private var qualityChoices: [PlayerChoice] {
        guard !variants.isEmpty else { return [] }
        return [PlayerChoice(id: Self.qualityAuto, label: "Automatisch")]
            + variants.map { PlayerChoice(id: $0.label, label: $0.label) }
    }

    /// Die Vorgabe aus „Mehr → Wiedergabe → Videoqualität" anwenden.
    ///
    /// Läuft genau einmal je Wiedergabe, sobald die Stufen der Playlist bekannt
    /// sind. Passt keine — weil „Automatisch" eingestellt ist, weil der Hoster
    /// nur eine Spur liefert oder weil alle Stufen über der Grenze liegen —,
    /// bleibt es bei der Automatik. Das ist die ehrlichere Antwort als die
    /// niedrigste Stufe zu erzwingen: für „höchstens 1080p" hat eine Playlist
    /// mit ausschliesslich 1440p und 2160p schlicht kein Angebot.
    ///
    /// Die Wahl im Player-Menü bleibt davon unberührt und gilt weiter für die
    /// laufende Folge — `selectQuality` schreibt sie nicht in die Einstellungen
    /// zurück, sonst wäre eine einmalige Sparmaßnahme unbemerkt zur Vorgabe
    /// geworden.
    @MainActor
    private func applyPreferredQuality(to item: AVPlayerItem) {
        let preference = NoriQualityOption.from(library.preferredQuality)
        guard let variant = preference.pick(from: variants) else { return }
        item.preferredPeakBitRate = Double(variant.bandwidth) * 1.05
        activeQuality = variant.label
    }

    /// Eine Stufe erzwingen.
    ///
    /// Über `preferredPeakBitRate`, den einzigen dokumentierten Weg, AVPlayer
    /// auf eine Spur festzulegen. Die Bitrate wird knapp über die der Stufe
    /// gesetzt, damit sie selbst noch hineinpasst, die nächsthöhere aber
    /// nicht mehr. `0` heißt „AVPlayer entscheidet".
    @MainActor
    private func selectQuality(_ id: String) {
        guard let item = player?.currentItem else { return }
        if id == Self.qualityAuto {
            item.preferredPeakBitRate = 0
        } else if let variant = variants.first(where: { $0.label == id }) {
            item.preferredPeakBitRate = Double(variant.bandwidth) * 1.05
        } else {
            return
        }
        activeQuality = id
        scheduleHide()
    }

    /// Untertitelspuren des Streams. Viele Hoster liefern gar keine — dann
    /// bleibt die Liste leer und das Menü erscheint nicht.
    @MainActor
    private func loadSubtitles(for item: AVPlayerItem) async {
        subtitleGroup = nil
        subtitleChoices = []
        activeSubtitle = Self.subtitleOff
        guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible),
              !group.options.isEmpty
        else { return }
        subtitleGroup = group
        subtitleChoices = [PlayerChoice(id: Self.subtitleOff, label: "Aus")]
            + group.options.map { PlayerChoice(id: $0.displayName, label: $0.displayName) }
        // Die gespeicherte Untertitel-Präferenz greift nur, wo der Stream Spuren
        // liefert. Sie ist ein Wunsch, kein Anspruch — wie auf webOS.
        if library.subtitlesEnabled {
            let want = library.subtitlePref
            if let option = preferredSubtitleOption(in: group, pref: want) {
                item.select(option, in: group)
                activeSubtitle = option.displayName
            }
        }
    }

    /// Die zur Präferenz passende Spur, falls der Stream eine führt. Nur eine
    /// ungefähre Übereinstimmung — die Anzeigen der Hoster sind nicht normiert.
    private func preferredSubtitleOption(in group: AVMediaSelectionGroup, pref: String) -> AVMediaSelectionOption? {
        guard !pref.isEmpty, pref != "off" else { return nil }
        let needle = pref.lowercased()
        return group.options.first { $0.displayName.lowercased().contains(needle) } ?? group.options.first
    }

    @MainActor
    private func selectSubtitle(_ id: String) {
        guard let group = subtitleGroup, let item = player?.currentItem else { return }
        if id == Self.subtitleOff {
            item.select(nil, in: group)
        } else if let option = group.options.first(where: { $0.displayName == id }) {
            item.select(option, in: group)
        }
        activeSubtitle = id
        scheduleHide()
    }

    /// Die Karte für die nächste Folge.
    ///
    /// Der Countdown steht als Ring um den Startknopf, nicht als Zahl im
    /// Fließtext: er zeigt die verbleibende Zeit, ohne dass man mitlesen
    /// muss, und der Knopf darunter ist das, was man ohnehin ansteuert.
    private func autoplayCard(seconds: Int, next: Episode) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nächste Folge")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(nextEpisodeTitle(next))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button("Abbrechen") { Task { @MainActor in cancelAutoplay() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .noriGlass(Capsule(), off: Color.white.opacity(0.18))
                    .buttonStyle(NoriPressStyle())

                Button {
                    autoplayTask?.cancel()
                    autoplaySeconds = nil
                    Task { await playNextEpisode() }
                } label: {
                    ZStack {
                        // Der Ring läuft von voll auf leer. Die Feder je
                        // Sekunde statt einer linearen Bewegung: der Wert
                        // kommt sekundenweise, ein linearer Übergang wirkt
                        // dabei ruckartig.
                        Circle()
                            .stroke(.white.opacity(0.22), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: min(max(Double(seconds) / 8, 0), 1))
                            .stroke(NoriTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .noriAnimation(NoriMotion.content, value: seconds)
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 46, height: 46)
                }
                .buttonStyle(NoriPressStyle())
                .accessibilityLabel("Nächste Folge jetzt abspielen")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: NoriRadius.overlay, style: .continuous))
            .noriGlass(
                RoundedRectangle(cornerRadius: NoriRadius.overlay, style: .continuous),
                off: Color.clear
            )
            .padding(.horizontal, NoriSpacing.screen)
            .padding(.bottom, 8)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func nextEpisodeTitle(_ next: Episode) -> String {
        let title = next.germanTitle.isEmpty ? next.englishTitle : next.germanTitle
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Folge \(next.number)" }
        return "Folge \(next.number) · \(trimmed)"
    }

    @MainActor
    func startPlayback(
        preferredHoster: String? = nil,
        preferredLang: String? = nil,
        resumeAt: Double? = nil
    ) async {
        cancelAutoplay()
        let targetResume = resumeAt ?? currentResumeAt
        clearPlayer(saveCurrent: false)
        standingPosition = targetResume
        let generation = playbackGeneration
        error = nil
        source = nil
        variants = []
        activeQuality = Self.qualityAuto
        watchInfo = nil
        // Beim Wechsel bleibt die Dauer stehen: der Regler soll nicht auf
        // null zusammenfallen und gleich darauf wieder aufspringen. Es ist
        // dieselbe Folge, nur ein anderer Hoster.
        if !keepChrome { clock.reset(position: 0, keepDuration: false) }
        isSwitching = true

        do {
            status = "Folge wird gelesen…"
            let path = currentEpisode.path.isEmpty
                ? guessEpisodePath(slug: series.slug, season: season, episode: currentEpisode.number, provider: provider)
                : currentEpisode.path
            currentPath = normalizeEpisodePath(path)

            let info = try await AniworldClient.shared.getWatch(provider: provider, path: path)
            guard generation == playbackGeneration, !Task.isCancelled else { return }
            watchInfo = info
            status = "Stream wird geholt…"

            // Bei einer ausdrücklichen Wahl nur passende Angebote versuchen.
            // Automatischer Start darf weiterhin die gespeicherten Präferenzen nutzen.
            let candidates: [HosterOption]
            if let language = preferredLang {
                candidates = HosterResolver.matching(info.hosters, language: language, hoster: preferredHoster)
                guard !candidates.isEmpty else {
                    throw NoriError.hoster("Für diese Auswahl ist kein Stream verfügbar.")
                }
            } else {
                candidates = info.hosters
            }
            let play = try await HosterResolver.resolveBest(
                hosters: candidates,
                preferredHoster: preferredHoster ?? library.hosterPref,
                preferredLang: preferredLang ?? library.langPref,
                episodePath: currentPath,
                provider: provider
            )
            guard generation == playbackGeneration, !Task.isCancelled else { return }
            source = play
            library.hosterPref = play.hoster
            library.langPref = play.lang

            guard let url = URL(string: play.url) else {
                throw NoriError.hoster("Ungültige Stream-URL")
            }

            // Hoster liefern das Video meist nur mit passendem Referer und
            // User-Agent aus. AVPlayer schickt von sich aus keinen, weshalb der
            // Player sonst mit leerem Bild und --:-- stehen bleibt.
            var headers = ["User-Agent": NoriOrigin.ua]
            if let referer = play.referer {
                headers["Referer"] = referer
                if let refererURL = URL(string: referer), let origin = originHeader(refererURL) {
                    headers["Origin"] = origin
                }
            }
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let item = AVPlayerItem(asset: asset)
            let titleMetadata = AVMutableMetadataItem()
            titleMetadata.identifier = .commonIdentifierTitle
            titleMetadata.value = (series.title + " – Folge " + String(currentEpisode.number)) as NSString
            titleMetadata.extendedLanguageTag = "und"
            item.externalMetadata = [titleMetadata]
            let av = AVPlayer(playerItem: item)
            av.actionAtItemEnd = .pause
            av.defaultRate = library.playbackSpeed

            if targetResume >= 8 {
                let t = CMTime(seconds: targetResume, preferredTimescale: 600)
                await av.seek(to: t)
            }

            guard generation == playbackGeneration, !Task.isCancelled else { return }

            // Scheitert die Wiedergabe selbst, meldet AVKit das nicht sichtbar.
            // Den Fehler in die eigene Fehleransicht holen, damit nicht nur ein
            // graues Bild dasteht.
            failureObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { note in
                let reason = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                    .localizedDescription ?? "Unbekannter Fehler"
                Task { @MainActor in
                    guard generation == playbackGeneration else { return }
                    reportPlaybackFailure(reason)
                }
            }

            av.playImmediately(atRate: library.playbackSpeed)

            // Vierteltakt statt alle fünf Sekunden: der Regler soll mitlaufen.
            // Gespeichert wird trotzdem nur alle fünf Sekunden — der Stand
            // gehört auf die Platte, nicht viermal pro Sekunde.
            observer = av.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                queue: .main
            ) { time in
                guard generation == playbackGeneration else { return }
                let pos = time.seconds
                guard pos.isFinite else { return }
                let dur = item.duration.seconds
                let end = item.loadedTimeRanges.last.map {
                    ($0.timeRangeValue.start + $0.timeRangeValue.duration).seconds
                }
                // Nur die Uhr. Der Player selbst zeichnet dafür nicht neu.
                clock.tick(position: pos, duration: dur, buffered: end)
                // `.playing` allein wäre falsch: beim Puffern steht der
                // Stand auf `.waitingToPlayAtSpecifiedRate`, und das viermal
                // pro Sekunde. Das Symbol sprang dann zwischen Pause und
                // Abspielen hin und her, und die Bedienung blendete beim
                // Nachladen nicht mehr weg, weil sie sich für angehalten
                // hielt. Gemeint ist „läuft, oder will laufen".
                let running = av.timeControlStatus != .paused
                if running != isPlaying {
                    isPlaying = running
                    // Fängt die Wiedergabe erst nach dem Puffern an, muss
                    // das Wegblenden von hier aus angestoßen werden — beim
                    // Start lief es ins Leere.
                    //
                    // Über `Task { @MainActor in … }`: der Beobachter läuft
                    // zwar auf der Hauptwarteschlange, ist dem Compiler
                    // gegenüber aber nicht an den Main-Actor gebunden. Ein
                    // direkter Aufruf ist unter Swift 6 ein Fehler und hier
                    // schon eine Warnung.
                    if running { Task { @MainActor in scheduleHide() } }
                }
                if pos - lastSaved >= 5 || lastSaved == 0 {
                    lastSaved = pos
                    savePosition(pos, duration: clock.duration)
                }
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    guard generation == playbackGeneration else { return }
                    save(forceComplete: true)
                    handleEpisodeEnded()
                }
            }

            player = av
            isPlaying = true
            clock.reset(position: targetResume >= 8 ? targetResume : 0, keepDuration: true)
            lastSaved = 0
            await loadSubtitles(for: item)
            currentResumeAt = 0
            // Nach dem Start die Bedienung zeigen und den Wegblendezähler
            // anwerfen — sonst steht sie beim Hosterwechsel stumm da oder
            // fehlt beim ersten Bild ganz.
            scheduleHide()
            // Die Qualitätsstufen erst danach: sie brauchen einen zweiten
            // Abruf der Playlist, und der darf den Start nicht aufhalten.
            Task { @MainActor in
                let found = await HLSPlaylist.variants(of: url, referer: play.referer)
                guard generation == playbackGeneration, !Task.isCancelled else { return }
                variants = found
                // Erst jetzt lässt sich die Vorgabe aus den Einstellungen
                // anwenden: vorher war nicht bekannt, welche Stufen es gibt.
                applyPreferredQuality(to: item)
            }
            statusTask = Task { @MainActor in
                // AVPlayerItem meldet .failed asynchron, nachdem der erste
                // Datenabruf fehlgeschlagen ist.
                for _ in 0 ..< 40 {
                    if Task.isCancelled || generation != playbackGeneration { return }
                    if item.status == .failed {
                        reportPlaybackFailure(item.error?.localizedDescription ?? "Stream nicht abspielbar")
                        return
                    }
                    if item.status == .readyToPlay { return }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        } catch {
            guard generation == playbackGeneration, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        isSwitching = false
        keepChrome = false
    }

    /// Nur „https://host" — manche Hoster prüfen Origin zusätzlich zum Referer.
    private func originHeader(_ url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        return "\(scheme)://\(host)"
    }

    @MainActor
    private func reportPlaybackFailure(_ reason: String) {
        guard error == nil else { return }
        let hoster = source?.hoster ?? "Hoster"
        clearPlayer(saveCurrent: true)
        error = "\(hoster) lieferte eine Adresse, die sich nicht abspielen lässt.\n\(reason)"
    }

    @MainActor
    func retry() async {
        let at = currentPosition()
        keepChrome = player != nil
        hideTask?.cancel()
        setControlsVisible(true)
        await startPlayback(resumeAt: at)
    }

    @MainActor
    func tryAlternativeHoster() async {
        guard let info = watchInfo else {
            await retry()
            return
        }
        let current = source?.hoster.lowercased()
        let options = HosterResolver.ordered(
            HosterResolver.matching(info.hosters, language: source?.lang ?? library.langPref),
            preferred: nil
        )
        guard let alternative = options.first(where: { $0.name.lowercased() != current }) else {
            error = "Kein weiterer Hoster verfügbar."
            return
        }
        await switchHoster(to: alternative.name)
    }

    @MainActor
    func switchHoster(to hoster: String) async {
        let at = currentPosition()
        keepChrome = player != nil
        hideTask?.cancel()
        setControlsVisible(true)
        save(forceComplete: false)
        await startPlayback(preferredHoster: hoster, preferredLang: source?.lang ?? library.langPref, resumeAt: at)
    }

    @MainActor
    func switchLanguage(to lang: String) async {
        let at = currentPosition()
        keepChrome = player != nil
        hideTask?.cancel()
        setControlsVisible(true)
        save(forceComplete: false)
        await startPlayback(preferredLang: lang, resumeAt: at)
    }

    @MainActor
    func setPlaybackSpeed(_ speed: Float) {
        library.playbackSpeed = speed
        player?.defaultRate = speed
        if player?.timeControlStatus == .playing {
            player?.rate = speed
        }
    }

    @MainActor
    func handleEpisodeEnded() {
        guard library.autoplayNext,
              library.nextEpisode(after: currentEpisode, in: series.episodes) != nil
        else { return }

        autoplayTask?.cancel()
        autoplaySeconds = 8
        autoplayTask = Task {
            for remaining in stride(from: 8, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                await MainActor.run { autoplaySeconds = remaining }
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            // Nicht in dieser Aufgabe weiter: `switchEpisode` bricht
            // `autoplayTask` ab — also genau die Aufgabe, in der es liefe. Der
            // Abruf der nächsten Folge kam dann abgebrochen zurück, wurde als
            // veraltet verworfen, und der Player stand ohne Meldung bei
            // „Folge wird gelesen…" (beobachtet: über zwei Minuten nach dem
            // Ende von Folge 1). Die neue Folge startet in einer eigenen Aufgabe.
            await MainActor.run {
                autoplayTask = nil
                Task { await playNextEpisode() }
            }
        }
    }

    @MainActor
    func playNextEpisode() async {
        guard let next = library.nextEpisode(after: currentEpisode, in: series.episodes) else {
            autoplaySeconds = nil
            return
        }
        autoplayTask?.cancel()
        autoplaySeconds = nil
        clearPlayer(saveCurrent: false)
        currentEpisode = next
        currentResumeAt = library.resumeEnabled
            ? resumePosition(library.progress(slug: series.slug, season: season, episode: next.number, path: next.path, provider: provider))
            : 0
        await startPlayback(resumeAt: currentResumeAt)
    }

    @MainActor
    func cancelAutoplay() {
        autoplayTask?.cancel()
        autoplayTask = nil
        autoplaySeconds = nil
    }

    func savePosition(_ pos: Double, duration dur: Double) {
        guard pos >= 2 else { return }
        let path = currentPath.isEmpty ? currentEpisode.path : currentPath
        library.upsert(
            WatchProgress(
                slug: series.slug,
                title: series.title,
                season: season,
                episode: currentEpisode.number,
                episodePath: path,
                germanTitle: currentEpisode.germanTitle,
                englishTitle: currentEpisode.englishTitle,
                positionSec: pos,
                durationSec: dur.isFinite ? dur : clock.duration,
                updatedAt: Date().timeIntervalSince1970 * 1000,
                lang: source?.lang ?? library.langPref,
                completed: dur >= 20 && pos >= dur * 0.9,
                provider: provider
            )
        )
    }

    func save(forceComplete: Bool) {
        guard player != nil || clock.duration > 0 else { return }
        let pos = player?.currentTime().seconds ?? 0
        var dur = player?.currentItem?.duration.seconds ?? clock.duration
        if !dur.isFinite { dur = clock.duration }
        let path = currentPath.isEmpty ? currentEpisode.path : currentPath
        library.upsert(
            WatchProgress(
                slug: series.slug,
                title: series.title,
                season: season,
                episode: currentEpisode.number,
                episodePath: path,
                germanTitle: currentEpisode.germanTitle,
                englishTitle: currentEpisode.englishTitle,
                positionSec: forceComplete ? max(pos, dur) : pos,
                durationSec: dur,
                updatedAt: Date().timeIntervalSince1970 * 1000,
                lang: source?.lang ?? library.langPref,
                completed: forceComplete || (dur >= 20 && pos >= dur * 0.9),
                provider: provider
            )
        )
    }

    func currentPosition() -> Double {
        guard let player else { return standingPosition }
        let pos = player.currentTime().seconds
        return pos.isFinite ? pos : standingPosition
    }

    @MainActor
    func clearPlayer(saveCurrent: Bool) {
        playbackGeneration = UUID()
        if saveCurrent { save(forceComplete: false) }
        if let observer, let player { player.removeTimeObserver(observer) }
        observer = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        statusTask?.cancel()
        statusTask = nil
        if let pos = player?.currentTime().seconds, pos.isFinite, pos > 0 {
            standingPosition = pos
        }
        player?.pause()
        player = nil
    }

    @MainActor
    func teardown(saveCurrent: Bool) {
        cancelAutoplay()
        clearPlayer(saveCurrent: saveCurrent)
        // Was während der Wiedergabe nur im Speicher stand, jetzt auf die
        // Platte — und „Weiterschauen" sieht den neuen Stand.
        library.flush()
    }

    func languageLabel(_ lang: String) -> String {
        switch lang.lowercased() {
        case "de": return "GerDub"
        case "gersub": return "GerSub"
        case "en": return "EN"
        default: return lang
        }
    }

    func speedLabel(_ speed: Float) -> String {
        if abs(speed - 1) < 0.01 { return "1×" }
        return String(format: "%g×", speed)
    }
}
