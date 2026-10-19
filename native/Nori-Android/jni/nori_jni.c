// Die JNI-Hülle um die C-Schnittstelle von NoriCore.
//
// Sie ist absichtlich winzig und enthält keine Logik: sie übersetzt zwischen
// Javas Byte-Feldern und C-Zeichenketten, sonst nichts.
//
// ## Warum Byte-Felder und keine Strings
//
// `GetStringUTFChars` und `NewStringUTF` arbeiten mit *modified UTF-8*. Das
// unterscheidet sich vom echten UTF-8 bei allem jenseits der BMP — bei einem
// Emoji in einem Serientitel kämen vier Bytes an, wo sechs erwartet werden,
// und die Antwort wäre kaputt. Byte-Felder gehen unverändert durch; kodiert
// und dekodiert wird auf beiden Seiten mit echtem UTF-8.
//
// ## Warum hier und nicht in CMake
//
// Diese Datei wird von SwiftPM zusammen mit NoriCore in dieselbe
// `libNoriAndroid.so` gebaut. Dadurch braucht der Gradle-Build weder NDK noch
// CMake — er kopiert nur die fertige Bibliothek nach `jniLibs`.
#if defined(__ANDROID__)

#include <jni.h>
#include <stdlib.h>
#include <string.h>

#include "nori_bridge.h"

JNIEXPORT jbyteArray JNICALL
Java_de_nori_core_NoriBridge_nativeCall(JNIEnv *env, jclass clazz, jbyteArray request)
{
    (void)clazz;

    if (request == NULL) {
        return NULL;
    }

    const jsize length = (*env)->GetArrayLength(env, request);
    char *input = (char *)malloc((size_t)length + 1);
    if (input == NULL) {
        return NULL;
    }
    (*env)->GetByteArrayRegion(env, request, 0, length, (jbyte *)input);
    input[length] = '\0';

    const char *reply = nori_bridge_call(input);
    free(input);

    if (reply == NULL) {
        return NULL;
    }

    const size_t replyLength = strlen(reply);
    jbyteArray out = (*env)->NewByteArray(env, (jsize)replyLength);
    if (out != NULL) {
        (*env)->SetByteArrayRegion(env, out, 0, (jsize)replyLength, (const jbyte *)reply);
    }
    nori_bridge_free((char *)reply);
    return out;
}

#endif /* __ANDROID__ */
