package de.nori.player

import android.app.PendingIntent
import android.content.Intent
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import de.nori.MainActivity

/**
 * Die Android-Medienbedienung: Sperrbildschirm, Benachrichtigung, Kopfhörer,
 * Bluetooth-Tasten.
 *
 * Der Dienst erzeugt **keinen** eigenen Player. Er hängt eine MediaSession an
 * genau die Instanz, die der Player-Bildschirm benutzt — sonst liefen zwei
 * Wiedergaben nebeneinander, von denen die Benachrichtigung die falsche
 * steuert.
 *
 * Media3 baut Benachrichtigung und Bedienelemente daraus selbst; Play, Pause,
 * Vor- und Zurückspulen kommen ohne weiteres Zutun.
 */
class NoriPlaybackService : MediaSessionService() {

    private var session: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val engine = NoriPlayerHolder.acquire(this)
        session = MediaSession.Builder(this, engine.player)
            .setId("nori")
            // Ein Tipp auf die Benachrichtigung führt zurück in die App und
            // nicht auf eine leere Startseite.
            .setSessionActivity(
                PendingIntent.getActivity(
                    this,
                    0,
                    Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            )
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    /**
     * Wischt der Nutzer die App aus den letzten Programmen, während nichts
     * läuft, soll auch die Benachrichtigung weg sein. Läuft etwas, bleibt sie
     * — das ist der Sinn einer Hintergrundwiedergabe.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = session?.player
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        session?.run {
            release()
            session = null
        }
        super.onDestroy()
    }
}
