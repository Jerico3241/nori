# Nori — Arbeitsanleitung

Anime- und Serien-App für Apple-Plattformen, Android und Windows. Kataloge von AniWorld und Serienstream, Merkliste, Verlauf, Wiedergabefortschritt, Kalender und integrierter Player.

## Aufbau

| Ordner | Inhalt | Bearbeiten? |
| --- | --- | --- |
| `native/NoriCore/Sources/NoriCore/` | gemeinsamer Swift-Kern | ja |
| `native/Nori-iOS/` | iOS/iPadOS, SwiftUI, Deployment-Target 17.0 | ja |
| `native/Nori-macOS/` | macOS, SwiftUI + AppKit, Deployment-Target 14.0 | ja |
| `native/Nori-Android/` | Android, Kotlin + Compose + Media3, minSdk 28 | ja |
| `native/Tests/` | Tests des gemeinsamen Kerns | ja |
| `desktop/` | Electron-Hülle für Windows | ja |
| `server/` | gebautes Nitro/Node-Bundle | nein, generiert |
| `config/contract.json` | kanonischer Daten-/Provider-Contract | ja |
| `tools/` | Prüfskripte | ja |

`server/` besteht aus generierten `.mjs`-Dateien mit Hash-Namen. Änderungen daran sind falsch; der ursprüngliche Web-Sourcecode gehört separat ins Repository, falls Windows wieder aktiv weiterentwickelt wird.

## Android

Die Oberfläche ist Compose, die Logik bleibt der Swift-Kern. Verbunden sind
beide über **eine** C-Funktion mit JSON hinein und heraus:

```text
Compose → ViewModels → NoriCore.kt → NoriBridge (JNI) → nori_bridge_call (Swift)
```

Die Swift-Seite steht in `native/NoriCore/Sources/NoriCore/Android/` und
vollständig in `#if os(Android)`; die Xcode-Projekte listen ihre Quellen
einzeln und sehen sie nicht.

Regel wie beim Kern: **keine zweite Implementierung.** Kein Kotlin-Parser für
AniWorld oder Serienstream, keine eigenen Fortschrittsregeln, keine parallele
Bibliotheksdatei. Was der Kern kann, wird gefragt.

Details, Einrichtung und bekannte Einschränkungen: `docs/android.md`.

## Gemeinsamer Apple-Core

Diese Dateien existieren kanonisch nur unter `native/NoriCore/Sources/NoriCore/`:

- `Models.swift`
- `LibraryStore.swift`
- `AniworldClient.swift`
- `HosterResolver.swift`
- `HTML.swift`

Die gleichnamigen Pfade in den iOS- und macOS-Ordnern sind Git-Symlinks auf diese Dateien. Änderungen am Kern deshalb **nur** in `native/NoriCore/Sources/NoriCore/` vornehmen. Die Xcode-Projekte referenzieren weiterhin ihre bekannten Pfade und bauen dadurch dieselben Quellen.

Die Oberflächen bleiben bewusst getrennt: `NoriApp.swift`, `Theme.swift`, Views und Player-Integration dürfen zwischen iOS und macOS voneinander abweichen.

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

## Konventionen

- Oberflächentexte, README und Commit-Nachrichten sind deutsch.
- Commit-Betreff mit Plattform-/Bereichspräfix, z. B. `Apple: …`, `iOS: …`, `macOS: …`.
- `SWIFT_VERSION = 5.0` ist der Sprachmodus, nicht die Compilerversion.
- App-Versionen stammen ausschließlich aus `MARKETING_VERSION` der jeweiligen Xcode-Projekte.
- `config/contract.json` enthält keine App-Version.

## Datenmodell

`LibraryStore.schemaVersion` ist die technische Source of Truth für das Bibliotheksschema. Aktuell: **v4**.

`config/contract.json` muss denselben Schemawert dokumentieren. Änderungen an `WatchProgress` oder der gespeicherten `Bag` brauchen eine rückwärtskompatible Migration; neue Felder möglichst optional halten.

Fortschritt wird nach `provider|normalizedEpisodePath` getrennt. Eine Serie bei AniWorld und Serienstream darf ihren Fortschritt nicht gegenseitig überschreiben.

## Synchronisation

Der Core kennt nur das Protokoll `LibrarySyncProvider`. Konkrete Anbieter wie Google Drive, Dropbox oder WebDAV werden außerhalb des Stores angebunden. Ohne Provider bleibt Nori lokal.

Keine Cloud-Implementierung direkt in `LibraryStore` verdrahten.

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

Keine weiteren Secrets oder Zugangsdaten fest in den Quelltext schreiben.
