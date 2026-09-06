package to.nori.android

/**
 * Die Kotlin-Seite der Brücke zum Swift-Kern.
 *
 * Geladen wird nur `nori_jni`; die eigentliche `libNoriAndroid.so` und die
 * Swift-Laufzeit hängen als `NEEDED`-Einträge daran und werden vom
 * Android-Linker aus demselben Verzeichnis im APK nachgezogen.
 *
 * **Alle Methoden hier blockieren.** Auf der Swift-Seite wartet ein Semaphor
 * darauf, dass die `async`-Aufgabe fertig ist — JNI ist synchron, der Kern
 * ist es nicht. Aufrufe gehören deshalb ausnahmslos in einen
 * `Dispatchers.IO`-Kontext; vom Main-Thread aus friert sonst die Oberfläche
 * ein. Das ist keine Stilfrage, sondern die Bedingung, unter der diese
 * Schnittstelle richtig ist.
 */
object NoriBridge {

    /** Was beim Laden schiefging, oder `null`, wenn alles steht. */
    val loadError: String?

    init {
        loadError = try {
            System.loadLibrary("nori_jni")
            null
        } catch (t: Throwable) {
            // Nicht werfen: eine App, die beim Start abstürzt, sagt dem
            // Nutzer nichts. Der Fehler gehört auf den Bildschirm.
            t.message ?: t.toString()
        }
    }

    /**
     * Lebenszeichen ohne Netzzugriff.
     *
     * Geht das durch, sind Bibliothek, Swift-Laufzeit und JNI in Ordnung.
     * Genau das will man zuerst wissen, wenn etwas nicht lädt.
     */
    external fun ping(): String

    /**
     * Den Katalog einer Quelle als JSON.
     *
     * @param provider `"aniworld"` oder `"serienstream"`.
     */
    external fun catalogJson(provider: String): String
}
