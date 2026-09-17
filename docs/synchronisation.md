# Bibliothek zwischen Geräten abgleichen

Merkliste, Verlauf, Wiedergabefortschritt und die geteilten Einstellungen
liegen in einer Datei je Gerät — auf Apple
`~/Library/Application Support/Nori/library.json`, auf dem Fernseher unter
`nori.library` im lokalen Speicher. Schema **v6**.

Abgeglichen wird über **Google Drive**. Apple legt seinen Stand im versteckten
`appDataFolder` ab (`drive.appdata`). Wer auf einem iPhone, iPad oder Mac „Mit
Fernseher teilen" einschaltet, bekommt zusätzlich einen sichtbaren Spiegel
(`drive.file`) — und nur den liest der Fernseher. Wie das eingerichtet wird und welche Werte der Betreiber
anlegen muss, steht in **[google-drive-sync.md](google-drive-sync.md)**. Diese
Datei erklärt, warum es so gebaut ist.

## Warum die Anmeldung nur ein Knopf ist

Ursprünglich stand in den Einstellungen ein Feld für die Google-Client-ID, auf
dem Fernseher zusätzlich eines für das Client-Secret. Der Gedanke dahinter war
richtig: wer Nori nicht selbst übersetzt, hat keine Build-Einstellung, und ohne
diesen Weg gäbe es auf dem iPhone überhaupt keine Möglichkeit, sich anzumelden.

Nur war es keine. Eine Client-ID bekommt man nicht, indem man Nori öffnet — man
bekommt sie, indem man ein Google-Cloud-Projekt anlegt, die Drive-API
aktiviert, einen Zustimmungsbildschirm einrichtet und einen OAuth-Client vom
richtigen Typ erstellt. Das Feld verlangte also nicht eine Eingabe, sondern
einen Nachmittag. Auf dem Fernseher kam eine Bildschirmtastatur dazu, mit der
ein 40-stelliges Secret mit der Fernbedienung einzugeben war.

Ein Feld, das niemand ausfüllen kann, ist keine Möglichkeit — es ist eine
Sackgasse mit Tastatur. Die Werte gehören zum **Build**, weil sie zum Projekt
des Betreibers gehören und nicht zum Nutzer. Fehlen sie, ist das ein Fehler
beim Bauen und keine offene Aufgabe für den, der die App installiert hat; Nori
sagt das in einem Satz und läuft ohne Abgleich weiter.

Was bleibt, ist ein Knopf. Und die Regel dahinter: **die Oberfläche zeigt
Zustand und Handlungen, nicht Konfiguration.**

## Warum der Fernseher einen QR-Code zeigt

Der Gerätefluss verlangt vom Nutzer zwei Dinge: eine Adresse öffnen und einen
Code eintippen. Das Erste ist auf einem Fernseher die eigentliche Zumutung —
`www.google.com/device` mit einer Fernbedienung über eine Bildschirmtastatur,
Buchstabe für Buchstabe.

RFC 8628 sieht dafür `verification_uri_complete` vor: eine Adresse, in der der
Code schon steckt, ausdrücklich für Geräte, die einen QR-Code anzeigen können.
Wer scannt, muss danach nur noch bestätigen.

Zwei Dinge sind dabei bewusst eng gefasst:

- **Der Code entsteht im Gerät.** Ein QR-Dienst im Netz hiesse, die Adresse
  einer laufenden Anmeldung an einen Dritten zu schicken. Der Encoder liegt
  deshalb im Kern (`shared/nori-core/src/qr.ts`), ohne Abhängigkeit und ohne
  einen einzigen Abruf.
- **Die Adresse wird nie gebaut.** Liefert Google keine vollständige, enthält
  der QR-Code genau `verification_uri`, und der Gerätecode steht daneben auf dem
  Bildschirm. Welchen Parameternamen Google an `google.com/device` erwartet,
  sichert es nirgends zu — ein geratener führt auf eine Fehlerseite statt auf
  die Zustimmung, und das sähe auf dem Fernseher aus wie „Nori ist kaputt".

