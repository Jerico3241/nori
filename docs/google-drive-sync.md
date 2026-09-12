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

## Für den Nutzer ist das ein Knopf

```text
Einstellungen → Synchronisation → [ Mit Google anmelden ]
```

Danach:

```text
Google Drive
Verbunden
Letzte Synchronisierung: vor wenigen Sekunden
[ Jetzt synchronisieren ]
[ Dieses Gerät trennen ]
```

Mehr ist nicht zu tun. Client-ID, Client-Secret, Redirect-URI, Access- und
Refresh-Token sind **keine** Benutzereinstellungen und stehen nicht in der
Oberfläche. Wer Nori benutzt, muss über OAuth nichts wissen.

Der Rest dieser Datei richtet sich an den, der Nori **baut**.

---

## 1. Was der Betreiber anlegen muss

Ohne diese Werte gibt es keinen Abgleich — Nori sagt dann „Diese Nori-Fassung
wurde ohne Google-Abgleich gebaut" und läuft ansonsten unverändert. Es sind
**vier** OAuth-Clients in **einem** Google-Cloud-Projekt.

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

Und keiner gehört in die Oberfläche. Das ist die Trennung, um die es in diesem
Abschnitt geht:

| | Nutzer | Betreiber / Bauender |
| --- | --- | --- |
| sieht | „Mit Google anmelden" | `GOOGLE_CLIENT_ID`, `VITE_NORI_GOOGLE_TV_CLIENT_ID`, … |
| tut | einmal bei Google bestätigen | einmal je Plattform einen OAuth-Client anlegen |
| muss wissen | nichts über OAuth | Abschnitt 1 dieser Datei |

Frühere Fassungen von Nori haben das vermischt: in den Einstellungen stand ein
Feld für die Google-Client-ID, auf dem Fernseher zusätzlich eines für das
Client-Secret. Gedacht war das als Ausweg für eine fertig installierte App —
tatsächlich war es eine Anmeldung, die erst nach einem Besuch in der Google
Cloud Console möglich war. Auf dem Fernseher kam eine Bildschirmtastatur dazu,
mit der ein 40-stelliges Secret einzugeben war. Wer das vor sich hatte, bekam
keinen Abgleich.

**Die Felder sind weg.** Die Werte kommen aus dem Build.

### Apple

Build-Einstellung `GOOGLE_CLIENT_ID`, von der `Info.plist` beider Targets als
`$(GOOGLE_CLIENT_ID)` übernommen — genau wie `TMDB_API_KEY`. Zum Beispiel in
einer nicht eingecheckten `Local.xcconfig` oder als Umgebungsvariable:

```bash
xcodebuild -project native/Nori-iOS/Nori.xcodeproj -scheme Nori \
  GOOGLE_CLIENT_ID=1234-abc.apps.googleusercontent.com build
```

Ist sie nicht gesetzt, bleibt in der `Info.plist` der unaufgelöste Platzhalter
`$(GOOGLE_CLIENT_ID)` stehen. Nori erkennt das und sagt in einem Satz, dass
diese Fassung ohne Google-Abgleich gebaut wurde — die Bibliothek funktioniert
vollständig weiter, sie bleibt eben auf dem Gerät. Ein Eingabefeld gibt es dafür
nicht: es ist ein **Build-Fehler** und keine Nutzeraufgabe.

Der Diagnosebereich unter *Synchronisation* — zugeklappt, ohne Eingabefeld —
zeigt die benutzte Client-ID, woher sie stammt und den angefragten Bereich. Er
richtet sich an den, der Nori baut.

Ein URL-Schema muss **nicht** in die `Info.plist`:
`ASWebAuthenticationSession` fängt die Rückleitung selbst ab.

### webOS

Vite-Variablen, am besten über eine `apps/webos/.env.local` — die steht in
`.gitignore`:

```bash
VITE_NORI_GOOGLE_TV_CLIENT_ID=1234-xyz.apps.googleusercontent.com \
VITE_NORI_GOOGLE_TV_CLIENT_SECRET=… \
npm --prefix apps/webos run build
```

Fehlen sie, sagt die Oberfläche dasselbe wie auf Apple: ohne Google-Abgleich
gebaut, die Bibliothek läuft weiter. Der Diagnosebereich hängt hier am
Entwicklerschalter *Diagnoseprotokoll* und zeigt Client-ID, Herkunft, **ob** ein
Secret vorliegt (nie welches) und den Bereich.

### Was von früher übrig ist

