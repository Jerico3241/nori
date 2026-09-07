// JNI-Shim: die einzige Stelle, an der Java- und C-Welt sich berühren.
//
// Warum das hier liegt und nicht im Swift-Paket: `jni.h` kommt aus dem NDK.
// Ein C-Target mit diesem Include in `native/Package.swift` würde `swift test`
// auf dem Mac zerlegen, wo es kein NDK gibt. Gradle dagegen hat das NDK
// ohnehin und übersetzt diese Datei nebenbei mit.
//
// Die Swift-Seite (native/NoriBridge/NoriBridge.swift) exportiert reines
// C-ABI. Hier wird daraus ein `jstring`, und der von Swift mit `strdup`
// geholte Speicher wieder freigegeben. Ohne das `nori_free` leckt jeder
// Aufruf — und zwar um die Größe eines ganzen Katalogs, nicht um ein paar
// Bytes.

#include <jni.h>
#include <stddef.h>

// Aus libNoriAndroid.so. Bewusst hier deklariert statt über einen Header:
// die Signaturen sind die vollständige Schnittstelle, und ein Header, den
// zwei Bausysteme finden müssten, wäre mehr Aufwand als Nutzen.
extern char *nori_ping(void);
extern char *nori_storage_path(void);
extern char *nori_catalog_json(const char *provider);
extern char *nori_series_json(const char *provider, const char *slug, const char *season);
extern char *nori_calendar_json(const char *provider);
extern char *nori_resolve_json(const char *provider, const char *path, const char *lang, const char *hoster);
extern char *nori_watch_json(const char *provider, const char *path);
extern char *nori_cover_url(const char *provider, const char *path);
extern char *nori_library_json(void);
extern char *nori_favorite_toggle(const char *slug, const char *title, const char *provider);
extern char *nori_remember(const char *slug, const char *title, const char *provider);
extern char *nori_progress_put(const char *json);
extern char *nori_progress_get(const char *path, const char *provider);
extern char *nori_prefs_put(const char *lang, const char *hoster);
extern char *nori_library_clear(const char *what);
extern void nori_free(char *pointer);

// Ein von Swift geliehener String wird zu einem jstring — und der Speicher
// dahinter sofort wieder frei.
static jstring take(JNIEnv *env, char *owned) {
    if (owned == NULL) {
        return (*env)->NewStringUTF(env, "{\"error\":\"Brücke lieferte nichts\"}");
    }
    jstring result = (*env)->NewStringUTF(env, owned);
    nori_free(owned);
    return result;
}

// Java-Strings sind nicht zwingend gültiges UTF-8 für C, und NULL ist
// erlaubt. Beides hier einmal abfangen, statt in jeder Funktion.
#define BORROW(name, jstr) \
    const char *name = ((jstr) == NULL) ? NULL : (*env)->GetStringUTFChars(env, (jstr), NULL); \
    const char *name##_safe = (name == NULL) ? "" : name

