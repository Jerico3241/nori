package de.nori.ui.search

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import de.nori.core.CatalogProvider
import de.nori.ui.components.EmptyState
import de.nori.ui.components.ErrorState
import de.nori.ui.components.LoadingState
import de.nori.ui.components.PosterCard
import de.nori.ui.theme.NoriColors

/**
 * Suche und Katalog in einem.
 *
 * Ohne Eingabe steht der vollständige Katalog des gewählten Bereichs da —
 * genau wie auf Apple. Die Suche filtert ihn, statt eine Anfrage pro
 * Tastendruck an die Quelle zu schicken: beide Quellen haben keine brauchbare
 * Suchschnittstelle, und der Katalog liegt ohnehin komplett vor.
 */
@Composable
fun SearchScreen(
    viewModel: SearchViewModel,
    columns: Int,
    onOpenSeries: (slug: String, title: String, provider: CatalogProvider) -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()

    Column(Modifier.fillMaxSize()) {
        OutlinedTextField(
            value = query,
            onValueChange = viewModel::onQueryChange,
            singleLine = true,
            placeholder = { Text("Titel suchen", color = NoriColors.muted) },
            leadingIcon = { Icon(Icons.Rounded.Search, contentDescription = null, tint = NoriColors.muted) },
            trailingIcon = {
                if (query.isNotEmpty()) {
                    IconButton(onClick = { viewModel.onQueryChange("") }) {
                        Icon(Icons.Rounded.Close, contentDescription = "Leeren", tint = NoriColors.muted)
                    }
                }
            },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = NoriColors.fg,
                unfocusedTextColor = NoriColors.fg,
                focusedContainerColor = NoriColors.elevated,
                unfocusedContainerColor = NoriColors.elevated,
                focusedBorderColor = NoriColors.border,
                unfocusedBorderColor = NoriColors.border,
                cursorColor = NoriColors.accent,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
        )

        Box(Modifier.fillMaxSize()) {
            when (val current = state) {
                SearchUiState.Loading -> LoadingState("Katalog wird geladen")

                is SearchUiState.Error -> ErrorState(current.message, onRetry = viewModel::reload)

                is SearchUiState.Ready -> when {
                    current.results.isEmpty() && query.isNotBlank() -> EmptyState(
                        title = "Nichts gefunden",
                        hint = "Für „$query" gibt es in ${current.scopeLabel} keinen Treffer.",
                    )

                    current.results.isEmpty() -> EmptyState("Der Katalog ist leer.")

                    else -> LazyVerticalGrid(
                        columns = GridCells.Fixed(columns),
                        contentPadding = PaddingValues(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(18.dp),
                    ) {
                        items(current.results, key = { it.key }) { item ->
                            val provider = item.provider ?: CatalogProvider.Aniworld
                            PosterCard(
                                title = item.title,
                                slug = item.slug,
                                provider = provider,
                                subtitle = item.genres.firstOrNull(),
                                onClick = { onOpenSeries(item.slug, item.title, provider) },
                            )
                        }
                    }
                }
            }
        }
    }
}
