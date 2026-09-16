# Nori für LG webOS

Die TV-Fassung von Nori, Stand **2.2.1**. Eigenständige App, kein skalierter
Webauftritt: vollständig mit der Fernbedienung bedienbar, auf 1920 × 1080
ausgelegt und proportional bis 3840 × 2160 skalierend.

## Oberfläche

Seit 2.0.0 nach der Vorlage `nori-webos-design-v4.html`: sehr dunkler Grund,
Blau-Graphit-Flächen, eisblauer Akzent, links eine schmale Seitenleiste mit
der Wortmarke „Nori" und fünf auf Bildmitte zentrierten Einträgen (Start,
Katalog, Kalender, Merkliste, Mehr). Die Oberfläche davor ist vollständig
ersetzt; übernommen sind nur Daten, Provider, Player-Logik, Bibliothek,
Abgleich und TMDB-Schicht.

| Ansicht | Datei |
| --- | --- |
| Start: Hero, Weiterschauen, Neu & beliebt, Neue Episoden, Für dich, Merkliste | `src/pages/Home.tsx` |
| Katalog: Suche mit Tippfehlertoleranz, Schnellfilter, Filterdialog, 5er-Raster | `src/pages/Catalog.tsx` |
| Detail: Hero, Staffelmenü, 3er-Folgenraster, ähnliche Titel | `src/pages/Details.tsx` |
| Kalender: Heute, Woche, Monat | `src/pages/Calendar.tsx` |
| Merkliste: Übersicht, Ungesehen/Angefangen/Gesehen, Bearbeiten | `src/pages/Watchlist.tsx` |
| Mehr: Wiedergabe, Darstellung, Synchronisierung, Nori; Unterseiten Verbindung, Abgleich, Daten, Diagnose, Verlauf | `src/pages/More.tsx`, `src/pages/more/` |

### Skalierung

Alle Maße in `rem`; die Wurzelschrift ist `min(100vw / 120, 100vh / 67.5)`,
bei 1920 × 1080 also 16 px, bei 3840 × 2160 32 px. 4K zeigt dasselbe Layout
doppelt so scharf — fünf große Poster je Zeile, nicht zehn kleine. Bildgrößen
wählt `src/services/images.ts` nach gezeichneter Breite mal Pixelverhältnis:
Poster `w342` bei 1080p und `w780` bei 4K, das Hero-Breitbild `w1280` bzw.
`original`.

### Navigation

`src/navigation/engine.ts` ersetzt Enact Spotlight. Links/Rechts bleiben in
der Zeile; Hoch/Runter nehmen zuerst die nächste Zeile und darin das
waagerecht nächste Element. Gemessen wird gegen das **Ziel** laufender
Scrollbewegungen, damit schnelle Tastendrücke nicht springen. Sichtbar
gemacht wird ohne `scrollIntoView`: Reihen bewegen sich nur so weit, dass die
Karte samt Vergrößerung und Ring ganz dasteht; die Seite hält 3,5 rem Abstand
zum Rand und holt die Überschrift einer Reihe mit herein. Overlays sperren den
Fokus ein und geben ihn beim Schließen an ihren Auslöser zurück. Fokus und
Scrollstand werden je Ansicht gemerkt.

Die Navigation besteht aus vier Dateien:

| Datei | Aufgabe |
| --- | --- |
| `navigation/engine.ts` | Tasten, Zielwahl, Sichtbarmachen, Fokusrückholung |
| `navigation/geometry.ts` | Boxen, Erreichbarkeit, Zwischenspeicher, DOM-Beobachtung |
| `navigation/scroll.ts` | Scrollbewegungen mit bekanntem Ziel |
| `navigation/metrics.ts` | Zähler und Zeiten, sichtbar unter *Mehr → Diagnose* |

#### Wie viel ein Tastendruck anfasst

