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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val gutter = 16.dp

/**
 * Startseite: „Schau weiter", Merkliste und Genre-Zeilen.
 *
 * Bewusst keine Kopfkarussell-Kachel wie auf iOS — dort trägt sie ein
 * Backdrop aus TMDB, das über die Brücke noch nicht zu haben ist. Eine leere
 * Fläche an der Stelle wäre schlechter als keine.
 */
@Composable
fun HomeScreen(model: NoriViewModel, nav: NavHostController) {
    val catalog by model.catalog.collectAsState()
    val library by model.library.collectAsState()
    val loading by model.loading.collectAsState()
    val error by model.error.collectAsState()
    val genreRows by model.genreRows.collectAsState()

    LazyColumn(
        contentPadding = PaddingValues(gutter),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        item {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Entdecken", style = MaterialTheme.typography.headlineMedium)
                KindSwitch(model)
            }
        }

        if (error != null) {
            item {
                Column {
                    Text(error!!, color = MaterialTheme.colorScheme.error)
                    Button(onClick = { model.loadCatalog(force = true) }) { Text("Erneut versuchen") }
                }
            }
        }

        if (library.continueWatching.isNotEmpty()) {
            item { SectionHeader("Schau weiter") }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(library.continueWatching, key = { it.episodePath }) { entry ->
                        Column(Modifier.width(140.dp)) {
                            PosterCell(
                                title = entry.title.ifBlank { entry.slug },
                                subtitle = "S${entry.season} · F${entry.episode}",
                                coverUrl = null,
                                progress = entry.ratio,
                                onClick = {
                                    nav.openSeries(Provider.from(entry.provider), entry.slug)
                                },
                            )
                        }
                    }
                }
            }
        }

        if (library.favorites.isNotEmpty()) {
            item { SectionHeader("Merkliste", "${library.favorites.size}") }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(library.favorites, key = { it }) { slug ->
                        Column(Modifier.width(140.dp)) {
                            PosterCell(
                                title = library.titles[slug] ?: slug,
                                coverUrl = null,
                                onClick = { nav.openSeries(model.sourceOf(slug), slug) },
                            )
                        }
                    }
                }
            }
        }

        if (loading && catalog.isEmpty()) {
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                    CircularProgressIndicator()
                }
            }
        }

        genreRows.forEach { (genre, items) ->
            item { SectionHeader(genre, "${items.size}") }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(items, key = { it.id }) { item ->
                        Column(Modifier.width(140.dp)) {
                            PosterCell(
                                title = item.title,
                                coverUrl = null,
                                onClick = {
                                    nav.openSeries(Provider.from(item.provider), item.slug)
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Katalog als Raster mit Suche — wie auf iOS. */
@Composable
fun CatalogScreen(model: NoriViewModel, nav: NavHostController) {
    val catalog by model.catalog.collectAsState()
    val loading by model.loading.collectAsState()
    var query by remember { mutableStateOf("") }

    val filtered = remember(catalog, query) {
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) catalog
        else catalog.filter { item ->
            item.title.lowercase().contains(needle) ||
                item.slug.lowercase().contains(needle) ||
                item.alts.any { it.lowercase().contains(needle) }
        }
    }

    Column(Modifier.fillMaxSize().padding(horizontal = gutter)) {
        Row(
            Modifier.fillMaxWidth().padding(vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Katalog", style = MaterialTheme.typography.headlineMedium)
            KindSwitch(model)
        }
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text("Suchen") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        if (loading && catalog.isEmpty()) {
            StatusBox("Katalog wird geladen …")
            return@Column
        }
        Text(
            "${filtered.size} Titel",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(vertical = 8.dp),
        )
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 110.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            contentPadding = PaddingValues(bottom = 24.dp),
        ) {
            items(filtered, key = { it.id }) { item ->
                PosterCell(
                    title = item.title,
                    subtitle = item.genres.take(2).joinToString(" · ").ifBlank { null },
                    coverUrl = null,
                    onClick = { nav.openSeries(Provider.from(item.provider), item.slug) },
                )
            }
        }
    }
}

/** Kalender: kommende und kürzliche Folgen, nach Tag gruppiert. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalendarScreen(model: NoriViewModel, nav: NavHostController) {
    val payload by model.calendar.collectAsState()
    val loading by model.calendarLoading.collectAsState()

    LaunchedEffect(Unit) { model.loadCalendar() }

    Column(Modifier.fillMaxSize().padding(horizontal = gutter)) {
        Row(
            Modifier.fillMaxWidth().padding(vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Kalender", style = MaterialTheme.typography.headlineMedium)
            KindSwitch(model)
        }
        when {
            loading && payload == null -> StatusBox("Kalender wird geladen …")
            payload == null -> StatusBox("Kein Kalender geladen.")
            else -> {
                val rows = payload!!.upcoming
                if (rows.isEmpty()) {
                    StatusBox("Für die nächsten Tage ist nichts eingetragen.")
                } else {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        var lastDay = ""
                        items(rows, key = { "${it.slug}|${it.season}|${it.episode}|${it.dayKey}" }) { row ->
                            if (row.dayLabel != lastDay) {
                                lastDay = row.dayLabel
                                SectionHeader(row.dayLabel)
                            }
                            ListItem(
                                headlineContent = {
                                    Text(row.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                },
                                supportingContent = {
                                    Text(
                                        "S${row.season} · F${row.episode}" +
                                            if (row.languages.isNotEmpty()) " · ${row.languages.first()}" else ""
                                    )
                                },
                                leadingContent = {
                                    PosterTile(
                                        title = row.title,
                                        coverUrl = null,
                                        modifier = Modifier.width(44.dp).height(62.dp),
                                    )
                                },
                                modifier = Modifier.clickable {
                                    nav.openSeries(Provider.from(row.provider), row.slug)
                                },
                            )
                            HorizontalDivider()
                        }
                    }
                }
            }
        }
    }
}

/** Merkliste. */
@Composable
fun WatchlistScreen(model: NoriViewModel, nav: NavHostController) {
    val library by model.library.collectAsState()

    Column(Modifier.fillMaxSize().padding(horizontal = gutter)) {
        Text(
            "Merkliste",
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.padding(vertical = 8.dp),
        )
        if (library.favorites.isEmpty()) {
            StatusBox("Noch nichts gemerkt.\nAuf einer Detailseite lässt sich ein Titel merken.")
            return@Column
        }
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 110.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            contentPadding = PaddingValues(bottom = 24.dp),
        ) {
            items(library.favorites, key = { it }) { slug ->
                PosterCell(
                    title = library.titles[slug] ?: slug,
                    coverUrl = null,
                    onClick = { nav.openSeries(model.sourceOf(slug), slug) },
                )
            }
        }
    }
}

/** Einstellungen und Diagnose. */
@Composable
fun SettingsScreen(model: NoriViewModel) {
    val library by model.library.collectAsState()
    var ping by remember { mutableStateOf("") }
    var storage by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    LazyColumn(
        contentPadding = PaddingValues(gutter),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { Text("Mehr", style = MaterialTheme.typography.headlineMedium) }

        item { SectionHeader("Wiedergabe") }
        item {
            Text("Sprache: ${library.langPref} · Hoster: ${library.hosterPref}")
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("DE", "SUB", "ENG").forEach { lang ->
                    OutlinedButton(onClick = { model.setPrefs(lang, library.hosterPref) }) {
                        Text(lang)
                    }
                }
            }
        }

        item { SectionHeader("Bibliothek") }
        item {
            Text("${library.favorites.size} gemerkt · ${library.recents.size} im Verlauf")
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { model.clear("history") }) { Text("Verlauf leeren") }
                OutlinedButton(onClick = { model.clear("progress") }) { Text("Fortschritt leeren") }
            }
        }

        item { SectionHeader("Diagnose") }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = {
                    scope.launch {
                        ping = (NoriRepository.ping() as? Result.Ok)?.value ?: "Fehler"
                    }
                }) { Text("Lebenszeichen") }
                OutlinedButton(onClick = {
                    scope.launch {
                        storage = (NoriRepository.storagePath() as? Result.Ok)?.value ?: "Fehler"
                    }
                }) { Text("Ablageort") }
            }
        }
        if (ping.isNotEmpty()) item { Text(ping, style = MaterialTheme.typography.bodySmall) }
        if (storage.isNotEmpty()) item { Text(storage, style = MaterialTheme.typography.bodySmall) }

        item {
            Text(
                "Nori für Android 0.1.0 — geteilter Swift-Kern, Compose-Oberfläche.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Zeitstempel des Kerns sind Sekunden seit 1970. */
fun formatDay(epochSeconds: Double): String =
    SimpleDateFormat("EEEE, d. MMMM", Locale.GERMAN).format(Date((epochSeconds * 1000).toLong()))
