package de.nori.data

import de.nori.core.CatalogProvider
import de.nori.core.CoverDetails
import de.nori.core.NoriCore
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Woher ein Cover kommt.
 *
 * Die Reihenfolge ist dieselbe wie auf Apple und sie ist nicht beliebig:
 *
 * 1. **Was schon dasteht** — der Kern führt `covers.json` und beantwortet das
 *    ohne Netz. Damit sind Kacheln beim zweiten Start sofort bebildert.
 * 2. **TMDB** — die besseren Bilder, dazu Beschreibung und Bewertung.
 * 3. **Die Detailseite der Quelle** — der letzte Ausweg, eine ganze Seite für
 *    ein Bild.
 *
 * Was hier ausdrücklich **nicht** passiert: die Adresse aus dem Slug raten.
 * Beide Quellen hängen einen Zufallsanteil an den Dateinamen; jede geratene
 * Adresse war eine 404, und genau daran blieben früher im Katalog fast alle
 * Kacheln leer.
 */
class CoverRepository {

    private val mutex = Mutex()
    private val known = mutableMapOf<String, CoverDetails>()
    /** Slugs, die gerade nachgeschlagen werden — keine doppelten Anfragen. */
    private val pending = mutableSetOf<String>()

    private fun key(slug: String, provider: CatalogProvider) = "${provider.wire}|$slug"

    /** Ohne Netz. Für den ersten Aufbau einer Liste. */
    suspend fun cached(slug: String, provider: CatalogProvider): CoverDetails? {
        mutex.withLock { known[key(slug, provider)] }?.let { return it }
        val details = runCatching { NoriCore.coverCached(slug) }.getOrNull()
        if (details?.poster != null) {
            mutex.withLock { known[key(slug, provider)] = details }
        }
        return details
    }

    /**
     * Vollständig, notfalls über das Netz.
     *
     * Aufrufer sollen das aus einer abbrechbaren Coroutine heraus rufen: beim
     * Durchscrollen einer langen Liste soll die Anfrage gar nicht erst
     * rausgehen, wenn die Kachel schon wieder weg ist.
     */
    suspend fun resolve(slug: String, title: String, provider: CatalogProvider): CoverDetails? {
        val id = key(slug, provider)
        mutex.withLock {
            known[id]?.let { if (it.poster != null) return it }
            if (!pending.add(id)) return known[id]
        }
        try {
            var details = runCatching { NoriCore.coverDetails(slug, title, provider) }.getOrNull()

            if (details?.poster == null) {
                val fromSource = runCatching { NoriCore.coverFromSource(slug, provider) }.getOrNull()
                if (fromSource != null) {
                    details = (details ?: CoverDetails()).copy(poster = fromSource)
                }
            }

            if (details != null) {
                mutex.withLock { known[id] = details }
            }
            return details
        } finally {
            mutex.withLock { pending.remove(id) }
        }
    }

    /** Von Hand gewähltes Cover. */
    suspend fun override(slug: String, provider: CatalogProvider, url: String?) {
        NoriCore.setCoverOverride(slug, url)
        mutex.withLock { known.remove(key(slug, provider)) }
    }
}
