package de.nori.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import de.nori.core.LibraryScope
import de.nori.data.CoreState
import de.nori.data.Nori
import de.nori.ui.components.ContentPadding
import de.nori.ui.components.NoriChip
import de.nori.ui.theme.NoriColors

@Composable
fun SettingsScreen(viewModel: SettingsViewModel) {
    val snapshot by viewModel.snapshot.collectAsStateWithLifecycle()
    val core by Nori.core.collectAsStateWithLifecycle()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = 12.dp, horizontal = 0.dp),
    ) {
        item(key = "scope") {
            SettingSection("Bereich") {
                LazyRow(
                    contentPadding = ContentPadding,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(LibraryScope.entries.toList(), key = { it.wire }) { scope ->
                        NoriChip(
                            text = scope.label,
                            selected = scope == snapshot.currentScope,
                            onClick = { viewModel.setScope(scope) },
                        )
                    }
                }
            }
        }

        item(key = "lang") {
            SettingSection("Bevorzugte Sprache") {
                LazyRow(
                    contentPadding = ContentPadding,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    // Reihenfolge wie im Contract: DE, GerSub, EN.
                    items(listOf("DE", "GerSub", "EN"), key = { it }) { lang ->
                        NoriChip(
                            text = lang,
                            selected = lang.equals(snapshot.langPref, ignoreCase = true),
                            onClick = { viewModel.setLanguage(lang) },
                        )
                    }
                }
            }
        }

        item(key = "hoster") {
            SettingSection("Bevorzugter Hoster") {
                LazyRow(
                    contentPadding = ContentPadding,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(HOSTERS, key = { it }) { hoster ->
                        NoriChip(
                            text = hoster,
                            selected = hoster.equals(snapshot.hosterPref, ignoreCase = true),
                            onClick = { viewModel.setHoster(hoster) },
                        )
                    }
                }
                Spacer(Modifier.height(8.dp))
                Hint(
                    "Ist der bevorzugte Hoster für eine Folge nicht eingetragen oder liefert " +
                        "er nichts, geht Nori die übrigen der Reihe nach durch."
                )
            }
        }

        item(key = "speed") {
            SettingSection("Wiedergabegeschwindigkeit") {
                LazyRow(
                    contentPadding = ContentPadding,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(listOf(0.75f, 1.0f, 1.25f, 1.5f, 2.0f), key = { it }) { speed ->
                        NoriChip(
                            text = if (speed == 1.0f) "Normal" else "${speed}×",
                            selected = kotlin.math.abs(snapshot.playbackSpeed - speed) < 0.01,
                            onClick = { viewModel.setSpeed(speed) },
                        )
                    }
                }
            }
        }

        item(key = "toggles") {
            SettingSection("Wiedergabe") {
                ToggleRow(
                    title = "An letzter Stelle fortsetzen",
                    hint = "Angefangene Folgen starten dort, wo sie zuletzt standen.",
                    checked = snapshot.resumeEnabled,
                    onChange = viewModel::setResume,
                )
                ToggleRow(
                    title = "Nächste Folge automatisch",
                    hint = "Am Ende einer Folge läuft nach acht Sekunden die nächste an.",
                    checked = snapshot.autoplayNext,
                    onChange = viewModel::setAutoplay,
                )
            }
        }

        item(key = "data") {
            SettingSection("Daten") {
                ActionRow("Verlauf löschen", viewModel::clearHistory)
                ActionRow("Wiedergabefortschritt löschen", viewModel::clearProgress)
                Spacer(Modifier.height(8.dp))
                Hint("Die Merkliste bleibt dabei erhalten.")
            }
        }

        item(key = "about") {
            SettingSection("Über") {
                Column(Modifier.padding(horizontal = 16.dp)) {
                    val version = (core as? CoreState.Ready)
                    Text(
                        text = "Nori für Android",
                        style = MaterialTheme.typography.bodyLarge,
                        color = NoriColors.fg,
                    )
                    Spacer(Modifier.height(4.dp))
                    Hint(
                        when (version) {
                            null -> "Der Kern wird noch geladen."
                            else -> "Bibliotheksschema v${version.schemaVersion} · " +
                                (if (version.hasTMDBKey) "TMDB verfügbar" else "ohne TMDB-Schlüssel")
                        }
                    )
                    Spacer(Modifier.height(8.dp))
                    Hint(
                        "Katalog, Auflösung der Streams und Fortschrittsregeln kommen aus " +
                            "demselben Swift-Kern wie in den Apple-Apps."
                    )
                }
            }
        }
    }
}

@Composable
private fun SettingSection(title: String, content: @Composable () -> Unit) {
    Column(Modifier.padding(bottom = 20.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = NoriColors.muted,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
        content()
        Spacer(Modifier.height(12.dp))
        HorizontalDivider(color = NoriColors.border)
    }
}

@Composable
private fun ToggleRow(
    title: String,
    hint: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onChange(!checked) }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = NoriColors.fg)
            Hint(hint)
        }
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = NoriColors.bg,
                checkedTrackColor = NoriColors.accent,
                uncheckedThumbColor = NoriColors.muted,
                uncheckedTrackColor = NoriColors.elevated,
            ),
        )
    }
}

@Composable
private fun ActionRow(title: String, onClick: () -> Unit) {
    Text(
        text = title,
        style = MaterialTheme.typography.bodyLarge,
        color = NoriColors.fg,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
    )
}

@Composable
private fun Hint(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = NoriColors.muted)
}

/** Reihenfolge wie `hosterOrder` im Contract. */
private val HOSTERS = listOf(
    "VOE", "Vidmoly", "Vidoza", "LuluStream", "SpeedFiles", "Filemoon", "Doodstream",
)
