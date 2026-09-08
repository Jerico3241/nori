package de.nori.ui.player

import android.view.SurfaceView
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Forward30
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PictureInPictureAlt
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Replay30
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import de.nori.ui.components.NoriChip
import de.nori.ui.components.RoundIconButton
import de.nori.ui.home.formatClock
import de.nori.ui.theme.NoriColors
import kotlinx.coroutines.delay

/**
 * Der Player.
 *
 * Die Steuerung liegt **auf** dem Bild und blendet sich aus. Es gibt bewusst
 * keine dauerhaft sichtbare Hosterleiste: Hoster, Sprache, Ton, Untertitel
 * und Qualität stehen in einer Zeile, die nur erscheint, wenn die Steuerung
 * sichtbar ist. Ein Video ist der Inhalt; alles andere ist Werkzeug.
 */
@Composable
fun PlayerScreen(
    viewModel: PlayerViewModel,
    inPictureInPicture: Boolean,
    onEnterPictureInPicture: () -> Unit,
    onBack: () -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val playback by viewModel.playback.collectAsStateWithLifecycle()
    val countdown by viewModel.countdown.collectAsStateWithLifecycle()
    val message by viewModel.messages.collectAsStateWithLifecycle()

    // Gewöhnliche Variable statt `by`-Delegat: nur so kann Kotlin darauf
    // smart-casten, und der Fehlerzweig unten braucht das.
    val failure = viewModel.error.collectAsStateWithLifecycle().value

    var controlsVisible by remember { mutableStateOf(true) }
    var sheet by remember { mutableStateOf<PlayerSheet?>(null) }
    var scrubbing by remember { mutableStateOf<Float?>(null) }

    // Automatisch ausblenden — aber nicht, während etwas ausgewählt wird oder
    // die Wiedergabe steht. Ein pausierter Player ohne Steuerung wirkt wie
    // ein Absturz.
    LaunchedEffect(controlsVisible, playback.isPlaying, sheet) {
        if (!controlsVisible || !playback.isPlaying || sheet != null) return@LaunchedEffect
        delay(3_500)
        controlsVisible = false
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { controlsVisible = !controlsVisible },
    ) {
        VideoSurface(viewModel, playback.aspectRatio)

        if (inPictureInPicture) {
            // Im kleinen Fenster hat Bedienung nichts zu suchen: Android
            // zeichnet dort eigene Knöpfe, und alles andere verdeckt nur das
            // Bild.
            return@Box
        }

        if (playback.isBuffering && failure == null) {
            CircularProgressIndicator(
                color = Color.White,
                strokeWidth = 2.dp,
                modifier = Modifier.align(Alignment.Center),
            )
        }

        when (val current = state) {
            is PlayerUiState.Loading -> LoadingOverlay(current.note, onBack)

            is PlayerUiState.Error -> ErrorOverlay(
                message = current.message,
                hosters = current.hosters,
                onBack = onBack,
                onRetry = viewModel::retry,
                onHoster = viewModel::switchHoster,
            )

            is PlayerUiState.Ready -> if (failure != null) {
                ErrorOverlay(
                    message = failure.message,
                    hosters = if (failure.sourceDead) current.hosters else emptyList(),
                    onBack = onBack,
                    onRetry = if (failure.retryable) viewModel::retry else null,
                    onHoster = viewModel::switchHoster,
                )
            } else {
                AnimatedVisibility(
                    visible = controlsVisible,
                    enter = fadeIn(),
                    exit = fadeOut(),
                ) {
                    Controls(
                        state = current,
                        positionMs = scrubbing?.let { (it * playback.durationMs).toLong() }
                            ?: playback.positionMs,
                        durationMs = playback.durationMs,
                        bufferedMs = playback.bufferedMs,
                        isPlaying = playback.isPlaying,
                        onBack = onBack,
                        onTogglePlay = viewModel.engine::togglePlayPause,
                        onSeekBy = viewModel.engine::seekBy,
                        onScrub = { scrubbing = it },
                        onScrubEnd = { fraction ->
                            scrubbing = null
                            if (playback.durationMs > 0) {
                                viewModel.engine.seekTo((fraction * playback.durationMs).toLong())
                            }
                        },
                        onPictureInPicture = onEnterPictureInPicture,
                        onNext = viewModel::playNext,
                        onSheet = { sheet = it },
                    )
                }

                countdown?.let { seconds ->
                    NextCountdown(
                        seconds = seconds,
                        onNow = viewModel::playNext,
                        onCancel = viewModel::cancelCountdown,
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .padding(24.dp),
                    )
                }

                sheet?.let { open ->
                    PlayerOptionsSheet(
                        sheet = open,
                        state = current,
                        playback = playback,
                        onDismiss = { sheet = null },
                        onHoster = { viewModel.switchHoster(it); sheet = null },
                        onLanguage = { viewModel.switchLanguage(it); sheet = null },
                        onTrack = { track, type ->
                            viewModel.engine.selectTrack(track, type)
                            sheet = null
                        },
                        onTrackAuto = { type ->
                            viewModel.engine.clearTrackChoice(type)
                            sheet = null
                        },
                        onSpeed = { viewModel.setSpeed(it); sheet = null },
                    )
                }
            }
        }

        message?.let { text ->
            LaunchedEffect(text) {
                delay(4_000)
                viewModel.clearMessage()
            }
            Text(
                text = text,
                style = MaterialTheme.typography.bodySmall,
                color = NoriColors.fg,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 100.dp)
                    .background(Color.Black.copy(alpha = 0.75f))
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            )
        }
    }
}

