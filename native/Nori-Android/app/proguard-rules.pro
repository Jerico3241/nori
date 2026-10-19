# Die Brücke wird über JNI gerufen, nicht aus Kotlin heraus. R8 sieht deshalb
# keinen Aufrufer und würde die Methode entfernen — die App startet dann und
# stirbt beim ersten Aufruf an „no implementation found for nativeCall".
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
-keep class de.nori.core.NoriBridge { *; }

# kotlinx.serialization erzeugt Serializer über generierte Companion-Objekte
# und findet sie zur Laufzeit über Reflection auf den Klassennamen.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class de.nori.core.**$$serializer { *; }
-keepclassmembers class de.nori.core.** {
    *** Companion;
}
-keepclasseswithmembers class de.nori.core.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Media3 lädt Renderer und Extraktoren teils über Reflection.
-dontwarn androidx.media3.**
-keep class androidx.media3.exoplayer.hls.HlsMediaSource$Factory { *; }
-keep class androidx.media3.exoplayer.dash.DashMediaSource$Factory { *; }

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
