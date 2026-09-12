// Die TMDB-Seite des Kerns.
//
// Warum das geprüft gehört: Eine falsche Zuordnung ist nicht bloß ein falsches
// Bild. Sie zieht Beschreibung, Bewertung, Folgentitel, Standbilder und die
// Beliebtheitssignale der Startseite hinter sich her — die Serie sieht dann
// durchgehend nach einer anderen aus.
//
// Die Fälle spiegeln `native/Tests/NoriCoreTests/TMDBMatcherTests.swift`: die
// beiden Kerne sollen bei denselben Eingaben dasselbe entscheiden. Dazu kommen
// die Bereiche, die es nur in TypeScript gibt — Staffelzuordnung, Ranglisten
// und der Abrufweg.

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  alignEpisodes, alignmentIsUsable, bestCandidate, bestLogoPath, candidateFromRow,
  emptyCandidate, isTMDBImage, namedEpisodeTitle, normalizeTitle, pickTmdbSeason,
  scoreCandidate, searchQueries, stripVariants, tmdbImageURL,
  type TMDBCandidate, type TMDBEpisodeInfo,
} from "../src/tmdb/index.js";
import {
  DirectTMDBTransport, NoTMDBTransport, ServerTMDBTransport, TMDBClient,
} from "../src/tmdb/client.js";
import {
  HomeCatalogIndex, buildCandidates, emptySignals, heroPicks, newAndPopular,
  newAndPopularScore, recentEpisodes, recommend, tasteProfile, topRated, trending,
  type HomeCandidate, type HomeTitle, type TMDBSignals,
} from "../src/tmdb/ranking.js";
import type { HttpClient, HttpResponse } from "../src/http.js";
import { NoriError } from "../src/models.js";
import type { AiringEntry, WatchProgress } from "../src/models.js";

// MARK: - Hilfen

function candidate(overrides: Partial<TMDBCandidate> & { id: number; name: string }): TMDBCandidate {
  return { ...emptyCandidate(overrides.id, overrides.name), ...overrides };
}

function title(overrides: Partial<HomeTitle> & { slug: string; title: string }): HomeTitle {
  return { provider: "aniworld", genres: [], alts: [], ...overrides };
}

function homeCandidate(
  slug: string,
  signals: Partial<TMDBSignals> = {},
  extra: Partial<HomeCandidate> = {},
): HomeCandidate {
  return {
    title: title({ slug, title: slug }),
    signals: { ...emptySignals(), ...signals },
    watchedRatio: 0,
    inWatchlist: false,
    hasFreshEpisode: false,
    ...extra,
  };
}

/**
 * Ein `HttpClient`, der aus einer Tabelle antwortet.
 *
 * Kein Netz im Test: eine Prüfung, die von TMDBs Tagesform abhängt, sagt am
 * Ende mehr über TMDB als über Nori. Die Tabelle wird über den Pfadanfang
 * getroffen, damit die Abfrageparameter nicht mitgeschrieben werden müssen.
 */
class FakeHttp implements HttpClient {
  readonly canReadRedirects = false;
  readonly calls: string[] = [];
  private readonly routes: { match: string; status: number; body: unknown }[];
  private readonly failOn: string | null;

  constructor(
    routes: { match: string; status?: number; body?: unknown }[],
    failOn: string | null = null,
  ) {
    this.routes = routes.map((route) => ({
      match: route.match,
      status: route.status ?? 200,
      body: route.body ?? {},
    }));
    this.failOn = failOn;
  }

  async request(url: string): Promise<HttpResponse> {
    this.calls.push(url);
    if (this.failOn && url.includes(this.failOn)) {
      throw NoriError.network("Netz weg");
    }
    const route = this.routes.find((entry) => url.includes(entry.match));
    const body = route ? route.body : {};
    const status = route ? route.status : 404;
    return {
      status,
      url,
      headers: new Headers(),
      text: async () => (typeof body === "string" ? body : JSON.stringify(body)),
    };
  }
}

// MARK: - Normalisierung

test("normalizeTitle faltet Groß-/Kleinschreibung, Akzente und Satzzeichen", () => {
  assert.equal(normalizeTitle("Pokémon"), "pokemon");
  assert.equal(normalizeTitle("Re:ZERO – Starting Life"), "re zero starting life");
  assert.equal(normalizeTitle("  Fullmetal   Alchemist  "), "fullmetal alchemist");
  assert.equal(normalizeTitle("KONOSUBA -God's blessing-"), "konosuba god s blessing");
});

test("normalizeTitle behält Ziffern", () => {
  // „86" und „91 Days" sind Titel, keine Zählung.
  assert.equal(normalizeTitle("86"), "86");
  assert.equal(normalizeTitle("91 Days"), "91 days");
});

test("normalizeTitle faltet Breitschrift", () => {
  // Beide Quellen schreiben japanische Titel gelegentlich in Breitschrift.
  assert.equal(normalizeTitle("ＮＡＲＵＴＯ"), "naruto");
});

test("stripVariants entfernt Staffel- und Jahreszusätze", () => {
  assert.equal(stripVariants("Vinland Saga Staffel 2"), "vinland saga");
  assert.equal(stripVariants("Attack on Titan Final Season"), "attack on titan");
  assert.equal(stripVariants("Overlord 2nd Season"), "overlord");
  assert.equal(stripVariants("Dark (2017)"), "dark");
  assert.equal(stripVariants("Mushoku Tensei Part 2"), "mushoku tensei");
  assert.equal(stripVariants("Mushoku Tensei Cour 2"), "mushoku tensei");
});

test("stripVariants lässt Zahlentitel in Ruhe", () => {
  // „1899" ist kein Jahreszusatz, sondern der Serienname.
  assert.equal(stripVariants("1899"), "1899");
});

// MARK: - Suchbegriffe

