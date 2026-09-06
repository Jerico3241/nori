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

    init(series: SeriesDetail, episode: Episode, season: String, resumeAt: Double, provider: CatalogProvider) {
        self.series = series
        self.season = season
        self.provider = provider
        _currentEpisode = State(initialValue: episode)
        _currentResumeAt = State(initialValue: resumeAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            playerChrome
                .background(Color.black)
            ZStack {
                Color.black
                if let player {
                    PlayerLayer(player: player)
                } else if let error {
                    errorView(error)
                } else {
                    loadingView
                }
                if let seconds = autoplaySeconds,
                   let next = library.nextEpisode(after: currentEpisode, in: series.episodes) {
                    autoplayCard(seconds: seconds, next: next)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
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

    private var playerChrome: some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    save(forceComplete: false)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .padding(12)
                        .background(.black.opacity(0.45), in: Circle())
                }

                Spacer()

                VStack(spacing: 2) {
                    Text(series.title)
                        .font(.caption.weight(.semibold))
                    Text("Folge \(currentEpisode.number)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .foregroundStyle(.white.opacity(0.9))

                Spacer()

                playbackMenu
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
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

        } label: {
            HStack(spacing: 5) {
                if isSwitching { ProgressView().controlSize(.small) }
                Text(source.map { "Hoster: " + $0.hoster } ?? "Hoster & Sprache")
                    .font(.caption2)
                Image(systemName: "ellipsis.circle")
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(.black.opacity(0.4), in: Capsule())
        }
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

            let play = try await HosterResolver.resolveBest(
                hosters: info.hosters,
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

            observer = av.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 5, preferredTimescale: 1),
                queue: .main
            ) { time in
                guard generation == playbackGeneration else { return }
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
                    guard generation == playbackGeneration else { return }
                    save(forceComplete: true)
                    handleEpisodeEnded()
                }
            }

            player = av
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

struct PlayerLayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.updatesNowPlayingInfoCenter = true
        return controller
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}