Die Adresse und der Code bleiben trotzdem stehen, gross genug zum Ablesen aus
drei Metern. Ein QR-Code hilft nur dem, der ein Telefon mit Kamera zur Hand
hat.

## Warum nicht eine Datei mit einem Zeitstempel

Ursprünglich stand hier: eine `library.json`, ein `modifiedAt`, der neuere
Stand gewinnt. Kein Feldabgleich, kein Konfliktdialog — bei einer Bibliothek,
die eine Person auf ihren eigenen Geräten führt, wäre das Aufwand ohne
Gegenwert.

Das stimmt nicht. Es verliert schon bei zwei Geräten:

```text
Fernseher und iPhone laden denselben Stand von gestern.
Der Fernseher schreibt den Fortschritt einer Folge.
Das iPhone merkt gleichzeitig einen Titel.
Beide laden ihren kompletten Zustand hoch.
Wer zuletzt schreibt, löscht die Änderung des anderen.
```

Niemand bemerkt das als Konflikt. Jedes Gerät sieht für sich richtig aus; nur
die Änderung ist weg.

Deshalb schreibt **jedes Gerät nur seine eigene Datei** und liest die aller
anderen:

```text
alle Gerätedateien lesen
        ↓
gemeinsamen Zustand berechnen
        ↓
lokal anwenden
        ↓
eigene Datei schreiben
```

Ein Gerät verändert nie die Datei eines anderen. Damit gibt es praktisch keine
Schreibkonflikte, und der Rest ist Rechnen.

## Warum eine Löschung eine Spur hinterlassen muss

Eine Liste sagt, was da ist — nie, was absichtlich weg ist. Würden nur Listen
zusammengeführt, brächte jedes Gerät mit älterem Stand einen entfernten Titel
zurück, und das Entfernen ließe sich nie durchsetzen.

Seit v6 trägt deshalb jede Änderung ihre eigene Marke:

- Die Merkliste ist ein **Zustand** je `provider|slug`, nicht eine Liste.
  `isFavorite: false` ist ein Grabstein und schlägt jedes ältere `true`.
- `historyClearedAt` und `progressClearedAt` verwerfen alles Ältere.
- `recentsRemoved` tut dasselbe für einzeln entfernte Verlaufseinträge.
- Jede Einstellung hat ihren **eigenen** Zeitstempel. Wer auf dem Mac die
  Sprache umstellt und auf dem Fernseher das Autoplay, behält beides — mit
  einem globalen `modifiedAt` verlöre eine der beiden Änderungen.

## Warum die Gerätekennung mitentscheidet

Bei gleichem Zeitstempel gewinnt die lexikographisch größere `deviceId`. Das
sieht willkürlich aus und ist der Kern der Sache: Drive gibt Dateien in keiner
zugesicherten Reihenfolge heraus. Ohne festen Tie-Break käme jedes Gerät zu
einem anderen Ergebnis, schriebe es zurück, und der nächste Abgleich drehte es
wieder um.

`merge(A, B, C)` muss `merge(C, A, B)` sein. Das ist getestet — in beiden
Kernen, in jeder Eingabereihenfolge.

## Warum die Regeln zweimal existieren

Den Kern gibt es in Swift und in TypeScript; TypeScript kann Swift nicht
einbinden. Beide Fassungen müssen dieselbe Entscheidung treffen, sonst
entscheidet der Fernseher anders als das iPhone, beide schreiben zurück, und die
Bibliothek pendelt zwischen zwei Ständen.

Abgesichert ist das über gemeinsame Fälle:

```text
config/sync-fixtures.json
        ├── native/Tests/NoriCoreTests/LibrarySyncTests.swift
        └── shared/nori-core/test/sync.test.ts
```

