import SwiftUI

/// Die Bedienung als Ganzes: obere Leiste, Mitteltasten, untere Leiste.
///
/// Sie bleibt **immer** aufgebaut und wird nur ein- und ausgeblendet. Früher
/// stand hier `if optionsVisible { controls }`: bei jedem Antippen wurde die
/// ganze Bedienung verworfen und neu gebaut, wodurch jeder lokale Zustand
/// verlorenging — ein Regler mitten im Ziehen, ein gerade geöffnetes Menü.
/// Ausgeblendet nimmt sie über `allowsHitTesting` keine Berührungen an; die
/// gehen an die Sprungfläche darunter.
///
/// Die drei Teile kommen als ein System: von oben herein, von unten herein,
/// die Mitte wächst leicht auf. Ein bloßes `opacity 0 → 1` für alles zugleich
/// liest sich flach.
struct PlayerControls: View {
    let visible: Bool

    let seriesTitle: String
    let episodeSubtitle: String
    let episodeNumber: String?
    let episodeTitle: String

    let isPlaying: Bool
    let position: Double
    let duration: Double
    let buffered: Double
    let speed: Float

    let hosters: [PlayerChoice]
    let activeHoster: String?
    let qualities: [PlayerChoice]
    let activeQuality: String?
    let languages: [PlayerChoice]
    let activeLanguage: String?
    let subtitles: [PlayerChoice]
    let activeSubtitle: String?
    let hasNextEpisode: Bool
    let isFilled: Bool
    let isSwitching: Bool

    let pip: PictureInPicture

    var onClose: () -> Void
    var onPlayPause: () -> Void
    var onSkip: (Double) -> Void
    var onScrub: (Double) -> Void
    var onSeek: (Double) -> Void
    var onScrubbing: (Bool) -> Void
    var onSpeed: (Float) -> Void
    var onHoster: (String) -> Void
    var onQuality: (String) -> Void
    var onLanguage: (String) -> Void
    var onSubtitle: (String) -> Void
    var onNextEpisode: () -> Void
    var onToggleFill: () -> Void
    var onMenuOpen: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var pad: Bool { sizeClass == .regular }

    var body: some View {
        ZStack {
            scrim
                .opacity(visible ? 1 : 0)

            VStack(spacing: 0) {
                PlayerTopBar(
                    title: seriesTitle,
                    subtitle: episodeSubtitle,
                    pip: pip,
                    onClose: onClose
                )
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : -14)

                Spacer(minLength: 0)

                PlayerBottomBar(
                    episodeNumber: episodeNumber,
                    episodeTitle: episodeTitle,
                    position: position,
                    duration: duration,
                    buffered: buffered,
                    speed: speed,
                    hosters: hosters,
                    activeHoster: activeHoster,
                    qualities: qualities,
                    activeQuality: activeQuality,
                    languages: languages,
                    activeLanguage: activeLanguage,
                    subtitles: subtitles,
                    activeSubtitle: activeSubtitle,
                    hasNextEpisode: hasNextEpisode,
                    isFilled: isFilled,
                    onScrub: onScrub,
                    onSeek: onSeek,
                    onScrubbing: onScrubbing,
                    onSpeed: onSpeed,
                    onHoster: onHoster,
                    onQuality: onQuality,
                    onLanguage: onLanguage,
                    onSubtitle: onSubtitle,
                    onNextEpisode: onNextEpisode,
                    onToggleFill: onToggleFill,
                    onMenuOpen: onMenuOpen
                )
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 14)
            }
            .padding(.horizontal, pad ? 28 : 18)
            .padding(.vertical, pad ? 16 : 10)

            center
                .opacity(visible ? 1 : 0)
                .scaleEffect(visible ? 1 : 0.94)
        }
        .allowsHitTesting(visible)
    }

    /// Beim Hosterwechsel tritt an die Stelle der Mitteltasten ein Ring.
    /// Die Leisten bleiben stehen: der Player schließt nicht, die Auswahl
    /// bleibt sichtbar, nur das Bild ist kurz nicht da.
    @ViewBuilder
    private var center: some View {
        if isSwitching {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .transition(.opacity)
        } else {
            PlayerCenterControls(
                isPlaying: isPlaying,
                onSkip: onSkip,
                onPlayPause: onPlayPause
            )
            .transition(.opacity)
        }
    }

    /// Zwei Verläufe statt einer Fläche: das Bild bleibt in der Mitte frei,
    /// die Schrift steht oben und unten trotzdem auf Grund.
    ///
    /// `ignoresSafeArea` ist hier kein Schönheitsfehler, sondern der Punkt:
    /// ohne das endete der untere Verlauf an der sicheren Fläche und ließ
    /// unter der Leiste einen hellen Streifen stehen — genau dort, wo der
    /// Home-Indikator liegt. Der Verlauf gehört bis an die Gerätekante, die
    /// Bedienung selbst nicht.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.72), location: 0),
                .init(color: .black.opacity(0.12), location: 0.28),
                .init(color: .clear, location: 0.45),
                .init(color: .black.opacity(0.2), location: 0.66),
                .init(color: .black.opacity(0.82), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
