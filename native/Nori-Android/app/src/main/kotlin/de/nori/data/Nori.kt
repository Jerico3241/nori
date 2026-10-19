package de.nori.data

import android.content.Context
import de.nori.core.NoriCore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Zustand des Kerns beim Start.
 *
 * Der Ladefehler der nativen Bibliothek ist der einzige, bei dem gar nichts
 * geht. Er wird deshalb bis in die Oberfläche getragen, statt die App im
 * Application-Konstruktor sterben zu lassen: ein Absturz beim Start sagt dem
 * Nutzer nichts, eine Meldung schon.
 */
sealed interface CoreState {
    data object Starting : CoreState
    data class Ready(val schemaVersion: Int, val hasTMDBKey: Boolean) : CoreState
    data class Failed(val message: String) : CoreState
}

/**
 * Die Abhängigkeiten der App, an einem Ort.
 *
 * Bewusst kein Dependency-Injection-Rahmenwerk: es gibt vier Objekte, alle
 * ohne Konfiguration, alle so langlebig wie der Prozess.
 */
object Nori {

    lateinit var library: LibraryRepository
        private set

    lateinit var catalog: CatalogRepository
        private set

    lateinit var covers: CoverRepository
        private set

    private val _core = MutableStateFlow<CoreState>(CoreState.Starting)
    val core: StateFlow<CoreState> = _core.asStateFlow()

    private var built = false

    @Synchronized
    fun build() {
        if (built) return
        library = LibraryRepository()
        catalog = CatalogRepository()
        covers = CoverRepository()
        built = true
    }

    /**
     * Den Kern hochfahren.
     *
     * `filesDir` ist der Ort, an dem `library.json`, `covers.json` und
     * `episodes.json` liegen — dieselben Dateien wie auf Apple, dasselbe
     * Format, dieselbe Migration.
     */
    suspend fun start(context: Context) {
        build()
        try {
            val setup = NoriCore.setUp(context.filesDir.absolutePath)
            library.refresh()
            _core.value = CoreState.Ready(setup.schemaVersion, setup.hasTMDBKey)
        } catch (error: Throwable) {
            _core.value = CoreState.Failed(
                error.message ?: "Der native Kern konnte nicht gestartet werden."
            )
        }
    }
}
