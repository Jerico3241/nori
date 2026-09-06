#!/bin/bash
# Baut den geteilten Swift-Kern für Android und legt ihn samt Swift-Laufzeit
# dort ab, wo Gradle ihn ins APK packt.
#
#   tools/build-android-core.sh [debug|release]
#
# Warum ein Skript und nicht Gradle: Gradle baut kein Swift. SwiftPM erzeugt
# `libNoriAndroid.so`, Gradle übersetzt nur den JNI-Shim daneben und packt
# beides ein. Diese Trennung ist Absicht — sie hält das Android-Projekt frei
# von Swift-Wissen.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE="$ROOT/native"
ABI="arm64-v8a"
TRIPLE="aarch64-unknown-linux-android28"
DEST="$NATIVE/Nori-Android/app/src/main/jniLibs/$ABI"

fail() { echo "::error::$1" >&2; shift; for l in "$@"; do echo "  $l" >&2; done; exit 1; }

# Die Werkzeugprüfung liegt im eigenen Skript — dieselbe Lehre wie überall
# hier: erst prüfen, dann bauen, sonst sieht ein fehlendes SDK aus wie ein
# Fehler im Quelltext.
"$ROOT/tools/require-swift-android.sh" >/dev/null

SDK_BUNDLE="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle"
RUNTIME="$SDK_BUNDLE/swift-android/swift-resources/usr/lib/swift-aarch64/android"
[ -d "$RUNTIME" ] || fail "Swift-Laufzeit für aarch64 nicht gefunden." "Erwartet in $RUNTIME"

# Das Tripel **als** SDK-Bezeichner, nicht über --triple.
#
# `--triple aarch64-… --swift-sdk <bundle>` sieht richtig aus, ist es aber
# nicht: SwiftPM übernimmt dann zwar das Ziel, zieht die Swift-Ressourcen
# aber weiter aus dem armv7-Verzeichnis und bricht mit „could not find module
# 'Swift' for target" ab. Ohne jede Angabe wiederum wählt es irgendein Tripel
# des Bundles — beobachtet wurden armv7 und x86_64 im Wechsel.
#
# `-soname` ist nicht optional.
#
# Ohne SONAME schreibt der Linker in jede Bibliothek, die dagegen linkt, den
# **Pfad**, unter dem er sie beim Bauen gefunden hat — hier also einen
# absoluten Pfad auf dem Mac. Auf dem Gerät gibt es den nicht, und die App
# stirbt beim Start mit „dlopen failed: library /Users/... not found".
# Die Swift-Laufzeitbibliotheken bringen ihr SONAME mit, diese hier nicht.
echo "Baue NoriAndroid für $TRIPLE ($CONFIG) …"
( cd "$NATIVE" && swift build \
    --product NoriAndroid \
    --swift-sdk "$TRIPLE" \
    --configuration "$CONFIG" \
    -Xlinker -soname -Xlinker libNoriAndroid.so )

BUILT="$NATIVE/.build/$TRIPLE/$CONFIG/libNoriAndroid.so"
[ -f "$BUILT" ] || fail "libNoriAndroid.so wurde nicht erzeugt." "Erwartet: $BUILT"

mkdir -p "$DEST"
rm -f "$DEST"/*.so
cp "$BUILT" "$DEST/"

# Die Swift-Laufzeit muss mit ins APK: Android hat sie nicht, anders als
# Apple, wo sie zum Betriebssystem gehört. Kopiert wird, was libNoriAndroid.so
# als NEEDED führt — nicht alles, sonst wüchse das APK um Testbibliotheken,
# die niemand lädt.
# Ohne `-type f`: llvm-readelf ist im NDK ein Symlink auf llvm-readobj, und
# `-type f` findet ihn deshalb nicht. Der Rückfall unten kopierte daraufhin
# die vollständige Laufzeit — samt libXCTest.so und libTesting.so, die in
# einer App nichts verloren haben. 114 MB statt 40.
FOUND_READELF="$(find "${ANDROID_NDK_HOME:-/opt/homebrew/share/android-commandlinetools/ndk}" \
    -name llvm-readelf 2>/dev/null | head -1)"
NDK_BIN="${FOUND_READELF:+$(dirname "$FOUND_READELF")}"
if [ -n "$NDK_BIN" ] && [ -x "$NDK_BIN/llvm-readelf" ]; then
    NEEDED="$("$NDK_BIN/llvm-readelf" -d "$BUILT" | awk '/NEEDED/ {gsub(/[\[\]]/,"",$NF); print $NF}')"
else
    NEEDED="$(ls "$RUNTIME" | grep '\.so$')"
fi

# Zwei Fundorte, nicht einer: die Swift-Laufzeit liegt im SDK-Bundle,
# `libc++_shared.so` dagegen im NDK. Letztere hängt an libswiftObservation.so,
# und ohne sie stirbt die App beim Start mit
# „dlopen failed: library libc++_shared.so not found".
NDK_SYSROOT_LIB="$(dirname "$(find "${ANDROID_NDK_HOME}" -name libc++_shared.so -path "*aarch64-linux-android*" 2>/dev/null | head -1)")"

find_lib() {
    if [ -f "$RUNTIME/$1" ]; then echo "$RUNTIME/$1"
    elif [ -n "$NDK_SYSROOT_LIB" ] && [ -f "$NDK_SYSROOT_LIB/$1" ]; then echo "$NDK_SYSROOT_LIB/$1"
    fi
}

COPIED=0
for lib in $NEEDED; do
    src="$(find_lib "$lib")"
    if [ -n "$src" ]; then
        cp "$src" "$DEST/"
        COPIED=$((COPIED + 1))
    fi
done

# Transitiv: die Laufzeitbibliotheken hängen ihrerseits aneinander.
for round in 1 2 3; do
    for so in "$DEST"/*.so; do
        [ -f "$so" ] || continue
        if [ -x "${NDK_BIN:-}/llvm-readelf" ]; then
            for dep in $("$NDK_BIN/llvm-readelf" -d "$so" | awk '/NEEDED/ {gsub(/[\[\]]/,"",$NF); print $NF}'); do
                if [ ! -f "$DEST/$dep" ]; then
                    src="$(find_lib "$dep")"
                    if [ -n "$src" ]; then
                        cp "$src" "$DEST/"
                        COPIED=$((COPIED + 1))
                    fi
                fi
            done
        fi
    done
done

echo "Fertig: $DEST"
ls -1 "$DEST" | sed 's/^/  /'
echo "  ($(ls -1 "$DEST" | wc -l | tr -d ' ') Bibliotheken, $(du -sh "$DEST" | cut -f1))"
