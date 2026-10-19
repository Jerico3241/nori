# Nori

Nori ist eine native Anime- und Serien-App mit Katalog, Suche, Merkliste, Verlauf, Wiedergabefortschritt, Resume, Kalender und integriertem Player.

Unterstützte Quellen:

- **AniWorld** für Anime
- **Serienstream** für Serien

Die App nutzt verfügbare Hoster nach Priorität und erlaubt während der Wiedergabe den Wechsel von Hoster und Sprache.

> **Privates Projekt.** Nori ist nicht mit AniWorld oder Serienstream verbunden.

Änderungen je Version: [CHANGELOG.md](CHANGELOG.md)

## Aktueller Stand

Nori **2.7.0** — Nori gibt es nur noch für iPhone und iPad. Die Apps für
macOS, Windows und LG webOS sind mit dieser Fassung eingestellt und aus dem
Repository entfernt; ihr letzter Stand bleibt in der Git-Geschichte erhalten.
Ein Release heißt `Nori v2.7.0` (Tag `v2.7.0`). Wie er entsteht:
[docs/releases.md](docs/releases.md).

| Plattform | Version | Paket im Release | Status |
| --- | --- | --- | --- |
| iOS / iPadOS | **2.7.0** (Build 42) | `Nori-iOS-v2.7.0.ipa`, unsigniert | Native SwiftUI-App, einzige gepflegte Plattform |
| macOS, Windows, LG webOS | — | — | eingestellt |
| Android / Google TV | — | — | Keine App in diesem Repository |

Die Nummer setzt und prüft `tools/nori-version.py`:

```bash
python3 tools/nori-version.py show     # alle Stellen mit ihrer Nummer
python3 tools/nori-version.py bump minor
python3 tools/nori-version.py check
```

## Projektstruktur

```text
nori/
├── native/
│   ├── NoriCore/
│   │   └── Sources/NoriCore/     # gemeinsame Swift-Kernlogik
│   ├── Nori-iOS/                 # iOS/iPadOS SwiftUI + AVPlayer
│   ├── Package.swift             # NoriCore für Tests/Android
│   └── Tests/NoriCoreTests/      # Tests des Kerns
├── config/
│   └── contract.json             # kanonischer Daten-/Provider-Contract
├── docs/
├── tools/
└── .github/workflows/
```

### Gemeinsamer Apple-Core

`Models.swift`, `LibraryStore.swift`, `HTML.swift`, `AniworldClient.swift`, `HosterResolver.swift` und `HLSPlaylist.swift` existieren nur einmal unter:

```text
native/NoriCore/Sources/NoriCore/
```

Die bestehenden Pfade in `native/Nori-iOS/Nori/` sind Git-Symlinks auf diese Quelle. Dadurch bleibt das handgeschriebene Xcode-Projekt stabil, und dieselben Quellen laufen über SwiftPM durch die Tests.

## Funktionen

### Katalog & Navigation

- Anime-Katalog über AniWorld
- Serien-Katalog über Serienstream
- gemeinsame Bibliotheksansicht mit Anime, Serien und K-Drama-Bereich
- Suche in Stufen und mit Tippfehlertoleranz, überall dieselbe: „pokemon"
  trifft „Pokémon", „shingeki no kyojin" den Eintrag, den die Quelle „Attack on
  Titan" nennt, und „Damonenjager" den „Dämonenjäger"
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
- Liquid Glass auf iOS 26 und neuer, mit klassischem Rückfall darunter
  und einem Schalter in den Einstellungen
- ein Bewegungssystem statt verstreuter Einzelwerte; „Bewegung reduzieren"
  schaltet Parallaxe, Dehnung und räumliche Übergänge ab, ohne Funktion zu
  ändern
- Zeigerrückmeldung und Kontextmenüs auf dem iPad

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
- automatischer Start der nächsten Folge nach zehn Sekunden, mit Countdown und
  Abbruch; die Länge steht im Kern und gilt auf allen Plattformen
- **Wiederherstellung nach einem abgebrochenen Stream**: die nächste Quelle
  wird selbst versucht, höchstens dreimal je Folge, eine gescheiterte kein
  zweites Mal — danach eine Meldung statt einer Schleife
- Bedienung blendet nach vier Sekunden aus — nicht im Stehen, nicht beim
  Ziehen, nicht bei offenem Menü, nicht mit VoiceOver

### Fortschritt & Bibliothek

- Merkliste
- Verlauf / zuletzt angesehen
- automatisches Speichern des Wiedergabefortschritts
- Weiterschauen / Resume an der letzten Position
- Folgen gelten ab etwa 90 % Wiedergabe als abgeschlossen
- **gesehen und ungesehen von Hand** — je Folge, je Staffel, je Serie, auf
  iPhone und iPad nach denselben Regeln
- **„Aus Weiterschauen entfernen"** und **Fortschritt zurücksetzen**; beides
  löscht nichts, es setzt angefangene Folgen auf null und lässt abgeschlossene
  abgeschlossen