Wer bereits verbunden ist, hat seine Tokens zu einer **von Hand eingetragenen**
Client-ID bekommen. Würde die jetzt ignoriert, wäre die Verbindung nach dem
Update weg — ohne Grund und ohne Meldung.

Deshalb liest Nori die alten Ablageorte weiter:

| Plattform | alter Ablageort |
| --- | --- |
| Apple | Schlüsselbund `de.nori.google` / `client_id`, sonst `UserDefaults` `nori.google.clientId` |
| webOS | `localStorage` `nori.google.clientId` und `nori.google.clientSecret` |

Der Wert im Gerät hat **Vorrang** vor dem aus dem Build; die vorhandenen Tokens
gehören zu ihm. Stimmen beide überein, wird die Kopie im Gerät beim nächsten
Start stillschweigend aufgeräumt — danach gibt es nur noch eine Quelle. Sind sie
verschieden, gilt weiter der alte, und die Diagnose sagt „aus einer früheren
Fassung übernommen".

**Neu eintragen lässt sich nichts.** Im Diagnosebereich steht ein Knopf, der den
übernommenen Wert verwirft; weil die Tokens zu ihm gehören, trennt er dieses
Gerät gleich mit. Die Bibliothek bleibt vollständig.

### Was öffentlich ist und was nicht

| Wert | Öffentlich? | Darf ins Repository? |
| --- | --- | --- |
| Client-ID (alle Plattformen) | ja, sie steht in jeder Anmeldeadresse | **nein** — gehört zum Projekt des Betreibers |
| Client-Secret (nur webOS) | nein, siehe Abschnitt 3 | **nein, unter keinen Umständen** |
| Access Token, Refresh Token | nein | **nein** |
| `deviceId` | harmlos, zufällig | steht ohnehin nur in der Bibliothek |

Tokens liegen auf Apple im Schlüsselbund und werden nie protokolliert, nie an
Analytics geschickt und nie über Drive synchronisiert. Sie sind ausdrücklich
**kein** Bestandteil von `library.json`.

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

Für den Nutzer ist es überall dasselbe: ein Knopf, eine Bestätigung bei Google,
fertig. Technisch sind es drei Flüsse, weil ein Fernseher keinen Browser zum
Anmelden hat.

| Plattform | Fluss | Rückleitung | Tokenspeicher |
| --- | --- | --- | --- |
| iOS / iPadOS | Authorization Code + PKCE über `ASWebAuthenticationSession` | umgedrehtes Client-Kürzel | Schlüsselbund |
| macOS | Authorization Code + PKCE, Systembrowser + Loopback-Server | `http://127.0.0.1:<freier Port>` | Schlüsselbund |
| webOS | Device Authorization Grant (RFC 8628 / Googles Fluss für Fernseher) | entfällt | privater App-Speicher, **unverschlüsselt** |
| Android | vorbereitet, siehe Abschnitt 7 | — | — |

### iPhone und iPad

```text
Einstellungen → Synchronisation → „Mit Google anmelden"
        ↓
Safari-Blatt mit der Kontoauswahl von Google
        ↓
einmal bestätigen
        ↓
Google leitet zu Nori zurück, der Abgleich startet von selbst
```

Danach ist bei normalen App-Starts keine Anmeldung mehr nötig: der
Auffrischungstoken liegt im Schlüsselbund, und Nori holt sich damit ein neues
Zugriffstoken, wenn das alte abläuft.

**Die Anmeldung läuft in der geteilten Browser-Sitzung.** Bis Version 1.20.0
stand dort `prefersEphemeralWebBrowserSession = true` — die Anmeldung sah die
Cookies aus Safari nicht, und der Nutzer musste sein Google-Passwort eingeben,
auf einem Telefon, das bei Google angemeldet ist. Das ist der Schritt, an dem
eine Einrichtung abgebrochen wird.

Dass die Zustimmung trotzdem gestellt wird, hängt nicht an der Sitzung, sondern
an `prompt=consent` in der Anmeldeadresse. Das bleibt, und aus einem harten
Grund: Google gibt den Auffrischungstoken nur heraus, wenn die Zustimmung in
diesem Durchlauf tatsächlich erteilt wird. Ohne ihn hielte die Verbindung eine
Stunde und wäre danach ohne Zutun weg — `GoogleAuthorization.signIn` wirft
deshalb `noRefreshToken`, statt das als Erfolg zu verbuchen.