Drei Stufen, von billig nach teuer; jede kommt nur dran, wenn die vorige
nichts gefunden hat. Das Ergebnis ist dasselbe wie bei einer Suche über die
ganze Seite, der Weg dorthin ein anderer:

1. **Die Zeile entlang.** Links/Rechts laufen die Geschwister innerhalb von
   `data-nav-row` ab und hören auf, sobald eines senkrecht deutlich versetzt
   liegt — im Raster der Zeilenumbruch, in einer Reihe das Ende. Zwei bis drei
   Messungen, unabhängig von der Seitengröße.
2. **Nachbarreihen.** Hoch/Runter sehen die eigene Reihe und je zwei darüber
   und darunter an.
3. **Die ganze Seite.** Der Rückfall — Bereichswechsel, Seiten ohne Reihen,
   alles Ungewöhnliche.

`data-nav-row` steht an den Behältern, die eine Zeile bilden: `.rail-inner`,
`.catalog-grid`, `.episode-grid`, `.chips-inner`, `.top-actions`,
`.hero-actions`, `.nav-list`, `.setting-card`, `.weekstrip`, `.month-grid`,
`.release-list`, `.season-row`, `.menu-list`.

#### Geometriespeicher

Gemessene Boxen bleiben zwischen zwei Tastendrücken gültig. Gespeichert wird
nicht die Position auf dem Bildschirm, sondern die im Inhalt — Bildschirmmitte
plus Scrollstand aller Scrollbereiche darüber. Die ist gegen Scrollen
unempfindlich; zurückgerechnet wird gegen das **Ziel** laufender Bewegungen,
nicht gegen deren Zwischenstand.

Verworfen wird bei jeder DOM-Änderung, die etwas verschieben kann — das
Verwerfen selbst erhöht nur eine Zahl, gemessen wird erst wieder auf Nachfrage.
Ausgenommen ist genau eine Sorte Änderung, und die ist im Markup angeschrieben:
alles unterhalb von `data-nav-quiet`. Das sind die Bildflächen (`.card-art`,
`.ep-thumb`, `.hero-media`). Ihre Größe steht im Stylesheet; ein eintreffendes
Bild, ein verschwindender Platzhalter, ein wachsender Fortschrittsbalken
verschiebt dort nichts. **Nicht** ausgenommen ist eine Unterzeile, die nach
einem TMDB-Treffer unter einer Kachel erscheint — die ändert die Kartenhöhe.

Auch der Scrollstand selbst wird gemerkt: `scrollTop` und `scrollLeft` sind
Layoutabfragen, und geschrieben wird bei jedem Tastendruck. Gelesen werden sie
nur noch beim ersten Mal und im `scroll`-Ereignis, wo das Layout ohnehin fertig
ist.

Gemessen auf der Startseite mit fünf Reihen, CPU sechsfach gedrosselt:

| | vorher | nachher |
| --- | ---: | ---: |
| Layoutabfragen je Tastendruck | 299 | 18 |
| `getComputedStyle` je Tastendruck | 86 | 6 |
| Zielsuche (Median) | — | 0,9 ms |

#### Wiederholrate

Eine gehaltene Taste liefert Wiederholungen schneller, als eine Bewegung
sichtbar wird. Die Sperre dazwischen richtet sich nach der **gemessenen** Dauer
der letzten Schritte (70 bis 180 ms) statt nach einer festen Zahl: mehr
Wiederholungen, als das Panel zeichnen kann, sind keine schnellere Bedienung,
sondern eine längere Warteschlange.

Die Scrollverankerung des Browsers ist in diesen Bereichen abgeschaltet
(`overflow-anchor: none` an `data-scroll-y` und `data-scroll-x`). Sortiert sich
ein Raster um — im Katalog, sobald TMDB-Treffer eintreffen —, verschob Chromium
sonst selbst die Seite um eine Zeile, ohne dass die Navigation davon erfuhr, und
die fokussierte Karte stand halb unter dem Bildrand. Verschiebt eine solche
Änderung das fokussierte Element selbst, holt die Navigation es im nächsten Frame
zurück ins Bild.