/**
 * Die Videofläche.
 *
 * Eine schlichte `SurfaceView`, an den Player gehängt. Bewusst nicht Media3s
 * `PlayerView`: die bringt eine eigene Steuerung mit, die hier abgeschaltet
 * werden müsste, und ein Layout, das mit dem hiesigen kollidiert.
 */
@Composable
private fun VideoSurface(viewModel: PlayerViewModel, aspectRatio: Float) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        AndroidView(
            factory = { context ->
                SurfaceView(context).also { viewModel.engine.player.setVideoSurfaceView(it) }
            },
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(aspectRatio),
        )
    }
}

@Composable
private fun LoadingOverlay(note: String, onBack: () -> Unit) {
    Box(Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier.align(Alignment.Center),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp)
            Spacer(Modifier.height(14.dp))
            Text(note, style = MaterialTheme.typography.bodyMedium, color = NoriColors.muted)
        }
        RoundIconButton(
            onClick = onBack,
            modifier = Modifier
                .align(Alignment.TopStart)
                .systemBarsPadding()
                .padding(12.dp),
            size = 40.dp,
            background = Color.White.copy(alpha = 0.12f),
        ) {
            Icon(Icons.Rounded.ArrowBack, contentDescription = "Zurück", tint = Color.White)
        }
    }
}

/**
 * Fehleranzeige mit Ausweg.
 *
 * Ein Wiedergabefehler ist selten endgültig: meist hilft ein anderer Hoster.
 * Deshalb steht die Hosterliste direkt darunter, statt den Nutzer zurück auf
 * die Detailseite zu schicken.
 */
