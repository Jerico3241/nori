// JNI-Shim: die einzige Stelle, an der Java- und C-Welt sich berühren.
//
// Warum das hier liegt und nicht im Swift-Paket: `jni.h` kommt aus dem NDK.
// Ein C-Target mit diesem Include in `native/Package.swift` würde `swift test`
// auf dem Mac zerlegen, wo es kein NDK gibt. Gradle dagegen hat das NDK
// ohnehin und übersetzt diese Datei nebenbei mit.
//
// Die Swift-Seite (native/NoriBridge/NoriBridge.swift) exportiert reines
// C-ABI — `nori_ping`, `nori_catalog_json`, `nori_free`. Hier wird daraus ein
// `jstring`, und der von Swift mit `strdup` geholte Speicher wieder
// freigegeben. Ohne das `nori_free` leckt jeder Aufruf.

#include <jni.h>
#include <stddef.h>

// Aus libNoriAndroid.so. Bewusst hier deklariert statt über einen Header:
// die drei Signaturen sind die vollständige Schnittstelle, und ein Header,
// den zwei Bausysteme finden müssten, wäre mehr Aufwand als Nutzen.
extern char *nori_ping(void);
extern char *nori_catalog_json(const char *provider);
extern void nori_free(char *pointer);

static jstring take(JNIEnv *env, char *owned) {
    if (owned == NULL) {
        return (*env)->NewStringUTF(env, "{\"error\":\"Brücke lieferte nichts\"}");
    }
    jstring result = (*env)->NewStringUTF(env, owned);
    nori_free(owned);
    return result;
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_ping(JNIEnv *env, jobject thiz) {
    (void) thiz;
    return take(env, nori_ping());
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_catalogJson(JNIEnv *env, jobject thiz, jstring provider) {
    (void) thiz;
    const char *raw = (*env)->GetStringUTFChars(env, provider, NULL);
    char *owned = nori_catalog_json(raw);
    (*env)->ReleaseStringUTFChars(env, provider, raw);
    return take(env, owned);
}
