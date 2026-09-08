package de.nori.ui.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.nori.core.AiringEntry
import de.nori.core.CatalogProvider
import de.nori.data.Nori
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

class LibraryViewModel : ViewModel() {

    val snapshot = Nori.library.snapshot

    /** `null` heißt „wird noch geladen", eine leere Liste heißt „nichts da". */
    private val _calendar = MutableStateFlow<List<AiringEntry>?>(null)
    val calendar: StateFlow<List<AiringEntry>?> = _calendar.asStateFlow()

    init {
        viewModelScope.launch {
            snapshot.map { it.currentScope }.collect { scope ->
                _calendar.value = null
                val providers = scope.provider?.let { listOf(it) }
                    ?: listOf(CatalogProvider.Aniworld, CatalogProvider.Serienstream)
                val entries = providers.flatMap { provider ->
                    runCatching { Nori.catalog.calendar(provider).upcoming }
                        .getOrDefault(emptyList())
                }
                _calendar.value = entries.sortedBy { it.airingAt }
            }
        }
    }
}
