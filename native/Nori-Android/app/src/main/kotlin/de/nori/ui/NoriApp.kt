package de.nori.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.VideoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.navArgument
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import de.nori.core.CatalogProvider
import de.nori.core.Episode
import de.nori.core.WatchProgress
import de.nori.core.providerFromPath
import de.nori.data.CoreState
import de.nori.data.Nori
import de.nori.ui.components.ErrorState
import de.nori.ui.components.LoadingState
import de.nori.ui.home.HomeScreen
import de.nori.ui.home.HomeViewModel
import de.nori.ui.library.LibraryScreen
import de.nori.ui.library.LibraryViewModel
import de.nori.ui.player.PlayerScreen
import de.nori.ui.player.PlayerViewModel
import de.nori.ui.search.SearchScreen
import de.nori.ui.search.SearchViewModel
import de.nori.ui.series.SeriesScreen
import de.nori.ui.series.SeriesViewModel
import de.nori.ui.settings.SettingsScreen
import de.nori.ui.settings.SettingsViewModel
import de.nori.ui.theme.NoriColors

private enum class Tab(val route: String, val label: String, val icon: ImageVector) {
    Home("home", "Start", Icons.Rounded.Home),
    Search("search", "Suche", Icons.Rounded.Search),
    Library("library", "Bibliothek", Icons.Rounded.VideoLibrary),
    Settings("settings", "Einstellungen", Icons.Rounded.Settings),
}

/**
 * Die Navigation.
 *
 * Auf dem Telefon eine Leiste unten, auf breiten Geräten eine Schiene links —
 * derselbe Inhalt, andere Anordnung. Der Player liegt außerhalb beider und
 * nimmt den ganzen Bildschirm.
 */
