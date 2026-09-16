# Nori — Arbeitsanleitung

Anime- und Serien-App für Apple-Plattformen, Windows und LG-Fernseher. Kataloge von AniWorld und Serienstream, Merkliste, Verlauf, Wiedergabefortschritt, Kalender und integrierter Player.

## Aufbau

| Ordner | Inhalt | Bearbeiten? |
| --- | --- | --- |
| `native/NoriCore/Sources/NoriCore/` | gemeinsamer Swift-Kern | ja |
| `native/Nori-iOS/` | iOS/iPadOS, SwiftUI, Deployment-Target 17.0 | ja |
| `native/Nori-macOS/` | macOS, SwiftUI + AppKit, Deployment-Target 14.0 | ja |
| `native/Tests/` | Tests des gemeinsamen Kerns | ja |
| `shared/nori-core/` | gemeinsamer Kern in TypeScript | ja |
| `shared/nori-app/` | gemeinsame Anwendungsschicht (React) für webOS und Windows | ja |
| `apps/webos/` | LG webOS, React + TypeScript + Enact Spotlight | ja |
| `apps/windows/` | Windows, Electron: Hauptprozess + React-Oberfläche | ja |
| `services/nori-api/` | Provider-Schicht als HTTP-Dienst für die TV-App | ja |
| `config/contract.json` | kanonischer Daten-/Provider-Contract | ja |
| `tools/` | Prüfskripte | ja |

Die frühere Windows-Fassung — `desktop/` mit einem gebauten Nitro-Bundle in `server/` — ist mit Windows 2.0.0 entfallen. Sie bestand aus generierten `.mjs`-Dateien, deren Quelltext nie im Repository lag; pflegen ließ sie sich damit nicht. `apps/windows/` ersetzt sie vollständig und besteht aus Quelltext.

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
- `CatalogSearch.swift`

Die gleichnamigen Pfade in den iOS- und macOS-Ordnern sind Git-Symlinks auf diese Dateien. Änderungen am Kern deshalb **nur** in `native/NoriCore/Sources/NoriCore/` vornehmen. Die Xcode-Projekte referenzieren weiterhin ihre bekannten Pfade und bauen dadurch dieselben Quellen.

Die Oberflächen bleiben bewusst getrennt: `NoriApp.swift`, `Theme.swift`, Views und Player-Integration dürfen zwischen iOS und macOS voneinander abweichen.

## Gemeinsame Anwendungsschicht

`shared/nori-app/` liegt zwischen `shared/nori-core/` und den zwei
JavaScript-Oberflächen (`apps/webos/`, `apps/windows/`): Zustand, Dienste,
Hooks, Wiedergabeanbindung und die Bausteine, die überall gleich aussehen
(`Artwork`, `Icon`).

Sie enthält **keine** Annahme über das Gerät. Was sie darüber wissen muss,
fragt sie über `NoriPlatform` (`shared/nori-app/src/platform.ts`) — Breite der
Zeichenfläche, ob die Eingabe gerade arbeitet, wie eine fremde Adresse
geöffnet und wie die App beendet wird. Jede App meldet ihre Umsetzung beim
Start an (`installPlatform`). Wer dort `window.webOS`, `navigator.userAgent`
oder `process` abfragt, hat die Schicht falsch verstanden.

Beide Apps binden sie als **Quelltext** ein (Vite-Alias auf
`shared/nori-app/src/index.ts`, dazu `resolve.dedupe: ["react", "react-dom"]`).
Ohne `dedupe` gäbe es zwei React-Instanzen, und der Fehler meldet sich als
„Invalid hook call" an ganz anderer Stelle.

Die Oberflächen bleiben getrennt: webOS ist für drei Meter Abstand und ein
Steuerkreuz gebaut, Windows für Zeiger, Tastatur und ein Fenster, dessen
Größe sich ändert. Was dort verschieden aussieht, ist Absicht.

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

Für Windows gilt dasselbe — auch diese Toolchain ist im Container vorhanden:

