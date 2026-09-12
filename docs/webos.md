# Nori für LG webOS

Die TV-Fassung von Nori, Stand **1.2.0**. Eigenständige App, kein skalierter
Webauftritt: vollständig mit der Fernbedienung bedienbar, auf 1920 × 1080
ausgelegt und auf andere Auflösungen mitskalierend.

## Aufbau

```
apps/webos/          TV-Oberfläche (React, TypeScript, Enact Spotlight, hls.js)
shared/nori-core/    gemeinsamer Kern in TypeScript — Modelle, Provider,
                     Parser, Hoster-Resolver, Bibliotheksregeln, TMDB
services/nori-api/   Provider-Schicht als HTTP-Dienst, benutzt denselben Kern
```

Der Kern ist die TypeScript-Entsprechung von `native/NoriCore/`, dem
gemeinsamen Swift-Kern der Apple-Apps. Maßgeblich ist für beide
`config/contract.json`. Feldnamen, Regeln und Ablageformat sind übernommen,
nicht neu erfunden: eine `library.json` aus der iOS- oder macOS-App liest sich
hier ohne Umschreiben.

### Warum es den Nori-Server gibt

iOS und macOS rufen AniWorld und Serienstream direkt ab und setzen dabei
Kopfzeilen, die ein Browser nicht setzen darf — vor allem `Referer`, ohne den
viele Hoster den Stream verweigern. Auf dem Fernseher läuft Nori aber in einem
Browser.

```
webOS-Client
     ↓  HTTP
services/nori-api
     ↓  shared/nori-core
AniWorld / Serienstream
     ↓
HosterResolver
     ↓
Weiterreichung mit Referer  (HLS-Playlists werden umgeschrieben,
     ↓                       damit auch die Segmente darüber laufen)
Hoster
```

Der Client kennt keinen einzigen Hoster: er bekommt ein `PlaySource` und eine
Adresse, die er laden kann. Hosterspezifische Extraktion liegt an genau einer
Stelle, im Kern.

**Direkter Weg.** In den Einstellungen lässt sich statt des Servers „Direkt vom
Fernseher" wählen. Dann benutzt der Client denselben Kern selbst. Das kommt
ohne Einrichtung aus, hängt aber davon ab, dass webOS der App fremde Abrufe
erlaubt und der Hoster ohne `Referer` ausliefert — ein Rückfall, kein Ersatz.
Was dabei eingeschränkt ist, steht unten unter *Bekannte Einschränkungen*.

## TMDB

TMDB liefert alles, was die Quellen nicht haben: Poster in brauchbarer Größe,
Hintergrundbilder, freigestellte Schriftzüge, Beschreibungen, Bewertungen,
Genres, Folgentitel, Folgenbeschreibungen und Standbilder — und die Signale,
aus denen „Neu & beliebt" und „Für dich" entstehen.

Die Logik dazu liegt im gemeinsamen Kern unter `shared/nori-core/src/tmdb/` und
entspricht `TMDBMatcher.swift`, `TMDBImages.swift`, `TMDBCatalog.swift` und
`HomeFeed.swift` der Apple-Seite. Es gibt bewusst **keine** dritte Umsetzung:
die webOS-App und der Nori-Server benutzen beide diese Dateien.

### Der Schlüssel ist mitgeliefert

**Einzurichten ist nichts.** `shared/nori-core/src/tmdb/key.ts` hält
`BUILT_IN_TMDB_KEY` — denselben Schlüssel, den iPhone und Mac benutzen
(`TMDBKeyStore.builtIn`). Ein frisch installierter Fernseher hat damit sofort
Poster, Hintergrundbilder, Schriftzüge, Beschreibungen, Bewertungen,
Folgentitel und Folgenbilder.

Auf einem Fernseher wiegt das mehr als auf einem Telefon: dort gibt es keine
Tastatur, und einen 32-stelligen Hex-Schlüssel mit einer Fernbedienung über
eine Bildschirmtastatur einzugeben, ist die Sorte Einrichtung, die niemand
macht.

Was das heißt, gehört dazugesagt: der Schlüssel steckt im gebauten `.ipk` und
lässt sich daraus herausziehen. Das ist die Entscheidung des Betreibers für ein
privates Repository — dieselbe wie auf der Apple-Seite, nachzulesen an der
Deklaration in `key.ts`. `tools/check-webos-package.py` erlaubt genau diese
eine Zeile; jeder zweite einkompilierte Schlüssel fällt auf, und ein Abgleich
prüft, dass beide Seiten dieselbe Zeichenkette benutzen.

