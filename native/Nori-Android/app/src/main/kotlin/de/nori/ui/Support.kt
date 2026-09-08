package de.nori.ui

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
