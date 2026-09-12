# Abgleich über Google Drive

Merkliste, Verlauf, Wiedergabefortschritt und die geteilten Einstellungen
zwischen iPhone, iPad, Mac und Fernseher. Eine Cloud, ein Konto, kein Server.

```text
iOS / iPadOS ─┐
macOS ────────┤
webOS ────────┼──► Google Drive appDataFolder ◄── dasselbe Google-Konto
Android ──────┘        (versteckt, je App)
```

Nori bleibt dabei **local-first**. Die Cloud ist ein Kanal zwischen Geräten und
nie die Voraussetzung: ohne Netz funktioniert alles weiter, und ein
fehlgeschlagener Abgleich fasst die lokale Bibliothek nicht an.

---

## 1. Was der Betreiber anlegen muss

Ohne diese Werte ist der Abgleich nicht einrichtbar — Nori zeigt dann „nicht
eingerichtet" und läuft ansonsten unverändert. Es sind **vier** OAuth-Clients in
**einem** Google-Cloud-Projekt.

| Plattform | Clienttyp in der Cloud Console | Wert, den Nori braucht |
| --- | --- | --- |
| iOS / iPadOS | iOS | Client-ID |
| macOS | Desktop-App | Client-ID |
| webOS | Fernseher und Geräte mit eingeschränkter Eingabe | Client-ID **und** Client-Secret |
| Android | Android | Client-ID (erst nötig, wenn die App existiert) |

Ein gemeinsames Projekt ist keine Bequemlichkeit, sondern Bedingung: der
`appDataFolder` gehört zu **Projekt und Konto**. Vier Projekte hießen vier
getrennte versteckte Ordner, und die Geräte sähen einander nicht.

### Schritt für Schritt

1. **Projekt anlegen oder auswählen.** <https://console.cloud.google.com/> →
   Projektauswahl → *Neues Projekt*. Der Name ist frei; er taucht nur intern auf.

2. **Google Drive API aktivieren.** *APIs & Dienste → Bibliothek* → „Google
   Drive API" → *Aktivieren*. Ohne diesen Schritt antwortet Drive mit `403` und
   der Begründung `accessNotConfigured` — der häufigste Anfängerfehler.

3. **Zustimmungsbildschirm einrichten.** *APIs & Dienste → OAuth-Zustimmungs-
   bildschirm*. Nutzertyp **Extern**, sofern es kein Workspace-Konto ist.
   Anwendungsname, Support-E-Mail und Kontaktadresse sind Pflicht — sie
   erscheinen dem Nutzer bei der Zustimmung.

4. **Bereich hinzufügen.** Genau einen:

   ```text
   https://www.googleapis.com/auth/drive.appdata
   ```

   Nicht `drive`, nicht `drive.file`, kein `email`, kein `profile`. Für den
   Abgleich einer Merkliste geht Google niemand etwas an, und was Nori nicht
   anfordert, kann Nori auch nicht verlieren.

5. **Vier Clients anlegen.** *APIs & Dienste → Anmeldedaten → Anmeldedaten
   erstellen → OAuth-Client-ID*, je Zeile der Tabelle oben einmal.

   - **iOS:** Bundle-ID eintragen. Sie muss der `PRODUCT_BUNDLE_IDENTIFIER` des
     Targets `Nori-iOS` entsprechen. iPhone und iPad teilen sich Bundle-ID und
     damit diesen einen Client.
   - **Desktop-App (macOS):** keine weiteren Angaben. Google vergibt hier auch
     ein Secret; Nori benutzt es **nicht** (siehe Abschnitt 3).
   - **Fernseher/eingeschränkte Eingabe (webOS):** liefert Client-ID **und**
     Client-Secret. Beide werden gebraucht.
   - **Android:** Paketname und SHA-1-Fingerabdruck des Signaturschlüssels.
     Erst nötig, wenn die Compose-App existiert (siehe Abschnitt 7).

### Muss die App überprüft werden?

**Nein.** `drive.appdata` ist bei Google ein **nicht sensibler** Bereich —
anders als `drive` (Vollzugriff), der als *restricted* gilt und eine
Sicherheitsprüfung verlangt.

