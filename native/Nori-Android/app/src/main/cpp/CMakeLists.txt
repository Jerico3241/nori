cmake_minimum_required(VERSION 3.22.1)
project(nori_jni C)

# Der Swift-Kern kommt fertig gebaut herein — SwiftPM baut ihn, nicht CMake.
# Eingesammelt wird er von tools/build-android-core.sh nach jniLibs/<ABI>/.
set(JNI_LIBS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

add_library(NoriAndroid SHARED IMPORTED)
set_target_properties(NoriAndroid PROPERTIES
    IMPORTED_LOCATION ${JNI_LIBS_DIR}/libNoriAndroid.so)

add_library(nori_jni SHARED nori_jni.c)

find_library(log-lib log)

target_link_libraries(nori_jni NoriAndroid ${log-lib})

# Die Swift-Laufzeit liegt neben der Bibliothek im APK. Ohne diesen rpath
# sucht der Linker sie nicht dort, und die App bricht beim Laden mit
# UnsatisfiedLinkError ab — der Fehler, der nach einem fehlenden Symbol
# aussieht, aber ein fehlender Suchpfad ist.
set_target_properties(nori_jni PROPERTIES
    LINK_FLAGS "-Wl,-rpath,'$ORIGIN'")
