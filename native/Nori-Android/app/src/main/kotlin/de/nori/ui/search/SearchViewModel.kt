package de.nori.ui.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.nori.core.CatalogItem
import de.nori.core.CatalogProvider
import de.nori.core.LibraryScope
import de.nori.core.userMessage
import de.nori.data.Nori
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

sealed interface SearchUiState {
    data object Loading : SearchUiState
    data class Error(val message: String) : SearchUiState
    data class Ready(val results: List<CatalogItem>, val scopeLabel: String) : SearchUiState
}

@OptIn(FlowPreview::class)
class SearchViewModel : ViewModel() {

    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()

    private val _state = MutableStateFlow<SearchUiState>(SearchUiState.Loading)
    val state: StateFlow<SearchUiState> = _state.asStateFlow()

    private val items = MutableStateFlow<List<CatalogItem>>(emptyList())

    init {
        viewModelScope.launch {
            Nori.library.snapshot.map { it.currentScope }.collect { load(it, force = false) }
        }
        viewModelScope.launch {
            // 250 ms: kurz genug, dass es sich sofort anfühlt, lang genug,
            // dass beim Tippen nicht jede Zwischenstufe einen Filterlauf über
            // mehrere tausend Einträge auslöst.
            combine(items, _query.debounce(250)) { list, text -> list to text }
                .collect { (list, text) ->
                    if (list.isEmpty()) return@collect
                    _state.value = SearchUiState.Ready(
                        results = Nori.catalog.search(list, text),
                        scopeLabel = Nori.library.snapshot.value.currentScope.label,
                    )
                }
        }
    }

    fun onQueryChange(text: String) {
        _query.value = text
    }

    fun reload() {
        viewModelScope.launch { load(Nori.library.snapshot.value.currentScope, force = true) }
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
            _state.value = SearchUiState.Error(
                failures.joinToString("\n").ifEmpty { "Kein Katalog verfügbar." }
            )
            return
        }
        items.value = loaded.filter { scope.includes(it) }
    }
}