test("searchQueries stellt den Quelltitel voran, dann die Alternativtitel", () => {
  const queries = searchQueries("Dämonenjäger", ["Demon Slayer", "Kimetsu no Yaiba"]);
  assert.equal(queries[0], "Dämonenjäger");
  assert.ok(queries.includes("Demon Slayer"));
  assert.ok(queries.includes("Kimetsu no Yaiba"));
});

test("searchQueries ergänzt den Teil vor dem Doppelpunkt genau einmal", () => {
  const queries = searchQueries("Sword Art Online: Alicization", ["Sword Art Online"]);
  assert.equal(queries.filter((query) => query === "Sword Art Online").length, 1);
});

// MARK: - Titelnähe

test("ein genauer Titel schlägt alles andere", () => {
  const exact = candidate({ id: 1, name: "Bleach", popularity: 5 });
  const popular = candidate({ id: 2, name: "Bleach: Thousand-Year Blood War", popularity: 900 });
  assert.equal(bestCandidate([popular, exact], "Bleach", { kind: "aniworld" })?.id, 1);
});

test("Beliebtheit kann keinen Treffer erzeugen", () => {
  // Der Fall, aus dem die falschen Cover entstehen: eine sehr bekannte, völlig
  // andere Serie reißt die Schwelle allein durch Beliebtheit.
  const unrelated = candidate({ id: 7, name: "Game of Thrones", popularity: 5000, genreIDs: [18] });
  assert.equal(scoreCandidate(unrelated, "Frieren", { kind: "aniworld" }), null);
  assert.equal(bestCandidate([unrelated], "Frieren", { kind: "aniworld" }), null);
});

test("ein kurzes Wort in einem längeren Titel ist kein Treffer", () => {
  const onePiece = candidate({ id: 3, name: "One Piece" });
  assert.equal(scoreCandidate(onePiece, "One", { kind: "aniworld" }), null);
  // Und die Übersetzungsfalle: „Ein Stück" darf nicht bei „One Piece" landen.
  assert.equal(scoreCandidate(onePiece, "Ein Stück", { kind: "aniworld" }), null);
});

test("ein Staffelzusatz trifft weiter dieselbe Serie", () => {
  const series = candidate({ id: 4, name: "Vinland Saga", genreIDs: [16], originCountries: ["JP"] });
  assert.notEqual(scoreCandidate(series, "Vinland Saga Staffel 2", { kind: "aniworld" }), null);
});

test("der deutsche Titel trifft über einen Alternativtitel", () => {
  const row = candidate({
    id: 5,
    name: "Demon Slayer: Kimetsu no Yaiba",
    originalName: "鬼滅の刃",
    alternateNames: ["Dämonenjäger"],
    genreIDs: [16],
    originCountries: ["JP"],
  });
  assert.notEqual(scoreCandidate(row, "Dämonenjäger", { kind: "aniworld" }), null);
});

test("Akzente und Sonderzeichen blocken keinen Treffer", () => {
  const row = candidate({ id: 6, name: "Re:ZERO -Starting Life in Another World-" });
  assert.notEqual(
    scoreCandidate(row, "Re Zero Starting Life in Another World", { kind: "aniworld" }),
    null,
  );
});

// MARK: - Quelle als Unterscheidung

test("gleichnamiger Anime und Realverfilmung trennen sich über die Quelle", () => {
  const anime = candidate({ id: 10, name: "One Piece", genreIDs: [16], originCountries: ["JP"], posterPath: "/a.jpg" });
  const live = candidate({ id: 11, name: "One Piece", genreIDs: [18], originCountries: ["US"], posterPath: "/b.jpg" });
  assert.equal(bestCandidate([anime, live], "One Piece", { kind: "aniworld" })?.id, 10);
  assert.equal(bestCandidate([anime, live], "One Piece", { kind: "serienstream" })?.id, 11);
});

// MARK: - Jahr

test("das Jahr trennt Neuverfilmungen mit demselben Namen", () => {
  const old = candidate({ id: 20, name: "Hunter x Hunter", firstAirYear: 1999, genreIDs: [16], originCountries: ["JP"] });
  const now = candidate({ id: 21, name: "Hunter x Hunter", firstAirYear: 2011, genreIDs: [16], originCountries: ["JP"] });
  assert.equal(
    bestCandidate([old, now], "Hunter x Hunter", { kind: "aniworld", expectedYear: 2011 })?.id,
    21,
  );
  assert.equal(
    bestCandidate([old, now], "Hunter x Hunter", { kind: "aniworld", expectedYear: 1999 })?.id,
    20,
  );
});

test("ein falsches Jahr allein verwirft keinen genauen Titel", () => {
  const row = candidate({ id: 22, name: "Dark", firstAirYear: 2017 });
  assert.notEqual(
    scoreCandidate(row, "Dark", { kind: "serienstream", expectedYear: 2024 }),
    null,
  );
});

// MARK: - Poster

test("requirePoster überspringt Zeilen ohne Poster", () => {
  const withoutPoster = candidate({ id: 30, name: "Frieren" });
  const withPoster = candidate({ id: 31, name: "Frieren", posterPath: "/f.jpg" });
  assert.equal(bestCandidate([withoutPoster], "Frieren", { kind: "aniworld" })?.id, 30);
  assert.equal(
    bestCandidate([withoutPoster], "Frieren", { kind: "aniworld", requirePoster: true }),
    null,
  );
  assert.equal(
    bestCandidate([withoutPoster, withPoster], "Frieren", { kind: "aniworld", requirePoster: true })?.id,
    31,
  );
});

// MARK: - Die Titel aus der Aufgabenstellung

