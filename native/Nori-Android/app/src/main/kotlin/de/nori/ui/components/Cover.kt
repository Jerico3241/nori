package de.nori.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import coil3.network.NetworkHeaders
import coil3.network.httpHeaders
import coil3.request.ImageRequest
import coil3.request.crossfade
import de.nori.core.CatalogProvider
import de.nori.core.NORI_USER_AGENT
import de.nori.data.Nori
import de.nori.ui.theme.NoriColors
import kotlinx.coroutines.delay

/**
 * Ein Cover im Verhältnis 2:3.
 *
 * Drei Dinge, die hier schiefgehen können und deshalb festgelegt sind:
 *
 * **Kopfzeilen.** Beide Quellen beantworten eine Bildanfrage ohne `Referer`
 * und `User-Agent` anders als im Browser. Coil bekommt sie deshalb mit; ein
 * schlichtes `AsyncImage(url)` liefert bei AniWorld eine leere Kachel.
 *
 * **Seitenverhältnis.** Der Rahmen setzt 2:3 und `ContentScale.Crop`
 * schneidet innerhalb dieses Rahmens. Die Kachel wächst dadurch **nie** über
 * ihre Zeile hinaus — genau der Fehler, der auf macOS Karten verschoben hat,
 * wenn ein Cover andere Maße hatte als erwartet.
 *
 * **Rückfall.** Kein Bild heißt: der Anfangsbuchstabe auf der erhöhten
 * Fläche, nicht ein leeres Rechteck und kein Dauerskelett.
 */
@Composable
fun NoriCover(
    title: String,
    slug: String,
    provider: CatalogProvider,
    modifier: Modifier = Modifier,
    coverUrl: String? = null,
    compact: Boolean = false,
) {
    val shape = RoundedCornerShape(if (compact) 10.dp else 14.dp)
    var resolved by remember(slug, provider, coverUrl) { mutableStateOf(coverUrl) }

    // Nachschlagen nur, wenn die Adresse nicht schon mitgeliefert wurde.
    LaunchedEffect(slug, provider, coverUrl) {
        if (coverUrl != null) return@LaunchedEffect
        resolved = Nori.covers.cached(slug, provider)?.poster
        if (resolved != null) return@LaunchedEffect

        // Die kurze Pause ist Absicht: beim Durchscrollen wird diese
        // Coroutine vorher abgebrochen und es geht gar keine Anfrage raus.
        // Geladen wird nur, was auch stehen bleibt.
        delay(400)
        resolved = Nori.covers.resolve(slug, title, provider)?.poster
    }

    Box(
        modifier = modifier
            .aspectRatio(2f / 3f)
            .clip(shape)
            .background(NoriColors.elevated),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = title.take(1).uppercase(),
            fontSize = if (compact) 30.sp else 42.sp,
            fontWeight = FontWeight.SemiBold,
            color = NoriColors.fg.copy(alpha = 0.16f),
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(if (compact) 8.dp else 12.dp),
        )

        val url = resolved
        if (url != null) {
            AsyncImage(
                model = noriImageRequest(url, provider),
                contentDescription = title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

/**
 * Ein Breitbild für den Kopfbereich. Dieselben Kopfzeilen, anderes
 * Seitenverhältnis — ein 2:3-Poster ist dafür die falsche Form.
 */
@Composable
fun NoriBackdrop(
    url: String?,
    provider: CatalogProvider,
    modifier: Modifier = Modifier,
    contentDescription: String? = null,
) {
    Box(modifier = modifier.background(NoriColors.elevated)) {
        if (url != null) {
            AsyncImage(
                model = noriImageRequest(url, provider),
                contentDescription = contentDescription,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

@Composable
private fun noriImageRequest(url: String, provider: CatalogProvider): ImageRequest {
    val context = LocalContext.current
    return remember(url, provider) {
        ImageRequest.Builder(context)
            .data(url)
            .crossfade(200)
            .httpHeaders(
                NetworkHeaders.Builder()
                    .set("User-Agent", NORI_USER_AGENT)
                    // Hotlink-Schutz: ohne den Referer antworten beide
                    // Quellen auf eine Bildanfrage anders als im Browser.
                    // TMDB stört er nicht.
                    .set("Referer", provider.imageReferer)
                    .set("Accept", "image/avif,image/webp,image/jpeg,image/png,*/*;q=0.8")
                    .build()
            )
            .build()
    }
}