Das ist ausdrücklich eine Korrektur: `docs/synchronisation.md` behauptete früher,
`drive.appdata` sei sensibel und brauche eine Überprüfung, weshalb nur der
Testmodus mit 100 Konten infrage komme. Das stimmt nicht.

Für den Eigengebrauch reicht der Testmodus mit eingetragenen Testkonten ohnehin.
Wer veröffentlicht, braucht für diesen Bereich keine erweiterte Überprüfung.

---

## 2. Wohin die Werte in Nori gehören

Keiner dieser Werte steht im Quelltext, und keiner gehört ins Repository.

### Apple

Zwei Wege, und der erste ist der wichtigere.

**In der App eintragen.** *Mehr → Synchronisation → Einrichten* (macOS:
*Einstellungen → Synchronisation*). Die Client-ID wird dort eingefügt und
bleibt auf dem Gerät. Das ist der Weg für jede fertig installierte App — wer
Nori nicht selbst übersetzt, hat keine Build-Einstellung, und ohne diesen Weg
gäbe es auf dem iPhone überhaupt keine Möglichkeit, sich anzumelden.

Geprüft wird beim Eintragen, dass die ID auf `.apps.googleusercontent.com`
endet. Das ist keine Förmlichkeit: auf iOS entsteht aus ihr die
Rückleitungsadresse, und steht dort etwas anderes, öffnet sich das
Anmeldefenster und kommt nie zurück.

**Beim Bauen setzen.** Build-Einstellung `GOOGLE_CLIENT_ID`, von der
`Info.plist` beider Targets als `$(GOOGLE_CLIENT_ID)` übernommen — genau wie
`TMDB_API_KEY`. Zum Beispiel in einer nicht eingecheckten `Local.xcconfig`
oder als Umgebungsvariable:

```bash
xcodebuild -project native/Nori-iOS/Nori.xcodeproj -scheme Nori \
  GOOGLE_CLIENT_ID=1234-abc.apps.googleusercontent.com build
```

Die eingetragene ID hat Vorrang vor der aus dem Build. Ist keine von beiden da,
bleibt in der `Info.plist` der unaufgelöste Platzhalter `$(GOOGLE_CLIENT_ID)`
stehen; Nori erkennt das und bietet die Einrichtung an, statt eine Anmeldung
anzubieten, die sicher scheitert.

**Wo sie liegt.** Im Schlüsselbund — und wenn der nicht zur Verfügung steht, in
den Voreinstellungen der App. Der zweite Weg ist kein Versehen: ohne
Signierteam bekommt eine iOS-App keine `application-identifier`-Berechtigung,
und dann lehnt der Schlüsselbund **jede** Ablage ab. Vertretbar ist der
Rückfall nur, weil eine Client-ID kein Geheimnis ist; für **Tokens** gibt es
ihn ausdrücklich nicht.

Ein URL-Schema muss **nicht** in die `Info.plist`:
`ASWebAuthenticationSession` fängt die Rückleitung selbst ab.

### webOS

Ebenfalls zwei Wege, und auch hier ist der erste der wichtigere.

**Am Fernseher eintragen.** *Einstellungen → Synchronisation*. Dort stehen zwei
Felder: Client-ID und Client-Secret. Wer ein fertiges `.ipk` installiert, hat
keine Build-Variable — ohne diesen Weg gäbe es auf dem Fernseher keine
Möglichkeit, sich jemals anzumelden.

Geprüft wird wie auf Apple, dass die Client-ID auf
`.apps.googleusercontent.com` endet, und beim Secret, dass es nicht leer ist
und keinen Leerraum enthält (der kommt beim Einfügen aus einer Zwischenablage
gern mit).

Die Client-ID wird danach angezeigt — sie ist kein Geheimnis, und sie zu sehen
ist der einzige Weg zu bemerken, dass beim Einfügen etwas verrutscht ist. Das
Secret wird **nicht** angezeigt.

**Beim Bauen setzen.** Vite-Variablen:

```bash
VITE_NORI_GOOGLE_TV_CLIENT_ID=1234-xyz.apps.googleusercontent.com \
VITE_NORI_GOOGLE_TV_CLIENT_SECRET=… \
npm --prefix apps/webos run build
```

Am besten über eine `apps/webos/.env.local` — die steht in `.gitignore`.

Eingetragene Werte haben Vorrang vor denen aus dem Build, und „Zugangsdaten
entfernen" räumt beide wieder weg und trennt das Gerät gleich mit: die Tokens
gehören zu genau diesen Zugangsdaten und wären danach wertlos.

**Wo sie liegen.** Im privaten Speicher der App — von anderen Apps nicht
lesbar, aber **nicht verschlüsselt**. Für das Secret gilt damit dasselbe wie
für die Tokens (Abschnitt 4). Schlimmer als die Lage ohnehin schon ist wird es
dadurch nicht: ein beim Bauen gesetztes Secret liegt im `.ipk` und damit
ebenso offen.

### Was öffentlich ist und was nicht

| Wert | Öffentlich? | Darf ins Repository? |
| --- | --- | --- |
| Client-ID (alle Plattformen) | ja, sie steht in jeder Anmeldeadresse | **nein** — gehört zum Projekt des Betreibers |
| Client-ID im Gerät (Schlüsselbund oder Voreinstellungen) | ja | wird nicht abgeglichen und nie hochgeladen |
| Client-Secret (nur webOS) | nein | **nein, unter keinen Umständen** |
| Access Token, Refresh Token | nein | **nein** |
| `deviceId` | harmlos, zufällig | steht ohnehin nur in der Bibliothek |

Tokens liegen auf Apple im Schlüsselbund und werden nie protokolliert, nie an
Analytics geschickt und nie über Drive synchronisiert. Sie sind ausdrücklich
**kein** Bestandteil von `library.json`.

---

## 3. Das Client-Secret auf webOS

Die Regel lautet: in einer App liegt kein Client-Secret. Native Apps und
TV-Apps sind öffentliche Clients — sie werden auf Geräte verteilt und können
nichts geheim halten.

Für iOS und macOS hält Nori sich daran. Google führt `client_secret` für den
Installed-App-Fluss ausdrücklich als optional, und PKCE ersetzt, wofür es
einmal gedacht war.

**Googles Fluss für Fernseher verlangt den Wert trotzdem.** Beim Abholen des
Gerätecodes nicht, beim Eintauschen gegen ein Token schon: dort führt Google
`client_secret` als *Required*. Ohne ihn antwortet Google mit `invalid_client`.

Das ist ein echter Widerspruch zwischen der Regel und dem Protokoll, und er
lässt sich nicht auflösen. Nori geht so damit um:

1. Der Wert wird **nicht eingecheckt**. Er kommt aus einer Build-Variablen und
   liegt nur in der gebauten `.ipk`.
2. Er ist für diesen Clienttyp kein vertrauliches Geheimnis im eigentlichen
   Sinn. Google gibt ihn für Geräte-Clients aus, die ihn naturgemäß nicht
   schützen können; die Sicherheit des Flusses hängt an der Zustimmung am
   zweiten Gerät, nicht an diesem Wert.
3. Er berechtigt zu nichts ohne die ausdrückliche Zustimmung eines Nutzers, und
   er öffnet nur `drive.appdata`.

Wer das nicht tragen will, hat genau eine Alternative: den Abgleich auf webOS
nicht anzubieten. Ein Proxy, der das Secret hält, wäre ein eigener Server — und
genau den soll es nicht geben.

---

## 4. Anmeldewege je Plattform

| Plattform | Fluss | Rückleitung | Tokenspeicher |
| --- | --- | --- | --- |
| iOS / iPadOS | Authorization Code + PKCE über `ASWebAuthenticationSession` | umgedrehtes Client-Kürzel | Schlüsselbund |
| macOS | Authorization Code + PKCE, Browser + Loopback-Server | `http://127.0.0.1:<freier Port>` | Schlüsselbund |
| webOS | Device Code (Fernseher/eingeschränkte Eingabe) | entfällt | privater App-Speicher, **unverschlüsselt** |
| Android | vorbereitet, siehe Abschnitt 7 | — | — |