test("die Schreibweisen der Quellen treffen dieselbe TMDB-Serie", () => {
  // Die Kennungen und Namen sind die von TMDB; sie stehen hier als Festdaten,
  // damit der Fall ohne Netz prüfbar ist.
  const aot = candidate({
    id: 1429,
    name: "Attack on Titan",
    originalName: "進撃の巨人",
    alternateNames: ["Shingeki no Kyojin", "Attack on Titan: Final Season"],
    firstAirYear: 2013,
    genreIDs: [16, 10759, 10765],
    originCountries: ["JP"],
    posterPath: "/a.jpg",
  });
  for (const query of [
    "Attack on Titan",
    "Attack on Titan Staffel 2",
    "Attack on Titan Final Season",
    "Shingeki no Kyojin",
  ]) {
    assert.notEqual(
      scoreCandidate(aot, query, { kind: "aniworld" }),
      null,
      `„${query}“ muss Attack on Titan treffen`,
    );
  }

  const frieren = candidate({
    id: 209867,
    name: "Frieren: Beyond Journey's End",
    originalName: "葬送のフリーレン",
    alternateNames: ["Sousou no Frieren", "Frieren", "Frieren – Nach dem Ende der Reise"],
    firstAirYear: 2023,
    genreIDs: [16],
    originCountries: ["JP"],
  });
  for (const query of ["Frieren", "Sousou no Frieren", "Frieren: Nach dem Ende der Reise"]) {
    assert.notEqual(
      scoreCandidate(frieren, query, { kind: "aniworld" }),
      null,
      `„${query}“ muss Frieren treffen`,
    );
  }

  const simple: [string, TMDBCandidate][] = [
    ["Jujutsu Kaisen", candidate({ id: 95479, name: "Jujutsu Kaisen", originalName: "呪術廻戦", genreIDs: [16], originCountries: ["JP"] })],
    ["Naruto", candidate({ id: 46260, name: "Naruto", originalName: "ＮＡＲＵＴＯ", genreIDs: [16], originCountries: ["JP"] })],
    ["Demon Slayer: Kimetsu no Yaiba", candidate({ id: 85937, name: "Demon Slayer: Kimetsu no Yaiba", genreIDs: [16], originCountries: ["JP"] })],
    ["Dan Da Dan", candidate({ id: 240411, name: "Dan Da Dan", originalName: "ダンダダン", genreIDs: [16], originCountries: ["JP"] })],
    ["Detektiv Conan", candidate({ id: 30983, name: "Detektiv Conan", originalName: "名探偵コナン", genreIDs: [16], originCountries: ["JP"] })],
  ];
  for (const [query, row] of simple) {
    assert.notEqual(scoreCandidate(row, query, { kind: "aniworld" }), null, `„${query}“ muss treffen`);
  }
});

test("ohne Alternativtitel bleibt „Sousou no Frieren“ ohne Treffer", () => {
  // Genau der Zustand, den `/search/tv` liefert: dort stehen keine
  // Alternativtitel. Der Treffer entsteht erst über `/alternative_titles` —
  // siehe den Abruftest weiter unten.
  const bare = candidate({
    id: 209867,
    name: "Frieren: Beyond Journey's End",
    originalName: "葬送のフリーレン",
    genreIDs: [16],
    originCountries: ["JP"],
  });
  assert.equal(scoreCandidate(bare, "Sousou no Frieren", { kind: "aniworld" }), null);
});

// MARK: - Bildadressen

test("tmdbImageURL setzt Host, Kürzel und Pfad zusammen", () => {
  assert.equal(tmdbImageURL("/abc.jpg", "posterCard"), "https://image.tmdb.org/t/p/w342/abc.jpg");
  assert.equal(tmdbImageURL("abc.jpg", "backdropHero"), "https://image.tmdb.org/t/p/w1280/abc.jpg");
  assert.equal(tmdbImageURL("/e.jpg", "still"), "https://image.tmdb.org/t/p/w454_and_h254_bestv2/e.jpg");
});

test("tmdbImageURL macht aus einem fehlenden Pfad keine Adresse", () => {
  assert.equal(tmdbImageURL(null, "posterCard"), null);
  assert.equal(tmdbImageURL("", "posterCard"), null);
  assert.equal(tmdbImageURL(undefined, "logo"), null);
});

test("isTMDBImage erkennt nur TMDB", () => {
  assert.equal(isTMDBImage("https://image.tmdb.org/t/p/w342/a.jpg"), true);
  assert.equal(isTMDBImage("https://aniworld.to/cover.jpg"), false);
  assert.equal(isTMDBImage("kein url"), false);
});

test("bestLogoPath nimmt Deutsch vor Englisch und PNG vor SVG", () => {
  const path = bestLogoPath([
    { file_path: "/en.png", iso_639_1: "en", vote_average: 9 },
    { file_path: "/de.svg", iso_639_1: "de", vote_average: 9 },
    { file_path: "/de.png", iso_639_1: "de", vote_average: 2 },
    { file_path: "/null.png", iso_639_1: null, vote_average: 10 },
  ]);
  assert.equal(path, "/de.png");
  assert.equal(bestLogoPath([{ file_path: "/a.svg", iso_639_1: "de" }]), null);
  assert.equal(bestLogoPath([]), null);
});

// MARK: - Zeilen lesen

test("candidateFromRow liest eine Suchzeile", () => {
  const row = candidateFromRow({
    id: 1429,
    name: "Attack on Titan",
    original_name: "進撃の巨人",
    first_air_date: "2013-04-07",
    popularity: 123.4,
    vote_average: 8.6,
    vote_count: 5400,
    genre_ids: [16, 10765],
    origin_country: ["JP"],
    poster_path: "/p.jpg",
    backdrop_path: "/b.jpg",
    overview: "Titanen.",
  });
  assert.equal(row?.id, 1429);
  assert.equal(row?.firstAirYear, 2013);
  assert.equal(row?.firstAirDate, Date.parse("2013-04-07T00:00:00Z"));
  assert.deepEqual(row?.genreIDs, [16, 10765]);
});

