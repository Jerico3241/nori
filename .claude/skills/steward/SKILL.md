---
name: steward
description: Wie in diesem Repo ein Pull Request grün wird — der macOS-CI-Build ist der einzige Swift-Typechecker, wie man seine Logs auswertet, welche Ordner generiert sind und nicht von Hand bearbeitet werden, und welche Fehler hier schon aufgetreten sind. Verwenden bei CI-Fehlern, Review-Kommentaren oder vor jedem Push auf einen PR-Branch.
---

# PRs in diesem Repo grün bekommen

## Es gibt keinen lokalen Swift-Compiler

In Claude-Code-Sitzungen (Linux-Container) ist **kein** `swift`, `swiftc` oder
`xcodebuild` verfügbar. Der einzige echte Typechecker ist der
GitHub-Actions-Workflow `.github/workflows/build-macos.yml`:

- läuft auf `macos-14`, dauert rund **eine Minute**
- wird durch jeden Push ausgelöst, der `native/Nori-macOS/**` berührt
- Check heißt `build`

Daraus folgt die Arbeitsweise: **erst statisch prüfen, dann pushen, dann den
Build lesen.** Nicht raten und nicht mehrere Spekulativ-Pushes hintereinander —
jede Runde kostet eine Minute und Vertrauen.

```bash
python3 tools/check-apple-sources.py    # Sekunden, fängt die bekannten Fehlerklassen
```

Das Skript ersetzt den Build nicht. Es prüft Target-Trennung, geteilte
Dateien, die API-Decke und eine gepflegte Liste von APIs, die es nicht gibt.

## Build-Logs auswerten

Das Job-Log ist eine einzige, ~100.000 Zeichen lange Zeile und sprengt jedes
Kontextlimit beim direkten Lesen. Erst filtern:

```python
import re
s = open(pfad).read()
parts = re.split(r'(?=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z )', s)
for p in parts:
    if re.search(r'error:|warning:|\*\* BUILD FAILED', p):
        print(p.strip()[:400])
```

Swift meldet Datei, Zeile und Spalte. Die Spalte ist wichtig: bei
`error: generic parameter 'T' could not be inferred` steht an der zweiten
Spaltenangabe der eigentlich schuldige Ausdruck.

Bei Fehlschlag lädt der Workflow zusätzlich `nori-macos-xcodebuild-log` als
Artefakt hoch.

## Nach einem roten Build

Jede gefundene Ursache gehört als Zeile in `tools/check-apple-sources.py`
(`NONEXISTENT`, `TOO_NEW_MACOS_14` oder `INEFFECTIVE_ON_MACOS`), damit
derselbe Fehler nicht zweimal eine CI-Runde kostet. Das Skript ist als
wachsende Lessons-learned-Liste gedacht.

Bereits eingetragen:

| Fehler | Ursache | Richtig |
| --- | --- | --- |
| `generic parameter 'T' could not be inferred` an `@Environment(\.openSettings)` | `EnvironmentValues.openSettings` existiert nicht | `SettingsLink { … }` (macOS 14+) |
| `missing argument label 'content:'` an `Section("Titel") { … } footer: { … }` | Diese Überladung gibt es nicht | `Section { … } header: { … } footer: { … }` |
| `The stickers icon set or app icon set named "AppIcon" did not have any applicable content` | Bild kleiner als in `Contents.json` eingetragen (iOS: 256×256 statt 1024×1024) — die Meldung nennt die Ursache nicht | Bild in der deklarierten Größe hinterlegen, iOS zusätzlich ohne Alphakanal (`check_app_icons()` prüft das) |

## Was nicht angefasst wird

- **`server/`** — gebautes Nitro/Node-Bundle, kein Quellcode. Minifizierte
  `.mjs`-Dateien mit Hash-Namen. Änderungen gehören in das Projekt, das dieses
  Bundle erzeugt, nicht hierher.
- **`native/Nori-macOS/Nori/Assets.xcassets/AppIcon.appiconset/icon_*.png`** —
  wird von `.github/workflows/fix-macos-appicon.yml` aus `icon.png` erzeugt.
- **Das jeweils andere Target** — einen macOS-Fehler nie dadurch beheben, dass
  die iOS-App angeglichen wird. Welche Dateien geteilt sind, steht in
  `.claude/skills/apple-parity/SKILL.md`.

## Konventionen

- Oberflächentexte, README und Commit-Nachrichten sind **deutsch**.
- Commit-Betreff mit Plattform-Präfix, wo es eine gibt: `macOS: …`, `iOS: …`.
- **Versionspflege gehört zu jeder Funktionsänderung.** macOS, iOS und
  Windows laufen auf eigenen Ständen. Zu ändern sind: `MARKETING_VERSION` und
  `CURRENT_PROJECT_VERSION` im jeweiligen pbxproj, `appVersion` in der
  zugehörigen `contract.json`, die Tabelle in `README.md`, die Überschrift im
  Plattform-README, `NoriRelease` in der macOS-`SettingsView.swift` und ein
  Eintrag in `CHANGELOG.md`. Die `Info.plist` beider Apple-Targets zieht die
  Version über `$(MARKETING_VERSION)` — dort nichts fest eintragen.
- Gegenprobe nach einem Versionswechsel:
  `grep -rn "<alte Version>" README.md native/ --include=*.md --include=*.json --include=*.pbxproj`
- Das Bibliotheksschema ist `v3` (`LibraryStore.schemaVersion`). Ein
  Feldwechsel in `WatchProgress` oder `Bag` braucht eine Migration in
  `migrateProgress` und eine Erhöhung von `schemaVersion`; neue Felder immer
  optional, damit ältere `library.json` weiter dekodiert.

## Wann ein PR fertig ist

`build` grün auf dem aktuellen Head, kein Merge-Konflikt, offene
Review-Kommentare beantwortet. Ein roter oder konfliktbehafteter PR wartet nie
„auf Review" — das ist Arbeit, kein Zustand.
