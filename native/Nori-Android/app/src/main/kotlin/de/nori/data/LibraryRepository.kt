package de.nori.data

import de.nori.core.CatalogProvider
import de.nori.core.Episode
import de.nori.core.LibraryScope
import de.nori.core.LibrarySnapshot
import de.nori.core.NextPlay
import de.nori.core.NoriCore
import de.nori.core.SeasonStats
import de.nori.core.WatchProgress
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Die eine Kopie des Bibliotheksstands.
 *
 * Merkliste, Verlauf, Fortschritt und Einstellungen liegen im Swift-Kern in
 * `library.json`. Hier steht davon genau **eine** Abbildung, und jede
 * Änderung ersetzt sie durch das, was der Kern zurückgibt.
 *
 * Das ist die Antwort auf einen Fehler, den man in Compose leicht baut: jeder
 * Bildschirm hält seinen eigenen `mutableStateOf`, die Merkliste zeigt einen
 * Titel noch als gemerkt, den die Detailseite gerade entfernt hat. Hier kann
 * das nicht passieren, weil es keinen zweiten Ort gibt, an dem der Zustand
 * steht.
 */
class LibraryRepository {

    private val _snapshot = MutableStateFlow(LibrarySnapshot())
    val snapshot: StateFlow<LibrarySnapshot> = _snapshot.asStateFlow()

    // Zwei gleichzeitige Änderungen dürfen sich nicht überholen: die zweite
    // würde sonst den Stand der ersten überschreiben.
    private val mutex = Mutex()

    suspend fun refresh() = mutex.withLock {
        _snapshot.value = NoriCore.librarySnapshot()
    }

    suspend fun toggleFavorite(slug: String, title: String?) = mutex.withLock {
        _snapshot.value = NoriCore.toggleFavorite(slug, title)
    }

    suspend fun remember(slug: String, title: String, provider: CatalogProvider) = mutex.withLock {
        _snapshot.value = NoriCore.remember(slug, title, provider)
    }

    suspend fun saveProgress(progress: WatchProgress) = mutex.withLock {
        _snapshot.value = NoriCore.upsertProgress(progress)
    }

    suspend fun setScope(scope: LibraryScope) = mutex.withLock {
        _snapshot.value = NoriCore.setPreferences(
            scope = scope,
            // Der Bereich bestimmt auch, welche Seite ein Titel ohne eigene
            // Quellangabe öffnet. „Alle" lässt die bisherige Quelle stehen.
            provider = scope.provider,
        )
    }

    suspend fun setProvider(provider: CatalogProvider) = mutex.withLock {
        _snapshot.value = NoriCore.setPreferences(provider = provider)
    }

    suspend fun setLanguage(lang: String) = mutex.withLock {
        _snapshot.value = NoriCore.setPreferences(langPref = lang)
    }

    suspend fun setHoster(hoster: String) = mutex.withLock {
        _snapshot.value = NoriCore.setPreferences(hosterPref = hoster)
    }

    suspend fun setResume(enabled: Boolean) = mutex.withLock {
        _snapshot.value = NoriCore.setPreferences(resumeEnabled = enabled)
    }

    suspend fun setAutoplay(enabled: Boolean) = mutex.withLock {
        _snapshot.value = NoriCore.setPreferences(autoplayNext = enabled)
    }

    suspend fun setSpeed(speed: Float) = mutex.withLock {
        _snapshot.value = NoriCore.setPreferences(playbackSpeed = speed)
    }

    suspend fun clearHistory() = mutex.withLock {
        _snapshot.value = NoriCore.clearHistory()
    }

    suspend fun clearProgress() = mutex.withLock {
        _snapshot.value = NoriCore.clearProgress()
    }

    /** „Weiterschauen" — Reihenfolge und Auswahl bestimmt der Kern. */
    suspend fun continueWatching(): List<WatchProgress> = NoriCore.continueWatching()

    /**
     * Welche Folge der Abspielknopf startet und ob er „Abspielen",
     * „Fortsetzen" oder „Weiter" heißt.
     */
    suspend fun nextPlay(
        slug: String,
        season: String,
        episodes: List<Episode>,
        provider: CatalogProvider,
    ): NextPlay = NoriCore.nextPlay(slug, season, episodes, provider)

    suspend fun seasonStats(
        slug: String,
        season: String,
        episodes: List<Episode>,
        provider: CatalogProvider,
    ): SeasonStats = NoriCore.seasonStats(slug, season, episodes, provider)
}
