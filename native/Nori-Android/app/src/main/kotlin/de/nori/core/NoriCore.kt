package de.nori.core

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.serializer
import android.util.Log

/**
 * Der getippte Zugang zu NoriCore.
 *
 * Alles, was Nori über Kataloge, Serien, Hoster, Streams und die Bibliothek
 * weiß, kommt durch dieses Objekt. Es gibt in dieser App bewusst **keine**
 * zweite Implementierung davon: kein Kotlin-Parser für AniWorld, keine
 * eigenen Fortschrittsregeln, keine parallele Bibliotheksdatei.
 *
 * Jeder Aufruf blockiert einen Thread auf der C-Seite, solange der Kern
 * arbeitet. Deshalb läuft alles auf [Dispatchers.IO] — und mit einem Deckel,
 * damit ein Katalog mit tausenden Kacheln nicht 64 Threads gleichzeitig auf
 * die Quelle loslässt.
 */
object NoriCore {

    private const val TAG = "NoriCore"

    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
    }

    /** Gleichzeitige Aufrufe. Der Kern deckelt TMDB selbst auf vier. */
    private val gate = Semaphore(12)

    private var dispatcher: CoroutineDispatcher = Dispatchers.IO

    @Volatile
    private var ready = false

    // MARK: Einrichtung

    /**
     * Muss vor allem anderen laufen.
     *
     * Der Kern legt `library.json`, `covers.json` und `episodes.json` ab, und
     * wo das auf Android ist, weiß nur die App. Auf Apple kommt der Ort aus
     * `applicationSupportDirectory`; dort gibt es das hier nicht.
     */
    suspend fun setUp(dataDir: String): BridgeSetup {
        NoriBridge.loadFailure?.let {
            throw NoriException(
                NoriErrorKind.Bridge,
                "Der native Kern konnte nicht geladen werden. Fehlt libNoriAndroid.so für diese CPU?",
                it,
            )
        }
        val result = request<BridgeSetup>("init") { put("dataDir", dataDir) }
        ready = true
        Log.i(TAG, "Kern bereit, Bibliotheksschema v${result.schemaVersion}, TMDB=${result.hasTMDBKey}")
        return result
    }

    val isReady: Boolean get() = ready

    // MARK: Katalog und Metadaten

    suspend fun catalog(provider: CatalogProvider, force: Boolean = false): CatalogResult =
        request("catalog") {
            put("provider", provider.wire)
            put("force", force)
        }

    suspend fun series(provider: CatalogProvider, slug: String, season: String? = null): SeriesDetail =
        request("series") {
            put("provider", provider.wire)
            put("slug", slug)
            season?.let { put("season", it) }
        }

    suspend fun watch(provider: CatalogProvider, path: String): WatchInfo =
        request("watch") {
            put("provider", provider.wire)
            put("path", path)
        }

    suspend fun calendar(provider: CatalogProvider, force: Boolean = false): CalendarPayload =
        request("calendar") {
            put("provider", provider.wire)
            put("force", force)
        }

    // MARK: Bilder und Beschreibungen

    /** Was schon dasteht — ohne Netz, für den ersten Aufbau einer Liste. */
    suspend fun coverCached(slug: String): CoverDetails =
        request("coverCached") { put("slug", slug) }

    /** Wie [coverCached], sucht bei Bedarf aber bei TMDB nach. */
    suspend fun coverDetails(slug: String, title: String, provider: CatalogProvider): CoverDetails =
        request("coverDetails") {
            put("slug", slug)
            put("title", title)
            put("provider", provider.wire)
        }

    /**
     * Letzter Ausweg: die Detailseite der Quelle lesen.
     *
     * Die Adresse eines Covers lässt sich nicht aus dem Slug bilden — beide
     * Quellen hängen einen Zufallsanteil an den Dateinamen. Das kostet eine
     * Seite pro Titel, aber nur einmal.
     */
    suspend fun coverFromSource(slug: String, provider: CatalogProvider): String? =
        request<Map<String, String?>>("coverSource") {
            put("slug", slug)
            put("provider", provider.wire)
        }["url"]

    suspend fun coverCandidates(title: String, provider: CatalogProvider): List<CoverCandidate> =
        request("coverCandidates") {
            put("title", title)
            put("provider", provider.wire)
        }

    suspend fun setCoverOverride(slug: String, url: String?) {
        request<JsonObject>("coverOverride") {
            put("slug", slug)
            url?.let { put("url", it) }
        }
    }

    suspend fun episodeInfo(
        slug: String,
        title: String,
        alternates: List<String>,
        season: String,
        provider: CatalogProvider,
    ): Map<Int, EpisodeInfo> {
        val raw: Map<String, EpisodeInfo> = request("episodeInfo") {
            put("slug", slug)
            put("title", title)
            put("season", season)
            put("provider", provider.wire)
            put("alternates", json.encodeToJsonElement(alternates))
        }
        return raw.mapNotNull { (key, value) -> key.toIntOrNull()?.let { it to value } }.toMap()
    }

    // MARK: Wiedergabequelle

    /**
     * Der eigentliche Beweis der Portierung.
     *
     * Aus den Hostern einer Folge wird eine abspielbare Adresse samt der
     * Kopfzeilen, die Media3 mitschicken muss. Sprachwahl und Reihenfolge
     * entscheidet der Kern.
     */
    suspend fun resolveBest(
        hosters: List<HosterOption>,
        preferredHoster: String,
        preferredLang: String,
        episodePath: String,
        provider: CatalogProvider,
    ): PlaySource = request("resolve") {
        put("hosters", json.encodeToJsonElement(hosters))
        put("preferredHoster", preferredHoster)
        put("preferredLang", preferredLang)
        put("episodePath", episodePath)
        put("provider", provider.wire)
    }

    /** Genau dieser Hoster — für den Wechsel während der Wiedergabe. */
    suspend fun resolveOne(
        hoster: HosterOption,
        episodePath: String,
        provider: CatalogProvider,
    ): PlaySource = request("resolveOne") {
        put("hoster", json.encodeToJsonElement(hoster))
        put("episodePath", episodePath)
        put("provider", provider.wire)
    }

    /** Dieselbe Reihenfolge, die [resolveBest] durchgeht — für die Liste im Player. */
    suspend fun hosterOrder(
        hosters: List<HosterOption>,
        preferredHoster: String?,
        preferredLang: String,
    ): List<HosterOption> = request("hosterOrder") {
        put("hosters", json.encodeToJsonElement(hosters))
        preferredHoster?.let { put("preferredHoster", it) }
        put("preferredLang", preferredLang)
    }

    // MARK: Bibliothek

    suspend fun librarySnapshot(): LibrarySnapshot = request("library.snapshot")

    suspend fun toggleFavorite(slug: String, title: String?): LibrarySnapshot =
        request("library.toggleFavorite") {
            put("slug", slug)
            title?.let { put("title", it) }
        }

    suspend fun remember(slug: String, title: String, provider: CatalogProvider): LibrarySnapshot =
        request("library.remember") {
            put("slug", slug)
            put("title", title)
            put("provider", provider.wire)
        }

    suspend fun upsertProgress(progress: WatchProgress): LibrarySnapshot =
        request("library.upsertProgress") {
            put("progress", json.encodeToJsonElement(progress))
        }

    suspend fun setPreferences(
        langPref: String? = null,
        hosterPref: String? = null,
        resumeEnabled: Boolean? = null,
        autoplayNext: Boolean? = null,
        playbackSpeed: Float? = null,
        provider: CatalogProvider? = null,
        scope: LibraryScope? = null,
    ): LibrarySnapshot = request("library.setPreferences") {
        langPref?.let { put("langPref", it) }
        hosterPref?.let { put("hosterPref", it) }
        resumeEnabled?.let { put("resumeEnabled", it) }
        autoplayNext?.let { put("autoplayNext", it) }
        playbackSpeed?.let { put("playbackSpeed", it.toDouble()) }
        provider?.let { put("provider", it.wire) }
        scope?.let { put("scope", it.wire) }
    }

    suspend fun clearHistory(): LibrarySnapshot = request("library.clearHistory")

    suspend fun clearProgress(): LibrarySnapshot = request("library.clearProgress")

    suspend fun continueWatching(): List<WatchProgress> = request("library.continueWatching")

    suspend fun nextPlay(
        slug: String,
        season: String,
        episodes: List<Episode>,
        provider: CatalogProvider,
    ): NextPlay = request("library.nextPlay") {
        put("slug", slug)
        put("season", season)
        put("episodes", json.encodeToJsonElement(episodes))
        put("provider", provider.wire)
    }

    suspend fun seasonStats(
        slug: String,
        season: String,
        episodes: List<Episode>,
        provider: CatalogProvider,
    ): SeasonStats = request("library.seasonStats") {
        put("slug", slug)
        put("season", season)
        put("episodes", json.encodeToJsonElement(episodes))
        put("provider", provider.wire)
    }

    /**
     * Die Fortschrittsregeln des Kerns.
     *
     * „Ab 90 % gilt als gesehen" und „unter 8 Sekunden ist kein Resume" sind
     * keine Anzeigedetails, sondern Regeln. Sie werden hier gefragt und nicht
     * nachgebaut, damit sie nicht an zwei Stellen auseinanderlaufen können.
     */
    suspend fun progressRules(progress: WatchProgress?): ProgressRules = request("rules.resume") {
        progress?.let { put("progress", json.encodeToJsonElement(it)) }
    }

    // MARK: Aufrufmechanik

    private suspend inline fun <reified T> request(
        op: String,
        noinline body: JsonObjectBuilder.() -> Unit = {},
    ): T = requestWith(op, buildJsonObject(body), serializer())

    @PublishedApi
    internal suspend fun <T> requestWith(
        op: String,
        params: JsonObject,
        deserializer: DeserializationStrategy<T>,
    ): T = gate.withPermit {
        withContext(dispatcher) {
            val payload = buildJsonObject {
                put("op", op)
                params.forEach { (key, value) -> put(key, value) }
            }
            val requestBytes = json.encodeToString(JsonObject.serializer(), payload)
                .toByteArray(Charsets.UTF_8)

            val responseBytes = try {
                NoriBridge.nativeCall(requestBytes)
            } catch (error: UnsatisfiedLinkError) {
                throw NoriException(NoriErrorKind.Bridge, "Der native Kern fehlt in dieser APK.", error)
            } ?: throw NoriException(NoriErrorKind.Bridge, "Der Kern lieferte auf '$op' keine Antwort.")

            val root = try {
                json.parseToJsonElement(String(responseBytes, Charsets.UTF_8)).jsonObject
            } catch (error: Exception) {
                throw NoriException(NoriErrorKind.Bridge, "Antwort auf '$op' ist kein JSON.", error)
            }

            if (root["ok"]?.jsonPrimitive?.content != "true") {
                val error = root["error"]?.jsonObject
                throw NoriException(
                    NoriErrorKind.fromWire(error?.get("kind")?.jsonPrimitive?.content),
                    error?.get("message")?.jsonPrimitive?.content ?: "Unbekannter Fehler bei '$op'.",
                )
            }

            val data = root["data"] ?: throw NoriException(
                NoriErrorKind.Bridge,
                "Antwort auf '$op' hat keine Nutzdaten.",
            )
            try {
                json.decodeFromJsonElement(deserializer, data)
            } catch (error: Exception) {
                throw NoriException(NoriErrorKind.Bridge, "Antwort auf '$op' passt nicht: ${error.message}", error)
            }
        }
    }
}
