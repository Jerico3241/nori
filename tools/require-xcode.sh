#!/bin/bash
# Wählt auf einem Mac automatisch ein vollständiges Xcode in ausreichender
# Version aus und stellt es nachfolgenden GitHub-Actions-Schritten über
# DEVELOPER_DIR bereit. Auf GitHub-hosted macos-26 ist das Standard-Xcode
# bereits 26; das Skript fängt den Fall ab, dass jemand ein älteres Image
# oder einen eigenen Mac nimmt.
#
#   tools/require-xcode.sh 16
#
# Hintergrund: `xcode-select` kann auf eine unvollständige Beta zeigen, obwohl
# daneben ein funktionierendes Xcode installiert ist. `xcodebuild -version`
# allein reicht als Prüfung nicht: in einem beschädigten Bundle kann der
# Swift-Compiler fehlen. Deshalb werden beide Werkzeuge direkt im jeweiligen
# Developer-Verzeichnis geprüft.
set -euo pipefail

MIN="${1:-16}"

fail() {
    echo "::error::$1"
    shift || true
    for line in "$@"; do
        echo "  $line" >&2
    done
    exit 1
}

major_from_version_line() {
    local line="$1"
    local rest major
    rest="${line#Xcode }"
    major="${rest%%.*}"
    case "$major" in
        ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s' "$major"
}

candidate_usable() {
    local dev="$1"
    [ -d "$dev" ] || return 1
    [ -x "$dev/usr/bin/xcodebuild" ] || return 1
    [ -x "$dev/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ] || return 1
    return 0
}

# Kandidaten in sinnvoller Reihenfolge: explizites DEVELOPER_DIR, aktuell über
# xcode-select gewähltes Xcode, stabile Standardinstallation, Beta und weitere
# Xcode-Bundles. Doppelte Pfade werden beim Durchlauf übersprungen.
candidates=()
if [ -n "${DEVELOPER_DIR:-}" ]; then
    candidates+=("$DEVELOPER_DIR")
fi
selected="$(xcode-select -p 2>/dev/null || true)"
if [ -n "$selected" ]; then
    candidates+=("$selected")
fi
for app in /Applications/Xcode.app /Applications/Xcode-beta.app /Applications/Xcode*.app; do
    [ -d "$app/Contents/Developer" ] && candidates+=("$app/Contents/Developer")
done

chosen=""
chosen_version=""
seen="|"
for dev in "${candidates[@]}"; do
    case "$seen" in
        *"|$dev|"*) continue ;;
    esac
    seen="${seen}${dev}|"

    if ! candidate_usable "$dev"; then
        echo "Überspringe unvollständiges Xcode: $dev"
        continue
    fi

    if ! version_out="$(DEVELOPER_DIR="$dev" /usr/bin/xcodebuild -version 2>&1)"; then
        echo "Überspringe nicht ausführbares Xcode: $dev"
        continue
    fi
    version_line="${version_out%%$'\n'*}"
    major="$(major_from_version_line "$version_line" || true)"
    if [ -z "$major" ]; then
        echo "Überspringe Xcode mit unlesbarer Version: $dev ($version_line)"
        continue
    fi
    if [ "$major" -lt "$MIN" ]; then
        echo "Überspringe $version_line: mindestens Xcode $MIN erforderlich."
        continue
    fi

    # Den Compiler direkt aus diesem Bundle ansprechen. So prüfen wir genau das
    # Xcode, das wir anschließend auch über DEVELOPER_DIR verwenden.
    swift_bin="$dev/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
    if ! swift_out="$("$swift_bin" --version 2>&1)"; then
        echo "Überspringe Xcode ohne funktionierenden Swift-Compiler: $dev"
        continue
    fi

    chosen="$dev"
    chosen_version="$version_line"
    chosen_swift="${swift_out%%$'\n'*}"
    break
done

if [ -z "$chosen" ]; then
    fail "Kein vollständiges Xcode $MIN oder neuer mit funktionierendem Swift-Compiler gefunden." \
        "Installierte Xcode-Bundles unter /Applications prüfen." \
        "Bei einer unvollständigen Beta die Installation reparieren oder ein stabiles Xcode.app installieren." \
        "Ausführlich: docs/self-hosted-runner.md"
fi

export DEVELOPER_DIR="$chosen"

# GitHub Actions übernimmt diese Variable erst ab dem nächsten Step. Genau das
# ist gewollt: Build/Resolve/Test-Schritte laufen danach mit demselben Xcode.
if [ -n "${GITHUB_ENV:-}" ]; then
    printf 'DEVELOPER_DIR=%s\n' "$chosen" >> "$GITHUB_ENV"
fi

echo "$chosen_version"
echo "$chosen_swift"
echo "Entwicklerverzeichnis: $chosen"
