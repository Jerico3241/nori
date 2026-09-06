package to.nori.android

import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Material You, aber immer dunkel.
 *
 * Dieselbe Entscheidung wie in docs/android.md beschrieben: der Inhalt sind
 * Cover, und ein heller Grund kämpft dagegen an. Die Farbtöne kommen ab
 * Android 12 aus dem Hintergrundbild, das Schema bleibt dunkel.
 */
@Composable
private fun NoriTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val scheme = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        dynamicDarkColorScheme(context)
    } else {
        darkColorScheme(
            primary = Color(0xFF7BD88F),
            background = Color(0xFF0E0F12),
            surface = Color(0xFF16181D),
        )
    }
    MaterialTheme(colorScheme = scheme, content = content)
}

/** Ein Katalogeintrag, so wie ihn der Swift-Kern als JSON liefert. */
private data class Item(val slug: String, val title: String, val genres: String)

private sealed interface State {
    data object Idle : State
    data object Loading : State
    data class Failed(val message: String) : State
    data class Loaded(val items: List<Item>) : State
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { NoriTheme { Root() } }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Root() {
    var state by remember { mutableStateOf<State>(State.Idle) }
    var provider by remember { mutableStateOf("aniworld") }
    var ping by remember { mutableStateOf(NoriBridge.loadError?.let { "Fehler: $it" } ?: "") }

    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Scaffold(
            topBar = { TopAppBar(title = { Text("Nori") }) }
        ) { insets ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(insets)
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                if (NoriBridge.loadError != null) {
                    Text(
                        "Der Swift-Kern ließ sich nicht laden.\n${NoriBridge.loadError}",
                        color = MaterialTheme.colorScheme.error
                    )
                    return@Column
                }

                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    listOf("aniworld" to "Anime", "serienstream" to "Serien")
                        .forEachIndexed { index, (raw, label) ->
                            SegmentedButton(
                                selected = provider == raw,
                                onClick = { provider = raw },
                                shape = SegmentedButtonDefaults.itemShape(index, 2)
                            ) { Text(label) }
                        }
                }

                Button(onClick = { ping = runCatching { NoriBridge.ping() }.getOrElse { "Fehler: ${it.message}" } }) {
                    Text("Lebenszeichen")
                }
                if (ping.isNotEmpty()) {
                    Text(ping, style = MaterialTheme.typography.bodySmall)
                }

                LoadButton(provider) { state = it }

                when (val current = state) {
                    is State.Idle -> Text("Noch nichts geladen.")
                    is State.Loading -> CircularProgressIndicator()
                    is State.Failed -> Text(
                        current.message,
                        color = MaterialTheme.colorScheme.error
                    )
                    is State.Loaded -> {
                        Text("${current.items.size} Titel")
                        LazyColumn(
                            contentPadding = PaddingValues(vertical = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            items(current.items) { item ->
                                Column {
                                    Text(item.title, style = MaterialTheme.typography.bodyLarge)
                                    if (item.genres.isNotEmpty()) {
                                        Text(
                                            item.genres,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LoadButton(provider: String, onState: (State) -> Unit) {
    val scope = rememberCoroutineScope()
    Button(onClick = {
        onState(State.Loading)
        scope.launch {
            // Zwingend abseits des Main-Threads: die Brücke blockiert, bis
            // der Swift-actor geantwortet hat.
            val json = withContext(Dispatchers.IO) {
                runCatching { NoriBridge.catalogJson(provider) }
                    .getOrElse { """{"error":"${it.message}"}""" }
            }
            onState(parse(json))
        }
    }) {
        Text("Katalog laden")
    }
}

private fun parse(json: String): State = runCatching {
    val trimmed = json.trim()
    if (trimmed.startsWith("{")) {
        val error = JSONObject(trimmed).optString("error", "Unbekannter Fehler")
        return State.Failed(error)
    }
    val array = JSONArray(trimmed)
    val items = buildList {
        for (i in 0 until array.length()) {
            val row = array.getJSONObject(i)
            val genres = row.optJSONArray("genres")
            add(
                Item(
                    slug = row.optString("slug"),
                    title = row.optString("title"),
                    genres = buildList {
                        if (genres != null) for (g in 0 until genres.length()) add(genres.getString(g))
                    }.take(3).joinToString(" · ")
                )
            )
        }
    }
    State.Loaded(items)
}.getOrElse { State.Failed("Antwort nicht lesbar: ${it.message}") }