### Reihenfolge im Katalog

Eine Katalogansicht — Bereich, Schnellfilter, Sortierung, Jahrzehnt, Suche —
bekommt beim Aufbau eine geordnete Liste stabiler Kennungen (`provider|slug`).
TMDB-Angaben, die danach eintreffen, aktualisieren Cover, Untertitel und
Bewertung, aber nicht die Reihenfolge: Beliebtheit, Trendplatz und Bewertung
kommen erst mit TMDB, und früher sortierte jeder gebündelte Treffer das Raster
unter der Fernbedienung neu. Später geladene Titel kommen hinten dazu; eine neue
Dubletten-Vertreterin ersetzt keine sichtbare Karte. Neu sortiert wird bei einer
anderen Ansicht und beim erneuten Öffnen über die Seitenleiste. Beim Zurückkehren
von einer Detailseite bleibt die Ansicht, damit der gemerkte Fokus dieselbe Karte
an derselben Stelle trifft. Die Regel steht als reine Funktion im Kern
(`shared/nori-core/src/catalog-order.ts`).

### Artwork: welche Auflösung wohin

`src/services/images.ts` entscheidet, welche TMDB-Stufe eine Stelle bekommt.
Gerechnet wird die gezeichnete CSS-Breite mal einem Pixelverhältnis — und
dieses Verhältnis ist **nicht** einfach `devicePixelRatio`.

Ein webOS-Paket mit `"resolution": "1920x1080"` zeichnet in 1920 × 1080
Bildpunkten; den Rest erledigt der Skalierer des Panels. Viele 4K-Geräte melden
trotzdem `devicePixelRatio === 2`, weil sie das Panel beschreiben und nicht die
Fläche, auf der die App zeichnet. Wer das für bare Münze nimmt, lädt Bilder in
der vierfachen Fläche, ohne dass ein Pixel davon sichtbar würde.

Deshalb gilt: **ein Bild braucht nie mehr Bildpunkte, als die Zeichenfläche der
App hat.** Die Fläche steht in `appinfo.json` und kommt über
`__NORI_WEBOS_RESOLUTION__` in den Build — eine Quelle, keine zweite Zahl im
Quelltext. Im Browser, wo es kein `appinfo.json` gibt, bleibt das echte
Pixelverhältnis maßgeblich; dort ist es die Wahrheit.

Auf einem 4K-Fernseher mit 1080p-Zeichenfläche:

| Stelle | vorher | nachher |
| --- | --- | --- |
| Poster | `w780` | `w342` |
| Breitbild einer Karte | `w1280` | `w780` |
| Kopfbild | `original` | `w1280` |
| Schriftzug | `original` | `w500` |

Auf einer echten 4K-Zeichenfläche (3840 CSS-Pixel breit) bleibt es bei `w780`
und `original` — dort werden die Pixel auch gezeichnet.

### Artwork: wie viele gleichzeitig

Ein `<img src>` im DOM ist kein Wunsch, sondern ein Auftrag. Auf der Startseite
standen bis zu achtzig davon gleichzeitig im Baum. `loading="lazy"` löst das
nicht: Chromium setzt den Vorlauf nach der gemessenen Verbindung, und auf einem
Fernseher ist die Verbindung selten der Engpass — die CPU ist es.

`src/services/artworkQueue.ts` lässt drei bis vier Abrufe gleichzeitig zu, in
dieser Rangfolge:

```text
0  Kopfbereich und die gerade fokussierte Kachel
1  Karten der ersten Reihe (eager)
2  alles andere, sobald es in Sichtweite kommt
```

