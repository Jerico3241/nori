package de.nori.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Die Modelle des geteilten Kerns, wie sie über die Brücke ankommen.
 *
 * Es sind bewusst **keine** eigenen Modelle: die Felder stehen genau so in
 * `native/NoriCore/Sources/NoriCore/Models.swift`, und Swifts `JSONEncoder`
 * schreibt die Namen unverändert. Kommt dort ein optionales Feld dazu, baut
 * diese Seite weiter, weil jedes Optional hier einen Standardwert hat.
 *
 * Swift lässt `nil`-Optionals beim Kodieren ganz weg. Deshalb ist jedes
 * nullable Feld hier mit `= null` vorbelegt — ohne das schlüge das Dekodieren
 * bei jedem fehlenden Feld fehl.
 */

@Serializable
enum class CatalogProvider {
    @SerialName("aniworld")
    Aniworld,

    @SerialName("serienstream")
    Serienstream;

    val label: String
        get() = when (this) {
            Aniworld -> "AniWorld"
            Serienstream -> "Serienstream"
        }

    val origin: String
        get() = when (this) {
            Aniworld -> "https://aniworld.to"
            Serienstream -> "https://serienstream.to"
        }

    /** Referer für Bildabrufe — beide Quellen schützen ihre Cover gegen Hotlinking. */
    val imageReferer: String get() = "$origin/"

    val wire: String
        get() = when (this) {
            Aniworld -> "aniworld"
            Serienstream -> "serienstream"
        }

    companion object {
        fun fromWire(raw: String?): CatalogProvider? = when (raw) {
            "aniworld" -> Aniworld
            "serienstream" -> Serienstream
            else -> null
        }
    }
}

/**
 * Was die Bibliothek zeigt. Wie im Kern ist ein Bereich nicht dasselbe wie
 * eine Quelle: K-Drama ist Serienstream, eingeschränkt auf ein Genre.
 */
@Serializable
enum class LibraryScope {
    @SerialName("all")
    All,

    @SerialName("aniworld")
    Aniworld,

    @SerialName("serienstream")
    Serienstream,

    @SerialName("kdrama")
    KDrama;

    val label: String
        get() = when (this) {
            All -> "Alle"
            Aniworld -> "Anime"
            Serienstream -> "Serien"
            KDrama -> "K-Drama"
        }

    val headline: String
        get() = when (this) {
            All -> "Alle Titel"
            Aniworld -> "Alle Anime"
            Serienstream -> "Alle Serien"
            KDrama -> "Alle K-Dramas"
        }

    val provider: CatalogProvider?
        get() = when (this) {
            All -> null
            Aniworld -> CatalogProvider.Aniworld
            Serienstream -> CatalogProvider.Serienstream
            KDrama -> CatalogProvider.Serienstream
        }

    private val genre: String?
        get() = if (this == KDrama) "K-Drama" else null

    val wire: String
        get() = when (this) {
            All -> "all"
            Aniworld -> "aniworld"
            Serienstream -> "serienstream"
            KDrama -> "kdrama"
        }

    /** Nur die Quelle — für Einträge ohne Genre (Fortschritt, Verlauf, Kalender). */
    fun includes(other: CatalogProvider?): Boolean {
        val want = provider ?: return true
        // Einträge ohne Quelle stammen aus einem älteren Stand und werden
        // nicht ausgefiltert, sonst verschwänden sie ganz.
        val actual = other ?: return true
        return want == actual
    }

    /** Quelle **und** Genre — für Katalogeinträge. */
    fun includes(item: CatalogItem): Boolean {
        if (!includes(item.provider)) return false
        val want = genre ?: return true
        return item.genres.any { it.equals(want, ignoreCase = true) }
    }
}

@Serializable
data class CatalogItem(
    val slug: String,
    val title: String,
    val alts: List<String> = emptyList(),
    val genres: List<String> = emptyList(),
    val provider: CatalogProvider? = null,
) {
    /** Zwei Quellen können denselben Slug führen. */
    val key: String get() = "${provider?.wire ?: "?"}|$slug"
}

