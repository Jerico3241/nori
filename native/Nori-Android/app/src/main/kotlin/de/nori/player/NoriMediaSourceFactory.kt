package de.nori.player

import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import android.content.Context
import de.nori.core.PlaySource

/**
 * Die einzige Stelle, an der aus einer aufgelösten Quelle eine MediaSource
 * wird.
 *
 * Zwei Dinge entscheiden sich hier, und beide gehören zusammen:
 *
 * **Die Kopfzeilen.** Viele Hoster liefern das Video nur aus, wenn der Abruf
 * denselben `Referer` und `User-Agent` mitbringt wie der Abruf der
 * Einbettungsseite. Media3 schickt von sich aus nur seinen eigenen
 * User-Agent; ohne `setDefaultRequestProperties` kommt dann ein 403 zurück,
 * obwohl die Adresse stimmt und im Browser läuft. Deshalb ist der DataSource
 * hier **nicht** der voreingestellte, sondern einer über OkHttp mit genau den
 * Kopfzeilen, die `PlaySource` mitbringt — dieselben, mit denen der Kern die
 * Adresse gefunden hat.
 *
 * **Der Containertyp.** `.m3u8` ist HLS, `.mpd` ist DASH, alles andere wird
 * progressiv gelesen. Der Kern sagt bereits, was er gefunden hat
 * ([PlaySource.kind]); die Endung dient nur als zweite Meinung, weil manche
 * Hoster HLS unter einer Adresse ohne `.m3u8` ausliefern.
 */
object NoriMediaSourceFactory {

    /**
     * Ein DataSource-Werk für genau diese Quelle.
     *
     * `DefaultDataSource` liegt bewusst darüber: es reicht `http(s)` an
     * OkHttp weiter und beantwortet `file`/`asset`/`content` selbst. Ohne das
     * ließe sich später kein lokaler Untertitel danebenlegen.
     */
    fun dataSourceFactory(context: Context, source: PlaySource): DataSource.Factory {
        val http = OkHttpDataSource.Factory(NoriHttp.client)
            .setUserAgent(source.userAgent)
            .setDefaultRequestProperties(source.headers)
        return DefaultDataSource.Factory(context, http)
    }

    fun mediaItem(source: PlaySource): MediaItem =
        MediaItem.Builder()
            .setUri(source.url)
            .setMimeType(mimeType(source))
            .build()

    fun create(context: Context, source: PlaySource): MediaSource {
        val factory = dataSourceFactory(context, source)
        val item = mediaItem(source)

        return when (mimeType(source)) {
            MimeTypes.APPLICATION_M3U8 ->
                HlsMediaSource.Factory(factory)
                    // Ohne das liest Media3 vor dem Start ein Segment jeder
                    // Variante, um Format und Dauer zu bestimmen. Bei einem
                    // Hoster mit langsamem Erststart kostet das mehrere
                    // Sekunden, bevor überhaupt ein Bild kommt.
                    .setAllowChunklessPreparation(true)
                    .createMediaSource(item)

            MimeTypes.APPLICATION_MPD ->
                DashMediaSource.Factory(factory).createMediaSource(item)

            else ->
                ProgressiveMediaSource.Factory(factory).createMediaSource(item)
        }
    }

    private fun mimeType(source: PlaySource): String {
        val path = source.url.substringBefore('?').lowercase()
        return when {
            path.endsWith(".m3u8") || path.contains(".m3u8") -> MimeTypes.APPLICATION_M3U8
            path.endsWith(".mpd") -> MimeTypes.APPLICATION_MPD
            // Der Kern hat die Seite gelesen und weiß, was dort stand. Das
            // zählt mehr als eine fehlende Dateiendung.
            source.isHls -> MimeTypes.APPLICATION_M3U8
            path.endsWith(".mp4") || path.endsWith(".m4v") -> MimeTypes.VIDEO_MP4
            path.endsWith(".mkv") -> MimeTypes.VIDEO_MATROSKA
            path.endsWith(".webm") -> MimeTypes.VIDEO_WEBM
            else -> MimeTypes.VIDEO_MP4
        }
    }
}
