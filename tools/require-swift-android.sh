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

# Den genauen Bezeichner ausgeben — der Workflow braucht ihn für --swift-sdk,
# und bei einem Fehlschlag steht damit im Protokoll, was tatsächlich da war.
printf '%s' "$LIST" | grep -i "android" || true
echo "Swift-SDK für Android gefunden."
