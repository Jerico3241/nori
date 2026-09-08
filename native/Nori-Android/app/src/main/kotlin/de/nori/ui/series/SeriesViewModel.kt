package de.nori.ui.series

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.nori.core.CatalogProvider
import de.nori.core.CoverDetails
import de.nori.core.Episode
import de.nori.core.EpisodeInfo
import de.nori.core.NextPlay
import de.nori.core.NoriCore
import de.nori.core.SeasonStats
import de.nori.core.SeriesDetail
import de.nori.core.userMessage
import de.nori.data.Nori
import de.nori.ui.PlaybackRequest
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface SeriesUiState {
    data object Loading : SeriesUiState
    data class Error(val message: String) : SeriesUiState
    data class Ready(
        val detail: SeriesDetail,
        val provider: CatalogProvider,
        val cover: CoverDetails?,
        val episodeInfo: Map<Int, EpisodeInfo>,
        val stats: SeasonStats?,
        val next: NextPlay?,
    ) : SeriesUiState
}

/**
 * Eine Serie mit ihren Staffeln und Folgen.
 *
 * Der Staffelwechsel lädt bewusst nur die Folgenliste neu: Beschreibung,
 * Cover und Genres stehen schon da und ändern sich nicht.
 */
class SeriesViewModel(
    private val slug: String,
    private val titleHint: String,
    private val provider: CatalogProvider,
) : ViewModel() {

    private val _state = MutableStateFlow<SeriesUiState>(SeriesUiState.Loading)
    val state: StateFlow<SeriesUiState> = _state.asStateFlow()

    val snapshot = Nori.library.snapshot

    private var loadJob: Job? = null
    private var currentSeason: String? = null

    init {
        load(null)
        // Der Verlauf hält fest, was geöffnet wurde — nicht erst, was
        // abgespielt wurde. Genau wie auf Apple.
        viewModelScope.launch {
            runCatching { Nori.library.remember(slug, titleHint, provider) }
        }
    }

    fun selectSeason(season: String) {
        if (season == currentSeason) return
        load(season)
    }

    fun reload() = load(currentSeason)

    private val _play = MutableStateFlow<PlaybackRequest?>(null)
    val play: StateFlow<PlaybackRequest?> = _play.asStateFlow()

    /**
     * Eine Folge starten.
     *
     * Die Stelle bestimmt **der Kern**, nicht diese Datei: „unter acht
     * Sekunden fängt von vorn an" und „eine fast fertige Folge gilt als
     * gesehen" sind Regeln, keine Anzeigedetails. In Kotlin nachgerechnet
     * liefen sie früher oder später von `LibraryStore` weg — und dann startet
     * dieselbe Folge auf iPhone und Telefon an verschiedenen Stellen.
     */
    fun startPlay(episode: Episode) {
        val ready = _state.value as? SeriesUiState.Ready ?: return
        viewModelScope.launch {
            val progress = Nori.library.snapshot.value
                .progressFor(episode.path, provider)
            val rules = runCatching { NoriCore.progressRules(progress) }.getOrNull()
            val at = if (Nori.library.snapshot.value.resumeEnabled) rules?.resumeAt ?: 0.0 else 0.0

            _play.value = PlaybackRequest(
                slug = slug,
                title = ready.detail.title.ifBlank { titleHint },
                provider = provider,
                season = ready.detail.activeSeason,
                episodes = ready.detail.episodes,
                start = episode,
                resumeAtSec = at,
            )
        }
    }

    fun consumePlay() {
        _play.value = null
    }

    fun toggleFavorite() {
        viewModelScope.launch {
            val title = (state.value as? SeriesUiState.Ready)?.detail?.title ?: titleHint
            runCatching { Nori.library.toggleFavorite(slug, title) }
        }
    }

    private fun load(season: String?) {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            val previous = _state.value as? SeriesUiState.Ready
            if (previous == null) _state.value = SeriesUiState.Loading

            val detail = try {
                Nori.catalog.series(provider, slug, season)
            } catch (error: Throwable) {
                _state.value = SeriesUiState.Error(error.userMessage())
                return@launch
            }
            currentSeason = detail.activeSeason

            // Erst das Gerüst zeigen, dann nachtragen. Cover und
            // Folgenbilder kommen von TMDB und dürfen die Liste nicht
            // aufhalten.
            _state.value = SeriesUiState.Ready(
                detail = detail,
                provider = provider,
                cover = previous?.cover,
                episodeInfo = emptyMap(),
                stats = null,
                next = null,
            )

            val cover = runCatching {
                Nori.covers.resolve(slug, detail.title, provider)
            }.getOrNull()
            update { it.copy(cover = cover) }

            val stats = runCatching {
                Nori.library.seasonStats(slug, detail.activeSeason, detail.episodes, provider)
            }.getOrNull()
            val next = runCatching {
                Nori.library.nextPlay(slug, detail.activeSeason, detail.episodes, provider)
            }.getOrNull()
            update { it.copy(stats = stats, next = next) }

            val info = runCatching {
                NoriCore.episodeInfo(
                    slug = slug,
                    title = detail.title,
                    alternates = detail.alts,
                    season = detail.activeSeason,
                    provider = provider,
                )
            }.getOrDefault(emptyMap())
            update { it.copy(episodeInfo = info) }
        }
    }

    /** Fortschrittszahlen neu holen, nachdem der Player etwas gespeichert hat. */
    fun refreshProgress() {
        val ready = _state.value as? SeriesUiState.Ready ?: return
        viewModelScope.launch {
            val stats = runCatching {
                Nori.library.seasonStats(slug, ready.detail.activeSeason, ready.detail.episodes, provider)
            }.getOrNull()
            val next = runCatching {
                Nori.library.nextPlay(slug, ready.detail.activeSeason, ready.detail.episodes, provider)
            }.getOrNull()
            update { it.copy(stats = stats, next = next) }
        }
    }

    private fun update(block: (SeriesUiState.Ready) -> SeriesUiState.Ready) {
        val ready = _state.value as? SeriesUiState.Ready ?: return
        _state.value = block(ready)
    }

    /** Die Folge, die der Abspielknopf startet. */
    fun episodeFor(number: Int): Episode? =
        (state.value as? SeriesUiState.Ready)?.detail?.episodes?.firstOrNull { it.number == number }
}
