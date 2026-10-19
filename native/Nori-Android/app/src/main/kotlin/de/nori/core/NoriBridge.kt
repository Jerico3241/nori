package de.nori.core

/**
 * Die JNI-Grenze. Eine Methode, sonst nichts.
 *
 * Die Gegenstelle steht in `native/Nori-Android/jni/nori_jni.c` und ruft von
 * dort `nori_bridge_call` in NoriCore auf. Der Name dieser Klasse und ihres
 * Pakets ist Teil des Symbolnamens auf der C-Seite
 * (`Java_de_nori_core_NoriBridge_nativeCall`) — wird die Klasse verschoben
 * oder umbenannt, muss `nori_jni.c` mit.
 *
 * Übertragen werden **Byte-Felder**, keine Strings: `NewStringUTF` erwartet
 * modified UTF-8 und liefert bei allem jenseits der BMP — einem Emoji im
 * Serientitel etwa — Unsinn zurück.
 */
internal object NoriBridge {

    /**
     * Ein Fehlschlag hier ist nicht behebbar: ohne den Kern kann die App
     * nichts. Er wird deshalb festgehalten und beim ersten Aufruf gemeldet,
     * statt die App im `Application`-Konstruktor sterben zu lassen — so
     * bekommt der Nutzer eine Meldung statt eines Absturzes beim Start.
     */
    val loadFailure: Throwable? = runCatching {
        System.loadLibrary("NoriAndroid")
    }.exceptionOrNull()

    @JvmStatic
    external fun nativeCall(request: ByteArray): ByteArray?
}