@Serializable
data class CatalogResult(
    val items: List<CatalogItem> = emptyList(),
    val source: String = "",
    val fetchedAt: Double = 0.0,
)

@Serializable
data class SeasonRef(
    val id: String,
    val label: String,
)

@Serializable
data class Episode(
    val number: Int,
    val germanTitle: String = "",
    val englishTitle: String = "",
    val path: String = "",
    val hosters: List<String> = emptyList(),
    val languages: List<String> = emptyList(),
) {
    val key: String get() = path.ifEmpty { number.toString() }

    /** Der Titel, der angezeigt wird — deutsch bevorzugt, sonst englisch. */
    val displayTitle: String
        get() = germanTitle.ifBlank { englishTitle }.ifBlank { "Folge $number" }
}

@Serializable
data class SeriesDetail(
    val slug: String,
    val title: String,
    val alts: List<String> = emptyList(),
    val description: String = "",
    val coverPath: String? = null,
    val yearStart: String? = null,
    val yearEnd: String? = null,
    val fsk: String? = null,
    val imdb: String? = null,
    val genres: List<String> = emptyList(),
    val seasons: List<SeasonRef> = emptyList(),
    val activeSeason: String = "",
    val episodes: List<Episode> = emptyList(),
) {
    val years: String?
        get() = when {
            yearStart == null -> null
            yearEnd == null || yearEnd == yearStart -> yearStart
            else -> "$yearStart – $yearEnd"
        }
}

@Serializable
data class HosterOption(
    val name: String,
    val lang: String,
    val langKey: String,
    val redirectPath: String,
)

@Serializable
data class WatchInfo(
    val path: String,
    val title: String = "",
    val germanTitle: String = "",
    val englishTitle: String = "",
    val hosters: List<HosterOption> = emptyList(),
)

@Serializable
data class WatchProgress(
    val slug: String,
    val title: String = "",
    val season: String = "",
    val episode: Int = 1,
    val episodePath: String = "",
    val germanTitle: String = "",
    val englishTitle: String = "",
    val positionSec: Double = 0.0,
    val durationSec: Double = 0.0,
    val updatedAt: Double = 0.0,
    val lang: String? = null,
    val completed: Boolean? = null,
    val provider: CatalogProvider? = null,
) {
    /**
     * Dieselbe Regel wie `isEpisodeComplete` im Kern.
     *
     * Sie steht hier nur, damit Listen ohne Rundreise über die Brücke
     * zeichnen können — maßgeblich bleibt der Kern, und `rules.resume` fragt
     * ihn, wo es zählt (Wiedergabestart, Abschluss einer Folge).
     */
    val complete: Boolean
        get() = completed == true || (durationSec >= 20 && positionSec >= durationSec * 0.9)

    val ratio: Float
        get() = when {
            complete -> 1f
            durationSec < 8 -> 0f
            else -> (positionSec / durationSec).coerceIn(0.0, 1.0).toFloat()
        }
}

@Serializable
data class RecentItem(
    val slug: String,
    val title: String = "",
    val viewedAt: Double = 0.0,
    val provider: CatalogProvider? = null,
)

@Serializable
data class AiringEntry(
    val airingAt: Double = 0.0,
    val episode: Int = 0,
    val season: String = "",
    val title: String = "",
    val english: String? = null,
    val slug: String = "",
    val languages: List<String> = emptyList(),
    val dayKey: String = "",
    val dayLabel: String = "",
    val coverPath: String? = null,
    val provider: CatalogProvider? = null,
)

@Serializable
data class CalendarPayload(
    val upcoming: List<AiringEntry> = emptyList(),
    val recent: List<AiringEntry> = emptyList(),
    val fetchedAt: Double = 0.0,
)

@Serializable
data class EpisodeInfo(
    val title: String? = null,
    val overview: String? = null,
    val still: String? = null,
    val airDate: String? = null,
)

/**
 * Was Media3 zum Abspielen braucht.
 *
 * Die Kopfzeilen entstehen im Kern und nicht hier: User-Agent und Referer
 * müssen dieselben sein, mit denen der Stream aufgelöst wurde, sonst
 * antwortet der Hoster auf den Abruf des Videos anders als auf den der Seite.
 */
