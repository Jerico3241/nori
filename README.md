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
| iOS / iPadOS | **1.25.0** | Native SwiftUI-App, aktueller Hauptstand |
| macOS | **1.20.0** | Native SwiftUI-App mit eigener Mac-Oberfläche |
| Windows | **1.8.0** | Electron / Node Portable Build, Legacy-Stand |
| LG webOS | **2.2.0** | TV-Oberfläche nach Design V4, eigene Fernbedienungsnavigation, 1080p und 4K, Google-Anmeldung per QR-Code, Abgleich über den TV-Spiegel; auf einem echten Gerät noch nicht erprobt |

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
├── shared/
│   └── nori-core/                # gemeinsamer Kern in TypeScript
├── apps/
│   └── webos/                    # TV-App für LG webOS
├── services/
│   └── nori-api/                 # Provider-Schicht als HTTP-Dienst
├── docs/
├── tools/
└── .github/workflows/
```

### Gemeinsamer Apple-Core

`Models.swift`, `LibraryStore.swift`, `HTML.swift`, `AniworldClient.swift`, `HosterResolver.swift` und `HLSPlaylist.swift` existieren nur noch einmal unter:

```text
native/NoriCore/Sources/NoriCore/
```

Die bestehenden Pfade in `native/Nori-iOS/Nori/` und `native/Nori-macOS/Nori/` sind Git-Symlinks auf diese gemeinsame Quelle. Dadurch bleiben die handgeschriebenen Xcode-Projekte stabil, während iOS und macOS garantiert dieselbe Kernimplementierung bauen.

Die Oberflächen bleiben bewusst plattformspezifisch. iOS nutzt unter anderem Tab-Navigation und den iOS-Player; macOS verwendet Desktop-Navigation, eigene Fenster und Mac-spezifische Bedienmuster.

### Gemeinsamer Kern für JavaScript-Clients

`shared/nori-core/` ist die TypeScript-Entsprechung von `native/NoriCore/`: dieselben Modelle, dieselben Regeln, dieselben Parser und derselbe Hoster-Resolver. Sie kann Swift nicht einbinden, richtet sich aber nach demselben `config/contract.json` und legt dieselbe `library.json`-Form ab. Die webOS-App und der Nori-Server benutzen sie beide; hosterspezifische Extraktion gibt es dadurch nur einmal.

Beide Testreihen prüfen absichtlich dieselben HTML-Ausschnitte — `native/Tests/NoriCoreTests/Fixtures.swift` und `shared/nori-core/test/fixtures.ts`.

## Funktionen

### Katalog & Navigation

- Anime-Katalog über AniWorld
- Serien-Katalog über Serienstream
- gemeinsame Bibliotheksansicht mit Anime, Serien und K-Drama-Bereich
- Suche
- Detailseiten für Serien und Anime
- Staffeln, Episoden und Filme
- Cover und Metadaten

### Oberfläche

Die native Apple-Oberfläche orientiert sich seit dem Redesign an
[Shirox](https://github.com/xibrox/Shirox) — Gestaltung, Bewegung und
Bedienung. Technik, Provider und Datenmodell sind unverändert Nori. Was
übernommen und was nachgebaut ist, steht in `docs/apple-redesign.md`, die
Lizenzhinweise in `THIRD-PARTY-NOTICES.md`.

- Startseite mit cinematischem Kopfbereich über rund drei Viertel des
  Bildschirms: Artwork bis unter die Statusleiste, Schriftzug, Eckdaten,
  Beschreibung und drei Knöpfe darauf. Kein Bereichsumschalter — Anime und
  Serien stehen dort gemeinsam.
- Reihen der Startseite aus echten Signalen: Weiterschauen aus dem eigenen
  Fortschritt, „Neu & beliebt" aus TMDB-Trend und -Beliebtheit, „Neue
  Episoden" aus dem Kalender der Provider, „Für dich" aus Verlauf und
  Merkliste. Was keine Daten hat, wird ausgeblendet statt leer gezeigt.
- Kachelreihen mit gleichbleibender Höhe und Druckrückmeldung
- Zoom-Übergang von der Kachel in die Detailseite
- Detailseite mit Abspielknopf, Kopfbild, Staffeln und Folgen
- Liquid Glass auf iOS/macOS 26 und neuer, mit klassischem Rückfall darunter
  und einem Schalter in den Einstellungen
- ein Bewegungssystem statt verstreuter Einzelwerte; „Bewegung reduzieren"
  schaltet Parallaxe, Dehnung und räumliche Übergänge ab, ohne Funktion zu
  ändern
- Zeigerrückmeldung und Kontextmenüs auf iPad und Mac

### Wiedergabe

- Nativer Player über AVPlayer / AVKit, mit eigener Bedienung statt
  `AVPlayerViewController` — nur so lassen sich Hoster, Sprache und Untertitel
  in die Leiste selbst legen statt daneben
- HLS- und MP4-Wiedergabe
- automatische Hoster-Auswahl
- **eine** Hoster-Auswahl, in den Player-Controls; Wechsel behält Position und
  Wiedergabezustand, die Bedienung bleibt dabei stehen
- manueller Hoster- und Sprachwechsel
- GerDub, GerSub und EN
- Qualitätsauswahl nur, wenn der Stream tatsächlich mehrere HLS-Stufen
  anbietet — gelesen aus der Master-Playlist, nicht geraten
- Untertitelspuren des Streams, soweit vorhanden
- Wiedergabegeschwindigkeit von 0,5× bis 2×
- Doppeltipp links und rechts springt zehn Sekunden, mit zusammengefasster
  Anzeige bei mehreren Tippern
- Fortschrittsregler mit Puffer- und Restzeitanzeige, folgt beim Ziehen dem
  Finger
- Bild einpassen oder formatfüllend
- AirPlay über `AVRoutePickerView`, Picture-in-Picture über
  `AVPictureInPictureController`
- automatischer Start der nächsten Folge, mit Countdown-Ring und Abbruch
- Bedienung blendet nach vier Sekunden aus — nicht im Stehen, nicht beim
  Ziehen, nicht bei offenem Menü, nicht mit VoiceOver

### Fortschritt & Bibliothek

- Merkliste
- Verlauf / zuletzt angesehen
- automatisches Speichern des Wiedergabefortschritts
- Weiterschauen / Resume an der letzten Position
- Folgen gelten ab etwa 90 % Wiedergabe als abgeschlossen
- Fortschritt wird nach Provider und normalisiertem Episodenpfad getrennt gespeichert
- Migration älterer lokaler Bibliotheksstände

Aktuelles Library-Schema: **v6**. Die maßgebliche Implementierung ist `LibraryStore.schemaVersion`; der kanonische Contract unter `config/contract.json` muss denselben Stand ausweisen.

### Synchronisation

Abgeglichen wird über **Google Drive**. Apple nutzt den versteckten `appDataFolder`; mit „Mit Fernseher teilen" legt ein iPhone, iPad oder Mac zusätzlich einen sichtbaren Spiegel im Ordner „Nori" an, und nur den liest der Fernseher. Jedes Gerät schreibt nur seine eigene Datei und liest die aller anderen; der Ablauf ist immer Pull → Merge → Push. Kein iCloud, kein Dropbox, kein WebDAV, kein eigener Server, kein Proxy.

**Für den Nutzer ist das ein Knopf:**

```text
Einstellungen → Synchronisation → [ Mit Google anmelden ]
```

Danach zeigt die Seite den Zustand, „Jetzt synchronisieren" und „Dieses Gerät trennen". Client-ID, Client-Secret, Redirect-URI, Access- und Refresh-Token sind **keine** Benutzereinstellungen und stehen nicht in der Oberfläche — wer Nori benutzt, muss über OAuth nichts wissen.

| Plattform | Anmeldung |
| --- | --- |
| iOS / iPadOS | Authorization Code + PKCE über `ASWebAuthenticationSession` |
| macOS | Authorization Code + PKCE, Systembrowser + Loopback auf `127.0.0.1` |
| webOS | Device Authorization Grant (RFC 8628) mit QR-Code und großem Gerätecode |
| Android | vorbereitet, noch nicht umgesetzt — `docs/android.md` |

Angefordert wird auf Apple `https://www.googleapis.com/auth/drive.appdata`, zusätzlich `https://www.googleapis.com/auth/drive.file` nur nach „Mit Fernseher teilen". Der Fernseher fragt ausschließlich nach `drive.file`, weil Googles Gerätefluss `drive.appdata` ablehnt. Kein `email`, kein `profile`, kein `openid` — Nori sieht weder Name noch Adresse des Google-Kontos.

