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
- gemeinsame Anwendungsschicht: `shared/nori-app/` — steckt in **beiden**
  JavaScript-Apps; wer sie ändert, prüft webOS und Windows
- Windows-App: `apps/windows/` (Electron: `src/main/`, `src/renderer/`)

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

Seit 2.6.0 tragen alle Plattformen **eine gemeinsame Nori-Version** — iOS/iPadOS, macOS, Windows, LG webOS, dazu Kern, Anwendungsschicht und Nori-Server. Welche Dateien sie tragen, weiß `tools/nori-version.py`; auf Apple landet sie über `MARKETING_VERSION` im Bundle.

Bei jeder Änderung, die in einem Paket landet:

1. `python3 tools/nori-version.py bump patch|minor|major` — setzt die Nummer überall und erhöht `CURRENT_PROJECT_VERSION` von iOS und macOS.
2. `CHANGELOG.md`: Abschnitt `## [Nori x.y.z]` mit den Unterabschnitten, die sich tatsächlich geändert haben; `Nori **x.y.z**` in der Übersicht.
3. `README.md` unter „Aktueller Stand“: `Nori **x.y.z**` und die Nummer in jeder Plattformzeile.
4. Plattform-README aktualisieren, falls dort ein aktueller Versionsstand genannt wird.
5. UI-interne Release-Hinweise aktualisieren: `NoriRelease.highlights` der Mac-App.
6. `python3 tools/nori-version.py check --against origin/main`.

Nie eine Plattform zurückstufen, nie eine Nummer zweimal für verschiedene Pakete vergeben.

**Nicht mehr pflegen:** eine App-Version in `contract.json`. Der Contract ist plattformübergreifend und enthält keine App-Version.

## Bibliotheksschema

`LibraryStore.schemaVersion` ist die technische Source of Truth. Aktuell: **v6**.

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

Eine Version, ein Tag, ein Release:

- Tag `vX.Y.Z`, GitHub Release `Nori vX.Y.Z`
- Anhänge `Nori-<Plattform>-vX.Y.Z.<Endung>` und `checksums-sha256.txt`
- keine Plattform-Tags mehr (`ios-v…`, `macos-v…`, `webos-v…`, `windows-v…`) — die alten bleiben stehen

Releases werden nicht von Hand getaggt und entstehen nicht in Plattform-Läufen. Einziger Weg: **GitHub → Actions → Nori Release → Run workflow → Version**, nachdem die Nummer auf `main` steht. Der Lauf prüft, baut, veröffentlicht, prüft nach und räumt erst dann alte Läufe auf. Regeln: `docs/releases.md`, Logik: `tools/nori-release.py`.

Das macOS-Release hängt **zwei** Pakete an: `Nori-macOS-vX.Y.Z.zip` (`Nori.app`, unsigniert) und das Quellpaket `Nori-macOS-Source-vX.Y.Z.zip`. Das Quellpaket muss enthalten:

- jeweiligen Plattformordner
- `native/NoriCore/`
- `native/Package.swift`
- `native/Tests/`
- `config/contract.json`
- `README.md`
- `CHANGELOG.md`

Symlinks müssen erhalten bleiben, sonst geht die gemeinsame Core-Struktur im Quellpaket verloren. `tools/nori-release.py source-package` schnürt das Paket deshalb direkt aus dem Commit, mit Symlinks als Symlinks.

## Build-Ausgabe

Nicht in Git einchecken:

- DerivedData
- `.build`
- `.swiftpm`
- `.output`
- `.app`
- `.ipa`
- Logs

`apps/windows/dist/`, `apps/windows/dist-main/` und `apps/windows/release/` sind Bauausgaben und gehören nicht ins Repository. Die frühere Ausnahme `server/` — der gebaute Windows-Runtime-Stand 1.8.0 — ist mit Windows 2.0.0 entfallen.

## Schlüssel

Keine neuen Secrets im Quelltext. Der vorhandene eingebaute TMDB-Fallback ist eine ausdrücklich dokumentierte Ausnahme für dieses private Projekt. Weitere Zugangsdaten gehören in Keychain, Build-Einstellungen oder Secrets.