**Kein Out-of-Band.** `urn:ietf:wg:oauth:2.0:oob` — der Weg, bei dem der Nutzer
einen Code aus dem Browser abtippt — hat Google 2022 abgeschaltet und kommt in
Nori nirgends vor.

**Kein eigenes URL-Schema auf macOS.** Google rät für Desktop-Anwendungen
davon ab: eine andere Anwendung kann dasselbe Schema beanspruchen und damit die
Antwort abfangen. Der Loopback-Port wird vom System vergeben und ist deshalb
nicht vorhersehbar.

**Angemeldet wird im echten Browser**, nie in einer eingebetteten WebView. Eine
App, die das Anmeldeformular selbst zeichnet, sieht dabei jedes Passwort — und
Google lehnt solche Anmeldungen ab.

### Der Tokenspeicher auf webOS

webOS bietet Web-Apps **keinen** Schlüsselbund an. Nori legt die Tokens im
privaten Speicher der App ab: von anderen Apps nicht lesbar, aber nicht
verschlüsselt. Wer Zugriff auf das Dateisystem des Fernsehers hat, kann sie
lesen.

Das ist eine Einschränkung der Plattform und keine Entscheidung. Sie steht hier,
damit niemand `localStorage` für einen sicheren Speicher hält. Die
`GoogleTokenStore`-Schnittstelle ist austauschbar — sobald LG einen
unterstützten Credential-Store anbietet, ist das eine Klasse und keine
Umbauaktion.

---

## 5. Was in der Cloud liegt

Im `appDataFolder`, einem versteckten Ordner je App und Konto. Der Nutzer sieht
ihn in „Meine Ablage" nicht, andere Apps kommen nicht heran, und beim Löschen
der App verschwindet er mit.

**Eine Datei je Gerät:**

```text
nori-sync-v1-<deviceId>.json
```

dazu `appProperties`: `app=nori`, `type=library-snapshot`, `syncVersion=1`,
`deviceId=…`.

Jedes Gerät schreibt **nur seine eigene Datei** und liest die aller anderen.
Deshalb gibt es praktisch keine Schreibkonflikte — und deshalb geht nichts
verloren, wenn Fernseher und iPhone gleichzeitig etwas ändern.

Warum nicht eine gemeinsame Datei mit einem `modifiedAt`, wie es die alte
Dokumentation vorsah: weil das schon bei zwei Geräten verliert. Beide laden
denselben älteren Stand, beide ändern etwas anderes, beide laden ihren
kompletten Zustand hoch — wer zuletzt schreibt, löscht die Änderung des anderen.

**Nicht synchronisiert** werden Cover, Videodaten, Streamadressen, Cookies,
Hoster-Zwischenstände, Caches und Tokens.

Eine Datei ist auf **2 MiB** begrenzt. Eine normale Bibliothek liegt im
zweistelligen Kilobyte-Bereich; was darüber liegt, wird gar nicht erst geladen.

---

## 6. Konfliktregeln

Die verbindliche Fassung steht in `config/contract.json` unter `sync.conflict`
und ist als Code zweimal umgesetzt — `native/NoriCore/Sources/NoriCore/LibrarySync.swift`
und `shared/nori-core/src/sync.ts`. Beide laufen gegen **dieselben** Fälle in
`config/sync-fixtures.json`.

| Daten | Regel |
| --- | --- |
| Merkliste | Zustand je `provider\|slug` mit `isFavorite`. `false` ist ein Grabstein und wird von einem älteren `true` nicht aufgehoben. |
| Fortschritt | Je `provider\|normalisierter episodePath` gewinnt das grössere `updatedAt`. |
| Verlauf | Je `provider\|slug` gewinnt das grössere `viewedAt`, höchstens 100 Einträge. |
| Einstellungen | Je Einstellung ein eigener Zeitstempel; der Wert kommt aus derselben Datei. |
| Löschungen | `historyClearedAt`, `progressClearedAt` und `recentsRemoved` verwerfen ältere Fremdeinträge. |
| Gleichstand | Die lexikographisch grössere `deviceId` gewinnt. |

