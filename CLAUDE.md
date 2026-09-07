# Nori — Arbeitsanleitung

Anime- und Serien-App für Apple-Plattformen, Windows und LG-Fernseher. Kataloge
von AniWorld (Anime) und Serienstream (Serien), Merkliste, Verlauf,
Wiedergabefortschritt, Kalender, integrierter Player.

## Aufbau

| Ordner | Inhalt | Bearbeiten? |
| --- | --- | --- |
| `native/Nori-iOS/` | iOS/iPadOS, SwiftUI, Deployment-Target 17.0 | ja |
| `native/Nori-macOS/` | macOS, SwiftUI + AppKit, Deployment-Target 14.0 | ja |
| `desktop/` | Electron-Hülle für Windows | ja |
| `apps/webos/` | LG webOS, React + TypeScript + Enact Spotlight | ja |
| `shared/nori-core/` | geteilter Kern in TypeScript | ja |
| `services/nori-api/` | Provider-Schicht als HTTP-Dienst | ja |
| `server/` | **gebautes** Nitro/Node-Bundle | nein, generiert |
| `tools/` | Prüfskripte | ja |

`server/` besteht aus minifizierten `.mjs`-Dateien mit Hash-Namen. Das ist
Build-Ausgabe, kein Quellcode — Änderungen daran sind immer falsch.

## Zwei Kerne, ein Vertrag

Es gibt den Kern **zweimal**: in Swift für die Apple-Targets und in TypeScript
unter `shared/nori-core` für webOS und den Nori-Server. Das ist keine Dublette
aus Versehen — TypeScript kann Swift nicht einbinden —, aber es ist eine
Gefahr: Feldnamen, die 90-%-Regel, die Resume-Schwelle, der Schlüssel
`provider|episodePath`, die Hoster-Rangfolge und die Sprachwahl **müssen** auf
beiden Seiten gleich sein. Maßgeblich ist `native/*/contract.json`.

Wer eine dieser Regeln ändert, ändert sie an drei Stellen: Swift, TypeScript,
contract.json — und in beiden Testreihen, die absichtlich dieselben
HTML-Ausschnitte benutzen (`native/Tests/NoriCoreTests/Fixtures.swift` und
`shared/nori-core/test/fixtures.ts`).

## Die wichtigste Regel

Die beiden Apple-Targets haben teilweise **gleiche Dateinamen bei
unterschiedlichem Inhalt**. Fünf Dateien müssen byte-gleich bleiben
(`Models`, `LibraryStore`, `AniworldClient`, `HosterResolver`, `HTML`),
sämtliche Views sowie `NoriApp.swift` und `Theme.swift` laufen seit dem
macOS-Umbau dagegen **bewusst** auseinander.

Die macOS-App war ursprünglich eine fast wörtliche Kopie der iOS-App. Dadurch
liefen mehrere iOS-Muster auf dem Mac ins Leere (`.refreshable` ohne Wirkung,
Drag-Gesten ohne Touch, erzwungenes Dark Mode). Diese Kopie nicht
wiederherstellen.

Details: `.claude/skills/apple-parity/SKILL.md`.

## Bauen und Prüfen

**Es gibt in dieser Umgebung keinen Swift-Compiler.** Der einzige Typechecker
ist der GitHub-Actions-Lauf `Build macOS` (~1 Minute, ausgelöst durch Pushes
auf `native/Nori-macOS/**`). Er läuft wie alle Workflows auf einem
self-hosted Mac — ist der aus, warten die Jobs in der Warteschlange, statt zu
scheitern. Einrichtung: `docs/self-hosted-runner.md`.

Vor jedem Push:

```bash
python3 tools/check-apple-sources.py
```

Prüft Target-Trennung, geteilte Dateien, die API-Decke und eine gepflegte
Liste nicht existierender APIs. Sekundenschnell, ersetzt aber keinen Build.
Nach jedem roten Build gehört die Ursache dort als neue Zeile hinein.

**Für die webOS-Seite** gibt es echte Prüfungen, die hier durchlaufen — anders
als bei Swift ist die Toolchain vorhanden:

```bash
npm --prefix shared/nori-core test     # 34 Tests gegen dieselben Fixtures
npm --prefix apps/webos run build      # tsc --noEmit und Vite
python3 tools/check-webos-package.py   # Quelltext, .ipk, appinfo.json
```

Die Oberfläche lässt sich zusätzlich mit einer nachgebauten Fernbedienung
durchspielen (`apps/webos/test/`, siehe `docs/webos.md`). Der Lauf braucht
Playwright und einen Chromium; er ist bewusst keine Abhängigkeit des Pakets.

Wie man die CI-Logs auswertet und was ein PR zum Fertigwerden braucht:
`.claude/skills/steward/SKILL.md`.

Auf einem echten Mac:

```bash
open native/Nori-macOS/NoriMac.xcodeproj   # Scheme „Nori", Ziel „My Mac", ⌘R
```

SwiftSoup wird als Swift-Package aufgelöst. Zum reinen Starten reicht ein
Personal Team unter Signing & Capabilities; iCloud-Sync braucht zusätzlich die
Key-Value-Store-Capability, die noch nicht eingerichtet ist.

## Arbeitsweise

Durcharbeiten, nicht nachfragen. Eine Aufgabe wird bis zum Ende gebracht —
Änderung, `tools/check-apple-sources.py`, Commit, Push, PR, CI-Lauf auswerten,
rote Läufe reparieren — ohne zwischendurch auf eine Bestätigung zu warten.
Enthält eine Anfrage mehrere Punkte, folgt der nächste Punkt direkt auf den
vorigen; größere Punkte werden zu eigenen PRs, aber nacheinander und
selbstständig.

Nachgefragt wird nur, wenn eine Angabe fehlt, die niemand außer dem Betreiber
liefern kann (etwa eine OAuth-Client-ID) oder wenn zwei Auslegungen zu
grundverschiedener Arbeit führen würden. Fragen der Form „soll ich bauen /
testen / committen?" gehören nicht dazu.

## Konventionen

- Oberflächentexte, README und Commit-Nachrichten sind **deutsch**.
- Commit-Betreff mit Plattform-Präfix: `macOS: …`, `iOS: …`, `webOS: …`.
- `SWIFT_VERSION = 5.0` ist der Sprachmodus, nicht die Compilerversion.
- Versionsnummern und `CHANGELOG.md` bei jeder Funktionsänderung mitpflegen;
  die Stellen listet `.claude/skills/steward/SKILL.md`. Die Plattformen haben
  eigene Stände.

## Datenmodell

`LibraryStore` hält Merkliste, Verlauf und Fortschritt in
`~/Library/Application Support/Nori/library.json`, Schema **v4**. Die
webOS-App legt denselben Aufbau im `localStorage` des Fernsehers ab
(`shared/nori-core/src/library.ts`) — dieselben Felder, dieselbe Migration.

Fortschritt wird nach `provider|episodePath` geschlüsselt — dieselbe Serie bei
AniWorld und Serienstream bleibt getrennt. Wer Felder in `WatchProgress` oder
`Bag` ändert: neue Felder optional halten, `migrateProgress` erweitern und
`schemaVersion` erhöhen, sonst verlieren bestehende Installationen ihren
Stand.

## Hoster

`HosterResolver` akzeptiert nur HTTPS-Ziele und blockt lokale und private
Netzwerkadressen. Diese Prüfung nicht aufweichen. Hoster ändern ihre Seiten
jederzeit — schlägt die Stream-Auflösung fehl, liegt das häufig dort und nicht
am Nori-Code.

## Schlüssel

Keine Schlüssel im Quelltext — `tools/check-apple-sources.py` meldet lange
Hex-Zeichenketten und Zuweisungen an Namen wie `apiKey`.

Der TMDB-Schlüssel kommt aus `TMDBKeyStore` (in `AniworldClient.swift`):
Schlüsselbund zuerst, sonst `TMDBAPIKey` aus der Info.plist, die aus der
Build-Einstellung `TMDB_API_KEY` gefüllt wird. Ohne Schlüssel fragt die App
TMDB gar nicht erst an und zeigt die Cover von AniWorld und Serienstream — das
ist ein gültiger Zustand, kein Fehler.