#define RETURN_BORROWED(jstr, name) \
    if (name != NULL) (*env)->ReleaseStringUTFChars(env, (jstr), name)

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_ping(JNIEnv *env, jobject thiz) {
    (void) thiz;
    return take(env, nori_ping());
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_storagePath(JNIEnv *env, jobject thiz) {
    (void) thiz;
    return take(env, nori_storage_path());
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_catalogJson(JNIEnv *env, jobject thiz, jstring provider) {
    (void) thiz;
    BORROW(p, provider);
    jstring out = take(env, nori_catalog_json(p_safe));
    RETURN_BORROWED(provider, p);
    return out;
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_seriesJson(JNIEnv *env, jobject thiz, jstring provider, jstring slug, jstring season) {
    (void) thiz;
    BORROW(p, provider);
    BORROW(s, slug);
    BORROW(se, season);
    jstring out = take(env, nori_series_json(p_safe, s_safe, se_safe));
    RETURN_BORROWED(season, se);
    RETURN_BORROWED(slug, s);
    RETURN_BORROWED(provider, p);
    return out;
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_calendarJson(JNIEnv *env, jobject thiz, jstring provider) {
    (void) thiz;
    BORROW(p, provider);
    jstring out = take(env, nori_calendar_json(p_safe));
    RETURN_BORROWED(provider, p);
    return out;
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_resolveJson(JNIEnv *env, jobject thiz, jstring provider, jstring path, jstring lang, jstring hoster) {
    (void) thiz;
    BORROW(p, provider);
    BORROW(pa, path);
    BORROW(l, lang);
    BORROW(h, hoster);
    jstring out = take(env, nori_resolve_json(p_safe, pa_safe, l_safe, h_safe));
    RETURN_BORROWED(hoster, h);
    RETURN_BORROWED(lang, l);
    RETURN_BORROWED(path, pa);
    RETURN_BORROWED(provider, p);
    return out;
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_watchJson(JNIEnv *env, jobject thiz, jstring provider, jstring path) {
    (void) thiz;
    BORROW(p, provider);
    BORROW(pa, path);
    jstring out = take(env, nori_watch_json(p_safe, pa_safe));
    RETURN_BORROWED(path, pa);
    RETURN_BORROWED(provider, p);
    return out;
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_coverUrl(JNIEnv *env, jobject thiz, jstring provider, jstring path) {
    (void) thiz;
    BORROW(p, provider);
    BORROW(pa, path);
    jstring out = take(env, nori_cover_url(p_safe, pa_safe));
    RETURN_BORROWED(path, pa);
    RETURN_BORROWED(provider, p);
    return out;
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_libraryJson(JNIEnv *env, jobject thiz) {
    (void) thiz;
    return take(env, nori_library_json());
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_favoriteToggle(JNIEnv *env, jobject thiz, jstring slug, jstring title, jstring provider) {
    (void) thiz;
    BORROW(s, slug);
    BORROW(t, title);
    BORROW(p, provider);
    jstring out = take(env, nori_favorite_toggle(s_safe, t_safe, p_safe));
    RETURN_BORROWED(provider, p);
    RETURN_BORROWED(title, t);
    RETURN_BORROWED(slug, s);
    return out;
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_remember(JNIEnv *env, jobject thiz, jstring slug, jstring title, jstring provider) {
    (void) thiz;
    BORROW(s, slug);
    BORROW(t, title);
    BORROW(p, provider);
    jstring out = take(env, nori_remember(s_safe, t_safe, p_safe));
    RETURN_BORROWED(provider, p);
    RETURN_BORROWED(title, t);
    RETURN_BORROWED(slug, s);
    return out;
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_progressPut(JNIEnv *env, jobject thiz, jstring json) {
    (void) thiz;
    BORROW(j, json);
    jstring out = take(env, nori_progress_put(j_safe));
    RETURN_BORROWED(json, j);
    return out;
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_progressGet(JNIEnv *env, jobject thiz, jstring path, jstring provider) {
    (void) thiz;
    BORROW(pa, path);
    BORROW(p, provider);
    jstring out = take(env, nori_progress_get(pa_safe, p_safe));
    RETURN_BORROWED(provider, p);
    RETURN_BORROWED(path, pa);
    return out;
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_prefsPut(JNIEnv *env, jobject thiz, jstring lang, jstring hoster) {
    (void) thiz;
    BORROW(l, lang);
    BORROW(h, hoster);
    jstring out = take(env, nori_prefs_put(l_safe, h_safe));
    RETURN_BORROWED(hoster, h);
    RETURN_BORROWED(lang, l);
    return out;
}

JNIEXPORT jstring JNICALL
Java_to_nori_android_NoriBridge_libraryClear(JNIEnv *env, jobject thiz, jstring what) {
    (void) thiz;
    BORROW(w, what);
    jstring out = take(env, nori_library_clear(w_safe));
    RETURN_BORROWED(what, w);
    return out;
}