Der letzte Punkt ist kein Detail: Drive gibt Dateien in keiner zugesicherten
Reihenfolge heraus. Ohne festen Tie-Break käme jedes Gerät zu einem anderen
Ergebnis, schriebe es zurück, und der nächste Abgleich drehte es wieder um.

**Uhren.** Zeitstempel über `jetzt + 24 h` gelten als kaputte Uhr und werden auf
„jetzt" gesetzt; negative und nicht endliche auf 0. Ein Fernseher, der ohne Netz
im Jahr 2100 startet, würde sonst jede echte Änderung für Jahrzehnte schlagen.

**Ablauf.** Immer **Pull → Merge → Push**, nie andersherum. Ein Gerät, das sich
zum ersten Mal verbindet, darf nicht zuerst seinen Stand hochladen und damit
löschen, was dort schon liegt.

---

## 7. Android

Die Android-App gibt es noch nicht. Was es gibt, ist ein Kern, der für Android
übersetzt (siehe `docs/android.md`).

**Fertig und für Android mitübersetzt:**

- Schema v6, Migration, Zusammenführung (`LibrarySync.swift`)
- Ablauf und Zeitplan (`LibrarySyncEngine.swift`)
- Drive-Client mit Wiederholungen und Backoff (`GoogleDrive.swift`)
- OAuth mit PKCE, Tokentausch, Erneuern, Widerruf (`GoogleOAuth.swift`) —
  ausdrücklich ohne CryptoKit, damit es dort übersetzt

**Was noch fehlt und nur in der Android-App liegen kann:**

1. **Tokenspeicher.** `KeychainTokenStore` gibt ausserhalb von Apple nichts
   zurück. Android braucht eine eigene Umsetzung von `GoogleTokenStore` über
   den empfohlenen Credential-/Keystore-Weg.
2. **Anmeldung.** Eine Umsetzung von `GoogleSignInPresenter` über den aktuellen
   Authorization-Client von Google Identity Services. Kein Firebase — Drive
   braucht es nicht.
3. **Merkposten.** Eine Umsetzung von `SyncBookkeeping` über
   `SharedPreferences`.
4. **Anbindung.** Aufruf von `GoogleDriveSync` aus der Compose-Oberfläche und
   an den Lebenszyklus.

Das sind vier kleine Klassen; die Arbeit liegt in der Compose-App, nicht im
Abgleich. **Solange sie fehlen, gibt es auf Android keinen Abgleich** — und
diese Datei behauptet nichts anderes.

---

## 8. Örtlich prüfen

```bash
python3 tools/check-apple-sources.py
cd native && swift test                      # Kern, Migration, Merge, Drive, OAuth
npm --prefix shared/nori-core test           # dieselben Fälle in TypeScript
npm --prefix apps/webos run build            # tsc --noEmit und Vite
python3 tools/check-webos-package.py
```

Die Apple-Targets bauen über `xcodebuild -scheme Nori` beziehungsweise über die
Läufe `Build iOS` und `Build macOS`.

### Mit einem echten Konto

1. Ein eigenes Test-Google-Konto anlegen und im Zustimmungsbildschirm als
   Testnutzer eintragen.
2. Auf Gerät A verbinden, einen Titel merken, eine Folge anspielen.
3. Auf Gerät B mit **demselben** Konto verbinden. Erwartung: Merkliste und
   Fortschritt erscheinen.
4. Auf B etwas ändern, auf A „Jetzt synchronisieren". Erwartung: die Änderung
   kommt an.
5. In Drive nachsehen: <https://drive.google.com/drive/my-drive> — die
   Nori-Dateien dürfen dort **nicht** auftauchen. Sie liegen im versteckten
   Ordner; sichtbar sind sie nur über die API mit
   `spaces=appDataFolder`.

---

## 9. Erreichbarkeit auf dem Fernseher

