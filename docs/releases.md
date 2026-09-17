# GitHub-Releases

Nori hat eine einheitliche Versionsnummer für alle Plattformen und deshalb auch
einen gemeinsamen Release pro Version. Er entsteht automatisch, sobald die
Plattform-Pakete auf `main` gebaut und geprüft sind — niemand setzt dafür einen
Tag von Hand.

| Plattform | Anhang | Quelle |
| --- | --- | --- |
| iOS/iPadOS | `Nori-iOS-<VERSION>-unsigned.ipa` | Package iOS IPA |
| LG webOS | `tv.nori.app_<VERSION>_all.ipk` | Build webOS |
| macOS | `Nori-macOS-<VERSION>-source.zip` | Package macOS Source |

Alle drei Anhänge landen im selben Release mit dem einheitlichen Tag `v<VERSION>`
(z. B. `v2.3.0`).

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
5. Prüfen, dass der Commit auf `main` liegt.
6. Den Entwurf anlegen, falls er noch fehlt, sonst das Paket anhängen, den
   Anhang über die Prüfsumme gegenprüfen. Ist der Entwurf durch diesen Anhang
   vollständig (alle drei Plattformen), annotierten Tag auf den geprüften
   Commit setzen, veröffentlichen, Endzustand prüfen — sonst wartet er auf
   die anderen Plattformen.

## Sammel-Release, Duplikate und Tags

| Zustand | Ergebnis |
| --- | --- |
| weder Tag noch Entwurf | Entwurf wird angelegt, Paket angehängt |
| Entwurf existiert, Paket fehlt noch | Paket wird angehängt |
| Entwurf ist vollständig (alle drei Plattformen) | Tag wird gesetzt, Release wird veröffentlicht |
| Release veröffentlicht, trägt dieses Paket schon | grün, keine Änderung |
| Release veröffentlicht, ohne dieses Paket | Abbruch — nicht nachträglich anhängbar |
| Tag ohne Release | Abbruch, nichts wird angelegt |
| Tag auf anderem Commit | Abbruch, der Tag wird nicht verschoben |
| unveröffentlichter Entwurf, trägt dieses Paket schon | Abbruch — bitte von Hand prüfen |
| mehrere Entwürfe derselben Version | Abbruch — bitte von Hand aufräumen |
| Version älter als ein vorhandener Tag | Abbruch |

Die Tag-Referenz wird über die API ohne `force` angelegt; gibt es sie
inzwischen, antwortet GitHub mit 422 und nichts wird veröffentlicht. Kein
Workflow reagiert auf Tags: alle Push-Auslöser sind auf Branches beschränkt,
ein neuer Release-Tag startet also weder Builds noch einen weiteren Release —
auch nicht, wenn er beim Nachholen mit einem persönlichen Token entsteht. Die
Release-Jobs einer Version laufen nacheinander (gleiche `concurrency`-Gruppe),
und auf `main` werden Paket-Läufe nicht mehr abgebrochen, damit ein Release nie
mittendrin endet.

Ein abgebrochener Zustand (Tag ohne Release, mehrere Entwürfe, Entwurf mit
unerwartetem Anhang) wird bewusst nicht automatisch repariert: erst von Hand
ansehen, dann aufräumen und den Release-Job neu starten („Re-run failed jobs").

## Release Notes

Der gemeinsame Release-Body fasst alle drei Plattformen zusammen. Für jede
Plattform wird der Abschnitt `[<Plattform> <Version>]` aus `CHANGELOG.md`
gerendert — fehlt einer, entsteht kein Release. Oben stehen Version, Commit und
die Liste der Pakete; je Plattform stehen Version, Build (wo vorhanden) und
der Hinweis zum Paket:

- iOS: „Unsigned IPA – muss vor der Installation mit einer gültigen Signatur
  signiert werden."
- webOS: „Installationspaket für LG webOS."
- macOS: Quellpaket, in Xcode signieren.

Übernommen werden nur die Abschnitte *Behoben*, *Geändert*, *Hinzugefügt*,
*Neu*, *Entfernt*, *Verbessert*, *Sicherheit*, *Bekannte Einschränkungen* und
*Hinweis zum Update*, und davon nur die für die jeweilige Plattform (`### Behoben —
macOS` fehlt im iOS-Block, `— beide Apple-Apps` steht in beiden). Tests,
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
