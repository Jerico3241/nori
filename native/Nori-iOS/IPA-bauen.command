#!/bin/bash
# Baut eine unsignierte Nori.ipa auf dem Mac.
# Signieren danach auf dem iPhone (Feather, ESign, SideStore, …).
set -euo pipefail
cd "$(dirname "$0")"

fail() {
  osascript -e "display dialog \"$1\" buttons {\"OK\"} default button 1 with icon stop" >/dev/null 2>&1 || echo "$1" >&2
  exit 1
}

if ! command -v xcodebuild >/dev/null 2>&1; then
  fail "Xcode fehlt. Im App Store installieren, einmal öffnen, danach dieses Skript nochmal doppelklicken."
fi

xcodebuild -version >/dev/null 2>&1 || fail "Xcode Command Line Tools sind nicht bereit. Xcode einmal öffnen."

rm -rf build Payload Nori.ipa
mkdir -p build

echo "Nori wird kompiliert (unsigniert, arm64)…"
xcodebuild \
  -project Nori.xcodeproj \
  -scheme Nori \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$PWD/build" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM= \
  ONLY_ACTIVE_ARCH=NO \
  build

APP="$(find "$PWD/build/Build/Products" -name "Nori.app" -path "*iphoneos*" | head -n 1)"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  fail "Build fertig, aber Nori.app fehlt. In Xcode einmal öffnen, Signing-Team setzen, erneut versuchen."
fi

mkdir -p Payload
cp -R "$APP" Payload/Nori.app
rm -f Payload/Nori.app/embedded.mobileprovision
zip -qry Nori.ipa Payload
rm -rf Payload

BYTES="$(wc -c < Nori.ipa | tr -d ' ')"
osascript -e "display dialog \"Nori.ipa ist fertig (${BYTES} Bytes). Unsigniert — aufs iPhone kopieren und dort signieren.\" buttons {\"Ordner öffnen\"} default button 1" >/dev/null 2>&1 || true
open -R Nori.ipa