@Composable
private fun ErrorOverlay(
    message: String,
    hosters: List<de.nori.core.HosterOption>,
    onBack: () -> Unit,
    onRetry: (() -> Unit)?,
    onHoster: (de.nori.core.HosterOption) -> Unit,
) {
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.82f)),
    ) {
        RoundIconButton(
            onClick = onBack,
            modifier = Modifier
                .align(Alignment.TopStart)
                .systemBarsPadding()
                .padding(12.dp),
            size = 40.dp,
        ) {
            Icon(Icons.Rounded.ArrowBack, contentDescription = "Zurück", tint = Color.White)
        }

        Column(
            modifier = Modifier
                .align(Alignment.Center)
                .padding(horizontal = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = NoriColors.fg,
                textAlign = TextAlign.Center,
            )
            if (onRetry != null) {
                Spacer(Modifier.height(8.dp))
                TextButton(onClick = onRetry) {
                    Text("Erneut versuchen", color = NoriColors.accent)
                }
            }
            if (hosters.isNotEmpty()) {
                Spacer(Modifier.height(16.dp))
                Text(
                    "Anderer Hoster",
                    style = MaterialTheme.typography.labelMedium,
                    color = NoriColors.muted,
                )
                Spacer(Modifier.height(8.dp))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(hosters, key = { "${it.name}|${it.langKey}|${it.redirectPath}" }) { option ->
                        NoriChip(
                            text = "${option.name} · ${option.lang}",
                            onClick = { onHoster(option) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun Controls(
    state: PlayerUiState.Ready,
    positionMs: Long,
    durationMs: Long,
    bufferedMs: Long,
    isPlaying: Boolean,
    onBack: () -> Unit,
    onTogglePlay: () -> Unit,
    onSeekBy: (Long) -> Unit,
    onScrub: (Float) -> Unit,
    onScrubEnd: (Float) -> Unit,
    onPictureInPicture: () -> Unit,
    onNext: () -> Unit,
    onSheet: (PlayerSheet) -> Unit,
) {
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.45f)),
    ) {
        // Kopfzeile: zurück, Titel, Bild-in-Bild.
        Row(
            modifier = Modifier
                .align(Alignment.TopStart)
                .fillMaxWidth()
                .systemBarsPadding()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            RoundIconButton(onClick = onBack, size = 40.dp) {
                Icon(Icons.Rounded.ArrowBack, contentDescription = "Zurück", tint = Color.White)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    text = state.seriesTitle,
                    style = MaterialTheme.typography.titleMedium,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = seasonLine(state),
                    style = MaterialTheme.typography.bodySmall,
                    color = NoriColors.muted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            RoundIconButton(onClick = onPictureInPicture, size = 40.dp) {
                Icon(
                    Icons.Rounded.PictureInPictureAlt,
                    contentDescription = "Bild-in-Bild",
                    tint = Color.White,
                )
            }
        }

        // Mitte: 30 s zurück, Play/Pause, 30 s vor.
        Row(
            modifier = Modifier.align(Alignment.Center),
            horizontalArrangement = Arrangement.spacedBy(28.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            RoundIconButton(onClick = { onSeekBy(-30_000) }, size = 52.dp) {
                Icon(Icons.Rounded.Replay30, contentDescription = "30 Sekunden zurück", tint = Color.White)
            }
            RoundIconButton(
                onClick = onTogglePlay,
                size = 72.dp,
                background = Color.White.copy(alpha = 0.20f),
            ) {
                Icon(
                    imageVector = if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    contentDescription = if (isPlaying) "Pause" else "Abspielen",
                    tint = Color.White,
                    modifier = Modifier.size(38.dp),
                )
            }
            RoundIconButton(onClick = { onSeekBy(30_000) }, size = 52.dp) {
                Icon(Icons.Rounded.Forward30, contentDescription = "30 Sekunden vor", tint = Color.White)
            }
        }

        // Fuß: Optionen, Fortschritt, nächste Folge.
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .systemBarsPadding()
                .padding(horizontal = 16.dp, vertical = 10.dp),
        ) {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                item {
                    NoriChip(state.source.hoster, onClick = { onSheet(PlayerSheet.Hoster) })
                }
                item {
                    NoriChip(state.source.lang, onClick = { onSheet(PlayerSheet.Language) })
                }
                item {
                    NoriChip("Ton", onClick = { onSheet(PlayerSheet.Audio) })
                }
                item {
                    NoriChip("Untertitel", onClick = { onSheet(PlayerSheet.Subtitles) })
                }
                item {
                    NoriChip("Qualität", onClick = { onSheet(PlayerSheet.Quality) })
                }
                item {
                    NoriChip("Tempo", onClick = { onSheet(PlayerSheet.Speed) })
                }
            }

            Spacer(Modifier.height(6.dp))

            val fraction = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f
            Slider(
                value = fraction.coerceIn(0f, 1f),
                onValueChange = onScrub,
                onValueChangeFinished = { onScrubEnd(fraction) },
                enabled = durationMs > 0,
                colors = SliderDefaults.colors(
                    thumbColor = NoriColors.accent,
                    activeTrackColor = NoriColors.accent,
                    inactiveTrackColor = Color.White.copy(alpha = 0.22f),
                ),
                modifier = Modifier.fillMaxWidth(),
            )

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = formatClock(positionMs / 1000.0),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White,
                )
                Spacer(Modifier.weight(1f))
                if (state.hasNext) {
                    TextButton(onClick = onNext) {
                        Icon(Icons.Rounded.SkipNext, contentDescription = null, tint = NoriColors.accent)
                        Spacer(Modifier.width(4.dp))
                        Text("Nächste Folge", color = NoriColors.accent)
                    }
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    text = if (durationMs > 0) formatClock(durationMs / 1000.0) else "–:––",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White,
                )
            }
        }
    }
}

@Composable
private fun NextCountdown(
    seconds: Int,
    onNow: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .background(Color.Black.copy(alpha = 0.85f))
            .padding(16.dp),
        horizontalAlignment = Alignment.End,
    ) {
        Text(
            "Nächste Folge in $seconds s",
            style = MaterialTheme.typography.bodyMedium,
            color = NoriColors.fg,
        )
        Spacer(Modifier.height(6.dp))
        Row {
            TextButton(onClick = onCancel) { Text("Abbrechen", color = NoriColors.muted) }
            TextButton(onClick = onNow) { Text("Jetzt", color = NoriColors.accent) }
        }
    }
}

private fun seasonLine(state: PlayerUiState.Ready): String {
    val season = if (state.season == "filme") "Filme" else "Staffel ${state.season}"
    val title = state.episode.displayTitle
    return "$season · Folge ${state.episode.number} · $title"
}
