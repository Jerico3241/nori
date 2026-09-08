package de.nori

import android.app.Application
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.crossfade
import de.nori.data.Nori
import de.nori.player.NoriHttp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import okio.Path.Companion.toOkioPath

class NoriApplication : Application(), SingletonImageLoader.Factory {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        // Der Kern wird sofort und nicht erst beim ersten Bildschirm
        // hochgefahren: er liest dabei library.json, und die Startseite
        // braucht „Weiterschauen" direkt.
        scope.launch { Nori.start(this@NoriApplication) }
    }

    /**
     * Der Bild-Lader.
     *
     * Eigene Fassung statt der Voreinstellung, aus zwei Gründen: derselbe
     * OkHttp-Client wie für Video (ein Verbindungspool statt zwei) und ein
     * echter Plattenspeicher. Ohne den fragt der Katalog nach jedem Neustart
     * alle Cover erneut an — bei einigen tausend Kacheln ist das der
     * Unterschied zwischen „ist sofort da" und „baut sich eine Minute lang
     * auf".
     */
    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .components {
                add(OkHttpNetworkFetcherFactory(callFactory = { NoriHttp.client }))
            }
            .memoryCache {
                MemoryCache.Builder()
                    .maxSizePercent(context, 0.20)
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    // Coil arbeitet mit okio-Pfaden, nicht mit java.io.File.
                    .directory(cacheDir.resolve("covers").toOkioPath())
                    .maxSizeBytes(256L * 1024 * 1024)
                    .build()
            }
            .crossfade(true)
            .build()
}