**Für den, der Nori baut**, sind die OAuth-Werte lokale Build-Einstellungen, je Plattform getrennt und nie eingecheckt: `GOOGLE_CLIENT_ID` in `native/Nori-iOS/Config/Google.local.xcconfig`, `GOOGLE_CLIENT_ID` und `GOOGLE_CLIENT_SECRET` (Desktop-Client) in `native/Nori-macOS/Config/Google.local.xcconfig`, `VITE_NORI_GOOGLE_TV_CLIENT_ID` und `VITE_NORI_GOOGLE_TV_CLIENT_SECRET` in `apps/webos/.env.local`. Geschrieben und geprüft werden sie mit `tools/configure-google-oauth.py` aus den OAuth-JSON-Dateien unter `~/.config/nori/secrets/`. Die Einrichtung steht in **[docs/google-drive-sync.md](docs/google-drive-sync.md)**, die Begründungen in **[docs/synchronisation.md](docs/synchronisation.md)**.

`LibrarySyncProvider` — eine Datei ablegen, eine Datei holen — bleibt als Abstraktion im Core bestehen. Der Mehrgeräte-Abgleich benutzt daneben `LibrarySnapshotStore`; umgesetzt ist davon genau einer, `GoogleDriveSnapshotStore`.

## Kanonischer Contract

