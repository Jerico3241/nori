# Nori — Arbeitsanleitung

Anime- und Serien-App für Apple-Plattformen, Windows und LG-Fernseher. Kataloge von AniWorld und Serienstream, Merkliste, Verlauf, Wiedergabefortschritt, Kalender und integrierter Player.

## Aufbau

| Ordner | Inhalt | Bearbeiten? |
| --- | --- | --- |
| `native/NoriCore/Sources/NoriCore/` | gemeinsamer Swift-Kern | ja |
| `native/Nori-iOS/` | iOS/iPadOS, SwiftUI, Deployment-Target 17.0 | ja |
| `native/Nori-macOS/` | macOS, SwiftUI + AppKit, Deployment-Target 14.0 | ja |
| `native/Tests/` | Tests des gemeinsamen Kerns | ja |
| `desktop/` | Electron-Hülle für Windows | ja |
| `server/` | gebautes Nitro/Node-Bundle | nein, generiert |
| `shared/nori-core/` | gemeinsamer Kern in TypeScript | ja |
| `apps/webos/` | LG webOS, React + TypeScript + Enact Spotlight | ja |
| `services/nori-api/` | Provider-Schicht als HTTP-Dienst für die TV-App | ja |
| `config/contract.json` | kanonischer Daten-/Provider-Contract | ja |
| `tools/` | Prüfskripte | ja |

`server/` besteht aus generierten `.mjs`-Dateien mit Hash-Namen. Änderungen daran sind falsch; der ursprüngliche Web-Sourcecode gehört separat ins Repository, falls Windows wieder aktiv weiterentwickelt wird.

## Gemeinsamer Apple-Core

Diese Dateien existieren kanonisch nur unter `native/NoriCore/Sources/NoriCore/`:

- `Models.swift`
- `LibraryStore.swift`
- `LibrarySync.swift`
- `LibrarySyncEngine.swift`
- `GoogleDrive.swift`
- `GoogleOAuth.swift`
- `GoogleAuthorization.swift`
- `NoriSync.swift`
- `AniworldClient.swift`
- `HosterResolver.swift`
- `HTML.swift`
- `HLSPlaylist.swift`

Die gleichnamigen Pfade in den iOS- und macOS-Ordnern sind Git-Symlinks auf diese Dateien. Änderungen am Kern deshalb **nur** in `native/NoriCore/Sources/NoriCore/` vornehmen. Die Xcode-Projekte referenzieren weiterhin ihre bekannten Pfade und bauen dadurch dieselben Quellen.

Die Oberflächen bleiben bewusst getrennt: `NoriApp.swift`, `Theme.swift`, Views und Player-Integration dürfen zwischen iOS und macOS voneinander abweichen.

## Zweiter Kern: TypeScript

Den Kern gibt es **zweimal** — in Swift unter `native/NoriCore/` für die
Apple-Apps und in TypeScript unter `shared/nori-core/` für die webOS-App und
den Nori-Server. Das ist keine versehentliche Dublette, TypeScript kann Swift
nicht einbinden; es ist aber eine Gefahr.

Maßgeblich ist für beide `config/contract.json`. Gleich bleiben müssen
insbesondere: Feldnamen, die 90-%-Abschlussregel, die Resume-Schwelle von
8 Sekunden, der Schlüssel `provider|normalizedEpisodePath`, die
Hoster-Rangfolge und die Sprachreihenfolge.

Wer eine dieser Regeln ändert, ändert sie an drei Stellen — Swift,
TypeScript, `config/contract.json` — und in **beiden** Testreihen. Die
benutzen absichtlich dieselben HTML-Ausschnitte:

- `native/Tests/NoriCoreTests/Fixtures.swift`
- `shared/nori-core/test/fixtures.ts`

## Bauen und Prüfen

Vor jedem Push:

```bash
python3 tools/check-apple-sources.py
cd native && swift test
```

Die echten App-Typechecks laufen über GitHub Actions auf dem self-hosted Mac:

- `Build iOS`
- `Build macOS`
- `Swift tests`

Änderungen an `native/NoriCore/**` müssen beide Apple-Builds auslösen.

Für die webOS-Seite gibt es echte Prüfungen, die auch im Container durchlaufen
— anders als bei Swift ist die Toolchain dort vorhanden:

```bash
npm --prefix shared/nori-core test     # Kern gegen dieselben Fixtures
npm --prefix apps/webos run build      # tsc --noEmit und Vite
python3 tools/check-webos-package.py   # Quelltext, .ipk, appinfo.json
```

Die Oberfläche lässt sich zusätzlich mit einer nachgebauten Fernbedienung
durchspielen (`apps/webos/test/`, siehe `docs/webos.md`). Der Lauf `Build
webOS` macht dasselbe in der CI und braucht dort kein Xcode, nur Node.

## Konventionen

