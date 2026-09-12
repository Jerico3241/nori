import assert from "node:assert/strict";
import { test } from "node:test";

import { tmdb } from "../src/index.js";

// Dieselben Fälle wie in `native/Tests/NoriCoreTests/TMDBMatcherTests.swift`
// und `TMDBArtworkTests.swift`. Wenn eine der beiden Seiten hier abweicht,
// zeigen iOS und der Fernseher unterschiedliche Cover — genau das war vorher
// der Fall, weil die webOS-App gar nicht bewertete, sondern die erste Zeile
// mit einem Bild nahm.

function candidate(over: Partial<tmdb.TmdbCandidate> = {}): tmdb.TmdbCandidate {
  return {
    id: 1, name: "Titel", originalName: "Titel", alternateNames: [],
    firstAirYear: null, popularity: 0, voteAverage: 0,
    genreIds: [], originCountries: [],
    posterPath: "/p.jpg", backdropPath: null, overview: null,
    ...over,
  };
}

test("Normalisierung faltet Schreibweise, Akzente und Satzzeichen", () => {
  assert.equal(tmdb.normalize("Re:ZERO – Starting Life"), "re zero starting life");
  assert.equal(tmdb.normalize("Pokémon"), "pokemon");
  assert.equal(tmdb.normalize("  Dr. Stone  "), "dr stone");
});

test("Ziffern bleiben stehen", () => {
  assert.equal(tmdb.normalize("86"), "86");
  assert.equal(tmdb.stripVariants("91 Days"), "91 days");
});

test("Staffel- und Jahresangaben fallen weg", () => {
  assert.equal(tmdb.stripVariants("Attack on Titan Staffel 2"), "attack on titan");
  assert.equal(tmdb.stripVariants("Dr. Stone Season 3"), "dr stone");
  assert.equal(tmdb.stripVariants("Shingeki no Kyojin The Final Season"), "shingeki no kyojin");
  assert.equal(tmdb.stripVariants("Irgendwas 2024"), "irgendwas");
});

test("Die Kette enthält die bereinigte Fassung", () => {
  // Gemessen: „Attack on Titan Staffel 2" liefert bei TMDB null Zeilen,
  // „attack on titan" vier.
  const chain = tmdb.queries("Attack on Titan Staffel 2");
  assert.equal(chain[0], "Attack on Titan Staffel 2");
  assert.ok(chain.some((q) => tmdb.normalize(q) === "attack on titan"), `Kette war ${chain.join(" | ")}`);
});

test("Die Kette beginnt mit dem Titel der Quelle, dann die Alternativen", () => {
  const chain = tmdb.queries("Dr. Stone", ["Doctor Stone"]);
  assert.equal(chain[0], "Dr. Stone");
  assert.ok(chain.includes("Doctor Stone"));
});

test("Der Teil vor dem Doppelpunkt kommt dazu", () => {
  assert.ok(tmdb.queries("Kaguya-sama: Love is War").some((q) => tmdb.normalize(q) === "kaguya sama"));
});

test("Beliebtheit erzeugt keinen Treffer", () => {
  const fremd = candidate({ id: 9, name: "Ganz etwas anderes", originalName: "Ganz etwas anderes", popularity: 900 });
  assert.equal(tmdb.best([fremd], "One Piece", "aniworld"), null);
});

test("Ein kurzes Wort im längeren Titel ist kein Treffer", () => {
  const onePiece = candidate({ id: 37854, name: "One Piece", originalName: "ワンピース" });
  assert.equal(tmdb.best([onePiece], "One", "aniworld"), null);
});

test("Staffelzusatz trifft weiterhin dieselbe Serie", () => {
  const aot = candidate({ id: 1429, name: "Attack on Titan", originalName: "進撃の巨人" });
  assert.equal(tmdb.best([aot], "Attack on Titan Staffel 2", "aniworld")?.id, 1429);
});

test("Romaji trifft erst über die Alternativtitel", () => {
  // Der belegte Fall: `/search/tv?query=Shingeki no Kyojin` liefert genau
  // eine Zeile, nämlich #1429 — mit name „Attack on Titan" und
  // original_name „進撃の巨人". Die Umschrift steht nur in
  // `/alternative_titles`.
  const bare = candidate({ id: 1429, name: "Attack on Titan", originalName: "進撃の巨人" });
  assert.equal(tmdb.best([bare], "Shingeki no Kyojin", "aniworld"), null);

  const enriched = { ...bare, alternateNames: ["Shingeki no Kyojin", "Angriff auf Titan"] };
  assert.equal(tmdb.best([enriched], "Shingeki no Kyojin", "aniworld")?.id, 1429);
});

