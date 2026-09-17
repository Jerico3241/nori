# Nori-Releases

Seit 2.6.0 gilt: **eine Version, ein Tag, ein GitHub Release** — für alle
Plattformen zugleich.

| | Beispiel |
| --- | --- |
| Version | `2.6.0` — in allen Apps gleich |
| Tag | `v2.6.0` |
| GitHub Release | `Nori v2.6.0` |
| Anhänge | ein Paket je Plattform und `checksums-sha256.txt` |

| Plattform | Anhang | Was es ist | Gebaut von |
| --- | --- | --- | --- |
| iOS / iPadOS | `Nori-iOS-v<VERSION>.ipa` | unsignierte IPA, vor der Installation signieren | Build iOS, Job `ipa` |
| macOS | `Nori-macOS-Source-v<VERSION>.zip` | Quellpaket, in Xcode öffnen und selbst signieren | Build macOS, Job `package` |
| LG webOS | `Nori-webOS-v<VERSION>.ipk` | Installationspaket mit produktivem TV-Client | Build webOS |
| Windows | `Nori-Windows-v<VERSION>.exe` | NSIS-Installer ohne Administratorrechte, nicht signiert | Build Windows |
| Windows | `Nori-Windows-v<VERSION>.zip` | dieselbe App zum Entpacken, ohne Installation | Build Windows |
| alle | `checksums-sha256.txt` | SHA-256 jedes Pakets | Nori Release |

Das Schema der Dateinamen ist `Nori-<Plattform>-v<VERSION>.<Endung>`. macOS
trägt `macOS-Source` als Plattform, weil es ein Quellpaket ist und kein
Programm. Android und Google TV haben keine App in diesem Repository; die
Notes nennen sie unter „nicht enthalten“, ein Paket wird nicht erfunden.

Die alten, plattformgetrennten Tags (`ios-v…`, `macos-v…`, `webos-v…`,
`v1.8.0` von Windows) bleiben stehen. Neue entstehen nicht.

## Einen Release machen

