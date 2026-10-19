package de.nori.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.nori.core.CatalogProvider
import de.nori.ui.theme.NoriColors

/**
 * Die Grundkachel: Cover, Titel, eine Zeile darunter.
 *
 * Die Höhe hängt **nicht** vom Cover ab — [NoriCover] hält 2:3 ein, der Titel
 * ist auf zwei Zeilen begrenzt, die Unterzeile auf eine. Dadurch stehen alle
 * Karten einer Zeile gleich hoch, auch wenn ein Titel lang und ein Cover
 * quadratisch ist.
 */
@Composable
fun PosterCard(
    title: String,
    slug: String,
    provider: CatalogProvider,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    coverUrl: String? = null,
    progress: Float = 0f,
    onClick: () -> Unit,
) {
    Column(
        modifier = modifier.clickable(onClick = onClick),
    ) {
        Box {
            NoriCover(
                title = title,
                slug = slug,
                provider = provider,
                coverUrl = coverUrl,
                modifier = Modifier.fillMaxWidth(),
            )
            CoverProgress(
                ratio = progress,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
        Spacer(Modifier.height(7.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = NoriColors.fg,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        if (!subtitle.isNullOrBlank()) {
            Spacer(Modifier.height(2.dp))
            OneLine(subtitle)
        }
    }
}

/** Zeilenform derselben Kachel — für die Listenansicht und die Suche. */
@Composable
fun PosterRow(
    title: String,
    slug: String,
    provider: CatalogProvider,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    trailing: (@Composable () -> Unit)? = null,
    progress: Float = 0f,
    onClick: () -> Unit,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.width(48.dp)) {
            NoriCover(
                title = title,
                slug = slug,
                provider = provider,
                compact = true,
                modifier = Modifier.fillMaxWidth(),
            )
            CoverProgress(
                ratio = progress,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = NoriColors.fg,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (!subtitle.isNullOrBlank()) {
                Spacer(Modifier.height(2.dp))
                OneLine(subtitle)
            }
        }
        if (trailing != null) {
            Spacer(Modifier.width(8.dp))
            Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) { trailing() }
        }
    }
}