test("candidateFromRow versteht auch die Detailform von genres", () => {
  const row = candidateFromRow({ id: 1, name: "X", genres: [{ id: 16, name: "Animation" }] });
  assert.deepEqual(row?.genreIDs, [16]);
});

test("candidateFromRow verwirft Zeilen ohne Kennung", () => {
  assert.equal(candidateFromRow({ name: "Ohne id" }), null);
  assert.equal(candidateFromRow(null), null);
  assert.equal(candidateFromRow("kaputt"), null);
});

// MARK: - Staffelzuordnung

test("passende Nummer und Folgenzahl ergeben eine sichere Zuordnung", () => {
  const match = pickTmdbSeason({
    sourceSeason: "2",
    sourceEpisodeCount: 12,
    tmdbSeasons: [
      { seasonNumber: 0, episodeCount: 5 },
      { seasonNumber: 1, episodeCount: 25 },
      { seasonNumber: 2, episodeCount: 12 },
    ],
  });
  assert.equal(match?.seasonNumber, 2);
  assert.equal(match?.confidence, "exact");
});

test("ein mitgezähltes Special verhindert keine Zuordnung", () => {
  const match = pickTmdbSeason({
    sourceSeason: "1",
    sourceEpisodeCount: 26,
    tmdbSeasons: [{ seasonNumber: 1, episodeCount: 25 }],
  });
  assert.equal(match?.confidence, "exact");
});

test("bei abweichender Nummer entscheidet eine eindeutige Folgenzahl", () => {
  // Detektiv Conan und andere lange Serien: die Quelle zählt anders als TMDB.
  const match = pickTmdbSeason({
    sourceSeason: "5",
    sourceEpisodeCount: 24,
    tmdbSeasons: [
      { seasonNumber: 1, episodeCount: 50 },
      { seasonNumber: 2, episodeCount: 52 },
      { seasonNumber: 3, episodeCount: 24 },
    ],
  });
  assert.equal(match?.seasonNumber, 3);
  assert.equal(match?.confidence, "counted");
});

test("mehrere gleich lange Staffeln bleiben ohne Zuordnung", () => {
  // Zwei Staffeln mit derselben Folgenzahl sind kein Zeichen, sondern ein
  // Münzwurf — und ein falsches Standbild verrät die Handlung.
  const match = pickTmdbSeason({
    sourceSeason: "9",
    sourceEpisodeCount: 12,
    tmdbSeasons: [
      { seasonNumber: 1, episodeCount: 12 },
      { seasonNumber: 2, episodeCount: 12 },
    ],
  });
  assert.equal(match, null);
});

test("passende Nummer bei widersprechender Folgenzahl gilt nur als schwach", () => {
  const match = pickTmdbSeason({
    sourceSeason: "4",
    sourceEpisodeCount: 16,
    tmdbSeasons: [{ seasonNumber: 4, episodeCount: 28 }],
  });
  assert.equal(match?.seasonNumber, 4);
  assert.equal(match?.confidence, "weak");
});

test("„Filme“ und Staffel 0 bekommen nie eine Zuordnung", () => {
  assert.equal(
    pickTmdbSeason({ sourceSeason: "filme", sourceEpisodeCount: 3, tmdbSeasons: [{ seasonNumber: 1, episodeCount: 3 }] }),
    null,
  );
  assert.equal(
    pickTmdbSeason({ sourceSeason: "0", sourceEpisodeCount: 3, tmdbSeasons: [{ seasonNumber: 0, episodeCount: 3 }] }),
    null,
  );
  assert.equal(
    pickTmdbSeason({ sourceSeason: "1", sourceEpisodeCount: 3, tmdbSeasons: [{ seasonNumber: 0, episodeCount: 3 }] }),
    null,
  );
});

// MARK: - Folgenzuordnung

function tmdbEpisode(number: number, title: string | null): TMDBEpisodeInfo {
  return {
    episodeNumber: number,
    title,
    overview: `Beschreibung ${number}`,
    still: `https://image.tmdb.org/t/p/w454_and_h254_bestv2/e${number}.jpg`,
    airDate: "2024-01-01",
    runtime: 24,
  };
}

test("gleiche Zählung ordnet Folge auf Folge", () => {
  const alignment = alignEpisodes(
    [{ number: 1, germanTitle: "Der Anfang" }, { number: 2, germanTitle: "Die Reise" }],
    [tmdbEpisode(1, "Der Anfang"), tmdbEpisode(2, "Die Reise")],
  );
  assert.equal(alignment.offset, 0);
  assert.equal(alignment.confirmed, true);
  assert.equal(alignment.pairs.get(1)?.episodeNumber, 1);
  assert.equal(alignment.pairs.get(2)?.episodeNumber, 2);
});

test("ein Versatz wird über die Folgentitel erkannt", () => {
  // Der Attack-on-Titan-Fall: die Quelle beginnt wieder bei Folge 1, TMDB
  // zählt in derselben Staffel ab 17 weiter.
  const alignment = alignEpisodes(
    [
      { number: 1, germanTitle: "Dämmerung der Menschheit" },
      { number: 2, germanTitle: "Vergeltungsschlacht" },
      { number: 3, germanTitle: "Zwei Brüder im Kampf" },
    ],
    [
      tmdbEpisode(16, "Vorher und nachher"),
      tmdbEpisode(17, "Dämmerung der Menschheit"),
      tmdbEpisode(18, "Vergeltungsschlacht"),
      tmdbEpisode(19, "Zwei Brüder im Kampf"),
    ],
  );
  assert.equal(alignment.offset, 16);
  assert.equal(alignment.pairs.get(1)?.episodeNumber, 17);
  assert.equal(alignment.pairs.get(3)?.episodeNumber, 19);
});