@Composable
fun NoriApp(
    inPictureInPicture: Boolean,
    onEnterPictureInPicture: () -> Unit,
    onPlaybackStarted: () -> Unit,
    onPlaybackFinished: () -> Unit,
) {
    val core by Nori.core.collectAsStateWithLifecycle()
    val navController = rememberNavController()

    when (val state = core) {
        CoreState.Starting -> LoadingState(
            "Nori startet",
            Modifier
                .fillMaxSize()
                .background(NoriColors.bg),
        )

        is CoreState.Failed -> ErrorState(
            state.message,
            Modifier
                .fillMaxSize()
                .background(NoriColors.bg),
        )

        is CoreState.Ready -> BoxWithConstraints(
            Modifier
                .fillMaxSize()
                .background(NoriColors.bg)
        ) {
            // Ein Tablet ist keine große Telefonoberfläche. Ab 600 dp bekommt
            // die Navigation eine Schiene, ab 840 dp stehen Cover und Text der
            // Detailseite nebeneinander, und das Raster wird breiter statt
            // die Kacheln größer.
            val width = maxWidth
            val wide = width >= 840.dp
            val rail = width >= 600.dp
            val columns = when {
                width >= 1200.dp -> 7
                width >= 960.dp -> 6
                width >= 700.dp -> 5
                width >= 520.dp -> 4
                else -> 3
            }

            val backStack by navController.currentBackStackEntryAsState()
            val route = backStack?.destination?.route
            val inPlayer = route?.startsWith("player") == true
            val showNav = !inPlayer && !inPictureInPicture

            if (rail && showNav) {
                androidx.compose.foundation.layout.Row(Modifier.fillMaxSize()) {
                    NoriRail(navController, route)
                    Graph(
                        navController = navController,
                        wide = wide,
                        columns = columns,
                        inPictureInPicture = inPictureInPicture,
                        onEnterPictureInPicture = onEnterPictureInPicture,
                        onPlaybackStarted = onPlaybackStarted,
                        onPlaybackFinished = onPlaybackFinished,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            } else {
                Scaffold(
                    containerColor = NoriColors.bg,
                    bottomBar = { if (showNav) NoriBottomBar(navController, route) },
                ) { padding ->
                    Graph(
                        navController = navController,
                        wide = wide,
                        columns = columns,
                        inPictureInPicture = inPictureInPicture,
                        onEnterPictureInPicture = onEnterPictureInPicture,
                        onPlaybackStarted = onPlaybackStarted,
                        onPlaybackFinished = onPlaybackFinished,
                        // Der Player zeichnet bis in die Systemleisten; alle
                        // anderen Bildschirme halten Abstand zur Navigation.
                        modifier = Modifier.padding(if (inPlayer) PaddingValues(0.dp) else padding),
                    )
                }
            }
        }
    }
}

@Composable
private fun Graph(
    navController: NavHostController,
    wide: Boolean,
    columns: Int,
    inPictureInPicture: Boolean,
    onEnterPictureInPicture: () -> Unit,
    onPlaybackStarted: () -> Unit,
    onPlaybackFinished: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    NavHost(
        navController = navController,
        startDestination = Tab.Home.route,
        modifier = modifier,
    ) {
        composable(Tab.Home.route) {
            val model: HomeViewModel = viewModel()
            HomeScreen(
                viewModel = model,
                wide = wide,
                onOpenSeries = { slug, title, provider ->
                    navController.navigateToSeries(slug, title, provider)
                },
                onResume = { progress -> navController.resume(progress) },
            )
        }

        composable(Tab.Search.route) {
            val model: SearchViewModel = viewModel()
            SearchScreen(
                viewModel = model,
                columns = columns,
                onOpenSeries = { slug, title, provider ->
                    navController.navigateToSeries(slug, title, provider)
                },
            )
        }

        composable(Tab.Library.route) {
            val model: LibraryViewModel = viewModel()
            LibraryScreen(
                viewModel = model,
                columns = columns,
                onOpenSeries = { slug, title, provider ->
                    navController.navigateToSeries(slug, title, provider)
                },
            )
        }

        composable(Tab.Settings.route) {
            val model: SettingsViewModel = viewModel()
            SettingsScreen(model)
        }

        composable(
            route = SERIES_ROUTE,
            arguments = listOf(
                navArgument("provider") { type = NavType.StringType },
                navArgument("slug") { type = NavType.StringType },
                // Ohne Standardwert scheitert der Aufbau des Ziels, sobald
                // ein Titel einmal fehlt.
                navArgument("title") {
                    type = NavType.StringType
                    defaultValue = ""
                },
            ),
        ) { entry ->
            val slug = entry.arguments?.getString("slug").orEmpty()
            val provider = CatalogProvider.fromWire(entry.arguments?.getString("provider"))
                ?: CatalogProvider.Aniworld
            val title = entry.arguments?.getString("title").orEmpty()

            val model: SeriesViewModel = viewModel(
                key = "series:${provider.wire}:$slug",
                factory = viewModelFactory { SeriesViewModel(slug, title, provider) },
            )
            SeriesScreen(
                viewModel = model,
                wide = wide,
                onBack = { navController.popBackStack() },
                onPlay = { episode, resumeAt ->
                    val ready = model.state.value as? de.nori.ui.series.SeriesUiState.Ready
                    PlaybackRequest.pending = PlaybackRequest(
                        slug = slug,
                        title = ready?.detail?.title ?: title,
                        provider = provider,
                        season = ready?.detail?.activeSeason.orEmpty(),
                        episodes = ready?.detail?.episodes.orEmpty(),
                        start = episode,
                        resumeAtSec = resumeAt,
                    )
                    navController.navigate("player")
                },
            )
        }

        composable("player") {
            val request = PlaybackRequest.pending
            if (request == null) {
                // Kann nur passieren, wenn der Prozess zwischen Antippen und
                // Anzeigen neu gestartet wurde. Dann zurück statt leer.
                navController.popBackStack()
                return@composable
            }

            val model: PlayerViewModel = viewModel(
                key = "player:${request.provider.wire}:${request.start.path}",
                factory = viewModelFactory {
                    PlayerViewModel(
                        context = context.applicationContext,
                        slug = request.slug,
                        seriesTitle = request.title,
                        provider = request.provider,
                        season = request.season,
                        episodes = request.episodes,
                    )
                },
            )

            androidx.compose.runtime.LaunchedEffect(request.start.path) {
                onPlaybackStarted()
                model.open(request.start, request.resumeAtSec)
            }

            PlayerScreen(
                viewModel = model,
                inPictureInPicture = inPictureInPicture,
                onEnterPictureInPicture = onEnterPictureInPicture,
                onBack = {
                    onPlaybackFinished()
                    navController.popBackStack()
                },
            )
        }
    }
}

@Composable
private fun NoriBottomBar(navController: NavHostController, route: String?) {
    NavigationBar(containerColor = NoriColors.surface) {
        Tab.entries.forEach { tab ->
            NavigationBarItem(
                selected = route == tab.route,
                onClick = { navController.switchTab(tab.route) },
                icon = { Icon(tab.icon, contentDescription = tab.label) },
                label = { Text(tab.label) },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = NoriColors.bg,
                    selectedTextColor = NoriColors.fg,
                    indicatorColor = NoriColors.accent,
                    unselectedIconColor = NoriColors.muted,
                    unselectedTextColor = NoriColors.muted,
                ),
            )
        }
    }
}

@Composable
private fun NoriRail(navController: NavHostController, route: String?) {
    NavigationRail(containerColor = NoriColors.surface) {
        Tab.entries.forEach { tab ->
            NavigationRailItem(
                selected = route == tab.route,
                onClick = { navController.switchTab(tab.route) },
                icon = { Icon(tab.icon, contentDescription = tab.label) },
                label = { Text(tab.label) },
            )
        }
    }
}

private const val SERIES_ROUTE = "series/{provider}/{slug}?title={title}"

private fun NavHostController.navigateToSeries(
    slug: String,
    title: String,
    provider: CatalogProvider,
) {
    val encodedSlug = java.net.URLEncoder.encode(slug, "UTF-8")
    val encodedTitle = java.net.URLEncoder.encode(title, "UTF-8")
    navigate("series/${provider.wire}/$encodedSlug?title=$encodedTitle")
}

/**
 * „Weiterschauen" öffnet die Detailseite und nicht direkt den Player.
 *
 * Der Fortschrittseintrag kennt zwar Folge und Pfad, aber nicht die
 * Folgenliste der Staffel — und die braucht der Player für „nächste Folge".
 * Die Detailseite holt sie und weiß von sich aus, wo weitergeht.
 */
private fun NavHostController.resume(progress: WatchProgress) {
    val provider = progress.provider ?: providerFromPath(progress.episodePath)
    navigateToSeries(progress.slug, progress.title, provider)
}

private fun NavHostController.switchTab(route: String) {
    navigate(route) {
        popUpTo(graph.startDestinationId) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}