Angemeldet wird erst beim Eintritt in den Sichtbereich — von oben nach unten
und von links nach rechts also genau in der Reihenfolge, in der jemand
hinsieht. Ein Platz wird frei, wenn das Bild geladen ist, gescheitert ist oder
die Kachel verschwindet; eine Frist von acht Sekunden verhindert, dass ein
totes Bild die Seite blockiert. `Artwork` trennt dabei zwei Dinge, die vorher
eines waren: **nachfragen** (TMDB nach diesem Titel) passiert in Sichtweite,
**laden** (`src` setzen) erst, wenn ein Platz frei ist.

Die Rangfolge der Startseite hängt nicht mehr daran: welche Titel bei TMDB
nachgeschlagen werden, entscheidet `state/home.ts` für die ersten zwölf jeder
Reihe, in Leerlaufpausen und höchstens einmal je Titel und Sitzung. Vorher war
das ein Nebeneffekt des Bildladens.

### Weniger auf einmal zeichnen

Sichtbar ist bei 1080p der Kopfbereich und eine Reihe. Deshalb (`hooks/useProgressive.ts`):

- **Reihen** kommen in Schritten: die ersten sofort, der Rest in
  Leerlaufpausen. Während die Fernbedienung arbeitet, ruht das Nachziehen.
- **Karten** einer Reihe stehen zunächst zu zehn (acht im sparsamen Modus);
  erreicht der Fokus die letzten drei, kommen weitere dazu — im nächsten Bild,
  nicht im Tastendruck. Die erreichte Breite bleibt je Reihe gemerkt, damit das
  Fokusgedächtnis beim Zurückkehren dieselbe Karte findet.

`content-visibility: auto` steht bewusst **nicht** im Stylesheet: übersprungene
Teilbäume liefern keine Geometrie mehr, und die Fernbedienungsnavigation lebt
von Geometrie. Stattdessen trägt jede Reihe `contain: layout style` — der
Browser rechnet beim erzwungenen Layout nach einem Tastendruck nur die Reihe
durch statt der ganzen Seite. Ohne `paint`, denn die fokussierte Karte wächst
über ihre Reihe hinaus.

### Leistungsmodus

*Mehr → Darstellung → Leistung* mit drei Stufen: **Automatisch** (Voreinstellung),
**Normal**, **Optimiert**. Getrennt von „Animationen reduzieren": das eine ist
eine Frage der Hardware, das andere eine des Geschmacks.

„Automatisch" entscheidet an drei Signalen, keines davon eine Modellnummer
(`src/services/performance.ts`):

1. Ein kurzer Rechenlauf, einmal je Gerät, **nach** dem ersten Bild; das
   Ergebnis liegt danach im `localStorage`.
2. Was das Gerät über sich sagt (`hardwareConcurrency`, `deviceMemory`) — ein
   Hinweis, nie allein ausschlaggebend.
3. Die gemessene Fokuslatenz. Bleibt die Navigation über viele Tastendrücke
   zäh, wechselt der Modus auch dann, wenn die ersten beiden unauffällig waren.
   Das ist das ehrlichste Signal, weil es genau das misst, worum es geht.

„Optimiert" ändert nichts an den Funktionen und wenig am Aussehen: Farben,
Abstände, Schriftgrößen, Postergrößen, Kopfbereich und die Art, wie der Fokus
aussieht, bleiben. Zurückgenommen wird die dritte, weiche Schattenebene des
Fokusrings, ein Hauch Wachstum (1,05 statt 1,07), der wandernde Schimmer der
Ladeflächen, der zweite Farbverlauf des Hintergrunds; dazu zwei statt vier
gleichzeitige Bildabrufe, ein kleinerer Vorlauf und kleinere Schritte beim
Aufbau.

Die Maße des Fokus stehen dabei **nur** in `theme.css`
(`--focus-scale-card`, `--focus-scale-control`, `--focus-ring-rem`); die
Scrollrechnung liest sie zur Laufzeit von dort. Zwei Zahlen, die gleich bleiben
müssen, laufen sonst auseinander.

### Der Referenzfernseher