### Drei Wege

| Einstellung | Wer fragt TMDB | Welcher Schlüssel |
| --- | --- | --- |
| **Über den Nori-Server** | der Server | `NORI_TMDB_KEY`, sonst der mitgelieferte |
| **Dieser Fernseher** | der Fernseher selbst | der eigene aus den Einstellungen, sonst der mitgelieferte |
| **Aus** | niemand | — |

Über den Server ist es der bessere Weg: der Zwischenspeicher gilt für alle
Fernseher gemeinsam, und TMDBs Ratenbegrenzung wird einmal statt je Gerät
ausgeschöpft. Nötig ist er nicht.

Ein **eigener** Schlüssel hat immer Vorrang. Er ist der Weg, die
Ratenbegrenzung von der geteilten Kennung zu trennen:

```bash
cd services/nori-api
NORI_TMDB_KEY=<eigener v3-Schlüssel> npm run dev
```

`/api/health` sagt in `features.tmdbKey`, ob dort ein eigener oder der
mitgelieferte gilt — den Schlüssel selbst gibt der Dienst nie heraus. Die
Einstellungen des Fernsehers zeigen es beim Prüfen der Serveradresse an, und
die Diagnosezeile nennt den tatsächlich benutzten Weg.

`/api/tmdb/<pfad>` ist **kein** offener Weiterreicher: der Pfad wird gegen eine
Liste geprüft (`services/nori-api/src/tmdb.ts`), `api_key` aus der Anfrage
verworfen, und die Antworten liegen mit eigener Frist je Pfad im
Arbeitsspeicher.

**Mit „Aus"** zeigt Nori die Cover und Texte der Quellen. Das ist ein gültiger
Zustand, kein Fehler: „Neu & beliebt" erscheint dann nicht, an seiner Stelle
steht „Neu im Katalog" mit dem Hinweis, dass die Reihenfolge von der Quelle
kommt. Eine Reihe, die „beliebt" heißt und der Katalogreihenfolge folgt, wäre
eine Behauptung.

### Zuordnung: lieber kein Treffer als ein falscher

Der Titel entscheidet, alles andere gewichtet nur. Beliebtheit, Genre und
Herkunftsland können einen Treffer vor einen anderen ziehen, aber keinen
Treffer *erzeugen*. Verglichen wird gegen Haupttitel, Originaltitel und **alle
Alternativtitel beider Seiten**, jeweils auch in der um Staffel- und
Jahresangaben bereinigten Form — „Attack on Titan Staffel 2", „Attack on Titan
Final Season" und „Shingeki no Kyojin" treffen damit denselben Eintrag.

Bleibt ein Titel ohne Treffer, wird **einmal** der oberste TMDB-Vorschlag
geholt und mit seinen Alternativtiteln erneut bewertet. Das ist der Weg, über
den „Sousou no Frieren" den Eintrag „Frieren: Beyond Journey's End" findet — die
Schwelle bleibt dieselbe, nur die Datenlage wird besser.

Staffeln werden **nicht** nach Nummer zugeordnet. `pickTmdbSeason` vergleicht
Nummer und Folgenzahl; weichen sie ab, gilt eine Staffel mit passender
Folgenzahl, und bei mehreren gleich langen gar keine. `alignEpisodes` erkennt
zusätzlich einen Versatz über die Folgentitel — bei „Attack on Titan Final
Season" beginnt die Quelle wieder bei Folge 1, während TMDB ab 17 weiterzählt.
Ist die Zuordnung unsicher, erscheinen **keine** Folgendaten; ein Standbild aus
der falschen Folge verrät im Zweifel die Handlung.

Zugeordnete Kennungen liegen versioniert im `localStorage`
(`nori.tmdb.titles.v2` und Nachbarn). Ändert sich die Zuordnung, wird die
Fassungsnummer erhöht und der alte Stand beim ersten Start verworfen — sonst
bliebe ein falscher Treffer für immer stehen. Von Hand geht dasselbe über
*Einstellungen → TMDB → Bildspeicher leeren*.

## Voraussetzungen

- Node 20 oder neuer
- Für Installation und Protokolle: das LG-SDK, `npm i -g @webosose/ares-cli`
- Ein LG-Fernseher mit webOS 6 oder neuer im Entwicklermodus

Das Paket entsteht **ohne** SDK: `npm run webos:package` schnürt das `.ipk`
selbst (ar plus tar, siehe `apps/webos/tools/package-ipk.mjs`).

