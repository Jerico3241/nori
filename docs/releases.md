# GitHub-Releases

Nori hat je Plattform eine eigene Versionsnummer, deshalb auch eigene Releases.
Sie entstehen automatisch, sobald eine neue Version auf `main` gebaut und
geprüft ist — niemand setzt dafür einen Tag von Hand.

| Plattform | Tag | Titel | Anhang | Quelle |
| --- | --- | --- | --- | --- |
| iOS/iPadOS | `ios-v<VERSION>` | Nori iOS `<VERSION>` | `Nori-iOS-<VERSION>-unsigned.ipa` | Package iOS IPA |
| LG webOS | `webos-v<VERSION>` | Nori webOS `<VERSION>` | `tv.nori.app_<VERSION>_all.ipk` | Build webOS |
| macOS | `macos-v<VERSION>` | Nori macOS `<VERSION>` | `Nori-macOS-<VERSION>-source.zip` | Package macOS Source |

## Ablauf

```text
Push auf main
  └─ Paket-Lauf (Package iOS IPA · Build webOS · Package macOS Source)
       ├─ Paket-Job: bauen → Produktions- und Zugangsdatenprüfungen
       │               → tools/nori-release.py verify (Prüfsumme festhalten)
       │               → Artefakt hochladen → lokale Zugangsdaten entfernen
       └─ release (needs: Paket-Job, nur refs/heads/main)
            └─ .github/workflows/release.yml
                 → tools/test_nori_release.py
                 → Artefakt dieses Laufs holen
                 → tools/nori-release.py publish
```

Die Logik liegt an einer Stelle, `tools/nori-release.py`; `release.yml` ist
ein wiederverwendbarer Workflow, den die drei Paket-Läufe aufrufen. Er baut
nichts selbst.

`publish` macht, in dieser Reihenfolge:

1. Version (und Build) aus den Projektdateien des Commits lesen —
   `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` bzw. `apps/webos/appinfo.json` —
   und als `x.y.z` prüfen.
2. Nachsehen, ob es Tag oder Release schon gibt (auch Entwürfe).
3. Das Paket prüfen: genau eine Datei im Artefakt, der erwartete Name,
   dieselbe Prüfsumme wie im Paket-Job, Version/Build/Kennung im Paket gleich
   dem Tag, keine `.env*`, `*.local.xcconfig`, OAuth-JSON, Logs oder
   Testbilder, keine Tokens, Cookies oder fremden Zugangsdaten. Das
   macOS-Quellpaket muss Datei für Datei dem Commit entsprechen.
4. Die Produktionsprüfung der Plattform noch einmal gegen genau diese Datei:
   `configure-google-oauth.py --verify-ios-ipa` bzw.
   `check-webos-package.py --production`.
5. Release Notes aus `CHANGELOG.md` erzeugen.
6. Prüfen, dass der Commit auf `main` liegt.
7. Unsichtbaren Entwurf anlegen, Paket anhängen, den Anhang über die
   Prüfsumme gegenprüfen, annotierten Tag auf den geprüften Commit setzen,
   veröffentlichen, Endzustand prüfen.

## Duplikate und Tags

| Zustand | Ergebnis |
| --- | --- |
| weder Tag noch Release | Release wird angelegt |
| Release existiert | grün, keine Änderung — auch wenn ein späterer Commit dieselbe Version trägt |
| Tag ohne Release | Abbruch, nichts wird angelegt |
| Tag auf anderem Commit | Abbruch, der Tag wird nicht verschoben |
| unveröffentlichter Entwurf | Abbruch, der Entwurf wird weder überschrieben noch gelöscht |
| Version älter als ein vorhandener Tag | Abbruch |

Die Tag-Referenz wird über die API ohne `force` angelegt; gibt es sie
inzwischen, antwortet GitHub mit 422 und nichts wird veröffentlicht. Die
Release-Jobs einer Plattform laufen nacheinander, und auf `main` werden
Paket-Läufe nicht mehr abgebrochen, damit ein Release nie mittendrin endet.

Ein abgebrochener Zustand (Tag ohne Release, Entwurf) wird bewusst nicht
automatisch repariert: erst von Hand ansehen, dann Entwurf bzw. Tag selbst
entfernen und den Release-Job neu starten („Re-run failed jobs").

## Release Notes

Aus dem Abschnitt `[<Plattform> <Version>]` in `CHANGELOG.md` — fehlt er,
entsteht kein Release. Oben stehen Plattform, Version, Build und Commit, dazu
der Hinweis zum Paket:

- iOS: „Unsigned IPA – muss vor der Installation mit einer gültigen Signatur
  signiert werden."
- webOS: „Installationspaket für LG webOS."
- macOS: Quellpaket, in Xcode signieren.

Übernommen werden nur die Abschnitte *Behoben*, *Geändert*, *Hinzugefügt*,
*Neu*, *Entfernt*, *Verbessert*, *Sicherheit*, *Bekannte Einschränkungen* und
*Hinweis zum Update*, und davon nur die für diese Plattform (`### Behoben —
macOS` fehlt in den iOS-Notes, `— beide Apple-Apps` steht in beiden). Tests,
Prüfprotokolle und Codeblöcke bleiben draußen. Sätze und Punkte, die interne
OAuth-, Secret-, Token-, `.env`-, xcconfig- oder Runner-Einzelheiten nennen,
fallen weg; bei einem Punkt mit fetter Überschrift bleibt die Überschrift.
Vor dem Veröffentlichen werden die Notes noch einmal auf Client-IDs, Secrets,
Tokens und die echten Zugangsdaten des Runners geprüft.

Vorschau am eigenen Rechner:

```bash
python3 tools/nori-release.py notes --platform webos
```

## Nachholen

Für einen schon abgeschlossenen, erfolgreichen Paket-Lauf — etwa einen aus der
Zeit vor dieser Pipeline — in Actions **Release → Run workflow** mit Plattform
und Lauf-ID, zuerst als Probelauf. Am Rechner mit Schreibrecht:

```bash
GITHUB_TOKEN="$(gh auth token)" python3 tools/nori-release.py from-run --platform ios --run-id <ID> --dry-run
```

Angenommen wird nur der jüngste erfolgreiche Lauf des Paket-Workflows auf
`main`, dessen Prüfschritte alle grün waren und dessen Version der ausgecheckte
Stand trägt. Danach dieselben Prüfungen wie oben.

## macOS später als Programm

Solange es kein signiertes macOS-Programm gibt, ist das Quellpaket der Anhang.
Für ein `.app.zip` oder `.dmg` in `PLATFORMS["macos"]` (`tools/nori-release.py`)
`kind`, `asset`, `artifact` und `content_type` ändern, unter `VERIFIERS` eine
Prüfung für die neue Paketart ergänzen und den Paket-Lauf auf das neue Artefakt
umstellen. Tag-Schema, Duplikatschutz und Notes bleiben unverändert.

## Tests

```bash
python3 tools/test_nori_release.py
```

Ohne echte Releases und ohne echte Tags: GitHub ist nachgebaut, das
Repository ein Wegwerf-Repository, alle Zugangsdaten sind erfunden. Der Lauf
**Check release pipeline** führt die Tests bei jeder Änderung an Release-Logik,
Paket-Workflows, Versionen oder Changelog aus.
