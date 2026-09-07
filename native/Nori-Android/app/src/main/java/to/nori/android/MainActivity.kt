package to.nori.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            NoriTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    Root()
                }
            }
        }
    }
}

/**
 * Die fünf Bereiche, dieselben wie auf dem iPhone.
 *
 * Bewusst eine `NavigationBar` unten und kein Schubladenmenü: auf iOS ist es
 * eine Tab-Leiste, und ein Nutzer, der beide Apps hat, soll nicht umlernen.
 */
private enum class Tab(val route: String, val label: String, val icon: ImageVector) {
    HOME("home", "Start", Icons.Filled.Home),
    CATALOG("catalog", "Katalog", Icons.Filled.Search),
    CALENDAR("calendar", "Kalender", Icons.Filled.DateRange),
    WATCHLIST("watchlist", "Merkliste", Icons.Filled.Favorite),
    SETTINGS("settings", "Mehr", Icons.Filled.Settings),
}

@Composable
private fun Root() {
    val model: NoriViewModel = viewModel()
    val nav = rememberNavController()

    if (NoriBridge.loadError != null) {
        StatusBox(
            "Der Swift-Kern ließ sich nicht laden.\n\n${NoriBridge.loadError}",
            isError = true,
        )
        return
    }

    val entry by nav.currentBackStackEntryAsState()
    val route = entry?.destination?.route

    androidx.compose.material3.Scaffold(
        bottomBar = {
            // Auf der Detailseite und im Player ist die Leiste im Weg.
            if (route in Tab.entries.map { it.route }) {
                NavigationBar {
                    Tab.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = route == tab.route,
                            onClick = {
                                nav.navigate(tab.route) {
                                    popUpTo(Tab.HOME.route) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(tab.icon, contentDescription = tab.label) },
                            label = { Text(tab.label) },
                        )
                    }
                }
            }
        }
    ) { insets ->
        NavHost(
            navController = nav,
            startDestination = Tab.HOME.route,
            modifier = Modifier.padding(insets),
        ) {
            composable(Tab.HOME.route) { HomeScreen(model, nav) }
            composable(Tab.CATALOG.route) { CatalogScreen(model, nav) }
            composable(Tab.CALENDAR.route) { CalendarScreen(model, nav) }
            composable(Tab.WATCHLIST.route) { WatchlistScreen(model, nav) }
            composable(Tab.SETTINGS.route) { SettingsScreen(model) }
            composable("series/{provider}/{slug}") { backStack ->
                SeriesScreen(
                    model = model,
                    nav = nav,
                    provider = Provider.from(backStack.arguments?.getString("provider")),
                    slug = backStack.arguments?.getString("slug").orEmpty(),
                )
            }
            composable("player/{provider}/{path}") { backStack ->
                PlayerScreen(
                    model = model,
                    nav = nav,
                    provider = Provider.from(backStack.arguments?.getString("provider")),
                    // Der Folgenpfad enthält Schrägstriche und wird deshalb
                    // kodiert übergeben.
                    path = java.net.URLDecoder.decode(
                        backStack.arguments?.getString("path").orEmpty(), "UTF-8"
                    ),
                )
            }
        }
    }
}

/** Zur Detailseite. Der Slug kann Sonderzeichen tragen, deshalb kodiert. */
fun NavHostController.openSeries(provider: Provider, slug: String) {
    navigate("series/${provider.raw}/${java.net.URLEncoder.encode(slug, "UTF-8")}")
}

/** In den Player. */
fun NavHostController.openPlayer(provider: Provider, path: String) {
    navigate("player/${provider.raw}/${java.net.URLEncoder.encode(path, "UTF-8")}")
}

/**
 * Der Quellenumschalter, wie auf iOS eine segmentierte Kapsel.
 *
 * Anders als auf dem Mac gibt es hier (noch) keinen K-Drama-Bereich: der
 * hängt an `LibraryScope`, und die gemeinsame Bibliothek ist auf iOS und
 * Android noch nicht eingebaut.
 */
@Composable
fun KindSwitch(model: NoriViewModel) {
    val current by model.provider.collectAsState()
    SingleChoiceSegmentedButtonRow {
        Provider.entries.forEachIndexed { index, source ->
            SegmentedButton(
                selected = current == source,
                onClick = { model.switch(source) },
                shape = SegmentedButtonDefaults.itemShape(index, Provider.entries.size),
            ) { Text(source.label) }
        }
    }
}
