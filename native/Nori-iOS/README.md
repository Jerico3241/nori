# Nori für iPhone (SwiftUI) — 1.9.2

Native iPhone/iPad App mit SwiftUI und AVPlayer. Der aktuelle iOS-Client arbeitet lokal; Merkliste und Fortschritt benötigen keinen Account.

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

Die `.ipa` kann außerhalb von macOS/Xcode nicht gebaut werden.

1. Diesen Ordner auf einen Mac legen.
2. `IPA-bauen.command` ausführen.
3. Xcode lädt beim ersten Build SwiftSoup.
4. Die erzeugte IPA anschließend mit dem gewünschten Signing-Verfahren installieren.

## Direkt aus Xcode

1. `Nori.xcodeproj` öffnen.
2. Unter Signing ein Development Team auswählen.
3. iPhone/iPad als Ziel auswählen und Run starten.

## Datenmigration

Nori 1.9 liest bestehende `library.json`-Dateien aus 1.x weiter. Beim ersten Start werden alte doppelte Progress-Schlüssel (`path` und `path::language`) zusammengeführt; der Datensatz mit dem neuesten `updatedAt` gewinnt. Danach wird Schema v2 atomar gespeichert.

## Noch nicht Bestandteil dieses Sourcepakets

Account-/Cloud-Sync, serverseitiger gemeinsamer Resolver und serverseitige TMDB/AniList-Metadaten benötigen die ursprünglichen Backend-/Web-Quellen. Diese sind im bereitgestellten Workspace nicht enthalten; die Portable-Version liegt nur als gebautes Electron-Artefakt vor.
