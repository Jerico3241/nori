package de.nori.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.nori.ui.theme.NoriColors

/** Überschrift über einem Abschnitt der Startseite. */
@Composable
fun SectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    action: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            color = NoriColors.fg,
            modifier = Modifier.weight(1f),
        )
        action?.invoke()
    }
}

/**
 * Der Fortschrittsbalken auf einer Kachel.
 *
 * Er sitzt **im** Cover und nicht darunter: eine zusätzliche Zeile unter der
 * Kachel würde die Karte höher machen als die Nachbarn, sobald ein Titel
 * angefangen ist — das Raster verzöge sich beim Scrollen.
 */
@Composable
fun CoverProgress(ratio: Float, modifier: Modifier = Modifier) {
    if (ratio <= 0f) return
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(3.dp)
            .background(Color.Black.copy(alpha = 0.55f)),
    ) {
        Box(
            Modifier
                .fillMaxWidth(ratio.coerceIn(0f, 1f))
                .fillMaxSize()
                .background(NoriColors.progress),
        )
    }
}

/** Kapsel-Etikett, etwa für Sprache oder Hoster. */
@Composable
fun NoriChip(
    text: String,
    selected: Boolean = false,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
) {
    Box(
        modifier = modifier
            .clip(CircleShape)
            .background(if (selected) NoriColors.accent else NoriColors.elevated)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 12.dp, vertical = 7.dp),
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium,
            color = if (selected) NoriColors.bg else NoriColors.fg,
            maxLines = 1,
        )
    }
}

/** Ladezustand mit Text — nie ein nackter Kringel ohne Erklärung. */
@Composable
fun LoadingState(text: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator(color = NoriColors.accent, strokeWidth = 2.dp)
        Spacer(Modifier.height(14.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium, color = NoriColors.muted)
    }
}

/**
 * Fehlerzustand.
 *
 * Die Meldung kommt aus dem Kern und ist bereits deutsch und konkret („Katalog
 * unvollständig, nur 3 Einträge gelesen"). Sie wird deshalb gezeigt und nicht
 * durch ein allgemeines „Etwas ist schiefgelaufen" ersetzt.
 */
@Composable
fun ErrorState(
    message: String,
    modifier: Modifier = Modifier,
    onRetry: (() -> Unit)? = null,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = NoriColors.muted,
            textAlign = TextAlign.Center,
        )
        if (onRetry != null) {
            Spacer(Modifier.height(12.dp))
            TextButton(onClick = onRetry) {
                Icon(Icons.Rounded.Refresh, contentDescription = null, tint = NoriColors.accent)
                Spacer(Modifier.width(8.dp))
                Text("Erneut versuchen", color = NoriColors.accent)
            }
        }
    }
}

@Composable
fun EmptyState(title: String, hint: String? = null, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, color = NoriColors.fg)
        if (hint != null) {
            Spacer(Modifier.height(6.dp))
            Text(
                hint,
                style = MaterialTheme.typography.bodySmall,
                color = NoriColors.muted,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/**
 * Platzhalterkachel während des Ladens.
 *
 * Sie hat dieselben Maße wie eine echte Karte. Das ist der Punkt: springt das
 * Raster beim Eintreffen der Daten um, wirkt die Liste unruhig, egal wie
 * schön die Animation ist.
 */
@Composable
fun SkeletonCard(modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "skeleton")
    val alpha by transition.animateFloat(
        initialValue = 0.30f,
        targetValue = 0.60f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "alpha",
    )
    Column(modifier = modifier) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(2f / 3f)
                .clip(RoundedCornerShape(14.dp))
                .background(NoriColors.elevated.copy(alpha = alpha)),
        )
        Spacer(Modifier.height(7.dp))
        Box(
            Modifier
                .fillMaxWidth(0.8f)
                .height(11.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(NoriColors.elevated.copy(alpha = alpha)),
        )
    }
}

@Composable
fun SkeletonRow(count: Int = 5, itemWidth: androidx.compose.ui.unit.Dp = 132.dp) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.padding(horizontal = 16.dp),
    ) {
        repeat(count) { SkeletonCard(Modifier.width(itemWidth)) }
    }
}

/** Einheitlicher Innenabstand für scrollende Inhalte. */
val ContentPadding = PaddingValues(horizontal = 16.dp)

@Composable
fun OneLine(text: String, modifier: Modifier = Modifier, color: Color = NoriColors.muted) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = color,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier,
    )
}

/** Rundes Symbolfeld für die Player-Steuerung. */
@Composable
fun RoundIconButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: androidx.compose.ui.unit.Dp = 48.dp,
    background: Color = Color.White.copy(alpha = 0.12f),
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(background)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        content()
    }
}
