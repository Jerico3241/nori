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
    @State private var duration: Double = 0
    @State private var source: PlaySource?
    @State private var watchInfo: WatchInfo?
    @State private var autoplaySeconds: Int?
    @State private var autoplayTask: Task<Void, Never>?
    @State private var failureObserver: NSObjectProtocol?
    @State private var statusTask: Task<Void, Never>?
    @State private var playbackGeneration = UUID()
    @State private var isSwitching = false
    @State private var optionsVisible = true
    @State private var optionsTick = 0
    /// Für die eigene Bedienung: Stand, Position und Puffer kamen vorher von
    /// AVKit und wurden nirgends gebraucht.
    @State private var isPlaying = false
    @State private var position: Double = 0
    @State private var buffered: Double = 0
    @State private var lastSaved: Double = 0
    @State private var subtitleGroup: AVMediaSelectionGroup?
    @State private var subtitleChoices: [PlayerChoice] = []
    @State private var activeSubtitle: String = PlayerScreen.subtitleOff
    @State private var pip = PictureInPicture()

    /// Kennung für „keine Untertitel". Ein leerer Text wäre als Auswahl nicht
    /// von „noch nichts gewählt" zu unterscheiden.
    static let subtitleOff = "__aus__" 
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

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
                VideoSurface(player: player) { layer in pip.attach(to: layer) }
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) { optionsVisible.toggle() }
                        if optionsVisible { optionsTick &+= 1 }
                    }
                    .overlay {
                        if optionsVisible || voiceOverEnabled {
                            controls.transition(.opacity)
                        }
                    }
                    // Nur ausblenden, während etwas läuft. Im Stehen die
                    // Bedienung wegzunehmen wäre die Zeit, in der man sie
                    // am ehesten braucht.
                    .task(id: optionsTick) {
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled, !voiceOverEnabled, isPlaying else { return }
                        withAnimation(.easeOut(duration: 0.25)) { optionsVisible = false }
                    }
            } else {
                if let error {
                    errorView(error)
                } else {
                    loadingView
                }
                VStack {
                    HStack {
                        Button("Schließen", systemImage: "xmark") { dismiss() }
                            .buttonStyle(.bordered)
                        Spacer()
                    }
                    Spacer()
                }
                .padding()
            }
            if let seconds = autoplaySeconds,
               let next = library.nextEpisode(after: currentEpisode, in: series.episodes) {
                autoplayCard(seconds: seconds, next: next)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
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

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.85))
            Text(message)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Erneut versuchen") {
                    Task { await retry() }
                }
                .buttonStyle(.borderedProminent)

                Button("Anderen Hoster") {
                    Task { await tryAlternativeHoster() }
                }
                .buttonStyle(.bordered)

                Button("Schließen") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
    }

    /// Die eigene Bedienleiste. Alle Auswahlmöglichkeiten liegen darin —
    /// Hoster, Sprache, Untertitel und Geschwindigkeit —, statt dass eine
    /// davon als eigener Knopf über dem Bild schwebt.
    private var controls: some View {
        PlayerControls(
            title: series.title,
            subtitle: "Staffel \(season) · Folge \(currentEpisode.number)",
            isPlaying: isPlaying,
            position: position,
            duration: duration,
            buffered: buffered,
            speed: library.playbackSpeed,
            hosters: hosterChoices,
            activeHoster: source?.hoster,
            languages: languageChoices,
            activeLanguage: source?.lang,
            subtitles: subtitleChoices,
            activeSubtitle: activeSubtitle,
            pip: pip,
            // Jeder Rückruf über `Task { @MainActor in … }`: `controls` ist
            // eine ausgelagerte View-Hilfe und damit **nicht** an den
            // Main-Actor gebunden, `var body` dagegen schon. Ein direkter
            // Aufruf einer @MainActor-Methode von hier aus ist ein
            // Übersetzungsfehler — im iOS-Build schon zweimal passiert.
            onClose: {
                Task { @MainActor in
                    save(forceComplete: false)
                    dismiss()
                }
            },
            onPlayPause: { Task { @MainActor in togglePlayback() } },
            onSkip: { seconds in Task { @MainActor in seek(to: position + seconds) } },
            onSeek: { target in Task { @MainActor in seek(to: target) } },
            onScrubbing: { active in
                // Während gezogen wird nicht wegblenden.
                Task { @MainActor in
                    if active { optionsVisible = true } else { optionsTick &+= 1 }
                }
            },
            onSpeed: { value in
                Task { @MainActor in
                    library.playbackSpeed = value
                    player?.defaultRate = value
                    if isPlaying { player?.rate = value }
                    optionsTick &+= 1
                }
            },
            onHoster: { hoster in
                Task { @MainActor in
                    optionsTick &+= 1
                    await switchHoster(to: hoster)
                }
            },
            onLanguage: { lang in
                Task { @MainActor in
                    optionsTick &+= 1
                    await switchLanguage(to: lang)
                }
            },
            onSubtitle: { id in Task { @MainActor in selectSubtitle(id) } }
        )
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
            // Beim Anhalten sichtbar bleiben, sonst verschwindet die
            // Bedienung genau dann, wenn man sie sucht.
            optionsVisible = true
        } else {
            player.playImmediately(atRate: library.playbackSpeed)
            isPlaying = true
            optionsTick &+= 1
        }
    }

    @MainActor
    private func seek(to seconds: Double) {
        guard let player, duration > 0 else { return }
        let target = min(max(seconds, 0), duration)
        position = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        savePosition(target, duration: duration)
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
        optionsTick &+= 1
    }

    private func autoplayCard(seconds: Int, next: Episode) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nächste Folge")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                    Text("Folge \(next.number) startet in \(seconds) s")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                Button("Abbrechen") { Task { @MainActor in cancelAutoplay() } }
                    .buttonStyle(.bordered)
                Button("Jetzt abspielen") {
                    autoplayTask?.cancel()
                    autoplaySeconds = nil
                    Task { await playNextEpisode() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
            .padding()
        }
    }

    @MainActor
    func startPlayback(
        preferredHoster: String? = nil,
        preferredLang: String? = nil,
        resumeAt: Double? = nil
    ) async {
        cancelAutoplay()
        clearPlayer(saveCurrent: false)
        let generation = playbackGeneration
        error = nil
        source = nil
        watchInfo = nil
        duration = 0
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

            let targetResume = resumeAt ?? currentResumeAt
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
                position = pos
                let dur = item.duration.seconds
                if dur.isFinite { duration = dur }
                isPlaying = av.timeControlStatus == .playing
                if let range = item.loadedTimeRanges.last?.timeRangeValue {
                    let end = (range.start + range.duration).seconds
                    if end.isFinite { buffered = end }
                }
                if pos - lastSaved >= 5 || lastSaved == 0 {
                    lastSaved = pos
                    savePosition(pos, duration: duration)
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
            position = targetResume >= 8 ? targetResume : 0
            lastSaved = 0
            buffered = 0
            await loadSubtitles(for: item)
            currentResumeAt = 0
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
        save(forceComplete: false)
        await startPlayback(preferredHoster: hoster, preferredLang: source?.lang ?? library.langPref, resumeAt: at)
    }

    @MainActor
    func switchLanguage(to lang: String) async {
        let at = currentPosition()
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
            await playNextEpisode()
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
                durationSec: dur.isFinite ? dur : duration,
                updatedAt: Date().timeIntervalSince1970 * 1000,
                lang: source?.lang ?? library.langPref,
                completed: dur >= 20 && pos >= dur * 0.9,
                provider: provider
            )
        )
    }

    func save(forceComplete: Bool) {
        guard player != nil || duration > 0 else { return }
        let pos = player?.currentTime().seconds ?? 0
        var dur = player?.currentItem?.duration.seconds ?? duration
        if !dur.isFinite { dur = duration }
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
        let pos = player?.currentTime().seconds ?? 0
        return pos.isFinite ? pos : 0
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
        player?.pause()
        player = nil
    }

    @MainActor
    func teardown(saveCurrent: Bool) {
        cancelAutoplay()
        clearPlayer(saveCurrent: saveCurrent)
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
