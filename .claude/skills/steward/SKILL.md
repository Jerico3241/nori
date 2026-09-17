---
name: steward
description: Arbeitsregeln für Änderungen, Prüfung, Releases und Versionspflege im Nori-Repository.
---

# Nori Steward

## Repository-Wahrheiten

- Gemeinsamer Swift-Kern: `native/NoriCore/Sources/NoriCore/`
- iOS-App: `native/Nori-iOS/`
- macOS-App: `native/Nori-macOS/`
- SwiftPM/Testpaket: `native/Package.swift` + `native/Tests/`
- kanonischer Contract: `config/contract.json`
- Windows-Legacy-Hülle: `desktop/`
- generiertes Windows-Runtime-Bundle: `server/` — nicht manuell bearbeiten

Die gleichnamigen Core-Dateien in den Apple-App-Ordnern sind Symlinks. Eine Kernänderung erfolgt ausschließlich unter `native/NoriCore/Sources/NoriCore/`.

## Vor jedem Push

```bash
python3 tools/check-apple-sources.py
cd native && swift test
```

Ein erfolgreicher statischer Check ersetzt keinen Xcode-Build. Für Änderungen am Core müssen mindestens diese CI-Läufe relevant sein:

- Build iOS
- Build macOS
- Swift tests

## Versionspflege

Die Apple-Plattformen haben eigene App-Versionen. Technische Source of Truth ist `MARKETING_VERSION` im jeweiligen `project.pbxproj`.

Bei einer Funktionsänderung:

1. `MARKETING_VERSION` anheben.
2. `CURRENT_PROJECT_VERSION` anheben.
3. `README.md`-Versionstabelle aktualisieren.
4. Plattform-README aktualisieren, falls dort ein aktueller Versionsstand genannt wird.
5. `CHANGELOG.md` ergänzen.
6. UI-interne Release-Hinweise aktualisieren, falls die Plattform solche anzeigt.

**Nicht mehr pflegen:** eine App-Version in `contract.json`. Der Contract ist plattformübergreifend und enthält keine App-Version.

## Bibliotheksschema

`LibraryStore.schemaVersion` ist die technische Source of Truth. Aktuell: **v4**.

`config/contract.json` muss denselben Wert dokumentieren. Änderungen an gespeicherten Feldern brauchen eine rückwärtskompatible Migration. Neue Felder möglichst optional halten.

## Contract

Nur `config/contract.json` inhaltlich bearbeiten. Die Dateien

- `native/Nori-iOS/contract.json`
- `native/Nori-macOS/contract.json`

sind Kompatibilitäts-Symlinks.

## Apple-Plattformtrennung

Core gemeinsam, UI getrennt. Nicht versuchen, macOS wieder zu einem wörtlichen iOS-Port zu machen.

Plattformspezifisch bleiben insbesondere:

- App-Lifecycle
- Navigation
- Theme
- Views
- Player-Integration
- Info.plist
- Xcode-Projekte

Details stehen in `.claude/skills/apple-parity/SKILL.md`.

## Release

Tags:

- `ios-vX.Y.Z`
- `macos-vX.Y.Z`
- `webos-vX.Y.Z`

Releases werden nicht von Hand getaggt. Sie entstehen automatisch als letzter Job von `Package iOS IPA`, `Build webOS` und `Package macOS Source` auf `main`, sobald dort eine neue Version gebaut und geprüft ist — Voraussetzung ist ein Abschnitt `[<Plattform> <Version>]` in `CHANGELOG.md`. Regeln und Nachholen: `docs/releases.md`, Logik: `tools/nori-release.py`.

Ein Release-Quellpaket muss enthalten:

- jeweiligen Plattformordner
- `native/NoriCore/`
- `native/Package.swift`
- `native/Tests/`
- `config/contract.json`
- `README.md`
- `CHANGELOG.md`

Symlinks beim ZIPpen erhalten (`zip -y`), sonst geht die gemeinsame Core-Struktur im Quellpaket verloren.

## Build-Ausgabe

Nicht in Git einchecken:

- DerivedData
- `.build`
- `.swiftpm`
- `.output`
- `.app`
- `.ipa`
- Logs

`server/` ist eine historische Ausnahme: dort liegt der gebaute Windows-Runtime-Stand 1.8.0. Er ist kein Ort für neue manuelle Implementierung.

## Schlüssel

Keine neuen Secrets im Quelltext. Der vorhandene eingebaute TMDB-Fallback ist eine ausdrücklich dokumentierte Ausnahme für dieses private Projekt. Weitere Zugangsdaten gehören in Keychain, Build-Einstellungen oder Secrets.