Als Low-/Mid-End-Referenz gilt der **LG 55UA75006LA**: 4K-Panel, schwache CPU,
webOS mit 1080p-Zeichenfläche. Er ist Maßstab, nicht Sonderfall — im Quelltext
steht seine Modellnummer nirgends, und alles, was für ihn getan wurde, gilt für
jedes Gerät, das sich genauso misst.

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
*Mehr → Verbindung & TMDB → Bildspeicher leeren*.

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
npm run webos:package  # ergibt tv.nori.app_2.2.1_all.ipk
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

Zu erhöhen sind `apps/webos/appinfo.json`, `apps/webos/package.json`,
`shared/nori-core/package.json`, `services/nori-api/package.json` und
`API_VERSION` in `services/nori-api/src/server.ts`; dazu gehört ein Abschnitt
`## [webOS x.y.z]` im `CHANGELOG.md` und die Zeile in seiner Übersicht. Die
Oberfläche zeigt die Nummer unter Mehr → Nori; sie wird beim Bauen aus
`appinfo.json` gelesen. `python3 tools/check-webos-package.py` vergleicht alle vier
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

5. **Nori einrichten**: beim ersten Start unter *Mehr → Verbindung & TMDB*
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
es erst, wenn unter *Mehr → Diagnoseprotokoll* eingeschaltet ist —
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
| Zurück (461 / 10009) | Dialog/Menü zu → Drawer zu → Bedienung zu → Player verlassen → Ansicht zurück → Hauptseite zur Startseite → auf der Startseite App verlassen |
| Play (415) / Pause (19) / Stop (413) | Wiedergabe steuern |
| Vor-/Zurückspulen (417 / 412) | springen, bei gehaltener Taste schneller |

Am Rechner ersetzen Escape die Zurück-Taste und die Leertaste Wiedergabe/Pause.

Der erste Fokus liegt im Inhalt, nicht in der Seitenleiste: auf der
Startseite „Jetzt ansehen", im Katalog die erste Karte, auf der Detailseite
„Jetzt ansehen", im Kalender der heutige Tag, in Mehr die erste Einstellung.
Die Seitenleiste erreicht man mit „links" am Zeilenanfang und landet dort auf
dem aktiven Eintrag; „rechts" führt zurück auf die zuletzt fokussierte Karte.

## Unterstützte Stände

Gebaut wird auf **Chrome 79** — die Engine von webOS 6. Damit läuft dieselbe
Datei auf webOS 6 bis 26; neuere Sprachmerkmale werden übersetzt, `?.` und `??`
eingeschlossen. `aspect-ratio` bekommt über `@supports` einen Rückfall,
`CSS.escape` und `AbortSignal.any` werden nicht benutzt.

### CSS für webOS 6

Chrome 79 kennt `gap` **nur im Raster**, nicht im Flex-Layout (erst ab 84),
dazu fehlen `aspect-ratio` (88) und `inset` (87). Die Oberfläche benutzt
deshalb keines davon: Abstände zwischen Geschwistern entstehen über Raster
(`grid-auto-flow: column`) oder Ränder, Seitenverhältnisse über `padding-top`,
Flächen über `top/right/bottom/left`.

`tools/check-webos-package.py` beanstandet `inset` und `aspect-ratio` in den
Stylesheets; der Fernbedienungslauf prüft im Browser, dass kein
Flex-Container ein `gap` trägt. `supportsFlexGap` misst weiterhin beim Start
und schreibt `data-flex-gap` ins Protokoll.

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

**hls.js ist nicht Teil des Bündels** (seit 2.2.0). Es war mit Abstand dessen
größter Teil, gebraucht wird es aber nur für HLS-Streams auf Geräten ohne
natives HLS — webOS spielt HLS in aller Regel selbst ab. `vite.config.ts` legt
die UMD-Fassung aus `node_modules` als `dist/vendor/hls.min.js` daneben (für
Chrome 79 übersetzt), und `src/player/hlsLoader.ts` lädt sie im Player als
**klassisches** Skript nach. Das funktioniert von `file://`, anders als ein
dynamisches `import()`. Das Startbündel sank damit von 1 001 KB auf 410 KB.
`check-webos-package.py` verlangt die Datei im `.ipk`, und der
Fernbedienungslauf lädt sie über `file://` nach und prüft `Hls.isSupported()`.

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

