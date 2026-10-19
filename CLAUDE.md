# Nori — Arbeitsanleitung

Anime- und Serien-App für iPhone und iPad. Kataloge von AniWorld und Serienstream, Merkliste, Verlauf, Wiedergabefortschritt, Kalender und integrierter Player.

## Aufbau

| Ordner | Inhalt | Bearbeiten? |
| --- | --- | --- |
| `native/NoriCore/Sources/NoriCore/` | gemeinsamer Swift-Kern | ja |
| `native/Nori-iOS/` | iOS/iPadOS, SwiftUI, Deployment-Target 17.0 | ja |
| `native/Nori-Android/` | Android (später auch Google TV), Compose + Media3, `minSdk` 28; Kern über JNI (`NoriCore/Sources/NoriCore/Android/`) | ja |
| `native/Tests/` | Tests des gemeinsamen Kerns | ja |
| `config/contract.json` | kanonischer Daten-/Provider-Contract | ja |
| `tools/` | Prüfskripte | ja |

macOS, Windows und LG webOS sind mit Nori 2.8.0 eingestellt; ihr Quelltext
(`native/Nori-macOS/`, `apps/`, `shared/`, `services/`) liegt nur noch in der
Git-Geschichte. Nicht wieder anlegen, ohne dass der Nutzer es ausdrücklich will.

Android ist seit Nori 2.9.0 im Repository und trägt dieselbe Nummer (gelesen
aus dem iOS-Projekt). Gebaut wird nur von Hand über „Build Android" auf
Linux; Plan und Einzelheiten: `docs/android.md`.

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

Die gleichnamigen Pfade im iOS-Ordner sind Git-Symlinks auf diese Dateien. Änderungen am Kern deshalb **nur** in `native/NoriCore/Sources/NoriCore/` vornehmen. Das Xcode-Projekt referenziert weiterhin seine bekannten Pfade; SwiftPM (`native/Package.swift`) baut dieselben Quellen für die Tests.

## Bauen und Prüfen

Vor jedem Push:

```bash
python3 tools/check-apple-sources.py
cd native && swift test
python3 tools/nori-version.py check --against origin/main
```

Die echten App-Typechecks laufen über GitHub Actions auf `macos-26`:

- `Build iOS`
- `Swift tests`

Änderungen an `native/NoriCore/**` müssen `Build iOS` und `Swift tests` auslösen.

Das Projekt ist privat, Actions-Minuten sind knapp: keine neuen Workflows oder
Trigger ohne Not, die macOS-Läufe nur über Pfadfilter auf `native/**`.

## Konventionen

- Oberflächentexte, README und Commit-Nachrichten sind deutsch.
- Commit-Betreff mit Plattform-/Bereichspräfix, z. B. `Apple: …`, `iOS: …`, `CI: …`.
- `SWIFT_VERSION = 5.0` ist der Sprachmodus, nicht die Compilerversion.
- Die öffentliche Version ist die Nori-Version. Sie gelangt ausschließlich über `MARKETING_VERSION` des Xcode-Projekts ins Bundle.
- `config/contract.json` enthält keine App-Version.

### Versionsnummer

Die App trägt eine Nummer `x.y.z`. Gesetzt und geprüft wird sie mit
`tools/nori-version.py` (Xcode-Projekt, `MARKETING_VERSION` aller
Konfigurationen):

```bash
python3 tools/nori-version.py show
python3 tools/nori-version.py bump patch|minor|major   # oder: set x.y.z
python3 tools/nori-version.py check --against origin/main
```

Jeder neue installierbare Stand braucht eine **höhere** Nummer. Es dürfen
niemals zwei unterschiedliche Pakete mit derselben Version entstehen: auf einem
Gerät installiert steht dann eine Fassung, die sich von außen nicht mehr von
der anderen unterscheiden lässt, und ein Fehlerbericht dazu ist nicht mehr
zuzuordnen. `bump` und `set` erhöhen deshalb auch `CURRENT_PROJECT_VERSION`
(die Buildnummer) von iOS. Nach Semantic Versioning: Fehlerbehebung
→ `patch`, neue Funktion → `minor`, Inkompatibles → `major`.

Dazu gehören ein Abschnitt `## [Nori x.y.z]` in `CHANGELOG.md` (Unterabschnitte
*Allgemein*, *iOS / iPadOS*, *Technische Änderungen* — nur die mit echten Änderungen),
`Nori **x.y.z**` in dessen Übersicht und in `README.md` unter „Aktueller
Stand“.

`check` verlangt auf einem Branch, der etwas ändert, das in einem Paket landet,
eine Nummer über jeder auf `main`; „Check release pipeline“ prüft das bei jedem
Push. `tools/nori-release.py verify` prüft die Version in der IPA.

### Releases

