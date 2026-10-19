package de.nori

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.nori.player.NoriPlaybackService
import de.nori.player.NoriPlayerHolder
import de.nori.ui.NoriApp
import de.nori.ui.theme.NoriTheme

class MainActivity : ComponentActivity() {

    /**
     * Ob gerade im kleinen Fenster gespielt wird.
     *
     * Als Compose-Zustand und nicht als Abfrage: `isInPictureInPictureMode`
     * ändert sich, ohne dass Compose davon erfährt, und die Steuerung bliebe
     * im kleinen Fenster stehen.
     */
    private var inPictureInPicture by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            NoriTheme {
                NoriApp(
                    inPictureInPicture = inPictureInPicture,
                    onEnterPictureInPicture = ::enterPictureInPicture,
                    onPlaybackStarted = ::startPlaybackService,
                    onPlaybackFinished = ::stopPlaybackService,
                )
            }
        }
    }

    /**
     * Bild-in-Bild mit dem Seitenverhältnis des laufenden Videos.
     *
     * Ohne das nimmt Android 16:9 an, und ein 4:3-Video bekäme schwarze
     * Balken, die sich nicht mehr wegbekommen lassen.
     */
    private fun enterPictureInPicture() {
        val state = NoriPlayerHolder.peek()?.state?.value ?: return
        val width = state.videoWidth.takeIf { it > 0 } ?: 16
        val height = state.videoHeight.takeIf { it > 0 } ?: 9

        // Android weist Seitenverhältnisse außerhalb dieses Bereichs ab, und
        // zwar mit einer Ausnahme, nicht mit einem Rückfall.
        val ratio = (width.toFloat() / height).coerceIn(0.42f, 2.39f)
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational((ratio * 1000).toInt(), 1000))
            .build()

        runCatching { enterPictureInPictureMode(params) }
    }

    /**
     * Beim Verlassen der App während der Wiedergabe von selbst ins kleine
     * Fenster wechseln — das ist das Verhalten, das Nutzer von Videoapps
     * erwarten. Ab Android 12 übernimmt das System das selbst, sofern es
     * angemeldet ist; darunter braucht es diesen Aufruf.
     */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        val playing = NoriPlayerHolder.peek()?.state?.value?.isPlaying == true
        if (playing) enterPictureInPicture()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        inPictureInPicture = isInPictureInPictureMode
    }

    /**
     * Der Dienst trägt die Medienbedienung — Benachrichtigung,
     * Sperrbildschirm, Kopfhörertasten. Er wird erst gestartet, wenn
     * tatsächlich etwas läuft, damit im normalen Blättern keine
     * Wiedergabebenachrichtigung erscheint.
     */
    private fun startPlaybackService() {
        runCatching { startService(Intent(this, NoriPlaybackService::class.java)) }
    }

    private fun stopPlaybackService() {
        runCatching { stopService(Intent(this, NoriPlaybackService::class.java)) }
    }

    override fun onDestroy() {
        // Nur bei echtem Ende, nicht beim Drehen: sonst bricht die Wiedergabe
        // bei jeder Drehung ab.
        if (isFinishing) {
            stopPlaybackService()
            NoriPlayerHolder.release()
        }
        super.onDestroy()
    }
}
