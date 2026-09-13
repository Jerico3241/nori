# Changelog

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
Versionierung nach [Semantic Versioning](https://semver.org/lang/de/).

Die Plattformen laufen auf eigenen Versionsständen, weil sie sich
unterschiedlich schnell bewegen: macOS **1.19.0**, iOS/iPadOS **1.24.0**,
Windows **1.8.0**, LG webOS **2.2.0**.

## [iOS 1.24.0] · [macOS 1.19.0] · [webOS 2.2.0] — 2026-09-13

Qualitätsdurchgang über alle drei gepflegten Apps: weniger Rechenarbeit,
weniger Schreibzugriffe, früher sichtbare Oberfläche, ruhigere Ladezustände.
Keine neuen Funktionen, keine Änderung an Google Drive, OAuth, Merge-Regeln,
`drive.appdata`, `drive.file` oder am Bibliotheksschema (weiter v6).

### Behoben — webOS

- **Der Player rechnete während der Wiedergabe ununterbrochen.** Die
  Aufräumfunktion „beim Verlassen sichern" hing an `saveProgress` und damit an
  der Bibliothek. Jede Sicherung erzeugte eine neue Bibliothek, damit ein neues
  `saveProgress`, damit einen Aufräumlauf, der wieder sicherte — eine
  Endlosschleife aus Sichern und Rendern. Gemessen (Chromium, CPU ×4
  gedrosselt): 20 s Wiedergabe kosteten 19,7 s Skriptzeit und 210 645
  React-Commits. Nebenwirkung: das gebündelte Schreiben in den `localStorage`
  wurde bei jedem Durchlauf neu verschoben und fand während der Wiedergabe nie
  statt. Jetzt hängen Videoereignisse, Zeitgeber und das Sichern beim Verlassen
  einmal am Element und lesen den aktuellen Stand über eine Referenz: 5 ms
  Skriptzeit und 4 Commits in 20 s.
- **Der letzte Stand beim Verlassen ging verloren.** Das Videoelement war beim
  Aufräumen schon abgebaut (Position 0). Die Stelle wird jetzt ohne Rendern
  mitgeschrieben und beim Verlassen, bei Pause, beim Folgenwechsel und am
  Folgenende sofort abgelegt.
- **Die Zeitleiste zeichnete den ganzen Player viermal pro Sekunde neu**, auch
  bei ausgeblendeter Bedienung. Sie zieht jetzt nur mit, solange die Bedienung
  sichtbar ist, und steht beim Einblenden im selben Bild richtig.
- **„Mehr" zeichnete alle drei Sekunden neu**, nur um den TMDB-Zustand zu lesen.
  Jetzt meldet `tmdb` Zustandswechsel (`subscribeStatus`), die Seite zeichnet nur
  dann. „Zuletzt vor 3 Minuten" bleibt über einen halbminütigen Takt richtig,
  auch auf „Abgleich".
- **Derselbe Wert als Einstellung** (`setPreference`) bekam eine frische Marke
  und stieß Schreiben und Abgleich an. Jetzt nur bei einer echten Änderung.

### Verbessert — webOS

- **hls.js wird erst im Player geladen.** Es lag im Startbündel und war mit
  Abstand dessen größter Teil. Jetzt liegt es als eigene Datei im Paket
  (`vendor/hls.min.js`, beim Bau für Chrome 79 übersetzt) und wird als
  klassisches Skript nachgeladen — ES-Module laden von `file://` nicht. Ein
  Fernseher mit nativem HLS lädt es nie. Hauptbündel 1 001 KB → 410 KB
  (gzip 317 → 133 KB).
- **Start** (Chromium, CPU ×4): Dokument geladen 233 → 63 ms, App-Hülle
  264 → 82 ms, erster Inhalt 352 → 155 ms, Skriptzeit bis zur fertigen
  Startseite 269 → 123 ms.
- **Bibliothek:** Änderungen stehen sofort im Zustand; geschrieben wird nach
  höchstens 400 ms, Fortschritt der Wiedergabe höchstens alle 10 s, und sofort
  bei `visibilitychange`/`pagehide`, Pause, Folgenende und beim Verlassen des
  Players. Ein unveränderter Stand wird nicht erneut geschrieben.
- **Fokus-Netz:** Der Watchdog lief alle 600 ms, auch im Hintergrund. Gemessen
  kostete er kaum Rechenzeit (≈ 1 ms in 20 s Leerlauf), weckte das Gerät aber
  hundertmal pro Minute. Jetzt alle 2 s, nicht bei verborgener App, dazu sofort
  beim Zurückkehren in den Vordergrund. Zurückgeholt wird weiter
  ereignisgesteuert (`focusout`, MutationObserver, Tastendruck).
- **Magic Remote:** Verschwindet der Zeiger (`cursorStateChange`), gilt wieder
  der Tastenmodus — der Fokus steht sichtbar auf dem zuletzt gezeigten Element.
- Die nicht mehr benutzte Enact-`.less`-Umleitung ist aus `vite.config.ts`
  entfernt.

### Behoben — iOS/iPadOS und macOS

- **Anzahl statt Revision.** Startseite („Weiterschauen"), Merkliste, Katalog,
  Kalender und Kategorien erkannten Änderungen an `catalog.count`,
  `favorites.count` oder `progress.count`. Ein getauschter Merklisteneintrag,
  eine zu Ende gesehene Folge oder ein Katalog mit derselben Zahl anderer Titel
  blieben unbemerkt. `LibraryStore` führt jetzt `favoritesRevision`,
  `recentsRevision`, `progressRevision` (jeder Takt) und `watchRevision`
  (abgeschlossene Änderungen); die Wurzelansichten zählen eine
  `catalogRevision` hoch, wenn sich der **Inhalt** ändert. Eine Aktualisierung
  mit identischem Ergebnis rechnet nichts neu.
- **Die Startseite zeichnete hinter dem Player alle fünf Sekunden neu** (iOS)
  bzw. im Hauptfenster neben dem Player (macOS), weil sie den Fortschritt in
  `body` las. Jetzt hängt sie an `watchRevision`.
- **Jede Sicherung der Wiedergabe schrieb die ganze Bibliothek auf die Platte.**
  Takte derselben Folge werden gebündelt (höchstens alle 10 s) und sofort
  geschrieben bei Pause, Ende der Wiedergabe, Hintergrund und Programmende.
  Neue Folgen, abgeschlossene Folgen, Merkliste und Einstellungen werden weiter
  sofort geschrieben. „Staffel als gesehen markieren" schreibt einmal statt je
  Folge (`upsert(contentsOf:)`).
- **Derselbe Einstellungswert war eine Änderung.** Der Player setzt Hoster und
  Sprache bei jedem Start; jede Wiedergabe schrieb damit zweimal und stieß einen
  Upload an, und die frische Marke konnte die bewusste Wahl eines anderen Geräts
  überschreiben.
- **Die Merkliste des Macs** suchte je Eintrag den Titel im ganzen Katalog, und
  das Öffnen eines Titels stellte die Vorgabequelle der ganzen Bibliothek um
  (mit Zeitstempel und Abgleich). Beides entfällt.

### Verbessert — iOS/iPadOS

- **Der Player** zeichnet beim Fortschreiten der Wiedergabe nur noch den Regler
  neu (`PlaybackClock`), und bei ausgeblendeter Bedienung gar nichts.
- **Stabile Reihenfolge im Katalog** (`CatalogStableOrder`, dieselbe Regel wie
  `stableCatalogOrder` auf dem Fernseher): der zweite Durchgang mit frischen
  TMDB-Daten aktualisiert Kacheln, sortiert sie aber nicht um, während jemand
  scrollt. Neu sortiert wird bei einer anderen Abfrage und beim Aktualisieren.
  Das Nachladen des Rasters beginnt nur bei einer neuen Abfrage von vorn, nicht
  mehr, wenn TMDB die Trefferzahl ändert.
- **Ladegerüste mit den echten Maßen:** Die Kacheln im Startseiten-Gerüst waren
  60 Punkte zu niedrig, die im Katalog-Gerüst hatten feste Balken statt echter
  Textzeilen — beim Eintreffen der Daten sprang das Layout. Kalender und
  Detailseite zeigen ein Gerüst statt eines Rädchens; die Detailseite nennt dabei
  schon den Titel. Gerüste sind für VoiceOver ein einziger Satz.
- **Katalog laden:** Sortieren und Zuschneiden von zehntausend Titeln liefen beim
  Start und bei jedem Bereichswechsel auf dem Hauptthread; jetzt daneben.

### Verbessert — macOS

- **Katalog wie auf iOS gebaut:** vorbereiteter Index (`CatalogItemIndex` im
  Kern, dieselbe Normalisierung wie die iPhone-Suche), entprellte Suche abseits
  des Hauptthreads. Vorher lief `lowercased().contains` über den ganzen Katalog
  bei jedem Neuzeichnen — dreimal je Durchlauf —, und „pokemon" fand „Pokémon"
  nicht.
- **Ladegerüste** für Startseite, Katalog, Kategorien, Kalender und Detailseite
  statt `ProgressView` im leeren Fenster; Toolbar und Suche stehen sofort.
- Kategorien, Startseitenreihen und „Ähnliche Titel" werden je Katalogstand
  einmal abseits des Hauptthreads gerechnet statt in `body`.

### Verbessert — Bilder (iOS und macOS)

- **Plattenspeicher für Cover** (`NoriImages`, 256 MB): nach einem Neustart und
  ohne Netz sind geladene Cover sofort da. Vorher lag nichts auf der Platte.
- **Ein Abruf je Adresse:** dasselbe Cover in mehreren Kacheln wird einmal
  geladen; der Abruf bricht erst ab, wenn keine Kachel mehr wartet.
- **Entschlüsselt abseits des Hauptthreads** und verkleinert auf höchstens
  1600 Pixel, mit einem Speicher für fertige Bilder. Vorher entstand das Bild
  auf dem Hauptthread und wurde erst beim Zeichnen entpackt — beim Scrollen.

### Geprüft

- Swift-Kern: **479/479** (vorher 452; neu: Revisionen und gebündeltes Schreiben
  10, Katalogindex 5, stabile Reihenfolge 8, Bildentschlüsselung 4).
- TypeScript-Kern **221/221**, nori-api **13/13**.
- Fernbedienungstest **310/310** (1080p, 4K, `file://`; neu 5): Start ohne
  hls.js, Startbündel unter 600 KB, Wiedergabe ohne Dauerrechnen (gemessen
  9 ms Skriptzeit in 3 s), Pause legt den Stand sofort ab, hls.js lässt sich
  von `file://` nachladen. Lokal ohne Google-Zugangsdaten im Build gebaut, wie
  in der CI.
- `check-webos-package.py` OK — 2.2.0 überall, `vendor/hls.min.js` im `.ipk`.
- `xcodebuild` iOS-Simulator und macOS: Build erfolgreich.
  `check-apple-sources.py`: keine Auffälligkeiten.
- Nicht auf LG-Hardware, nicht auf einem physischen iPhone/iPad geprüft.

## [webOS 2.1.1] — 2026-09-13

Katalog: Die Reihenfolge einer Ansicht bleibt stehen, während TMDB-Angaben
nachkommen.

### Behoben

- **Das Katalograster sortierte sich während der Navigation um.** Sichtbar
  werdende Karten holen ihre TMDB-Angaben (`covers.ensure` → `tmdb.ensureArt`),
  auch Ranglisten melden sich nachträglich. `useCatalogView` bündelte jede
  Meldung nach 1,5 s zu einem neuen Durchlauf von `dedupeCatalog` und
  `buildCandidates`, und `Catalog.tsx` sortierte das Ergebnis jedes Mal neu.
  Beliebtheit, Trendplatz, Bewertung und Stimmen kamen aber erst mit TMDB:
  Karten wechselten die Stelle, TMDB-abhängige Filter änderten die
  Zugehörigkeit, und die Dublettenregel tauschte eine sichtbare Karte gegen die
  Fassung der anderen Quelle. Der fokussierte Titel wechselte dabei die Stelle
  oder wurde durch einen anderen ersetzt.
- **Anreicherung und Reihenfolge sind getrennt.** Eine Ansicht — Bereich,
  Schnellfilter, Sortierung, Jahrzehnt, Suche — bekommt beim Aufbau eine
  geordnete Liste stabiler Kennungen (`provider|slug`, `stableCatalogOrder` im
  Kern). TMDB aktualisiert danach nur noch Cover, Untertitel und Bewertung
  dahinter. Später geladene Titel kommen hinten dazu; eine neue
  Dubletten-Vertreterin ersetzt keine sichtbare Karte. Neu sortiert wird bei
  einer anderen Ansicht und beim erneuten Öffnen über die Seitenleiste — beim
  Zurückkehren von einer Detailseite bleibt die Ansicht, damit der gemerkte
  Fokus dieselbe Karte an derselben Stelle trifft.

### Unverändert

- Der Fokus- und Scroll-Fix aus 2.0.1 bleibt.
- Keine Änderung an Google Drive, OAuth, TV-Synchronisation, `drive.file` oder
  `drive.appdata`.

### Geprüft

- **Unit-Tests im TS-Kern (neu, 10):** erster Aufbau, geänderter Sortierwert
  in derselben Ansicht, mehrere Antworten in unterschiedlicher Reihenfolge,
  später geladene Titel, TMDB-abhängiger Filter, entfernte Titel,
  Dubletten-Vertreterin, bewusste neue Ansicht (Sortierung, Filter, Suche),
  erneutes Öffnen, leere Ansicht. TS-Kern insgesamt 221/221.
- **Fernbedienungstest (neu, 38 Prüfungen, 1080p und 4K):** TMDB-Antworten
  werden zurückgehalten und während der Navigation in umgekehrter Reihenfolge
  freigegeben. Geprüft: Fokus und Reihenfolge bleiben, Kartenpositionen bleiben,
  Cover und Untertitel werden trotzdem aktualisiert, mit Zeiger bleibt die Karte
  unter ihm, erneutes Öffnen sortiert nach Beliebtheit, A–Z und zurück sortieren
  neu, „Top bewertet" filtert, Navigation danach vollständig sichtbar, keine
  Skriptfehler.
- **Gegenbeweis:** Mit dem bisherigen Katalog-Code schlagen je Auflösung
  „Reihenfolge der Ansicht bleibt stabil", „… auch nach allen Antworten stabil"
  und „mit Zeiger bleibt die Karte unter ihm" fehl (299/305).
- **Mit dieser Fassung:** Fernbedienungstest 305/305, zweimal hintereinander;
  nori-api 13/13; `check-webos-package.py` OK (2.1.1 überall, auch im `.ipk`).
- Nicht auf LG-Hardware geprüft.

## [iOS 1.23.0] · [macOS 1.18.0] · [webOS 2.1.0] — 2026-09-13

Google Drive auf dem LG-Fernseher — über einen TV-Spiegel, den iPhone, iPad
oder Mac nach ausdrücklicher Freigabe zusätzlich schreiben.

### Hintergrund

Googles Gerätefluss für Fernseher lehnt `drive.appdata` reproduzierbar mit
`invalid_scope` ab: mit mehreren TV-Clients und in einem separaten
Google-Cloud-Projekt, entgegen der Dokumentation. Der versteckte
`appDataFolder` ist vom Fernseher aus deshalb nicht erreichbar. Nach einer
Architekturstudie und einem Proof of Concept mit einem echten Konto gilt das
hybride Modell; Begründung in `docs/synchronisation.md`, Messungen in
`docs/google-drive-sync.md`.

### Neu

- **„Mit Fernseher teilen" (iOS/iPadOS, macOS).** Schalter unter
  Synchronisation → Fernseher, je Gerät, standardmäßig aus. Vor dem Einschalten
  erklärt ein Dialog, dass Nori eine sichtbare Kopie im Ordner „Nori" anlegt und
  nur auf eigene Dateien zugreift. Eingeschaltet wird erst nach Googles
  Zustimmung (`drive.file` mit `include_granted_scopes`; `drive.appdata` bleibt).
- **TV-Spiegel.** Je Gerät eine Datei `nori-tv-sync-v1-<deviceId>.json`, erkannt
  ausschließlich über `appProperties` (`type=library-mirror`, `mirror=tv`). Der
  Ordner „Nori" ist nur für den Nutzer da; Umbenennen und Verschieben brechen den
  Abgleich nicht. Eine Dateikennung gehört genau zu einer Ablage.
- **Relais.** Ein Apple-Gerät mit Freigabe gleicht `appDataFolder` und Spiegel
  gegen dieselbe Bibliothek ab und reicht Änderungen in beide Richtungen weiter,
  entprellt und ohne zusätzlichen Zeitgeber. Die Oberfläche sagt ohne
  Fachbegriffe, dass mindestens ein solches Gerät regelmäßig synchronisieren muss.
- **webOS** fragt ausschließlich nach `drive.file` und liest nur den Spiegel.
  Ohne Spiegel eines Apple-Geräts steht dort „Noch keine TV-Synchronisation
  gefunden – Aktiviere auf deinem iPhone, iPad oder Mac in Nori unter
  Synchronisation „Mit Fernseher teilen"." Fehlt `drive.file`, heißt der Zustand
  „Anmeldung nötig" statt eines Fehlertexts.
- **Diagnose (Apple):** erteilte Bereiche, Zustand des Spiegels (aus, Zustimmung
  fehlt, aktiv) und dessen letzter Fehler. Keine Tokens.

### Behoben

- **Am Fernseher war keine Anmeldung möglich** — Google lehnte den angefragten
  Bereich `drive.appdata` ab. Jetzt `drive.file`.
- **Ein Abgleich ohne Änderung schrieb nach einem Neustart wieder.** Der zuletzt
  geschriebene Stand (SHA-256, Datei, Änderungsstempel) wird jetzt je Ablage und
  Gerät dauerhaft gemerkt, in Swift und TypeScript.
- **webOS schrieb seine unveränderte Datei bei jedem Abgleich neu** — im Proof of
  Concept 27-mal in 17 Minuten. Der TypeScript-Kern prüft jetzt ebenso vor dem
  Upload; SHA-256 wird ohne `crypto.subtle` gerechnet (webOS 6).
- **Doppelte Dateien eines Geräts** führen nicht mehr zu wechselnden Ständen:
  gelesen wird deterministisch die neueste, gelöscht wird nichts.
- **Eine eigene Datei im Papierkorb** wird nicht weiter beschrieben; Nori legt
  eine neue an.
- **Eine erneute Zustimmung** schreibt einen unveränderten Stand nicht noch
  einmal.
- **Beim Erneuern eines Tokens ohne Bereichsangabe** gehen die erteilten
  Bereiche nicht verloren (Apple und webOS).

### Unverändert

- Ohne „Mit Fernseher teilen" fragt Apple nur nach `drive.appdata` und gleicht
  ausschließlich im `appDataFolder` ab — wie in iOS 1.22.0 und macOS 1.17.0.
- Kein Umzug des `appDataFolder`, keine automatische Löschung, keine
  Ende-zu-Ende-Verschlüsselung (mögliche spätere Erweiterung).
- Auf LG-Hardware ist der Abgleich nicht geprüft.

### Geprüft

- **Swift-Kern:** 452 Tests bestanden. Neu sind 27, darunter: getrennte Ablagen
  und Merkposten, eine hineingeschmuggelte Dateikennung, Ordner finden, anlegen
  und fehlend, Erkennung umbenannter Dateien über `appProperties`, Papierkorb,
  doppelte Dateien, kein Upload nach einem Neustart ohne Änderung, Relais in
  beide Richtungen mit Grabstein, Meldung an die andere Ablage nur bei
  Änderung, gleichzeitige Läufe, mehrere Geräte, zusätzliche Zustimmung mit
  `include_granted_scopes`, fehlender oder entzogener `drive.file` sowie
  401, 403, 429 und Netzfehler im Spiegel.
- **TypeScript-Kern:** 211 Tests bestanden, darunter SHA-256 gegen Node — auch
  ohne `TextEncoder` —, dieselben Spiegel-Fälle wie in Swift, der Gerätecode nur
  mit `drive.file` und der Erhalt der Bereiche beim Erneuern.
- **nori-api:** 13 Tests bestanden. `check-apple-sources.py` ohne
  Auffälligkeiten. `check-webos-package.py` OK, Version 2.1.0 überall gleich,
  auch im `.ipk`.
- **Fernbedienungstest webOS:** 267/267 bestanden, nach Übernahme von webOS
  2.0.1 aus `main`. Vorher schlug „Katalog Matrix" fehl — ein vorbestehender
  Fokusfehler im Katalograster, auch auf `main`; behoben in 2.0.1. Alle
  Abgleich-Prüfungen bestehen (nur `drive.file` im Gerätefluss, nie
  `appDataFolder`, Spiegel-Kennzeichnung, Hinweis ohne Fachbegriffe).
- **Xcode:** Debug- und Release-Builds von iOS 1.23.0 und macOS 1.18.0
  erfolgreich.
- **Bundles:** iOS 1.23.0 (35) enthält nur die eigene Client-ID und kein Secret,
  macOS 1.18.0 (27) nur die eigene Client-ID und das eigene Secret, das
  webOS-Paket 2.1.0 nur die TV-Client-ID und das TV-Secret. Keine OAuth-JSON in
  einem Bundle.
- **Ende-zu-Ende mit einem echten Google-Konto** — iPhone-Simulator mit iOS
  1.23.0, Mac mit macOS 1.18.0, webOS-TV-Simulator 26 mit webOS 2.1.0:
  - Das iPhone gleicht nach dem Update ohne neue Anmeldung weiter ab und erkennt
    seine Datei im `appDataFolder` wieder. Der Mac — ad-hoc signiert, das alte
    Token im Schlüsselbund ist für ihn nicht lesbar — meldet sich neu an und
    erkennt ebenfalls seine bisherige Datei wieder.
  - „Mit Fernseher teilen" nach Googles Zustimmung auf iPhone und Mac
    eingeschaltet, je mit eigener Spiegeldatei.
  - Der Fernseher hat nur `drive.file` und keinen Merkposten für den
    `appDataFolder`; Verlauf und Fortschritt stimmen mit iPhone und Mac überein.
  - Fernseher → Spiegel → iPhone → `appDataFolder` → Mac mit ausgeschalteter
    Freigabe: ein Merklisteneintrag kam an.
  - Mac → `appDataFolder` → iPhone → Spiegel → Fernseher: seine Entfernung kam
    an, am Fernseher als Grabstein.
  - Danach vier Minuten ohne Änderung: kein weiterer Upload auf einem der drei
    Geräte.
- **Nicht geprüft:** LG-Hardware und webOS 6 auf einem echten Gerät. Dass die
  Spiegeldatei des Mac nach dem Ausschalten in Drive liegen bleibt, ist nicht in
  Drive nachgesehen; belegt ist, dass Nori dabei keine Löschanfrage stellt.

## [webOS 2.0.1] — 2026-09-13

Fokus im Katalog: nach dem Eintreffen von TMDB-Treffern stand die fokussierte
Karte halb unter dem Bildrand.

### Behoben

- **Die Scrollverankerung des Browsers arbeitete gegen die Navigation.** Kommen
  TMDB-Treffer an, bewertet `useCatalogView` die Karten gebündelt neu, und das
  Raster sortiert sich um. Chromium hielt dabei mit `overflow-anchor: auto`
  einen Knoten oberhalb der fokussierten Karte optisch fest und verschob
  `scrollTop` selbst um eine Rasterzeile — 538 px auf 1080p —, an
  `navigation/engine.ts` vorbei und ohne Fokuswechsel, also ohne `reveal`. Die
  fokussierte Karte stand danach bei 1005–1549 px. Die Bereiche mit
  `data-scroll-y` und `data-scroll-x` haben jetzt `overflow-anchor: none`; ihre
  Position bestimmt allein die Navigation. Aufgefallen im Fernbedienungstest
  („Katalog Matrix", 4. Druck nach Rechts auf „Chainsaw Man"), dort reproduzierbar
  auf `main`.
- **Wechselte die fokussierte Karte beim Umsortieren selbst die Zeile, holte sie
  niemand zurück.** Die Verankerung hatte das zufällig mit abgefangen — ohne sie
  stand die Karte am Ende des Katalogs bei −81 px. Sichtbar gemacht wurde bisher
  nur beim Fokuswechsel; `navigation/engine.ts` prüft jetzt nach jeder
  DOM-Änderung, ob sich das fokussierte Element verschoben hat, und holt es mit
  demselben `reveal` ins Bild. Ohne Verschiebung passiert nichts, mit Zeiger
  (Magic Remote) wird nicht gescrollt.

### Geprüft

- **Ursache belegt:** Im protokollierten Lauf sortierte sich das Raster 45 ms nach
  dem 4. Druck nach Rechts um, 22 ms später änderte der Browser `scrollTop` von
  949 auf 411 — ohne dass die Navigation scrollte. Mit `overflow-anchor: none`
  sortierte sich das Raster zum selben Zeitpunkt um, die Seite blieb stehen.
- **Zwei neue Prüfungen** im Fernbedienungstest stellen die Umsortierung nach:
  „Katalog umsortiert: Seite bleibt stehen, Fokus vollständig sichtbar" und
  „… fokussierte Karte wechselt die Zeile und bleibt ganz sichtbar". Ohne Fix
  schlagen „Katalog Matrix" und die erste fehl; nur mit dem CSS-Teil schlagen die
  zweite und „unterste Reihe vollständig sichtbar" fehl.
- **Fernbedienungstest mit vollständigem Fix:** 261/261, zweimal hintereinander,
  1080p und 4K; keine bestehende Prüfung verändert.
- TS-Kern 188/188, nori-api 13/13, `check-webos-package.py` OK (2.0.1 überall,
  auch im `.ipk`).
- Nicht auf LG-Hardware geprüft.

## [iOS 1.22.0] · [macOS 1.17.0] — 2026-09-13

Google Drive auf iPhone, iPad und Mac: eingerichtet statt nur vorbereitet.

### Behoben

- **Die Anmeldung auf dem Mac konnte nie gelingen.** Der macOS-Client ist vom
  Typ „Desktop-App", und Googles Token-Endpunkt verlangt dafür ein
  `client_secret` — beim Tausch des Codes **und** beim Erneuern. Nori schickte
  keines, weil die Dokumentation den Parameter als optional führt; Google
  antwortete mit `client_secret is missing`. Gemessen am echten Endpunkt, nicht
  angenommen. Das Secret kommt jetzt aus der Build-Einstellung
  `GOOGLE_CLIENT_SECRET` in der nicht eingecheckten
  `native/Nori-macOS/Config/Google.local.xcconfig` und wird nur auf macOS
  mitgeschickt. Die iOS-App hat den Schlüssel gar nicht.
- **Eine verweigerte Ablage im Schlüsselbund sah aus wie eine gelungene
  Anmeldung.** Die Tokens werden jetzt zurückgelesen; fehlen sie, meldet Nori
  „Die Anmeldung ließ sich nicht im Schlüsselbund ablegen" statt beim ersten
  Abgleich still auf „Anmeldung nötig" zu fallen.
- **Nach der Anmeldung lief der Zeitgeber nicht an.** Änderungen der anderen
  Geräte kamen erst nach dem nächsten Wechsel in den Vordergrund an; auf dem Mac
  gar nicht, weil der Zeitgeber dort nur beim Start angestossen wurde, als noch
  keine Verbindung bestand.
- **Jeder Blick in die Einstellungen löste einen vollständigen Abgleich aus.**
  `restore()` band die Engine erneut an, auch wenn sie längst verbunden war.
- **Die Browserseite auf dem Mac sagte „Nori ist verbunden", auch wenn Google
  abgelehnt hatte.** Sie unterscheidet jetzt, und Nori holt sich nach der
  Rückleitung selbst nach vorn.

### Geändert

- **Build-Konfiguration je Plattform.** `native/Nori-iOS/Config/Nori.xcconfig`
  und `native/Nori-macOS/Config/Nori.xcconfig` sind die Basiskonfiguration der
  Targets und binden je eine nicht eingecheckte `Google.local.xcconfig` ein.
  Eine gemeinsame Datei gibt es mit Absicht nicht: keine Plattform soll die
  Client-ID der anderen erben.
- **Eine übernommene Client-ID gilt nur noch mit Tokens.** Frühere Fassungen
  liessen die Client-ID von Hand eintragen. Eine bestehende Verbindung behält
  ihre ID; ohne Tokens verbindet den alten Wert nichts mehr mit dem Gerät, und
  es gilt ausschliesslich der Build. Gehört ein übernommener Wert zu einem
  anderen Cloud-Projekt, sagt die Diagnose das.
- **Ein Abgleich ohne Änderung schreibt nichts.** Vorher lud jedes Gerät im
  Vordergrund alle 30 Sekunden seine unveränderte Datei hoch; jeder Upload
  setzte einen neuen Änderungsstempel, und jedes andere Gerät holte die Datei
  danach erneut.
- **Vordergrund und Hintergrund sind entprellt.** Nach vorn kommen gleicht nur
  ab, wenn lokal etwas offen ist oder der letzte Versuch mindestens 30 Sekunden
  zurückliegt; weggehen nur, wenn etwas offen ist. Der Mac reagiert jetzt
  überhaupt auf Aktivierung und Deaktivierung.
- **Die Diagnose zeigt mehr — und weiterhin nichts Geheimes:** ob ein
  Client-Secret vorliegt (macOS), ob eine Anmeldung im Schlüsselbund liegt,
  letzter Abgleich, letzter Fehler, die erwarteten Build-Einstellungen.

### Hinzugefügt

- **`tools/configure-google-oauth.py`** schreibt die lokalen Dateien — iOS aus
  der Client-ID, macOS aus `~/.config/nori/secrets/google-macos-oauth.json`,
  webOS aus `~/.config/nori/secrets/google-webos-oauth.json` — und prüft mit
  `--check`, dass sie ignoriert und nicht verfolgt sind, dass die Client-IDs
  verschieden sind und kein Secret in verfolgten Dateien, im Index oder in neuen
  Commits steht. Mit `--inspect-ios`, `--inspect-macos` und `--inspect-webos`
  sieht es in fertige Builds. Secrets gibt es nie aus.
- **`.gitignore`** erfasst die lokalen `.xcconfig`-Dateien und OAuth-JSON-Dateien.

### Geprüft

Mit einem echten Google-Konto, einem iPhone-17-Pro-Simulator (iOS 1.22.0) und
der Mac-App (1.17.0), beide gebaut mit ihrer eigenen lokalen Konfiguration:

- **Anmeldung iOS:** `ASWebAuthenticationSession` öffnet Google, nach der
  Zustimmung kommt Nori zurück, die Tokens liegen im Schlüsselbund, der erste
  Abgleich legt die eigene Datei im `appDataFolder` an.
- **Anmeldung macOS:** Systembrowser, Rückleitung auf `127.0.0.1`, Tausch mit
  Client-Secret, Tokens im Schlüsselbund, erster Abgleich legt die eigene Datei
  an.
- **Mac → iPhone:** 21 Verlaufseinträge und 4 Fortschrittsstände vom Mac kamen
  vollständig auf dem iPhone an.
- **iPhone → Mac:** ein Merklisteneintrag vom iPhone erschien auf dem Mac.
- **Löschen:** derselbe Eintrag, auf dem iPhone entfernt, verschwand auf dem Mac
  — über den Grabstein, nicht über eine Liste.
- **Neustart:** beide Apps nach dem Beenden neu gestartet — verbunden ohne
  erneute Anmeldung, und die Löschung lief danach in beide Richtungen durch.
- **Erneuern:** nach Ablauf der Zugriffstokens (eine Stunde nach der Anmeldung)
  lief der Abgleich auf beiden Geräten ohne erneute Anmeldung weiter — auf dem
  Mac mit Client-Secret, die Tokens im Schlüsselbund wurden dabei neu
  geschrieben.
- **Bundles:** iOS enthält genau die iOS-Client-ID und kein Secret, macOS genau
  die macOS-Client-ID und sein Secret nur in der `Info.plist`; keine
  OAuth-JSON in einem Bundle, keine fremde Client-ID in einem Bundle.
- **Git:** kein Secret, keine Client-ID und kein Token im Commit; die lokalen
  Dateien sind ignoriert.
- 425 Swift-Tests, `tools/check-apple-sources.py`, Builds für iOS (Simulator)
  und macOS.

### Nicht geändert

- **webOS.** Googles Gerätefluss lehnt `drive.appdata` für den TV-Client derzeit
  mit `invalid_scope` ab, obwohl die Dokumentation den Bereich erlaubt. Die
  Messungen stehen in `docs/google-drive-sync.md`, Abschnitt 10. Bis die Ursache
  geklärt ist, bleibt die webOS-App unverändert beim `appDataFolder`.

## [webOS 2.0.0] — 2026-09-12

Die sichtbare TV-Oberfläche ist neu gebaut, nach `nori-webos-design-v4.html`.
Übernommen sind nur Daten, Provider, Player-Logik, Bibliothek, Abgleich und
die TMDB-Schicht. Eine neue Hauptnummer, weil nichts Sichtbare bleibt — und
weil `1.4.0` (die Google-Anmeldung per QR-Code, unten) schon als Paket
existiert; ein Fernseher mit diesem Stand muss 2.0.0 als neuer erkennen.

### Geändert

- **Alle Ansichten neu:** Start (Hero, Weiterschauen, Neu & beliebt, Neue
  Episoden, Für dich, Merkliste), Katalog (Suche, Schnellfilter, Filterdialog,
  fünf Poster je Zeile), Detailseite (großer Backdrop, Staffelmenü, drei
  Folgenkarten je Zeile), Kalender (Heute, Woche, Monat), Merkliste (Übersicht,
  Ungesehen/Angefangen/Gesehen, Bearbeiten), Mehr (große Karten, Unterseiten
  Verbindung, Abgleich, Daten, Diagnose, Verlauf). Player: gleiche Logik, neue
  Palette und Fokus.
- **Seitenleiste:** nur die Wortmarke „Nori" oben links, fünf Einträge auf
  Bildmitte, feste Breite von 15,5 rem ohne Aufklappen.
- **Farben:** Grund `#03070d`, Akzent Eisblau `#79c7ff`, Fokus hell mit dunkler
  Schrift. Der Merkliste-Knopf im Hero ist normal hell auf dunkel und im Fokus
  dunkel auf hell.
- **Skalierung:** alle Maße in rem, Wurzelschrift aus Breite und Höhe; 4K
  zeigt dasselbe Layout doppelt so groß. TMDB-Bildgrößen je gezeichneter Breite
  (`src/services/images.ts`).
- **Navigation:** eigene Engine (`src/navigation/engine.ts`) statt Enact
  Spotlight. Scrollen ohne `scrollIntoView`, mit Rechnung gegen das Ziel
  laufender Bewegungen, Fokuswachstum, Ring und 3,5 rem Sicherheitsrand. Fokus
  und Scrollstand je Ansicht gemerkt. `@enact/spotlight` ist keine Abhängigkeit
  mehr.
- **Keine CSS-Merkmale, die webOS 6 fehlen:** kein Flex-`gap`, kein
  `aspect-ratio`, kein `inset`. `tools/check-webos-package.py` prüft die
  beiden letzten.
- **Katalog im Bereich „Alle" ohne Dubletten:** zusammengeführt über dieselbe
  TMDB-Kennung oder denselben Slug mit gleichem Titel.
- **Kalender:** eine Uhrzeit nur, wenn die Quelle eine nennt (`hasTime`).
- **Die Google-Anmeldung aus 1.4.0 ist übernommen:** ein Knopf in
  Mehr → Synchronisierung und unter Mehr → Abgleich, der Gerätedialog mit
  QR-Code im Stil der neuen Oberfläche, die Zugangsdiagnose hinter dem
  Schalter „Diagnoseprotokoll“.

### Behoben

- **TMDB konnte für die ganze Sitzung stillstehen.** `ensureLogo` und
  `ensureSeason` belegten einen der vier Abrufplätze und warteten darin auf
  `ensureArt`, das selbst einen Platz brauchte. Waren alle vier so belegt,
  kam kein TMDB-Abruf mehr zurück. Die Zuordnung läuft jetzt vor dem
  Einreihen.
- **Ein 404 auf dem Weg zu TMDB galt als „gibt es nicht" — für vierzehn
  Tage.** Die Suche antwortet nie mit 404; er kam etwa von einem Nori-Server
  ohne `/api/tmdb`. Gemerkt wird nur noch „TMDB hat geantwortet, nichts
  passte" (zwölf Stunden). Ablagefassung v4 verwirft die falschen Einträge.
- **Ein einmal abgelegtes Quellcover verhinderte das TMDB-Poster.** Kacheln
  fragten TMDB nur, wenn gar kein Bild bekannt war.
- **Jede Kachel lud die Detailseite der Quelle**, auch wenn TMDB ein Poster
  hatte. Jetzt TMDB zuerst, die Quelle nur als Rückfall.
- **Rücktaste im Suchfeld** verließ die Ansicht.

### Geprüft

- `npm --prefix shared/nori-core test`: 188 bestanden.
- `npm --prefix services/nori-api test`: 13 bestanden.
- `npm --prefix apps/webos run build`: `tsc --noEmit` und Vite ohne Fehler.
- Fernbedienungslauf (`test/remote-control.test.mjs`, neu geschrieben) gegen
  den Mock-Server in Chromium, getrennt bei 1920 × 1080 und 3840 × 2160:
  259 von 259 Prüfungen bestanden, darunter der Gerätefluss mit QR-Code aus
  1.4.0 in der neuen Oberfläche; siehe `docs/webos.md`.
- `swift test`: 413 Tests, 0 Fehler; `tools/check-apple-sources.py` ohne Befund.
- Die Bildschirmfotos von Start, Katalog, Detail, Staffelmenü, Kalender
  (Heute, Monat), Merkliste, Mehr, Player-Drawer und 4K-Start habe ich mir
  angesehen.

### Nicht geprüft

- **Kein echter Fernseher.** Weder installiert noch gestartet; das `ares`-SDK
  ist auf dem Bauplatz nicht vorhanden. Magic Remote, Systemtastatur und
  HLS-Wiedergabe auf dem Gerät sind offen.
- **Keine echten Quellen und kein echtes TMDB.** Alle Läufe gegen feste Daten
  (`test/mock-server.mjs`, `test/mock-tmdb.mjs`).
- **Google Drive** nicht mit einem echten Konto.

## [webOS 1.4.0] · [iOS 1.21.0] · [macOS 1.16.0] — 2026-09-12

Anmelden statt einrichten. Der Abgleich über Google Drive bleibt derselbe — die
Anmeldung dazu ist jetzt ein Knopf.

### Geändert

- **Die OAuth-Einstellungen sind aus der Oberfläche verschwunden.** Auf allen
  drei Plattformen standen dort Eingabefelder: iPhone und Mac für die
  Google-Client-ID, der Fernseher zusätzlich für das Client-Secret — 40 Zeichen,
  einzugeben mit einer Fernbedienung über eine Bildschirmtastatur. Das war keine
  Einrichtung, das war eine Hürde, und wer sie vor sich hatte, bekam keinen
  Abgleich. Die Werte kommen jetzt aus dem Build (`GOOGLE_CLIENT_ID` auf Apple,
  `VITE_NORI_GOOGLE_TV_CLIENT_ID` und `VITE_NORI_GOOGLE_TV_CLIENT_SECRET` auf
  webOS). Fehlen sie, ist das ein Build-Fehler und keine Nutzeraufgabe: die
  Oberfläche sagt es in einem Satz, statt ein Feld anzubieten, in dem niemand
  etwas Sinnvolles eintragen könnte.
- **Was eine ältere Fassung im Gerät hinterlassen hat, gilt weiter.** Die Tokens
  einer bestehenden Verbindung sind zu der von Hand eingetragenen Client-ID
  ausgestellt; würde sie jetzt übergangen, wäre die Verbindung nach dem Update
  weg — ohne Grund und ohne Meldung. Sie hat deshalb Vorrang, und wenn sie mit
  der aus dem Build übereinstimmt, wird die Kopie im Gerät aufgeräumt.
- **iOS meldet sich in der geteilten Browser-Sitzung an.** Vorher lief die
  Anmeldung mit `prefersEphemeralWebBrowserSession = true`, also ohne die
  Cookies aus Safari — auf einem Telefon, das bei Google angemeldet ist, hiess
  das: Passwort eingeben. Jetzt sieht der Nutzer die Kontoauswahl und bestätigt
  einmal. Dass die Frage gestellt wird, hängt an `prompt=consent` in der
  Anmeldeadresse und nicht an der Sitzung; PKCE und `state` bleiben unberührt.
- **„Google Drive muss erneut verbunden werden" ist ein eigener Zustand.** Eine
  widerrufene oder abgelaufene Berechtigung stand vorher als Fehlertext da — und
  wenn sie aus der Autorisierungsschicht kam, sogar als „offline", weil sie kein
  `DriveError` ist. Die Oberfläche wartete dann auf ein Netz, das längst da war.
  Jetzt gibt es `needsReauthorization` in beiden Kernen und einen Knopf „Erneut
  anmelden".

### Hinzugefügt

- **Ein QR-Code für die Anmeldung am Fernseher.** Der Gerätefluss bekommt einen
  eigenen Bildschirm statt einer Zeile in der Einstellungsliste: links ein
  QR-Code von 22 rem Kante (328 px auf 1080p), rechts die Adresse ohne Schema
  und der Gerätecode in 4 rem Schrift, darunter die Restlaufzeit. Läuft der Code
  ab, steht dort ein Satz und ein Knopf für einen neuen — kein OAuth-Fehlertext.
  Der Fokus wandert in den Dialog, „Zurück" schliesst ihn und gibt den Fokus
  zurück.
- **Ein QR-Encoder im gemeinsamen Kern** (`shared/nori-core/src/qr.ts`):
  Byte-Modus, Fehlerkorrektur M, Fassungen 1 bis 10, ohne Abhängigkeit und ohne
  einen einzigen Netzabruf. Ein QR-Dienst im Netz hätte geheissen, die Adresse
  einer laufenden Anmeldung an einen Dritten zu schicken.
- **`verification_uri_complete` nach RFC 8628** wird gelesen und für den
  QR-Code bevorzugt: dann steckt der Code schon in der Adresse und am Telefon
  ist nichts mehr zu tippen. Fehlt das Feld, enthält der QR-Code genau
  `verification_uri` — eine Adresse mit angehängtem `user_code` selbst zu bauen
  wäre geraten, und ein falscher Parameter führt auf eine Fehlerseite.
- **`config/contract.json` beschreibt die Anmeldung.** Neu unter `sync.auth`:
  Bereich, Fluss je Plattform, Anmeldeparameter, die Fehlercodes des
  Geräteflusses, wo Tokens liegen, was nie abgeglichen und nie protokolliert
  wird, und der Unterschied zwischen „Gerät trennen" und „Zugriff widerrufen".

### Behoben

- **Ein Abbruch der Anmeldung wirkte erst beim nächsten Aufwachen.** Die
  Abfrageschleife schlief bis zu einem ganzen Wartetakt und gab ihren Platz
  bis dahin nicht frei; wer abbrach und gleich wieder „Verbinden" drückte,
  bekam nichts. Das Warten endet jetzt mit dem Abbruch.
- **`slow_down` beachtet Googles eigene Wartezeit.** Nennt Google im Fehler ein
  längeres `interval`, gilt das — vorher wurden pauschal fünf Sekunden
  aufgeschlagen.
- **Eine Antwort ohne Anmeldeadresse wird nicht mehr geraten.** Vorher fiel Nori
  auf `https://www.google.com/device` zurück; eine Antwort ohne Adresse heisst
  aber nicht, dass diese Adresse gilt.
- **Unsinnige Zahlen von Google enden nicht in `NaN`.** `expires_in: "bald"`
  hiess vorher: der Code läuft nie ab und die Schleife nie aus.
- **`invalid_client` und `invalid_scope` fallen schon beim Gerätecode auf** und
  werden als Build-Fehler benannt statt als allgemeine Störung.

### Geprüft

169 Prüfungen im Fernbedienungslauf (vorher 140), darunter der ganze
Gerätefluss mit abgefangenen Google-Endpunkten: QR-Code gezeichnet und
gross genug, Code und Adresse lesbar, Restlaufzeit, Fokus im Dialog, „Zurück",
automatischer Abschluss nach der Zustimmung, Neustart ohne erneute Anmeldung,
abgelaufener Code. Dazu 188 Kerntests (vorher 165) und 413 Swift-Tests (vorher
406).

Der QR-Encoder ist gegen eine **unabhängige** Referenzumsetzung geprüft, Modul
für Modul über alle Längen von 1 bis 213 Byte; fünf dieser Matrizen liegen als
Festwerte in `shared/nori-core/test/qr.test.ts`. Zusätzlich habe ich den auf dem
Bildschirm gerenderten Code aus den Bildschirmfotos mit einem Decoder gelesen —
bei 1280 × 720, 1920 × 1080 und 3840 × 2160 kommt genau
`verification_uri_complete` heraus.

Was **nicht** geprüft ist: eine echte Anmeldung bei Google. Die hängt an einem
echten Konto und an echter Hardware.

## [webOS 1.3.1] — 2026-09-12

Die Seitenleiste, nachgemessen statt nach Augenmaß.

### Behoben

- **Die Auswahl reichte weit über ihr Symbol hinaus.** Eingeklappt war das
  Feld 83 px breit, das Symbol darin lag bei 34…64 px — rechts davon standen
  38 px leere Fläche, und die Markierung endete im Nichts. Der Grund war nicht
  die Breite allein: Abstand (`gap`) und Schriftzug belegten auch eingeklappt
  Platz. Jetzt ist das Feld eingeklappt 3,5 rem im Quadrat, dasselbe Maß wie
  das Markenbild darüber und an derselben linken Kante.
- **Die Marke ragte 23,7 px über die eingeklappte Leiste hinaus.** Das Wort
  „Nori" stand auch dort im Textfluss; sichtbar wurde es nur nicht, weil es
  mit `opacity: 0` steht und die Leiste kein `overflow: hidden` hat.
- **Die Einträge saßen oben angeschlagen.** Die Leiste ist 1080 px hoch, die
  sieben Einträge zusammen 468 px; darunter blieben über vierhundert Pixel
  leer. Sie sitzen jetzt auf Bildmitte — auf 540 px genau, weil die Marke
  dafür aus dem Fluss genommen ist und die Mitte nicht mehr verschiebt.

### Geprüft

Vier neue Prüfungen im Fernbedienungslauf messen genau diese vier Maße, damit
sie nicht wieder wegdriften: Überhang der Marke, Polster links und rechts des
Symbols, gemeinsame linke Kante von Symbolfeld und Markenbild, Abstand des
Eintragsblocks zur Bildmitte. 140 Prüfungen insgesamt, dazu 165 Kern- und 13
Servertests. Beide Zustände der Leiste habe ich mir als Bildschirmfoto
angesehen.

Das App-Symbol ist **nicht** geändert: `tools/make-app-icons.py --write`
erzeugt aus `assets/branding/nori-app-icon.png` bitgleich die Dateien, die
schon im Paket liegen — webOS zeigt dasselbe Motiv wie iOS, macOS und Windows.

## [webOS 1.3.0] — 2026-09-12

Die Zusammenführung von 1.2.0 mit dem Stand auf `main`. Beide Seiten hatten
gleichzeitig an TMDB gearbeitet, und `main` hat dabei den Abgleich über Google
Drive und Bibliotheksschema v6 bekommen. Eine neue Nummer, weil ein anderes
Paket entsteht: derselbe Stand unter derselben Version wäre der Fehler, den man
auf einem Fernseher nicht mehr auseinanderhalten kann.

### Hinzugefügt

- **Abgleich über Google Drive** auf dem Fernseher — aus `main` übernommen,
  mitsamt Anmeldung über den Gerätecode (die Fernbedienung tippt keine
  Zugangsdaten) und Bibliotheksschema **v6** mit Löschmarken. Was daran geprüft
  ist und was nicht, steht unten.

### Geändert

- **Eine TMDB-Fassung statt zweier.** `main` hatte `shared/nori-core/src/tmdb.ts`
  bekommen, dieser Zweig `shared/nori-core/src/tmdb/`. Geblieben ist das
  Verzeichnis; aus der Einzeldatei sind die Teile übernommen, die dort besser
  waren:
  - „The Final Season" räumt nicht mehr zu „… the" ab — der bestimmte Artikel
    gehört **in** den Ausdruck und nicht in eine zweite Zeile danach.
  - Ein Logo **ohne** Sprachkennzeichen steht jetzt vor einem fremdsprachigen
    statt mit ihm auf einer Stufe, und bei gleicher Bewertung entscheidet
    `vote_count`.
  - Eine bereits vollständige Bildadresse wird nicht noch einmal
    zusammengesetzt.
  - Fehlschläge haben zwei Fristen statt einer: **HTTP 404** gilt vierzehn
    Tage, „gesucht und nichts über der Titelschwelle" nur zwölf Stunden. TMDB
    wächst, und gerade bei frischen Anime kommt der Eintrag Tage später.
    Ratenbegrenzung und abgelehnter Schlüssel gelten wie vorher überhaupt nicht
    als Fehlschlag.
- **Die Staffelzuordnung folgt jetzt buchstäblich dem Contract.** Sie hatte
  einen Versatz schon bei **zwei** übereinstimmenden Folgentiteln übernommen,
  während `config/contract.json` und `TMDBSeasonMap` auf der Swift-Seite drei
  verlangen, dazu die Hälfte der benennbaren Quellfolgen und keinen zweiten
  gleich gut belegten Versatz. Jetzt gilt dieselbe Regel in beiden Kernen —
  drei neue Testfälle grenzen sie ab. Das ist die strengere Fassung: lieber
  keine Folgendaten als die der falschen Folge.
- **„Bibliothek einlesen" benutzt `mergeLibrarySnapshots`**, also dieselbe
  Regel wie der Geräteabgleich, statt einer eigenen. Von Hand eingelesen und
  über Drive abgeglichen führen damit nicht zu zwei verschiedenen Ergebnissen.
  Die eigene Gerätekennung bleibt dabei die dieser Installation — übernähme der
  Fernseher die des Geräts, von dem der Stand stammt, schrieben beide in
  dieselbe Drive-Datei.
- **Die Ablage der TMDB-Angaben auf dem Fernseher ist v3.** v2-Stände werden
  verworfen, weil die Fehlschläge dort keine Frist mittragen. Kostet einmal
  Nachladen, keine Daten.

### Behoben

- **Aussagen über den Geräteabgleich, die nicht mehr stimmten.** Einstellungen,
  `docs/webos.md` und der CHANGELOG behaupteten „ein Abgleich zwischen Geräten
  ist auf keiner Plattform gebaut". Das war vor der Zusammenführung richtig und
  danach falsch.

### Geprüft

- **Automatisch:** 165 Testfälle im Kern (davon die TMDB-Zuordnung,
  Staffelversätze, Ranglisten und der Schlüssel), 13 am Nori-Server, 130 Prüfungen
  im Fernbedienungslauf gegen einen nachgebauten Server — einschließlich Start
  von `file://`, dem Rückfall für fehlendes Flex-`gap` und der Ablage nach
  Schema v6.
- **Nicht geprüft:** der Abgleich über ein echtes Google-Konto und zwei echte
  Geräte. Die Zusammenführungsregel selbst ist es — in beiden Kernen gegen
  `config/sync-fixtures.json`. Und wie immer: kein Lauf auf einem echten
  webOS-Gerät.

## [webOS 1.2.0] — 2026-09-12

Nachtrag zu 1.1.0. Dort war TMDB vollständig eingebaut, aber **einzurichten**:
Wer keinen Nori-Server und keinen eigenen Schlüssel hatte, sah die kleinen
Cover der Quellen. Auf einem Fernseher ist das derselbe Zustand wie „geht
nicht" — dort gibt es keine Tastatur, und einen 32-stelligen Hex-Schlüssel mit
einer Fernbedienung über eine Bildschirmtastatur einzugeben, macht niemand.

Die Apple-Apps haben dafür längst einen mitgelieferten Schlüssel
(`TMDBKeyStore.builtIn`, dokumentiert in `CLAUDE.md` und als einzige erlaubte
Zeile in `tools/check-apple-sources.py`). webOS hatte ihn nicht.

### Geändert

- **Der TMDB-Schlüssel ist mitgeliefert.**
  `shared/nori-core/src/tmdb/key.ts` hält `BUILT_IN_TMDB_KEY` — denselben, den
  die Apple-Seite benutzt. Damit ist TMDB auf einem frisch installierten
  Fernseher sofort da: Poster, Hintergrundbilder, Schriftzüge, Beschreibungen,
  Bewertungen, Folgentitel, Folgenbilder und die Signale für „Neu & beliebt"
  und „Für dich". Einzurichten ist nichts.
- **Der Nori-Server ebenso.** Ohne `NORI_TMDB_KEY` greift derselbe
  mitgelieferte Schlüssel; ein frisch aufgesetzter Server kann sofort TMDB.
  `/api/health` sagt in `features.tmdbKey`, ob ein eigener oder der
  mitgelieferte gilt — den Schlüssel selbst gibt der Dienst nie heraus.
- **Ein eigener Schlüssel hat weiter Vorrang** und heißt in den Einstellungen
  jetzt so: „Eigener TMDB-Schlüssel", optional, mit „Löschen" daneben. Der Weg
  heißt nicht mehr „Eigener Schlüssel", sondern „Dieser Fernseher" — er
  funktioniert ja ohne einen. Wer einen einträgt, trennt seine
  Ratenbegrenzung von der geteilten Kennung.
- **„Aus" ist die einzige Art, TMDB nicht zu benutzen.** Vorher konnte der
  Zustand „nicht eingerichtet" dasselbe bewirken, ohne dass jemand ihn gewählt
  hatte. Der Unterschied steht jetzt in den Einstellungen: der Weg nennt
  entweder „Nori-Server", „dieser Fernseher, mitgelieferter Schlüssel",
  „dieser Fernseher, eigener Schlüssel" — oder „aus".

### Hinzugefügt

- **`tools/check-webos-package.py` prüft auf Schlüssel im Quelltext.** Dieselbe
  enge Ausnahme wie auf der Apple-Seite: genau die Zeile mit
  `BUILT_IN_TMDB_KEY` ist erlaubt, jeder zweite einkompilierte Schlüssel fällt
  auf — auch einer in derselben Datei. Prüfdateien werden nur auf lange
  Hex-Zeichenketten gelesen: ein Test, der belegt, dass `api_key` aus einer
  Anfrage **entfernt** wird, muss so eine Zuweisung enthalten.
- **Und darauf, dass beide Seiten denselben Schlüssel benutzen.** Zwei Kopien
  einer Zeichenkette laufen auseinander; läuft diese auseinander, zeigt der
  Fernseher zu derselben Serie andere Daten als das iPhone — ohne
  Fehlermeldung, weil beide Schlüssel gültig sind.
- **Fünf Tests** für die Schlüsselauflösung im Kern (122 gesamt) und einer für
  den Server (13 gesamt). Der Fernbedienungslauf prüft zusätzlich den Zustand
  eines frisch installierten Fernsehers: keine Einstellungen, kein Server, kein
  Schlüssel — und TMDB trotzdem eingerichtet. 130 Prüfungen.

### Warum eine neue Nummer

1.1.0 war nie installiert, aber der CI-Lauf des Pull Requests hat dafür ein
`.ipk` abgelegt. Ein Paket ist ein Paket: zwei mit derselben Nummer und
unterschiedlichem Inhalt sind hinterher nicht mehr unterscheidbar, und der
Fernseher installiert das zweite nicht über das erste.

### Was das bedeutet

Der Schlüssel steckt damit im gebauten `.ipk`, und aus dem lässt er sich
herausziehen. Das ist die Entscheidung des Betreibers für ein privates
Repository, dieselbe wie auf iPhone und Mac — aufgeschrieben an der
Deklaration in `key.ts`. Wird das Repository je öffentlich, ist der Schlüssel
es auch.

## [webOS 1.1.0] — 2026-09-12

Der zweite Aufschlag für **Nori auf LG-Fernsehern**. Die erste Fassung war
bedienbar, aber sie sah nicht nach Nori aus und wusste über eine Serie fast
nichts: Ihr Hauptakzent war ein warmes Orange (`#f47521`), das aus einer
anderen Streaming-App stammte, ihre Reihe „Beliebt" waren die ersten 24
Katalogeinträge, und TMDB lieferte genau ein Bild — das Hintergrundbild des
Kopfbereichs, über den erstbesten Suchtreffer gefunden.

Dieser Stand bringt drei Dinge: die Farben und Maße der Apple-Apps, TMDB
vollständig über den gemeinsamen Kern, und eine Startseite, deren Reihen ihren
Namen verdienen.

### Hinzugefügt

- **TMDB im gemeinsamen Kern.** `shared/nori-core/src/tmdb/` ist die
  TypeScript-Entsprechung von `TMDBMatcher.swift`, `TMDBImages.swift`,
  `TMDBCatalog.swift` und `HomeFeed.swift`: Titelzuordnung, Bildadressen,
  Ranglisten, Geschmacksprofil und Abrufweg. Die webOS-App und der Nori-Server
  benutzen beide diese Dateien — es gibt keine dritte Umsetzung.
- **TMDB über den Nori-Server** (`/api/tmdb/*`). Der Schlüssel liegt damit an
  einer Stelle statt auf jedem Fernseher, der Zwischenspeicher gilt für alle
  Geräte gemeinsam, und TMDBs Ratenbegrenzung wird einmal statt je Gerät
  ausgeschöpft. Die Pfade sind gegen eine Liste geprüft und nicht
  durchgereicht; `api_key` aus der Anfrage wird verworfen. Der eigene Schlüssel
  am Gerät bleibt als Rückfall, und „aus" ist ein gültiger Zustand.
- **Staffel- und Folgenzuordnung mit Versatzerkennung.** AniWorld und TMDB
  teilen dieselbe Serie anders auf: „Attack on Titan Final Season" beginnt bei
  der Quelle wieder bei Folge 1, bei TMDB läuft die Zählung weiter. Nori
  erkennt den Versatz über die Folgentitel — und zeigt bei unsicherer
  Zuordnung **keine** Folgendaten statt der Standbilder einer anderen Staffel.
- **Folgenkacheln mit Inhalt**: Standbild, Nummer, Titel, zwei Zeilen
  Beschreibung, Laufzeit, Erscheinungsdatum, Sprache, Fortschritt und
  „Gesehen". Die Beschreibung ist auf zwei Zeilen begrenzt, weil TMDB dort
  regelmäßig schreibt, wie die Folge ausgeht.
- **Ein Auswahlraster für die Staffelwahl** ab neun Staffeln. Detektiv Conan
  hat bei AniWorld über dreißig; als waagerechte Leiste hieß das dreißigmal
  „rechts" durch eine Leiste, die sich unter dem Fokus wegscrollte. Das Raster
  ist mit allen vier Richtungen bedienbar, fängt den Fokus ein, öffnet auf der
  aktiven Staffel und schließt mit Zurück.
- **„Ähnliche Titel"** auf der Detailseite, aus TMDBs Empfehlungen und
  Ähnlichkeitsliste — gezeigt wird nur, was Noris Katalog tatsächlich führt.
  Eine Empfehlung, die sich auswählen lässt und nichts öffnet, ist schlechter
  als eine Reihe weniger.
- **Breitformat-Kacheln** für „Weiterschauen" und „Neue Episoden", mit
  Standbild der Folge, Rest-Laufzeit und Fortschrittsbalken. Beide Reihen
  zeigen eine Folge, keine Serie — ein 2:3-Poster sagt darüber nichts.
- **Bewertungen auf den Kacheln**, erst ab fünfzig Stimmen. Sonst stünde 10,0
  aus zwei Stimmen neben einer weltweit laufenden Serie.
- **Schriftzüge von TMDB** im Kopfbereich von Startseite und Detailseite; ohne
  einen steht der Titel als Schrift, und das ist kein Mangel.
- **„Bibliothek einlesen" führt zusammen statt zu ersetzen.** Ein eingelesener
  Stand von letzter Woche kann damit den Fortschritt von heute Abend nicht mehr
  löschen. Die Regel ist dieselbe, die der Geräteabgleich benutzt
  (`mergeLibrarySnapshots` im Kern) — von Hand eingelesen und über Drive
  abgeglichen führen also nicht zu zwei verschiedenen Ergebnissen.
- **TMDB-Diagnose in den Einstellungen**: welcher Weg gilt, was TMDB
  zuletzt geantwortet hat, wie viele Titel zugeordnet sind, wie viele davon
  erst über Alternativtitel, wie viele Staffeln abgelegt sind und wie viele
  Titel ohne Treffer blieben. Dazu „Erneut nach fehlenden suchen", ohne die
  vorhandenen Bilder zu verlieren.
- **Tests für den Nori-Server** (`services/nori-api`, bisher keine): die
  Umschreibung der HLS-Playlisten samt Schlüssel-, Map- und Media-Zeilen, die
  Pfadliste von `/api/tmdb` und das Entfernen von `api_key` aus der Anfrage.
  Alle drei sind sicherheitsrelevant und wären sonst nur auf dem Gerät zu
  merken. `rewriteM3U8` liegt dafür jetzt in `src/playlist.ts` — `server.ts`
  startet beim Einlesen einen Dienst und ist damit nicht prüfbar.
- **76 neue Tests** im gemeinsamen Kern (41 → 117) für Titelzuordnung,
  Staffelmapping, Folgenversatz, Ranglisten, Geschmacksprofil, Abrufwege samt
  401/404/429/Netzfehler und die Zusammenführung zweier Bibliotheksstände, dazu
  12 für den Server. Der Fernbedienungslauf wächst von 48 auf 127 Prüfungen,
  erzeugt 20 Bildschirmfotos und öffnet die gebaute Datei zusätzlich über
  `file://` — den Weg, den der Fernseher nimmt.
- **Unbehandelte Fehler landen im Protokoll** (`unhandledrejection`, `error`).
  Auf einem Fernseher klappt niemand eine Konsole auf; eine abgewiesene Zusage,
  die niemand abfängt, sah dort aus wie „die Kachel bleibt einfach leer".

### Geändert

- **Die Farben sind Noris Farben.** `#f47521` ist weg. Grund ist
  `#05060a`, der Hauptakzent ein sehr helles Neutral (`#d7deea`), aktive
  Zustände und der Fokusring tragen das Signalblau (`#78c5ff`), und der einzige
  warme Ton im ganzen Bild ist der Stern einer Bewertung (`#ffe07a`) — Wert für
  Wert aus `native/Nori-iOS/Sources/UI/Theme.swift`.
- **Der Fokusring auf hellen Flächen** ist innen dunkel und außen blau. Ein
  blauer Ring um einen fast weißen Knopf war kaum zu sehen, und genau diese
  Knöpfe sind die wichtigsten.
- **Die Seitenleiste trägt das App-Symbol**, nicht mehr ein gemaltes „N" auf
  oranger Fläche. Auf jeder anderen Nori-Plattform steht dort das Torii unter
  dem Schriftzug.
- **Die Startseite entsteht aus Signalen.** „Neu & beliebt" rechnet mit TMDBs
  Wochentrend, Beliebtheit (logarithmisch gedämpft), Aktualität und Bewertung;
  „Neue Episoden" kommt chronologisch aus Noris eigenem Kalender; „Für dich"
  aus Verlauf, Fortschritt, Merkliste und TMDBs Empfehlungen. Ohne genug
  Verlauf heißt die Reihe „Entdecke etwas Neues", und ohne TMDB heißt sie „Neu
  im Katalog" und sagt dazu, dass die Reihenfolge von der Quelle kommt.
  `catalog.items.slice(0, 24)` als „beliebt" gibt es nicht mehr.
- **Der Kopfbereich ist groß** — 44 rem auf der Startseite, 38 rem auf der
  Detailseite, mit Text **im** Bild statt darunter. Vorher schob eine
  Posterkachel sich mit −12 rem über ein 30 rem hohes Bild; auf dem Fernseher
  las sich das als Bruch mitten im Bild.
- **Der erste Fokus liegt im Inhalt**, nicht in der Seitenleiste. Die stand im
  Dokument vorn und bekam deshalb jeden Kaltstart — klappte auf und verdeckte
  den halben Kopfbereich, bevor eine Taste gedrückt war.
- **TMDB-Bilder gehen den kurzen Weg.** Sie verlangen keinen `Referer` und
  laufen deshalb nicht mehr über die Bildweiterreichung des Servers. Cover der
  Quellen weiter schon — die kommen nur mit passender Kopfzeile.
- **Der Bildspeicher ist versioniert** (`nori.tmdb.*.v2`). Die Zuordnungen des
  vorherigen Stands entstanden mit dem erstbesten Suchtreffer und sind
  teilweise falsch; sie werden beim ersten Start verworfen statt weiterbenutzt.
- **`reduceEffects` schaltet mehr ab**: neben `backdrop-filter` jetzt auch die
  Fokusübergänge, die Anhebung der Kacheln und das Flimmern der Platzhalter.
- **Das Paket ist ein klassisches Skript**, kein ES-Modul (`format: "iife"`,
  `modulePreload: false`, kein `crossorigin`, `type="module"` durch `defer`
  ersetzt). Das ist die folgenreichste Änderung an der Bauweise: ein
  webOS-Paket wird von `file://` geladen, und Chromium lädt von dort **keine**
  ES-Module — die Seite hat die Herkunft `null`. Auf dem Fernseher hätte das
  einen schwarzen Bildschirm ohne Fehlermeldung bedeutet, weil das Skript, das
  den Fehler melden würde, nie läuft. Die Stile bleiben eine eigene Datei
  (`cssCodeSplit: false`), sonst stünde der Startbildschirm unformatiert da.
- **Abstände ohne Flex-`gap`.** Chrome 79 — die Engine von webOS 6 — kennt
  `gap` nur im Raster, nicht im Flex-Layout; das kam erst mit Chrome 84. Noris
  Oberfläche benutzt es an gut vierzig Stellen, und ohne Rückfall klebte dort
  alles aneinander. Über `@supports` ist das nicht erfragbar (`@supports (gap:
  1px)` ist dort wahr, weil Rasterabstände existieren), also wird beim Start
  gemessen und ein Rückfall über Ränder eingeschaltet. Der Fernbedienungslauf
  prüft, dass er denselben Abstand erzeugt.
- **Das Prüfskript prüft mehr.** `tools/check-webos-package.py` vergleicht
  `appinfo.json`, `apps/webos/package.json`, den Paketnamen, die Dateien im
  Paket und den Changelog; es verlangt Symbole, Splashscreen und
  `packageinfo.json` im Paket und beanstandet in `dist/index.html` absolute
  Adressen, `type="module"` und `crossorigin`.

### Behoben

- **Die Detailseite lief in eine Endlosschleife**, sobald sie ähnliche Titel
  nachlud: `scopedCatalog()` gab bei jedem Aufruf ein neues Feld zurück, ein
  davon abgeleitetes `useMemo` rechnete deshalb bei jedem Rendern neu, und der
  Effekt daran setzte wieder Zustand. Der Fernseher reagierte danach auf keine
  Taste mehr. Der Katalogausschnitt ist jetzt ein stabiles Objekt.
- **Die Schemaversion stand doppelt.** Die Einstellungen zeigten „v4", der
  Fernbedienungslauf prüfte auf 4 — der Kern war längst bei v5. Beide lesen die
  Zahl jetzt aus `LIBRARY_SCHEMA_VERSION`.
- **Ein gescheitertes TMDB-Bild ließ die Kachel leer.** Jetzt fällt sie eine
  Stufe tiefer auf das Cover der Quelle und erst dann auf den Buchstaben.
- **„Bibliothek einlesen" hat den lokalen Stand ersetzt** und damit alles
  gelöscht, was nur auf diesem Fernseher stand. Es führt jetzt zusammen.
- **Der Kalender und der Verlauf zeigten Poster im Hochformat** für Folgen. Das
  sind jetzt 16:9-Standbilder, wo TMDB eines hat.
- **Die ausgeklappte Seitenleiste schnitt den Seitentitel ab.** Sie liegt über
  der Seite und schiebt sie absichtlich nicht; sichtbar blieb dadurch aber
  „auf" statt „Verlauf". Die Seite dahinter tritt jetzt in der Deckkraft
  zurück — dasselbe Bild liest sich damit als „Menü vorn" statt als
  abgeschnittener Text.
- **Die Detailseite behielt die Staffel des zuvor geöffneten Titels.** React
  Router tauscht bei gleichem Muster nur die Parameter aus; wer bei Detektiv
  Conan Staffel 7 wählte und dann Frieren öffnete, bekam Frieren „Staffel 7" zu
  sehen — samt Folgen, die es dort nicht gibt. Dasselbe galt für Bilder,
  Bewertung und ähnliche Titel.
- **„3 Staffeln" bei zwei Staffeln und einem Filmabschnitt.** „Filme" steht in
  derselben Liste, ist aber keine Staffel; gezählt werden jetzt nur die
  nummerierten.
- **Die große Folgennummer stand halbdurchsichtig über dem Standbild** und war
  je nach Bild lesbar oder nicht. Mit Standbild ist sie jetzt ein kleines
  Schild, ohne eines bleibt sie groß und füllt die leere Kachel.

- **Der Fokus geht nicht mehr verloren.** Bisher wurde nur nach einem
  Routenwechsel geprüft, ob überhaupt etwas fokussiert ist. Fällt ein
  Katalogabruf mitten im Betrieb weg, verschwindet aber die Reihe samt dem
  fokussierten Element — danach lag der Fokus auf `body`, und der Fernseher
  reagierte auf keine Taste mehr. Jetzt prüft ein Wächter alle 600 ms, und
  `Spotlight.focus` wird **nachgeprüft** statt nur aufgerufen: Spotlight nimmt
  den Fokus bei einem gerade eingehängten Container nicht immer an, ohne es zu
  sagen. Dasselbe galt für Drawer und Auswahlraster, wo sichtbar das Overlay
  stand und bedient wurde, was dahinter lag.
- **Die Suche faltet Akzente und Umlaute** (`normalizeTitle` aus dem Kern statt
  `toLowerCase`). Die Bildschirmtastatur hat kein Ä; „Damonenjager" trifft
  jetzt „Dämonenjäger".

### Nicht geprüft

- **Auf einem echten LG-Fernseher.** Der Lauf prüft dieselbe gebaute Datei in
  Chromium bei 1920 × 1080 mit echten LG-Tastencodes — und zusätzlich einmal
  **über `file://`**, den Weg, den der Fernseher nimmt. Die Wiedergabe eines
  echten HLS-Streams, das Zusammenspiel mit dem Systemplayer von webOS und das
  Verhalten der Magic Remote entscheiden sich erst auf dem Gerät.
- **Mit einem echten TMDB-Schlüssel.** Geprüft ist gegen einen Nachbau, der
  dieselben Antwortformen liefert — einschließlich der Fälle, die in der Praxis
  schiefgehen (Name ohne Gemeinsamkeit mit dem Quelltitel, versetzte
  Folgenzählung, Titel ohne TMDB-Eintrag, 401, 404, 429, Netzfehler).
- **Der Abgleich über Google Drive.** Er ist in derselben Zusammenführung nach
  webOS gekommen (eigener Abschnitt weiter unten) und im Fernbedienungslauf nur
  bis zur Einstellungsseite geprüft: dass der Abschnitt steht, sagt, was fehlt,
  und bedienbar ist. Der Geräteanmeldecode, der Drive-Abruf und das
  Zusammenführen über zwei echte Geräte sind hier **nicht** geprüft — die
  Regel selbst schon, gegen `config/sync-fixtures.json` und in beiden Kernen.

## [Unveröffentlicht] — TMDB-Metadaten

Fehlende Cover, Backdrops, Logos, Folgenbilder, Folgentitel und -beschreibungen
hatten nicht **eine** Ursache, sondern sechs voneinander unabhängige. Alle
wurden gegen die echte TMDB-Schnittstelle nachgewiesen, bevor etwas geändert
wurde.

### Behoben

- **Die Cover-Suche stellte nur eine einzige Anfrage.** `TMDBMatcher.queries`
  baut seit jeher eine Kette von Schreibweisen auf — die Cover-Suche benutzte
  sie nie, nur die Kennungssuche. Gemessen: „Attack on Titan Staffel 2" liefert
  bei TMDB **null** Zeilen, „attack on titan" vier. Die Kette wird jetzt
  abgearbeitet, der erste Treffer beendet sie. Für Titel, die schon vorher
  gefunden wurden, bleibt es bei einer Anfrage.
- **Alternativtitel erreichten die Cover-Suche gar nicht.** `detailsLoading`
  nahm keine entgegen; die Detailseite gab sie nur an Kennungs- und Logosuche
  weiter. Sie werden jetzt durchgereicht.
- **Anime unter ihrer Umschrift waren nicht auffindbar.** `/search/tv?query=
  Shingeki no Kyojin` liefert genau eine Zeile — die richtige (#1429) —, deren
  `name` „Attack on Titan" und deren `original_name` „進撃の巨人" ist. Zu
  keinem von beiden passt der Suchbegriff, also verwarf Nori den Treffer. Die
  Umschrift steht nur in `/tv/{id}/alternative_titles`; die werden jetzt
  nachgeladen, wenn die Kette nichts ergibt. Dasselbe galt für „Sousou no
  Frieren".
- **Ein fehlendes Poster kostete sämtliche Metadaten.** Die Cover-Suche verlangte
  ein Poster und verwarf sonst die ganze Zeile — mitsamt Breitbild,
  Beschreibung, Bewertung und vor allem der **TMDB-Kennung**, an der Logo und
  alle Folgendaten hängen. Übernommen wird jetzt, was dasteht.
- **Folgendaten fehlten, sobald die Quelle anders in Staffeln teilt als TMDB.**
  Gemessen: Jujutsu Kaisen ist bei TMDB **eine** Staffel mit 59 Folgen, AniWorld
  führt zwei — `/tv/95479/season/2` antwortet mit HTTP 404. Dasselbe bei
  Detektiv Conan (eine Staffel, 1213 Folgen) und Frieren. Neu ordnet
  `TMDBSeasonMap` die Folgen über ihre **Titel** zu und belegt den Versatz;
  lässt er sich nicht belegen, wird nichts zugeordnet.
- **Fehlgeschlagene Abrufe wurden wie gültige leere Daten abgelegt.** Jede
  Antwort ohne Folgen landete im `missed`-Satz, der auf die Platte wandert —
  auch eine Zeitüberschreitung, ein 429 und ein 401. Eine einzige
  Ratenbegrenzung schrieb eine Staffel damit dauerhaft ab. Neu unterscheidet
  `TMDBFailure`; nur HTTP 404 darf gemerkt werden, und auch das nur 14 Tage.
- **Einzelne Textlücken wurden nie gefüllt.** Die englische Fassung wurde erst
  geholt, wenn mehr als der **halben** Staffel die deutsche Beschreibung
  fehlte. Gemessen an Dan Da Dan, Staffel 1: 23 von 24 deutschen Texten
  vorhanden, der 24. blieb leer, obwohl der englische vorlag. Jetzt entscheidet
  jede Folge und jedes Feld für sich, und `airDate` und `runtime` werden beim
  Zusammenführen nicht mehr vergessen.
- **Der Sprachfilter für Logos hatte keinen Ausweg.** `include_image_language=
  de,en,null` kostet messbar Bilder — Jujutsu Kaisen 8 gefiltert gegen 30
  ungefiltert, Naruto 3 gegen 20, Demon Slayer 13 gegen 49. Ergibt der Filter
  nichts, wird jetzt ohne ihn gefragt. In der Rangfolge steht ein Logo **ohne**
  Sprachkennzeichen nun vor einem fremdsprachigen statt mit ihm auf einer Stufe.
- **„The Final Season" wurde zu „the" abgeräumt.** Ein Ausdruck in
  `stripVariants` griff vor dem, der den Artikel mitnimmt; übrig blieb
  „attack on titan the". Beide Kerne korrigiert.
- **webOS nahm den erstbesten TMDB-Treffer.** Die Fernseh-App suchte einmal und
  nahm `results.find((row) => row.backdrop_path)` — die erste Zeile mit einem
  Bild, ungeprüft. Sie benutzt jetzt dieselbe Bewertung wie die Apple-Apps, aus
  `@nori/core`.

### Hinzugefügt

- `shared/nori-core/src/tmdb/` — die TMDB-Zuordnung als zweiter Kern, mit
  denselben Testfällen wie auf der Swift-Seite.
- Ein `tmdb`-Abschnitt in `config/contract.json`: Bildgrößen, Titelschwelle,
  Suchkette, Sprachreihenfolgen, Logorangfolge, Staffelzuordnung und die Regel,
  welche Fehlschläge gemerkt werden dürfen.
- `NoriLog` — Protokollzeilen zur Fehlersuche, über `NORI_LOG` einzuschalten und
  standardmäßig aus. Sie tragen nie den API-Schlüssel und nie eine vollständige
  Anfrageadresse.

## [Unveröffentlicht] — Abgleich über Google Drive

Noch keine Version geschnitten: die App-Versionen stammen aus
`MARKETING_VERSION` der Xcode-Projekte und werden beim Release gesetzt.

### Hinzugefügt

- **Abgleich über Google Drive** zwischen iPhone, iPad, Mac und Fernseher.
  Ausschließlich im versteckten `appDataFolder` (Bereich `drive.appdata`) —
  die Dateien tauchen in „Meine Ablage" nicht auf, und mehr als diesen einen
  Bereich fordert Nori nicht an. Einrichtung: `docs/google-drive-sync.md`.
- **Eine Datei je Gerät** statt einer gemeinsamen. Jedes Gerät schreibt nur
  seine eigene und liest die der anderen; damit gehen gleichzeitige Änderungen
  auf zwei Geräten nicht mehr verloren.
- **Anmeldung je Plattform auf dem dafür vorgesehenen Weg:**
  `ASWebAuthenticationSession` auf iOS, Browser mit Loopback-Server auf macOS,
  Gerätecode auf dem Fernseher — dort mit großer Adresse, großem Code und
  sichtbarem Ablauf statt eines Wartekreisels.
- **„Dieses Gerät trennen" und „Google-Zugriff widerrufen"** als getrennte
  Handlungen. Das erste lässt Bibliothek, Drive-Dateien und die anderen Geräte
  unangetastet; das zweite betrifft alle Geräte an diesem Konto und fragt
  vorher.

### Geändert

- **Bibliotheksschema v6.** Jede Änderung trägt jetzt ihre eigene Marke: die
  Merkliste ist ein Zustand mit Grabsteinen statt einer Liste, Löschungen von
  Verlauf und Fortschritt hinterlassen einen Zeitpunkt, und jede Einstellung
  hat ihren eigenen Änderungsstempel. Bestehende Stände werden verlustfrei
  übernommen; die Migration ist getestet.
- **Der Fortschritt geht nicht mehr bei jeder Sekunde ins Netz.** Lokal wird
  weiter im Sekundentakt geschrieben, in die Cloud höchstens alle 25 Sekunden —
  und sofort bei Pause, Verlassen des Players und Wechsel in den Hintergrund.

### Behoben

- **`docs/synchronisation.md` behauptete, `drive.appdata` sei bei Google ein
  sensibler Bereich** und brauche eine Überprüfung, weshalb nur der Testmodus
  infrage komme. Das stimmt nicht: der Bereich gilt als nicht sensibel.

### Sicherheit

- Tokens liegen auf Apple im Schlüsselbund, nie in `library.json`, nie im
  Protokoll und nie in der Cloud. Client-IDs kommen aus Build-Einstellungen.
- Ein Fehler in OAuth, Drive, Netz, Parsing oder Schema führt unter keinen
  Umständen dazu, dass lokal etwas gelöscht wird. Ein unlesbarer Fremdstand
  wird übergangen, ein neuerer Schemastand hält den Upload an, und ohne Netz
  läuft Nori vollständig weiter.

## [iOS 1.20.0] — 2026-09-12

Die Startseite ist neu gebaut, nicht überarbeitet. Vorlage ist derselbe Entwurf
wie bei der Detailseite, diesmal als `nori-home-v2.html`; übernommen sind daraus
Aufbau, Größenverhältnisse und Anmutung, nicht seine Beispieldaten. Der zweite,
größere Teil steckt darunter: die Reihen hießen „Beliebte Titel" und „Schau
weiter", aber nur eine davon stimmte. Sie entstehen jetzt aus echten Signalen
und sind prüfbar.

### Hinzugefügt

- **Ein cinematischer Kopfbereich** über rund drei Viertel des Bildschirms:
  Artwork bis unter die Statusleiste, darauf Schriftzug, Eckdaten, Beschreibung
  und drei Knöpfe. Der gezeigte Titel wechselt täglich und wird aus Trend,
  Beliebtheit und Aktualität bestimmt — nicht gewürfelt und nicht der erste
  Eintrag des Alphabets.
- **„Neu & beliebt" mit echter Bedeutung.** Die Reihenfolge entsteht aus
  TMDBs Wochentrend, Beliebtheit (logarithmisch gedämpft), Aktualität und
  Bewertung — Letztere erst ab fünfzig Stimmen, damit 10,0 aus zwei Stimmen
  nicht vor einer weltweit laufenden Serie steht.
- **„Neue Episoden"** aus Noris eigenem Kalender, chronologisch, die neueste
  zuerst. Ausdrücklich nicht nach Beliebtheit sortiert.
- **„Für dich"** aus Verlauf, Fortschritt und Merkliste, angereichert um
  TMDBs Empfehlungen zu den meistgesehenen Titeln. Ohne genug Signal heißt die
  Reihe „Entdecke etwas Neues" und zeigt Bestbewertetes — „Für dich" über einer
  Beliebtheitsliste wäre eine Behauptung.
- **Abzeichen auf den Kacheln** — „NEU" und „TOP 10" — ausschließlich aus
  echten Signalen.
- **`TMDBCatalog`**: Trend-, Beliebtheits- und Ausstrahlungslisten mit
  Zwischenspeicher auf der Platte und eigenen Fristen je Liste (Trend sechs
  Stunden, Dauerliste drei Tage, Empfehlungen eine Woche).
- **`TMDBMatcher`** und **`TMDBImages`** im gemeinsamen Kern: die Zuordnung
  Nori ↔ TMDB und die Bildadressen liegen an einer Stelle statt verstreut.
- **45 neue Tests** für Zuordnung und Rangfolge — Schreibweisen, deutsche und
  englische Titel, Staffelzusätze, gleichnamige Serien, Sonderzeichen, sowie
  alter Trendtitel gegen neuen Unbekannten, Bewertung mit wenigen Stimmen und
  die Frage, ob ein Titel bei Nori überhaupt verfügbar ist.
- **TMDB-Nachweis** am Fuß der Startseite, wie die Nutzungsbedingungen es
  verlangen.

### Geändert

- **Die Startseite bekommt den vollständigen Katalog**, nicht den nach Bereich
  ausgeschnittenen. Sie hat keinen Umschalter, also wäre ein Ausschnitt dort
  nicht erklärbar. Katalog, Kalender und Merkliste schneiden weiter zu.
- **Die Rangfolge liegt in `NoriCore`**, nicht in einem SwiftUI-Body. Dadurch
  läuft sie einmal statt bei jedem Neuzeichnen und lässt sich prüfen.
- **Die Startseite erscheint sofort**: erst aus Noris Daten und dem
  TMDB-Zwischenspeicher, dann still ergänzt. Kein Ladeskelett über Sekunden.
- **Die Titelzuordnung zu TMDB** berücksichtigt jetzt Jahr, Staffelzusätze
  („Staffel 2", „Final Season", „2nd Season"), Akzente und Sonderzeichen.
  Beliebtheit bleibt reiner Stichentscheid und kann keinen Treffer erzeugen.
- **Der Suchknopf** der Startseite öffnet Noris vorhandene Suche im Katalog,
  statt eine zweite aufzubauen.
- **Posterbilder in passender Auflösung**: eine 132 Punkte breite Kachel lud
  bisher ein 780 Pixel breites Poster.

### Entfernt

- **Die bisherige Startseiten-Oberfläche vollständig** — Kopfbereich als
  blätterbares Karussell, Kachelreihen mit Titel im Bild, Fortschrittskacheln,
  Genre-Gruppierung im View und die Abstände drumherum.
- **Die Bereichspillen („Alle | Anime | Serien | K-Drama")** auf der
  Startseite. Der Umschalter selbst bleibt in Katalog, Kalender und Merkliste
  und liegt jetzt in `Sources/UI/ScopeSwitch.swift`.
- **Die Reihe „Beliebte Titel"** — sie zeigte die ersten zwanzig Einträge des
  alphabetisch sortierten Katalogs.

## [iOS 1.19.0] — 2026-09-11

Die Serien- und Animedetailseite ist neu gebaut, nicht überarbeitet. Vorlage
ist ein Entwurf, der als HTML vorlag; übernommen sind daraus Aufbau,
Größenverhältnisse und Anmutung, nicht seine Zahlen und erst recht nicht seine
Beispieldaten. Daten, Fortschritt, Provider und Wiedergabe bleiben unverändert
Nori — ersetzt wurde ausschließlich, was man sieht.

### Hinzugefügt

- **Ein Kopfbereich über die volle Breite**, bis unter die Statusleiste und
  hinter die Navigationsleiste. Darauf stehen Schriftzug, Eckdaten,
  Beschreibung und die beiden Knöpfe — vorher lag daneben ein kleines Poster
  und rechts eine Textspalte.
- **Der Titel als gestalteter Schriftzug**: das freigestellte Logo von TMDB,
  wo es eines gibt, sonst der Titel in Serifen und groß. Der Rückfall ist der
  Normalfall, nicht die Ausnahme — die wenigsten Serien haben ein Logo.
- **Eine Zeile Eckdaten** aus Jahr, Genres, Staffelzahl, Stand und Bewertung.
  Was fehlt, fällt samt Trenner weg; leere Trennpunkte gibt es nicht.
- **Die Beschreibung steht sofort da**, vier Zeilen, der Rest hinter „Mehr
  anzeigen“. Der Knopf erscheint nur, wo es wirklich etwas aufzuklappen gibt.
- **Folgen als Karten mit 16:9-Standbild**, Nummer und Titel, darunter Datum,
  Laufzeit und Sprache. Fehlt ein Standbild, steht dort das Artwork der Serie
  stark abgedunkelt, erst danach Noris eigener Rückfall.
- **Die Laufzeit einer Folge** — `EpisodeInfo.runtime`. Sie steht in derselben
  TMDB-Antwort wie Titel und Standbild und kostet keine zusätzliche Anfrage.
- **Ein Fortschrittsring** an jeder Folge: leer, teilweise gefüllt oder
  gefüllt mit Haken. Der Haken ist eine Form und nicht nur eine andere Farbe.
- **Ein Überlaufmenü oben rechts** mit Teilen, „Von vorn abspielen“, „Staffel
  als gesehen markieren“, dem Verwerfen des Staffelfortschritts sowie Quelle,
  Freigabe und Alternativtiteln zum Nachlesen.
- **Ein Schimmer in der Farbe des Artworks** hinter Titel, Fortschrittsring
  und Fortschrittsstreifen. Abgetastet wird mit `CoverToneSampler`, und die
  Farbe wird auf eine Helligkeit gezogen, die auf dunklem Grund trägt — sonst
  wäre ein Ring aus einem düsteren Cover unsichtbar. Die Seite selbst bleibt
  dunkel.

### Geändert

- **Die Staffel ist ein Auswahlmenü**, daneben die Zahl der Folgen. Vorher
  eine Liste aus Staffelzeilen, von denen eine ihre Folgen aufklappte — ein
  Zwischenschritt zwischen „Staffel 2“ und der zweiten Folge darin.
- **Das Artwork wird nicht mehr blind mittig zugeschnitten.** Ein Breitbild
  bekommt einen flacheren Streifen als ein Poster, damit von ihm das meiste
  stehen bleibt, und der Zuschnitt sitzt oberhalb der Mitte, wo Gesichter und
  Schriftzüge stehen. Darunter füllt dieselbe Aufnahme unscharf weiter, so
  dass zwischen Bild und Seite keine Kante bleibt.
- **Die Quelle einer Serie merkt sich, woher sie tatsächlich kam.** Weicht das
  Laden auf die zweite Seite aus, liefen vorher Bildabruf, Fortschritt und
  Wiedergabe weiter gegen die Seite, die gar nicht geantwortet hatte.
- Beim Staffelwechsel bleibt die bisherige Liste stehen und blendet nur ab,
  statt zu verschwinden — die Seite fällt nicht mehr bei jedem Wechsel kurz in
  sich zusammen.
- Der abgelegte Stand der Folgendaten (`episodes.json`) wird einmalig
  verworfen, damit die Laufzeit auch für bereits geholte Staffeln nachkommt.

### Entfernt

- **Der Umschalter „Details | Folgen“.** Die Details stehen jetzt oben, ein
  Tipp weniger.
- **Der Abschnitt „Als Nächstes“.** Welche Folge weitergeht, sagt der
  Hauptknopf, und dieselbe Folge trägt in der Liste das Abspielzeichen.
- **Der zweite Merken-Knopf.** Es gibt nur noch den einen unter der
  Beschreibung; oben stehen ausschließlich Zurück und das Überlaufmenü.
- `EpisodeRow` und `EpisodePlaceholder` — sie gehörten zur alten Detailseite
  und werden nirgends sonst benutzt.

## [iOS 1.18.0] — 2026-09-09

Redesign der Oberfläche nach dem Vorbild von
[Shirox](https://github.com/xibrox/Shirox). Gestaltung, Bewegung und Bedienung
kommen von dort; Architektur, Provider, Datenmodell und Wiedergabelogik
bleiben unverändert Nori. Was übernommen und was nachgebaut ist, steht in
`docs/apple-redesign.md`, die Lizenzhinweise in `THIRD-PARTY-NOTICES.md`.

### Hinzugefügt

- **Doppeltipp springt zehn Sekunden**, links zurück, rechts vor. Mehrere
  schnelle Tipper werden zusammengefasst: viermal rechts zeigt „+40 s“ und
  springt einmal um 40 Sekunden.
- **Qualitätsauswahl** — aber nur, wenn der Stream tatsächlich mehrere Stufen
  anbietet. Die Stufen werden aus der HLS-Master-Playlist gelesen und über
  `preferredPeakBitRate` durchgesetzt. Liefert ein Hoster eine einzelne Spur,
  erscheint die Auswahl gar nicht.
- **Nächste Folge** als Knopf in der Bedienleiste, nicht nur am Folgenende.
- **Bild einpassen oder füllen** — im Querformat bleiben sonst breite schwarze
  Balken stehen.
- **Abspielknopf auf der Detailseite**: „Weiter · Folge 7“ beziehungsweise
  „Folge 1 abspielen“, nach derselben Regel wie „Schau weiter“. Bisher ließ
  sich eine Serie dort nur über die Folgenliste starten.
- **Liquid Glass** ab iOS 26 für Player-Bedienung, Bereichspillen und
  Merken-Knopf, mit klassischem Rückfall darunter und einem Schalter unter
  Einstellungen › Darstellung.
- **Zeigerrückmeldung und Kontextmenü** auf den Kacheln — für iPad mit
  Trackpad.
- Haptik an wenigen Stellen: Merkliste, Play/Pause, Sprung.

### Geändert

- **Neues App-Symbol** — Torii, Sonnenuntergang und 「ノリ」 auf nahezu
  Schwarz. Es löst das serifige „N“ auf allen Plattformen ab; Master ist
  `assets/branding/nori-app-icon.png`, alle Größen entstehen daraus mit
  `tools/make-app-icons.py`.
- **Der Kopfbereich läuft von Kante zu Kante** bis unter die Statusleiste, mit
  Parallaxe beim Blättern, Dehnung beim Herunterziehen, Verlauf in den
  Hintergrund, Schriftzug, Genres und zwei Knöpfen. Vorher eine 250 Punkte
  hohe Karte mit Rand.
- **Kacheln tragen den Titel im Bild** statt darunter. Die Reihen bleiben
  dadurch gleich hoch — ein zweizeiliger Titel neben einem einzeiligen
  verschob vorher die ganze Zeile — und das Artwork bekommt die Fläche.
- **Der Player besteht aus acht Dateien statt einer.** Die Bedienung bleibt
  aufgebaut und wird ein- und ausgeblendet, statt bei jedem Antippen verworfen
  zu werden; sie kommt oben und unten herein, die Mitte wächst auf.
- **Alle Wiedergabeoptionen in einer Glasgruppe** — Hoster, Qualität, Sprache,
  Untertitel, Geschwindigkeit, nächste Folge. Angezeigt wird nur, was es
  wirklich gibt.
- **Der Fortschrittsregler folgt beim Ziehen dem Finger** statt erst beim
  Loslassen zu springen, und zeigt Puffer und Restzeit.
- **Das automatische Ausblenden** berücksichtigt jetzt auch offene Menüs und
  das Ziehen am Regler, nicht mehr nur VoiceOver und Pause.
- **Ein gemeinsames Bewegungssystem** statt verstreuter Einzelwerte.
  „Bewegung reduzieren“ schaltet Parallaxe, Dehnung und räumliche Übergänge
  ab, ohne dass eine Funktion verlorengeht.
- Die Fehleransicht des Players bietet „Anderen Hoster versuchen“ als
  Hauptknopf an — bei diesen Quellen ist das der Alltag, nicht die Ausnahme.

### Behoben

- **Das Play/Pause-Symbol sprang beim Puffern hin und her**, und die Bedienung
  blendete dabei nicht mehr weg. `timeControlStatus == .playing` ist während
  des Nachladens falsch; gemeint war „läuft, oder will laufen“.
- **Die Hosterliste flackerte**, solange sie offen war: ein SwiftUI-`Menu`
  schließt und öffnet sich bei jedem Neuzeichnen des Rumpfs, und der zeichnet
  viermal pro Sekunde neu. Die Menüs laufen jetzt über UIKit.
- **Der Hosterwechsel warf die Ansicht auf den Ladebildschirm zurück** — die
  eben benutzte Auswahl war mitsamt Leiste weg, der Regler sprang auf null.
  Leisten, Titel und Fortschritt bleiben jetzt stehen.
- **Kacheln blendeten beim Zurückscrollen erneut auf**, als würden sie neu
  geladen. Ein Bild blendet jetzt nur beim ersten Mal auf.
- **Im Querformat füllte der Kopfbereich den ganzen Bildschirm**, und das
  Kopfbild der Detailseite war höher als das Gerät — die Seite begann
  unterhalb des sichtbaren Bereichs.
- Fehlende Standbilder zeigen Nummer und Filmstreifen statt eines leeren
  dunklen Rechtecks.

## [macOS 1.15.0] — 2026-09-09

Die Mac-Fassung bleibt Desktop-Bauform — Seitenleiste, Hover, Kontextmenüs,
eigenes Player-Fenster. Übernommen ist, was plattformübergreifend gilt.

### Hinzugefügt

- **Liquid Glass** ab macOS 26 für die Karussellpfeile und den Merken-Knopf,
  mit klassischem Rückfall darunter und einem Schalter unter Einstellungen ›
  Allgemein.

### Geändert

- **Neues App-Symbol**, dasselbe wie auf dem iPhone. Randlos und quadratisch
  hinterlegt: die abgerundete Form kommt vom System, nicht aus dem Bild.
- **Ein gemeinsames Bewegungssystem**: dieselben Kurven wie auf dem iPhone,
  statt drei eigener Dauern. „Bewegung reduzieren“ wird überall ausgewertet.
- Abschnittsüberschriften mit Akzentbalken, Druckstil mit dezenter
  Verkleinerung.

### Behoben

- **Kacheln blendeten beim Zurückscrollen erneut auf**, als würden sie neu
  geladen.

## [iOS 1.17.2] — 2026-09-08

### Behoben

- Ausdrücklich gewählte Sprache und Hoster werden nicht mehr still durch eine
  andere Auswahl ersetzt. Der automatische Start behält seine Rückfälle.
- Die Hoster-Auswahl zeigt nur Angebote der aktuellen Sprache. Einstellungen
  werden erst nach erfolgreicher Stream-Auflösung gespeichert.
- Die Fehlerkorrektur und zwei Regressionstests stammen aus der lokalen Kopie;
  die aktuelle Player-Oberfläche bleibt bestehen.

## [iOS 1.17.1] — 2026-09-08

### Behoben

- Den iOS-Stand 1.17.0 aus dem bisherigen Android-Arbeitsbranch in die aktuelle
  Feature-Struktur und den zentralen NoriCore integriert.
- Die Fortschrittsanzeige auf der Detailseite verwendet die Quelle des Titels,
  auch wenn die gespeicherte Vorgabequelle auf den anderen Katalog zeigt.
- Regressionstest für Fortsetzen und Fortschrittsanzeige bei abweichender Vorgabequelle.

## [iOS 1.17.0] - 2026-09-07

### Geaendert

- **Die Detailseite folgt dem Aufbau von Serien-Apps.** Statt Poster-Kachel
  neben dem Titel traegt jetzt ein grosser Backdrop den Kopf, mit dem
  freigestellten TMDB-Schriftzug darueber. Darunter zwei Zeilen Eckdaten —
  Jahr und Genres, dann Staffelzahl, Stand und Bewertung.
- **Merkliste als Pille, dazu ein Ueberlaufmenue** („Von vorn abspielen",
  „Fortschritt dieser Staffel vergessen"). Das Herz in der Navigationsleiste
  entfaellt.
- **Umschalter Details / Folgen.** Beschreibung, Alternativtitel, FSK und
  Quelle stehen unter „Details" und draengen sich nicht mehr zwischen Kopf
  und Folgenliste.
- **„Als Naechstes"** zeigt die kommenden Folgen als waagerechte Karten mit
  Standbild — beginnend bei der Folge, die `nextPlay` bestimmt.
- **„Alle Folgen"** listet die Staffeln; die gewaehlte klappt ihre Folgen
  darunter auf. Frueher war die Staffelwahl eine Knopfreihe und die
  Folgenliste stand lose darunter.

### Bekannte Abweichung von der Vorlage

- Die Staffelzeilen tragen **kein Vorschaubild**. TMDB liefert Staffelposter
  nur teilweise, und die Quellen gar nicht; dieselbe Serienkachel an jeder
  Zeile waere Wiederholung statt Auskunft.

## [iOS 1.16.1] - 2026-09-07

### Behoben

- **Das Oeffnen eines Titels aenderte die Vorgabequelle.** Merkliste und
  Detailseite setzten `library.provider` auf die Quelle des geoeffneten
  Titels — ein Ueberbleibsel aus der Zeit, als der Umschalter ein
  Moduswechsel war. Seit die Bibliothek beide Quellen zusammenfuehrt, ist das
  schaedlich: `source(of:)` faellt fuer Eintraege ohne eigene Quellangabe auf
  `library.provider` zurueck, und die Merkliste teilt danach in „Anime" und
  „Serien" auf. Ein einziges Oeffnen verschob damit fremde Eintraege zwischen
  den Abschnitten. Nachweisbar an einer gespeicherten Bibliothek, in der
  `provider` auf einer Quelle stand, die der Nutzer nie gewaehlt hatte.

### Entfernt

- **Die Einstellung „Vorgabequelle".** Was in den Listen steht, entscheidet
  seit 1.15.0 der Bereich; die Quelle eines einzelnen Titels steht am Eintrag
  selbst. Damit blieb der Schalter ohne erkennbare Wirkung — und wer ihn
  umstellte, veraenderte still, in welchem Abschnitt der Merkliste alte
  Eintraege ohne Quellangabe landen. Das Feld bleibt im Datenmodell als
  Rueckfall erhalten, ist aber nicht mehr bedienbar.

### Sonstiges

- Der gewaehlte Bereich ueberlebt den Neustart. Das tat er schon seit 1.15.0
  — geprueft, nicht angenommen: `scope` steht in `library.json`, und nach
  Beenden und Neustart stand die Auswahl unveraendert.

## [iOS 1.16.0] - 2026-09-07

### Hinzugefuegt

- **Bereichspillen ueber der Startseite.** Alle, Anime, Serien, K-Drama
  stehen jetzt direkt im Inhalt statt im Menue der Navigationsleiste. In den
  uebrigen Tabs bleibt es beim Menue - eine Pillenreihe ueber jeder Ansicht
  waere nur Wiederholung.
- **Schriftzuege aus TMDB.** Der Kern holt ueber `/tv/{id}/images` das
  freigestellte Logo einer Serie und legt es im Cover-Index ab. Es kostet
  einen eigenen Abruf - `/search/tv` liefert es nicht mit - und wird deshalb
  nur dort geholt, wo es sichtbar wird: im Kopfbereich und auf den
  Weiterschauen-Kacheln. Deutsch vor Englisch vor sprachlos, PNG vor SVG
  (SVG kann `AsyncImage` nicht darstellen).

### Geaendert

- **Der Kopfbereich ist nur noch Bild.** Breitbild statt Poster, der
  freigestellte Schriftzug unten links, und die ganze Flaeche fuehrt beim
  Antippen zur Serie. Titel, Quelle, Genres, Beschreibung und zwei Knoepfe
  sind weg - das war ein Steckbrief, kein Kopfbereich, und alles davon steht
  eine Ebene tiefer ohnehin. Von 560 auf 250 Punkte Hoehe: die Startseite
  beginnt wieder oben statt unter dem Kopfbereich. Der Titel als Text bleibt
  der Rueckfall, denn viele Serien haben bei TMDB kein Logo - ohne Titelzeile
  darunter waere der Kopfbereich sonst namenlos.
- **Die Weiterschauen-Kacheln stehen im Querformat**, mit Backdrop als Bild,
  Logo unten links und dem Fortschritt als Streifen **im** Bild. Darunter die
  Restzeit - "Noch 14 Min." sagt, worauf man sich einlaesst, ein Prozentwert
  nicht.
- **Antippen spielt sofort ab.** Vorher fuehrte die Kachel auf die
  Detailseite. Jetzt entscheidet `nextPlay` im Kern: die zuletzt angefangene
  Folge, solange sie nicht zu Ende gesehen ist - sonst die naechste
  unfertige. Solange die Serie geholt wird, liegt ein Fortschrittsring auf
  der Kachel; ohne den wirkte das Antippen tot.

### Behoben

- **`nextPlay` nahm die Vorgabequelle statt der Quelle des Titels.** Seit die
  Bibliothek beide Quellen zusammenfuehrt, ist ein Titel der *anderen* Seite
  der Normalfall - die Fortschrittssuche griff dann daneben und begann von
  vorn. Die Quelle wird jetzt uebergeben; ohne Angabe bleibt es beim alten
  Verhalten.

### Sonstiges

- `tools/check-apple-sources.py` kennt `NoriTheme.danger`. Ein erfundenes
  Symbol in einem ViewBuilder meldet der Compiler nicht als "has no member",
  sondern als `failed to produce diagnostic for expression` mit Spalte auf
  `some View` - das sieht nach einem zu komplexen Ausdruck aus und fuehrt in
  die Irre. Hat hier drei Build-Durchlaeufe gekostet.

## [iOS 1.15.0] – 2026-09-07

### Hinzugefügt

- **Bereich „K-Drama" auf dem iPhone.** Der Umschalter oben rechts wählt jetzt
  einen Ausschnitt der Bibliothek: Alle, Anime, Serien oder K-Drama. Die
  koreanischen Serien führt Serienstream selbst unter diesem Genre — rund
  hundert Titel, die vorher nur über die Suche zu finden waren. Katalog,
  Startseite und Kalender folgen dem Bereich.

### Geändert

- **iOS lädt beide Kataloge und führt sie zusammen.** Bisher wurde nur der
  Katalog der aktiven Quelle geholt, eine Liste konnte also nie Titel beider
  Seiten enthalten — „Alle" war damit nicht darstellbar und „K-Drama" erst
  recht nicht. Der Mac macht es seit 1.12.0 genauso. Fällt eine Quelle aus,
  zeigt die App die andere weiter, statt leer zu bleiben.
- **Der Umschalter ist ein Menü statt eines segmentierten Reglers.** Auf dem
  Mac sitzt er als Segmentregler in der Seitenleiste, wo Platz ist; in einer
  iPhone-Navigationsleiste sind vier Segmente zu viel — „K-Drama" allein
  braucht mehr Breite als die beiden alten Segmente zusammen, und mit Dynamic
  Type wird daraus abgeschnittener Text. Das Menü bleibt gleich breit, egal
  wie viele Bereiche dazukommen.
- **Der Kalender führt beide Quellen zusammen** und filtert im
  K-Drama-Bereich über die Slugs des Katalogs mit: ein Kalendereintrag trägt
  Slug und Quelle, aber keine Genres. Steht der Katalog noch nicht, wird
  bewusst nicht eingeschränkt — ein vollständiger Kalender ist die bessere
  Antwort als ein leerer.
- In den Einstellungen heißt „Aktive Quelle" jetzt **„Vorgabequelle"**. Sie
  entscheidet nur noch, wohin ein Titel ohne eigene Quellangabe führt; was in
  den Listen steht, bestimmt der Bereich.

## [webOS 1.0.0] – 2026-09-07

Erste Fassung von **Nori für LG webOS**. Eine eigenständige TV-App, keine auf
den Fernseher gezogene Webseite: vollständig mit der Fernbedienung bedienbar,
auf 1920 × 1080 ausgelegt und auf andere Auflösungen mitskalierend.

**Für iOS, macOS und Windows ändert sich nichts.** Kein Swift wurde angefasst,
`server/` und `desktop/` bleiben unberührt.

### Hinzugefügt

- **`shared/nori-core`** — der gemeinsame Kern für JavaScript-Clients. Die
  TypeScript-Entsprechung von `native/NoriCore/`; maßgeblich ist für beide
  `config/contract.json`: dieselben Feldnamen, dieselbe
  90-%-Regel, dieselbe Resume-Schwelle, derselbe Schlüssel
  `provider|episodePath`, dieselbe Hoster-Rangfolge. Eine `library.json` aus
  der iOS- oder macOS-App liest sich dort ohne Umschreiben. 34 Tests laufen
  gegen dieselben HTML-Ausschnitte wie `native/Tests/NoriCoreTests`.
- **`services/nori-api`** — die Provider-Schicht als HTTP-Dienst. Der Grund ist
  keine Bequemlichkeit: viele Hoster liefern nur mit einer `Referer`-Kopfzeile
  aus, und die darf ein Browser nicht setzen. Der Dienst holt Katalog, Serie,
  Folge und Kalender, löst den Hoster auf und reicht den Stream weiter;
  HLS-Playlists werden dabei umgeschrieben, damit auch die Segmente über ihn
  laufen. Die Weiterreichung lässt nur durch, was `isSafeRemoteURL` aus dem
  Kern passieren lässt — dieselbe Prüfung wie in den Apple-Apps.
- **`apps/webos`** — die TV-Oberfläche. React, TypeScript, Enact Spotlight für
  die Fernbedienung, hls.js als Rückfall, gebaut mit Vite auf Chrome 79 (die
  Engine von webOS 6). Startseite mit Hero und Reihen, Entdecken mit Genre- und
  Sortierfiltern, TV-taugliche Suche, Kalender, Merkliste, Verlauf,
  Einstellungen, Detailseite mit Staffeln und Folgen, und ein Vollbild-Player.
- **Fokusgedächtnis.** Wer den siebten Titel einer Reihe öffnet und zurückgeht,
  steht wieder auf dem siebten. Spotlight kann das je Container, verliert es
  aber beim Ausbau der Seite — Nori merkt sich deshalb zusätzlich den Schlüssel
  des zuletzt fokussierten Elements je Route und Bereich.
- **Zurück-Taste als Stapel.** Der oberste angemeldete Griff gewinnt: im Player
  erst den Drawer schließen, dann die Bedienung, dann erst den Player
  verlassen. Auf der Startseite verlässt Zurück die App.
- **Player** mit ausblendender Bedienung (3–8 s, einstellbar), Seekbar samt
  Pufferbereich, ±5/10/15/30 s (bei gehaltener Taste schneller), vorheriger und
  nächster Folge, rechtem Drawer für Sprache, Hoster, Staffel und Folgen,
  Resume-Frage ab acht Sekunden, Countdown zur nächsten Folge und vollständigem
  Abbau beim Verlassen.
- **Hosterwechsel im Betrieb.** Position merken, neuen Hoster auflösen, Stream
  laden, Position wiederherstellen. Scheitert ein Stream, bietet der Player den
  nächsten Hoster an, statt den Player zu verlassen.
- **Cover-Beschaffung wie im Swift-Kern.** Die Katalogseiten beider Quellen
  sind reine Titellisten; die Adresse des Covers steht nur auf der Detailseite
  und enthält einen Zufallsanteil. Nori lädt sie bei Bedarf nach, höchstens
  vier gleichzeitig, und legt sie dauerhaft ab.
- **Eigenes Symbol und Startbild**, aus dem Nori-Zeichen erzeugt
  (`apps/webos/tools/make-assets.mjs`) — kein fremdes Material im Paket.
- **`npm run webos:package`** schnürt das `.ipk` ohne LG-SDK (ar plus tar von
  Hand). `webos:install`, `webos:launch` und `webos:inspect` benutzen das SDK,
  wenn es vorhanden ist, und sagen sonst, wie man es bekommt.
- **`tools/check-webos-package.py`** prüft Quelltext und fertiges Paket auf
  Namen und Adressen fremder Apps und validiert `appinfo.json` gegen die Liste
  der Felder, die webOS tatsächlich kennt.
- **`.github/workflows/build-webos.yml`** baut Kern, Server und App, schnürt
  das Paket, prüft es und legt es als Artefakt ab. Auf demselben self-hosted
  Mac wie alle anderen Läufe. Er braucht kein Xcode, nur Node — und ist damit
  der einzige Lauf des Projekts, der eine Änderung wirklich durchbaut und
  testet, statt sie nur statisch zu prüfen.

### Bekannte Einschränkungen

- Auf einem echten Fernseher ist der Stand nicht erprobt.
- Kein Abgleich zwischen Geräten; die Bibliothek liegt im `localStorage` des
  Fernsehers, im Format von `library.json`.
- Keine Sprungmarken für Intro, Recap und Ending — Nori hat dafür keine Daten,
  und erfundene Zeitmarken wären schlechter als keine.

## [iOS 1.14.5] · [macOS 1.14.2] – 2026-09-06

**Für iPhone und Mac ändert sich nichts Sichtbares.** Der geteilte Kern baut
jetzt auch für Android durch; auf Apple ist die Änderung wirkungslos.

### Geändert

- **`FoundationNetworking` wird bedingt importiert.** Außerhalb von Apple
  liegen `URLSession`, `URLRequest`, `HTTPURLResponse` und `HTTPCookieStorage`
  in einem eigenen Modul. `AniworldClient.swift` und `HosterResolver.swift`
  holen es über `#if canImport(FoundationNetworking)` — dieselbe Kapselung,
  die dort schon für `Security` und `ImageIO` steht. Auf Apple gibt es das
  Modul nicht, der Import ist damit ein Nichts; für Android war er der
  Unterschied zwischen 50 Fehlern und einem grünen Build.

### Behoben

- **`tools/require-swift-android.sh` meldete grün, wo nichts ging.** Es prüfte
  nur, ob `swift sdk list` einen Android-Eintrag zeigt. Zwei Einrichtungs-
  fehler kamen dadurch erst im Build heraus, und dort sahen beide nach
  kaputtem Quelltext aus: eine Toolchain in der falschen Version (die aus
  Xcode taugt für Cross-Compilation nicht) und ein SDK, das nie gegen ein NDK
  eingerichtet wurde (`'semaphore.h' file not found`, mitten in SwiftSoup).
  Beides wird jetzt vorher geprüft und mit dem nötigen Befehl gemeldet.
- **`build-android.yml` baute mit der Toolchain aus Xcode.** Der Lauf wählt
  jetzt die zum SDK passende Open-Source-Toolchain über `TOOLCHAINS` aus.
  Dazu musste die Schrittfolge umgedreht werden: erst SDK, dann Toolchain,
  dann prüfen.

### Sonstiges

- `docs/android.md`: Die Einrichtungsanleitung nennt jetzt alle vier Schritte
  statt zwei — die beiden fehlenden waren genau die, die stillschweigend
  schiefgingen. Punkt 1 des Fahrplans („Übersetzt der Kern für Android?") ist
  beantwortet: **ja.** Die Kotlin-Rückfallebene entfällt.

## [iOS 1.14.4] · [macOS 1.14.1] – 2026-09-06

### Hinzugefügt

- **Bereich „K-Drama“ (macOS).** Der Umschalter in der Seitenleiste hat ein
  viertes Segment: Anime, Serien, K-Drama, Alle. Es zeigt die koreanischen
  Serien, die Serienstream unter dem Genre „K-Drama“ auf
  `/serien?by=genre` selbst führt — rund hundert Titel, die bisher nur über
  den Umweg „Kategorien“ zu finden waren. Katalog, Startseite und Kalender
  folgen dem Bereich.

### Geändert

- **Ein Bereich ist nicht mehr gleichbedeutend mit einer Quelle.**
  `LibraryScope` war bisher eine Umbenennung von `CatalogProvider`: jeder
  Bereich hatte genau eine Seite, und `provider` allein reichte zum Filtern.
  K-Drama ist keine dritte Seite, sondern ein Ausschnitt aus einer
  bestehenden. Der Bereich trägt deshalb jetzt ein Paar aus Quelle und
  `genre`, und Katalogeinträge laufen über `includes(item:)`, das beides
  prüft. Für „Alle“, „Anime“ und „Serien“ ändert sich dadurch nichts —
  festgehalten in `LibraryScopeTests`.
- **Der Kalender filtert im Genre-Bereich mit.** Ein Kalendereintrag trägt
  Slug und Quelle, aber keine Genres; ohne den Umweg über den Katalog hätte
  „K-Drama“ den vollständigen Serienstream-Kalender gezeigt. Steht der
  Katalog noch nicht, wird bewusst nicht eingeschränkt: ein vollständiger
  Kalender ist die bessere Antwort als ein leerer.

## [macOS 1.14.0] – 2026-09-06

### Hinzugefügt

- **Rasteransicht in Kalender und Merkliste.** Der Katalog konnte das schon
  länger; die beiden anderen Ansichten waren auf Liste festgelegt.
  Umgeschaltet wird über die Fensterleiste — auf dem Mac der erwartete Ort
  für einen Darstellungsschalter, anders als auf dem iPhone, wo er über dem
  Inhalt sitzt.
- Die Wahl bleibt je Ansicht erhalten. Der Kalender startet auf **Liste**,
  weil dort zählt, wann etwas kommt; Katalog und Merkliste auf **Raster**.
- In der Merkliste entfernt ein Kontextmenü auf der Kachel den Eintrag — in
  der Liste tut das weiterhin der Knopf am Zeilenende.

### Geändert

- `CatalogLayout` heißt jetzt `NoriViewMode` und liegt in `Theme.swift`. Drei
  Ansichten teilen sich den Typ; ein Name, der nur eine davon nennt, führte in
  die Irre. `NoriLayout` war nicht zu haben — so heißt auf dem Mac schon das
  Maß-Enum in `HomeView`.
- Der Umschalter selbst ist als `NoriViewModePicker` einmal vorhanden statt
  dreimal abgeschrieben.

## [macOS 1.13.0] – 2026-09-06

### Hinzugefügt

- **Folgenbilder und -beschreibungen aus TMDB**, jetzt auch auf dem Mac. Der
  Unterbau lag seit iOS 1.14.0 in der geteilten `AniworldClient.swift` bereit
  und wurde dort nur nicht genutzt.
- Die Kachel ist **128 × 72 Punkte** statt des früheren 38er-Quadrats —
  breiter als auf dem iPhone, weil die Fensterbreite es hergibt und eine
  briefmarkengroße Kachel auf dem Mac keine Auskunft wäre.
- **Der Tooltip trägt die vollständige Beschreibung.** In der Liste steht sie
  auf zwei Zeilen gekürzt; unter dem Mauszeiger ganz. Das gibt es so nur auf
  dem Mac, und es kostet keinen Platz.
- Platzhalter wie „Episode 7" werden erkannt: dann trägt der TMDB-Titel die
  Zeile, und die zweite Zeile entfällt.

### Geändert

- Der Fortschritt einer angefangenen Folge liegt als schmaler Streifen am
  unteren Bildrand statt als Balken unter dem Titel, wo er der Beschreibung
  im Weg stünde.
- `README.md`: Der macOS-Stand wurde als „der weiteste" geführt. Das stimmt
  seit dem iOS-Player-Umbau nicht mehr — Player und Startseite liegen dort
  zurück.

## [iOS 1.14.3] · [macOS 1.12.5] – 2026-09-06

### Geändert

- **`CatalogProvider` entscheidet über `switch` statt über Ternäre.** Für
  zwei Quellen war `self == .aniworld ? … : …` gleichwertig; für eine dritte
  wäre es still gefährlich gewesen. Jeder Sonst-Zweig hätte sie
  aufgesammelt, und die App hätte fehlerfrei übersetzt und dabei die
  falschen Seiten abgerufen. Ohne `default` zwingt der Compiler jetzt dazu,
  jede Stelle einzeln zu benennen.
- **`providerFromPath` leitet die Quelle über `streamPrefix` ab** statt über
  eine fest verdrahtete Abfrage auf „/serie/" mit AniWorld als Sonst-Zweig.
  Das ist kein Etikett: Der Fortschritt ist nach `provider|episodePath`
  geschlüsselt, eine falsch geratene Quelle hätte also den Stand vertauscht.
  Für die beiden bestehenden Quellen ist das Ergebnis unverändert —
  festgehalten in drei Tests, darunter einer, der über `allCases` läuft und
  eine dritte Quelle von selbst mitprüft.

## [iOS 1.14.2] · [macOS 1.12.4] – 2026-09-06

### Geändert

- **Der geteilte Kern ist jetzt Android-tauglich.** Die beiden einzigen
  Darwin-Bindungen in `AniworldClient.swift` liegen hinter
  `#if canImport(…)`: der Schlüsselbund in `TMDBKeyStore` (`Security`) und
  die Prüfung, ob heruntergeladene Bytes ein Bild sind (`ImageIO`). Auf
  Apple ändert sich nichts — dieselben Aufrufe, dasselbe Verhalten.
- Ohne ImageIO wird die Bildprüfung über die Signatur am Dateianfang
  gemacht (JPEG, PNG, GIF, WebP, ISO-BMFF für AVIF und HEIC). Sie erkennt
  eine als Bild ausgelieferte HTML-Fehlerseite genauso zuverlässig, nur ein
  abgeschnittenes Bild nicht.

### Hinzugefügt

- `tools/require-swift-android.sh` prüft vor dem Bauen, ob ein Swift-SDK
  für Android eingerichtet ist — dieselbe Lehre wie bei
  `require-xcode.sh`: ein fehlendes SDK sieht sonst aus wie ein Fehler im
  Quelltext.
- `.github/workflows/build-android.yml` baut das Target `NoriCore` quer für
  Android. **Nur von Hand auslösbar**, solange das SDK auf dem Runner nicht
  steht — ein push-Auslöser würde sonst jeden Pull Request rot färben,
  obwohl am Quelltext nichts falsch ist.
- `docs/android.md`: warum der Kern Swift bleibt und die Oberfläche Compose
  wird, warum die Web-App sich nicht verpacken lässt, und was auf dem
  Runner zu installieren ist. Dazu die Festlegung auf **Material 3 mit
  dynamischen Farben** — immer das dunkle Schema, die Töne aber vom
  Hintergrundbild, abschaltbar, und im Player bewusst nicht.

## [iOS 1.14.1] · [macOS 1.12.3] – 2026-09-06

### Behoben

- **Folgen blieben ohne Bild und Beschreibung.** Die Kennungssuche hing an
  zwei Sperren: am Cover-Treffer und am `missed`-Satz der Cover-Suche. In
  diesem Satz landet aber gerade, was TMDB **unter dem Titel der Quelle**
  nicht kennt — der Fall, in dem ein Alternativtitel hilft. Die Kennung
  wird jetzt auch über die Alternativtitel der Detailseite und über den
  Teil vor einem Doppelpunkt gesucht; Fehlschläge merkt ein eigener Satz,
  und der nur bis zum nächsten Start.
- **Überlappung beim Wischen durch den Kopfbereich.** `scaledToFill` meldet
  eine größere Größe, als ihm angeboten wurde; der Stapel wuchs über die
  Seitenbreite hinaus, und der Zuschnitt griff auf diese größere Fläche.
  Das Bild lief damit seitlich in die Nachbarseite. Jetzt bestimmt eine
  durchsichtige Fläche die Größe, und das Bild wird darauf beschnitten.
- **Der Schatten im Player reichte nicht bis zum unteren Rand.** Der
  Verlauf endete an der sicheren Fläche und ließ unter der Bedienleiste
  einen hellen Streifen stehen, genau dort, wo der Home-Indikator liegt.
- **„Episode 7" stand doppelt untereinander.** Beide Quellen setzen das
  ein, wo sie keinen echten Titel haben. Solche Platzhalter werden erkannt:
  dann trägt der TMDB-Titel die Zeile, und die zweite Zeile entfällt.

### Geändert

- **Der Kopfbereich zeigt das Poster statt des Breitbilds.** Ein
  16:9-Backdrop in einer hochkant stehenden Fläche zeigt einen schmalen
  Streifen aus der Bildmitte — meist Hintergrund, oft unkenntlich. Das
  Poster hat mit 2:3 fast genau das Seitenverhältnis dieser Fläche. Sie ist
  dafür von 520 auf 560 Punkte gewachsen, und das Bild ist oben
  ausgerichtet: beschnitten wird unten, wo ohnehin Verlauf und Schrift
  liegen.
- **Der Umschalter für die Kachelansicht sitzt eine Zeile tiefer**, über
  dem Inhalt statt in der Navigationsleiste. Dort drängte er sich mit dem
  Anime/Serien-Schalter auf einer Höhe.

## [iOS 1.14.0] · [macOS 1.12.2] – 2026-09-06

### Hinzugefügt

- **Folgenbilder und -beschreibungen aus TMDB** (iOS). Die Folgenliste einer
  Serie zeigt jetzt zu jeder Folge das Standbild im 16:9-Format und bis zu
  drei Zeilen Beschreibung. AniWorld und Serienstream liefern zu einer Folge
  nur zwei Titel und einen Pfad — beides kommt von TMDB, hinter der Kennung,
  die die Cover-Suche ohnehin schon ermittelt.
- Fehlt der deutsche Text bei TMDB — bei Anime die Regel, nicht die
  Ausnahme —, wird die englische Fassung nachgeholt und füllt nur die
  Lücken. Deutsche Texte bleiben stehen.
- Der Fortschritt einer angefangenen Folge liegt als schmaler Streifen am
  unteren Rand des Standbilds statt als Balken zwischen Titel und
  Beschreibung.

### Geändert

- **Der Cover-Index merkt sich die TMDB-Kennung** (beide Plattformen). Sie
  fällt bei der Cover-Suche ohnehin an und ist der Einstieg zu allem, was
  unterhalb der Serie liegt. Bewusst ohne Erhöhung der Speicherversion:
  ältere `covers.json` haben das Feld nicht, füllen es aber beim nächsten
  Öffnen einer Detailseite nach — eine Versionserhöhung hätte dafür
  sämtliche Cover verworfen.
- Folgendaten liegen in einer eigenen Datei `episodes.json`, getrennt von
  `covers.json`, die beim Scrollen durch den Katalog ohnehin ständig
  geschrieben wird.

## [iOS 1.13.0] – 2026-09-06

### Hinzugefügt

- **Kachelansicht in Katalog, Kalender und Merkliste.** Neben der Liste
  steht jetzt dasselbe Raster wie auf der Startseite; umgeschaltet wird über
  ein Menü in der Navigationsleiste. Die Wahl bleibt je Bildschirm erhalten —
  Katalog und Merkliste starten auf Kacheln, der Kalender auf Liste, weil
  dort die Angabe zählt und nicht das Bild.

## [macOS 1.12.1] · [iOS 1.12.1] – 2026-09-06

### Behoben

- **„Weiter · Folge 1" auf einer nie geöffneten Serie.** `nextPlay` landete
  ohne jeden Fortschritt im Zweig „next". Es heißt jetzt „Abspielen",
  solange nichts angefangen wurde.
- **Die Fortschrittsangabe stand auf jeder Detailseite**, auch mit „0 %
  gesehen 0/1". Sie erscheint erst, wenn tatsächlich etwas angesehen wurde.
- **Der Regler im Player zeigte zwei Spuren übereinander** und einen Griff,
  der über den linken Rand hinausstand: der Systemregler bringt eine eigene
  Spur mit, dahinter lag zusätzlich die Pufferanzeige. Ersetzt durch einen
  eigenen Regler aus drei Kapseln und einem Punkt — eine Spur, ein Griff,
  Puffer sichtbar.

### Geändert

- **TMDB-Schlüssel liegt jetzt bei.** Cover, Breitbilder und Beschreibungen
  sind damit ohne Einrichtung da. Bewusst gegen die Regel „keine Schlüssel
  im Quelltext" entschieden — vom Betreiber, für eine private App in einem
  privaten Repository. Ein im Schlüsselbund hinterlegter Schlüssel hat
  weiterhin Vorrang. `check_no_secrets()` lässt genau diese eine
  Deklaration durch; jeder weitere einkompilierte Schlüssel fällt auf.

## [iOS 1.12.0] – 2026-09-06

### Geändert

- **Eigene Bedienoberfläche im Player.** Apples fertige Bedienung ließ sich
  nicht erweitern — `transportBarCustomMenuItems` gibt es nur auf tvOS —,
  weshalb die Hosterwahl als eigener Knopf über dem Bild schwebte. Jetzt
  trägt Nori die Bedienung selbst: Hoster, Quellsprache, Untertitel und
  Geschwindigkeit liegen als Menüs in **einer** Leiste, im selben Stil,
  gemeinsam ein- und ausgeblendet.
- Dazu Abspielen/Pause, ±10 Sekunden, ein Regler mit Pufferanzeige und
  Restzeit, AirPlay und Bild-in-Bild. Die beiden letzten kamen mit Apples
  Bedienung geschenkt und sind jetzt ausdrücklich eingebaut
  (`AVRoutePickerView`, `AVPictureInPictureController`).
- Die Bedienung blendet nach vier Sekunden aus, aber nur während etwas
  läuft. Im Stehen wäre das die Zeit, in der man sie am ehesten braucht.
- Der Wiedergabestand wird weiterhin alle fünf Sekunden gesichert, obwohl
  die Position jetzt viermal pro Sekunde abgefragt wird — der Regler soll
  mitlaufen, die Platte nicht.

## [macOS 1.12.0] · [iOS 1.11.0] – 2026-09-06

### Entfernt

- **Die iCloud-Synchronisation.** Sie hat nie funktioniert:
  `NSUbiquitousKeyValueStore` verlangt die Berechtigung
  `com.apple.developer.ubiquity-kvstore-identifier`, die es nur im
  kostenpflichtigen Apple-Developer-Programm gibt. Ohne sie bleiben die
  Aufrufe wirkungslos — ohne Fehler, ohne Meldung. Der Schalter in den
  Einstellungen versprach einen Abgleich, der nie stattfand; jetzt steht
  dort, was Sache ist.
- Mit ihr das automatische Hochladen bei jeder Änderung. Ein Anbieter, der
  über das Netz geht, gehört nicht in jeden Tastendruck.

### Neu

- `LibrarySyncProvider`: die Naht, an der ein Abgleich andockt. Zwei
  Fragen — was liegt dort, nimm das hier —, der neuere Zeitstempel gewinnt.
  Solange kein Anbieter eingerichtet ist, sagt die Oberfläche das auch.
- `docs/synchronisation.md` vergleicht die kostenlosen Wege (Google Drive,
  Dropbox, WebDAV, Git) und nennt, was jeder davon einmalig an Einrichtung
  braucht.

## [iOS 1.10.1] – 2026-09-06

### Behoben

- **Der Kopfbereich der Startseite blieb schwarz.** Ohne TMDB-Treffer hat er
  weder Breitbild noch Poster, und das Cover der Quelle steht nur auf der
  Detailseite. Die Kacheln holen es sich längst von dort — der Kopfbereich
  tat es nicht. Jetzt schon.
- **Der Umschalter Anime/Serien stand verrutscht.** Er war ein handgebauter
  Schieber aus Kapsel, Daumen und zwei Textfeldern mit von Hand
  abgestimmten Breiten. Ersetzt durch das Systembauteil, das dasselbe kann
  und Dynamic Type, VoiceOver und jede Navigationsleiste von sich aus
  richtig behandelt.

### Neu

- **Cover in Katalog, Kalender und Merkliste.** Die Listen zeigten nur Text;
  jede Zeile trägt jetzt dieselbe Kachel wie das Raster, klein. Der Kalender
  nutzt den Coverpfad, den die Quelle mitliefert, wo vorhanden.
- Kalendereinträge öffnen die Serie mit ihrer eigenen Quelle statt mit der
  gerade eingestellten.

## [iOS 1.10.0] – 2026-09-06

### Geändert

- **Neue Startseite**, nach dem Vorbild von Crunchyroll. Statt Überschrift
  und Raster steht oben ein vollflächiger Kopfbereich: Bild bis unter die
  Statusleiste, darüber Titel, Quelle und Genres, Kurzbeschreibung und ein
  breiter Abspielknopf neben dem Merken-Knopf. Fünf Titel zum Durchwischen,
  mit Seitenpunkten; die Auswahl wechselt täglich.
- Darunter waagerechte Zeilen statt eines Rasters — „Weiterschauen",
  „Beliebte …" und bis zu sechs Genre-Zeilen, wie sie der Mac schon hat. Die
  Karten tragen Titel und Genre unter dem Bild.
- Der Abspielknopf ist nach Stand beschriftet: „Jetzt ansehen" oder
  „F12 weiterschauen", wenn die Serie angefangen ist.
- Die Farben bleiben Noris eigene. Übernommen ist der Aufbau, nicht das
  Aussehen einer fremden App.

## [iOS 1.9.11] – 2026-09-06

- Separate Playerleiste durch einen kleinen Liquid-Glass-Menüknopf im Video ersetzt (ab iOS 26, Material-Fallback auf älteren Systemen). Hoster/Quellsprache als UIKit-Menüs; nach vier Sekunden ausgeblendet, per Videotipp wieder sichtbar. Eigenständige Sichtbarkeitssteuerung; bei VoiceOver bleibt der Knopf erreichbar.
- Titel/Folge als Player-Metadaten übergeben; Schließen als Menüaktion sowie weiterhin im Lade-/Fehlerzustand erreichbar.

## [iOS 1.9.10] – 2026-09-06

- Nori-Leiste mit Schließen, Titel und Hoster/Sprachwahl außerhalb der nativen Playerfläche angeordnet. Keine Überlagerung mit AVKit-Lautstärke und Schließen.
- Doppelte Geschwindigkeitsauswahl aus dem Nori-Menü entfernt; native Playerbedienung bleibt verfügbar.
- Nutzer bestätigt Installation über KravaSign „semi-lokal“ und Videowiedergabe. Die zuvor beobachtete Kennungsabweichung ist keine bestätigte Ursache für „Bereit“.

## [macOS 1.11.6] – 2026-09-06

- Startseitenbanner: Bildgröße vom Vordergrund entkoppelt und auf die Bannerfläche begrenzt, damit Titel, Metadaten und Schaltflächen beim Laden nicht herausgeschoben werden.
- Banner und Weiterschauen verwenden den Cover-Lader mit Request-Headern; fehlende Quellposter werden aus der Detailseite nachgeladen.
- Weiterschauen-Karten bleiben 284×160 Punkte groß; Hochkantposter werden vollständig vor einem unscharfen Hintergrund angezeigt.
- iOS-Installation über KravaSign weiterhin nicht diagnostiziert; keine unbelegte Signaturkorrektur vorgenommen.

## [macOS 1.11.5] · [iOS 1.9.9] – 2026-09-05

- Cover: Originaladressen einschließlich Host, PNG-Endung und AVIF-Query erhalten; keine pauschale JPG-Umschreibung.
- Parser: Lazy-Load-Bilder und Open-Graph-Fallback für beide Quellen auswerten.
- Bilddaten vor dem Cachen mit ImageIO decodieren; HTML-Fehlerseiten nicht als Bilder speichern.
- Vorübergehende Bild-/Detailseitenfehler nach 30 Sekunden erneut zulassen; abgebrochene Bildanfragen nicht als Fehler merken.
- Alte, umgeschriebene Coveradressen einmalig verwerfen; manuelle Auswahl erhalten. Coveraufgaben bei Quellenwechsel neu starten und verspätete Bilder verwerfen.
- Regressionstests mit den gemeldeten PNG-/AVIF-Adressen ergänzt. Xcode-/Swift-Tests und Live-Bildabrufe noch ausstehend; keine Workflows gestartet.

## [macOS 1.11.4] · [iOS 1.9.8] – 2026-09-05

### Behoben

- Beide Player halten die Quelle des Wiedergabeauftrags fest. Navigation zu
  einem Titel der anderen Quelle ändert weder den gespeicherten Fortschritt
  noch Hoster-Auflösung, Resume oder den automatischen Folgenwechsel.
- iOS übergibt Quelle und Episodenpfad auch an den Hoster-Resolver. Zuvor
  griff dort die AniWorld-Vorgabe auch bei Serienstream-Wiedergaben.
- iOS übergibt wie macOS User-Agent und den vom Resolver gelieferten Referer
  samt Origin an das Video-Asset und zeigt asynchrone Wiedergabefehler an.
- Abgeschlossene Ladeversuche und Player-Rückmeldungen werden verworfen,
  wenn inzwischen eine andere Wiedergabe gestartet oder der Player geschlossen
  wurde. Fehlerbeobachter werden erst nach dem Resume-Suchlauf eingerichtet.

### Prüfstand

- Quellcodeprüfung lokal; Xcode-Builds, Swift-Tests und Geräteprüfungen für
  diesen Stand stehen aus. Auf Wunsch wurden keine Workflows gestartet.

## [macOS 1.11.3] – 2026-09-05

### Neu

- **Cover-Diagnose** unter Einstellungen › Daten. Sie geht den Weg ab, auf
  dem ein Cover entsteht — Detailseite laden, Adresse darin finden, Bild
  abrufen — und schreibt jeden Schritt mit Befund auf. Aus einer leeren
  Kachel allein ließ sich nicht ablesen, an welchem der drei Schritte es
  scheitert; das waren drei sehr verschiedene Ursachen mit identischem Bild
  auf dem Schirm.

## [macOS 1.11.2] · [iOS 1.9.7] – 2026-09-05

### Behoben

- **Die Kacheln blieben leer — der Grund war ein anderer als gedacht.** Die
  Adresse eines Covers lässt sich nicht aus dem Slug bilden, weil beide
  Quellen einen Zufallsanteil an den Dateinamen hängen:

  ```
  /media/images/channel/desktop/black-mirror-7sqv7dhs
  /public/img/cover/black-clover-stream-cover-WWoAujz6fnp…_220x330.jpg
  ```

  Jede geratene Adresse war also eine 404. Nori liest die Adresse jetzt bei
  Bedarf aus der Detailseite — dort steht sie — und legt sie dauerhaft in
  `covers.json` ab. Das kostet beim ersten Anzeigen eines Titels eine
  Seite, danach nie wieder; geladen wird nur, was auch stehen bleibt, ein
  schneller Scroll löst gar keine Anfrage aus.
- Für Serienstream wird `format=jpg` festgeschrieben. Die Seiten liefern
  `format=avif` aus; jpg decodiert überall.
- Die Testfixtures trugen vereinfachte Dateinamen (`one-piece.jpg`) und
  bestätigten dadurch eine Annahme, die die Wirklichkeit nicht hergibt.
  Jetzt stehen dort die echten Namen.

## [macOS 1.11.1] · [iOS 1.9.6] – 2026-09-05

### Behoben

- **Die Kacheln blieben fast alle leer.** Nicht die Adresse war falsch,
  sondern die Anfrage: `AsyncImage` schickt weder User-Agent noch Referer,
  und beide Quellen beantworten eine Bildanfrage ohne diese Kopfzeilen
  anders als dem Browser. Genau deshalb schickt der Player sie längst mit
  und baut `CoverToneSampler` seine Anfrage selbst — nur die Kacheln hingen
  noch an `AsyncImage`. Cover werden jetzt über einen eigenen Lader geholt,
  mit denselben Kopfzeilen wie jeder andere Abruf, samt Zwischenspeicher
  und gemerkter Fehlschläge.
- Für Serienstream wird zusätzlich `s.to` probiert — die Seiten nennen ihre
  Bilder dort selbst, erreichbar sind sie unter beiden Namen. Eine einzige
  geratene Adresse hieß: trifft sie nicht, bleibt die Kachel leer.
- **Die iOS-App blieb nach der Installation als Platzhalter auf dem
  Home-Bildschirm stehen** und sah aus, als lade sie endlos. In der
  Info.plist fehlte `CFBundleIconName`; Xcode trägt den Schlüssel nur bei
  generierter Info.plist nach, und beide Targets pflegen sie von Hand. Ohne
  ihn findet iOS kein App-Icon. Auf macOS zeigte dieselbe Lücke das graue
  Standardsymbol in Dock und Finder.

## [macOS 1.11.0] – 2026-09-05

### Neu

- **Eine gemeinsame Bibliothek.** Anime und Serien stehen zusammen in
  Startseite, Katalog, Kategorien, Merkliste und Kalender. Der Umschalter
  unten links ist kein Moduswechsel mehr, sondern ein Filter: **Alle ·
  Anime · Serien**. Vorgabe ist „Alle"; die Wahl wird gespeichert
  (Bibliotheksschema v4).
- Jeder Titel und jeder Kalendereintrag weiß, von welcher Seite er stammt,
  und öffnet sie auch dann richtig, wenn die Liste beide Quellen enthält.
- Beide Kataloge werden nebenläufig geladen. Fällt eine Quelle aus, bleibt
  die andere stehen — gemeldet wird nur, wenn beide ausfallen oder wenn
  gerade nach genau der ausgefallenen gefiltert ist.

### Geändert

- „Ähnliche Titel" bleiben innerhalb derselben Quelle. Ein Vorschlag, der
  von einer Anime-Seite auf Serienstream führt, wäre zwar abspielbar, wirkt
  dort aber wie ein Fehler.
- Auf der Detailseite zeigen Cover, Quelle und Empfehlungen jetzt die
  Quelle **dieses Titels** statt der zuletzt global gewählten.

## [macOS 1.10.4] · [iOS 1.9.5] – 2026-09-05

### Behoben

- **Viele Kacheln blieben ohne Cover.** Der Grund liegt nicht bei TMDB: ein
  Katalogeintrag trägt überhaupt kein Bild, weil die Katalogseite der
  Quellen eine reine Titelliste ist. Das Cover der Quelle lernte Nori erst,
  wenn man die Serie öffnete — im Raster gab es bis dahin nur TMDB, und
  ohne Treffer blieb der Buchstabe.

  Der Coverpfad wird jetzt aus dem Slug abgeleitet. Dass der Dateiname der
  Slug ist, nutzt der Kalender-Parser bereits in der Gegenrichtung. Trifft
  die Ableitung nicht, antwortet die Quelle mit 404 und es bleibt beim
  Buchstaben — also nicht schlechter als vorher, aber in den meisten Fällen
  mit Bild.

### Geändert

- Die Besonderheiten der Hoster stehen je Anbieter in einer Registry statt
  verstreut im Ablauf. Ein neuer Hoster ist ein Eintrag mehr, ein kaputter
  betrifft nur seinen eigenen.

## [macOS 1.10.3] – 2026-09-05

Vier Anzeigefehler, alle aus Screenshots gemeldet.

### Behoben

- **Der Kopfbereich der Detailseite schnitt seinen eigenen Inhalt ab.**
  Das Breitbild lag mit `scaledToFill` im selben Stapel wie der Text. Ein
  so skaliertes Bild meldet nach außen eine *größere* Größe, als ihm
  angeboten wurde — der Stapel wuchs mit, das feste `frame(height: 430)`
  zentrierte den zu großen Stapel darin, und `clipped()` schnitt an beiden
  Rändern ab; der Abspielknopf war zur Hälfte weg. Das Bild liegt jetzt als
  Hintergrund hinter dem Inhalt, wo es die Größe nicht beeinflusst.
- **Dieselben Angaben standen dreimal auf der Detailseite**: als Chips, in
  der Zeile darunter und in der Faktenspalte rechts. Jetzt trägt der
  Kopfbereich Titel, Jahr, Altersfreigabe und Bewertung, die Faktenspalte
  Genres, Sprachen und Quelle — jede Angabe an genau einer Stelle.
- **Das Banner zeigte bei fehlendem Breitbild ein Hochkant-Poster
  vollflächig.** In einer etwa 2:1 breiten Fläche blieb davon ein winziger
  Ausschnitt aus der Bildmitte übrig, in dem der Titel unterging. Ohne
  Breitbild dient das Poster jetzt nur noch unscharf und abgedunkelt als
  Untergrund. Dasselbe in den Karten von „Schau weiter": dort steht das
  Poster vollständig vor seinem eigenen unscharfen Untergrund.
- **Das Hover-Infofeld auf den Kacheln war durchscheinend.** Mit 86 %
  Schwarz stand die Schrift auf dem Poster und war kaum zu lesen. Es ist
  jetzt deckend, hat abgerundete Ecken wie die Kachel und eine Akzentkante
  oben.

### Geändert

- **Das Banner zeigt nur noch Empfehlungen.** Angefangene Titel standen
  dort mit „Folge N fortsetzen" — und gleich darunter noch einmal in
  „Schau weiter". Die Auswahl wechselt täglich, bleibt innerhalb eines
  Tages aber gleich; vorher standen dort immer dieselben sechs Titel vom
  Anfang des Alphabets. Sie mischt sich auch nicht mehr neu, sobald man
  etwas anschaut.

## [macOS 1.10.2] · [iOS 1.9.4] – 2026-09-05

### Behoben

- **Sprachfähnchen ohne `title` blieben ohne Sprache** (AniWorld,
  Folgenliste). Der vorgesehene Rückfall auf `alt` konnte nie greifen:
  SwiftSoups `attr()` liefert bei fehlendem Attribut `""` statt zu werfen,
  `try?` ergibt also `.some("")` und die `??`-Kette fällt nicht durch.
- **Dieselbe Ursache bei den Hoster-Namen** (Serienstream, Folgenliste): der
  Rückfall von `alt` auf `title` lief nie an.

Beide Stellen sind beim Schreiben der Parser-Tests aufgefallen.

### Neu

- **Parser-Tests mit Fixtures.** `HTML.swift` lief bis hierher ohne jede
  Prüfung — dabei ist es die Stelle, die als Erstes bricht, wenn AniWorld
  oder Serienstream ihr Markup ändern. Neu sind 48 Tests über Katalog,
  Serienseite, Folgenseite und Kalender beider Quellen, dazu die
  Hilfsfunktionen für Pfade, Slugs und Sprachkürzel.
- Das Testpaket bindet jetzt auch `HTML.swift` ein und löst SwiftSoup auf
  derselben Spanne auf wie beide Xcode-Projekte (2.7.0, up to next major).

## [macOS 1.10.1] · [iOS 1.9.3] – 2026-09-05

### Geändert

- **Der TMDB-Schlüssel steht nicht mehr im Quelltext.** Er lag als
  Zeichenkette in `AniworldClient.swift` und damit in jedem Klon, in jedem
  Build und in der Git-Historie; gesperrt wird er für alle Installationen
  zugleich. Er kommt jetzt aus dem Schlüsselbund oder, für Builds mit
  gesetzter Build-Einstellung `TMDB_API_KEY`, aus der Info.plist.
- **Ohne Schlüssel bleibt die App vollständig benutzbar.** Sie fragt TMDB
  dann gar nicht erst an und zeigt die Cover von AniWorld und Serienstream,
  die sie ohnehin einliest. Ein Schlüssel bringt zusätzlich Breitbilder für
  den Kopfbereich, Kurzbeschreibungen und Bewertungen.
- Eintragen und Entfernen unter **Einstellungen › Daten** (macOS) bzw.
  **Einstellungen › Datenschutz** (iOS). Die manuelle Cover-Auswahl sagt
  jetzt, dass ohne Schlüssel nichts zur Auswahl steht, statt „keine
  Treffer" zu melden, obwohl gar nicht gesucht wurde.

## [iOS 1.9.2] – 2026-09-05

Der iOS-Code wurde bis dahin von keiner Prüfung übersetzt. Der erste
CI-Build deckte auf, dass er sich gar nicht übersetzen ließ.

### Behoben

- **Die App ließ sich nicht bauen.** `HTML.swift` enthielt lange
  `??`-Ketten mit `try` in einzelnen Gliedern; der Compiler brach dort mit
  „operator can throw but expression is not marked with 'try'" und
  „unable to type-check this expression in reasonable time" ab.
  `nextElementSibling()` fehlte zweimal das `try`. Die macOS-Fassung
  derselben Datei hatte diese Stellen bereits aufgelöst und ist jetzt in
  beiden Targets identisch — damit kann die Parsing-Logik nicht mehr
  zwischen den Plattformen auseinanderlaufen.
- **Player: zwei Aktionen ohne Wirkung.** Wiedergabegeschwindigkeit und
  „Abbrechen" beim Autoplay riefen `@MainActor`-Methoden synchron aus einer
  View-Hilfe auf, was der Compiler ablehnt. Beide laufen jetzt über
  `Task { @MainActor in … }`.
- **App-Icon fehlte.** Hinterlegt war das 256×256-Icon der Windows-Hülle,
  eingetragen als 1024×1024. Der Asset-Catalog verwarf es stillschweigend
  und meldete nur ein leeres Icon-Set. Das Icon wird jetzt aus dem
  macOS-Master erzeugt: 1024×1024, deckend, ohne Alphakanal.

### Werkzeuge

- `tools/make-app-icons.py` erzeugt beide Icon-Sätze reproduzierbar aus
  einem Master und ersetzt den Workflow, der sich selbst committet hat.
- `tools/check-apple-sources.py` prüft zusätzlich Icon-Größen und
  Alphakanal, synchrone `@MainActor`-Aufrufe aus View-Hilfen und ob der
  iOS-Runner zum verwendeten SDK passt.
- Neue Workflows `Build iOS` (macos-15, Simulator, ohne Signatur) und
  `Swift tests` (21 Tests für Fortschritts- und Pfadregeln).

## [macOS 1.10.0] – 2026-09-04

Die macOS-App war bis dahin eine nahezu wörtliche Kopie der iOS-Oberfläche.
Dieser Stand macht sie zu einer eigenständigen Mac-App und behebt zwei Fehler,
die die Wiedergabe komplett verhindert haben.

### Behoben

- **AniWorld war überhaupt nicht abspielbar.** Die Weiterleitung prüfte
  `hasPrefix("/r")` für Serienstream. AniWorlds Pfade lauten `/redirect/…` und
  beginnen ebenfalls mit `/r`, liefen damit immer in den Serienstream-Zweig und
  landeten auf `serienstream.to/redirect/…` mit HTTP 404.
- **Player blieb leer.** AVPlayer schickte weder Referer noch User-Agent. Die
  meisten Hoster liefern das Video nur mit passendem Referer aus. Das Asset
  wird jetzt mit Referer, Origin und User-Agent aufgebaut.
- **Falsche Cover.** Die Beliebtheit einer Serie floss voll in die
  TMDB-Bewertung ein und riss die Annahmeschwelle ohne jede
  Titelübereinstimmung. Beliebtheit ist jetzt gedeckelt und nur noch
  Stichentscheid.
- **Fehlende Cover.** Beim Scrollen liefen bis zu sechzig gleichzeitige
  TMDB-Anfragen und rannten in die Ratenbegrenzung. Jetzt höchstens vier
  parallel, identische Anfragen werden gebündelt.
- **Kalendereinträge führten auf falsche Seiten.** Sie gaben ihre Quelle nicht
  mit, und ein einmaliger Ladefehler stellte die ganze App dauerhaft auf die
  andere Quelle um.
- Weiterleitungen, die als HTML statt als HTTP-302 kommen, werden erkannt
  (meta-refresh, `window.location`, iframe).
- Fehlermeldungen nennen jetzt Hoster, Sprache und Grund statt einer pauschalen
  Meldung; bei der Weiterleitung zusätzlich HTTP-Status und Zielhost.

### Neu

- **Seitenleiste statt Tab-Bar** (`NavigationSplitView`) mit Entdecken,
  Katalog, Kategorien, Kalender und Merkliste.
- **Eigenes Wiedergabefenster** mit eigener Titelleiste, Vollbild über den
  grünen Knopf und `⌘W`. Hoster, Sprache, Tempo und Folgenwechsel sitzen in der
  Fenster-Symbolleiste und verdecken die AVKit-Regler nicht mehr.
- **Einstellungsfenster** (`⌘,`) mit den Bereichen Allgemein, Wiedergabe,
  Synchronisation und Daten.
- **Entdecken-Startseite** mit Kopfkarussell, „Schau weiter" im Querformat mit
  Fortschritt und Restzeit, Genre-Zeilen und Postern.
- **Kategorien**: alle Genres als Kacheln, nach Auswahl das Raster der Titel.
- **Ähnliche Titel** auf der Detailseite, abgeleitet aus der
  Genre-Überschneidung im geladenen Katalog.
- **Manuelle Cover-Auswahl** je Serie, wenn die automatische Zuordnung nicht
  passt. Findet TMDB nichts, wird das Cover von AniWorld oder Serienstream
  genommen.
- Infofeld beim Überfahren einer Kachel mit Bewertung, Genres und Beschreibung.
- Tastenkürzel `⌘1`–`⌘5` für die Bereiche, `⌘R` zum Aktualisieren.
- Bildschirmruhezustand wird während der Wiedergabe blockiert.

### Geändert

- Farbpalette folgt dem Systemerscheinungsbild statt erzwungenem Dunkelmodus;
  Akzentfarbe auf Orange umgestellt.
- Native Listenstile mit alternierenden Zeilen, Hover-Zustände,
  Rechtsklick-Kontextmenüs und Tooltips.
- Explizite Aktualisieren-Knöpfe, weil Pull-to-Refresh auf macOS wirkungslos
  ist.
- Cover-Index liegt jetzt auf der Platte statt nur im Arbeitsspeicher.
- Fenstermindestgröße von 960 × 640 auf 720 × 460 gesenkt.

### Hinweis zum Update

Beim ersten Start werden die automatisch zugeordneten Cover verworfen und neu
gesucht, weil die alte Zuordnung fehlerhaft war. Manuell gewählte Cover,
Merkliste, Verlauf und Wiedergabefortschritt bleiben erhalten.

## [iOS 1.9.1] – 2026-09-04

Die Oberfläche ist unverändert; iOS erbt die Korrekturen aus den gemeinsamen
Dateien.

### Behoben

- AniWorld-Weiterleitung landete auf der falschen Domain und war dadurch nicht
  abspielbar.
- Serienstream-Weiterleitungen konnten einen Zwischenschritt innerhalb der
  eigenen Domain als Hoster-Adresse nehmen.
- Falsche Cover-Zuordnung durch Beliebtheit ohne Titelübereinstimmung.
- Kalendereinträge ohne URL erzeugten aus dem Poster-Dateinamen einen
  ungültigen Slug.

### Neu

- Cover-Index wird auf der Platte gespeichert und ist beim nächsten Start
  sofort verfügbar.
- Kalendereinträge tragen ein Cover, sofern die Quelle eines mitliefert.
- Fehlermeldungen nennen Hoster, Sprache und Grund.

## [1.9.0] und früher

Kein gepflegtes Changelog. Der Stand ist über die Git-Historie und die
GitHub-Releases nachvollziehbar.

