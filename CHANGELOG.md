# Changelog

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
Versionierung nach [Semantic Versioning](https://semver.org/lang/de/).

Die Plattformen laufen auf eigenen Versionsständen, weil sie sich
unterschiedlich schnell bewegen: macOS **1.14.0**, iOS/iPadOS **1.14.3**,
Windows **1.8.0**.

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