Providerpfade, relevante Modellfelder, Bibliotheksschema und gemeinsame Regeln stehen zentral in:

```text
config/contract.json
```

Die bisherigen Dateien `native/Nori-iOS/contract.json` und `native/Nori-macOS/contract.json` bleiben nur als Symlinks auf diesen Contract bestehen. App-Versionen gehören ausdrücklich **nicht** in den Contract; sie stammen aus `MARKETING_VERSION` der jeweiligen Xcode-Projekte.

## iPhone / iPad

Voraussetzungen:

- macOS mit **Xcode 26 oder neuer**: das Deployment-Target bleibt iOS 17,
  aber Liquid Glass steht hinter `#available` und braucht trotzdem das
  passende SDK
- iOS/iPadOS 17 oder neuer zum Ausführen; Liquid Glass ab iOS 26, darunter
  der klassische Rückfall

### Mit Xcode

1. `native/Nori-iOS/Nori.xcodeproj` öffnen.
2. SwiftSoup auflösen lassen.
3. Unter **Signing & Capabilities** ein Development Team auswählen.
4. iPhone oder iPad als Zielgerät auswählen.
5. Mit `⌘R` bauen und starten.

Alternativ kann `native/Nori-iOS/IPA-bauen.command` verwendet werden.

## macOS

Voraussetzungen:

- macOS 14 oder neuer zum Ausführen; Liquid Glass ab macOS 26, darunter der
  klassische Rückfall
- **Xcode 26 oder neuer** zum Bauen — aus demselben Grund wie bei iOS: das
  Deployment-Target bleibt macOS 14, das SDK muss die Glas-API trotzdem
  kennen

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

Die Tests liegen unter `native/Tests/NoriCoreTests/` und decken unter anderem AniWorld-/Serienstream-Parsing, Kalender, Providerpfade, Hoster-Auflösung, HLS-Qualitätsstufen, Bibliotheksmigration und Fortschrittsregeln ab.

Der TypeScript-Kern wird gegen dieselben HTML-Ausschnitte geprüft:

```bash
npm --prefix shared/nori-core test
python3 tools/check-webos-package.py
```

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
npm run webos:package     # ergibt tv.nori.app_1.2.0_all.ipk
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
NORI_TMDB_KEY=<optional> npm run dev   # hört auf 0.0.0.0:8730
```

Die Adresse wird in der App unter *Einstellungen → Verbindung* eingetragen.
Alternativ steht dort „Direkt vom Fernseher" — dann benutzt der Client denselben
Kern selbst, was ohne Einrichtung auskommt, aber vom Verhalten des Geräts und
des Hosters abhängt.

### TMDB

Poster, Hintergrundbilder, Schriftzüge, Beschreibungen, Bewertungen,
Folgentitel und Folgenbilder kommen von TMDB — und mit ihnen die Signale, aus
denen „Neu & beliebt" und „Für dich" entstehen. Die Zuordnung liegt im
gemeinsamen Kern (`shared/nori-core/src/tmdb/`) und ist dieselbe wie auf
iPhone und Mac.

**Einzurichten ist nichts.** Ein Schlüssel ist mitgeliefert — derselbe, den
iPhone und Mac benutzen (`BUILT_IN_TMDB_KEY` im Kern, `TMDBKeyStore.builtIn`
auf der Apple-Seite). Auf einem Fernseher zählt das mehr als sonst: dort gibt
es keine Tastatur.

Ein **eigener** Schlüssel hat Vorrang und trennt die Ratenbegrenzung von der
geteilten Kennung — am Server über `NORI_TMDB_KEY`, am Gerät in den
Einstellungen. Über den Server gilt der Zwischenspeicher zusätzlich für alle
Fernseher gemeinsam. „Aus" ist die einzige Art, TMDB nicht zu benutzen; dann
zeigt Nori die Cover und Texte der Quellen.

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

### Prüfen

```bash
npm --prefix shared/nori-core test        # Kern, 122 Tests
python3 tools/check-webos-package.py      # Quelltext, Paket, Versionen
cd apps/webos && npm run build
npm run mock &                            # Nori-Server und TMDB mit festen Daten
npm i -D playwright && npx playwright install chromium
npm run test:tv                           # 130 Prüfungen mit echten LG-Tastencodes
```

Der Fernbedienungslauf legt dabei 21 Bildschirmfotos in
`apps/webos/test-shots/` ab.

### Architektur

```text
webOS-Client  →  Nori-Server  →  AniWorld / Serienstream
                      ↓
               HosterResolver
                      ↓
       Weiterreichung mit Referer  →  Hoster
```

Beide Seiten benutzen `shared/nori-core`. Der Client selbst kennt keinen
Hoster — er bekommt ein `PlaySource` und eine Adresse, die er laden kann.

## Windows

Der Windows-Stand ist derzeit **1.8.0** und wird als Legacy-Bereich behandelt:

- `desktop/` enthält die Electron-Hülle.
- `server/` enthält ausschließlich das bereits gebaute Nitro/Node-Runtime-Bundle.

`server/` ist **kein Quellcode** und sollte nicht manuell editiert werden. Für eine aktive Weiterentwicklung der Windows-Version sollte zuerst der ursprüngliche Web-Sourcecode wieder als eigene App-Struktur ins Repository aufgenommen werden; erst dann wäre ein Umzug nach `apps/windows/` sinnvoll.

## CI / Releases

Die GitHub-Actions-Läufe verwenden den self-hosted Mac-Runner. Änderungen am gemeinsamen `native/NoriCore/` müssen sowohl den iOS- als auch den macOS-Build auslösen, zusätzlich zu den Swift-Tests.

Der Lauf **Build webOS** liegt auf demselben Runner, braucht dort aber kein Xcode, nur Node. Er baut Kern, Server und App, schnürt das `.ipk`, prüft es und legt es als Artefakt ab.

Release-Quellpakete müssen neben dem jeweiligen Plattformordner auch `native/NoriCore`, `native/Package.swift`, `native/Tests`, `config/contract.json`, `README.md` und `CHANGELOG.md` enthalten, damit die Symlinks im Xcode-Projekt auflösbar bleiben.

## Technische Hinweise

- AniWorld-Weiterleitungen (`/redirect/...`) und Serienstream-Weiterleitungen (`/r?...`) werden getrennt behandelt.
- Der Hoster-Resolver akzeptiert nur sichere HTTPS-Ziele und blockiert lokale/private Netzwerkadressen.
- Hoster können ihre Seiten oder Schutzmechanismen jederzeit ändern. Dadurch kann die Stream-Auflösung trotz unverändertem Nori-Code zeitweise ausfallen.
- `server/` ist generierte Build-Ausgabe und kein Ort für manuelle Änderungen.
