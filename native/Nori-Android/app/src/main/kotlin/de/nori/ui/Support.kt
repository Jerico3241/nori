package de.nori.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import de.nori.core.CatalogProvider
import de.nori.core.Episode

/**
 * Was der Player wissen muss, um zu starten.
 *
 * Bewusst **nicht** über die Navigationsargumente: dort müsste die
 * vollständige Folgenliste der Staffel durch — als kodierte Zeichenkette in
 * einer URL. Das wären bei einer langen Staffel mehrere Kilobyte pro
 * Navigation, und Android deckelt die Größe eines Bundles.
 *
 * Deshalb ein Übergabeplatz: gesetzt beim Antippen, gelesen beim Aufbau des
 * Players. Er lebt genau einen Wechsel lang.
 */
data class PlaybackRequest(
    val slug: String,
    val title: String,
    val provider: CatalogProvider,
    val season: String,
    val episodes: List<Episode>,
    val start: Episode,
    val resumeAtSec: Double,
) {
    companion object {
        @Volatile
        var pending: PlaybackRequest? = null
    }
}

/**
 * Ein ViewModel mit Konstruktorargumenten, ohne ein
 * Dependency-Injection-Rahmenwerk dafür einzuführen.
 */
inline fun <reified T : ViewModel> viewModelFactory(
    crossinline create: () -> T,
): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <VM : ViewModel> create(modelClass: Class<VM>): VM = create() as VM
}