test("ein einzelner Titeltreffer belegt keinen Versatz", () => {
  // Ein gleichnamiger Recap darf die ganze Staffel nicht verschieben.
  const alignment = alignEpisodes(
    [{ number: 1, germanTitle: "Rückblick auf alles" }, { number: 2, germanTitle: "Etwas Neues hier" }],
    [tmdbEpisode(1, "Ganz was anderes"), tmdbEpisode(9, "Rückblick auf alles")],
  );
  assert.equal(alignment.offset, 0);
  assert.equal(alignment.confirmed, true);
  assert.equal(alignment.pairs.get(1)?.episodeNumber, 1);
});

test("Platzhaltertitel von TMDB gelten nicht als Titel", () => {
  assert.equal(namedEpisodeTitle("Folge 11"), null);
  assert.equal(namedEpisodeTitle("Episode 11"), null);
  assert.equal(namedEpisodeTitle("  "), null);
  assert.equal(namedEpisodeTitle("Der Anfang"), "Der Anfang");
  // Ein Versatz darf nicht aus Platzhaltern entstehen, die überall passen.
  const alignment = alignEpisodes(
    [{ number: 1, germanTitle: "Folge 1" }, { number: 2, germanTitle: "Folge 2" }],
    [tmdbEpisode(5, "Folge 5"), tmdbEpisode(6, "Folge 6")],
  );
  assert.equal(alignment.offset, 0);
  assert.equal(alignment.confirmed, false);
});

test("mehr Quellfolgen als TMDB-Folgen lässt den Rest einfach leer", () => {
  const alignment = alignEpisodes(
    [{ number: 1 }, { number: 2 }, { number: 3 }],
    [tmdbEpisode(1, "Eins"), tmdbEpisode(2, "Zwei")],
  );
  assert.equal(alignment.pairs.size, 2);
  assert.equal(alignment.pairs.has(3), false);
});

test("eine schwache Zuordnung ohne Titelbestätigung wird nicht benutzt", () => {
  const weak = pickTmdbSeason({
    sourceSeason: "4",
    sourceEpisodeCount: 16,
    tmdbSeasons: [{ seasonNumber: 4, episodeCount: 28 }],
  });
  assert.ok(weak);
  const blind = alignEpisodes([{ number: 1 }], [tmdbEpisode(1, "Folge 1")]);
  assert.equal(alignmentIsUsable(weak, blind), false);
  const confirmed = alignEpisodes(
    [{ number: 1, germanTitle: "Dämmerung der Menschheit" }],
    [tmdbEpisode(1, "Dämmerung der Menschheit")],
  );
  assert.equal(alignmentIsUsable(weak, confirmed), true);
});

// MARK: - Rückweg auf den Nori-Katalog

test("der Katalogindex findet den Nori-Titel zu einer TMDB-Zeile", () => {
  const index = new HomeCatalogIndex([
    title({ slug: "vinland-saga", title: "Vinland Saga" }),
    title({ slug: "dark", title: "Dark", provider: "serienstream" }),
  ]);
  const row = candidate({ id: 40, name: "Vinland Saga", genreIDs: [16], originCountries: ["JP"] });
  assert.equal(index.match(row)?.slug, "vinland-saga");
});

test("der Katalogindex lehnt Titel ab, die Nori nicht hat", () => {
  // Der Kern der Regel: TMDBs Ranglisten bestehen überwiegend aus Titeln, die
  // Nori nicht anbietet. Keiner davon darf auf der Startseite landen.
  const index = new HomeCatalogIndex([title({ slug: "dark", title: "Dark", provider: "serienstream" })]);
  const row = candidate({ id: 41, name: "Stranger Things", genreIDs: [18], originCountries: ["US"] });
  assert.equal(index.match(row), null);
});

test("der Katalogindex trifft über einen Alternativtitel der Quelle", () => {
  const index = new HomeCatalogIndex([
    title({
      slug: "daemonenjaeger",
      title: "Dämonenjäger",
      alts: ["Demon Slayer: Kimetsu no Yaiba"],
    }),
  ]);
  const row = candidate({
    id: 42,
    name: "Demon Slayer: Kimetsu no Yaiba",
    genreIDs: [16],
    originCountries: ["JP"],
  });
  assert.equal(index.match(row)?.slug, "daemonenjaeger");
});

// MARK: - Reihenfolge der Startseite

const NOW = Date.parse("2026-03-01T12:00:00Z");
const DAY = 86_400_000;

test("Trend schlägt Beliebtheit, Aktualität schlägt Alter", () => {
  const trendy = homeCandidate("trendy", { trendingRank: 2, popularity: 20, firstAirDate: NOW - 900 * DAY });
  const popular = homeCandidate("popular", { popularity: 400, firstAirDate: NOW - 900 * DAY });
  const fresh = homeCandidate("fresh", { popularity: 20, lastAirDate: NOW - 3 * DAY });
  const ancient = homeCandidate("ancient", { popularity: 20, firstAirDate: NOW - 4000 * DAY });

  assert.ok(newAndPopularScore(trendy, NOW) > newAndPopularScore(popular, NOW));
  assert.ok(newAndPopularScore(fresh, NOW) > newAndPopularScore(ancient, NOW));
});

test("eine gute Bewertung ohne Stimmen zählt nicht", () => {
  const thin = homeCandidate("thin", { popularity: 10, voteAverage: 10, voteCount: 2 });
  const solid = homeCandidate("solid", { popularity: 10, voteAverage: 8.6, voteCount: 5000 });
  assert.ok(newAndPopularScore(solid, NOW) > newAndPopularScore(thin, NOW));
  assert.equal(topRated([thin, solid], { minimumVotes: 300 }).length, 1);
});

test("Titel ohne jedes TMDB-Signal stehen nicht in „Neu & beliebt“", () => {
  // Genau das war die alte Startseite: `catalog.items.slice(0, 24)` als
  // „beliebt". Ohne Signal gibt es keine Aussage, also keine Reihe.
  const blank = homeCandidate("blank");
  assert.deepEqual(newAndPopular([blank], NOW), []);
});

