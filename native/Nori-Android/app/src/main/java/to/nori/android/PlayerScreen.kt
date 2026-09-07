package to.nori.android

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import androidx.navigation.NavHostController
import kotlinx.coroutines.delay

/**
 * Der Player.
 *
 * Media3/ExoPlayer statt AVPlayer, sonst dieselbe Aufgabe wie auf iOS: Stream
 * über die Brücke auflösen, abspielen, Fortschritt zurückschreiben.
 *
 * **Der Referer ist nicht optional.** Viele Hoster liefern das Video nur
 * aus, wenn der Abruf die Seite mitschickt, von der es stammt — ohne die
 * Kopfzeile kommt ein 403 statt eines Bildes. Auf iOS setzt `AVURLAsset` sie
 * über `AVURLAssetHTTPHeaderFieldsKey`, hier tut es die
 * `DefaultHttpDataSource.Factory`.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
fun PlayerScreen(
    model: NoriViewModel,
    nav: NavHostController,
    provider: Provider,
    path: String,
) {
    val context = LocalContext.current
    val library by model.library.collectAsState()

    var status by remember { mutableStateOf("Stream wird gesucht …") }
    var source by remember { mutableStateOf<PlaySource?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var player by remember { mutableStateOf<ExoPlayer?>(null) }

    // Auflösen. Der teuerste Aufruf der App — jeder Hoster wird der Reihe
    // nach probiert, das kann zehn Sekunden dauern.
    LaunchedEffect(path) {
        error = null
        source = null
        status = "Stream wird gesucht …"
        when (val result = NoriRepository.resolve(provider, path, library.langPref, library.hosterPref)) {
            is Result.Ok -> {
                source = result.value
                status = "${result.value.hoster} · ${result.value.lang}"
                // Die erfolgreiche Wahl merken, damit der nächste Start
                // schneller geht — genau wie auf iOS.
                NoriRepository.putPrefs(result.value.lang, result.value.hoster)
            }
            is Result.Failed -> error = result.message
        }
    }

    // Player aufbauen, sobald eine Adresse da ist.
    LaunchedEffect(source) {
        val play = source ?: return@LaunchedEffect
        val headers = buildMap {
            play.referer?.takeIf { it.isNotBlank() }?.let { put("Referer", it) }
            put("User-Agent", USER_AGENT)
        }
        val http = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(headers)
            .setAllowCrossProtocolRedirects(true)
        val exo = ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(http))
            .build()
        exo.setMediaItem(MediaItem.fromUri(play.url))
        exo.prepare()
        exo.playWhenReady = true
        player = exo
    }

    // Fortschritt zurückschreiben, solange gespielt wird.
    LaunchedEffect(player) {
        val exo = player ?: return@LaunchedEffect
        while (true) {
            delay(5000)
            val position = exo.currentPosition / 1000.0
            val duration = exo.duration / 1000.0
            if (duration > 0 && position > 0) {
                NoriRepository.putProgress(
                    WatchProgress(
                        slug = slugFrom(path),
                        title = "",
                        season = seasonFrom(path),
                        episode = episodeFrom(path),
                        episodePath = path,
                        positionSec = position,
                        durationSec = duration,
                        updatedAt = System.currentTimeMillis() / 1000.0,
                        lang = source?.lang,
                        provider = provider.raw,
                    )
                )
            }
            if (exo.playbackState == Player.STATE_ENDED) break
        }
    }

    DisposableEffect(Unit) {
        onDispose { player?.release() }
    }

    Box(Modifier.fillMaxSize()) {
        val exo = player
        if (exo != null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        this.player = exo
                        useController = true
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Column(
                Modifier.fillMaxSize().padding(24.dp),
                verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (error == null) {
                    CircularProgressIndicator()
                    Text(status, Modifier.padding(top = 16.dp))
                } else {
                    Text(
                        "Kein Stream.",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                    Text(
                        error!!,
                        Modifier.padding(top = 8.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedButton(
                        onClick = { nav.popBackStack() },
                        modifier = Modifier.padding(top = 16.dp),
                    ) { Text("Zurück") }
                }
            }
        }

        IconButton(
            onClick = { nav.popBackStack() },
            modifier = Modifier.align(Alignment.TopStart).padding(8.dp),
        ) {
            Icon(Icons.Filled.ArrowBack, contentDescription = "Zurück", tint = Color.White)
        }
    }
}

/**
 * Derselbe User-Agent wie im Kern (`NoriOrigin.ua`).
 *
 * Nicht kosmetisch: Hoster liefern je nach Kennung anderes Markup oder gar
 * nichts. Weicht der Player vom Kern ab, holt er womöglich eine Adresse, die
 * für einen anderen Client gedacht war.
 */
private const val USER_AGENT =
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

// Aus dem Folgenpfad ableiten, was der Fortschritt braucht. Der Pfad hat die
// Form /anime/stream/<slug>/staffel-N/episode-M beziehungsweise
// /serie/<slug>/staffel-N/episode-M.
private fun slugFrom(path: String): String {
    val parts = path.trim('/').split('/')
    val index = parts.indexOfFirst { it.startsWith("staffel-") || it == "filme" }
    return if (index > 0) parts[index - 1] else parts.lastOrNull().orEmpty()
}

private fun seasonFrom(path: String): String =
    path.substringAfter("staffel-", "").substringBefore('/').ifBlank { "" }

private fun episodeFrom(path: String): Int =
    path.substringAfter("episode-", "").substringBefore('/').toIntOrNull() ?: 0