Dieselbe Datei, dieselben Erwartungen, zusätzlich jede Eingabereihenfolge und
ein zweiter Durchlauf. Wer eine Regel ändert, ändert sie an drei Stellen —
Swift, TypeScript, `config/contract.json` — und die Fixtures fangen ab, wenn
nur zwei davon stimmen.

## Warum ein Fehler nie Daten kostet

Cloud-Abgleich ist optional, die lokale Bibliothek ist es nicht. Deshalb gilt
ausnahmslos: kein Fehler in OAuth, Drive, Netz, Parsing oder Schema führt dazu,
dass lokal etwas gelöscht wird.

- Ein **unlesbarer Fremdstand** wird übergangen; die übrigen laufen durch.
- Ein Stand mit **neuerer Schemaversion** hält den Upload an, statt Felder
  wegzuwerfen, die diese Fassung nicht kennt.
- **Kein Netz** ist ein Zustand und kein Fehler: die Änderungen liegen lokal,
  und beim nächsten Netz geht es weiter.
- Geschrieben wird **atomar**: ein Absturz mittendrin lässt den alten Stand
  stehen statt eines halben JSON.

## Warum nicht bei jeder Wiedergabesekunde

Der Fortschritt wird lokal im Sekundentakt geschrieben — das muss er auch,
sonst fehlt nach einem Absturz die letzte Minute. In die Cloud gehört er
deshalb noch lange nicht im Sekundentakt.

| Auslöser | Wann |
| --- | --- |
| Merkliste, Einstellungen, Verlauf | nach 4 Sekunden Ruhe |
| laufende Wiedergabe | höchstens alle 25 Sekunden |
| Pause, Player verlassen, Folge beendet | sofort |
| Anmeldung, App-Start mit gespeicherter Anmeldung | sofort |
| Rückkehr in den Vordergrund | sofort, wenn lokal etwas offen ist oder der letzte Versuch mindestens 30 Sekunden zurückliegt |
| Gang in den Hintergrund | sofort, wenn lokal etwas offen ist |
| im Vordergrund | alle 30 Sekunden nachsehen |
| „Jetzt synchronisieren" | sofort, vollständig — holen, zusammenführen, schreiben |

Der Gang in den Hintergrund ist der letzte verlässliche Moment. Auf ein „App
wird beendet" ist kein Verlass, und deshalb hängt daran auch nichts.

Auf dem Mac heisst „Vordergrund" das aktive Programm. Ein Mac wechselt
dutzendfach am Tag zwischen Programmen; ohne die 30-Sekunden-Schwelle wäre jeder
Klick in ein anderes Fenster eine Anfrage an Google.

**Nachsehen heisst nicht schreiben.** Ein Abgleich holt und führt immer
zusammen. Hochgeladen wird aber nur, wenn sich der eigene Stand gegenüber dem
unterscheidet, was dieses Gerät zuletzt selbst geschrieben hat und was
unverändert in der Cloud liegt. Sonst schriebe jedes Gerät alle 30 Sekunden
seine Datei neu, und jedes andere holte sie wegen des neuen Änderungsstempels
erneut ab.

Umgesetzt ist das bisher im Swift-Kern (`LibrarySyncEngine`, iOS und macOS).
Die TypeScript-Engine der webOS-App ist unverändert.

Die Wiedergabe wartet nie auf Drive: der Spieler schreibt lokal, meldet die
Änderung und läuft weiter.

## Warum der Fernseher einen sichtbaren Spiegel liest

Der naheliegende Weg — alle Geräte im versteckten `appDataFolder` — ist für den
Fernseher verschlossen. Googles Gerätefluss, der einzige Anmeldeweg ohne
Browser und Tastatur, lehnt `drive.appdata` mit `invalid_scope` ab. Gemessen,
nicht vermutet: mit dem TV-Client von Nori, einem zweiten frisch angelegten
TV-Client und einem Client in einem vollständig neuen Google-Cloud-Projekt,
sofort und nach 5 und 15 Minuten. Googles Dokumentation sagt etwas anderes;
maßgeblich ist, was der Endpunkt antwortet.

