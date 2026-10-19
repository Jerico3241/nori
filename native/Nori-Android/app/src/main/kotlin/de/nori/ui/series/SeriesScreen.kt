package de.nori.ui.series

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.BookmarkBorder
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import de.nori.core.Episode
import de.nori.core.EpisodeInfo
import de.nori.core.SeriesDetail
import de.nori.core.WatchProgress
import de.nori.ui.components.ErrorState
import de.nori.ui.components.LoadingState
import de.nori.ui.components.NoriBackdrop
import de.nori.ui.components.NoriChip
import de.nori.ui.components.NoriCover
import de.nori.ui.components.OneLine
import de.nori.ui.components.RoundIconButton
import de.nori.ui.theme.NoriColors

/**
 * Die Detailseite.
 *
 * Auf dem Telefon steht das Cover über der Beschreibung, auf einem Tablet
 * daneben — das ist der einzige Unterschied, alles andere ist gleich.
 */
@Composable
fun SeriesScreen(
    viewModel: SeriesViewModel,
    wide: Boolean,
    onBack: () -> Unit,
    onPlay: (Episode) -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val snapshot by viewModel.snapshot.collectAsStateWithLifecycle()

    when (val current = state) {
        SeriesUiState.Loading -> Box(Modifier.fillMaxSize()) {
            LoadingState("Serie wird geladen")
            BackButton(onBack, Modifier.padding(12.dp))
        }

        is SeriesUiState.Error -> Box(Modifier.fillMaxSize()) {
            ErrorState(current.message, onRetry = viewModel::reload)
            BackButton(onBack, Modifier.padding(12.dp))
        }

        is SeriesUiState.Ready -> {
            val detail = current.detail
            val favorite = snapshot.isFavorite(detail.slug)

            Box(Modifier.fillMaxSize()) {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 32.dp),
                ) {
                    item(key = "header") {
                        Header(
                            detail = detail,
                            state = current,
                            wide = wide,
                            favorite = favorite,
                            onToggleFavorite = viewModel::toggleFavorite,
                            onPlay = { number ->
                                viewModel.episodeFor(number)?.let(onPlay)
                            },
                        )
                    }

                    if (detail.seasons.size > 1) {
                        item(key = "seasons") {
                            LazyRow(
                                contentPadding = PaddingValues(horizontal = 16.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                modifier = Modifier.padding(top = 6.dp, bottom = 10.dp),
                            ) {
                                items(detail.seasons, key = { it.id }) { season ->
                                    NoriChip(
                                        text = season.label,
                                        selected = season.id == detail.activeSeason,
                                        onClick = { viewModel.selectSeason(season.id) },
                                    )
                                }
                            }
                        }
                    }

                    item(key = "stats") {
                        current.stats?.let { stats ->
                            if (stats.total > 0) {
                                Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                                    OneLine("${stats.watched} von ${stats.total} gesehen · ${stats.percent} %")
                                    Spacer(Modifier.height(6.dp))
                                    LinearProgressIndicator(
                                        progress = { stats.percent / 100f },
                                        color = NoriColors.progress,
                                        trackColor = NoriColors.elevated,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .height(3.dp)
                                            .clip(RoundedCornerShape(2.dp)),
                                    )
                                }
                            }
                        }
                    }

                    items(detail.episodes, key = { it.key }) { episode ->
                        EpisodeRow(
                            episode = episode,
                            info = current.episodeInfo[episode.number],
                            progress = snapshot.progressFor(episode.path, current.provider),
                            onClick = { onPlay(episode) },
                        )
                    }

                    if (detail.episodes.isEmpty()) {
                        item(key = "no-episodes") {
                            Text(
                                "Für diese Staffel sind keine Folgen eingetragen.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = NoriColors.muted,
                                modifier = Modifier.padding(16.dp),
                            )
                        }
                    }
                }

                BackButton(onBack, Modifier.padding(12.dp))
            }
        }
    }
}

@Composable
private fun BackButton(onBack: () -> Unit, modifier: Modifier = Modifier) {
    RoundIconButton(
        onClick = onBack,
        modifier = modifier,
        size = 40.dp,
        background = Color.Black.copy(alpha = 0.45f),
    ) {
        Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Zurück", tint = NoriColors.fg)
    }
}

