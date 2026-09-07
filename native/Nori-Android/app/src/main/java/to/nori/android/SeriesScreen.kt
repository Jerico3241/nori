package to.nori.android

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController

/**
 * Die Detailseite: Beschreibung, Staffelwahl, Folgenliste.
 *
 * Der Fortschritt aller Folgen wird in **einem** Durchgang erfragt
 * ([NoriRepository.progressFor]). Einzeln je Folge kostete einen
 * Thread-Wechsel und ein Semaphor pro Aufruf — bei einer langen Staffel eine
 * spürbare Pause, bevor die Liste steht.
 */
@Composable
fun SeriesScreen(
    model: NoriViewModel,
    nav: NavHostController,
    provider: Provider,
    slug: String,
) {
    var detail by remember { mutableStateOf<SeriesDetail?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    var season by remember { mutableStateOf("") }
    var cover by remember { mutableStateOf<String?>(null) }
    var progress by remember { mutableStateOf<Map<String, WatchProgress>>(emptyMap()) }

    val library by model.library.collectAsState()
    val isFavorite = library.favorites.contains(slug)

    LaunchedEffect(slug, season) {
        loading = true
        error = null
        when (val result = NoriRepository.series(provider, slug, season)) {
            is Result.Ok -> {
                detail = result.value
                cover = NoriRepository.coverUrl(provider, result.value.coverPath)
                // Merken, dass der Titel angesehen wurde — füttert „Verlauf".
                model.remember(slug, result.value.title, provider)
                progress = NoriRepository.progressFor(
                    result.value.episodes.map { it.path },
                    provider,
                )
            }
            is Result.Failed -> error = result.message
        }
        loading = false
    }

    val current = detail

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 32.dp),
    ) {
        item {
            Row(
                Modifier.fillMaxWidth().padding(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = { nav.popBackStack() }) {
                    Icon(Icons.Filled.ArrowBack, contentDescription = "Zurück")
                }
                Text(
                    current?.title ?: slug,
                    style = MaterialTheme.typography.titleLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = {
                    model.toggleFavorite(slug, current?.title ?: slug, provider)
                }) {
                    Icon(
                        if (isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                        contentDescription = if (isFavorite) "Nicht mehr merken" else "Merken",
                    )
                }
            }
        }

        if (loading && current == null) {
            item {
                Row(Modifier.fillMaxWidth().padding(32.dp), horizontalArrangement = Arrangement.Center) {
                    CircularProgressIndicator()
                }
            }
        }

        if (error != null) {
            item {
                Column(Modifier.padding(16.dp)) {
                    Text(error!!, color = MaterialTheme.colorScheme.error)
                    Button(onClick = { season = season }) { Text("Erneut versuchen") }
                }
            }
        }

        if (current != null) {
            item {
                Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    PosterTile(
                        title = current.title,
                        coverUrl = cover,
                        modifier = Modifier.width(120.dp).height(170.dp),
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        val meta = listOfNotNull(
                            current.yearStart?.takeIf { it.isNotBlank() },
                            current.fsk?.takeIf { it.isNotBlank() }?.let { "FSK $it" },
                            current.genres.take(2).joinToString(" · ").takeIf { it.isNotBlank() },
                        ).joinToString(" · ")
                        if (meta.isNotBlank()) {
                            Text(meta, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        // Erste abspielbare Folge — der „Jetzt ansehen"-Knopf.
                        val first = current.episodes.firstOrNull { it.path.isNotBlank() }
                        if (first != null) {
                            Button(onClick = { nav.openPlayer(provider, first.path) }) {
                                Icon(Icons.Filled.PlayArrow, contentDescription = null)
                                Text("  Abspielen")
                            }
                        }
                    }
                }
            }

            if (current.description.isNotBlank()) {
                item {
                    Text(
                        current.description,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(16.dp),
                    )
                }
            }

            if (current.seasons.isNotEmpty()) {
                item {
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(current.seasons, key = { it.id }) { ref ->
                            FilterChip(
                                selected = ref.id == current.activeSeason,
                                onClick = { season = ref.id },
                                label = { Text(ref.label) },
                            )
                        }
                    }
                }
            }

            item {
                SectionHeader("Folgen", "${current.episodes.size}")
                HorizontalDivider()
            }

            items(current.episodes, key = { it.path.ifBlank { "e${it.number}" } }) { episode ->
                val watched = progress[episode.path]
                ListItem(
                    headlineContent = {
                        Text("${episode.number}. ${episode.displayTitle}",
                            maxLines = 2, overflow = TextOverflow.Ellipsis)
                    },
                    supportingContent = {
                        val bits = buildList {
                            if (episode.languages.isNotEmpty()) add(episode.languages.joinToString("/"))
                            if (watched != null) {
                                add(if (watched.isComplete) "gesehen" else "${(watched.ratio * 100).toInt()} %")
                            }
                        }
                        if (bits.isNotEmpty()) Text(bits.joinToString(" · "))
                    },
                    trailingContent = {
                        Icon(Icons.Filled.PlayArrow, contentDescription = "Abspielen")
                    },
                    modifier = Modifier.clickable(enabled = episode.path.isNotBlank()) {
                        nav.openPlayer(provider, episode.path)
                    },
                )
                HorizontalDivider()
            }
        }
    }
}