@Serializable
data class PlaySource(
    val kind: String,
    val url: String,
    val hoster: String,
    val lang: String,
    val referer: String? = null,
    val origin: String? = null,
    val userAgent: String,
    val headers: Map<String, String> = emptyMap(),
) {
    val isHls: Boolean get() = kind == "hls"
}

@Serializable
data class CoverDetails(
    val poster: String? = null,
    val backdrop: String? = null,
    val overview: String? = null,
    val rating: Double? = null,
)

@Serializable
data class CoverCandidate(
    val url: String,
    val label: String,
    val source: String,
)

@Serializable
data class NextPlay(
    val episode: Int,
    val resumeAt: Double,
    /** `play`, `resume` oder `next` — bestimmt die Beschriftung des Knopfes. */
    val kind: String,
)

@Serializable
data class SeasonStats(
    val watched: Int,
    val total: Int,
    val percent: Int,
)

@Serializable
data class ProgressRules(
    val complete: Boolean,
    val ratio: Double,
    val resumeAt: Double,
)

@Serializable
data class BridgeSetup(
    val schemaVersion: Int,
    val hasTMDBKey: Boolean,
)

/**
 * Der gesamte Bibliotheksstand.
 *
 * Jede Änderung gibt ihn frisch zurück, und die App hält davon genau eine
 * Kopie. Dadurch kann es zwischen Merkliste, Verlauf, Detailseite und Player
 * keine zwei Wahrheiten geben — der häufigste Fehler beim Nachbau einer
 * bestehenden App in Compose.
 */
@Serializable
data class LibrarySnapshot(
    val schemaVersion: Int = 0,
    val favorites: List<String> = emptyList(),
    val favoriteSource: Map<String, String> = emptyMap(),
    val recents: List<RecentItem> = emptyList(),
    val titles: Map<String, String> = emptyMap(),
    val progress: Map<String, WatchProgress> = emptyMap(),
    val langPref: String = "DE",
    val hosterPref: String = "VOE",
    val resumeEnabled: Boolean = true,
    val autoplayNext: Boolean = true,
    val playbackSpeed: Double = 1.0,
    val provider: String = "aniworld",
    val scope: String = "all",
) {
    val currentProvider: CatalogProvider
        get() = CatalogProvider.fromWire(provider) ?: CatalogProvider.Aniworld

    val currentScope: LibraryScope
        get() = when (scope) {
            "aniworld" -> LibraryScope.Aniworld
            "serienstream" -> LibraryScope.Serienstream
            "kdrama" -> LibraryScope.KDrama
            else -> LibraryScope.All
        }

    fun isFavorite(slug: String): Boolean = favorites.contains(slug)

    fun sourceOf(slug: String): CatalogProvider =
        CatalogProvider.fromWire(favoriteSource[slug]) ?: currentProvider

    /** Fortschritt zu einem Episodenpfad, nach Quelle getrennt wie im Kern. */
    fun progressFor(path: String, provider: CatalogProvider?): WatchProgress? {
        val clean = normalizeEpisodePath(path)
        progress["${provider?.wire}|$clean"]?.let { return it }
        progress[clean]?.let { return it }
        return progress.values
            .filter { normalizeEpisodePath(it.episodePath) == clean }
            .filter { provider == null || (it.provider ?: providerFromPath(it.episodePath)) == provider }
            .maxByOrNull { it.updatedAt }
    }
}

/** Wie `normalizeEpisodePath` im Kern: ohne Schema, ohne Schrägstrich am Ende. */
fun normalizeEpisodePath(raw: String): String {
    var path = raw
    if (path.startsWith("http")) {
        path = runCatching { java.net.URI(path).path ?: path }.getOrDefault(path)
    }
    return path.trimEnd('/')
}

/** Wie `providerFromPath` im Kern: der Pfadanfang entscheidet, nicht eine Heuristik. */
fun providerFromPath(path: String): CatalogProvider = when {
    path.contains("/serie/") -> CatalogProvider.Serienstream
    else -> CatalogProvider.Aniworld
}
