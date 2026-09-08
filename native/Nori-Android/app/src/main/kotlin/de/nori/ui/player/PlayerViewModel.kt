package de.nori.ui.player

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.nori.core.CatalogProvider
import de.nori.core.Episode
import de.nori.core.HosterOption
import de.nori.core.NoriCore
import de.nori.core.PlaySource
import de.nori.core.WatchProgress
import de.nori.core.userMessage
import de.nori.data.Nori
import de.nori.player.NoriPlayerEngine
import de.nori.player.NoriPlayerHolder
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Was der Player-Bildschirm zeigt. */
sealed interface PlayerUiState {
    /** Die Adresse wird noch gesucht — das ist die Rundreise über den Kern. */
    data class Loading(val note: String) : PlayerUiState

    data class Ready(
        val source: PlaySource,
        /** Alle Hoster dieser Folge, in der Reihenfolge des Kerns. */
        val hosters: List<HosterOption>,
        /** Verfügbare Sprachen, entdoppelt. */
        val languages: List<String>,
        val episode: Episode,
        val seriesTitle: String,
        val season: String,
        val hasNext: Boolean,
    ) : PlayerUiState

    data class Error(val message: String, val hosters: List<HosterOption>) : PlayerUiState
}

/**
 * Der Ablauf einer Wiedergabe, von der Folge bis zum Bild.
 *
 * Die Kette ist genau die, die diese Portierung tragfähig macht:
 *
 *     Episode → NoriCore.watch → Hoster
 *             → NoriCore.resolveBest → PlaySource (URL + Kopfzeilen)
 *             → Media3
 *
 * Nichts davon wird hier nachgebaut. Dieses ViewModel kennt weder AniWorld
 * noch VOE; es kennt Folgen und eine Quelle, die es abspielen kann.
 */