@Composable
private fun Header(
    detail: SeriesDetail,
    state: SeriesUiState.Ready,
    wide: Boolean,
    favorite: Boolean,
    onToggleFavorite: () -> Unit,
    onPlay: (episodeNumber: Int) -> Unit,
) {
    Column {
        Box(Modifier.fillMaxWidth().height(if (wide) 300.dp else 230.dp)) {
            NoriBackdrop(
                url = state.cover?.backdrop ?: state.cover?.poster,
                provider = state.provider,
                contentDescription = detail.title,
                modifier = Modifier.fillMaxSize(),
            )
            Box(
                Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            0.3f to Color.Transparent,
                            1f to NoriColors.bg,
                        )
                    )
            )
        }

        val info = @Composable {
            Column {
                Text(
                    text = detail.title,
                    style = MaterialTheme.typography.headlineSmall,
                    color = NoriColors.fg,
                )
                val meta = buildList {
                    detail.years?.let { add(it) }
                    detail.fsk?.takeIf { it.isNotBlank() }?.let { add("FSK $it") }
                    detail.imdb?.takeIf { it.isNotBlank() }?.let { add("IMDb $it") }
                    state.cover?.rating?.let { add("TMDB %.1f".format(it)) }
                }
                if (meta.isNotEmpty()) {
                    Spacer(Modifier.height(4.dp))
                    OneLine(meta.joinToString(" · "))
                }
                if (detail.genres.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(detail.genres.take(6), key = { it }) { NoriChip(it) }
                    }
                }

                val description = detail.description.ifBlank { state.cover?.overview.orEmpty() }
                if (description.isNotBlank()) {
                    Spacer(Modifier.height(12.dp))
                    ExpandableText(description)
                }

                Spacer(Modifier.height(14.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val next = state.next
                    Button(
                        onClick = { next?.let { onPlay(it.episode) } },
                        enabled = next != null,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = NoriColors.accent,
                            contentColor = NoriColors.bg,
                        ),
                        shape = RoundedCornerShape(12.dp),
                    ) {
                        Icon(Icons.Rounded.PlayArrow, contentDescription = null)
                        Spacer(Modifier.width(6.dp))
                        Text(playLabel(next?.kind, next?.episode))
                    }

                    RoundIconButton(
                        onClick = onToggleFavorite,
                        size = 44.dp,
                        background = NoriColors.elevated,
                    ) {
                        Icon(
                            imageVector = if (favorite) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder,
                            contentDescription = if (favorite) "Aus Merkliste entfernen" else "Merken",
                            tint = if (favorite) NoriColors.accent else NoriColors.fg,
                        )
                    }
                }
            }
        }

        if (wide) {
            Row(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                NoriCover(
                    title = detail.title,
                    slug = detail.slug,
                    provider = state.provider,
                    coverUrl = state.cover?.poster,
                    modifier = Modifier.width(180.dp),
                )
                Box(Modifier.weight(1f)) { info() }
            }
        } else {
            Column(Modifier.padding(horizontal = 16.dp)) { info() }
        }
    }
}

@Composable
private fun ExpandableText(text: String) {
    var expanded by remember(text) { mutableStateOf(false) }
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = NoriColors.muted,
        maxLines = if (expanded) Int.MAX_VALUE else 4,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.clickable { expanded = !expanded },
    )
}

private fun playLabel(kind: String?, episode: Int?): String = when (kind) {
    "resume" -> "Fortsetzen · F$episode"
    "next" -> "Weiter · F$episode"
    else -> "Abspielen"
}

/**
 * Eine Folge.
 *
 * Bild links, Titel und Beschreibung rechts, Fortschritt als Balken unter dem
 * Bild. Das Bild ist auf 16:9 festgelegt und wird darin beschnitten — TMDB
 * liefert nicht für jede Folge dieselben Maße, und eine Zeile, die je nach
 * Bild anders hoch ist, macht die Liste unruhig.
 */
@Composable
private fun EpisodeRow(
    episode: Episode,
    info: EpisodeInfo?,
    progress: WatchProgress?,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Box(Modifier.width(124.dp)) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(70.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(NoriColors.elevated),
            ) {
                info?.still?.let { still ->
                    AsyncImage(
                        model = still,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                if (progress?.complete == true) {
                    Box(
                        Modifier
                            .align(Alignment.TopEnd)
                            .padding(4.dp)
                            .size(20.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color.Black.copy(alpha = 0.6f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.Rounded.Check,
                            contentDescription = "Gesehen",
                            tint = NoriColors.progress,
                            modifier = Modifier.size(14.dp),
                        )
                    }
                }
            }
            if (progress != null && progress.ratio > 0f) {
                Box(
                    Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .height(3.dp)
                        .background(Color.Black.copy(alpha = 0.5f)),
                ) {
                    Box(
                        Modifier
                            .fillMaxWidth(progress.ratio)
                            .height(3.dp)
                            .background(NoriColors.progress),
                    )
                }
            }
        }

        Spacer(Modifier.width(12.dp))

        Column(Modifier.weight(1f)) {
            Text(
                text = "${episode.number}. ${info?.title ?: episode.displayTitle}",
                style = MaterialTheme.typography.titleSmall,
                color = NoriColors.fg,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            val text = info?.overview ?: episode.englishTitle.takeIf { it.isNotBlank() }
            if (!text.isNullOrBlank()) {
                Spacer(Modifier.height(3.dp))
                Text(
                    text = text,
                    style = MaterialTheme.typography.bodySmall,
                    color = NoriColors.muted,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (episode.languages.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                OneLine(episode.languages.joinToString(" · "))
            }
        }
    }
}
