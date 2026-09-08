#!/usr/bin/env bash
#
# Besorgt JDK und Android-SDK für den Build auf dem self-hosted Mac.
#
# Warum überhaupt: auf dem Runner steht ein Java 8. Damit lässt sich kein
# Android-Gradle-Plugin 8 bauen — der Fehler dabei („Unsupported class file
# major version") sieht aus wie ein kaputtes Projekt und ist keiner. Das
# System-Java wird deshalb **nicht** angefasst; stattdessen liegt hier ein
# eigenes JDK daneben, das nur dieser Build sieht.
#
# Alles landet unter $ANDROID_TOOLS_HOME (Vorgabe: ~/Library/Android). Wer die
# Werkzeuge wieder loswerden will, löscht dieses Verzeichnis — sonst bleibt
# nichts zurück.
#
#     source tools/android-sdk.sh
#
# Danach stehen JAVA_HOME, ANDROID_HOME und ANDROID_SDK_ROOT.
set -euo pipefail

TOOLS_HOME="${ANDROID_TOOLS_HOME:-$HOME/Library/Android}"
SDK_DIR="$TOOLS_HOME/sdk"
JDK_DIR="$TOOLS_HOME/jdk-21"

# Die Fassungen stehen hier und nicht im Workflow: so ist nachvollziehbar,
# womit gebaut wurde, ohne durch die Lauf-Historie zu gehen.
JDK_VERSION="21.0.5+11"
CMDLINE_TOOLS="11076708"   # cmdline-tools 12.0
PLATFORM="android-36"
BUILD_TOOLS="36.0.0"

case "$(uname -m)" in
    arm64)  JDK_ARCH="aarch64" ;;
    x86_64) JDK_ARCH="x64" ;;
    *)      echo "Unbekannte Architektur: $(uname -m)" >&2; exit 1 ;;
esac

mkdir -p "$TOOLS_HOME"

# --- JDK ---------------------------------------------------------------
if [ ! -x "$JDK_DIR/Contents/Home/bin/javac" ]; then
    echo "JDK $JDK_VERSION wird geholt ($JDK_ARCH) ..."
    ENCODED="${JDK_VERSION/+/%2B}"
    URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${ENCODED}/OpenJDK21U-jdk_${JDK_ARCH}_mac_hotspot_${JDK_VERSION/+/_}.tar.gz"
    TMP="$(mktemp -d)"
    curl -fsSL "$URL" -o "$TMP/jdk.tar.gz"
    mkdir -p "$JDK_DIR"
    tar -xzf "$TMP/jdk.tar.gz" -C "$JDK_DIR" --strip-components=1
    rm -rf "$TMP"
fi
export JAVA_HOME="$JDK_DIR/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
echo "JAVA_HOME=$JAVA_HOME"
java -version

# --- Android-SDK -------------------------------------------------------
export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"

if [ ! -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]; then
    echo "Android-Befehlszeilenwerkzeuge werden geholt ..."
    TMP="$(mktemp -d)"
    URL="https://dl.google.com/android/repository/commandlinetools-mac-${CMDLINE_TOOLS}_latest.zip"
    if ! curl -fsSL "$URL" -o "$TMP/tools.zip"; then
        echo "Download fehlgeschlagen: $URL" >&2
        echo "Die Build-Nummer der Command-line-Tools aendert sich mit jeder" >&2
        echo "Fassung. Aktuelle steht auf https://developer.android.com/studio" >&2
        echo "unter 'Command line tools only' — dann CMDLINE_TOOLS oben setzen." >&2
        exit 1
    fi
    mkdir -p "$SDK_DIR/cmdline-tools"
    unzip -q "$TMP/tools.zip" -d "$TMP"
    rm -rf "$SDK_DIR/cmdline-tools/latest"
    mv "$TMP/cmdline-tools" "$SDK_DIR/cmdline-tools/latest"
    rm -rf "$TMP"
fi

SDKMANAGER="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"

# `yes |` ist hier kein Hack: sdkmanager fragt jede Lizenz einzeln ab und
# bricht ohne Antwort ab. Die Lizenzen sind die von Google, unverändert.
yes 2>/dev/null | "$SDKMANAGER" --licenses > /dev/null || true
"$SDKMANAGER" \
    "platform-tools" \
    "platforms;$PLATFORM" \
    "build-tools;$BUILD_TOOLS" > /dev/null

export PATH="$SDK_DIR/platform-tools:$PATH"
echo "ANDROID_HOME=$ANDROID_HOME"
ls "$SDK_DIR/platforms"
