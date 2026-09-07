package to.nori.android

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Die Datentypen des Kerns, gespiegelt.
 *
 * Es sind bewusst dieselben Feldnamen wie in `Models.swift`: der Kern kodiert
 * mit `JSONEncoder` ohne Namensumwandlung, also passt `slug` auf `slug`. Wer
 * hier ein Feld umbenennt, muss es mit `@SerialName` festnageln, sonst
 * verschwindet der Wert stillschweigend — er wird nicht etwa zum Fehler.
 *
 * `ignoreUnknownKeys` steht im [NoriJson]-Format: der Kern darf Felder
 * ergänzen, ohne dass die App bricht.
 */

@Serializable
data class CatalogItem(
    val slug: String,
    val title: String,
    val alts: List<String> = emptyList(),
    val genres: List<String> = emptyList(),
    /** Erst beim Laden gestempelt, deshalb optional. */
    val provider: String? = null,
) {
    val id: String get() = "${provider ?: "?"}|$slug"
}

@Serializable
data class SeasonRef(val id: String, val label: String)

@Serializable
data class Episode(
    val number: Int,
    val germanTitle: String = "",
    val englishTitle: String = "",
    val path: String = "",
    val hosters: List<String> = emptyList(),
    val languages: List<String> = emptyList(),
) {
    /** Der Titel, der angezeigt werden sollte — deutsch vor englisch. */
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
    val provider: String? = null,
)

@Serializable
data class CalendarPayload(
    val upcoming: List<AiringEntry> = emptyList(),
    val recent: List<AiringEntry> = emptyList(),
    val fetchedAt: Double = 0.0,
)

@Serializable
data class HosterOption(
    val name: String,
    val lang: String,
    val langKey: String = "",
    val redirectPath: String = "",
)

@Serializable
data class WatchInfo(
    val path: String = "",
    val title: String = "",
    val germanTitle: String = "",
    val englishTitle: String = "",
    val hosters: List<HosterOption> = emptyList(),
)

@Serializable
data class PlaySource(
    /** `"hls"` oder `"mp4"`. */
    val kind: String,
    val url: String,
    val hoster: String = "",
    val lang: String = "",
    /**
     * Seite, von der der Stream stammt. Viele Hoster liefern das Video nur
     * aus, wenn der Abruf diesen Referer mitschickt — Media3 muss ihn
     * deshalb als Kopfzeile gesetzt bekommen, sonst kommt ein 403 statt
     * eines Videos.
     */
    val referer: String? = null,
)

@Serializable
data class WatchProgress(
    val slug: String,
    val title: String = "",
    val season: String = "",
    val episode: Int = 0,
    val episodePath: String = "",
    val germanTitle: String = "",
    val englishTitle: String = "",
    val positionSec: Double = 0.0,
    val durationSec: Double = 0.0,
    val updatedAt: Double = 0.0,
    val lang: String? = null,
    val completed: Boolean? = null,
    val provider: String? = null,
) {
    /** Dieselbe Regel wie `isEpisodeComplete` im Kern. */
    val isComplete: Boolean
        get() = completed == true || (durationSec >= 20 && positionSec >= durationSec * 0.9)

    /** Anteil zwischen 0 und 1 — für den Streifen unter dem Cover. */
    val ratio: Float
        get() = when {
            isComplete -> 1f
            durationSec < 8 -> 0f
            else -> (positionSec / durationSec).coerceIn(0.0, 1.0).toFloat()
        }

    /** Wo weitergeschaut wird, oder 0 für „von vorn". */
    val resumeAt: Double
        get() = if (isComplete || positionSec < 8) 0.0 else positionSec
}

@Serializable
data class RecentItem(
    val slug: String,
    val title: String = "",
    val viewedAt: Double = 0.0,
    val provider: String? = null,
)

@Serializable
data class LibrarySnapshot(
    val favorites: List<String> = emptyList(),
    val titles: Map<String, String> = emptyMap(),
    val recents: List<RecentItem> = emptyList(),
    val continueWatching: List<WatchProgress> = emptyList(),
    val langPref: String = "DE",
    val hosterPref: String = "VOE",
    val favoriteSource: Map<String, String> = emptyMap(),
)

/** Fehlerantwort der Brücke. Jede Funktion kann sie statt Nutzdaten liefern. */
@Serializable
data class BridgeError(@SerialName("error") val message: String)

/**
 * Die beiden Quellen.
 *
 * Kein `enum class` mit `rawValue`-Magie: die Zeichenkette geht so über JNI
 * an den Kern, und der kennt genau diese beiden Werte.
 */
enum class Provider(val raw: String, val label: String) {
    ANIWORLD("aniworld", "Anime"),
    SERIENSTREAM("serienstream", "Serien");

    companion object {
        fun from(raw: String?): Provider =
            entries.firstOrNull { it.raw == raw } ?: ANIWORLD
    }
}
