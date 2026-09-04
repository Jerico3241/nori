import AVKit
import SwiftUI

struct PlayerScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let series: SeriesDetail
    let episode: Episode
    let season: String
    let resumeAt: Double

    @State private var player: AVPlayer?
    @State private var status = "Hoster wird gelöst…"
    @State private var error: String?
    @State private var observer: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var duration: Double = 0
    @State private var source: PlaySource?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                PlayerLayer(player: player)
                    .ignoresSafeArea()
            } else if let error {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(.white).multilineTextAlignment(.center)
                    Button("Schließen") { dismiss() }
                }
                .padding()
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(status).foregroundStyle(.white.opacity(0.8)).font(.subheadline)
                }
            }
            VStack {
                HStack {
                    Button {
                        save(forceComplete: false)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .padding(12)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    Spacer()
                    Text("\(series.title) · F\(episode.number)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    if let source {
                        Text(source.hoster)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding()
                Spacer()
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task { await start() }
        .onDisappear { teardown() }
    }

    func start() async {
        do {
            status = "Folge wird gelesen…"
            let path = episode.path.isEmpty ? guessEpisodePath(slug: series.slug, season: season, episode: episode.number, provider: library.provider) : episode.path
            let info = try await AniworldClient.shared.getWatch(provider: library.provider, path: path)
            status = "Stream wird geholt…"
            let play = try await HosterResolver.resolveBest(
                hosters: info.hosters,
                preferredHoster: library.hosterPref,
                preferredLang: library.langPref
            )
            source = play
            guard let url = URL(string: play.url) else { throw NoriError.hoster("Ungültige Stream-URL") }
            let item = AVPlayerItem(url: url)
            let av = AVPlayer(playerItem: item)
            av.actionAtItemEnd = .pause
            if resumeAt >= 8 {
                let t = CMTime(seconds: resumeAt, preferredTimescale: 600)
                await av.seek(to: t)
            }
            av.play()
            observer = av.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { time in
                let pos = time.seconds
                let dur = item.duration.seconds
                if dur.isFinite { duration = dur }
                if pos.isFinite { savePosition(pos, duration: duration) }
            }
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                save(forceComplete: true)
            }
            player = av
        } catch {
            self.error = error.localizedDescription
        }
    }

    func savePosition(_ pos: Double, duration dur: Double) {
        guard pos >= 2 else { return }
        library.upsert(
            WatchProgress(
                slug: series.slug,
                title: series.title,
                season: season,
                episode: episode.number,
                episodePath: episode.path,
                germanTitle: episode.germanTitle,
                englishTitle: episode.englishTitle,
                positionSec: pos,
                durationSec: dur.isFinite ? dur : duration,
                updatedAt: Date().timeIntervalSince1970 * 1000,
                lang: library.langPref,
                completed: dur >= 20 && pos >= dur * 0.9
            )
        )
    }

    func save(forceComplete: Bool) {
        let pos = player?.currentTime().seconds ?? 0
        var dur = player?.currentItem?.duration.seconds ?? duration
        if !dur.isFinite { dur = duration }
        library.upsert(
            WatchProgress(
                slug: series.slug,
                title: series.title,
                season: season,
                episode: episode.number,
                episodePath: episode.path,
                germanTitle: episode.germanTitle,
                englishTitle: episode.englishTitle,
                positionSec: forceComplete ? max(pos, dur) : pos,
                durationSec: dur,
                updatedAt: Date().timeIntervalSince1970 * 1000,
                lang: library.langPref,
                completed: forceComplete || (dur >= 20 && pos >= dur * 0.9)
            )
        )
    }

    func teardown() {
        save(forceComplete: false)
        if let observer, let player { player.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player?.pause()
        player = nil
    }
}

struct PlayerLayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let c = AVPlayerViewController()
        c.player = player
        c.allowsPictureInPicturePlayback = true
        c.updatesNowPlayingInfoCenter = true
        return c
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
