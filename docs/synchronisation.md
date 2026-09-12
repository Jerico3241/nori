# Bibliothek zwischen Geräten abgleichen

Merkliste, Verlauf, Fortschritt und Einstellungen liegen in einer einzigen
Datei: `~/Library/Application Support/Nori/library.json`, Schema v5, mit einem
Zeitstempel `modifiedAt`. Ein Abgleich muss deshalb nur zwei Dinge können —
die Datei irgendwo ablegen und sie wieder holen. Genau das verlangt
`LibrarySyncProvider`:

```swift
protocol LibrarySyncProvider: AnyObject, Sendable {
    var name: String { get }
    func load() async throws -> Data?
    func save(_ data: Data, modifiedAt: Double) async throws
}
```

Der neuere Zeitstempel gewinnt. Kein Feldabgleich, kein Konfliktdialog: bei
einer Bibliothek, die eine Person auf ihren eigenen Geräten führt, wäre das
Aufwand ohne Gegenwert.

## Was nach dem Holen passiert

Das ist **keine** Frage des Anbieters, sondern eine Regel des Datenmodells —
und sie liegt deshalb im Kern, nicht in einem Abgleichdienst:
`mergeLibraries` in `shared/nori-core/src/library.ts` (TypeScript-Seite; die
Swift-Seite zieht nach, wenn dort ein Anbieter entsteht).

- **Fortschritt**: je Folge gewinnt der jüngere `updatedAt`.
- **Merkliste**: Vereinigung, sortiert nach `favoriteAddedAt`. Löschungen
  wandern **nicht** mit — dafür bräuchte das Schema Grabsteine. Bis die es
  gibt, ist ein zu viel gemerkter Titel der harmlosere Fehler.
- **Titel und Verlauf**: Vereinigung, der jüngere Eintrag gewinnt.
- **Einstellungen**: vollständig aus dem Stand mit dem jüngeren `modifiedAt`.
  Ein Mischen einzelner Schalter ergäbe eine Einstellung, die auf keinem Gerät
  jemals so gesetzt wurde.

Die wichtigste Folge davon: **ein leerer oder alter Fremdstand löscht nichts.**
Genau das ist der Fehler, den ein Abgleich machen kann und der nicht
rückgängig zu machen ist.

Die webOS-App benutzt dieselbe Funktion schon heute für „Bibliothek einlesen"
in den Einstellungen — ein Einlesen, das den lokalen Stand ersetzt, löscht
stillschweigend alles, was nur auf diesem Gerät stand.

## Warum iCloud draußen ist

iCloud war fest im Store verdrahtet und hat **nie funktioniert**.
`NSUbiquitousKeyValueStore` braucht die Berechtigung
`com.apple.developer.ubiquity-kvstore-identifier`. Die gibt es nur über das
kostenpflichtige Apple-Developer-Programm (99 €/Jahr), und ohne sie tun die
Aufrufe schlicht nichts — kein Fehler, keine Ausnahme, kein Protokolleintrag.
Der Schalter in den Einstellungen versprach also einen Abgleich, der nie
stattfand.

Weggefallen ist damit auch das automatische Hochladen bei jeder Änderung. Ein
Anbieter, der über das Netz geht, gehört nicht in jeden Tastendruck;
angestoßen wird über `syncNow()`.

## Was stattdessen möglich ist

Alle vier Wege sind für den Nutzer kostenlos. Der Unterschied liegt darin,
was **einmalig eingerichtet** werden muss.

| Weg | Kosten | Einmalige Einrichtung | Aufwand im Code |
| --- | --- | --- | --- |
| **Google Drive** (`appDataFolder`) | keine | Google-Cloud-Projekt, OAuth-Client-ID | mittel |
| **Dropbox** | keine | App im Dropbox-Entwicklerportal, App-Key | mittel |
| **WebDAV / Nextcloud** | keine, wenn ein Server da ist | Adresse, Benutzer, Passwort | **klein** |
| **Git-Repository** | keine | privates Repo, Zugriffstoken | klein |

### Google Drive

Der `appDataFolder` ist ein versteckter Ordner je App und Konto. Der Nutzer
sieht ihn in Drive nicht, andere Apps kommen nicht heran, und beim Löschen der
App verschwindet er mit.

- Anmeldung über `ASWebAuthenticationSession` mit OAuth 2.0 und PKCE. Ein
  Client-Secret ist damit nicht nötig und gehört auch nicht in eine App.
- Nötiger Bereich: `https://www.googleapis.com/auth/drive.appdata`.
- Zwei Aufrufe genügen: `files.list` mit `spaces=appDataFolder`, dann
  `files.create` beziehungsweise `files.update` mit `uploadType=media`.
- **Haken:** `drive.appdata` gilt bei Google als sensibler Bereich. Eine
  veröffentlichte App braucht dafür eine Überprüfung. Für den Eigengebrauch
  reicht der Testmodus mit bis zu 100 eingetragenen Konten — ohne
  Überprüfung, ohne Kosten.

### Dropbox

Technisch dasselbe Bild, ohne Überprüfungshürde: App anlegen, Bereich
`files.content.write` und `files.content.read`, dann `/2/files/upload` und
`/2/files/download`. Die Datei liegt sichtbar im Ordner der App.

### WebDAV

Der kürzeste Weg: zwei HTTP-Aufrufe, `GET` und `PUT`, Anmeldung per Basic Auth
über den Schlüsselbund. Kein Entwicklerportal, keine Überprüfung, kein
Token-Auffrischen. Setzt voraus, dass der Nutzer eine Nextcloud oder einen
anderen WebDAV-Speicher hat.

### Git

Ein privates Repository und ein Token; die Bibliothek als eine Datei darin.
Ungewöhnlich, aber der Verlauf ist damit gratis dabei — jeder Stand bleibt
nachvollziehbar und lässt sich zurückholen.

## Empfehlung

**Google Drive**, weil fast jeder ein Konto hat und der `appDataFolder` genau
für diesen Zweck gemacht ist. Der Testmodus deckt den Eigengebrauch ab.

Nötig ist dafür **eine Angabe, die nur der Betreiber liefern kann**: eine
OAuth-Client-ID aus der Google Cloud Console. Ohne sie lässt sich die
Anmeldung nicht bauen — und genau daran ist iCloud gescheitert, nur unsichtbar.
Deshalb wird die Client-ID wie der TMDB-Schlüssel behandelt: nicht im
Quelltext, sondern über Schlüsselbund beziehungsweise Build-Einstellung.

Wer keinen Google-Account einbinden will, ist mit **WebDAV** schneller am
Ziel — vorausgesetzt, es gibt einen Server.
