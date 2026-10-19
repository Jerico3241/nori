---
name: steward
description: Arbeitsregeln für Änderungen, Prüfung, Releases und Versionspflege im Nori-Repository.
---

# Nori Steward

## Repository-Wahrheiten

- Gemeinsamer Swift-Kern: `native/NoriCore/Sources/NoriCore/`
- iOS-App: `native/Nori-iOS/` — seit 2.8.0 die einzige App; macOS, Windows
  und LG webOS sind eingestellt und nicht wieder anzulegen, ohne dass der
  Nutzer es ausdrücklich will
- SwiftPM/Testpaket: `native/Package.swift` + `native/Tests/`
- kanonischer Contract: `config/contract.json`

Die gleichnamigen Core-Dateien im iOS-Ordner sind Symlinks. Eine Kernänderung erfolgt ausschließlich unter `native/NoriCore/Sources/NoriCore/`.

## Vor jedem Push

```bash
python3 tools/check-apple-sources.py
cd native && swift test
```

Ein erfolgreicher statischer Check ersetzt keinen Xcode-Build. Für Änderungen am Core müssen mindestens diese CI-Läufe relevant sein:

- Build iOS
- Swift tests

Das Projekt ist privat, Actions-Minuten auf macOS sind knapp: ein Push pro
fertigem Stand, keine zusätzlichen Auslöser, keine Läufe zum bloßen Anstoßen.

## Versionspflege

Die App trägt die Nori-Version. Welche Stellen sie tragen, weiß `tools/nori-version.py`; ins Bundle gelangt sie über `MARKETING_VERSION`.

Bei jeder Änderung, die in einem Paket landet:

1. `python3 tools/nori-version.py bump patch|minor|major` — setzt die Nummer überall und erhöht `CURRENT_PROJECT_VERSION` von iOS.
2. `CHANGELOG.md`: Abschnitt `## [Nori x.y.z]` mit den Unterabschnitten, die sich tatsächlich geändert haben; `Nori **x.y.z**` in der Übersicht.
3. `README.md` unter „Aktueller Stand“: `Nori **x.y.z**` und die Nummer in der Zeile iOS / iPadOS.
4. `native/Nori-iOS/README.md` aktualisieren, falls dort ein aktueller Versionsstand genannt wird.
5. `python3 tools/nori-version.py check --against origin/main`.

Nie eine Version zurückstufen, nie eine Nummer zweimal für verschiedene Pakete vergeben.

**Nicht mehr pflegen:** eine App-Version in `contract.json`. Der Contract ist plattformübergreifend und enthält keine App-Version.

## Bibliotheksschema

`LibraryStore.schemaVersion` ist die technische Source of Truth. Aktuell: **v6**.

`config/contract.json` muss denselben Wert dokumentieren. Änderungen an gespeicherten Feldern brauchen eine rückwärtskompatible Migration. Neue Felder möglichst optional halten.

## Contract

Nur `config/contract.json` inhaltlich bearbeiten. `native/Nori-iOS/contract.json` ist ein Kompatibilitäts-Symlink.

Regeln für iOS und Kern: `.claude/skills/apple-parity/SKILL.md`.

## Release

Eine Version, ein Tag, ein Release:

- Tag `vX.Y.Z`, GitHub Release `Nori vX.Y.Z`
- Anhänge `Nori-iOS-vX.Y.Z.ipa` und `checksums-sha256.txt`
- keine Plattform-Tags mehr (`ios-v…`, `macos-v…`, `webos-v…`, `windows-v…`) — die alten bleiben stehen

Releases werden nicht von Hand getaggt und entstehen nicht in Plattform-Läufen. Einziger Weg: **GitHub → Actions → Nori Release → Run workflow → Version**, nachdem die Nummer auf `main` steht. Der Lauf prüft, baut, veröffentlicht, prüft nach und räumt erst dann alte Läufe auf. Regeln: `docs/releases.md`, Logik: `tools/nori-release.py`.

## Build-Ausgabe

Nicht in Git einchecken:

- DerivedData
- `.build`
- `.swiftpm`
- `.output`
- `.app`
- `.ipa`
- Logs

## Schlüssel

Keine neuen Secrets im Quelltext. Der vorhandene eingebaute TMDB-Fallback ist eine ausdrücklich dokumentierte Ausnahme für dieses private Projekt. Weitere Zugangsdaten gehören in Keychain, Build-Einstellungen oder Secrets.
