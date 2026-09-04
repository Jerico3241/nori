import AVKit
import SwiftUI

/// Der Player läuft auf dem Mac in einem eigenen Fenster. Die Bedienelemente
/// von AVKit bleiben unangetastet – Hoster, Sprache und Tempo sitzen in der
/// Fenster-Symbolleiste statt in einem Overlay über den Systemreglern.
struct PlayerScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    let series: SeriesDetail
    let season: String

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
    @State private var isSwitching = false
    @State private var sleepActivity: NSObjectProtocol?

    init(request: PlayerRequest) {
        self.series = request.series
        self.season = request.season
        _currentEpisode = State(initialValue: request.episode)
        _currentResumeAt = State(initialValue: request.resumeAt)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if let error {
                errorView(error)
            } else {
                loadingView
            }

            if let seconds = autoplaySeconds,
               let next = library.nextEpisode(after: currentEpisode, in: series.episodes)
            {
                autoplayCard(seconds: seconds, next: next)
            }
        }
        .navigationTitle(series.title)
        .navigationSubtitle(episodeSubtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    Task { await playPreviousEpisode() }
                } label: {
                    Label("Vorherige Folge", systemImage: "backward.end")
                }
                .help("Vorherige Folge")
                .disabled(previousEpisode == nil)
            }
            ToolbarItem(placement: .principal) {
                Button {
                    Task { await playNextEpisode() }
                } label: {
                    Label("Nächste Folge", systemImage: "forward.end")
                }
                .help("Nächste Folge")
                .disabled(library.nextEpisode(after: currentEpisode, in: series.episodes) == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                playbackMenu
            }
        }
        .task { await startPlayback(resumeAt: currentResumeAt) }
        .onDisappear { teardown(saveCurrent: true) }
    }

    private var episodeSubtitle: String {
        let name = currentEpisode.germanTitle.isEmpty ? "" : " · \(currentEpisode.germanTitle)"
        return "Staffel \(season) · Folge \(currentEpisode.number)\(name)"
    }

    private var previousEpisode: Episode? {
        let sorted = series.episodes.sorted { $0.number < $1.number }
        guard let index = sorted.firstIndex(where: { $0.number == currentEpisode.number }), index > 0 else { return nil }
        return sorted[index - 1]
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
                .textSelection(.enabled)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("Erneut versuchen") { Task { await retry() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button("Anderen Hoster") { Task { await tryAlternativeHoster() } }
                    .buttonStyle(.bordered)
                Button("Fenster schließen") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
    }

    private var playbackMenu: some View {
        Menu {
            if let info = watchInfo {
                let hosters = Array(Set(info.hosters.map(\.name))).sorted { HosterResolver.rank($0) < HosterResolver.rank($1) }
                if !hosters.isEmpty {
                    Section("Hoster") {
                        ForEach(hosters, id: \.self) { hoster in
                            Button {
                                Task { await switchHoster(to: hoster) }
                            } label: {
                                if source?.hoster.caseInsensitiveCompare(hoster) == .orderedSame {
                                    Label(hoster, systemImage: "checkmark")
                                } else {
                                    Text(hoster)
                                }
                            }
                        }
                    }
                }

                let languages = Array(Set(info.hosters.map(\.lang))).sorted()
                if !languages.isEmpty {
                    Section("Sprache") {
                        ForEach(languages, id: \.self) { lang in
                            Button {
                                Task { await switchLanguage(to: lang) }
                            } label: {
                                if source?.lang.caseInsensitiveCompare(lang) == .orderedSame {
                                    Label(languageLabel(lang), systemImage: "checkmark")
                                } else {
                                    Text(languageLabel(lang))
                                }
                            }
                        }
                    }
                }
            }

            Section("Geschwindigkeit") {
                ForEach([Float(0.75), 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Button {
                        Task { @MainActor in setPlaybackSpeed(speed) }
                    } label: {
                        if abs(library.playbackSpeed - speed) < 0.01 {
                            Label(speedLabel(speed), systemImage: "checkmark")
                        } else {
                            Text(speedLabel(speed))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if isSwitching { ProgressView().controlSize(.small) }
                Text(source?.hoster ?? "Optionen")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Hoster, Sprache und Wiedergabegeschwindigkeit")
    }

    private func autoplayCard(seconds: Int, next: Episode) -> some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nächste Folge")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                    Text("Folge \(next.number) startet in \(seconds) s")
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack(spacing: 10) {
                        Button("Abbrechen") { Task { @MainActor in cancelAutoplay() } }
                            .buttonStyle(.bordered)
                        Button("Jetzt abspielen") {
                            autoplayTask?.cancel()
                            autoplaySeconds = nil
                            Task { await playNextEpisode() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
                .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(20)
            }
            Spacer()
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
        error = nil
        source = nil
        watchInfo = nil
        duration = 0
        isSwitching = true

        do {
            status = "Folge wird gelesen…"
            let path = currentEpisode.path.isEmpty
                ? guessEpisodePath(slug: series.slug, season: season, episode: currentEpisode.number, provider: library.provider)
                : currentEpisode.path
            currentPath = normalizeEpisodePath(path)

            let info = try await AniworldClient.shared.getWatch(provider: library.provider, path: path)
            watchInfo = info
            status = "Stream wird geholt…"

            let play = try await HosterResolver.resolveBest(
                hosters: info.hosters,
                preferredHoster: preferredHoster ?? library.hosterPref,
                preferredLang: preferredLang ?? library.langPref
            )
            source = play
            library.hosterPref = play.hoster
            library.langPref = play.lang

            guard let url = URL(string: play.url) else {
                throw NoriError.hoster("Ungültige Stream-URL")
            }

            let item = AVPlayerItem(url: url)
            let av = AVPlayer(playerItem: item)
            av.actionAtItemEnd = .pause
            av.defaultRate = library.playbackSpeed

            let targetResume = resumeAt ?? currentResumeAt
            if targetResume >= 8 {
                let t = CMTime(seconds: targetResume, preferredTimescale: 600)
                await av.seek(to: t)
            }

            av.playImmediately(atRate: library.playbackSpeed)

            observer = av.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 5, preferredTimescale: 1),
                queue: .main
            ) { time in
                let pos = time.seconds
                let dur = item.duration.seconds
                if dur.isFinite { duration = dur }
                if pos.isFinite { savePosition(pos, duration: duration) }
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    save(forceComplete: true)
                    handleEpisodeEnded()
                }
            }

            player = av
            currentResumeAt = 0
            beginSleepBlock()
        } catch {
            self.error = error.localizedDescription
        }
        isSwitching = false
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
            HosterResolver.pickLang(info.hosters, pref: source?.lang ?? library.langPref),
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
        library.hosterPref = hoster
        await startPlayback(preferredHoster: hoster, preferredLang: source?.lang ?? library.langPref, resumeAt: at)
    }

    @MainActor
    func switchLanguage(to lang: String) async {
        let at = currentPosition()
        save(forceComplete: false)
        library.langPref = lang
        await startPlayback(preferredHoster: source?.hoster ?? library.hosterPref, preferredLang: lang, resumeAt: at)
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
        await switchEpisode(to: next)
    }

    @MainActor
    func playPreviousEpisode() async {
        guard let previous = previousEpisode else { return }
        await switchEpisode(to: previous)
    }

    @MainActor
    private func switchEpisode(to next: Episode) async {
        autoplayTask?.cancel()
        autoplaySeconds = nil
        clearPlayer(saveCurrent: true)
        currentEpisode = next
        currentResumeAt = library.resumeEnabled
            ? resumePosition(library.progress(slug: series.slug, season: season, episode: next.number, path: next.path, provider: library.provider))
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
                provider: library.provider
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
                provider: library.provider
            )
        )
    }

    func currentPosition() -> Double {
        let pos = player?.currentTime().seconds ?? 0
        return pos.isFinite ? pos : 0
    }

    /// Verhindert, dass der Bildschirm während der Wiedergabe schlafen geht.
    @MainActor
    private func beginSleepBlock() {
        guard sleepActivity == nil else { return }
        sleepActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
            reason: "Nori Wiedergabe"
        )
    }

    @MainActor
    private func endSleepBlock() {
        if let sleepActivity { ProcessInfo.processInfo.endActivity(sleepActivity) }
        sleepActivity = nil
    }

    @MainActor
    func clearPlayer(saveCurrent: Bool) {
        if saveCurrent { save(forceComplete: false) }
        if let observer, let player { player.removeTimeObserver(observer) }
        observer = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        endSleepBlock()
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