Sicherheit kostet die geteilte Sitzung nicht: der Autorisierungscode ist durch
PKCE gebunden, die Antwort durch `state` geprüft, und angemeldet wird in Safari
und nicht in einer WebView, die Nori einsehen könnte.

### Mac

```text
Einstellungen → Synchronisation → „Mit Google anmelden"
        ↓
Systembrowser öffnet Google
        ↓
Konto wählen, bestätigen
        ↓
Browser landet auf 127.0.0.1, Nori ist verbunden
```

Der Loopback-Port wird vom System vergeben und ist deshalb nicht vorhersehbar.
**Kein eigenes URL-Schema:** Google rät für Desktop-Anwendungen davon ab, weil
eine andere Anwendung dasselbe Schema beanspruchen und damit die Antwort
abfangen kann.

### Fernseher

```text
Mehr → Synchronisierung → „Mit Google Drive verbinden"
        ↓
┌──────────────────────────────────────────────┐
│  Google Drive verbinden                      │
│                                              │
│  ███████  Scanne den QR-Code mit deinem      │
│  ██ ▄ ██  Smartphone.                        │
│  ███████                                     │
│           Oder öffne am Telefon              │
│           www.google.com/device              │
│           und gib diesen Code ein            │
│           WDXR-KQPF                          │
│                                              │
│  Nori wartet auf deine Anmeldung …           │
│  Der Code gilt noch 14:32 Minuten.           │
└──────────────────────────────────────────────┘
        ↓
Zustimmung am Telefon
        ↓
der Fernseher merkt es von selbst, der Dialog schliesst, der Abgleich startet
```

Am Fernseher ist danach nichts zu bestätigen. Läuft der Code ab, steht dort ein
Satz — „Der Anmeldecode ist abgelaufen." — und ein Knopf für einen neuen; kein
OAuth-Fehlertext.

Der Dialog sperrt den Fokus ein, „Zurück" bricht ab und gibt den Fokus an die
Abgleich-Reihe zurück.

### Was nirgends vorkommt

- **Out-of-Band.** `urn:ietf:wg:oauth:2.0:oob` — der Weg, bei dem der Nutzer
  einen Code aus dem Browser abtippt — hat Google 2022 abgeschaltet.
- **Eingebettete WebViews.** Eine App, die das Anmeldeformular selbst zeichnet,
  sieht dabei jedes Passwort, und Google lehnt solche Anmeldungen ab.
- **Passwortabfragen in Nori.** Nori sieht nie ein Google-Passwort.
- **Tokens zum Kopieren.** Kein Feld, in das jemand ein Token einfügt.

### Der QR-Code

Er entsteht **im Gerät** (`shared/nori-core/src/qr.ts`) und nicht bei einem
Dienst im Netz. Das ist keine Sparsamkeit: die Adresse, die er abbildet, gehört
zu einer laufenden Anmeldung, und sie an einen Dritten zu schicken wäre genau
die Art Datenweitergabe, die beim Anmelden nicht passieren darf.

Welche Adresse darin steckt, entscheidet Google:

| Googles Antwort | Inhalt des QR-Codes |
| --- | --- |
| `verification_uri_complete` vorhanden | genau dieser Wert — der Code steckt schon darin, am Telefon ist nichts zu tippen |
| nur `verification_uri` / `verification_url` | genau dieser Wert; der Gerätecode steht daneben auf dem Bildschirm |

**Niemals eine selbst zusammengesetzte Adresse.** Welchen Parameternamen Google
an `google.com/device` erwartet, sichert es nirgends zu; ein falscher führt auf
eine Fehlerseite statt auf die Zustimmung. Genauso gibt es keinen Rückfall auf
eine geratene Adresse, wenn Googles Antwort gar keine enthält — dann ist die
Antwort kaputt und wird als kaputt behandelt.

Der Encoder kann Byte-Modus, Fehlerkorrektur M und die Fassungen 1 bis 10; das
reicht für gut zweihundert Zeichen, die längste Adresse dieses Flusses liegt bei
etwa fünfzig. Geprüft ist er gegen eine **unabhängige** Referenzumsetzung, Modul
für Modul über alle Längen von 1 bis 213 Byte
(`shared/nori-core/test/qr.test.ts`).

### Wie oft der Fernseher nachfragt

Googles `interval` wird eingehalten und nicht unterboten. Antwortet Google mit
`slow_down`, steigt das Intervall um fünf Sekunden — oder auf den Wert, den
Google selbst nennt, falls der grösser ist. Eine zweite Abfrageschleife auf
denselben Gerätecode gibt es nicht, und ein Abbruch beendet auch ein laufendes
Warten: sonst dauerte „Abbrechen" bis zu einem ganzen Wartetakt, und wer danach
gleich wieder „Verbinden" drückte, bekam nichts.