Eine webOS-App wird von `file://` geladen und sendet damit `Origin: null`. Ob
Googles Endpunkte unter dieser Bedingung überhaupt erreichbar sind, war die
offene Frage — ohne sie wäre die ganze webOS-Seite hinfällig.

Gemessen am 12. September 2026:

| Endpunkt | Methode | Ergebnis mit `Origin: null` |
| --- | --- | --- |
| `oauth2.googleapis.com/device/code` | `OPTIONS` | `200`, `access-control-allow-origin: null`, POST und `content-type` erlaubt |
| `oauth2.googleapis.com/token` | `OPTIONS` | `200`, `access-control-allow-origin: null` |
| `www.googleapis.com/drive/v3/files` | `GET` | `401` (ohne gültigen Token erwartet), `access-control-allow-origin: *` |
| `www.googleapis.com/upload/drive/v3/files` | `OPTIONS` | `200`, `access-control-allow-origin: *`, `authorization` erlaubt |

Zusätzlich aus einer echten, fremden Herkunft im Browser geprüft: sowohl der
Gerätecode-Aufruf als auch `files.list` liefern einen lesbaren JSON-Körper
zurück (`invalid_client` beziehungsweise `401`), statt von CORS geblockt zu
werden. Ein Körper, den JavaScript lesen kann, ist der Beweis — geblockte
Anfragen liefern gar nichts.

**Damit braucht webOS keinen Proxy und keinen JavaScript-Service.** `fetch()`
genügt.

**Was damit nicht bewiesen ist:** dass die Chromium-Fassung eines bestimmten
LG-Fernsehers sich genauso verhält, und dass dessen Zertifikatsspeicher Googles
Kette trägt. Das lässt sich nur auf echter Hardware oder im Emulator
feststellen. Die gemessenen Werte sind Eigenschaften von Googles Servern und
gelten für jeden Client, der sie so anfragt.

---

## 10. Wenn etwas nicht geht

| Meldung | Ursache | Abhilfe |
| --- | --- | --- |
| `invalid_client` | Client-ID oder Secret falsch, oder falscher Clienttyp | Für webOS muss es ein Client für *Fernseher und Geräte mit eingeschränkter Eingabe* sein. |
| `accessNotConfigured` | Drive API im Projekt nicht aktiviert | Schritt 2 oben. |
| `access_denied` beim Zustimmen | Konto nicht als Testnutzer eingetragen | Im Zustimmungsbildschirm ergänzen. |
| `invalid_scope` | Der Bereich ist für den Clienttyp nicht erlaubt | Der Gerätefluss erlaubt nur wenige Bereiche; `drive.appdata` gehört dazu. |
| `invalid_grant` beim Erneuern | Zugriff widerrufen, Passwort geändert, lange nicht benutzt | Neu verbinden. Nori räumt den wertlosen Token selbst weg. |
| „nicht eingerichtet" | Keine Client-ID hinterlegt | In der App eintragen oder beim Bauen setzen — Abschnitt 2. |
| „Der Schlüsselbund hat die Ablage abgelehnt" | App ohne Signierteam gebaut | Tritt seit dem Rückfall auf die Voreinstellungen nicht mehr auf; bei Tokens bleibt der Schlüsselbund Voraussetzung. |
| „neuerer Stand in der Cloud" | Ein anderes Gerät hat mit neuerem Schema geschrieben | Diese Nori-Fassung aktualisieren. Sie lädt bewusst nicht hoch, um nichts wegzuwerfen. |
| Abgleich bleibt „offline" | Kein Netz, DNS, oder TLS auf dem Fernseher | Lokal ist alles da; beim nächsten Netz geht es weiter. |
| Zwei Dateien für ein Gerät | Sollte nicht vorkommen | Nori erkennt seine Datei am `deviceId` in `appProperties` wieder. Überzählige lassen sich gefahrlos löschen. |

---

## Quellen

- [OAuth 2.0 für Fernseher und Geräte mit eingeschränkter Eingabe](https://developers.google.com/identity/protocols/oauth2/limited-input-device)
- [OAuth 2.0 für native Anwendungen](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Drive-API: Bereiche wählen](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Überprüfung sensibler Bereiche](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification)