## Bauen

```bash
cd apps/webos
npm install
npm run build          # prüft Typen und baut nach dist/
npm run webos:package  # ergibt tv.nori.app_1.2.0_all.ipk
```

Vom Repository-Stamm aus geht auch `npm run webos:build` und
`npm run webos:package`.

Der Nori-Server daneben:

```bash
cd services/nori-api
npm install
npm run dev            # hört auf 0.0.0.0:8730, TMDB ohne Einrichtung
```

### Versionsnummer

**Jeder installierbare Stand bekommt eine neue Nummer.** Zwei Pakete mit
derselben Nummer, aber unterschiedlichem Inhalt, sind hinterher nicht mehr
unterscheidbar — und der Fernseher installiert das zweite nicht über das erste.

Zu erhöhen sind `apps/webos/appinfo.json` und `apps/webos/package.json`, dazu
gehört ein Abschnitt `## [webOS x.y.z]` im `CHANGELOG.md` und die Zeile in
seiner Übersicht. `python3 tools/check-webos-package.py` vergleicht alle vier
Stellen samt Paketnamen und den Dateien im Paket und bricht ab, wenn eine
abweicht.

## Entwicklungsstand

```bash
cd services/nori-api && npm run dev &
cd apps/webos && npm run dev
```

Vite liegt auf `http://localhost:8731` und reicht `/api` an den Server weiter.
Im Browser lässt sich alles mit den Pfeiltasten und Enter bedienen; Escape
entspricht der Zurück-Taste der Fernbedienung.

## Installation auf dem Fernseher

1. **LG-Konto anlegen** auf <https://lgaccount.lge.com> und am Fernseher
   anmelden.
2. **Developer Mode installieren**: im LG Content Store nach „Developer Mode"
   suchen, installieren, starten, mit demselben Konto anmelden und
   *Dev Mode Status* auf **on** stellen. Der Fernseher startet neu und zeigt
   danach eine **Passphrase** und seine **IP-Adresse**.
3. **Gerät eintragen** (einmalig, am Rechner):

   ```bash
   ares-setup-device --add tv --info "{'host':'192.168.1.50','port':'9922','username':'prisoner'}"
   ares-novacom --device tv --getkey        # fragt nach der Passphrase
   ```

4. **Installieren und starten**:

   ```bash
   cd apps/webos
   npm run webos:install tv
   npm run webos:launch tv
   ```

   Ohne Gerätenamen wird das voreingestellte Gerät benutzt; alternativ
   `NORI_WEBOS_DEVICE=tv` setzen.

5. **Nori einrichten**: beim ersten Start unter *Einstellungen → Verbindung*
   die Adresse des Nori-Servers eintragen, etwa `http://192.168.1.20:8730`, und
   auf **Prüfen** gehen. Fernseher und Server müssen im selben Netz sein. Die
   Antwort sagt zugleich, welchen TMDB-Schlüssel der Server benutzt.

   Für TMDB selbst ist nichts einzurichten — ohne Server fragt der Fernseher
   direkt, mit dem mitgelieferten Schlüssel.

### Fehlersuche

```bash
npm run webos:inspect tv    # Web-Inspector im Browser öffnen
node tools/webos-cli.mjs log tv
```

Im Protokoll trägt alles von Nori das Präfix `[Nori:webOS]`. Ausführlich wird
es erst, wenn in den Einstellungen *Diagnoseprotokoll* eingeschaltet ist —
sonst bleiben nur Warnungen und Fehler übrig. Der Bereich `[tmdb]` nennt jeden
Treffer samt Kennung, jede Staffelzuordnung samt Güte und Versatz und jede
Zuordnung, die abgelehnt wurde.

### Entwicklermodus verlängern

Die Developer-Mode-App zeigt eine Restlaufzeit (üblicherweise 50 Stunden). Der
Knopf **Extend Dev Mode Status** in derselben App setzt sie zurück; das geht
beliebig oft, muss aber vor Ablauf geschehen, sonst wird die App vom Fernseher
entfernt und muss neu installiert werden.

## Bedienung

| Taste | Wirkung |
| --- | --- |
| Pfeiltasten | Fokus bewegen; im Player ohne sichtbare Bedienung Links/Rechts = spulen, Hoch = Drawer |
| OK (13) | auslösen; im Player ohne Bedienung Wiedergabe/Pause |
| Zurück (461 / 10009) | Auswahlraster zu → Drawer zu → Bedienung zu → Player verlassen → Ansicht zurück → App verlassen |
| Play (415) / Pause (19) / Stop (413) | Wiedergabe steuern |
| Vor-/Zurückspulen (417 / 412) | springen, bei gehaltener Taste schneller |

