package de.nori.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.nori.core.AiringEntry
import de.nori.core.CatalogItem
import de.nori.core.CatalogProvider
import de.nori.core.LibraryScope
import de.nori.core.NoriCore
import de.nori.core.WatchProgress
import de.nori.core.normalizeEpisodePath
import de.nori.core.providerFromPath
import de.nori.ui.PlaybackRequest
import de.nori.core.userMessage
import de.nori.data.Nori
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Eine Reihe der Startseite. */
data class HomeRow(
    val title: String,
    val items: List<CatalogItem>,
)

data class HeroItem(
    val slug: String,
    val title: String,
    val provider: CatalogProvider,
    val genres: List<String>,
) {
    val key: String get() = "${provider.wire}|$slug"
}

/**
 * Was ein Tipp auf „Weiterschauen" ergibt.
 *
 * Der Fortschrittseintrag kennt Folge und Pfad, aber nicht die Folgenliste
 * der Staffel — und die braucht der Player für „nächste Folge" und Autoplay.
 * Sie wird deshalb nachgeholt. Klappt das nicht (Quelle nicht erreichbar,
 * Staffel neu geschnitten), führt der Tipp auf die Detailseite statt ins
 * Leere.
 */
sealed interface ResumeResult {
    data class Play(val request: PlaybackRequest) : ResumeResult
    data class OpenSeries(
        val slug: String,
        val title: String,
        val provider: CatalogProvider,
    ) : ResumeResult
}

sealed interface HomeUiState {
    data object Loading : HomeUiState

    data class Ready(
        val hero: List<HeroItem>,
        val popularTitle: String,
        val popular: List<CatalogItem>,
        val rows: List<HomeRow>,
        val freshEpisodes: List<AiringEntry>,
        /** Nicht leer, wenn der Katalog steht, aber eine Quelle klemmt. */
        val warning: String? = null,
    ) : HomeUiState

    data class Error(val message: String) : HomeUiState
}

class HomeViewModel : ViewModel() {

    private val _state = MutableStateFlow<HomeUiState>(HomeUiState.Loading)
    val state: StateFlow<HomeUiState> = _state.asStateFlow()

    private val _refreshing = MutableStateFlow(false)
    val refreshing: StateFlow<Boolean> = _refreshing.asStateFlow()

    val snapshot = Nori.library.snapshot