Das Artefakt `Nori-webOS` ist seit 2.2.1 das **installierbare Paket mit
Google-Abgleich**. Der Fernbedienungslauf läuft gegen einen Build mit leeren
TV-Variablen; danach schreibt `tools/configure-google-oauth.py --webos` die
`.env.local` aus `~/.config/nori/secrets/google-webos-oauth.json` auf dem
Runner, der produktive Build wird gepackt und mit
`check-webos-package.py --production --reference-dist …` im fertigen `.ipk`
geprüft. Einzelheiten: `docs/google-drive-sync.md`, Abschnitt zur
Build-Konfiguration für webOS. Lokal ändert sich nichts — ohne `.env.local`
entsteht ein Paket ohne Google-Abgleich, und die Prüfung ohne `--production`
nimmt es an.

Die Oberfläche lässt sich mit einer nachgebauten Fernbedienung durchspielen:

```bash
cd apps/webos
npm run build
npm run mock &                          # Nori-Server und TMDB mit festen Daten
npm i --no-save playwright && npx playwright install chromium
npm run test:tv
```

Der Lauf drückt echte LG-Tastencodes — geklickt wird nur, um einen Zustand
herzustellen — und prüft auf jeder Hauptansicht die Matrix →×10 ←×10 ↓×10
↑×10 plus eine gemischte Folge. Nach **jedem** Druck: es gibt einen Fokus;
das Element liegt samt Vergrößerung und Ring im Bild, in seiner Reihe, in
seinem Scrollbereich und nicht unter der Seitenleiste; es liegt nicht hinter
einem offenen Overlay; seine Schrift hat mindestens 4,5 : 1 Kontrast.

Dazu: Rand der Reihen (erste Karte ←, letzte Karte →), schnelle Eingabe im
25-ms-Takt, Hero → erste Reihe mit sichtbarer Überschrift, das alte
Startseiten-Clipping (↓×8, ↑×8), Zurück mit Fokus- und Scrollwiederherstellung
auf Start, Katalog, Detail und Kalender, Dialog- und Menü-Zurück, Kontrast des
Merkliste-Knopfs normal und im Fokus, Überlappungen, Flex-`gap`,
Mindestschriftgröße, abgeschnittene Titel, Bildgrößen je Auflösung, Player,
TMDB-Zuordnung und -Ausfall, Katalogausfall, frische Installation und der
Aufbau über `file://`. Die Ansichten werden getrennt bei **1920 × 1080** und
**3840 × 2160** geprüft.

Die Bildschirmfotos landen in `apps/webos/test-shots/` (nicht im Repository),
`NORI_SHOTS=<Ordner>` legt sie woanders ab.

### Leistung messen

`test/perf-bench.mjs` beantwortet nicht „stimmt es", sondern „was kostet es".
Er läuft mit gedrosselter CPU, kaltem Bildspeicher und großem Katalog und
zählt im Browser selbst — `getBoundingClientRect`, `getComputedStyle`,
`offsetWidth`/`offsetHeight`, `scrollWidth`/`scrollHeight` werden vor jedem
Skript der Seite ersetzt. Ein Tastendruck ist damit nicht mehr „fühlt sich träge
an", sondern „283 Layoutabfragen".

```bash
cd apps/webos
npm run build
NORI_MOCK_TITLES=400 NORI_MOCK_SYNTH_TMDB=1 node test/mock-server.mjs &
node test/perf-bench.mjs --label vorher  --out test-perf/vorher.json
# … Änderungen, neu bauen …
node test/perf-bench.mjs --label nachher --out test-perf/nachher.json
node test/perf-bench.mjs --compare test-perf/vorher.json test-perf/nachher.json
```

