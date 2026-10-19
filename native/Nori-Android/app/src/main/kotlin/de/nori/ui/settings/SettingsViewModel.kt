package de.nori.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.nori.core.LibraryScope
import de.nori.data.Nori
import kotlinx.coroutines.launch

class SettingsViewModel : ViewModel() {

    val snapshot = Nori.library.snapshot

    fun setScope(scope: LibraryScope) = launchSafely { Nori.library.setScope(scope) }
    fun setLanguage(lang: String) = launchSafely { Nori.library.setLanguage(lang) }
    fun setHoster(hoster: String) = launchSafely { Nori.library.setHoster(hoster) }
    fun setSpeed(speed: Float) = launchSafely { Nori.library.setSpeed(speed) }
    fun setResume(enabled: Boolean) = launchSafely { Nori.library.setResume(enabled) }
    fun setAutoplay(enabled: Boolean) = launchSafely { Nori.library.setAutoplay(enabled) }
    fun clearHistory() = launchSafely { Nori.library.clearHistory() }
    fun clearProgress() = launchSafely { Nori.library.clearProgress() }

    /**
     * Ein fehlgeschlagenes Speichern einer Einstellung darf die App nicht
     * beenden. Der Zustand bleibt dann schlicht, wie er war — sichtbar am
     * Schalter, der zurückspringt.
     */
    private fun launchSafely(block: suspend () -> Unit) {
        viewModelScope.launch { runCatching { block() } }
    }
}