Am Rechner ersetzen Escape die Zurück-Taste und die Leertaste Wiedergabe/Pause.

Der erste Fokus liegt im Inhalt, nicht in der Seitenleiste — die erreicht man
über „links" und sie klappt nur auf, solange sie den Fokus hat.

## Unterstützte Stände

Gebaut wird auf **Chrome 79** — die Engine von webOS 6. Damit läuft dieselbe
Datei auf webOS 6 bis 26; neuere Sprachmerkmale werden übersetzt, `?.` und `??`
eingeschlossen. `aspect-ratio` bekommt über `@supports` einen Rückfall,
`CSS.escape` und `AbortSignal.any` werden nicht benutzt.

### Flex-Abstände auf webOS 6

Chrome 79 kennt `gap` **nur im Raster**, nicht im Flex-Layout — das kam erst
mit Chrome 84. Noris Oberfläche benutzt es an gut vierzig Stellen; ohne
Rückfall klebt dort alles aneinander, und zwar genau auf dem ältesten Gerät,
das Nori unterstützen soll.

Über `@supports` lässt sich das nicht erfragen: `@supports (gap: 1px)` ist in
Chrome 79 **wahr**, weil es Rasterabstände kennt. Nori misst deshalb beim Start
(`supportsFlexGap` in `src/services/webos.ts`) und schreibt das Ergebnis als
`data-flex-gap` an das Wurzelelement; das Stylesheet hängt daran einen Rückfall
über Ränder (`> * + *`). Auf einem neueren Panel greift keine dieser Regeln.

Der Fernbedienungslauf prüft beides: dass die Messung in einem heutigen
Chromium „ja" sagt — sonst gäbe es dort doppelte Abstände —, und dass der
Rückfall bei abgeschaltetem Flex-`gap` denselben Abstand zwischen zwei Kacheln
erzeugt.

### Warum ein klassisches Bündel

Ein webOS-Paket wird von
`file:///usr/palm/applications/tv.nori.app/index.html` geladen, nicht über
HTTP. Dort scheitern drei Dinge, die über HTTP nie auffallen — und alle drei
enden in einem schwarzen Bildschirm **ohne** Fehlermeldung, weil das Skript,
das den Fehler melden würde, nie läuft:

| Was | Warum es dort scheitert |
| --- | --- |
| `<script type="module">` | Chromium lädt keine ES-Module von `file://` — die Seite hat die Herkunft `null`. |
| `crossorigin` | Macht aus einem gleichartigen Abruf einen mit Herkunftsprüfung, und die scheitert aus demselben Grund. |
| `/assets/index.js` | Ein führender Schrägstrich zeigt auf die Wurzel des Dateisystems. |

`vite.config.ts` baut deshalb **ein** klassisches Skript (`format: "iife"`,
`modulePreload: false`), entfernt `crossorigin`, ersetzt `type="module"` durch
`defer` und setzt `base: "./"`. Die aufgeteilten Bündel fallen dabei weg, und
das ist kein Verlust: die Dateien liegen auf dem Gerät, nicht im Netz — es gibt
keine Übertragung, die sich parallelisieren ließe.

Die Stile bleiben eine eigene Datei (`cssCodeSplit: false`), obwohl Vite sie
bei einem einzigen Bündel sonst in das Skript legt. Der Startbildschirm in
`index.html` ist genau für den Moment davor da; unformatiert wäre er ein
Absatz auf Weiß.

Geprüft wird das zweifach: `tools/check-webos-package.py` beanstandet alle drei
Fälle in `dist/index.html`, und der Fernbedienungslauf öffnet die gebaute Datei
zusätzlich **über `file://`** und sieht nach, dass die App sich aufbaut, die
Stile greifen, die Daten ankommen und der Fokus sitzt.

## Prüfen

```bash
npm --prefix shared/nori-core test     # Kern gegen dieselben Fixtures wie Swift
npm --prefix services/nori-api test    # Playlisten, TMDB-Pfadliste, Schlüssel
python3 tools/check-webos-package.py   # Quelltext, .ipk, Versionen, Schlüssel
cd apps/webos && npm run typecheck
```

