# Nori

Nori ist eine native Anime- und Serien-App mit Katalog, Suche, Merkliste, Verlauf, Wiedergabefortschritt, Resume, Kalender und integriertem Player.

Unterstützte Quellen:

- **AniWorld** für Anime
- **Serienstream** für Serien

Die App nutzt verfügbare Hoster nach Priorität und erlaubt während der Wiedergabe den Wechsel von Hoster und Sprache.

> **Privates Projekt.** Nori ist nicht mit AniWorld oder Serienstream verbunden.

Änderungen je Version: [CHANGELOG.md](CHANGELOG.md)

## Aktueller Stand

| Plattform | Version | Status |
| --- | --- | --- |
| iOS / iPadOS | **1.14.5** | Native SwiftUI-App, aktueller Hauptstand |
| macOS | **1.14.2** | Native SwiftUI-App mit eigener Mac-Oberfläche |
| Windows | **1.8.0** | Electron / Node Portable Build, Legacy-Stand |

## Projektstruktur

```text
nori/
├── native/
│   ├── NoriCore/
│   │   └── Sources/NoriCore/     # gemeinsame Swift-Kernlogik
│   ├── Nori-iOS/                 # iOS/iPadOS SwiftUI + AVPlayer
│   ├── Nori-macOS/               # macOS SwiftUI + AVKit/AppKit
│   ├── Package.swift             # NoriCore für Tests/Android
│   └── Tests/NoriCoreTests/      # Tests des gemeinsamen Kerns
├── config/
│   └── contract.json             # kanonischer Daten-/Provider-Contract
├── desktop/                      # Electron-Hülle des Windows-Legacy-Stands
├── server/                       # gebautes Nitro/Node-Bundle, kein Quellcode
├── docs/
├── tools/
└── .github/workflows/
```

### Gemeinsamer Apple-Core

`Models.swift`, `LibraryStore.swift`, `HTML.swift`, `AniworldClient.swift` und `HosterResolver.swift` existieren nur noch einmal unter:

```text
native/NoriCore/Sources/NoriCore/
```

Die bestehenden Pfade in `native/Nori-iOS/Nori/` und `native/Nori-macOS/Nori/` sind Git-Symlinks auf diese gemeinsame Quelle. Dadurch bleiben die handgeschriebenen Xcode-Projekte stabil, während iOS und macOS garantiert dieselbe Kernimplementierung bauen.

Die Oberflächen bleiben bewusst plattformspezifisch. iOS nutzt unter anderem Tab-Navigation und den iOS-Player; macOS verwendet Desktop-Navigation, eigene Fenster und Mac-spezifische Bedienmuster.

## Funktionen

### Katalog & Navigation

- Anime-Katalog über AniWorld
- Serien-Katalog über Serienstream
- gemeinsame Bibliotheksansicht mit Anime, Serien und K-Drama-Bereich
- Suche
- Detailseiten für Serien und Anime
- Staffeln, Episoden und Filme
- Cover und Metadaten

### Wiedergabe

- Nativer Player über AVPlayer / AVKit
- HLS- und MP4-Wiedergabe
- automatische Hoster-Auswahl
- manueller Hoster- und Sprachwechsel
- GerDub, GerSub und EN
- Wiedergabegeschwindigkeit von 0,75× bis 2×
- Picture-in-Picture, soweit System und Stream es unterstützen
- automatischer Start der nächsten Folge

### Fortschritt & Bibliothek

- Merkliste
- Verlauf / zuletzt angesehen
- automatisches Speichern des Wiedergabefortschritts
- Weiterschauen / Resume an der letzten Position
- Folgen gelten ab etwa 90 % Wiedergabe als abgeschlossen
- Fortschritt wird nach Provider und normalisiertem Episodenpfad getrennt gespeichert
- Migration älterer lokaler Bibliotheksstände

Aktuelles Library-Schema: **v4**. Die maßgebliche Implementierung ist `LibraryStore.schemaVersion`; der kanonische Contract unter `config/contract.json` muss denselben Stand ausweisen.

### Synchronisation