`NORI_MOCK_TITLES` stellt einen großen Katalog her, `NORI_MOCK_SYNTH_TMDB=1`
lässt den TMDB-Nachbau zu jedem Titel eine Antwort erfinden — sonst hat die
Startseite zwei Reihen statt sieben. Beides ist **aus**, wenn nichts gesetzt
ist; der Fernbedienungslauf prüft ausdrücklich den Fall „Titel ohne
TMDB-Eintrag", und der verschwände sonst.

`--throttle` setzt die Drosselung (Vorgabe 6×), `--perf lean` misst den
sparsamen Modus, `--keys` die Zahl der Tastendrücke.

Was der Lauf **nicht** kann: Farbauftrag und Zusammensetzung messen. Headless
Chromium zeichnet nicht auf ein Panel; was der sparsame Modus an Schatten und
Animation spart, zeigt sich dort nicht. Gemessen wird, was auf dem Hauptthread
passiert — und das ist auf einem Fernseher der Engpass.

Zur Laufzeit stehen dieselben Zahlen unter *Mehr → Diagnose* im Abschnitt
**Leistung**: Modus und Begründung, mittlere und schlechteste Fokuslatenz,
Zahl der Messungen gegenüber den Treffern im Zwischenspeicher, die gewählten
TMDB-Stufen und der Stand der Bildwarteschlange. Im Quelltext hängen sie an
`window.__noriNav` und `window.__noriArtwork()` — reine Zahlenobjekte, kein
Steuerpult.

Der Nachbau unter `test/mock-tmdb.mjs` enthält absichtlich die drei Fälle, die
in der Praxis schiefgehen: ein Titel, dessen TMDB-Name mit dem Quelltitel
nichts gemeinsam hat; eine Staffel mit versetzter Folgenzählung; ein Titel, den
TMDB gar nicht führt.

## Mit Google Drive verbinden

*Mehr → Synchronisierung → „Mit Google Drive verbinden"*. Danach ein
eigener Bildschirm, kein Absatz in der Liste:

```
┌──────────────────────────────────────────────────────┐
│  Google Drive verbinden                              │
│                                                      │
│  ███████████    Scanne den QR-Code mit deinem        │
│  ██ ▄▄▄▄▄ ██    Smartphone.                          │
│  ██ █████ ██                                         │
│  ███████████    Oder öffne am Telefon                │
│                 www.google.com/device                │
│                 und gib diesen Code ein              │
│                 WDXR-KQPF                            │
│                                                      │
│  Nori wartet auf deine Anmeldung …                   │
│  Der Code gilt noch 14:32 Minuten.                   │
│                                                      │
│  [ Abbrechen ]                                       │
└──────────────────────────────────────────────────────┘
```

Der QR-Code ist 22 rem im Quadrat — 328 px auf 1080p, 431 px auf einem
4K-Panel — mit weissem Grund und dem von der Norm verlangten Rand von vier
Modulen. `shape-rendering="crispEdges"` ist dabei nicht Kosmetik: ohne das
glättet der Browser die Kanten, und bei einem Modul von wenigen Bildpunkten
verschwimmen hell und dunkel ineinander. Der Gerätecode steht in 4 rem
(64 px auf 1080p), mit Sperrsatz und Tabellenziffern — er wird abgetippt.

Gerechnet wird der Code **im Gerät** (`shared/nori-core/src/qr.ts`), nie bei
einem Dienst im Netz: die Adresse gehört zu einer laufenden Anmeldung. Enthalten
ist `verification_uri_complete`, wenn Google eine liefert — dann steckt der Code
schon darin —, sonst genau `verification_uri`. Selbst zusammengesetzt wird
nichts.