1. **Version setzen** — auf einem Branch, nach
   [Semantic Versioning](https://semver.org/lang/de/):

   ```bash
   python3 tools/nori-version.py bump patch   # Fehlerbehebung: 2.6.0 → 2.6.1
   python3 tools/nori-version.py bump minor   # neue Funktionen: 2.6.1 → 2.7.0
   python3 tools/nori-version.py bump major   # Inkompatibles:   2.7.0 → 3.0.0
   ```

   Das setzt die Nummer an allen Stellen und erhöht die Buildnummern von iOS
   und macOS um eins. `python3 tools/nori-version.py set 2.7.0` geht auch.

2. **Beschreiben**, was sich geändert hat — in `CHANGELOG.md` ein Abschnitt

   ```markdown
   ## [Nori 2.7.0] — 2026-10-01

   ### Allgemein
   ### iOS / iPadOS
   ### macOS
   ### Android / Google TV
   ### Windows
   ### webOS
   ### Technische Änderungen
   ```

   mit nur den Unterabschnitten, in denen sich tatsächlich etwas geändert hat,
   dazu `Nori **2.7.0**` in der Übersicht am Anfang. In `README.md` unter
   „Aktueller Stand“ dieselbe Nummer in jeder Plattformzeile, auf dem Mac die
   Hinweise in `NoriRelease` (`native/Nori-macOS/Sources/Features/Settings/SettingsView.swift`).

3. **Prüfen** und über einen Pull Request nach `main` bringen:

   ```bash
   python3 tools/nori-version.py check --against origin/main
   ```

4. **Auslösen:** GitHub → **Actions** → **Nori Release** → **Run workflow** →
   *Use workflow from* `main`, Version `2.7.0` (auch `v2.7.0` geht) →
   **Run workflow**. Von der Kommandozeile:

   ```bash
   gh workflow run release.yml --ref main -f version=2.7.0
   ```

   Die Häkchen je Plattform stehen auf „an“. Wer eine Plattform abwählt,
   bekommt einen Release ohne sie; die Notes sagen das. **Probelauf** baut und
   prüft alles, legt aber nichts an und löscht nichts.

Die Eingabe bestätigt nur, was im Repository steht. Trägt `main` eine andere
Nummer, bricht der Lauf sofort ab — eine Version kommt nie aus dem Eingabefeld
in ein Paket.

## Vor dem ersten Release: Artefakt-Speicher

Ein Release reicht die Pakete über Actions-Artefakte vom Paket-Job an den
Release-Job weiter. Am 17.09. war das Artefakt-Kontingent des Repositorys
**voll** — 214 Artefakte mit zusammen rund 2,5 GB, davon 1,4 GB aus alten
Android-Läufen und 0,7 GB Bildschirmfotos; das früheste läuft erst am 26.09.
ab. Jedes Hochladen scheitert dann mit „Artifact storage quota has been hit“,
also auch der erste Release (er bricht sauber ab, es entsteht nichts).

Das Aufräumen des Release-Workflows kann das nicht lösen: Es läuft mit
Absicht erst **nach** einem erfolgreichen Release. Einmalig also von Hand —
entweder unter *Actions* die alten Läufe löschen oder nur die Artefakte, am
eigenen Rechner:

```bash
gh api --paginate 'repos/Jerico3241/nori/actions/artifacts?per_page=100' --jq '.artifacts[].id' \
  | while read -r id; do gh api -X DELETE "repos/Jerico3241/nori/actions/artifacts/$id"; sleep 1; done
```

Das löscht nur Actions-Artefakte (derzeit gibt es keinen GitHub Release, und
Releases wären davon ohnehin nicht betroffen). GitHub rechnet den Verbrauch
nur alle 6 bis 12 Stunden neu; erst danach geht das Hochladen wieder.

Danach bleibt der Speicher klein: Übergabe-Artefakte leben einen Tag und
werden nach dem Veröffentlichen gelöscht, Testpakete und Diagnose drei Tage,
Windows lädt bei einem Push nichts hoch, und jeder Release löscht alte Läufe
samt ihren Artefakten. Zwei Releases kurz hintereinander brauchen trotzdem
Platz für zwei Sätze Pakete (je rund 220 MB), weil GitHub gelöschte
Artefakte erst bei der nächsten Neuberechnung abzieht.

## Ablauf

```text
Nori Release (workflow_dispatch, concurrency „nori-release“)
 ├─ prepare    Eingabe (x.y.z oder vx.y.z) · alle Versionsstellen gleich ·
 │             Changelog und README · Tag, Release, Entwurf noch nicht da ·
 │             Version über jedem Tag · Buildnummern über jedem früheren
 │             Release · auf main · Windows-Secrets, falls Windows gewählt
 ├─ checks     Werkzeug-Tests · Apple-Quellen · swift test ·
 │             TypeScript-Kern · Nori-Server
 ├─ ios        Build iOS (Job ipa)         → nori-release-ios
 ├─ macos      Build macOS (Job package)   → nori-release-macos
 ├─ webos      Build webOS                 → nori-release-webos
 ├─ windows    Build Windows               → nori-release-windows
 ├─ publish    nur wenn jede gewählte Plattform grün ist
 │             Pakete holen · noch einmal prüfen (Name, Prüfsumme aus dem
 │             Paket-Job, Inhalt, Produktionsprüfung) · checksums-sha256.txt ·
 │             Notes · Entwurf · Anhänge hochladen und gegenprüfen ·
 │             annotierter Tag · veröffentlichen · Endzustand prüfen
 ├─ validate   Release von außen: veröffentlicht, Tag auf dem Commit, genau
 │             die erwarteten Anhänge, Prüfsummen gleich
 └─ cleanup    alte Läufe und Übergabe-Artefakte löschen
```

Die Plattform-Läufe sind dieselben, die bei jedem Push prüfen. Vom Release
bekommen sie `release-version`; dann

- muss die Nummer im Commit genau diese sein,
- heißt das Paket `Nori-<Plattform>-v<VERSION>.<Endung>` statt
  `…-v<VERSION>-<commit>.<Endung>`,
- liegt es als Übergabe-Artefakt `nori-release-<plattform>` **einen Tag** am
  Lauf,
- und bei Windows sind die Google-Secrets Pflicht.

Alle Jobs checken denselben Commit aus (`GITHUB_SHA`), auch wenn `main`
während des Laufs weiterzieht.

## Fehler

Nach dem Grundsatz *fail safely*:

| Was scheitert | Folge |
| --- | --- |
| Eingabe ungültig, Nummer abweichend, Changelog fehlt | prepare rot — nichts wird gebaut |
| Tag, Release oder höhere Version vorhanden | prepare rot, verständliche Meldung |
| Test im gemeinsamen Kern | checks rot — keine Plattform wird gebaut |
| Build, Test oder Paketprüfung einer gewählten Plattform | publish, validate und cleanup laufen nicht |
| Paket fehlt, ist zu viel, weicht in Prüfsumme oder Inhalt ab | publish rot, nichts angelegt |
| Hochladen oder Gegenprüfen eines Anhangs | der Entwurf bleibt **unveröffentlicht** liegen, kein Tag |
| Tag entsteht zwischendurch anderswo | Abbruch vor dem Veröffentlichen, Tag unberührt |
| Release weicht bei der Nachprüfung ab | validate rot — **kein Aufräumen** |
| Lauf abgebrochen | nichts danach läuft (`!cancelled()`) |

Ein liegengebliebener Entwurf oder ein Tag ohne Release wird nie automatisch
repariert. Erst ansehen, dann von Hand entfernen und den Lauf neu starten. Ein
Entwurf ist für den Prüfschritt mit Lesezugriff unsichtbar; ihn findet erst
`publish` — der Lauf bricht dann dort ab.

## Doppelte Releases

| Zustand | Ergebnis |
| --- | --- |
| weder Tag noch Release | Release wird angelegt |
| Release `Nori v<VERSION>` existiert | Abbruch — kein zweiter, keiner überschrieben |
| unveröffentlichter Entwurf | Abbruch — er wird weder überschrieben noch gelöscht |
| Tag `v<VERSION>` existiert | Abbruch — der Tag wird nicht verschoben |
| gleiche Version unter altem Tag (`webos-v2.6.0`) | Abbruch |
| höhere Version unter irgendeinem Tag | Abbruch |
| Buildnummer iOS/macOS nicht über der eines früheren Release-Tags | Abbruch |

Die Tag-Referenz wird über die API ohne `force` angelegt; gibt es sie
inzwischen, antwortet GitHub mit 422, und nichts wird veröffentlicht. Kein
Workflow reagiert auf Tags oder Release-Ereignisse: alle Push-Auslöser sind
auf Branches beschränkt. Zwei Releases laufen nie gleichzeitig
(`concurrency: nori-release`, `cancel-in-progress: false`), und ein laufender
wird nicht abgebrochen.

## Versionsnummern

`tools/nori-version.py` kennt jede Stelle, an der die Nummer steht, und prüft
sie zusammen:

| Stelle | Wozu |
| --- | --- |
| `MARKETING_VERSION` in beiden Xcode-Projekten | `CFBundleShortVersionString` |
| `CURRENT_PROJECT_VERSION` in beiden Xcode-Projekten | `CFBundleVersion` — die Buildnummer |
| `NoriRelease.version` (macOS, Einstellungen → „Neu in“) | Anzeige |
| `apps/webos/appinfo.json`, `apps/webos/package.json` | Version auf dem Fernseher, Paketname |
| `apps/windows/package.json`, `package.json` | `electron-builder`: Dateiname, Produktversion, Deinstallationseintrag |
| `shared/nori-core/package.json`, `shared/nori-app/package.json` | gemeinsamer Kern, Anwendungsschicht |
| `services/nori-api/package.json`, `API_VERSION` | Nori-Server |
| vier `package-lock.json` | dieselbe Nummer, auch für die verlinkten Nori-Pakete |

Ein neues Paket muss vom Gerät als neuer erkannt werden:

- **iOS/iPadOS, macOS:** `CFBundleShortVersionString` steigt mit der Version,
  `CFBundleVersion` mit jeder Änderung. Der Release prüft beides im gebauten
  Programm und verlangt eine Buildnummer über der jedes früheren Release-Tags.
- **LG webOS:** `appinfo.json` und `control` im `.ipk` tragen die Version; ein
  zweites Paket unter derselben Nummer wird nicht über das erste installiert.
- **Windows:** Produktversion der `Nori.exe` und des Installers (`2.6.0.0`).
- **Android** hätte `versionName` und `versionCode` — es gibt die App noch
  nicht.

Auf jedem Branch prüft „Check release pipeline“ mit `--against origin/main`:
Ändert sich etwas, das in einem Paket landet, muss die Nummer größer sein als
jede Nummer auf `main`, und die Buildnummern müssen steigen. Tests,
Dokumentation und Werkzeuge verlangen keine neue Nummer.

## Aufräumen

Nach jedem **veröffentlichten und nachgeprüften** Release löscht der Job
`cleanup` alte Läufe — nie vorher, nie bei einem Probelauf.

Gelöscht werden abgeschlossene Läufe dieser Workflows, die vor dem Release
begonnen haben — mitsamt ihren Protokollen und Artefakten:

- Nori Release (`release.yml`)
- Build iOS, Build macOS, Build webOS, Build Windows, Build Android core
- Swift tests, Check Apple sources, Check release pipeline
- die entfernten Package iOS IPA, Package macOS Source und Build Android

Dazu die Übergabe-Artefakte `nori-release-*` des laufenden Releases — ihr
Inhalt hängt da bereits am Release.

Stehen bleiben:

| Was | Warum |
| --- | --- |
| der laufende Release-Lauf | `--keep-run "$GITHUB_RUN_ID"`; das Werkzeug verweigert jede Löschung, wenn die ID fehlt oder nicht dieser Lauf ist |
| Läufe, die noch laufen oder warten | nicht abgeschlossen |
| Läufe, die nach dem Release begonnen haben | gehören nicht zu „alt“ |
| Prüfläufe des veröffentlichten Commits und der Köpfe offener Pull Requests | sichtbare Prüfergebnisse |
| Läufe jedes anderen Workflows | die Liste `CLEANUP_WORKFLOWS` ist abschließend — CodeQL, Dependabot oder eine Wartung kommen nie hinein, ohne dass sie dort jemand einträgt |
| GitHub Releases, Anhänge, Tags, Branches, Quelltext, Workflow-Dateien | `GitHub.request` lässt `DELETE` nur für `/actions/runs/<id>` und `/actions/artifacts/<id>` zu |

GitHub begrenzt schreibende Aufrufe. Gelöscht wird deshalb eine Sekunde
nacheinander und höchstens 400 Läufe je Release, älteste zuerst. Bremst GitHub
oder ist die Grenze erreicht, endet der Job trotzdem grün und nennt die Zahl
der verbliebenen Läufe; sie folgen beim nächsten Release. Fehlt die
Berechtigung, wird der Job rot.

Vor dem ersten Release lagen rund 900 Läufe und über 200 Artefakte in
Actions; der erste Release räumt also nur einen Teil davon ab.

## Artefakte

| Art | Wo | Wie lange |
| --- | --- | --- |
| Release-Anhänge | am GitHub Release | dauerhaft — sie sind die Build-Historie |
| Übergabe `nori-release-*` | am Release-Lauf | ein Tag, nach dem Veröffentlichen gelöscht |
| Testpakete (`…-v<VERSION>-<commit>`) | an einem Push- oder Hand-Lauf | drei Tage |
| Protokolle und Bildschirmfotos | nur bei einem Fehlschlag | drei Tage |

Windows lädt bei einem gewöhnlichen Push keine Pakete hoch: Installer und ZIP
sind zusammen rund 200 MB, und das Artefakt-Kontingent war am 17.09. schon
einmal erschöpft.

## Release Notes

Aus dem Abschnitt `[Nori <VERSION>]` in `CHANGELOG.md` — fehlt er, entsteht
kein Release. Oben stehen Version, Commit, eine Tabelle der Anhänge mit
Hinweisen (Buildnummer, signiert oder nicht), die nicht enthaltenen
Plattformen und wie man die Prüfsummen nachrechnet.

Übernommen werden die Unterabschnitte *Allgemein*, *iOS / iPadOS*, *macOS*,
*Android / Google TV*, *Windows*, *webOS*, *Technische Änderungen* und
*Bekannte Einschränkungen* (dazu die älteren *Behoben*, *Geändert*,
*Hinzugefügt* …). *Tests*, Prüfprotokolle und Codeblöcke bleiben draußen.
Sätze und Punkte, die interne OAuth-, Secret-, Token-, `.env`-, xcconfig-
oder Runner-Einzelheiten nennen, fallen weg; bei einem Punkt mit fetter
Überschrift bleibt die Überschrift. Vor dem Veröffentlichen werden die Notes
noch einmal auf Client-IDs, Secrets, Tokens und die echten Zugangsdaten des
Runners geprüft.

```bash
python3 tools/nori-release.py notes                       # aktuelle Version, alle Plattformen
python3 tools/nori-release.py notes --platforms ios,webos
```

## Berechtigungen

| Job | Rechte |
| --- | --- |
| Workflow-Vorgabe, prepare, checks, validate, Plattform-Läufe | `contents: read` |
| publish | `contents: write` — Release, Anhänge, Tag |
| cleanup | `actions: write`, `contents: read`, `pull-requests: read` |

Kein Job bekommt `write-all`; die Plattform-Läufe haben nirgends
Schreibrechte. Die Checkouts in publish, validate und cleanup behalten kein
Token (`persist-credentials: false`). Die Versionseingabe erreicht Skripte
nur als Umgebungsvariable.

## Plattformen und Runner

Alle Jobs laufen auf dem self-hosted Mac (`[self-hosted, macOS]`,
[self-hosted-runner.md](self-hosted-runner.md)). Von GitHub gestellte Runner
starten bei diesem privaten Repository nicht mehr — das Minutenkontingent ist
aufgebraucht. Ist der Mac aus, warten die Jobs; es wird nichts vorgetäuscht.

| Plattform | Automatisiert | Einschränkung |
| --- | --- | --- |
| iOS / iPadOS | ja | unsigniert — kein Verteilungszertifikat im Repository |
| macOS | ja, als Quellpaket | für ein `.dmg` fehlen ein Zertifikat „Developer ID Application“ und die Notarisierung (App-spezifisches Passwort oder API-Schlüssel); beides müsste im Schlüsselbund des Runners bzw. als Secret liegen, danach: `PLATFORMS["macos"]` und `ASSETS["macos"]` in `tools/nori-release.py` umstellen und einen Prüfer für das Programm ergänzen |
| LG webOS | ja | Paket nicht auf einem echten Fernseher erprobt |
| Windows | ja, wenn die Secrets gesetzt sind | `NORI_GOOGLE_DESKTOP_CLIENT_ID` und `NORI_GOOGLE_DESKTOP_CLIENT_SECRET` (Settings → Secrets and variables → Actions) fehlen derzeit; ohne sie bricht ein Release mit Windows im ersten Job ab. Kreuzgebaut auf dem Mac, das gepackte Programm startet nur ein Windows-Runner (`NORI_WINDOWS_RUNNER`, [windows.md](windows.md)). Nicht signiert |
| Android / Google TV | nein | keine App in diesem Repository; `Build Android core` baut nur den Swift-Kern von Hand. Für einen Release bräuchte es die App, einen Build-Job, `versionName`/`versionCode` in `tools/nori-version.py`, einen Eintrag in `PLATFORMS` und einen Prüfer für `.apk` |

## Tests

```bash
python3 tools/test_nori_version.py
python3 tools/test_nori_release.py
```

Ohne echte Releases, Tags oder Löschungen: GitHub ist nachgebaut, das
Repository ein Wegwerf-Repository, alle Zugangsdaten sind erfunden. Die
Workflow-Struktur — Auslöser, `needs`, `if`, Berechtigungen, Aufbewahrung,
Reihenfolge von Prüfung und Hochladen — lesen die Tests aus den echten
Dateien (dafür braucht es `ruby`, das macOS mitbringt). Der Lauf **Check
release pipeline** führt beides bei jeder Änderung an Paketen, Versionen,
Changelog, Werkzeugen oder Workflows aus, und **Nori Release** noch einmal vor
jedem Release.
