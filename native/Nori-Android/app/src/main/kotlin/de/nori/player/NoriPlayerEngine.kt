package de.nori.player

import android.content.Context
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import de.nori.core.PlaySource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Was der Player gerade tut. Eine Wahrheit, aus der die Oberfläche zeichnet.
 */
data class NoriPlaybackState(
    val isPlaying: Boolean = false,
    val isBuffering: Boolean = true,
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val bufferedMs: Long = 0,
    val speed: Float = 1f,
    val ended: Boolean = false,
    val audioTracks: List<NoriTrack> = emptyList(),
    val textTracks: List<NoriTrack> = emptyList(),
    val videoTracks: List<NoriTrack> = emptyList(),
    val subtitlesEnabled: Boolean = false,
    val videoWidth: Int = 0,
    val videoHeight: Int = 0,
) {
    val hasDuration: Boolean get() = durationMs > 0
    val aspectRatio: Float
        get() = if (videoWidth > 0 && videoHeight > 0) videoWidth.toFloat() / videoHeight else 16f / 9f
}

/** Ein Wiedergabefehler, bereits eingeordnet. */
data class NoriPlaybackError(
    val message: String,
    /** Lohnt ein erneuter Versuch mit derselben Adresse? */
    val retryable: Boolean,
    /** Ist die Adresse selbst tot, sodass nur ein anderer Hoster hilft? */
    val sourceDead: Boolean,
)

/**
 * Die Hülle um ExoPlayer.
 *
 * Sie enthält bewusst **keine** Kenntnis von AniWorld, Serienstream oder
 * Hostern: sie bekommt eine bereits aufgelöste [PlaySource] und spielt sie.
 * Alles, was mit dem Finden einer Adresse zu tun hat, liegt im Swift-Kern.
 *
 * Der Player wird nicht pro Bildschirm erzeugt. Er lebt in
 * [NoriPlayerHolder], damit Drehen des Geräts, Bild-in-Bild und der Wechsel
 * in den Hintergrund die Wiedergabe nicht abreißen lassen — genau die Stellen,
 * an denen ein im ViewModel erzeugter Player scheitert.
 */
