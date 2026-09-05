# Nori

Nori ist eine native Anime- und Serien-App mit Katalog, Suche, Merkliste, Verlauf, Wiedergabefortschritt, Resume, Kalender und integriertem Player.

Unterstützte Quellen:

- **AniWorld** für Anime
- **Serienstream** für Serien

Die App nutzt verfügbare Hoster automatisch nach Priorität und erlaubt während der Wiedergabe den Wechsel von Hoster und Sprache.

> **Privates Projekt.** Nori ist nicht mit AniWorld oder Serienstream verbunden.

Änderungen je Version: [CHANGELOG.md](CHANGELOG.md)

## Aktueller Stand

| Plattform | Version | Status |
| --- | --- | --- |
| iOS / iPadOS | **1.9.3** | Native SwiftUI-App, aktueller Hauptstand |
| macOS | **1.10.1** | Native SwiftUI-App mit eigener Mac-Oberfläche, aktuell der weiteste Stand |
| Windows | **1.8.0** | Electron / Node Portable Build |

Die nativen Apple-Versionen liegen unter `native/`.

## Funktionen

### Katalog & Navigation

- Anime-Katalog über AniWorld
- Serien-Katalog über Serienstream
- Suche
- Detailseiten für Serien und Anime
- Staffeln, Episoden und Filme
- Umschalter zwischen Anime und Serien
- Cover und Metadaten

### Wiedergabe

- Nativer Player über AVPlayer / AVKit
- HLS- und MP4-Wiedergabe
- Automatische Hoster-Auswahl
- Manueller Hoster-Wechsel während der Wiedergabe
- Sprachwechsel während der Wiedergabe
- GerDub, GerSub und EN
- Wiedergabegeschwindigkeit von 0,75× bis 2×
- Picture-in-Picture, soweit vom System und Stream unterstützt
- Automatischer Start der nächsten Folge

### Fortschritt & Bibliothek

- Merkliste
- Verlauf / zuletzt angesehen
- Automatisches Speichern des Wiedergabefortschritts
- **Weiterschauen / Resume** an der letzten Position
- Folgen werden ab ca. 90 % Wiedergabe als abgeschlossen behandelt
- Fortschritt wird nach Quelle und Episode getrennt gespeichert
- Migration älterer lokaler Bibliotheksdaten auf das aktuelle Datenmodell

Aktuelles Library-Schema: **v3**.

### Kalender

- Anime-Kalender
- Serien-Kalender, soweit von der jeweiligen Quelle unterstützt
- Gruppierung nach Tagen
- Anzeige von Staffel, Folge und verfügbaren Sprachen
- Pull-to-Refresh / manuelles Aktualisieren

### Synchronisation

Nori enthält inzwischen eine optionale **iCloud-Key-Value-Synchronisation** für:

- Merkliste
- Verlauf
- Wiedergabefortschritt
- ausgewählte Quelle
- Sprache
- bevorzugten Hoster
- Resume- und Autoplay-Einstellungen
- Wiedergabegeschwindigkeit

Damit ist die gemeinsame Datenbasis für iPhone/iPad und Mac im Code vorhanden.

**Wichtig:** Für echte iCloud-Synchronisation müssen in Xcode für die verwendeten Targets noch die passenden iCloud-/Key-Value-Store-Capabilities und Signing-Einstellungen aktiviert werden. Ohne diese Entitlements bleibt die lokale Speicherung weiterhin funktionsfähig, die Geräte-Synchronisation ist aber nicht garantiert.

## Projektstruktur

| Ordner | Inhalt |
| --- | --- |
| `native/Nori-iOS/` | Native iOS/iPadOS-App mit SwiftUI und AVPlayer |
| `native/Nori-macOS/` | Native macOS-App mit SwiftUI und AVKit |
| `desktop/` | Electron-Hülle für Windows |
| `server/` | Gebauter Nitro/Node-Webserver für die Windows-Version |

Gemeinsames Datenmodell / Contract:

- `native/Nori-iOS/contract.json`
- `native/Nori-macOS/contract.json`

## iPhone / iPad