| Antwort von Google | Was Nori tut |
| --- | --- |
| `authorization_pending` | weiter warten — der Normalfall |
| `slow_down` | Intervall erhöhen, weiter warten |
| `access_denied` | „Die Anmeldung wurde abgebrochen." |
| `expired_token`, `invalid_grant` | „Der Anmeldecode ist abgelaufen." + neuer Code |
| `admin_policy_enforced` | „Die Einstellungen dieses Google-Kontos erlauben den Zugriff nicht." |
| `invalid_client`, `invalid_scope` | „Der Google-Zugang dieser Nori-Fassung stimmt nicht." — ein Build-Fehler |

### Wenn die Berechtigung nicht mehr gilt

Widerrufen, Passwort geändert, zu lange nicht benutzt: Google antwortet beim
Erneuern mit `invalid_grant`. Der Auffrischungstoken ist dann wertlos und wird
weggeräumt — sonst scheiterte jeder Abgleich weiter am selben Punkt.

Die Oberfläche zeigt dafür einen **eigenen Zustand** und keinen Fehler:

```text
Google Drive muss erneut verbunden werden.
[ Erneut anmelden ]
```

Im Kern heisst er `needsReauthorization` (in Swift und in TypeScript). Vorher
stand dort ein Fehlertext — und wenn die abgelaufene Berechtigung aus der
Autorisierungsschicht kam, sogar „offline", weil sie kein `DriveError` ist. Die
Oberfläche wartete dann auf ein Netz, das längst da war.

### Trennen ist nicht Widerrufen

| | „Dieses Gerät trennen" | „Google-Zugriff widerrufen" |
| --- | --- | --- |
| lokale Tokens | gelöscht | gelöscht |
| andere Geräte | gleichen weiter ab | verlieren den Zugriff |
| Dateien in Drive | bleiben liegen | bleiben liegen |
| lokale Bibliothek | bleibt vollständig | bleibt vollständig |
| Rückfrage | nein | **ja** |

Das Zweite hinter einem unscheinbaren „Abmelden" zu verstecken, wäre die Art
Fehler, die jemand erst bemerkt, wenn der Fernseher nicht mehr mitkommt.

### Der Tokenspeicher auf webOS

webOS bietet Web-Apps **keinen** Schlüsselbund an. Nori legt die Tokens im
privaten Speicher der App ab: von anderen Apps nicht lesbar, aber nicht
verschlüsselt. Wer Zugriff auf das Dateisystem des Fernsehers hat, kann sie
lesen.

Das ist eine Einschränkung der Plattform und keine Entscheidung. Sie steht hier,
damit niemand `localStorage` für einen sicheren Speicher hält. Was dazu
eingehalten wird:

- Tokens werden **nie protokolliert** — auch nicht verkürzt, auch nicht im
  Fehlerfall. Der Web-Inspector eines Fernsehers ist über das Netz erreichbar.
- Tokens werden **nie abgeglichen** und stehen nie in `library.json`.
- Der kurze `user_code` landet ebenfalls nicht im Protokoll: er ist für die
  Dauer seiner Gültigkeit ein Zugang.

Die `GoogleTokenStore`-Schnittstelle ist austauschbar — sobald LG einen
unterstützten Credential-Store anbietet, ist das eine Klasse und keine
Umbauaktion.

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
   zurück (`#if canImport(Security)`). Android braucht eine eigene Umsetzung von
   `GoogleTokenStore` über `EncryptedSharedPreferences` mit einem Schlüssel aus
   dem Android-Keystore.
2. **Anmeldung.** Eine Umsetzung von `GoogleSignInPresenter` über Googles
   **Authorization API** (`com.google.android.gms:play-services-auth`,
   `AuthorizationRequest` mit `requestedScopes = [drive.appdata]` und
   `requestOfflineAccess(serverClientId)`). Der Credential Manager ist dafür
   nicht der richtige Baustein: er authentifiziert (wer ist das?), er
   autorisiert nicht (darf Nori an den App-Ordner?). Kein Firebase — Drive
   braucht es nicht. Kein eingebetteter Browser.
3. **Merkposten.** Eine Umsetzung von `SyncBookkeeping` über
   `SharedPreferences`.
