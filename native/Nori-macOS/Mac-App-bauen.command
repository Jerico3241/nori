#!/bin/zsh
set -e
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
echo "Baue Nori für macOS (Release)…"
if [ -f "$HOME/.config/nori/secrets/google-macos-oauth.json" ]; then
  python3 "$ROOT/tools/configure-google-oauth.py" --macos
else
  echo "Hinweis: keine google-macos-oauth.json – dieser Build hat keinen Google-Abgleich."
fi
xcodebuild \
  -project NoriMac.xcodeproj \
  -scheme Nori \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath ./DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
APP="./DerivedData/Build/Products/Release/Nori.app"
if [ ! -d "$APP" ]; then
  echo "Build lief durch, aber Nori.app fehlt." >&2
  exit 1
fi
rm -rf ./Nori.app
ditto "$APP" ./Nori.app
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ./Nori.app/Contents/Info.plist)"
ZIP="./Nori-macOS-v${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent --sequesterRsrc ./Nori.app "$ZIP"
echo ""
echo "Fertig: $(pwd)/Nori.app"
echo "Paket:  $(pwd)/$ZIP"
echo "Öffnen: Rechtsklick auf Nori.app → Öffnen (nicht doppelklicken)."
open "$(pwd)"
