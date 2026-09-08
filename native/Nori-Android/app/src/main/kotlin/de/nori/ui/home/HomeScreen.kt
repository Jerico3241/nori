package de.nori.ui.home

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
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import de.nori.core.AiringEntry
import de.nori.core.CatalogItem
import de.nori.core.CatalogProvider
import de.nori.core.LibraryScope
import de.nori.core.WatchProgress
import de.nori.core.providerFromPath
import de.nori.data.Nori
import de.nori.ui.components.ContentPadding
import de.nori.ui.components.CoverProgress
import de.nori.ui.components.ErrorState
import de.nori.ui.components.NoriBackdrop
import de.nori.ui.components.NoriChip
import de.nori.ui.components.NoriCover
import de.nori.ui.components.OneLine
import de.nori.ui.components.PosterCard
import de.nori.ui.components.SectionHeader
import de.nori.ui.components.SkeletonRow
import de.nori.ui.theme.NoriColors

/**
 * Die Startseite.
 *
 * Aufbau wie auf iOS: Kopfbereich, Weiterschauen, Beliebtes, Genre-Reihen —
 * dazu die neuen Folgen aus dem Kalender. Auf breiten Geräten sind die
 * Kacheln größer und der Kopfbereich flacher; das entscheidet [wide].
 */
@Composable
fun HomeScreen(
    viewModel: HomeViewModel,
    wide: Boolean,
    onOpenSeries: (slug: String, title: String, provider: CatalogProvider) -> Unit,
    onResume: (WatchProgress) -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val watching by viewModel.continueWatching.collectAsStateWithLifecycle()
    val scope by viewModel.scope.collectAsStateWithLifecycle()

    val cardWidth = if (wide) 168.dp else 132.dp

    when (val current = state) {
        is HomeUiState.Error -> ErrorState(current.message, onRetry = viewModel::refresh)

        HomeUiState.Loading -> Column(Modifier.fillMaxSize()) {
            Spacer(Modifier.height(24.dp))
            ScopeBar(scope, viewModel::setScope)
            Spacer(Modifier.height(16.dp))
            SkeletonRow(itemWidth = cardWidth)
            Spacer(Modifier.height(24.dp))
            SkeletonRow(itemWidth = cardWidth)
        }

        is HomeUiState.Ready -> LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            if (current.hero.isNotEmpty()) {
                item(key = "hero") {
                    Hero(current.hero, wide, onOpenSeries)
                }
            }

            item(key = "scope") { ScopeBar(scope, viewModel::setScope) }

            current.warning?.let { warning ->
                item(key = "warning") {
                    Text(
                        text = warning,
                        style = MaterialTheme.typography.bodySmall,
                        color = NoriColors.danger,
                        modifier = Modifier.padding(ContentPadding),
                    )
                }
            }

            if (watching.isNotEmpty()) {
                item(key = "continue") {
                    Column {
                        SectionHeader("Weiterschauen")
                        LazyRow(
                            contentPadding = ContentPadding,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(watching, key = { "${it.provider?.wire}|${it.episodePath}" }) { item ->
                                ContinueCard(
                                    item = item,
                                    width = cardWidth,
                                    onClick = { onResume(item) },
                                )
                            }
                        }
                    }
                }
            }

            if (current.popular.isNotEmpty()) {
                item(key = "popular") {
                    CatalogRow(current.popularTitle, current.popular, cardWidth, onOpenSeries)
                }
            }

            if (current.freshEpisodes.isNotEmpty()) {
                item(key = "fresh") {
                    Column {
                        SectionHeader("Neue Folgen")
                        LazyRow(
                            contentPadding = ContentPadding,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(
                                current.freshEpisodes,
                                key = { "${it.provider?.wire}|${it.slug}|${it.season}|${it.episode}" },
                            ) { entry ->
                                AiringCard(entry, cardWidth, onOpenSeries)
                            }
                        }
                    }
                }
            }

            items(current.rows, key = { it.title }) { row ->
                CatalogRow(row.title, row.items, cardWidth, onOpenSeries)
            }
        }
    }
}

@Composable
private fun ScopeBar(current: LibraryScope, onSelect: (LibraryScope) -> Unit) {
    LazyRow(
        contentPadding = ContentPadding,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(LibraryScope.entries.toList(), key = { it.wire }) { scope ->
            NoriChip(
                text = scope.label,
                selected = scope == current,
                onClick = { onSelect(scope) },
            )
        }
    }
}

@Composable
private fun CatalogRow(
    title: String,
    items: List<CatalogItem>,
    cardWidth: androidx.compose.ui.unit.Dp,
    onOpenSeries: (String, String, CatalogProvider) -> Unit,
) {
    Column {
        SectionHeader(title)
        LazyRow(
            contentPadding = ContentPadding,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Stabiler Schlüssel: sonst zeichnet Compose beim Nachladen von
            // Covern die ganze Reihe neu.
            items(items, key = { it.key }) { item ->
                val provider = item.provider ?: CatalogProvider.Aniworld
                PosterCard(
                    title = item.title,
                    slug = item.slug,
                    provider = provider,
                    subtitle = item.genres.firstOrNull(),
                    modifier = Modifier.width(cardWidth),
                    onClick = { onOpenSeries(item.slug, item.title, provider) },
                )
            }
        }
    }
}

