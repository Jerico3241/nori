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
 * Schnittstelle richtig ist. [NoriRepository] hält sich daran, und alles
 * andere sollte durch das Repository gehen statt hier direkt.
 *
 * Jede Methode gibt JSON zurück, auch im Fehlerfall: `{"error":"…"}`.
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

    /** Wohin der Kern die Bibliothek schreibt — reine Diagnose. */
    external fun storagePath(): String

    // --- Kataloge und Seiten ---------------------------------------------

    /** @param provider `"aniworld"` oder `"serienstream"`. */
    external fun catalogJson(provider: String): String

    /** @param season leer für die Vorgabestaffel. */
    external fun seriesJson(provider: String, slug: String, season: String): String

    external fun calendarJson(provider: String): String

    /** Die Hoster-Auswahl einer Folge, ohne aufzulösen. */
    external fun watchJson(provider: String, path: String): String

    /**
     * Einen abspielbaren Stream besorgen. Der teuerste Aufruf: erst die
     * Folgenseite, dann jeder Hoster der Reihe nach.
     */
    external fun resolveJson(provider: String, path: String, lang: String, hoster: String): String

    /** Vollständige Cover-Adresse aus dem Pfad, den die Quelle nennt. */
    external fun coverUrl(provider: String, path: String): String

    // --- Bibliothek -------------------------------------------------------

    external fun libraryJson(): String

    external fun favoriteToggle(slug: String, title: String, provider: String): String

    external fun remember(slug: String, title: String, provider: String): String

    external fun progressPut(json: String): String

    /** Gibt `"null"` zurück, wenn zu der Folge nichts gespeichert ist. */
    external fun progressGet(path: String, provider: String): String

    external fun prefsPut(lang: String, hoster: String): String

    /** @param what `"history"` oder `"progress"`. */
    external fun libraryClear(what: String): String
}