Der gemeinsame Core enthält mit `LibrarySyncProvider` eine schmale Abstraktion für externe Synchronisationsziele. Ein Anbieter muss lediglich einen Stand laden und speichern können. Dadurch können beispielsweise Google Drive, Dropbox oder WebDAV angebunden werden, ohne `LibraryStore` erneut umzubauen.

Aktuell ist **kein Cloud-Anbieter fest in den Core verdrahtet**. Ohne eingerichteten Provider arbeitet Nori ausschließlich mit der lokalen `library.json`.

## Kanonischer Contract

Providerpfade, relevante Modellfelder, Bibliotheksschema und gemeinsame Regeln stehen zentral in:

```text
config/contract.json
```

Die bisherigen Dateien `native/Nori-iOS/contract.json` und `native/Nori-macOS/contract.json` bleiben nur als Symlinks auf diesen Contract bestehen. App-Versionen gehören ausdrücklich **nicht** in den Contract; sie stammen aus `MARKETING_VERSION` der jeweiligen Xcode-Projekte.

## iPhone / iPad

Voraussetzungen:

- macOS mit Xcode 16 oder neuer für den aktuellen iOS-Stand
- iOS/iPadOS 17 oder neuer

### Mit Xcode

1. `native/Nori-iOS/Nori.xcodeproj` öffnen.
2. SwiftSoup auflösen lassen.
3. Unter **Signing & Capabilities** ein Development Team auswählen.
4. iPhone oder iPad als Zielgerät auswählen.
5. Mit `⌘R` bauen und starten.

Alternativ kann `native/Nori-iOS/IPA-bauen.command` verwendet werden.

## macOS

Voraussetzungen:

- macOS 14 oder neuer
- Xcode 15 oder neuer

### Mit Xcode

1. `native/Nori-macOS/NoriMac.xcodeproj` öffnen.
2. SwiftSoup auflösen lassen.
3. Scheme `Nori` auswählen.
4. Ziel `My Mac` auswählen.
5. Mit `⌘R` starten.

Alternativ:

```text
native/Nori-macOS/Mac-App-bauen.command
```

## Tests

Der gemeinsame Kern wird über SwiftPM geprüft:

```bash
cd native
swift test
```

Die Tests liegen unter `native/Tests/NoriCoreTests/` und decken unter anderem AniWorld-/Serienstream-Parsing, Kalender, Providerpfade, Hoster-Auflösung, Bibliotheksmigration und Fortschrittsregeln ab.

## Windows

Der Windows-Stand ist derzeit **1.8.0** und wird als Legacy-Bereich behandelt:

- `desktop/` enthält die Electron-Hülle.
- `server/` enthält ausschließlich das bereits gebaute Nitro/Node-Runtime-Bundle.

`server/` ist **kein Quellcode** und sollte nicht manuell editiert werden. Für eine aktive Weiterentwicklung der Windows-Version sollte zuerst der ursprüngliche Web-Sourcecode wieder als eigene App-Struktur ins Repository aufgenommen werden; erst dann wäre ein Umzug nach `apps/windows/` sinnvoll.

## CI / Releases

Die GitHub-Actions-Läufe verwenden den self-hosted Mac-Runner. Änderungen am gemeinsamen `native/NoriCore/` müssen sowohl den iOS- als auch den macOS-Build auslösen, zusätzlich zu den Swift-Tests.

Release-Quellpakete müssen neben dem jeweiligen Plattformordner auch `native/NoriCore`, `native/Package.swift`, `native/Tests`, `config/contract.json`, `README.md` und `CHANGELOG.md` enthalten, damit die Symlinks im Xcode-Projekt auflösbar bleiben.

## Technische Hinweise

- AniWorld-Weiterleitungen (`/redirect/...`) und Serienstream-Weiterleitungen (`/r?...`) werden getrennt behandelt.
- Der Hoster-Resolver akzeptiert nur sichere HTTPS-Ziele und blockiert lokale/private Netzwerkadressen.
- Hoster können ihre Seiten oder Schutzmechanismen jederzeit ändern. Dadurch kann die Stream-Auflösung trotz unverändertem Nori-Code zeitweise ausfallen.
- `server/` ist generierte Build-Ausgabe und kein Ort für manuelle Änderungen.
