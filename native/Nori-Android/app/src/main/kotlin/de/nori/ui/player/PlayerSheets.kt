package de.nori.ui.player

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.nori.core.HosterOption
import de.nori.player.NoriPlaybackState
import de.nori.player.NoriTrack
import de.nori.player.NoriTrackType
import de.nori.ui.theme.NoriColors

/** Welche Auswahl gerade offen ist. */
enum class PlayerSheet(val title: String) {
    Hoster("Hoster"),
    Language("Sprache"),
    Audio("Tonspur"),
    Subtitles("Untertitel"),
    Quality("Qualität"),
    Speed("Geschwindigkeit"),
}

/**
 * Die Auswahl zu einem der Knöpfe in der Player-Steuerung.
 *
 * Alles in derselben Bauform: eine Liste mit Häkchen. Der Unterschied zwischen
 * „Hoster wechseln" und „Untertitel wählen" ist für den Nutzer keiner — beides
 * ist eine Liste, aus der er eins nimmt.
 */
@Composable
fun PlayerOptionsSheet(
    sheet: PlayerSheet,
    state: PlayerUiState.Ready,
    playback: NoriPlaybackState,
    onDismiss: () -> Unit,
    onHoster: (HosterOption) -> Unit,
    onLanguage: (String) -> Unit,
    onTrack: (NoriTrack, NoriTrackType) -> Unit,
    onTrackAuto: (NoriTrackType) -> Unit,
    onSpeed: (Float) -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = NoriColors.surface,
        contentColor = NoriColors.fg,
    ) {
        Column(Modifier.padding(bottom = 24.dp)) {
            Text(
                text = sheet.title,
                style = MaterialTheme.typography.titleMedium,
                color = NoriColors.fg,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
            )

            LazyColumn(Modifier.heightIn(max = 420.dp)) {
                when (sheet) {
                    PlayerSheet.Hoster -> items(
                        state.hosters,
                        key = { "${it.name}|${it.langKey}|${it.redirectPath}" },
                    ) { option ->
                        OptionRow(
                            label = option.name,
                            hint = option.lang,
                            selected = option.name.equals(state.source.hoster, ignoreCase = true) &&
                                option.lang.equals(state.source.lang, ignoreCase = true),
                            onClick = { onHoster(option) },
                        )
                    }

                    PlayerSheet.Language -> items(state.languages, key = { it }) { lang ->
                        OptionRow(
                            label = lang,
                            hint = state.hosters.count { it.lang == lang }.let { "$it Hoster" },
                            selected = lang.equals(state.source.lang, ignoreCase = true),
                            onClick = { onLanguage(lang) },
                        )
                    }

                    PlayerSheet.Audio -> trackSection(
                        tracks = playback.audioTracks,
                        type = NoriTrackType.Audio,
                        autoLabel = "Automatisch",
                        emptyHint = "Diese Quelle hat nur eine Tonspur.",
                        onTrack = onTrack,
                        onAuto = onTrackAuto,
                    )

                    PlayerSheet.Subtitles -> trackSection(
                        tracks = playback.textTracks,
                        type = NoriTrackType.Text,
                        autoLabel = "Aus",
                        emptyHint = "Diese Quelle liefert keine Untertitel.",
                        onTrack = onTrack,
                        onAuto = onTrackAuto,
                    )

                    PlayerSheet.Quality -> trackSection(
                        tracks = playback.videoTracks,
                        type = NoriTrackType.Video,
                        autoLabel = "Automatisch",
                        emptyHint = "Diese Quelle bietet nur eine Qualität.",
                        onTrack = onTrack,
                        onAuto = onTrackAuto,
                    )

                    PlayerSheet.Speed -> items(SPEEDS, key = { it }) { speed ->
                        OptionRow(
                            label = if (speed == 1f) "Normal" else "${speed}×",
                            hint = null,
                            selected = kotlin.math.abs(playback.speed - speed) < 0.01f,
                            onClick = { onSpeed(speed) },
                        )
                    }
                }
            }
        }
    }
}

/**
 * Ein Kanalabschnitt: „Automatisch"/„Aus" zuerst, dann die Kanäle.
 *
 * Der Hinweis bei leerer Liste ist wichtig. Bei HLS kommen Ton- und
 * Untertitelspuren erst mit der Wiedergabeliste an; eine leere Auswahl ohne
 * Erklärung sähe aus wie ein Fehler.
 */
private fun androidx.compose.foundation.lazy.LazyListScope.trackSection(
    tracks: List<NoriTrack>,
    type: NoriTrackType,
    autoLabel: String,
    emptyHint: String,
    onTrack: (NoriTrack, NoriTrackType) -> Unit,
    onAuto: (NoriTrackType) -> Unit,
) {
    item(key = "auto-${type.name}") {
        OptionRow(
            label = autoLabel,
            hint = null,
            selected = tracks.none { it.selected },
            onClick = { onAuto(type) },
        )
    }
    if (tracks.isEmpty()) {
        item(key = "empty-${type.name}") {
            Text(
                text = emptyHint,
                style = MaterialTheme.typography.bodySmall,
                color = NoriColors.muted,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
            )
        }
        return
    }
    items(tracks, key = { "${type.name}|${it.groupIndex}|${it.trackIndex}" }) { track ->
        OptionRow(
            label = track.label,
            hint = null,
            selected = track.selected,
            onClick = { onTrack(track, type) },
        )
    }
}

@Composable
private fun OptionRow(
    label: String,
    hint: String?,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                text = label,
                style = MaterialTheme.typography.bodyLarge,
                color = if (selected) NoriColors.accent else NoriColors.fg,
            )
            if (hint != null) {
                Text(
                    text = hint,
                    style = MaterialTheme.typography.bodySmall,
                    color = NoriColors.muted,
                )
            }
        }
        if (selected) {
            Icon(
                Icons.Rounded.Check,
                contentDescription = null,
                tint = NoriColors.accent,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

/** Dieselben Stufen wie im Contract. */
private val SPEEDS = listOf(0.75f, 1.0f, 1.25f, 1.5f, 2.0f)
