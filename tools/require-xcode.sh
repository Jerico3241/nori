#!/bin/bash
# Prüft, dass auf dem Runner ein vollständiges Xcode in ausreichender Version
# aktiv ist — und sagt bei einem Fehlschlag, was zu tun ist.
#
#   tools/require-xcode.sh 16
#
# Warum das nötig ist: seit die Workflows auf einem eigenen Mac laufen, steht
# die Xcode-Version nicht mehr im Workflow (bei GitHub-Runnern hing sie am
# Label `macos-15`), sondern hängt an dem, was dort installiert ist. Ohne
# diese Prüfung bricht der Build entweder gleich mit einer kryptischen
# xcode-select-Meldung ab oder erst zwanzig Minuten später mit
# „has no member".
set -euo pipefail

MIN="${1:-16}"

fail() {
    echo "::error::$1"
    shift
    for line in "$@"; do
        echo "  $line" >&2
    done
    exit 1
}

# Was liegt überhaupt an Xcode auf der Platte? Der Pfad heißt bei einer Beta
# `Xcode-beta.app`, und genau dann geht der Standardbefehl aus jeder Anleitung
# ins Leere. Deshalb in der Fehlermeldung den tatsächlich gefundenen Pfad
# nennen statt eines geratenen.
found_xcode() {
    local app
    for app in /Applications/Xcode.app /Applications/Xcode-beta.app /Applications/Xcode*.app; do
        [ -d "$app/Contents/Developer" ] && { printf '%s' "$app"; return 0; }
    done
    return 1
}

XCODE_APP="$(found_xcode || true)"
SELECT_HINT="  sudo xcode-select -s ${XCODE_APP:-/Applications/Xcode.app}"
if [ -z "$XCODE_APP" ]; then
    SELECT_HINT="$SELECT_HINT   # kein Xcode unter /Applications gefunden"
fi

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"

if [ -z "$DEV_DIR" ]; then
    fail "Auf diesem Runner sind keine Entwicklerwerkzeuge ausgewählt." \
        "Xcode aus dem App Store installieren, dann:" \
        "$SELECT_HINT"
fi

# Der häufigste Fall auf einem frischen Mac: es sind nur die Command Line
# Tools da. `git` und `swiftc` laufen damit, aber
#
#   - `xcodebuild` meldet bloß „requires Xcode, but active developer directory
#     … is a command line tools instance", ohne zu sagen, was fehlt;
#   - `swift test` übersetzt Paket und Abhängigkeiten anstandslos und bricht
#     erst am Testziel ab: „unable to resolve module dependency: 'XCTest'".
#     XCTest liegt ebenfalls nur im vollständigen Xcode.
case "$DEV_DIR" in
    *CommandLineTools*)
        fail "Nur die Command Line Tools sind aktiv ($DEV_DIR), kein vollständiges Xcode." \
            "xcodebuild und XCTest gibt es nur dort. Auswählen mit:" \
            "$SELECT_HINT" \
            "  sudo xcodebuild -license accept" \
            "  xcodebuild -runFirstLaunch" \
            "Ausführlich: docs/self-hosted-runner.md"
        ;;
esac

if ! VERSION_LINE="$(xcodebuild -version 2>&1 | head -1)"; then
    fail "xcodebuild lässt sich nicht ausführen." \
        "Meldung: $VERSION_LINE" \
        "Ausführlich: docs/self-hosted-runner.md"
fi

echo "$VERSION_LINE"
echo "Entwicklerverzeichnis: $DEV_DIR"

MAJOR="$(printf '%s' "$VERSION_LINE" | awk '{print $2}' | cut -d. -f1)"
case "$MAJOR" in
    ''|*[!0-9]*)
        fail "Xcode-Version nicht lesbar aus: $VERSION_LINE"
        ;;
esac

if [ "$MAJOR" -lt "$MIN" ]; then
    fail "Xcode $MAJOR auf diesem Runner, gebraucht wird $MIN oder neuer." \
        "Bei iOS liegt es an den iOS-18-APIs hinter #available: die prüfen nur" \
        "zur Laufzeit, übersetzt wird gegen das SDK des Runners." \
        "Neueres Xcode installieren und auswählen:" \
        "$SELECT_HINT"
fi
