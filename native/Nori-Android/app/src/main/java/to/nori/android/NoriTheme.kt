package to.nori.android

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage

/**
 * Material You, aber immer dunkel.
 *
 * Dieselbe Entscheidung wie in `docs/android.md`: der Inhalt sind Cover, und
 * ein heller Grund kämpft dagegen an. Die Farbtöne kommen ab Android 12 aus
 * dem Hintergrundbild, das Schema bleibt dunkel — anders als bei Material You
 * üblich, wo auch hell/dunkel vom System kommt.
 *
 * Unterhalb von Android 12 trägt `noriDark`, von Hand aus den Werten in
 * `Theme.swift` abgeleitet, damit die App auf älteren Geräten aussieht wie
 * ihre Geschwister und nicht wie eine Vorlage.
 */
private val noriDark = darkColorScheme(
    primary = Color(0xFF7BD88F),
    onPrimary = Color(0xFF06210F),
    secondary = Color(0xFF9AA6B2),
    background = Color(0xFF0E0F12),
    onBackground = Color(0xFFECEDEF),
    surface = Color(0xFF16181D),
    onSurface = Color(0xFFECEDEF),
    surfaceVariant = Color(0xFF22262E),
    onSurfaceVariant = Color(0xFF9AA6B2),
    error = Color(0xFFFF8A80),
)

@Composable
fun NoriTheme(useSystemColors: Boolean = true, content: @Composable () -> Unit) {
    val scheme = if (useSystemColors && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        dynamicDarkColorScheme(LocalContext.current)
    } else {
        noriDark
    }
    MaterialTheme(colorScheme = scheme, content = content)
}

/**
 * Eine Cover-Kachel mit Buchstaben-Rückfall.
 *
 * Der Rückfall ist nicht Kosmetik: Cover-Adressen stehen nur auf der
 * Detailseite, die Katalogseiten sind reine Titellisten. Eine Kachel ohne
 * Bild ist deshalb der Normalfall und darf nicht wie ein Fehler aussehen.
 */
@Composable
fun PosterTile(
    title: String,
    coverUrl: String?,
    modifier: Modifier = Modifier,
    progress: Float = 0f,
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
    ) {
        if (coverUrl != null) {
            AsyncImage(
                model = coverUrl,
                contentDescription = title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Text(
                text = title.take(2).uppercase(),
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.Center),
            )
        }
        if (progress > 0f) {
            // Schmaler Streifen am unteren Rand statt eines Balkens darunter:
            // er nimmt keinen Platz aus dem Raster und liest sich trotzdem.
            Box(
                Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .height(3.dp)
                    .background(MaterialTheme.colorScheme.surface)
            )
            Box(
                Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth(progress)
                    .height(3.dp)
                    .background(MaterialTheme.colorScheme.primary)
            )
        }
    }
}

/** Kachel mit Titel darunter — der Baustein für alle Raster. */
@Composable
fun PosterCell(
    title: String,
    subtitle: String? = null,
    coverUrl: String?,
    progress: Float = 0f,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    ) {
        PosterTile(
            title = title,
            coverUrl = coverUrl,
            progress = progress,
            modifier = Modifier
                .fillMaxWidth()
                .height(210.dp),
        )
        Text(
            text = title,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 6.dp),
        )
        if (!subtitle.isNullOrBlank()) {
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** Überschrift einer Abteilung, optional mit Zusatz rechts. */
@Composable
fun SectionHeader(title: String, trailing: String? = null) {
    Box(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge)
        if (trailing != null) {
            Text(
                trailing,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.CenterEnd),
            )
        }
    }
}

/** Leerer oder fehlgeschlagener Zustand — einheitlich statt je Ansicht neu. */
@Composable
fun StatusBox(message: String, isError: Boolean = false) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Text(
            message,
            textAlign = TextAlign.Center,
            color = if (isError) MaterialTheme.colorScheme.error
            else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