class PlayerViewModel(
    context: Context,
    private val slug: String,
    private val seriesTitle: String,
    private val provider: CatalogProvider,
    private val season: String,
    private val episodes: List<Episode>,
) : ViewModel() {

    val engine: NoriPlayerEngine = NoriPlayerHolder.acquire(context)

    private val _state = MutableStateFlow<PlayerUiState>(PlayerUiState.Loading("Folge wird geöffnet"))
    val state: StateFlow<PlayerUiState> = _state.asStateFlow()

    /** Läuft der Countdown zur nächsten Folge? Sekunden, oder `null`. */
    private val _countdown = MutableStateFlow<Int?>(null)
    val countdown: StateFlow<Int?> = _countdown.asStateFlow()

    val snapshot = Nori.library.snapshot
    val playback = engine.state
    val error = engine.error

    private var current: Episode? = null
    private var resolveJob: Job? = null
    private var saveJob: Job? = null
    private var countdownJob: Job? = null

    /** Zuletzt gespeicherte Position — verhindert Schreiben ohne Änderung. */
    private var lastSavedSec = -1.0

    init {
        // Der Player behält die Geschwindigkeit aus den Einstellungen.
        engine.setSpeed(snapshot.value.playbackSpeed.toFloat())
        startAutosave()
        observeEnd()
    }

    // MARK: Folgen

    fun open(episode: Episode, resumeAtSec: Double) {
        current = episode
        resolveJob?.cancel()
        countdownJob?.cancel()
        _countdown.value = null
        lastSavedSec = -1.0

        resolveJob = viewModelScope.launch {
            _state.value = PlayerUiState.Loading("Hoster werden gesucht")

            val watch = try {
                NoriCore.watch(provider, episode.path)
            } catch (error: Throwable) {
                _state.value = PlayerUiState.Error(error.userMessage(), emptyList())
                return@launch
            }

            val prefs = snapshot.value
            val ordered = runCatching {
                NoriCore.hosterOrder(watch.hosters, prefs.hosterPref, prefs.langPref)
            }.getOrDefault(watch.hosters)

            _state.value = PlayerUiState.Loading("Stream wird aufgelöst")

            val source = try {
                NoriCore.resolveBest(
                    hosters = watch.hosters,
                    preferredHoster = prefs.hosterPref,
                    preferredLang = prefs.langPref,
                    episodePath = episode.path,
                    provider = provider,
                )
            } catch (error: Throwable) {
                _state.value = PlayerUiState.Error(error.userMessage(), ordered)
                return@launch
            }

            _state.value = PlayerUiState.Ready(
                source = source,
                hosters = ordered,
                languages = ordered.map { it.lang }.distinct(),
                episode = episode,
                seriesTitle = seriesTitle,
                season = season,
                hasNext = nextEpisode(episode) != null,
            )
            engine.play(source, (resumeAtSec * 1000).toLong())
        }
    }

    fun playNext() {
        val next = current?.let { nextEpisode(it) } ?: return
        countdownJob?.cancel()
        _countdown.value = null
        saveProgress(force = true)
        open(next, 0.0)
    }

    fun cancelCountdown() {
        countdownJob?.cancel()
        _countdown.value = null
    }

    private fun nextEpisode(after: Episode): Episode? {
        val sorted = episodes.sortedBy { it.number }
        val index = sorted.indexOfFirst { it.number == after.number }
        return if (index >= 0 && index + 1 < sorted.size) sorted[index + 1] else null
    }

    // MARK: Hoster und Sprache

    /**
     * Hosterwechsel während der Wiedergabe.
     *
     * Die Stelle bleibt erhalten: `switchSource` merkt sich die Position,
     * tauscht die MediaSource und setzt sie danach zurück. Die Folge wird
     * nicht neu geöffnet und der Fortschritt nicht angefasst.
     */
    fun switchHoster(option: HosterOption) {
        val episode = current ?: return
        resolveJob?.cancel()
        resolveJob = viewModelScope.launch {
            val previous = _state.value
            try {
                val source = NoriCore.resolveOne(option, episode.path, provider)
                _state.update { if (it is PlayerUiState.Ready) it.copy(source = source) else it }
                engine.switchSource(source)
                Nori.library.setHoster(option.name)
            } catch (error: Throwable) {
                // Der Wechsel ist gescheitert — die laufende Wiedergabe soll
                // deswegen nicht abbrechen. Der bisherige Zustand bleibt.
                _state.value = previous
                _messages.emitMessage("${option.name}: ${error.userMessage()}")
            }
        }
    }

    /** Sprachwechsel: derselbe Weg wie beim Start, nur mit anderer Vorgabe. */
    fun switchLanguage(lang: String) {
        val episode = current ?: return
        val ready = _state.value as? PlayerUiState.Ready ?: return
        resolveJob?.cancel()
        resolveJob = viewModelScope.launch {
            Nori.library.setLanguage(lang)
            try {
                val source = NoriCore.resolveBest(
                    hosters = ready.hosters,
                    preferredHoster = snapshot.value.hosterPref,
                    preferredLang = lang,
                    episodePath = episode.path,
                    provider = provider,
                )
                _state.update { if (it is PlayerUiState.Ready) it.copy(source = source) else it }
                engine.switchSource(source)
            } catch (error: Throwable) {
                _messages.emitMessage(error.userMessage())
            }
        }
    }

    fun retry() {
        val episode = current ?: return
        val (position, _) = engine.snapshotPosition()
        if (_state.value is PlayerUiState.Ready) engine.retry() else open(episode, position / 1000.0)
    }

    fun setSpeed(speed: Float) {
        engine.setSpeed(speed)
        viewModelScope.launch { Nori.library.setSpeed(speed) }
    }

    // MARK: Fortschritt

    /**
     * Regelmäßig speichern, aber nicht bei jedem Bild.
     *
     * Alle fünf Sekunden, und nur wenn sich die Stelle wirklich verschoben
     * hat. Dazu bei Pause, beim Verlassen und beim Folgenwechsel. Ein Absturz
     * kostet damit höchstens fünf Sekunden.
     */
    private fun startAutosave() {
        saveJob = viewModelScope.launch {
            while (true) {
                delay(5_000)
                if (playback.value.isPlaying) saveProgress(force = false)
            }
        }
    }

    fun saveProgress(force: Boolean) {
        val episode = current ?: return
        val (positionMs, durationMs) = engine.snapshotPosition()
        val position = positionMs / 1000.0
        val duration = durationMs / 1000.0

        // Ohne bekannte Dauer wäre jede Abschlussregel geraten.
        if (duration <= 0) return
        if (!force && kotlin.math.abs(position - lastSavedSec) < 1.0) return
        lastSavedSec = position

        val ready = _state.value as? PlayerUiState.Ready
        val item = WatchProgress(
            slug = slug,
            title = seriesTitle,
            season = season,
            episode = episode.number,
            episodePath = episode.path,
            germanTitle = episode.germanTitle,
            englishTitle = episode.englishTitle,
            positionSec = position,
            durationSec = duration,
            updatedAt = System.currentTimeMillis().toDouble(),
            lang = ready?.source?.lang,
            provider = provider,
        )
        viewModelScope.launch { runCatching { Nori.library.saveProgress(item) } }
    }

    // MARK: Autoplay

    private fun observeEnd() {
        viewModelScope.launch {
            playback.collect { state ->
                if (!state.ended) return@collect
                saveProgress(force = true)
                if (!snapshot.value.autoplayNext) return@collect
                if (current?.let { nextEpisode(it) } == null) return@collect
                if (countdownJob?.isActive == true) return@collect

                countdownJob = launch {
                    // Acht Sekunden wie im Contract — lang genug, um
                    // abzubrechen, kurz genug, um nicht zu warten.
                    for (second in 8 downTo 1) {
                        _countdown.value = second
                        delay(1_000)
                    }
                    _countdown.value = null
                    playNext()
                }
            }
        }
    }

    // MARK: Meldungen

    private val _messages = MutableStateFlow<String?>(null)
    val messages: StateFlow<String?> = _messages.asStateFlow()

    fun clearMessage() {
        _messages.value = null
    }

    private fun MutableStateFlow<String?>.emitMessage(text: String) {
        value = text
    }

    override fun onCleared() {
        saveProgress(force = true)
        saveJob?.cancel()
        countdownJob?.cancel()
        resolveJob?.cancel()
        super.onCleared()
    }
}
