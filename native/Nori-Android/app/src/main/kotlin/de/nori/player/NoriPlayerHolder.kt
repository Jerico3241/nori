package de.nori.player

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * Wem der Player gehört.
 *
 * Nicht dem ViewModel und nicht der Activity. Beide sterben an Stellen, an
 * denen die Wiedergabe weiterlaufen soll: beim Drehen des Geräts, beim
 * Wechsel in Bild-in-Bild, beim Zurückkommen aus dem Hintergrund. Ein Player
 * im ViewModel überlebt zwar die Drehung, aber nicht den Prozesswechsel in
 * die MediaSession — und ein Player in der Activity überlebt gar nichts.
 *
 * Deshalb genau eine Instanz, an den Anwendungskontext gebunden. Erzeugt
 * wird sie beim ersten Bedarf, freigegeben, wenn der Player-Bildschirm
 * endgültig verlassen wird.
 */
object NoriPlayerHolder {

    private var engine: NoriPlayerEngine? = null
    private var scope: CoroutineScope? = null

    /** Die laufende Instanz, oder eine neue. */
    @Synchronized
    fun acquire(context: Context): NoriPlayerEngine {
        engine?.let { return it }
        val newScope = CoroutineScope(SupervisorJob())
        val created = NoriPlayerEngine(context.applicationContext, newScope)
        scope = newScope
        engine = created
        return created
    }

    /** Die laufende Instanz, ohne eine zu erzeugen. Für die MediaSession. */
    @Synchronized
    fun peek(): NoriPlayerEngine? = engine

    @Synchronized
    fun release() {
        engine?.release()
        engine = null
        scope?.cancel()
        scope = null
    }
}
