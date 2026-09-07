package de.nori.player

import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/**
 * Der HTTP-Stack für Video und Bilder.
 *
 * Ein einziger Client für beides: OkHttp teilt darüber Verbindungspool und
 * DNS-Cache, und das ist bei einer Seite voller Cover spürbar.
 *
 * Weiterleitungen sind ausdrücklich erlaubt — Hoster liefern Streams fast
 * immer über mindestens einen Sprung aus, teils auch von HTTPS auf HTTPS mit
 * anderem Host. Was Nori dabei **nicht** tut: auf HTTP zurückfallen. Der
 * Resolver im Kern lässt nur HTTPS-Ziele durch, und das darf der Player nicht
 * unterlaufen.
 */
object NoriHttp {

    val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .callTimeout(0, TimeUnit.MILLISECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .retryOnConnectionFailure(true)
            .build()
    }
}
