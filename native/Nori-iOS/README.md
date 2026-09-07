# Nori für iPhone (SwiftUI) — 1.16.1

Native iPhone/iPad App mit SwiftUI und AVPlayer. Der aktuelle iOS-Client arbeitet lokal; Merkliste und Fortschritt benötigen keinen Account.

## Neu in 1.16

- Bereiche statt Quellen: Alle, Anime, Serien, **K-Drama** — die koreanischen
  Serien führt Serienstream selbst unter diesem Genre.
- Beide Kataloge werden zusammengeführt; fällt eine Quelle aus, bleibt die
  andere sichtbar.
- Kopfbereich als reine Bildfläche mit freigestelltem TMDB-Schriftzug, beim
  Antippen führt er zur Serie.
- „Schau weiter" im Querformat mit Backdrop, Logo und Restzeit — Antippen
  startet die zuletzt angefangene Folge, sonst die nächste unfertige.

## Nori 1.9

- echtes Autoplay der nächsten Folge mit 8-Sekunden-Countdown und Abbrechen/sofort Abspielen
- Hosterwechsel direkt im Player
- Sprachwechsel direkt im Player
- Wiedergabegeschwindigkeit 0,75× / 1× / 1,25× / 1,5× / 2×
- Retry und alternativer Hoster bei Wiedergabefehlern
- Library-Schema v2 mit automatischer Migration bestehender 1.x-Daten
- nur noch ein Progress-Datensatz pro Provider + Episode; Sprache bleibt Metadatum
- Provider wird bei neuen Progress-Einträgen explizit gespeichert
- bis zu 100 zuletzt geöffnete Titel
- härtere Prüfung externer Hoster-/Stream-URLs gegen lokale/private Zieladressen
- Versionsanzeige kommt aus `CFBundleShortVersionString` statt aus einem hart codierten UI-String
- `contract.json` auf Contract v2 / App 1.9.0 aktualisiert

## IPA (unsigniert)

### Ohne eigenen Mac: aus der CI herunterladen

Der Workflow **Package iOS IPA** legt bei jedem Push auf `main`, der den
iOS-Ordner berührt, eine unsignierte IPA als Artefakt ab. Unter *Actions →
Package iOS IPA → letzter Lauf → Artifacts* liegt sie als
`Nori-iOS-<Version>-unsigned`. Haltbarkeit 30 Tage. Von Hand anstoßen geht über
*Run workflow*.

### Auf einem Mac mit Xcode

1. Diesen Ordner auf einen Mac legen.
2. `IPA-bauen.command` ausführen.
3. Xcode lädt beim ersten Build SwiftSoup.

Beide Wege bauen dasselbe: `-sdk iphoneos`, ohne Signatur, ohne
`embedded.mobileprovision`.

### Danach

Die IPA ist **unsigniert** und lässt sich so nicht installieren. Signieren auf
dem Gerät (Feather, ESign, SideStore …) oder mit einem eigenen Zertifikat.
Wer ein Apple-Entwicklerkonto hat, nimmt besser den Weg über Xcode weiter
unten — dann entfällt das nachträgliche Signieren.

## Direkt aus Xcode

1. `Nori.xcodeproj` öffnen.
2. Unter Signing ein Development Team auswählen.
3. iPhone/iPad als Ziel auswählen und Run starten.

## Datenmigration

Nori 1.9 liest bestehende `library.json`-Dateien aus 1.x weiter. Beim ersten Start werden alte doppelte Progress-Schlüssel (`path` und `path::language`) zusammengeführt; der Datensatz mit dem neuesten `updatedAt` gewinnt. Danach wird Schema v2 atomar gespeichert.

## Noch nicht Bestandteil dieses Sourcepakets

Account-/Cloud-Sync, serverseitiger gemeinsamer Resolver und serverseitige TMDB/AniList-Metadaten benötigen die ursprünglichen Backend-/Web-Quellen. Diese sind im bereitgestellten Workspace nicht enthalten; die Portable-Version liegt nur als gebautes Electron-Artefakt vor.