```bash
npm --prefix apps/windows run build          # tsc --noEmit, esbuild, Vite
npm --prefix apps/windows run test:desktop   # Playwright startet die App
npm --prefix apps/windows run package        # Installer und ZIP
```

`test:desktop` startet die **gebaute** App über `_electron.launch` und dazu
einen Nachbau des Nori-Servers über `https:`. Unter Linux braucht es
`xvfb-run -a` davor. Wer den Installer plattformübergreifend bauen will,
braucht Wine (`wine64` **und** `wine32:i386`) — ohne die 32-Bit-Hälfte
scheitert die Deinstallationsroutine von NSIS.

Wer `shared/nori-app/**` ändert, ändert **beide** Apps. Dann gehören beide
Läufe dazu, nicht nur der der eigenen Plattform.

## Konventionen

- Oberflächentexte, README und Commit-Nachrichten sind deutsch.
- Commit-Betreff mit Plattform-/Bereichspräfix, z. B. `Apple: …`, `iOS: …`, `macOS: …`, `webOS: …`, `Windows: …`.
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
`shared/nori-core/package.json`, `shared/nori-app/package.json`,
`services/nori-api/package.json`, `API_VERSION` in
`services/nori-api/src/server.ts` und ein Abschnitt `[webOS <version>]` in
`CHANGELOG.md` samt der Übersicht am Dateianfang.
`tools/check-webos-package.py` prüft das, einschließlich der Version **im
gebauten `.ipk`**.

Weil `shared/nori-app/` in beiden Apps steckt, gilt: Wer dort etwas ändert,
erhöht **beide** Versionen — die von webOS und die von Windows. Sonst gäbe es
zwei verschiedene Fassungen unter derselben Nummer.

### Versionsnummer bei Windows

Die Windows-Version steht in `apps/windows/package.json` und im
`package.json` der Wurzel; beide müssen übereinstimmen, und ein Installer mit
neuem Inhalt braucht eine neue Nummer — aus demselben Grund wie beim
Fernseher. `electron-builder` nimmt die Nummer aus
`apps/windows/package.json` und setzt sie in Dateinamen,
Windows-Ressourcen und Deinstallationseintrag. Ein Abschnitt
`[Windows <version>]` in `CHANGELOG.md` und die Übersicht am Dateianfang
gehören dazu.

## Datenmodell

`LibraryStore.schemaVersion` ist die technische Source of Truth für das Bibliotheksschema. Aktuell: **v6**.

`config/contract.json` muss denselben Schemawert dokumentieren. Änderungen an `WatchProgress` oder der gespeicherten `Bag` brauchen eine rückwärtskompatible Migration; neue Felder möglichst optional halten.

Fortschritt wird nach `provider|normalizedEpisodePath` getrennt. Eine Serie bei AniWorld und Serienstream darf ihren Fortschritt nicht gegenseitig überschreiben.

`shared/nori-core/src/library.ts` legt denselben Aufbau ab — dieselben Felder, dieselbe Migration —, damit die webOS-App und die Apple-Apps denselben Stand lesen können.

## Synchronisation

Abgeglichen wird ausschließlich über **Google Drive**. Apple verwendet `drive.appdata` als primäre Ablage. Für die ausdrücklich aktivierte TV-Synchronisation verwendet Apple zusätzlich `drive.file` als Spiegel. webOS verwendet ausschließlich diesen `drive.file`-Spiegel. Andere Cloud-Anbieter, eigener Server oder Proxy bleiben ausgeschlossen. Einrichtung: `docs/google-drive-sync.md`, Begründungen: `docs/synchronisation.md`.

Der Grund für den Spiegel: Googles Gerätefluss für Fernseher (`/device/code`) lehnt `drive.appdata` reproduzierbar mit `invalid_scope` ab — mit mehreren TV-Clients und auch in einem separaten Google-Cloud-Projekt, entgegen Googles Dokumentation. Die Messungen stehen in `docs/google-drive-sync.md`, Abschnitt 10.

Regeln für die zwei Ablagen:

- „Mit Fernseher teilen" wird je Apple-Gerät ausdrücklich eingeschaltet und nie still aktiviert. Ohne den Schalter fragt Apple nur nach `drive.appdata` — keine Verhaltensänderung.
- Kein Umzug und kein Ersatz des `appDataFolder`. Der Spiegel wird aus dem zusammengeführten lokalen Stand erzeugt.
- Erkannt wird ausschließlich über `appProperties` (`app=nori`, `type=library-snapshot` bzw. `type=library-mirror`), nie über Name, Ordner oder Pfad. Der Ordner „Nori" ist nur für den Nutzer da.
- Eine Dateikennung gehört genau zu einer Ablage (Merkposten `nori.sync.*` bzw. `nori.sync.tvMirror.*`) und wird nie in der anderen benutzt.
- Ausschalten stoppt nur den Spiegel dieses Geräts und löscht nichts in Drive.
- Keine Ende-zu-Ende-Verschlüsselung in dieser Fassung; sie ist eine mögliche spätere Erweiterung.

Jedes Gerät schreibt je Ablage **nur seine eigene Datei** (`nori-sync-v1-<deviceId>.json`, im Spiegel `nori-tv-sync-v1-<deviceId>.json`) und liest die aller anderen. Ablauf immer **Pull → Merge → Push**, nie andersherum. Eine Master-Datei gibt es nicht.

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

Eine Ausnahme mit Ansage: Googles OAuth-Fluss für Fernseher verlangt zusätzlich ein `client_secret` (`VITE_NORI_GOOGLE_TV_CLIENT_SECRET`). Der Wert wird **nicht** eingecheckt; warum er trotzdem in der gebauten `.ipk` liegt und warum er dort nicht wirklich geheim bleibt, steht in `docs/google-drive-sync.md`.

## Google-Anmeldung

Für den Nutzer ist die Anmeldung **ein Knopf** — „Mit Google anmelden", einmal bei Google bestätigen, fertig. Client-ID, Client-Secret, Redirect-URI, Access- und Refresh-Token sind keine Benutzereinstellungen und gehören **nicht** in die Oberfläche; frühere Eingabefelder dafür sind entfernt. Fehlt die Build-Einstellung, ist das ein Build-Fehler: die Oberfläche sagt das in einem Satz und bietet kein Feld an.

Ein zugeklappter Diagnosebereich (auf webOS am Entwicklerschalter) darf Client-ID, Herkunft und Bereich zeigen — nie ein Secret und nie einen Token.

Was eine ältere Fassung im Gerät hinterlassen hat, wird weiter **gelesen** (Schlüsselbund/`UserDefaults` auf Apple, `localStorage` auf webOS) und hat Vorrang vor dem Build, weil die vorhandenen Tokens dazu gehören. Neu eintragen lässt sich nichts.

Die Flüsse: Authorization Code mit PKCE auf iOS (`ASWebAuthenticationSession`, geteilte Browser-Sitzung) und macOS (Systembrowser + Loopback), Device Authorization Grant nach RFC 8628 auf webOS. Kein `urn:ietf:wg:oauth:2.0:oob`, keine eingebettete WebView, kein eigener Auth-Server, kein Proxy. Angefordert wird auf Apple `drive.appdata` und nur nach „Mit Fernseher teilen" zusätzlich `drive.file` (mit `include_granted_scopes`), auf webOS ausschließlich `drive.file`.

Der QR-Code am Fernseher wird **im Gerät** gerechnet (`shared/nori-core/src/qr.ts`, geprüft gegen eine unabhängige Referenz) und enthält `verification_uri_complete`, wenn Google eine liefert, sonst genau `verification_uri`. Eine Adresse mit angehängtem `user_code` selbst zusammenzusetzen ist untersagt.

Tokens, Autorisierungscodes, Client-Secret, `device_code` und `user_code` gehören in **kein** Protokoll. Verbindlich beschrieben ist das alles in `config/contract.json` unter `sync.auth`.

Keine weiteren Secrets oder Zugangsdaten fest in den Quelltext schreiben.