test("Alternativtitel erzeugen keinen Treffer aus dem Nichts", () => {
  const fremd = candidate({ name: "Etwas anderes", originalName: "Etwas anderes", alternateNames: ["Noch was"] });
  assert.equal(tmdb.best([fremd], "Shingeki no Kyojin", "aniworld"), null);
});

test("Anime und Realverfilmung trennen sich über die Quelle", () => {
  const anime = candidate({ id: 1, name: "Death Note", genreIds: [16], originCountries: ["JP"] });
  const real = candidate({ id: 2, name: "Death Note", genreIds: [18], originCountries: ["US"] });
  assert.equal(tmdb.best([anime, real], "Death Note", "aniworld")?.id, 1);
  assert.equal(tmdb.best([anime, real], "Death Note", "serienstream")?.id, 2);
});

test("Das Jahr trennt Neuverfilmungen", () => {
  const alt = candidate({ id: 1, name: "Cowboy Bebop", firstAirYear: 1998 });
  const neu = candidate({ id: 2, name: "Cowboy Bebop", firstAirYear: 2021 });
  assert.equal(tmdb.best([alt, neu], "Cowboy Bebop", "aniworld", { expectedYear: 1998 })?.id, 1);
  assert.equal(tmdb.best([alt, neu], "Cowboy Bebop", "aniworld", { expectedYear: 2021 })?.id, 2);
});

test("Ohne Poster nur dann verworfen, wenn eines verlangt ist", () => {
  const ohne = candidate({ id: 42, name: "Ohne Titelbild", posterPath: null });
  assert.equal(tmdb.best([ohne], "Ohne Titelbild", "aniworld", { requirePoster: true }), null);
  assert.equal(tmdb.best([ohne], "Ohne Titelbild", "aniworld")?.id, 42);
});

test("Bildadressen entstehen an einer Stelle", () => {
  assert.equal(tmdb.imageURL("/a.jpg", "backdropHero"), "https://image.tmdb.org/t/p/w1280/a.jpg");
  assert.equal(tmdb.imageURL("a.jpg", "posterCard"), "https://image.tmdb.org/t/p/w342/a.jpg");
  assert.equal(tmdb.imageURL("/s.jpg", "still"), "https://image.tmdb.org/t/p/w454_and_h254_bestv2/s.jpg");
});

test("Kein Bild heißt kein Bild, nicht der nackte Host", () => {
  assert.equal(tmdb.imageURL(null, "posterCard"), null);
  assert.equal(tmdb.imageURL("", "posterCard"), null);
  assert.equal(tmdb.imageURL(undefined, "logo"), null);
});

test("Eine fertige Adresse wird nicht noch einmal zusammengesetzt", () => {
  const fertig = "https://image.tmdb.org/t/p/w500/a.jpg";
  assert.equal(tmdb.imageURL(fertig, "posterCard"), fertig);
});

test("Logo: Deutsch vor Englisch vor sprachlos vor allem anderen", () => {
  assert.ok(tmdb.languageRank("de") < tmdb.languageRank("en"));
  assert.ok(tmdb.languageRank("en") < tmdb.languageRank(null));
  assert.ok(tmdb.languageRank(null) < tmdb.languageRank("ja"));
  assert.equal(
    tmdb.bestLogoPath([{ file_path: "/ja.png", iso_639_1: "ja", vote_average: 9 }, { file_path: "/n.png", vote_average: 1 }]),
    "/n.png",
  );
});

test("SVG wird nie gewählt", () => {
  assert.equal(
    tmdb.bestLogoPath([{ file_path: "/de.svg", iso_639_1: "de" }, { file_path: "/ja.png", iso_639_1: "ja" }]),
    "/ja.png",
  );
  assert.equal(tmdb.bestLogoPath([{ file_path: "/a.svg", iso_639_1: "de" }]), null);
});

test("Nur 404 darf dauerhaft gemerkt werden", () => {
  assert.equal(tmdb.failureFromStatus(200), null);
  assert.equal(tmdb.failureFromStatus(404), "notFound");
  assert.equal(tmdb.failureFromStatus(429), "rateLimited");
  assert.equal(tmdb.failureFromStatus(401), "unauthorized");
  assert.equal(tmdb.isDefinitive("notFound"), true);
  for (const f of ["rateLimited", "unauthorized", "network", "server", "malformed", "noKey"] as tmdb.TmdbFailure[]) {
    assert.equal(tmdb.isDefinitive(f), false, `${f} darf nicht dauerhaft gemerkt werden`);
  }
});

test("Zeilen ohne Kennung sind keine Kandidaten", () => {
  assert.equal(tmdb.candidateFromRow({ name: "Ohne id" }), null);
  const row = tmdb.candidateFromRow({ id: 7, name: "Mit id", first_air_date: "2019-07-05", poster_path: "" });
  assert.equal(row?.firstAirYear, 2019);
  assert.equal(row?.posterPath, null, "Ein leerer Pfad ist kein Poster");
});