test("Ausschlüsse und Deckel greifen", () => {
  const rows = [
    homeCandidate("a", { trendingRank: 1 }),
    homeCandidate("b", { trendingRank: 2 }),
    homeCandidate("c", { trendingRank: 3 }),
  ];
  const list = newAndPopular(rows, NOW, { excluding: new Set(["aniworld|a"]), limit: 1 });
  assert.equal(list.length, 1);
  assert.equal(list[0].title.slug, "b");
});

test("die Trendreihe ordnet nach Platz, nicht nach Punkten", () => {
  const rows = [
    homeCandidate("drei", { trendingRank: 3, popularity: 900 }),
    homeCandidate("eins", { trendingRank: 1, popularity: 1 }),
  ];
  assert.deepEqual(trending(rows).map((row) => row.title.slug), ["eins", "drei"]);
});

test("der Kopfbereich nimmt nur Titel mit Breitbild und rotiert über den Tag", () => {
  const withBackdrop = [1, 2, 3].map((index) =>
    homeCandidate(`hero${index}`, { trendingRank: index, hasBackdrop: true }));
  const withoutBackdrop = homeCandidate("flat", { trendingRank: 1 });

  const picks = heroPicks([...withBackdrop, withoutBackdrop], NOW, 0, { limit: 5 });
  assert.deepEqual(picks.map((pick) => pick.title.slug), ["hero1", "hero2", "hero3"]);

  const nextDay = heroPicks([...withBackdrop, withoutBackdrop], NOW, 1, { limit: 5 });
  assert.deepEqual(nextDay.map((pick) => pick.title.slug), ["hero2", "hero3", "hero1"]);

  // Durchgesehenes gehört nicht in den Kopfbereich.
  const seen = homeCandidate("seen", { trendingRank: 1, hasBackdrop: true }, { watchedRatio: 1 });
  assert.deepEqual(heroPicks([seen], NOW, 0), []);
});

test("das Geschmacksprofil entsteht nur aus lokalen Daten", () => {
  const catalog = [
    title({ slug: "vinland-saga", title: "Vinland Saga", genres: ["Action", "Drama"] }),
    title({ slug: "frieren", title: "Frieren", genres: ["Abenteuer"] }),
    title({ slug: "neu", title: "Neu", genres: ["Action"] }),
  ];
  const progress: WatchProgress[] = [{
    slug: "vinland-saga",
    title: "Vinland Saga",
    season: "1",
    episode: 3,
    episodePath: "/anime/stream/vinland-saga/staffel-1/episode-3",
    germanTitle: "",
    englishTitle: "",
    positionSec: 1200,
    durationSec: 1400,
    updatedAt: NOW - DAY,
    provider: "aniworld",
  }];
  const signals = new Map<string, TMDBSignals>([
    ["aniworld|vinland-saga", { ...emptySignals(), tmdbID: 79144, genreIDs: [16, 18] }],
  ]);

  const profile = tasteProfile({
    progress,
    favorites: ["frieren"],
    favoriteSource: { frieren: "aniworld" },
    catalog,
    signals,
    now: NOW,
  });
  assert.ok(profile.genreWeights.has("action"));
  assert.ok(profile.touched.has("aniworld|vinland-saga"));
  assert.ok(profile.touched.has("aniworld|frieren"));
  assert.deepEqual(profile.seeds, [79144]);

  // „Für dich" zeigt nichts, womit der Nutzer schon zu tun hatte.
  const suggestion = homeCandidate("neu", { tmdbID: 1, voteAverage: 8.5, voteCount: 900 });
  suggestion.title = catalog[2];
  const touched = homeCandidate("vinland-saga", { tmdbID: 79144 });
  touched.title = catalog[0];
  const picks = recommend([suggestion, touched], profile);
  assert.deepEqual(picks.map((pick) => pick.title.slug), ["neu"]);
});

test("eine TMDB-Empfehlung wiegt schwerer als eine Genreüberschneidung", () => {
  const profile = tasteProfile({
    progress: [],
    favorites: [],
    favoriteSource: {},
    catalog: [],
    signals: new Map(),
    now: NOW,
  });
  const recommended = new Map([[42, 2]]);
  const named = homeCandidate("named", { tmdbID: 42 });
  const other = homeCandidate("other", { tmdbID: 43, voteAverage: 9, voteCount: 5000 });
  const picks = recommend([other, named], profile, { recommended });
  assert.equal(picks[0].title.slug, "named");
});

test("buildCandidates verbindet TMDB-Listen mit dem Nori-Katalog", () => {
  const catalog = [
    title({ slug: "vinland-saga", title: "Vinland Saga" }),
    title({ slug: "unbekannt", title: "Ganz Unbekannt" }),
  ];
  const rows = [
    candidate({ id: 1, name: "Vinland Saga", popularity: 50, voteAverage: 8.8, voteCount: 900, genreIDs: [16], originCountries: ["JP"], backdropPath: "/b.jpg" }),
    // Steht nicht im Nori-Katalog und darf deshalb nirgends auftauchen.
    candidate({ id: 2, name: "Stranger Things", popularity: 900, genreIDs: [18], originCountries: ["US"] }),
  ];
  const built = buildCandidates({ catalog, trending: rows, now: NOW });
  assert.equal(built.length, 2);
  const vinland = built.find((row) => row.title.slug === "vinland-saga");
  assert.equal(vinland?.signals.tmdbID, 1);
  assert.equal(vinland?.signals.trendingRank, 1);
  assert.equal(vinland?.signals.hasBackdrop, true);
  const unknown = built.find((row) => row.title.slug === "unbekannt");
  assert.equal(unknown?.signals.tmdbID, null);
});