In der CI macht das der Lauf **Build webOS**, ausgelöst durch Pushes auf
`apps/webos/**`, `shared/nori-core/**` und `services/nori-api/**`. Er läuft auf
demselben self-hosted Mac wie alle anderen Läufe (siehe
`docs/self-hosted-runner.md`) — ist der aus, wartet der Job in der
Warteschlange, statt zu scheitern. Xcode braucht er nicht, nur Node.

Die Oberfläche lässt sich mit einer nachgebauten Fernbedienung durchspielen:

```bash
cd apps/webos
npm run build
npm run mock &                          # Nori-Server und TMDB mit festen Daten
npm i -D playwright && npx playwright install chromium
npm run test:tv
```

Der Lauf drückt echte LG-Tastencodes und prüft unter anderem, dass nie ein
Zustand ohne Fokus entsteht, dass der Fokus nie außerhalb des Bildes liegt,
dass er beim Zurückgehen auf derselben Kachel steht, dass Drawer und
Staffelraster den Fokus einsperren, dass nach dem Verlassen des Players kein
Stream weiterläuft, dass ein Hosterfehler in einem benannten Fehlerzustand
endet — und dass im ganzen Bild keine orangefarbene Fläche mehr steht.

Dabei entstehen **21 Bildschirmfotos** in `apps/webos/test-shots/`
(Bootscreen, Startseite, fokussierte Kachel, Seitenleiste, Entdecken,
Kalender, Suche, Merkliste, Verlauf, Einstellungen, Staffelwahl, Detailseite,
ähnliche Titel, Weiterschauen, Player, Player-Drawer, Playerfehler,
Fehlerzustand, TMDB ohne Einrichtung, Aufbau über `file://`). Der Ordner liegt
nicht im Repository; `NORI_SHOTS=<Ordner>`
legt sie woanders ab.

Der Nachbau unter `test/mock-tmdb.mjs` enthält absichtlich die drei Fälle, die
in der Praxis schiefgehen: ein Titel, dessen TMDB-Name mit dem Quelltitel
nichts gemeinsam hat; eine Staffel mit versetzter Folgenzählung; ein Titel, den
TMDB gar nicht führt.

## Bekannte Einschränkungen

- **Der Abgleich über Google Drive ist nicht auf einem Fernseher geprüft.** Er
  ist gebaut (Einstellungen → Abgleich, Anmeldung über den Gerätecode) und die
  Zusammenführungsregel ist in beiden Kernen gegen dieselben Fälle geprüft
  (`config/sync-fixtures.json`); der Ablauf über ein echtes Google-Konto und
  zwei echte Geräte ist es nicht. Siehe `docs/google-drive-sync.md`.
- **Ohne Drive bleibt die Bibliothek im `localStorage`** des Fernsehers. Das
  Format ist dasselbe wie in der `library.json` von iPhone und Mac, und
  „Bibliothek einlesen" **führt zusammen statt zu ersetzen**
  (`mergeLibrarySnapshots` im Kern) — ein Stand lässt sich also auch von Hand
  übernehmen, ohne etwas zu verlieren.
- **Export und Einlesen gehen über die Konsole und ein Eingabefeld.** Der
  Fernseher hat keinen Dateimanager, und webOS blockt einen Download aus einer
  `file://`-App.
- **Im direkten Modus** hängt alles daran, dass webOS der App fremde Abrufe
  erlaubt. Die Kataloge kommen dort meist durch, die Streams oft nicht: viele
  Hoster verlangen einen `Referer`, den ein Browser nicht setzen darf. Nori
  erkennt das nicht vorab — es zeigt den Fehler des Hosters, statt einen
  Erfolg zu behaupten. Der Serverweg ist der vorgesehene.
- **Intro-, Recap- und Ending-Sprungmarken fehlen**, weil Nori dafür keine
  Daten hat. Erfundene Zeitmarken wären schlechter als keine.
- **Untertitelspuren werden nicht getrennt angeboten**; „GerSub" ist bei beiden
  Quellen eine eigene Tonspur, keine Textspur.
- **Keine Downloads.** Nori lädt nichts herunter, auf keiner Plattform.
- **Nicht auf einem echten LG-Fernseher geprüft.** Ob webOS eine bestimmte
  Playlist nativ abspielt oder hls.js übernehmen muss, entscheidet sich erst
  dort — der Player fragt zur Laufzeit `canPlayType` und wählt danach. Ebenso
  offen: das Verhalten der Magic Remote, die Systemtastatur und ob die
  Abstände des Flex-Rückfalls auf einem webOS-6-Panel bis auf das Pixel denen
  eines neueren entsprechen.