Der Dialog sperrt den Fokus ein (`restrict="self-only"`), „Zurück" bricht ab und
gibt den Fokus an die Abgleich-Reihe zurück. Läuft der Code ab, steht dort ein
Satz und ein Knopf für einen neuen; der Fokus wandert dabei auf diesen Knopf,
weil „Abbrechen" der eine ist, der nicht weiterhilft.

### Was der Fernseher liest

Der Fernseher fragt ausschliesslich nach `drive.file` und liest den sichtbaren
TV-Spiegel im Ordner „Nori" — nie den versteckten `appDataFolder`. Googles
Gerätefluss lehnt `drive.appdata` reproduzierbar mit `invalid_scope` ab, auch
für weitere TV-Clients und in einem zweiten Projekt
(`docs/google-drive-sync.md`, Abschnitt 10).

Die Daten von iPhone, iPad und Mac kommen deshalb über ein Apple-Gerät, auf dem
unter *Synchronisation* „Mit Fernseher teilen" eingeschaltet ist. Liegt im
Spiegel noch keines, steht auf der Abgleich-Seite:

> Noch keine TV-Synchronisation gefunden – Aktiviere auf deinem iPhone, iPad
> oder Mac in Nori unter Synchronisation „Mit Fernseher teilen".

Der Fernseher schreibt nur seine eigene Datei `nori-tv-sync-v1-<deviceId>.json`
und liest alle anderen Spiegeldateien. Gefunden werden sie über
`appProperties`, auch wenn jemand sie umbenennt oder verschiebt. Fehlt
`drive.file` — bei der Zustimmung abgewählt oder später entzogen —, zeigt die
Seite „Anmeldung nötig" und den Knopf zum erneuten Verbinden. Merkposten einer
früheren Fassung für den `appDataFolder` räumt die App beim Start weg.

**webOS 6 (Chrome 79).** Der Spiegel braucht keine neuere Browser-API. Den
geschriebenen Stand vergleicht Nori über SHA-256, selbst gerechnet
(`shared/nori-core/src/hash.ts`): `crypto.subtle` hat eine `file://`-App nicht
verlässlich, und für Umgebungen ohne `TextEncoder` gibt es einen Rückfall. Auf
einem echten Fernseher ist das nicht geprüft.

**Eingerichtet wird am Fernseher nichts.** Client-ID und Client-Secret kommen
aus dem Build (`VITE_NORI_GOOGLE_TV_CLIENT_ID`,
`VITE_NORI_GOOGLE_TV_CLIENT_SECRET`, am besten über eine nicht eingecheckte
`apps/webos/.env.local`). Die Eingabefelder, die dafür bis 1.3.1 in den
Einstellungen standen, sind weg: ein 40-stelliges Secret mit der Fernbedienung
über eine Bildschirmtastatur einzugeben war keine Einrichtung, sondern eine
Hürde. Am Entwicklerschalter *Diagnoseprotokoll* hängt eine Zeile mit Client-ID,
Herkunft und der Auskunft, **ob** ein Secret vorliegt — nie welches.

Durchspielen lässt sich das alles ohne Google-Konto: der Fernbedienungslauf
fängt Googles Endpunkte ab (`npm run test:tv`, Bildschirmfotos in
`test-shots/22b…22d`).

## Bekannte Einschränkungen

- **Der Abgleich über Google Drive ist nicht auf einem Fernseher geprüft.** Er
  ist gebaut, die Zusammenführungsregel ist in beiden Kernen gegen dieselben
  Fälle geprüft (`config/sync-fixtures.json`), und der Weg über den TV-Spiegel
  wurde im webOS-TV-Simulator mit einem echten Google-Konto gegen iPhone und
  Mac durchgespielt. Auf LG-Hardware ist er es nicht. Siehe
  `docs/google-drive-sync.md`.
- **Der Fernseher bekommt Änderungen nur über ein Apple-Gerät mit „Mit
  Fernseher teilen".** Ist auf keinem eingeschaltet oder wird keines mehr
  geöffnet, bleibt der Stand am Fernseher beim letzten Abgleich stehen.
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