test("buildCandidates behält bereits bekannte Signale", () => {
  const catalog = [title({ slug: "frieren", title: "Frieren" })];
  const known = new Map<string, TMDBSignals>([
    ["aniworld|frieren", { ...emptySignals(), tmdbID: 209867, voteAverage: 8.7, voteCount: 700 }],
  ]);
  const built = buildCandidates({ catalog, known, now: NOW });
  assert.equal(built[0].signals.tmdbID, 209867);
  assert.equal(built[0].signals.voteCount, 700);
});

test("neue Folgen kommen chronologisch und nur für vorhandene Titel", () => {
  const entry = (slug: string, offset: number, episode = 1): AiringEntry => ({
    airingAt: NOW + offset,
    episode,
    season: "1",
    title: slug,
    slug,
    languages: ["DE"],
    dayKey: "2026-03-01",
    dayLabel: "Heute",
    provider: "aniworld",
  });
  const list = recentEpisodes(
    [entry("alt", -2 * DAY), entry("neu", -DAY), entry("morgen", DAY), entry("fremd", -DAY)],
    NOW,
    { availableIds: new Set(["aniworld|alt", "aniworld|neu"]) },
  );
  assert.deepEqual(list.map((row) => row.slug), ["neu", "alt"]);
});

test("dieselbe Folge in vier Sprachen füllt die Reihe nicht", () => {
  const entries: AiringEntry[] = ["DE", "GerSub", "EN", "JP"].map((lang) => ({
    airingAt: NOW - DAY,
    episode: 5,
    season: "1",
    title: "Frieren",
    slug: "frieren",
    languages: [lang],
    dayKey: "2026-02-28",
    dayLabel: "Gestern",
    provider: "aniworld",
  }));
  assert.equal(recentEpisodes(entries, NOW).length, 1);
});

// MARK: - Abrufweg

test("ohne Schlüssel wird gar nicht gefragt", async () => {
  const http = new FakeHttp([]);
  const client = new TMDBClient(new DirectTMDBTransport("", http));
  assert.equal(client.available, false);
  const { result, status } = await client.findSeries({ title: "Frieren", provider: "aniworld" });
  assert.equal(result, null);
  assert.equal(status, "noKey");
  assert.equal(http.calls.length, 0);
});

test("der Zustand ohne TMDB ist ausdrücklich", async () => {
  const client = new TMDBClient(new NoTMDBTransport());
  assert.equal(client.available, false);
  assert.deepEqual((await client.feed("popular")).rows, []);
  assert.equal((await client.series(1)).details, null);
  assert.equal((await client.logo(1)).url, null);
});

test("401 bricht die Suche ab, statt weitere Begriffe zu verbrennen", async () => {
  const http = new FakeHttp([{ match: "search/tv", status: 401 }]);
  const client = new TMDBClient(new DirectTMDBTransport("falsch", http));
  const { result, status } = await client.findSeries({
    title: "Attack on Titan",
    alternates: ["Shingeki no Kyojin"],
    provider: "aniworld",
  });
  assert.equal(result, null);
  assert.equal(status, "unauthorized");
  assert.equal(http.calls.length, 1);
});

test("429 und 404 enden als Befund, nicht als Ausnahme", async () => {
  const limited = new TMDBClient(new DirectTMDBTransport("k", new FakeHttp([{ match: "search/tv", status: 429 }])));
  assert.equal((await limited.findSeries({ title: "Frieren", provider: "aniworld" })).status, "rateLimited");

  const missing = new TMDBClient(new DirectTMDBTransport("k", new FakeHttp([{ match: "tv/999", status: 404 }])));
  const { details, status } = await missing.series(999);
  assert.equal(details, null);
  assert.equal(status, "notFound");
});

test("ein Netzfehler endet als leeres Ergebnis", async () => {
  const http = new FakeHttp([{ match: "search/tv", body: { results: [] } }], "search/tv");
  const client = new TMDBClient(new DirectTMDBTransport("k", http));
  const { result, status } = await client.findSeries({ title: "Frieren", provider: "aniworld" });
  assert.equal(result, null);
  assert.equal(status, "unavailable");
});

test("HTTP 200 mit kaputtem JSON ist kein Treffer", async () => {
  const http = new FakeHttp([{ match: "search/tv", body: "<html>Anmeldung nötig</html>" }]);
  const client = new TMDBClient(new DirectTMDBTransport("k", http));
  assert.equal((await client.search("Frieren")).status, "unavailable");
});

test("findSeries geht die Begriffe in absteigender Güte durch", async () => {
  const http = new FakeHttp([
    { match: "query=D%C3%A4monenj%C3%A4ger", body: { results: [] } },
    {
      match: "query=Demon+Slayer",
      body: {
        results: [{
          id: 85937,
          name: "Demon Slayer: Kimetsu no Yaiba",
          genre_ids: [16],
          origin_country: ["JP"],
          poster_path: "/d.jpg",
        }],
      },
    },
  ]);
  const client = new TMDBClient(new DirectTMDBTransport("k", http));
  const { result } = await client.findSeries({
    title: "Dämonenjäger",
    alternates: ["Demon Slayer"],
    provider: "aniworld",
  });
  assert.equal(result?.candidate.id, 85937);
  assert.equal(result?.query, "Demon Slayer");
  assert.equal(result?.viaAlternates, false);
});

test("die Alternativtitel von TMDB retten „Sousou no Frieren“", async () => {
  // Der Fall aus der Aufgabenstellung: `/search/tv` findet den Eintrag, aber
  // sein Name hat mit dem Quelltitel nichts gemeinsam. Erst die
  // Alternativtitel belegen, dass es dieselbe Serie ist — die Schwelle bleibt
  // dieselbe, nur die Datenlage wird besser.
  const http = new FakeHttp([
    {
      match: "search/tv",
      body: {
        results: [{
          id: 209867,
          name: "Frieren: Beyond Journey's End",
          original_name: "葬送のフリーレン",
          genre_ids: [16],
          origin_country: ["JP"],
          poster_path: "/f.jpg",
        }],
      },
    },
    {
      match: "alternative_titles",
      body: { results: [{ title: "Sousou no Frieren" }, { title: "Frieren" }] },
    },
  ]);
  const client = new TMDBClient(new DirectTMDBTransport("k", http));
  const { result } = await client.findSeries({ title: "Sousou no Frieren", provider: "aniworld" });
  assert.equal(result?.candidate.id, 209867);
  assert.equal(result?.viaAlternates, true);
});

