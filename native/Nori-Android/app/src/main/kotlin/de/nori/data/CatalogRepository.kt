package de.nori.data

import de.nori.core.CatalogItem
import de.nori.core.CatalogProvider
import de.nori.core.CalendarPayload
import de.nori.core.NoriCore
import de.nori.core.SeriesDetail
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Kataloge, Serien und Kalender — mit einem Zwischenspeicher **diesseits**
 * der Brücke.
 *
 * Der Kern hält seine eigenen Puffer (Katalog 30 Minuten, Serie 10). Trotzdem
 * lohnt einer hier: ein Katalog hat mehrere tausend Einträge, und jeder Gang
 * über die Brücke kodiert und dekodiert ihn vollständig als JSON. Das ist die
 * eine Stelle, an der die gewählte Übergabeform ins Gewicht fällt — also wird
 * sie genau einmal je Quelle bezahlt.
 */
class CatalogRepository {

    private val mutex = Mutex()
    private val catalogs = mutableMapOf<CatalogProvider, List<CatalogItem>>()
    private val calendars = mutableMapOf<CatalogProvider, CalendarPayload>()

    suspend fun catalog(provider: CatalogProvider, force: Boolean = false): List<CatalogItem> {
        if (!force) {
            mutex.withLock { catalogs[provider] }?.let { return it }
        }
        val items = NoriCore.catalog(provider, force).items
        mutex.withLock { catalogs[provider] = items }
        return items
    }

    /** Beide Quellen für die gemeinsame Bibliotheksansicht. */
    suspend fun catalogs(providers: List<CatalogProvider>, force: Boolean = false): List<CatalogItem> =
        providers.flatMap { catalog(it, force) }

    suspend fun calendar(provider: CatalogProvider, force: Boolean = false): CalendarPayload {
        if (!force) {
            mutex.withLock { calendars[provider] }?.let { return it }
        }
        val payload = NoriCore.calendar(provider, force)
        mutex.withLock { calendars[provider] = payload }
        return payload
    }

    suspend fun series(provider: CatalogProvider, slug: String, season: String? = null): SeriesDetail =
        NoriCore.series(provider, slug, season)

    /**
     * Suche über den geladenen Katalog — Titel, Alternativtitel, Slug.
     *
     * Genau wie auf iOS und macOS: beide Quellen haben keine brauchbare
     * Suchschnittstelle, und der Katalog liegt ohnehin vollständig vor. Eine
     * Anfrage pro Tastendruck an AniWorld zu schicken wäre langsamer und
     * würde die Quelle unnötig belasten.
     */
    fun search(items: List<CatalogItem>, query: String): List<CatalogItem> {
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) return items
        return items.filter { item ->
            item.title.lowercase().contains(needle) ||
                item.slug.lowercase().contains(needle) ||
                item.alts.any { it.lowercase().contains(needle) }
        }
    }
}