`drive.file` lässt der Gerätefluss zu. Dieser Bereich erlaubt nur Dateien, die
Nori selbst angelegt hat — und zwar je **Cloud-Projekt**, nicht je Client. Eine
Datei, die der Mac mit seinem Desktop-Client anlegt, findet der Fernseher mit
seinem TV-Client über eine Suche nach `appProperties`, ohne Dateiauswahl. Im
Proof of Concept mit einem echten Konto bestätigt, ebenso wie die Grenze in die
andere Richtung: mit `drive.file` bleibt der `appDataFolder` verschlossen (403).

Daraus folgt das hybride Modell:

| Gerät | Bereich | liest und schreibt |
| --- | --- | --- |
| iPhone, iPad, Mac ohne Freigabe | `drive.appdata` | `appDataFolder` — wie bisher |
| iPhone, iPad, Mac mit „Mit Fernseher teilen" | `drive.appdata` und `drive.file` | `appDataFolder` **und** TV-Spiegel |
| Fernseher | nur `drive.file` | nur den TV-Spiegel |

Ein Apple-Gerät mit Freigabe ist ein **Relais**. Beide Ablagen laufen gegen
dieselbe lokale Bibliothek; hat die eine den lokalen Stand verändert, stößt sie
die andere an — entprellt wie jede andere Änderung, ohne eigenen Zeitgeber. Weil
ein unveränderter Stand nicht geschrieben wird, schaukelt sich dabei nichts
hoch. Welcher Stand zuletzt geschrieben wurde, merkt sich jedes Gerät je Ablage
dauerhaft: auch nach einem Neustart wird eine unveränderte Datei nicht neu
geschrieben. Im Proof of Concept schrieb der Fernseher ohne diese Prüfung seine
unveränderte Datei 27-mal in 17 Minuten. Die Kehrseite des Relais steht in der
Oberfläche, ohne Fachbegriffe: mindestens ein solches Gerät muss regelmäßig
synchronisieren.

**Warum nicht alles auf `drive.file` umziehen.** Der `appDataFolder` funktioniert
auf Apple, ist unsichtbar und braucht keine zusätzliche Zustimmung. Ihn für alle
zu ersetzen hieße, jedem Nutzer eine sichtbare Kopie aufzuzwingen, auch ohne
Fernseher — und bestehende Stände umzuziehen. Beides unterbleibt.

**Warum eine eigene Zustimmung und kein stilles Einschalten.** Der Spiegel liegt
sichtbar in „Meine Ablage". Das soll niemand zufällig entdecken. Der
Erklärdialog sagt vorher, was dort liegt und worauf Nori Zugriff bekommt; erst
nach Googles Zustimmung — mit `include_granted_scopes`, `drive.appdata` bleibt
erhalten — wird geschrieben, und nur auf diesem Gerät.

**Dieselben Regeln wie im `appDataFolder`.** Eine Datei je Gerät, Pull → Merge →
Push, keine Master-Datei, dieselben Grabsteine. Erkannt wird nur über
`appProperties`: Dateien und Ordner lassen sich umbenennen oder verschieben, ohne
dass der Abgleich bricht. Liegt die eigene Datei im Papierkorb, schreibt Nori
eine neue, statt eine unauffindbare weiter zu beschreiben. Liegen für ein Gerät
mehrere Dateien vor, gilt deterministisch die neueste. Gelöscht wird nichts
automatisch — auch nicht beim Ausschalten.

**Keine Ende-zu-Ende-Verschlüsselung in dieser Fassung.** Der Spiegel ist für
den Kontoinhaber in Drive lesbar, wie jede andere seiner Dateien. Eine
Verschlüsselung bräuchte einen Schlüssel, der auf den Fernseher kommt, ohne dass
ihn jemand mit der Fernbedienung abtippt. Das ist eine mögliche spätere
Erweiterung, kein Teil dieser Fassung.

