# TMDB in Nori

> **Stand Nori 2.8.0:** macOS, Windows und LG webOS sind eingestellt und aus
> dem Repository entfernt. Was hier über diese Plattformen, den
> TypeScript-Kern (`shared/`) oder den Nori-Server steht, beschreibt den
> früheren Stand und bleibt als Begründung stehen.

Nori holt Poster, Breitbilder, Logos, Beschreibungen, Bewertungen und sämtliche
Folgendaten von TMDB. AniWorld und Serienstream liefern davon nur das Cover der
Serie — keine Folgenbilder, keine Folgentexte.

Die Regeln stehen in `config/contract.json` unter `tmdb` und gelten für beide
Kerne: `native/NoriCore/Sources/NoriCore/TMDB*.swift` und
`shared/nori-core/src/tmdb/`.

## Woher was kommt

| Angabe | Endpunkt |
| --- | --- |
| TMDB-Kennung, Poster, Breitbild, Beschreibung, Bewertung | `/search/tv` |
| weitere Schreibweisen (Nachbesserung) | `/tv/{id}/alternative_titles` |
| Logo | `/tv/{id}/images` |
| Staffelliste (nur bei abweichender Zählung) | `/tv/{id}` |
| Folgentitel, -text, -standbild, Laufzeit, Datum | `/tv/{id}/season/{n}` |
| Ranglisten für die Startseite | `trending`, `discover`, `tv/popular` |

Folgenbilder stehen in **`still_path`**, nicht in `poster_path` — Folgen haben
bei TMDB kein Poster. Alle Adressen entstehen in `TMDBImages` bzw.
`tmdbImageURL`, nirgends sonst.

## Die Zuordnung

Der Titel entscheidet, alles andere gewichtet nur. Beliebtheit, Genre und
Herkunftsland ziehen einen Treffer vor einen anderen, **erzeugen** aber keinen.
Wer die Titelschwelle nicht erreicht, fällt raus — lieber kein Bild als das
einer fremden Serie.

Gesucht wird in einer Kette absteigender Güte (`TMDBMatcher.queries`): Titel der
Quelle, Alternativtitel, der Teil vor einem Doppelpunkt, zuletzt die um
Staffel- und Jahresangaben bereinigte Fassung. Der erste Treffer beendet die
Kette; im Regelfall bleibt es bei einer Anfrage.

Ergibt die Kette nichts, obwohl TMDB Zeilen geliefert hat, werden für die
vordersten Zeilen die Alternativtitel nachgeladen. Das ist kein Beiwerk:
`/search/tv?query=Shingeki no Kyojin` liefert genau eine Zeile — die richtige —,
deren `name` „Attack on Titan" und deren `original_name` „進撃の巨人" ist. Die
Umschrift, unter der AniWorld Anime führt, steht nur in den Alternativtiteln.

## Staffeln und Folgen

`season_number` ist keine gemeinsame Sprache. Gemessen:

| Serie | TMDB | Quelle |
| --- | --- | --- |
| Jujutsu Kaisen | 1 Staffel, 59 Folgen | mehrere Staffeln |
| Detektiv Conan | 1 Staffel, 1213 Folgen | über ein Dutzend |
| Frieren | 1 Staffel, 38 Folgen | 1 Staffel |

`/tv/95479/season/2` antwortet mit **HTTP 404**. Deckt die direkte Antwort
weniger als die Hälfte der Quellfolgen ab oder fehlt sie ganz, ordnet
`TMDBSeasonMap` über die **Folgentitel** zu: gleicher Versatz bei mindestens
drei Titeln und mindestens der Hälfte der benennbaren Quellfolgen, und kein
zweiter Versatz mit gleich vielen Belegen. Lässt sich nichts belegen, wird
nichts zugeordnet.

Staffel 0 und Abschnitte ohne Nummer („Filme") bleiben außen vor — die
Zuordnung wäre geraten.

## Sprache

Für **Texte** `de-DE`, Lücken aus `en-US`. Pro Feld, nicht pro Staffel: ein
leerer String ist eine Lücke, keine Auskunft.

Für **Bilder** `include_image_language=de,en,null`; ergibt das nichts, wird ohne
Filter gefragt. Der Filter kostet messbar Bilder — Jujutsu Kaisen 8 gefiltert
gegen 30 ungefiltert. Logos: deutsch vor englisch vor sprachlos vor allem
anderen, SVG fällt heraus.

## Fehlschläge

Nur **HTTP 404** darf als „hat TMDB nicht" abgelegt werden, und auch das nur
vierzehn Tage. 401, 403, 429, 5xx, Zeitüberschreitung, Netzfehler und unlesbare
Antworten werden nie gemerkt. Ohne diese Unterscheidung macht eine einzige
Ratenbegrenzung aus „gerade nicht erreichbar" ein „gibt es nicht", und zwar bis
zum Löschen des Caches.

## Fehlersuche

```bash
NORI_LOG=1
```

schaltet `NoriLog` ein: gewählter Suchbegriff, Treffer mit Kennung, ob Poster
und Breitbild dabei sind, Zahl der Logokandidaten, Zahl der Folgen und ein
etwaiger Versatz. Protokollzeilen tragen nie den API-Schlüssel und nie eine
vollständige Anfrageadresse — die trägt ihn als Abfrageparameter.

## Schlüssel

Die Reihenfolge ist auf beiden Seiten dieselbe: ein **eigener** Schlüssel hat
Vorrang, sonst greift der mitgelieferte.

- Apple: `TMDBKeyStore` — Schlüsselbund vor `TMDBAPIKey` aus der Info.plist vor
  `TMDBKeyStore.builtIn`.
- TypeScript: `resolveTmdbKey` in `shared/nori-core/src/tmdb/key.ts` — der
  eingetragene vor `BUILT_IN_TMDB_KEY`. Am Server ist der eingetragene
  `NORI_TMDB_KEY`, am Fernseher der aus den Einstellungen.

Beide Seiten benutzen **denselben** mitgelieferten Schlüssel; wird er getauscht,
gehört er an beiden Stellen getauscht. `tools/check-apple-sources.py` und
`tools/check-webos-package.py` erlauben je genau diese eine Zeile, und der
zweite vergleicht zusätzlich, dass die Zeichenketten übereinstimmen — sonst
zeigte der Fernseher zu derselben Serie andere Daten als das iPhone, und zwar
ohne Fehlermeldung.

Es gibt damit keinen Zustand „noch kein Schlüssel eingetragen". Wer TMDB nicht
will, schaltet es ausdrücklich ab; dann zeigt Nori die Cover der Quellen — ein
gültiger Zustand, kein Fehler.