Voraussetzungen:

- macOS mit Xcode
- iOS/iPadOS 17 oder neuer

### Mit Xcode

1. `native/Nori-iOS/Nori.xcodeproj` öffnen.
2. SwiftSoup auflösen lassen.
3. Unter **Signing & Capabilities** eine eigene Apple-ID / ein Development Team auswählen.
4. iPhone oder iPad als Zielgerät auswählen.
5. Mit `⌘R` bauen und starten.

Alternativ kann `native/Nori-iOS/IPA-bauen.command` verwendet werden.

Für iCloud-Sync müssen zusätzlich die entsprechenden iCloud-/Key-Value-Store-Capabilities für den iOS-Target eingerichtet werden.

## macOS

Voraussetzungen:

- macOS 14 oder neuer
- Xcode 15.4 oder neuer

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

Das lokale Build-Skript erzeugt die App normalerweise unter:

```text
native/Nori-macOS/DerivedData/Build/Products/Debug/Nori.app
```

Für iCloud-Sync müssen auch beim macOS-Target die passenden Capabilities und Signing-Einstellungen aktiviert werden.

## Automatisches macOS-Quellpaket

Unter `.github/workflows/package-macos-source.yml` befindet sich ein GitHub-Actions-Workflow.

Bei Änderungen an der macOS-App bzw. am Workflow wird automatisch ein Artefakt namens **`Nori-macOS`** erzeugt. Dieses enthält ein aktuelles `Nori-macOS.zip` mit dem macOS-Xcode-Projekt und dem zugehörigen Quellcode.

Das Artefakt kann über den jeweiligen erfolgreichen GitHub-Actions-Lauf heruntergeladen werden.

## Windows

Der Windows-Stand ist aktuell **1.8.0**.

Ein fertiges Portable-Paket liegt unter den GitHub-Releases als `Nori-Portable-x64.zip`, sofern der entsprechende Release vorhanden ist.

Nach dem Entpacken kann entweder die portable Anwendung direkt gestartet oder das enthaltene Installationsskript verwendet werden.

Lokale Daten werden bei der Windows-Version separat gespeichert und sind derzeit nicht Teil der nativen Apple-iCloud-Synchronisation.

## Lokaler Web-Server

Der Ordner `server/` enthält den gebauten Node-Server. Start:

```bash
node server/server/index.mjs
```

Die Electron-Hülle erwartet denselben Server packaged unter `resources/nori-server/` beziehungsweise im Entwicklungsstand unter `.output/server/`.

## Technische Hinweise

- iOS und macOS teilen Modelle, Netzwerklogik und Bibliotheksverwaltung (`Models`, `LibraryStore`, `AniworldClient`, `HosterResolver`, `HTML`).
- Die **Oberfläche ist getrennt**: macOS nutzt eine Seitenleiste (`NavigationSplitView`) statt Tab-Bar, ein eigenes Wiedergabefenster statt Sheet, das Systemeinstellungsfenster (⌘,) statt eines Einstellungs-Tabs sowie eine an das Systemerscheinungsbild angepasste Farbpalette.
- Plattformspezifisch bleiben außerdem Player-Integration, App-Lifecycle, Xcode-Projekte und Info.plist-Konfiguration.
- AniWorld-Weiterleitungen (`/redirect/...`) und Serienstream-Weiterleitungen (`/r?...`) werden getrennt behandelt.
- Der Hoster-Resolver akzeptiert nur sichere HTTPS-Ziele und blockiert lokale/private Netzwerkadressen.
- Hoster können ihre Seiten oder Schutzmechanismen jederzeit ändern. Dadurch kann die Stream-Auflösung trotz unverändertem Nori-Code zeitweise ausfallen.

## Noch offen

Für einen vollständig verifizierten Release-Stand stehen insbesondere noch an:

- iCloud-Capabilities und Signing für iOS und macOS final konfigurieren
- Sync auf echten Geräten testen
- iOS- und macOS-Builds in Xcode vollständig verifizieren
- Hoster unter realen Bedingungen testen
- anschließend einen sauber versionierten nächsten Release vorbereiten
