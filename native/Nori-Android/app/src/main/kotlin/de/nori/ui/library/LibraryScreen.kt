package de.nori.ui.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import de.nori.core.AiringEntry
import de.nori.core.CatalogProvider
import de.nori.core.providerFromPath
import de.nori.ui.components.ContentPadding
import de.nori.ui.components.EmptyState
import de.nori.ui.components.LoadingState
import de.nori.ui.components.NoriChip
import de.nori.ui.components.OneLine
import de.nori.ui.components.PosterCard
import de.nori.ui.components.PosterRow
import de.nori.ui.theme.NoriColors
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private enum class LibraryTab(val label: String) {
    Watchlist("Merkliste"),
    History("Verlauf"),
    Calendar("Kalender"),
}

/**
 * Merkliste, Verlauf und Kalender.
 *
 * Alle drei lesen denselben Bibliotheksstand wie jeder andere Bildschirm.
 * Wird ein Titel auf der Detailseite gemerkt, ist er hier sofort da — nicht,
 * weil hier etwas nachgeladen wird, sondern weil es nur einen Zustand gibt.
 */
@Composable
fun LibraryScreen(
    viewModel: LibraryViewModel,
    columns: Int,
    onOpenSeries: (slug: String, title: String, provider: CatalogProvider) -> Unit,
) {
    var tab by remember { mutableStateOf(LibraryTab.Watchlist) }
    val snapshot by viewModel.snapshot.collectAsStateWithLifecycle()
    val calendar by viewModel.calendar.collectAsStateWithLifecycle()

    Column(Modifier.fillMaxSize()) {
        LazyRow(
            contentPadding = ContentPadding,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(vertical = 10.dp),
        ) {
            items(LibraryTab.entries.toList(), key = { it.name }) { entry ->
                NoriChip(entry.label, selected = entry == tab, onClick = { tab = entry })
            }
        }

        Box(Modifier.fillMaxSize()) {
            when (tab) {
                LibraryTab.Watchlist -> {
                    val favorites = snapshot.favorites
                    if (favorites.isEmpty()) {
                        EmptyState(
                            "Die Merkliste ist leer.",
                            "Auf einer Detailseite lässt sich ein Titel merken.",
                        )
                    } else {
                        LazyVerticalGrid(
                            columns = GridCells.Fixed(columns),
                            contentPadding = PaddingValues(16.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalArrangement = Arrangement.spacedBy(18.dp),
                        ) {
                            items(favorites, key = { it }) { slug ->
                                val provider = snapshot.sourceOf(slug)
                                val title = snapshot.titles[slug] ?: slug
                                PosterCard(
                                    title = title,
                                    slug = slug,
                                    provider = provider,
                                    subtitle = provider.label,
                                    onClick = { onOpenSeries(slug, title, provider) },
                                )
                            }
                        }
                    }
                }

                LibraryTab.History -> {
                    val recents = snapshot.recents
                    if (recents.isEmpty()) {
                        EmptyState("Noch nichts angesehen.")
                    } else {
                        LazyColumn(contentPadding = PaddingValues(vertical = 8.dp)) {
                            items(recents, key = { "${it.provider?.wire}|${it.slug}|${it.viewedAt}" }) { item ->
                                val provider = item.provider ?: CatalogProvider.Aniworld
                                val progress = snapshot.progress.values
                                    .filter { it.slug == item.slug }
                                    .maxByOrNull { it.updatedAt }
                                PosterRow(
                                    title = item.title,
                                    slug = item.slug,
                                    provider = provider,
                                    subtitle = progress?.let {
                                        "S${it.season} · F${it.episode} · ${provider.label}"
                                    } ?: provider.label,
                                    progress = progress?.ratio ?: 0f,
                                    onClick = { onOpenSeries(item.slug, item.title, provider) },
                                )
                            }
                        }
                    }
                }

                LibraryTab.Calendar -> when (val current = calendar) {
                    null -> LoadingState("Kalender wird geladen")
                    else -> if (current.isEmpty()) {
                        EmptyState("Für die nächsten Tage ist nichts eingetragen.")
                    } else {
                        LazyColumn(contentPadding = PaddingValues(vertical = 8.dp)) {
                            items(
                                current,
                                key = { "${it.provider?.wire}|${it.slug}|${it.season}|${it.episode}|${it.dayKey}" },
                            ) { entry ->
                                CalendarRow(entry, onOpenSeries)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CalendarRow(
    entry: AiringEntry,
    onOpenSeries: (String, String, CatalogProvider) -> Unit,
) {
    val provider = entry.provider ?: CatalogProvider.Aniworld
    PosterRow(
        title = entry.title,
        slug = entry.slug,
        provider = provider,
        subtitle = "${entry.dayLabel} · ${airTime(entry.airingAt)} · S${entry.season} F${entry.episode}",
        onClick = { onOpenSeries(entry.slug, entry.title, provider) },
    )
}

/**
 * Die Uhrzeit einer Ausstrahlung.
 *
 * Der Kern liefert einen Zeitstempel in Millisekunden und rechnet dabei in
 * Europa/Berlin — die Quellen tun das auch. Angezeigt wird deshalb die lokale
 * Zeit des Geräts, was für die allermeisten Nutzer dasselbe ist.
 */
private fun airTime(millis: Double): String =
    SimpleDateFormat("HH:mm", Locale.GERMANY).format(Date(millis.toLong()))
