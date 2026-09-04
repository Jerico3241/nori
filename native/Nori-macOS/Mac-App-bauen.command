#!/bin/zsh
set -e
cd "$(dirname "$0")"
echo "Baue Nori 1.9.0 für macOS..."
xcodebuild -project NoriMac.xcodeproj -scheme Nori -configuration Debug -destination 'platform=macOS' -derivedDataPath ./DerivedData build
APP="./DerivedData/Build/Products/Debug/Nori.app"
echo ""
echo "Fertig: $APP"
open "$(dirname "$APP")"
