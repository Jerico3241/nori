# Changelog

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
Versionierung nach [Semantic Versioning](https://semver.org/lang/de/).

Die Plattformen laufen auf eigenen Versionsständen, weil sie sich
unterschiedlich schnell bewegen: macOS **1.10.2**, iOS/iPadOS **1.9.4**,
Windows **1.8.0**.

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