Ein Release entsteht nur über den Workflow **Nori Release**
(`.github/workflows/release.yml`, von Hand): ein Tag `v<VERSION>`, ein GitHub
Release `Nori v<VERSION>`, das Paket `Nori-iOS-v<VERSION>.ipa` und
`checksums-sha256.txt`. Keine Plattform-Tags mehr (`ios-v…`, `macos-v…`), kein
Tag von Hand, kein Release aus einem Plattform-Lauf. Erst nach dem
nachgeprüften Release löscht er alte Läufe der Nori-Workflows — nie Releases,
Anhänge, Tags oder Branches. Regeln: `docs/releases.md`, Logik:
`tools/nori-release.py`.

## Datenmodell

`LibraryStore.schemaVersion` ist die technische Source of Truth für das Bibliotheksschema. Aktuell: **v6**.

`config/contract.json` muss denselben Schemawert dokumentieren. Änderungen an `WatchProgress` oder der gespeicherten `Bag` brauchen eine rückwärtskompatible Migration; neue Felder möglichst optional halten.

Fortschritt wird nach `provider|normalizedEpisodePath` getrennt. Eine Serie bei AniWorld und Serienstream darf ihren Fortschritt nicht gegenseitig überschreiben.

## Synchronisation

Abgeglichen wird ausschließlich über **Google Drive**. iOS verwendet `drive.appdata` als einzige Ablage. Den TV-Spiegel (`drive.file`) und den Schalter „Mit Fernseher teilen" gibt es seit 2.8.0 in der Oberfläche nicht mehr; `NoriApp` schaltet einen eingeschalteten Spiegel beim Start aus und löscht nichts. Der Spiegel-Code im Kern (`TVMirrorState`, `mirrorEngine`, `DriveSpace.tvMirror`) ruht und ist samt Tests noch vorhanden; die Regeln unten gelten für ihn, falls er je wieder angeschaltet wird. Andere Cloud-Anbieter, eigener Server oder Proxy bleiben ausgeschlossen. Einrichtung: `docs/google-drive-sync.md`, Begründungen: `docs/synchronisation.md`.

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

Die Merge-Regeln sind eine reine Funktion in `LibrarySync.swift`. Sie läuft gegen die Fälle in `config/sync-fixtures.json`; wer eine Regel ändert, ändert sie in Swift und in `config/contract.json`.

Tokens gehören in den Schlüsselbund und niemals in `library.json`, ins Protokoll oder in die Cloud.

## Contract

Kanonisch:

```text
config/contract.json
```

`native/Nori-iOS/contract.json` ist nur ein Kompatibilitäts-Symlink darauf.

## Hoster

`HosterResolver` akzeptiert nur HTTPS-Ziele und blockiert lokale/private Netzwerkadressen. Diese Prüfung nicht aufweichen.

Hoster ändern ihre Seiten häufig. Stream-Auflösungsfehler zuerst anhand Redirect, Referer, Schutzseite und Hoster-spezifischer Extraktion untersuchen.

## Schlüssel

Der TMDB-Schlüssel kann über Schlüsselbund bzw. Build-Einstellung bereitgestellt werden. Im aktuellen privaten Projekt existiert zusätzlich bewusst ein eingebauter Fallback-Schlüssel in `TMDBKeyStore`; diese Ausnahme ist eng begrenzt und in `tools/check-apple-sources.py` dokumentiert.

Die Google-Client-ID kommt ebenso aus einer Build-Einstellung (`GOOGLE_CLIENT_ID`, in der CI das Secret `NORI_GOOGLE_IOS_CLIENT_ID`) und nicht aus dem Quelltext.

## Google-Anmeldung

Für den Nutzer ist die Anmeldung **ein Knopf** — „Mit Google anmelden", einmal bei Google bestätigen, fertig. Client-ID, Client-Secret, Redirect-URI, Access- und Refresh-Token sind keine Benutzereinstellungen und gehören **nicht** in die Oberfläche; frühere Eingabefelder dafür sind entfernt. Fehlt die Build-Einstellung, ist das ein Build-Fehler: die Oberfläche sagt das in einem Satz und bietet kein Feld an.

Ein zugeklappter Diagnosebereich darf Client-ID, Herkunft und Bereich zeigen — nie ein Secret und nie einen Token.

Was eine ältere Fassung im Gerät hinterlassen hat, wird weiter **gelesen** (Schlüsselbund/`UserDefaults`) und hat Vorrang vor dem Build, weil die vorhandenen Tokens dazu gehören. Neu eintragen lässt sich nichts.

Der Fluss: Authorization Code mit PKCE (`ASWebAuthenticationSession`, geteilte Browser-Sitzung). Kein `urn:ietf:wg:oauth:2.0:oob`, keine eingebettete WebView, kein eigener Auth-Server, kein Proxy. Angefordert wird nur `drive.appdata`.

Tokens, Autorisierungscodes und Secrets gehören in **kein** Protokoll. Verbindlich beschrieben ist das alles in `config/contract.json` unter `sync.auth`.

Keine weiteren Secrets oder Zugangsdaten fest in den Quelltext schreiben.
