# Bibliothek zwischen Geräten abgleichen

Merkliste, Verlauf, Wiedergabefortschritt und die geteilten Einstellungen
liegen in einer Datei je Gerät — auf Apple
`~/Library/Application Support/Nori/library.json`, auf dem Fernseher unter
`nori.library` im lokalen Speicher. Schema **v6**.

Abgeglichen wird über **Google Drive**, ausschließlich im versteckten
`appDataFolder`. Wie das eingerichtet wird und welche Werte der Betreiber
anlegen muss, steht in **[google-drive-sync.md](google-drive-sync.md)**. Diese
Datei erklärt, warum es so gebaut ist.

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
| App-Start, Rückkehr in den Vordergrund | sofort |
| Gang in den Hintergrund | sofort |
| im Vordergrund | alle 30 Sekunden nachsehen |
| „Jetzt synchronisieren" | sofort, vollständig — holen, zusammenführen, schreiben |

Der Gang in den Hintergrund ist der letzte verlässliche Moment. Auf ein „App
wird beendet" ist kein Verlass, und deshalb hängt daran auch nichts.

Die Wiedergabe wartet nie auf Drive: der Spieler schreibt lokal, meldet die
Änderung und läuft weiter.

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

## Was von der alten Abstraktion bleibt

`LibrarySyncProvider` — eine Datei ablegen, eine Datei holen — steht weiterhin
im Kern. Sie ist für eine einfache Ablage die richtige Form und wird nicht
entfernt, nur weil aktuell Google Drive umgesetzt ist.

Der Abgleich über mehrere Geräte benutzt daneben `LibrarySnapshotStore`, der
viele Dateien kennt. Umgesetzt ist davon genau einer:
`GoogleDriveSnapshotStore`. Dropbox, WebDAV und Git sind nicht gebaut.
