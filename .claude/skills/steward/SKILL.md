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

## Vier Workflows, was sie abdecken

| Workflow | Runner | Prüft |
| --- | --- | --- |
| `build-macos.yml` | `macos-14` | macOS-Target, ~1 min |
| `build-ios.yml` | `macos-15` | iOS-Target gegen den Simulator. **macos-15 wegen Xcode 16** — die App nutzt hinter `#available` iOS-18-APIs, `#available` prüft aber nur zur Laufzeit |
| `swift-tests.yml` | `macos-14` | `swift test` in `native/` |
| `check-sources.yml` | `ubuntu-latest` | `tools/check-apple-sources.py` |

Das Testpaket `native/Package.swift` bindet `Models.swift` und `HTML.swift`
aus dem **macOS**-Target direkt ein, statt sie zu kopieren — beide sind
byte-gleich mit iOS, der Test deckt also beide Plattformen ab. SwiftSoup ist
dort auf dieselbe Spanne gepinnt wie in beiden Xcode-Projekten; läuft das
auseinander, parst der Test etwas anderes als die App.

Kommt eine Datei nach `sources:`, muss sie aus `exclude:` verschwinden —
sonst meldet SwiftPM sie als unbehandelte Ressource.

Fixtures für die Parser-Tests stehen als Swift-Zeichenketten in
`native/Tests/NoriCoreTests/Fixtures.swift`, nicht als heruntergeladene
Seiten: echte Seiten wären hunderte Kilobyte groß und gehören nicht ins
Repository. Ändert eine Quelle ihr Markup, ändert sich dort die Fixture.

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
| `has no member 'matchedTransitionSource'` / `'navigationTransition'` im iOS-Build | `#available(iOS 18.0, *)` schützt nur zur Laufzeit; übersetzt wird gegen das SDK des Runners, und macos-14 bringt Xcode 15.4 mit iOS-SDK 17.5 | `runs-on: macos-15` in `build-ios.yml` (`check_ios_runner()` prüft das) |
| `operator can throw but expression is not marked with 'try'` / `unable to type-check this expression in reasonable time` | Lange `??`-Kette, in der ein Glied `try` enthält | Kette in einzelne `let` mit eigenem `try` auflösen — so wie in `HTML.swift` bereits geschehen |
| `call to main actor-isolated instance method '…' in a synchronous nonisolated context` | `var body` ist über die View-Konformanz an den Main-Actor gebunden, eine ausgelagerte `private var chrome: some View` aber nicht | `Task { @MainActor in methode() }` (`check_main_actor_calls()` prüft das) |
| `The stickers icon set or app icon set named "AppIcon" did not have any applicable content` | Bild kleiner als in `Contents.json` eingetragen (iOS: 256×256 statt 1024×1024) — die Meldung nennt die Ursache nicht | Bild in der deklarierten Größe hinterlegen, iOS zusätzlich ohne Alphakanal (`check_app_icons()` prüft das) |

## Was nicht angefasst wird

- **`server/`** — gebautes Nitro/Node-Bundle, kein Quellcode. Minifizierte
  `.mjs`-Dateien mit Hash-Namen. Änderungen gehören in das Projekt, das dieses
  Bundle erzeugt, nicht hierher.
- **Abgeleitete App-Icons** — `native/Nori-macOS/…/icon_*.png` und
  `native/Nori-iOS/…/icon.png` entstehen aus dem macOS-Master
  `native/Nori-macOS/Nori/Assets.xcassets/AppIcon.appiconset/icon.png`.
  Nicht von Hand bearbeiten, sondern neu erzeugen:

  ```bash
  python3 -m pip install pillow
  python3 tools/make-app-icons.py --write
  ```

  Der Lauf ist deterministisch: unverändertes Master ⇒ unverändertes
  `git status`. Nur der Master selbst wird per Hand ausgetauscht.
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

## Release

Die beiden Plattformen haben eigene Versionsstände und deshalb eigene Tags:

```bash
git tag macos-v1.10.2 && git push origin macos-v1.10.2
git tag ios-v1.9.4    && git push origin ios-v1.9.4
```

Aus einer Claude-Code-Sitzung heraus geht das **nicht**: Pushes nach
`refs/tags/*` beantwortet GitHub mit HTTP 403, die Anmeldedaten der Sitzung
reichen nur für Branches. Dort stattdessen den Workflow unter Actions →
Release → „Run workflow" starten und den Tag angeben — er wird dann im Lauf
angelegt, nachdem die Prüfungen durch sind.

Der Tag löst `.github/workflows/release.yml` aus. Der Workflow bricht ab, wenn

- die Version im Tag nicht zur `MARKETING_VERSION` im pbxproj passt, oder
- `CHANGELOG.md` keinen Abschnitt `[<Plattform> <Version>]` enthält.

Beides ist Absicht: ein Release, dessen Inhalt eine andere Version ist oder das
nicht sagt, was sich geändert hat, soll gar nicht erst entstehen. Also **erst**
Version und Changelog per PR nach main, **dann** taggen.

Das Anhängsel heißt `Nori-<Plattform>-<Version>-source.zip` — nie `final.zip`
oder Ähnliches. Es enthält das Plattformverzeichnis, `native/Package.swift`,
`native/Tests`, `CHANGELOG.md` und `README.md`; ein fertig gebautes Programm
liegt nicht bei, dafür fehlt die Signatur.

Zum Ausprobieren zwischendurch gibt es `package-macos-source.yml`: läuft bei
jedem Push auf main, der macOS berührt, und legt dasselbe Paket als Artefakt ab
— mit 30 Tagen Haltbarkeit.

## Wann ein PR fertig ist

`build` grün auf dem aktuellen Head, kein Merge-Konflikt, offene
Review-Kommentare beantwortet. Ein roter oder konfliktbehafteter PR wartet nie
„auf Review" — das ist Arbeit, kein Zustand.