test("die Alternativtitel erzeugen keinen Treffer, wenn sie nicht passen", async () => {
  const http = new FakeHttp([
    {
      match: "search/tv",
      body: { results: [{ id: 1399, name: "Game of Thrones", genre_ids: [18], origin_country: ["US"] }] },
    },
    { match: "alternative_titles", body: { results: [{ title: "Das Lied von Eis und Feuer" }] } },
  ]);
  const client = new TMDBClient(new DirectTMDBTransport("k", http));
  const { result } = await client.findSeries({ title: "Sousou no Frieren", provider: "aniworld" });
  assert.equal(result, null);
});

test("series liest Staffelliste, Status und letzte Ausstrahlung", async () => {
  const http = new FakeHttp([{
    match: "tv/1429",
    body: {
      id: 1429,
      name: "Attack on Titan",
      last_air_date: "2023-11-05",
      status: "Ended",
      episode_run_time: [0, 24],
      genres: [{ id: 16 }],
      seasons: [
        { season_number: 0, episode_count: 8, name: "Specials" },
        { season_number: 1, episode_count: 25, name: "Staffel 1", air_date: "2013-04-07" },
        { season_number: 4, episode_count: 28, name: "Final Season" },
      ],
    },
  }]);
  const client = new TMDBClient(new DirectTMDBTransport("k", http));
  const { details } = await client.series(1429);
  assert.equal(details?.seasons.length, 3);
  assert.equal(details?.seasons[1].episodeCount, 25);
  assert.equal(details?.seriesStatus, "Ended");
  assert.equal(details?.episodeRuntime, 24);
  assert.equal(details?.lastAirDate, Date.parse("2023-11-05T00:00:00Z"));
});

test("season liefert Titel, Beschreibung, Standbild und Laufzeit", async () => {
  const http = new FakeHttp([{
    match: "tv/209867/season/1",
    body: {
      episodes: [
        { episode_number: 1, name: "Das Ende der Reise", overview: "Himmel.", still_path: "/s1.jpg", air_date: "2023-09-29", runtime: 24 },
        { episode_number: 2, name: "Folge 2", overview: "", still_path: null, air_date: "2023-10-06", runtime: 0 },
      ],
    },
  }]);
  const client = new TMDBClient(new DirectTMDBTransport("k", http));
  const { episodes } = await client.season(209867, 1);
  assert.equal(episodes.length, 2);
  assert.equal(episodes[0].still, "https://image.tmdb.org/t/p/w454_and_h254_bestv2/s1.jpg");
  assert.equal(episodes[0].runtime, 24);
  // Null Minuten ist keine Auskunft, sondern eine Lücke.
  assert.equal(episodes[1].runtime, null);
  assert.equal(episodes[1].still, null);
});

test("related führt Empfehlungen und Ähnliches ohne Dubletten zusammen", async () => {
  const http = new FakeHttp([
    { match: "recommendations", body: { results: [{ id: 1, name: "A" }, { id: 2, name: "B" }] } },
    { match: "similar", body: { results: [{ id: 2, name: "B" }, { id: 3, name: "C" }] } },
  ]);
  const client = new TMDBClient(new DirectTMDBTransport("k", http));
  const { rows } = await client.related(5);
  assert.deepEqual(rows.map((row) => row.id), [1, 2, 3]);
});

test("der Serverweg hängt keinen Schlüssel an und erkennt einen Server ohne", async () => {
  const withKey = new FakeHttp([{ match: "/api/tmdb/search/tv", body: { results: [{ id: 1, name: "Frieren" }] } }]);
  const client = new TMDBClient(new ServerTMDBTransport("http://192.168.1.20:8730/", withKey));
  const { rows } = await client.search("Frieren");
  assert.equal(rows.length, 1);
  assert.ok(withKey.calls[0].startsWith("http://192.168.1.20:8730/api/tmdb/search/tv?"));
  assert.equal(withKey.calls[0].includes("api_key"), false);

  const withoutKey = new FakeHttp([{ match: "/api/tmdb/", body: { kind: "noKey", error: "Kein TMDB-Schlüssel" } }]);
  const bare = new TMDBClient(new ServerTMDBTransport("http://192.168.1.20:8730", withoutKey));
  assert.equal((await bare.search("Frieren")).status, "noKey");
});

test("eine Rangliste holt beide Seiten und lässt Dubletten weg", async () => {
  const http = new FakeHttp([
    { match: "page=1", body: { results: [{ id: 1, name: "A" }, { id: 2, name: "B" }] } },
    { match: "page=2", body: { results: [{ id: 2, name: "B" }, { id: 3, name: "C" }] } },
  ]);
  const client = new TMDBClient(new DirectTMDBTransport("k", http));
  const { rows, status } = await client.feed("trendingWeek", NOW);
  assert.deepEqual(rows.map((row) => row.id), [1, 2, 3]);
  assert.equal(status, "ok");
});

test("die Anime-Ranglisten grenzen auf Zeichentrick aus Japan ein", async () => {
  const http = new FakeHttp([{ match: "discover/tv", body: { results: [] } }]);
  const client = new TMDBClient(new DirectTMDBTransport("k", http));
  await client.feed("animeAiringRecently", NOW);
  const call = http.calls[0];
  assert.ok(call.includes("with_genres=16"));
  assert.ok(call.includes("with_origin_country=JP"));
  assert.ok(call.includes("air_date.gte=2026-01-15"));
});