## Warum iCloud draußen ist

iCloud war fest im Store verdrahtet und hat **nie funktioniert**.
`NSUbiquitousKeyValueStore` braucht die Berechtigung
`com.apple.developer.ubiquity-kvstore-identifier`. Die gibt es nur über das
kostenpflichtige Apple-Developer-Programm, und ohne sie tun die Aufrufe schlicht
nichts — kein Fehler, keine Ausnahme, kein Protokolleintrag. Der Schalter in den
Einstellungen versprach also einen Abgleich, der nie stattfand.

Google Drive war auch deshalb die Wahl: es funktioniert auf allen vier
Plattformen mit demselben Konto, und der `appDataFolder` ist genau für diesen
Zweck gemacht.

Eine Korrektur zur früheren Fassung dieser Datei: `drive.appdata` gilt bei
Google **nicht** als sensibler Bereich. Eine Überprüfung ist dafür nicht nötig,
und der Testmodus ist keine Einschränkung, sondern nur der bequemste Weg für den
Eigengebrauch.

## Warum „erneut anmelden" ein Zustand ist und kein Fehler

Ein Auffrischungstoken gilt nicht für immer. Widerrufen, Passwort geändert, zu
lange nicht benutzt — Google antwortet dann beim Erneuern mit `invalid_grant`.
Nori räumt den wertlosen Token weg, sonst scheiterte jeder Abgleich weiter am
selben Punkt.

Was die Oberfläche daraus machte, war lange ein Fehlertext: „Die Verbindung zu
Google ist abgelaufen. Bitte neu verbinden." Wahr, und trotzdem falsch
eingeordnet — es ist nichts kaputt, es fehlt eine Anmeldung. Schlimmer war der
zweite Fall: kommt die abgelaufene Berechtigung aus der Autorisierungsschicht,
ist sie kein `DriveError`, und der Abgleich landete bei **„offline"**. Die
Oberfläche wartete dann auf ein Netz, das längst da war.

Deshalb gibt es `needsReauthorization` als eigenen Zustand in beiden Kernen,
ohne Fehlertext, mit genau einer Handlung daneben:

```text
Google Drive muss erneut verbunden werden.
[ Erneut anmelden ]
```

## Was von der alten Abstraktion bleibt

`LibrarySyncProvider` — eine Datei ablegen, eine Datei holen — steht weiterhin
im Kern. Sie ist für eine einfache Ablage die richtige Form und wird nicht
entfernt, nur weil aktuell Google Drive umgesetzt ist.

Der Abgleich über mehrere Geräte benutzt daneben `LibrarySnapshotStore`, der
viele Dateien kennt. Umgesetzt ist davon genau einer:
`GoogleDriveSnapshotStore`. Dropbox, WebDAV und Git sind nicht gebaut.

## Was seit v6 zusätzlich abgeglichen wird

Die Schema-Version bleibt v6 — die neuen Felder sind optional und
rückwärtskompatibel, alte Stände dekodieren weiter. Abgeglichen werden
zusätzlich:

- **Untertitel-Einstellungen** (`subtitlePref`, `subtitlesEnabled`) als
  geteilte Präferenz je eigenem Zeitstempel. Greifen nur, wenn der Stream
  Untertitelspuren mitbringt — die Quellen liefern heute keine.
- **Eigene Listen** (`lists`, je `CustomList`). Neben der Merkliste können
  Nutzer eigene Listen anlegen; je Liste gewinnt der jüngste `updatedAt`, bei
  Gleichstand die größere Gerätekennung. Die bestehende Merkliste ist kein
  Mitglied dieser Sammlung und bleibt unangetastet.
- **Manuelle Markierungen** gelten nicht als eigenes Feld — sie schreiben
  `completed` in denselben Fortschrittsspeicher wie das automatische Sichern
  und werden damit über dieselbe `provider|episodePath`-Regel abgeglichen.
