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
| iOS / iPadOS | **1.14.5** | Native SwiftUI-App, aktueller Hauptstand |
| macOS | **1.14.2** | Native SwiftUI-App mit eigener Mac-Oberfläche; Player und Startseite liegen hinter dem iOS-Stand |
| Windows | **1.8.0** | Electron / Node Portable Build |
| LG webOS | **1.0.0** | TV-App mit Fernbedienungsnavigation; auf einem echten Gerät noch nicht erprobt |

Die nativen Apple-Versionen liegen unter `native/`, die TV-Version unter
`apps/webos/`.

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

Aktuelles Library-Schema: **v4**.

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
| `apps/webos/` | TV-App für LG webOS (React, TypeScript, Enact Spotlight) |
| `shared/nori-core/` | Gemeinsamer Kern in TypeScript für alle JavaScript-Clients |
| `services/nori-api/` | Provider-Schicht als HTTP-Dienst für die TV-App |

Gemeinsames Datenmodell / Contract:

- `native/Nori-iOS/contract.json`
- `native/Nori-macOS/contract.json`

`shared/nori-core` ist die TypeScript-Seite desselben Vertrags: dieselben
Feldnamen, dieselben Regeln, dasselbe Ablageformat. Eine `library.json` aus der
iOS- oder macOS-App liest sich dort ohne Umschreiben.

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

## Nori for LG webOS

Eine eigenständige TV-App, vollständig mit der Fernbedienung bedienbar und auf
1920 × 1080 ausgelegt. Ausführlich: [docs/webos.md](docs/webos.md).

### Voraussetzungen

- Node 20 oder neuer
- Ein LG-Fernseher mit webOS 6 oder neuer im Entwicklermodus
- Für Installation und Protokolle das LG-SDK: `npm i -g @webosose/ares-cli`

Zum **Bauen** wird das SDK nicht gebraucht — `npm run webos:package` schnürt das
`.ipk` selbst.

### Build und Paket

```bash
cd apps/webos
npm install
npm run build
npm run webos:package     # ergibt tv.nori.app_1.0.0_all.ipk
```

Vom Repository-Stamm aus: `npm run webos:build` und `npm run webos:package`.

### Nori-Server

Der Fernseher holt Katalog und Stream über einen kleinen Dienst, statt die
Quellen selbst abzurufen. Der Grund ist nicht Bequemlichkeit: viele Hoster
liefern nur mit einer `Referer`-Kopfzeile aus, und die darf ein Browser nicht
setzen.

```bash
cd services/nori-api
npm install
npm run dev               # hört auf 0.0.0.0:8730
```

Die Adresse wird in der App unter *Einstellungen → Verbindung* eingetragen.
Alternativ steht dort „Direkt vom Fernseher" — dann benutzt der Client denselben
Kern selbst, was ohne Einrichtung auskommt, aber vom Verhalten des Geräts und
des Hosters abhängt.

### Installation

1. LG-Konto anlegen und am Fernseher anmelden.
2. Im Content Store die App **Developer Mode** installieren, anmelden,
   *Dev Mode Status* einschalten. Der Fernseher zeigt danach Passphrase und
   IP-Adresse.
3. Gerät eintragen:

   ```bash
   ares-setup-device --add tv --info "{'host':'192.168.1.50','port':'9922','username':'prisoner'}"
   ares-novacom --device tv --getkey
   ```

4. Installieren und starten:

   ```bash
   npm run webos:install tv
   npm run webos:launch tv
   ```

5. Verlängern: der Entwicklermodus läuft nach etwa 50 Stunden ab. **Extend Dev
   Mode Status** in derselben App setzt die Frist zurück.

### Debugging

```bash
npm run webos:inspect tv                      # Web-Inspector
node apps/webos/tools/webos-cli.mjs log tv    # Protokoll des Geräts
```

Alles von Nori trägt das Präfix `[Nori:webOS]`.

### Unterstützte Stände

Gebaut auf Chrome 79 — die Engine von webOS 6. Damit läuft dasselbe Paket auf
**webOS 6 bis 26**. Auf einem echten Gerät ist der Stand noch nicht erprobt.

### Architektur

```
webOS-Client  →  Nori-Server  →  AniWorld / Serienstream
                      ↓
               HosterResolver
                      ↓
       Weiterreichung mit Referer  →  Hoster
```

Beide Seiten benutzen `shared/nori-core`; hosterspezifische Logik gibt es
deshalb nur einmal. Der Client selbst kennt keinen Hoster — er bekommt ein
`PlaySource` und eine Adresse, die er laden kann.

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

