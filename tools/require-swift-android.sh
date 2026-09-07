#!/bin/bash
# Prüft, dass auf dem Runner ein Swift-SDK für Android eingerichtet ist — und
# sagt bei einem Fehlschlag, was zu tun ist.
#
#   tools/require-swift-android.sh
#
# Warum das nötig ist: Der Android-Durchbau des geteilten Kerns braucht neben
# der Swift-Toolchain ein quergebautes SDK, das nicht mit Xcode kommt. Fehlt
# es, bricht `swift build --swift-sdk` mit einer Meldung ab, die nach einem
# Fehler im Quelltext aussieht, obwohl nur das SDK fehlt. Dieselbe Lehre wie
# bei require-xcode.sh: erst die Werkzeuge prüfen, dann bauen.
set -euo pipefail

fail() {
    echo "::error::$1"
    shift
    for line in "$@"; do
        echo "  $line" >&2
    done
    exit 1
}

if ! command -v swift >/dev/null 2>&1; then
    fail "Keine Swift-Toolchain gefunden." \
        "Erwartet wird 'swift' im Pfad." \
        "Auf einem Mac mit Xcode: sudo xcode-select -s /Applications/Xcode.app"
fi

# Welche SDKs kennt die Toolchain? Ohne installiertes Android-SDK ist die
# Liste leer beziehungsweise enthält nur Apple-Ziele.
if ! LIST="$(swift sdk list 2>&1)"; then
    fail "'swift sdk list' lässt sich nicht ausführen." \
        "Meldung: $LIST" \
        "Die Swift-Version ist vermutlich zu alt — Swift-SDKs gibt es ab 5.9."
fi

if ! printf '%s' "$LIST" | grep -qi "android"; then
    fail "Kein Swift-SDK für Android installiert." \
        "Gefundene SDKs: ${LIST:-(keine)}" \
        "Einrichten mit dem passenden Bundle von swift.org:" \
        "  swift sdk install <URL-des-Android-SDK-Bundles>" \
        "Zusätzlich nötig: das Android NDK, passend zur SDK-Version." \
        "Siehe docs/android.md."
fi

SDK_ID="$(printf '%s' "$LIST" | grep -i "android" | head -1 | tr -d '[:space:]')"

# --- Falle 1: die Toolchain --------------------------------------------------
#
# Ein Cross-Compilation-SDK verlangt eine **Open-Source**-Toolchain von
# swift.org, und zwar in exakt derselben Version. Die Toolchain aus Xcode
# erfüllt beides nicht. Sie kommt aber trotzdem durch `swift sdk list`, weil
# die SDK-Liste unabhängig von der Toolchain im Benutzerverzeichnis liegt —
# die Prüfung oben war also grün, und der Build scheiterte erst hinterher.
SDK_VERSION="${SDK_ID#swift-}"
SDK_VERSION="${SDK_VERSION%%-RELEASE*}"
# Bewusst an „Swift version" festgemacht und nicht an der ersten Zahl in der
# Ausgabe: Xcodes Toolchain stellt eine Treiberzeile voran —
#   swift-driver version: 1.168.6 Apple Swift version 6.4 (…)
# — und die erste Zahl wäre dort 1.168.6, also die Version des Treibers.
SWIFT_VERSION="$(swift --version 2>&1 \
    | grep -oE 'Swift version [0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 \
    | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')"

if [ -n "$SDK_VERSION" ] && [ "$SWIFT_VERSION" != "$SDK_VERSION" ]; then
    HINT="  Eine passende Toolchain ist nicht installiert."
    for dir in "$HOME/Library/Developer/Toolchains" "/Library/Developer/Toolchains"; do
        if [ -d "$dir/swift-${SDK_VERSION}-RELEASE.xctoolchain" ]; then
            HINT="  Vorhanden in $dir — auswählen mit:
    export TOOLCHAINS=\$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \\
      \"$dir/swift-${SDK_VERSION}-RELEASE.xctoolchain/Info.plist\")"
        fi
    done
    fail "Swift-Toolchain passt nicht zum Android-SDK." \
        "SDK $SDK_ID erwartet Swift $SDK_VERSION, gefunden wurde $SWIFT_VERSION." \
        "Ein Android-SDK braucht die Open-Source-Toolchain von swift.org in" \
        "derselben Version; die Toolchain aus Xcode taugt dafür nicht." \
        "$HINT" \
        "Siehe docs/android.md."
fi

# --- Falle 2: das NDK-Sysroot ------------------------------------------------
#
# Das SDK-Bundle zeigt über `sdkRootPath: ndk-sysroot` auf ein Verzeichnis, das
# es **nicht mitbringt**: es entsteht erst, wenn das mitgelieferte
# setup-android-sdk.sh gegen das lokale NDK gelaufen ist. Fehlt es, bricht der
# Build mitten in SwiftSoup mit „'semaphore.h' file not found" ab — eine
# Meldung, die nach einer kaputten Abhängigkeit aussieht und nicht nach einem
# fehlenden Einrichtungsschritt.
BUNDLE="$(find "$HOME/Library/org.swift.swiftpm/swift-sdks" \
    -maxdepth 1 -name "${SDK_ID}.artifactbundle" -type d 2>/dev/null | head -1)"

if [ -n "$BUNDLE" ]; then
    SETUP="$(find "$BUNDLE" -maxdepth 3 -name "setup-android-sdk.sh" 2>/dev/null | head -1)"
    if ! find "$BUNDLE" -maxdepth 2 -name "ndk-sysroot" -type d 2>/dev/null | grep -q .; then
        fail "Das Android-SDK ist nicht gegen ein NDK eingerichtet." \
            "Im Bundle fehlt 'ndk-sysroot'; der Build scheitert sonst an" \
            "'semaphore.h' file not found, mitten in einer Abhängigkeit." \
            "Nachholen mit dem Skript aus dem Bundle selbst:" \
            "  export ANDROID_NDK_HOME=<Pfad zum NDK, r27d oder neuer>" \
            "  bash ${SETUP:-<Bundle>/swift-android/scripts/setup-android-sdk.sh}" \
            "Siehe docs/android.md."
    fi
fi

# Den genauen Bezeichner ausgeben — der Workflow braucht ihn für --swift-sdk,
# und bei einem Fehlschlag steht damit im Protokoll, was tatsächlich da war.
printf '%s\n' "$SDK_ID"
echo "Swift-SDK für Android gefunden, Toolchain $SWIFT_VERSION, NDK-Sysroot eingerichtet."
