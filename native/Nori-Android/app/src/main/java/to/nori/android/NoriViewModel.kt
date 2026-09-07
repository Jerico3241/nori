package to.nori.android

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Der gemeinsame Zustand der App.
 *
 * Ein einziges ViewModel für alle Tabs, nicht eines je Ansicht: Katalog und
 * Bibliothek werden von mehreren Tabs gelesen, und zweimal geladen wäre der
 * Katalog zweimal geparst — bei 2500 Titeln ist das spürbar.
 *
 * Der Katalog wird je Quelle gehalten, damit ein Wechsel zwischen Anime und
 * Serien nicht jedes Mal neu lädt.
 */
class NoriViewModel : ViewModel() {

    private val catalogs = mutableMapOf<Provider, List<CatalogItem>>()

    private val _provider = MutableStateFlow(Provider.ANIWORLD)
    val provider: StateFlow<Provider> = _provider.asStateFlow()

    private val _catalog = MutableStateFlow<List<CatalogItem>>(emptyList())
    val catalog: StateFlow<List<CatalogItem>> = _catalog.asStateFlow()

    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _library = MutableStateFlow(LibrarySnapshot())
    val library: StateFlow<LibrarySnapshot> = _library.asStateFlow()

    private val _calendar = MutableStateFlow<CalendarPayload?>(null)
    val calendar: StateFlow<CalendarPayload?> = _calendar.asStateFlow()

    private val _calendarLoading = MutableStateFlow(false)
    val calendarLoading: StateFlow<Boolean> = _calendarLoading.asStateFlow()

    /**
     * Die Genre-Zeilen der Startseite — **einmal** berechnet, wenn der
     * Katalog steht.
     *
     * Vorher rechnete die Startseite sie bei jeder Neukomposition neu: über
     * 2463 Titel samt Genres, mit Maps und Sortierung, auf dem Haupt-Thread.
     * Das Ergebnis war kein langsames Bild, sondern ein ANR — Android hat die
     * App nach 125 Sekunden Blockade abgeschossen.
     */
    private val _genreRows = MutableStateFlow<List<Pair<String, List<CatalogItem>>>>(emptyList())
    val genreRows: StateFlow<List<Pair<String, List<CatalogItem>>>> = _genreRows.asStateFlow()

    init {
        loadCatalog()
        refreshLibrary()
    }

    fun switch(to: Provider) {
        if (_provider.value == to) return
        _provider.value = to
        // Aus dem Zwischenspeicher, falls schon geladen — sonst frisch.
        catalogs[to]?.let { _catalog.value = it } ?: run { _catalog.value = emptyList() }
        loadCatalog()
        _calendar.value = null
        _genreRows.value = emptyList()
    }

    fun loadCatalog(force: Boolean = false) {
        val source = _provider.value
        if (!force && catalogs[source] != null) {
            val cached = catalogs[source]!!
            _catalog.value = cached
            viewModelScope.launch {
                _genreRows.value = withContext(Dispatchers.Default) { buildGenreRows(cached) }
            }
            return
        }
        viewModelScope.launch {
            _loading.value = true
            _error.value = null
            when (val result = NoriRepository.catalog(source)) {
                is Result.Ok -> {
                    catalogs[source] = result.value
                    // Nur übernehmen, wenn der Nutzer inzwischen nicht
                    // umgeschaltet hat — sonst erscheinen Anime unter Serien.
                    if (_provider.value == source) {
                        _catalog.value = result.value
                        _genreRows.value = withContext(Dispatchers.Default) {
                            buildGenreRows(result.value)
                        }
                    }
                }
                is Result.Failed -> if (_provider.value == source) _error.value = result.message
            }
            _loading.value = false
        }
    }

    fun loadCalendar(force: Boolean = false) {
        if (!force && _calendar.value != null) return
        val source = _provider.value
        viewModelScope.launch {
            _calendarLoading.value = true
            when (val result = NoriRepository.calendar(source)) {
                is Result.Ok -> if (_provider.value == source) _calendar.value = result.value
                is Result.Failed -> if (_provider.value == source) _error.value = result.message
            }
            _calendarLoading.value = false
        }
    }

    fun refreshLibrary() {
        viewModelScope.launch {
            when (val result = NoriRepository.library()) {
                is Result.Ok -> _library.value = result.value
                is Result.Failed -> Unit // Die Bibliothek ist lokal; ein
                // Fehlschlag hier ist kein Grund, die Ansicht zu stören.
            }
        }
    }

    fun toggleFavorite(slug: String, title: String, source: Provider = _provider.value) {
        viewModelScope.launch {
            NoriRepository.toggleFavorite(slug, title, source)
            refreshLibrary()
        }
    }

    fun remember(slug: String, title: String, source: Provider = _provider.value) {
        viewModelScope.launch {
            NoriRepository.remember(slug, title, source)
            refreshLibrary()
        }
    }

    fun clear(what: String) {
        viewModelScope.launch {
            NoriRepository.clear(what)
            refreshLibrary()
        }
    }

    fun setPrefs(lang: String, hoster: String) {
        viewModelScope.launch {
            NoriRepository.putPrefs(lang, hoster)
            refreshLibrary()
        }
    }

    /** Zu welcher Quelle ein gemerkter Titel gehört. */
    fun sourceOf(slug: String): Provider =
        Provider.from(_library.value.favoriteSource[slug] ?: _provider.value.raw)

    /** Genre-Zeilen nach Häufigkeit. Rein — der Aufrufer sorgt für den Thread. */
    private fun buildGenreRows(
        items: List<CatalogItem>,
        limit: Int = 8,
    ): List<Pair<String, List<CatalogItem>>> {
        val byGenre = mutableMapOf<String, MutableList<CatalogItem>>()
        for (item in items) {
            for (genre in item.genres) {
                if (genre.isBlank() || genre.startsWith("filter.")) continue
                byGenre.getOrPut(genre) { mutableListOf() }.add(item)
            }
        }
        return byGenre.entries
            .filter { it.value.size >= 6 }
            .sortedByDescending { it.value.size }
            .take(limit)
            .map { it.key to it.value.take(20) }
    }
}