    /**
     * „Weiterschauen" wird bei jeder Änderung der Bibliothek neu beim Kern
     * geholt.
     *
     * Die Auswahl ist keine Anzeigefrage: welche Folge weitergeht und welche
     * als abgeschlossen gilt, entscheidet `continueWatching()` in
     * `LibraryStore`. In Kotlin nachgebaut liefe es früher oder später
     * auseinander.
     */
    val continueWatching: StateFlow<List<WatchProgress>> = snapshot
        .map { runCatching { NoriCore.continueWatching() }.getOrDefault(emptyList()) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val scope: StateFlow<LibraryScope> = snapshot
        .map { it.currentScope }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), LibraryScope.All)

    init {
        viewModelScope.launch {
            // Bei jedem Bereichswechsel neu aufbauen. Der Bereich entscheidet,
            // welche Quellen geladen und welche Titel gezeigt werden.
            snapshot.map { it.currentScope }.collect { load(it, force = false) }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _refreshing.value = true
            load(snapshot.value.currentScope, force = true)
            _refreshing.value = false
        }
    }

    private val _resume = MutableStateFlow<ResumeResult?>(null)
    val resume: StateFlow<ResumeResult?> = _resume.asStateFlow()

    private val _resuming = MutableStateFlow(false)
    val resuming: StateFlow<Boolean> = _resuming.asStateFlow()

    /**
     * „Weiterschauen" soll die Folge starten, nicht die Detailseite öffnen.
     *
     * Dafür fehlen zwei Dinge, die der Fortschrittseintrag nicht hat: die
     * Folgenliste der Staffel und die genaue Stelle nach den Regeln des Kerns
     * (unter acht Sekunden wird von vorn begonnen, eine fast fertige Folge
     * gilt als gesehen). Beides wird hier geholt.
     */
    fun startResume(progress: WatchProgress) {
        if (_resuming.value) return
        viewModelScope.launch {
            _resuming.value = true
            val provider = progress.provider ?: providerFromPath(progress.episodePath)
            _resume.value = buildResume(progress, provider)
            _resuming.value = false
        }
    }

    fun consumeResume() {
        _resume.value = null
    }

    private suspend fun buildResume(
        progress: WatchProgress,
        provider: CatalogProvider,
    ): ResumeResult {
        val fallback = ResumeResult.OpenSeries(progress.slug, progress.title, provider)

        val detail = runCatching {
            Nori.catalog.series(provider, progress.slug, progress.season.ifBlank { null })
        }.getOrNull() ?: return fallback

        val episode = detail.episodes.firstOrNull { it.number == progress.episode }
            ?: detail.episodes.firstOrNull {
                normalizeEpisodePath(it.path) == normalizeEpisodePath(progress.episodePath)
            }
            ?: return fallback

        // Die Stelle bestimmt der Kern, nicht diese Datei.
        val rules = runCatching { NoriCore.progressRules(progress) }.getOrNull()
        val at = if (snapshot.value.resumeEnabled) rules?.resumeAt ?: 0.0 else 0.0

        return ResumeResult.Play(
            PlaybackRequest(
                slug = progress.slug,
                title = detail.title.ifBlank { progress.title },
                provider = provider,
                season = detail.activeSeason,
                episodes = detail.episodes,
                start = episode,
                resumeAtSec = at,
            )
        )
    }

    fun setScope(next: LibraryScope) {
        viewModelScope.launch { Nori.library.setScope(next) }
    }

    private suspend fun load(scope: LibraryScope, force: Boolean) {
        val providers = scope.provider?.let { listOf(it) }
            ?: listOf(CatalogProvider.Aniworld, CatalogProvider.Serienstream)

        val loaded = mutableListOf<CatalogItem>()
        val failures = mutableListOf<String>()
        for (provider in providers) {
            runCatching { Nori.catalog.catalog(provider, force) }
                .onSuccess { loaded += it }
                .onFailure { failures += "${provider.label}: ${it.userMessage()}" }
        }

        if (loaded.isEmpty()) {
            _state.value = HomeUiState.Error(
                failures.joinToString("\n").ifEmpty { "Kein Katalog verfügbar." }
            )
            return
        }

        val items = loaded.filter { scope.includes(it) }

        // Der Kalender ist Beiwerk: schlägt er fehl, bleibt die Startseite
        // trotzdem stehen.
        val fresh = providers.flatMap { provider ->
            runCatching { Nori.catalog.calendar(provider, force).recent }.getOrDefault(emptyList())
        }.sortedByDescending { it.airingAt }.take(20)

        _state.value = HomeUiState.Ready(
            hero = buildHero(items, scope),
            popularTitle = "Beliebt · ${scope.label}",
            popular = items.take(20),
            rows = buildRows(items),
            freshEpisodes = fresh,
            warning = failures.joinToString("\n").ifEmpty { null },
        )
    }

    private fun buildHero(items: List<CatalogItem>, scope: LibraryScope): List<HeroItem> {
        // Titel ohne Genre sagen im Kopfbereich nichts aus; nur wenn zu wenige
        // mit Genre da sind, wird der ganze Katalog genommen.
        val described = items.filter { it.genres.isNotEmpty() }
        val source = if (described.size >= 6) described else items
        if (source.isEmpty()) return emptyList()

        val day = (System.currentTimeMillis() / 86_400_000L).toInt()
        return source
            .sortedBy { featureRank(it.slug, day) }
            .take(5)
            .map {
                HeroItem(
                    slug = it.slug,
                    title = it.title,
                    provider = it.provider ?: scope.provider ?: CatalogProvider.Aniworld,
                    genres = it.genres,
                )
            }
    }

    private fun buildRows(items: List<CatalogItem>): List<HomeRow> {
        if (items.size <= 12) return emptyList()

        val counts = mutableMapOf<String, Int>()
        for (item in items) {
            for (genre in item.genres.take(3)) {
                if (genre.isBlank()) continue
                counts[genre] = (counts[genre] ?: 0) + 1
            }
        }
        val top = counts
            .filterValues { it >= 8 }
            .entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .take(6)
            .map { it.key }

        // Über den zusammengesetzten Schlüssel entdoppeln, nicht über den
        // Slug: beide Quellen können denselben Slug führen.
        val used = mutableSetOf<String>()
        val rows = mutableListOf<HomeRow>()
        for (genre in top) {
            val row = items
                .filter { it.genres.contains(genre) && it.key !in used }
                .take(18)
            if (row.size < 6) continue
            used += row.map { it.key }
            rows += HomeRow(genre, row)
        }
        return rows
    }

    private companion object {
        /**
         * Stabile Streuung über den Tag.
         *
         * `hashCode()` ist in der JVM zwar stabil, in Kotlin/Native aber nicht
         * — und vor allem soll sich die Auswahl täglich ändern, nicht bei
         * jedem Start. Dieselbe Rechnung wie in `HomeView.featureRank` auf
         * Apple, damit beide Plattformen denselben Titel zeigen.
         */
        fun featureRank(slug: String, day: Int): Int {
            var acc = day * 2_654_435_761L
            for (char in slug) {
                acc = (acc * 31 + char.code) % 1_000_003
            }
            return (if (acc < 0) -acc else acc).toInt()
        }
    }
}
