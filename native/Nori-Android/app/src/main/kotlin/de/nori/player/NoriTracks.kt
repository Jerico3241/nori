package de.nori.player

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import java.util.Locale

/**
 * Ein auswählbarer Ton-, Untertitel- oder Bildkanal.
 *
 * Bewusst eine eigene Form und nicht Media3s [Tracks.Group]: die Oberfläche
 * soll eine Liste mit Beschriftung und Häkchen zeigen, nicht mit
 * Renderer-Indizes hantieren.
 */
data class NoriTrack(
    val id: String,
    val label: String,
    val selected: Boolean,
    val groupIndex: Int,
    val trackIndex: Int,
)

/** Die drei Kanalarten, die der Player anbietet. */
enum class NoriTrackType(val media3: Int) {
    Audio(C.TRACK_TYPE_AUDIO),
    Text(C.TRACK_TYPE_TEXT),
    Video(C.TRACK_TYPE_VIDEO),
}

/**
 * Liest die Kanäle aus dem Player und schaltet zwischen ihnen um.
 *
 * Untertitel und Tonspuren kommen bei HLS erst mit der Wiedergabeliste an —
 * beim Start ist die Liste deshalb leer und füllt sich, sobald Media3
 * `onTracksChanged` meldet. Eine Auswahl vor diesem Zeitpunkt gibt es nicht,
 * und die Oberfläche darf das nicht als „keine Untertitel vorhanden" zeigen.
 */
object NoriTrackReader {

    fun read(tracks: Tracks, type: NoriTrackType): List<NoriTrack> {
        val out = mutableListOf<NoriTrack>()
        tracks.groups.forEachIndexed { groupIndex, group ->
            if (group.type != type.media3) return@forEachIndexed
            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSupported(trackIndex)) continue
                val format = group.getTrackFormat(trackIndex)
                out += NoriTrack(
                    id = format.id ?: "$groupIndex:$trackIndex",
                    label = label(format, type, out.size),
                    selected = group.isTrackSelected(trackIndex),
                    groupIndex = groupIndex,
                    trackIndex = trackIndex,
                )
            }
        }
        return out
    }

    /**
     * Eine Beschriftung, die ein Mensch lesen kann.
     *
     * Reihenfolge: was der Stream selbst mitgibt, dann der Sprachname, dann
     * die Auflösung. Bleibt alles leer, wird durchnummeriert — besser als
     * eine Zeile ohne Text.
     */
    private fun label(format: Format, type: NoriTrackType, index: Int): String {
        format.label?.takeIf { it.isNotBlank() }?.let { return it }

        val language = format.language
            ?.takeIf { it.isNotBlank() && it != C.LANGUAGE_UNDETERMINED }
            ?.let { tag ->
                val locale = Locale.forLanguageTag(tag)
                locale.getDisplayLanguage(Locale.GERMAN).takeIf { it.isNotBlank() } ?: tag
            }

        return when (type) {
            NoriTrackType.Video -> {
                val height = format.height.takeIf { it > 0 }
                val rate = format.bitrate.takeIf { it > 0 }?.let { " · ${it / 1000} kbit/s" } ?: ""
                if (height != null) "${height}p$rate" else language ?: "Qualität ${index + 1}"
            }

            NoriTrackType.Audio -> {
                val channels = when (format.channelCount) {
                    1 -> " · Mono"
                    2 -> " · Stereo"
                    in 3..Int.MAX_VALUE -> " · ${format.channelCount} Kanäle"
                    else -> ""
                }
                (language ?: "Tonspur ${index + 1}") + channels
            }

            NoriTrackType.Text -> language ?: "Untertitel ${index + 1}"
        }
    }

    /** Genau diesen Kanal auswählen. */
    fun select(player: Player, tracks: Tracks, track: NoriTrack, type: NoriTrackType) {
        val group = tracks.groups.getOrNull(track.groupIndex) ?: return
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(type.media3, false)
            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, track.trackIndex))
            .build()
    }

    /**
     * Zurück auf automatisch.
     *
     * Bei Bild heißt das: Media3 wählt die Qualität nach Bandbreite. Bei
     * Untertiteln heißt es: aus — eine automatische Untertitelwahl wäre in
     * einer App mit deutschem Ton eine Überraschung.
     */
    fun reset(player: Player, type: NoriTrackType, disable: Boolean) {
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .clearOverridesOfType(type.media3)
            .setTrackTypeDisabled(type.media3, disable)
            .build()
    }
}