4. **Anbindung.** Aufruf von `GoogleDriveSync` aus der Compose-Oberfläche und an
   den Lebenszyklus.
5. **OAuth-Client und Build-Einstellung.** Ein Client vom Typ *Android* mit
   Paketname und SHA-1 im **selben** Cloud-Projekt, dazu ein Weg, die Client-ID
   beim Bauen zu setzen (`buildConfigField` aus einer nicht eingecheckten
   `local.properties`) — dieselbe Trennung wie `GOOGLE_CLIENT_ID` auf Apple.
   `requestOfflineAccess` braucht zusätzlich die Client-ID des
   **Web**-Clients desselben Projekts; ohne sie gibt es keinen
   Auffrischungstoken und die Verbindung hielte eine Stunde.

Das sind vier kleine Klassen und eine Build-Einstellung; die Arbeit liegt in der
Compose-App, nicht im Abgleich. **Solange sie fehlen, gibt es auf Android keinen
Abgleich** — und diese Datei behauptet nichts anderes.

Die gewünschte Oberfläche ist dieselbe wie auf den anderen Plattformen: ein
Knopf „Mit Google anmelden", danach „Jetzt synchronisieren" und „Dieses Gerät
trennen". Kein Feld für eine Client-ID, keine Tokens, keine technischen
Einstellungen.

---

## 8. Örtlich prüfen

```bash
python3 tools/check-apple-sources.py
cd native && swift test                      # Kern, Migration, Merge, Drive, OAuth
npm --prefix shared/nori-core test           # dieselben Fälle in TypeScript, dazu QR-Code
npm --prefix apps/webos run build            # tsc --noEmit und Vite
python3 tools/check-webos-package.py
```

Der Gerätefluss lässt sich vollständig durchspielen, ohne ein Google-Konto
anzufassen — der Fernbedienungslauf fängt Googles Endpunkte ab:

```bash
npm --prefix apps/webos run mock             # in einem zweiten Fenster
npm --prefix apps/webos run test:tv
```

Geprüft werden dabei QR-Code, Gerätecode, Restlaufzeit, Fokus im Dialog, die
Zurück-Taste, der automatische Abschluss nach der Zustimmung, ein Neustart ohne
erneute Anmeldung und ein abgelaufener Code. Die Bildschirmfotos landen in
`apps/webos/test-shots/`.

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
| „ohne Google-Abgleich gebaut" | Keine Client-ID im Build | `GOOGLE_CLIENT_ID` beziehungsweise die Vite-Variablen setzen — Abschnitt 2. Ein Eingabefeld gibt es dafür nicht. |
| „Google Drive muss erneut verbunden werden" | Berechtigung widerrufen oder abgelaufen | „Erneut anmelden". Nori räumt den wertlosen Token selbst weg. |
| „Der Anmeldecode ist abgelaufen" | Der Gerätecode gilt nur wenige Minuten | „Neuen Code erzeugen" am Fernseher. |
| QR-Code wird nicht erkannt | Zu weit weg, oder der Fernseher steht sehr schräg | Die Adresse und der Code stehen daneben — beide sind so gross, dass sie sich abtippen lassen. |
| „neuerer Stand in der Cloud" | Ein anderes Gerät hat mit neuerem Schema geschrieben | Diese Nori-Fassung aktualisieren. Sie lädt bewusst nicht hoch, um nichts wegzuwerfen. |
| Abgleich bleibt „offline" | Kein Netz, DNS, oder TLS auf dem Fernseher | Lokal ist alles da; beim nächsten Netz geht es weiter. |
| Zwei Dateien für ein Gerät | Sollte nicht vorkommen | Nori erkennt seine Datei am `deviceId` in `appProperties` wieder. Überzählige lassen sich gefahrlos löschen. |

---

## Quellen

- [OAuth 2.0 für Fernseher und Geräte mit eingeschränkter Eingabe](https://developers.google.com/identity/protocols/oauth2/limited-input-device)
- [OAuth 2.0 für native Anwendungen](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Drive-API: Bereiche wählen](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Überprüfung sensibler Bereiche](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification)
- [RFC 8628 — OAuth 2.0 Device Authorization Grant](https://www.rfc-editor.org/rfc/rfc8628)
- [RFC 7636 — PKCE](https://www.rfc-editor.org/rfc/rfc7636)
- [Google Identity für iOS](https://developers.google.com/identity/sign-in/ios/sign-in)
- [Android: Autorisierung zusätzlicher Bereiche](https://developers.google.com/identity/authorization/android)