/**
 * Kopfbereich mit Wischen.
 *
 * Feste Höhe statt Seitenverhältnis: ein 2:3-Poster wäre auf dem Telefon
 * höher als der halbe Bildschirm, und von der Startseite bliebe darunter
 * nichts übrig.
 */
@Composable
private fun Hero(
    items: List<HeroItem>,
    wide: Boolean,
    onOpenSeries: (String, String, CatalogProvider) -> Unit,
) {
    val pagerState = rememberPagerState(pageCount = { items.size })
    val height = if (wide) 420.dp else 480.dp

    Box(Modifier.fillMaxWidth().height(height)) {
        HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
            HeroSlide(items[page], onOpenSeries)
        }

        Row(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            repeat(items.size) { index ->
                Box(
                    Modifier
                        .size(if (index == pagerState.currentPage) 7.dp else 5.dp)
                        .clip(CircleShape)
                        .background(
                            if (index == pagerState.currentPage) NoriColors.fg
                            else NoriColors.fg.copy(alpha = 0.35f)
                        )
                )
            }
        }
    }
}

@Composable
private fun HeroSlide(
    item: HeroItem,
    onOpenSeries: (String, String, CatalogProvider) -> Unit,
) {
    var backdrop by remember(item.key) { mutableStateOf<String?>(null) }
    var poster by remember(item.key) { mutableStateOf<String?>(null) }

    LaunchedEffect(item.key) {
        val details = Nori.covers.resolve(item.slug, item.title, item.provider)
        backdrop = details?.backdrop
        poster = details?.poster
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .clickable { onOpenSeries(item.slug, item.title, item.provider) },
    ) {
        // Breitbild bevorzugt, Poster als Rückfall — ein 2:3-Poster füllt die
        // Fläche zwar, wird dabei aber stark beschnitten.
        NoriBackdrop(
            url = backdrop ?: poster,
            provider = item.provider,
            contentDescription = item.title,
            modifier = Modifier.fillMaxSize(),
        )

        // Verlauf nach unten, damit die Schrift auf jedem Bild lesbar bleibt.
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0.35f to Color.Transparent,
                        1f to NoriColors.bg,
                    )
                )
        )

        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(start = 16.dp, end = 16.dp, bottom = 34.dp),
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.headlineMedium,
                color = NoriColors.fg,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (item.genres.isNotEmpty()) {
                Spacer(Modifier.height(6.dp))
                OneLine(item.genres.take(3).joinToString(" · "))
            }
        }
    }
}

/** „Weiterschauen": Cover, Fortschritt, Staffel und Folge. */
@Composable
private fun ContinueCard(
    item: WatchProgress,
    width: androidx.compose.ui.unit.Dp,
    onClick: () -> Unit,
) {
    val provider = item.provider ?: providerFromPath(item.episodePath)
    Column(
        modifier = Modifier
            .width(width)
            .clickable(onClick = onClick),
    ) {
        Box {
            NoriCover(
                title = item.title,
                slug = item.slug,
                provider = provider,
                modifier = Modifier.fillMaxWidth(),
            )
            CoverProgress(item.ratio, Modifier.align(Alignment.BottomCenter))
        }
        Spacer(Modifier.height(7.dp))
        Text(
            text = item.title,
            style = MaterialTheme.typography.titleSmall,
            color = NoriColors.fg,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(2.dp))
        OneLine(seasonEpisodeLabel(item))
    }
}

@Composable
private fun AiringCard(
    entry: AiringEntry,
    width: androidx.compose.ui.unit.Dp,
    onOpenSeries: (String, String, CatalogProvider) -> Unit,
) {
    val provider = entry.provider ?: CatalogProvider.Aniworld
    PosterCard(
        title = entry.title,
        slug = entry.slug,
        provider = provider,
        // Der Kalender liefert bei AniWorld eine Coveradresse mit; dann muss
        // sie nicht erst gesucht werden.
        coverUrl = entry.coverPath?.let { path ->
            if (path.startsWith("http")) path else provider.origin + path
        },
        subtitle = "S${entry.season} · F${entry.episode}",
        modifier = Modifier.width(width),
        onClick = { onOpenSeries(entry.slug, entry.title, provider) },
    )
}

internal fun seasonEpisodeLabel(item: WatchProgress): String {
    val season = if (item.season == "filme") "Filme" else "S${item.season}"
    return "$season · F${item.episode} · ${formatClock(item.positionSec)}"
}

/** Wie `formatClock` im Kern: h:mm:ss ab einer Stunde, sonst m:ss. */
internal fun formatClock(seconds: Double): String {
    val total = seconds.coerceAtLeast(0.0).toInt()
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val rest = total % 60
    return if (hours > 0) {
        "%d:%02d:%02d".format(hours, minutes, rest)
    } else {
        "%d:%02d".format(minutes, rest)
    }
}
