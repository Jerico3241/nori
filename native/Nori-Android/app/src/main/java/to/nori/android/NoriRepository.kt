package to.nori.android

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

/** Ein Aufruf ging entweder gut oder mit einer Meldung schief. */
sealed interface Result<out T> {
    data class Ok<T>(val value: T) : Result<T>
    data class Failed(val message: String) : Result<Nothing>
}

internal val NoriJson = Json {
    ignoreUnknownKeys = true
    isLenient = true
    explicitNulls = false
}

/**
 * Der einzige Ort, an dem [NoriBridge] aufgerufen wird.
 *
 * Zwei Dinge erledigt das Repository, die sonst überall wiederholt würden:
 *
 * 1. **Es geht auf `Dispatchers.IO`.** Die Brücke blockiert, bis der
 *    Swift-`actor` geantwortet hat. Vom Main-Thread aus stünde die
 *    Oberfläche — bei einem Katalog mit 2500 Titeln mehrere Sekunden lang.
 * 2. **Es unterscheidet Nutzdaten von Fehlern.** Die Brücke antwortet immer
 *    JSON; ein Fehler ist ein Objekt mit `error`. Weil eine Liste mit `[`
 *    beginnt und ein Objekt mit `{`, reicht das erste Zeichen — aber nur für
 *    Listen. Für Antworten, die selbst Objekte sind, muss auf `error`
 *    geprüft werden, und genau das passiert hier zentral.
 */
object NoriRepository {

    private suspend fun <T> call(
        parse: (String) -> T,
        block: () -> String,
    ): Result<T> = withContext(Dispatchers.IO) {
        if (NoriBridge.loadError != null) {
            return@withContext Result.Failed("Swift-Kern nicht geladen: ${NoriBridge.loadError}")
        }
        val raw = try {
            block()
        } catch (t: Throwable) {
            return@withContext Result.Failed(t.message ?: t.toString())
        }
        val trimmed = raw.trim()
        // Ein Fehler ist immer ein Objekt mit `error`. Eine Liste kann nie
        // eines sein, deshalb nur Objekte prüfen.
        if (trimmed.startsWith("{")) {
            val failure = runCatching { NoriJson.decodeFromString<BridgeError>(trimmed) }.getOrNull()
            if (failure != null) return@withContext Result.Failed(failure.message)
        }
        runCatching { Result.Ok(parse(trimmed)) }
            .getOrElse { Result.Failed("Antwort nicht lesbar: ${it.message}") }
    }

    suspend fun ping(): Result<String> = call({ it }) { NoriBridge.ping() }

    suspend fun storagePath(): Result<String> = call({ it }) { NoriBridge.storagePath() }

    suspend fun catalog(provider: Provider): Result<List<CatalogItem>> =
        call({ NoriJson.decodeFromString<List<CatalogItem>>(it) }) {
            NoriBridge.catalogJson(provider.raw)
        }

    suspend fun series(provider: Provider, slug: String, season: String = ""): Result<SeriesDetail> =
        call({ NoriJson.decodeFromString<SeriesDetail>(it) }) {
            NoriBridge.seriesJson(provider.raw, slug, season)
        }

    suspend fun calendar(provider: Provider): Result<CalendarPayload> =
        call({ NoriJson.decodeFromString<CalendarPayload>(it) }) {
            NoriBridge.calendarJson(provider.raw)
        }

    suspend fun watch(provider: Provider, path: String): Result<WatchInfo> =
        call({ NoriJson.decodeFromString<WatchInfo>(it) }) {
            NoriBridge.watchJson(provider.raw, path)
        }

    /**
     * Der teuerste Aufruf: Folgenseite holen, dann jeden Hoster probieren.
     * Kann leicht zehn Sekunden dauern — die Oberfläche muss das anzeigen.
     */
    suspend fun resolve(
        provider: Provider,
        path: String,
        lang: String,
        hoster: String,
    ): Result<PlaySource> =
        call({ NoriJson.decodeFromString<PlaySource>(it) }) {
            NoriBridge.resolveJson(provider.raw, path, lang, hoster)
        }

    suspend fun coverUrl(provider: Provider, path: String?): String? {
        if (path.isNullOrBlank()) return null
        return withContext(Dispatchers.IO) {
            NoriBridge.coverUrl(provider.raw, path).takeIf { it.isNotBlank() }
        }
    }

    // --- Bibliothek -------------------------------------------------------

    suspend fun library(): Result<LibrarySnapshot> =
        call({ NoriJson.decodeFromString<LibrarySnapshot>(it) }) { NoriBridge.libraryJson() }

    suspend fun toggleFavorite(slug: String, title: String, provider: Provider): Result<Boolean> =
        call({ NoriJson.parseToJsonElement(it).let { el ->
            el.toString().contains("\"favorite\":true")
        } }) {
            NoriBridge.favoriteToggle(slug, title, provider.raw)
        }

    suspend fun remember(slug: String, title: String, provider: Provider) {
        withContext(Dispatchers.IO) {
            runCatching { NoriBridge.remember(slug, title, provider.raw) }
        }
    }

    suspend fun putProgress(item: WatchProgress) {
        withContext(Dispatchers.IO) {
            runCatching { NoriBridge.progressPut(NoriJson.encodeToString(WatchProgress.serializer(), item)) }
        }
    }

    suspend fun progress(path: String, provider: Provider): WatchProgress? =
        withContext(Dispatchers.IO) {
            val raw = runCatching { NoriBridge.progressGet(path, provider.raw) }.getOrNull() ?: return@withContext null
            if (raw.trim() == "null") return@withContext null
            runCatching { NoriJson.decodeFromString<WatchProgress>(raw) }.getOrNull()
        }

    /**
     * Der Fortschritt zu vielen Folgen auf einmal.
     *
     * Ein einziger Wechsel auf den IO-Thread statt einer je Folge: die
     * Detailseite fragte vorher pro Folge einzeln, und jede Abfrage kostet
     * einen Kontextwechsel plus ein Semaphor in der Brücke. Bei einer Serie
     * mit vielen Folgen summiert sich das zu einer spürbaren Pause, bevor die
     * Liste steht.
     */
    suspend fun progressFor(paths: List<String>, provider: Provider): Map<String, WatchProgress> =
        withContext(Dispatchers.IO) {
            buildMap {
                for (path in paths) {
                    if (path.isBlank()) continue
                    val raw = runCatching { NoriBridge.progressGet(path, provider.raw) }.getOrNull() ?: continue
                    if (raw.trim() == "null") continue
                    runCatching { NoriJson.decodeFromString<WatchProgress>(raw) }
                        .getOrNull()?.let { put(path, it) }
                }
            }
        }

    suspend fun putPrefs(lang: String, hoster: String) {
        withContext(Dispatchers.IO) { runCatching { NoriBridge.prefsPut(lang, hoster) } }
    }

    /** @param what `"history"` oder `"progress"`. */
    suspend fun clear(what: String) {
        withContext(Dispatchers.IO) { runCatching { NoriBridge.libraryClear(what) } }
    }
}