- Oberflächentexte, README und Commit-Nachrichten sind deutsch.
- Commit-Betreff mit Plattform-/Bereichspräfix, z. B. `Apple: …`, `iOS: …`, `macOS: …`, `webOS: …`.
- `SWIFT_VERSION = 5.0` ist der Sprachmodus, nicht die Compilerversion.
- App-Versionen stammen auf den Apple-Plattformen ausschließlich aus `MARKETING_VERSION` der jeweiligen Xcode-Projekte.
- `config/contract.json` enthält keine App-Version.

### Versionsnummer bei webOS

Jedes neue installierbare webOS-Paket braucht eine **höhere** Nummer. Es dürfen
niemals zwei unterschiedliche `.ipk` mit derselben Version entstehen: auf dem
Fernseher installiert steht dann eine Fassung, die sich von außen nicht mehr von
der anderen unterscheiden lässt, und ein Fehlerbericht dazu ist nicht mehr
zuzuordnen.

Gleich stehen müssen `apps/webos/appinfo.json`, `apps/webos/package.json`,
`shared/nori-core/package.json`, `services/nori-api/package.json`,
`API_VERSION` in `services/nori-api/src/server.ts` und ein Abschnitt
`[webOS <version>]` in `CHANGELOG.md` samt der Übersicht am Dateianfang.
`tools/check-webos-package.py` prüft das, einschließlich der Version **im
gebauten `.ipk`**.

## Datenmodell

`LibraryStore.schemaVersion` ist die technische Source of Truth für das Bibliotheksschema. Aktuell: **v6**.

`config/contract.json` muss denselben Schemawert dokumentieren. Änderungen an `WatchProgress` oder der gespeicherten `Bag` brauchen eine rückwärtskompatible Migration; neue Felder möglichst optional halten.

Fortschritt wird nach `provider|normalizedEpisodePath` getrennt. Eine Serie bei AniWorld und Serienstream darf ihren Fortschritt nicht gegenseitig überschreiben.

`shared/nori-core/src/library.ts` legt denselben Aufbau ab — dieselben Felder, dieselbe Migration —, damit die webOS-App und die Apple-Apps denselben Stand lesen können.

## Synchronisation

Abgeglichen wird ausschließlich über **Google Drive**, und dort ausschließlich im versteckten `appDataFolder` (Bereich `drive.appdata`). Kein iCloud, kein Dropbox, kein WebDAV, kein eigener Server, kein Proxy. Einrichtung: `docs/google-drive-sync.md`, Begründungen: `docs/synchronisation.md`.

Jedes Gerät schreibt **nur seine eigene Datei** (`nori-sync-v1-<deviceId>.json`) und liest die aller anderen. Ablauf immer **Pull → Merge → Push**, nie andersherum.

Die Schichten bleiben getrennt:

```text
LibraryStore → LibrarySyncEngine → LibrarySnapshotStore → GoogleDriveClient → GoogleAuthorization
```

Keine OAuth-Logik in `LibraryStore`, kein Drive-HTTP in Views oder React-Komponenten. `LibrarySyncProvider` (eine Datei ablegen und holen) bleibt als Abstraktion bestehen und wird nicht entfernt.

Die Merge-Regeln sind eine reine Funktion und existieren zweimal — `LibrarySync.swift` und `shared/nori-core/src/sync.ts`. Beide laufen gegen dieselben Fälle in `config/sync-fixtures.json`; wer eine Regel ändert, ändert sie in Swift, in TypeScript und in `config/contract.json`.

Tokens gehören in den Schlüsselbund und niemals in `library.json`, ins Protokoll oder in die Cloud.

## Contract

Kanonisch:

```text
config/contract.json
```

`native/Nori-iOS/contract.json` und `native/Nori-macOS/contract.json` sind nur Kompatibilitäts-Symlinks darauf.

## Hoster

`HosterResolver` akzeptiert nur HTTPS-Ziele und blockiert lokale/private Netzwerkadressen. Diese Prüfung nicht aufweichen.

Hoster ändern ihre Seiten häufig. Stream-Auflösungsfehler zuerst anhand Redirect, Referer, Schutzseite und Hoster-spezifischer Extraktion untersuchen.

## Schlüssel

Der TMDB-Schlüssel kann über Schlüsselbund bzw. Build-Einstellung bereitgestellt werden. Im aktuellen privaten Projekt existiert zusätzlich bewusst ein eingebauter Fallback-Schlüssel in `TMDBKeyStore`; diese Ausnahme ist eng begrenzt und in `tools/check-apple-sources.py` dokumentiert.

Die Google-Client-IDs kommen ebenso aus Build-Einstellungen (`GOOGLE_CLIENT_ID` auf Apple, `VITE_NORI_GOOGLE_TV_CLIENT_ID` auf webOS) und nicht aus dem Quelltext.

Eine Ausnahme mit Ansage: Googles OAuth-Fluss für Fernseher verlangt zusätzlich ein `client_secret` (`VITE_NORI_GOOGLE_TV_CLIENT_SECRET`). Der Wert wird **nicht** eingecheckt; warum er trotzdem in der gebauten `.ipk` liegt, steht in `docs/google-drive-sync.md`.

Keine weiteren Secrets oder Zugangsdaten fest in den Quelltext schreiben.