- Fortschritt wird nach Provider und normalisiertem Episodenpfad getrennt gespeichert
- Migration älterer lokaler Bibliotheksstände

Aktuelles Library-Schema: **v6**. Die maßgebliche Implementierung ist `LibraryStore.schemaVersion`; der kanonische Contract unter `config/contract.json` muss denselben Stand ausweisen.

### Synchronisation

Abgeglichen wird über **Google Drive**. Nori nutzt den versteckten `appDataFolder`. Der Schalter „Mit Fernseher teilen" legt zusätzlich einen sichtbaren Spiegel im Ordner „Nori" an; seit die LG-App eingestellt ist, liest ihn kein Gerät mehr. Jedes Gerät schreibt nur seine eigene Datei und liest die aller anderen; der Ablauf ist immer Pull → Merge → Push. Kein iCloud, kein Dropbox, kein WebDAV, kein eigener Server, kein Proxy.

**Für den Nutzer ist das ein Knopf:**

```text
Einstellungen → Synchronisation → [ Mit Google anmelden ]
```

Danach zeigt die Seite den Zustand, „Jetzt synchronisieren" und „Dieses Gerät trennen". Client-ID, Client-Secret, Redirect-URI, Access- und Refresh-Token sind **keine** Benutzereinstellungen und stehen nicht in der Oberfläche — wer Nori benutzt, muss über OAuth nichts wissen.

| Plattform | Anmeldung |
| --- | --- |
| iOS / iPadOS | Authorization Code + PKCE über `ASWebAuthenticationSession` |
| Android | vorbereitet, noch nicht umgesetzt — `docs/android.md` |

Angefordert wird `https://www.googleapis.com/auth/drive.appdata`, zusätzlich `https://www.googleapis.com/auth/drive.file` nur nach „Mit Fernseher teilen". Kein `email`, kein `profile`, kein `openid` — Nori sieht weder Name noch Adresse des Google-Kontos.

**Für den, der Nori baut**, ist die Client-ID eine lokale Build-Einstellung und nie eingecheckt: `GOOGLE_CLIENT_ID` in `native/Nori-iOS/Config/Google.local.xcconfig`, bei GitHub das Secret `NORI_GOOGLE_IOS_CLIENT_ID`. Geschrieben und geprüft wird sie mit `tools/configure-google-oauth.py`. Die Einrichtung steht in **[docs/google-drive-sync.md](docs/google-drive-sync.md)**, die Begründungen in **[docs/synchronisation.md](docs/synchronisation.md)**.

`LibrarySyncProvider` — eine Datei ablegen, eine Datei holen — bleibt als Abstraktion im Core bestehen. Der Mehrgeräte-Abgleich benutzt daneben `LibrarySnapshotStore`; umgesetzt ist davon genau einer, `GoogleDriveSnapshotStore`.

## Kanonischer Contract

Providerpfade, relevante Modellfelder, Bibliotheksschema und gemeinsame Regeln stehen zentral in:

```text
config/contract.json
```

Die Datei `native/Nori-iOS/contract.json` ist nur ein Symlink auf diesen Contract. App-Versionen gehören ausdrücklich **nicht** in den Contract; sie stammen aus `MARKETING_VERSION` des Xcode-Projekts.

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

## Tests

Der Kern wird über SwiftPM geprüft:

```bash
cd native
swift test
```

Die Tests liegen unter `native/Tests/NoriCoreTests/` und decken unter anderem AniWorld-/Serienstream-Parsing, Kalender, Providerpfade, Hoster-Auflösung, HLS-Qualitätsstufen, Bibliotheksmigration und Fortschrittsregeln ab.

## CI / Releases

Die GitHub-Actions-Läufe verwenden GitHub-hosted Runner (`macos-26` für die
iOS-App und die Swift-Tests, `ubuntu-latest` für die Prüfskripte). Die
teuren Läufe auf macOS starten nur, wenn sich `native/**` ändert.

Ein Release entsteht von Hand: **GitHub → Actions → Nori Release → Run workflow → Version**. Der Lauf prüft Version und Changelog, testet den Kern, baut die iOS-App, prüft das Paket, legt den Release `Nori v<VERSION>` mit dem Tag `v<VERSION>` und `checksums-sha256.txt` an, prüft ihn nach und löscht erst dann alte Läufe der Nori-Workflows. Jede Version bekommt genau einen Release; Tags werden nie verschoben, Releases nie gelöscht. Einzelheiten: [docs/releases.md](docs/releases.md).

## Technische Hinweise

- AniWorld-Weiterleitungen (`/redirect/...`) und Serienstream-Weiterleitungen (`/r?...`) werden getrennt behandelt.
- Der Hoster-Resolver akzeptiert nur sichere HTTPS-Ziele und blockiert lokale/private Netzwerkadressen.
- Hoster können ihre Seiten oder Schutzmechanismen jederzeit ändern. Dadurch kann die Stream-Auflösung trotz unverändertem Nori-Code zeitweise ausfallen.
