package de.nori.core

/**
 * Fehlerklassen, wie der Kern sie unterscheidet.
 *
 * Die Oberfläche soll „kein Netz" von „dieser Hoster liefert nichts" trennen
 * können, ohne die Meldung zu lesen — die ist deutsch und für Menschen, nicht
 * für `when`-Zweige.
 */
enum class NoriErrorKind {
    Network,
    Parse,
    Blocked,
    NotFound,
    Hoster,
    Bridge,
    Unknown;

    companion object {
        fun fromWire(raw: String?): NoriErrorKind = when (raw) {
            "network" -> Network
            "parse" -> Parse
            "blocked" -> Blocked
            "notFound" -> NotFound
            "hoster" -> Hoster
            "bridge" -> Bridge
            else -> Unknown
        }
    }
}

class NoriException(
    val kind: NoriErrorKind,
    override val message: String,
    override val cause: Throwable? = null,
) : Exception(message, cause)

/**
 * Was dem Nutzer gezeigt wird.
 *
 * Kein Stacktrace, keine Klassennamen. Die Meldungen des Kerns sind bereits
 * deutsch und beschreiben die Ursache; ergänzt wird nur, was auf Android
 * dazukommt.
 */
fun Throwable.userMessage(): String = when (this) {
    is NoriException -> when (kind) {
        NoriErrorKind.Network -> "Keine Verbindung zur Quelle. $message"
        NoriErrorKind.Blocked -> "Die Quelle hat die Anfrage abgewiesen. $message"
        NoriErrorKind.NotFound -> message
        NoriErrorKind.Parse -> "Die Seite der Quelle sieht anders aus als erwartet. $message"
        NoriErrorKind.Hoster -> message
        NoriErrorKind.Bridge -> "Interner Fehler in der Verbindung zum Kern. $message"
        NoriErrorKind.Unknown -> message
    }

    is java.net.UnknownHostException -> "Kein Netzwerk."
    is java.net.SocketTimeoutException -> "Zeitüberschreitung — die Quelle antwortet nicht."
    else -> message ?: "Unbekannter Fehler."
}