class NoriPlayerEngine(
    private val context: Context,
    private val scope: CoroutineScope,
) {
    private companion object {
        const val TAG = "NoriPlayer"

        /**
         * Puffergrenzen.
         *
         * Die Voreinstellung von Media3 ist auf Streams mit verlässlicher
         * Bandbreite ausgelegt. Hoster liefern in Schüben; ein größerer
         * Puffer überbrückt das, ohne den Start zu verzögern — der bleibt bei
         * 2,5 Sekunden.
         */
        const val MIN_BUFFER_MS = 30_000
        const val MAX_BUFFER_MS = 120_000
        const val BUFFER_FOR_PLAYBACK_MS = 2_500
        const val BUFFER_FOR_REBUFFER_MS = 5_000
    }

    private val trackSelector = DefaultTrackSelector(context).apply {
        parameters = buildUponParameters()
            // Untertitel bleiben aus, bis jemand sie einschaltet.
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            .build()
    }

    private val _state = MutableStateFlow(NoriPlaybackState())
    val state: StateFlow<NoriPlaybackState> = _state.asStateFlow()

    private val _error = MutableStateFlow<NoriPlaybackError?>(null)
    val error: StateFlow<NoriPlaybackError?> = _error.asStateFlow()

    private var ticker: Job? = null
    private var currentSource: PlaySource? = null

    val player: ExoPlayer = ExoPlayer.Builder(context)
        .setTrackSelector(trackSelector)
        .setLoadControl(
            DefaultLoadControl.Builder()
                .setBufferDurationsMs(
                    MIN_BUFFER_MS,
                    MAX_BUFFER_MS,
                    BUFFER_FOR_PLAYBACK_MS,
                    BUFFER_FOR_REBUFFER_MS,
                )
                .build()
        )
        // Der Player hält den Bildschirm wach und legt die Lautstärke auf den
        // Medienkanal. Ohne das dimmt das Gerät mitten im Film.
        .setWakeMode(C.WAKE_MODE_NETWORK)
        .setHandleAudioBecomingNoisy(true)
        .build()
        .also { it.addListener(Listener()) }

    // MARK: Steuerung

    /**
     * Eine Quelle abspielen.
     *
     * [startAtMs] ist die Stelle, an der begonnen wird — beim Fortsetzen die
     * gespeicherte Position, beim Hosterwechsel die aktuelle.
     */
    fun play(source: PlaySource, startAtMs: Long, autoPlay: Boolean = true) {
        Log.i(TAG, "Quelle: ${source.hoster} (${source.kind}) ab ${startAtMs}ms")
        currentSource = source
        _error.value = null
        _state.update { it.copy(isBuffering = true, ended = false) }

        val mediaSource = NoriMediaSourceFactory.create(context, source)
        player.setMediaSource(mediaSource, startAtMs.coerceAtLeast(0))
        player.prepare()
        player.playWhenReady = autoPlay
        startTicker()
    }

    /**
     * Denselben Punkt mit einer anderen Quelle weiterspielen.
     *
     * Das ist der Hosterwechsel. Die Position wird vor dem Austausch
     * abgegriffen und danach wiederhergestellt — die Folge bleibt dieselbe,
     * die Detailseite wird nicht neu geladen, der Fortschritt nicht
     * zurückgesetzt.
     */
    fun switchSource(source: PlaySource) {
        val keep = player.currentPosition.coerceAtLeast(0)
        val wasPlaying = player.playWhenReady
        play(source, keep, autoPlay = wasPlaying)
    }

    /** Nochmal versuchen, ohne die Stelle zu verlieren. */
    fun retry() {
        val source = currentSource ?: return
        play(source, player.currentPosition.coerceAtLeast(0), autoPlay = true)
    }

    fun togglePlayPause() {
        if (player.isPlaying) player.pause() else player.play()
    }

    fun seekTo(positionMs: Long) {
        player.seekTo(positionMs.coerceIn(0, player.duration.takeIf { it > 0 } ?: Long.MAX_VALUE))
        pushPosition()
    }

    fun seekBy(deltaMs: Long) = seekTo(player.currentPosition + deltaMs)

    fun setSpeed(speed: Float) {
        player.setPlaybackSpeed(speed)
        _state.update { it.copy(speed = speed) }
    }

    fun selectTrack(track: NoriTrack, type: NoriTrackType) {
        NoriTrackReader.select(player, player.currentTracks, track, type)
        readTracks(player.currentTracks)
    }

    fun clearTrackChoice(type: NoriTrackType) {
        NoriTrackReader.reset(player, type, disable = type == NoriTrackType.Text)
        readTracks(player.currentTracks)
    }

    /** Die aktuelle Position, für das Speichern des Fortschritts. */
    fun snapshotPosition(): Pair<Long, Long> =
        player.currentPosition.coerceAtLeast(0) to player.duration.coerceAtLeast(0)

    fun release() {
        ticker?.cancel()
        ticker = null
        player.release()
    }

    // MARK: Innenleben

    private fun startTicker() {
        ticker?.cancel()
        ticker = scope.launch(Dispatchers.Main) {
            while (true) {
                pushPosition()
                // 250 ms hält die Fortschrittsleiste flüssig, ohne dass die
                // Compose-Ebene bei jedem Frame neu zeichnet.
                delay(250)
            }
        }
    }

    private fun pushPosition() {
        _state.update {
            it.copy(
                positionMs = player.currentPosition.coerceAtLeast(0),
                durationMs = player.duration.takeIf { d -> d != C.TIME_UNSET && d > 0 } ?: 0,
                bufferedMs = player.bufferedPosition.coerceAtLeast(0),
            )
        }
    }

    private fun readTracks(tracks: Tracks) {
        val text = NoriTrackReader.read(tracks, NoriTrackType.Text)
        _state.update {
            it.copy(
                audioTracks = NoriTrackReader.read(tracks, NoriTrackType.Audio),
                textTracks = text,
                videoTracks = NoriTrackReader.read(tracks, NoriTrackType.Video),
                subtitlesEnabled = text.any { track -> track.selected },
            )
        }
    }

    private inner class Listener : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            _state.update { it.copy(isPlaying = isPlaying) }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            _state.update {
                it.copy(
                    isBuffering = playbackState == Player.STATE_BUFFERING,
                    ended = playbackState == Player.STATE_ENDED,
                )
            }
            if (playbackState == Player.STATE_READY) pushPosition()
        }

        override fun onTracksChanged(tracks: Tracks) = readTracks(tracks)

        override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) {
            _state.update { it.copy(videoWidth = videoSize.width, videoHeight = videoSize.height) }
        }

        override fun onPlayerError(error: PlaybackException) {
            Log.w(TAG, "Wiedergabefehler ${error.errorCodeName}", error)
            _error.value = classify(error)
        }
    }

    /**
     * Einordnen statt weiterreichen.
     *
     * Ein Stacktrace hilft dem Nutzer nicht, und „Wiedergabe fehlgeschlagen"
     * auch nicht. Entscheidend sind zwei Fragen: hilft ein zweiter Versuch,
     * oder hilft nur ein anderer Hoster? Danach richtet sich, was der Player
     * anbietet.
     */
    private fun classify(error: PlaybackException): NoriPlaybackError {
        val http = generateSequence(error.cause) { it.cause }
            .filterIsInstance<HttpDataSource.InvalidResponseCodeException>()
            .firstOrNull()

        if (http != null) {
            return when (http.responseCode) {
                // Genau der Fall, für den die Kopfzeilen aus PlaySource da
                // sind. Kommt er trotzdem, hat der Hoster nachgezogen.
                401, 403 -> NoriPlaybackError(
                    "Der Hoster weist den Abruf ab (${http.responseCode}). Ein anderer Hoster hilft meist.",
                    retryable = false,
                    sourceDead = true,
                )

                404, 410 -> NoriPlaybackError(
                    "Der Stream ist beim Hoster nicht mehr vorhanden.",
                    retryable = false,
                    sourceDead = true,
                )

                429 -> NoriPlaybackError(
                    "Der Hoster drosselt gerade. Kurz warten oder anderen Hoster wählen.",
                    retryable = true,
                    sourceDead = false,
                )

                in 500..599 -> NoriPlaybackError(
                    "Der Hoster hat einen Fehler gemeldet (${http.responseCode}).",
                    retryable = true,
                    sourceDead = false,
                )

                else -> NoriPlaybackError(
                    "Der Hoster antwortete mit ${http.responseCode}.",
                    retryable = true,
                    sourceDead = false,
                )
            }
        }

        return when (error.errorCode) {
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
            -> NoriPlaybackError("Die Verbindung ist abgebrochen.", retryable = true, sourceDead = false)

            PlaybackException.ERROR_CODE_IO_NO_PERMISSION,
            PlaybackException.ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED,
            -> NoriPlaybackError("Der Abruf wurde blockiert.", retryable = false, sourceDead = true)

            PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED,
            -> NoriPlaybackError(
                "Der Hoster liefert kein abspielbares Video (womöglich eine Fehlerseite).",
                retryable = false,
                sourceDead = true,
            )

            PlaybackException.ERROR_CODE_DECODING_FAILED,
            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            -> NoriPlaybackError(
                "Dieses Gerät kann das Videoformat nicht dekodieren.",
                retryable = false,
                sourceDead = true,
            )

            else -> NoriPlaybackError(
                "Die Wiedergabe ist fehlgeschlagen (${error.errorCodeName}).",
                retryable = true,
                sourceDead = false,
            )
        }
    }
}
