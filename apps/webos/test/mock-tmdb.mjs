// Ein Nachbau von TMDB mit festen Daten.
//
// Wofür: Die Startseite, die Detailseite und die Folgenkacheln hängen an
// TMDB. Ohne Nachbau ließe sich davon nichts durchspielen — und ein Test gegen
// das echte TMDB bräuchte einen Schlüssel, eine Internetverbindung und wäre
// von der Ratenbegrenzung abhängig. Er sagte am Ende mehr über TMDBs Tagesform
// als über Nori.
//
// Die Antworten haben dieselbe Form wie die echten. Drei Fälle sind absichtlich
// eingebaut, weil genau sie in der Praxis schiefgehen:
//
// 1. **Ein Titel, dessen TMDB-Name mit dem Quelltitel nichts gemeinsam hat**
//    („Pluto" → „Pluto: The Last Robot"). Er darf nur über
//    `/alternative_titles` treffen — der Weg, der „Sousou no Frieren" rettet.
// 2. **Eine Serie mit versetzter Folgenzählung** („Vinland Saga" Staffel 1 bei
//    TMDB ab Folge 17). Die Zuordnung darf nicht nach Nummer zuschlagen,
//    sondern muss den Versatz über die Folgentitel finden.
// 3. **Ein Titel, den TMDB gar nicht führt** („Barakamon"). Er muss ohne
//    Bild und ohne Fehler dastehen.

/** Serien, die dieser Nachbau kennt. Der Schlüssel ist der Nori-Slug. */
const SERIES = {
  frieren: {
    id: 209867,
    name: "Frieren: Nach dem Ende der Reise",
    original: "葬送のフリーレン",
    alternates: ["Sousou no Frieren", "Frieren"],
    firstAir: "2023-09-29",
    lastAir: "2024-03-22",
    popularity: 320,
    vote: 8.7,
    votes: 1400,
    seasons: [{ n: 1, count: 12 }, { n: 2, count: 12 }],
    trending: 1,
  },
  "one-piece": {
    id: 37854,
    name: "One Piece",
    original: "ワンピース",
    alternates: ["One Piece"],
    firstAir: "1999-10-20",
    lastAir: "2026-02-15",
    popularity: 480,
    vote: 8.7,
    votes: 4900,
    seasons: [{ n: 1, count: 12 }, { n: 2, count: 12 }],
    trending: 2,
  },
  "vinland-saga": {
    id: 85077,
    name: "Vinland Saga",
    original: "ヴィンランド・サガ",
    alternates: ["Vinland Saga"],
    firstAir: "2019-07-08",
    lastAir: "2023-06-19",
    popularity: 160,
    vote: 8.6,
    votes: 900,
    /*
     * Versetzte Zählung — dieselbe Aufteilung, die „Attack on Titan Final
     * Season" hat: die Quelle beginnt bei Folge 1, TMDB zählt in derselben
     * Staffel ab 17 weiter. Die Zuordnung muss den Versatz über die
     * Folgentitel finden; nach Nummer zugeordnet stünde zu Folge 1 das
     * Standbild von Folge 1, gemeint ist aber 17.
     */
    seasons: [{ n: 1, count: 12, startsAt: 17 }, { n: 2, count: 12 }],
    trending: 5,
  },
  "jujutsu-kaisen": {
    id: 95479,
    name: "Jujutsu Kaisen",
    original: "呪術廻戦",
    alternates: ["Jujutsu Kaisen", "Sorcery Fight"],
    firstAir: "2020-10-03",
    lastAir: "2024-09-12",
    popularity: 290,
    vote: 8.5,
    votes: 2600,
    seasons: [{ n: 1, count: 24 }, { n: 2, count: 23 }],
    trending: 3,
  },
  dandadan: {
    id: 240411,
    name: "Dan Da Dan",
    original: "ダンダダン",
    alternates: ["Dandadan", "Dan Da Dan"],
    firstAir: "2024-10-04",
    lastAir: "2026-03-05",
    popularity: 410,
    vote: 8.4,
    votes: 700,
    seasons: [{ n: 1, count: 12 }, { n: 2, count: 12 }],
    trending: 4,
  },
  "detektiv-conan": {
    id: 30983,
    name: "Detektiv Conan",
    original: "名探偵コナン",
    alternates: ["Case Closed", "Meitantei Conan"],
    firstAir: "1996-01-08",
    lastAir: "2026-03-01",
    popularity: 140,
    vote: 8.3,
    votes: 500,
    // Dreißig Staffeln: der Fall, für den es das Auswahlraster gibt.
    seasons: Array.from({ length: 30 }, (_, index) => ({ n: index + 1, count: 12 })),
  },
  pluto: {
    // Der Name hat mit dem Quelltitel nichts gemeinsam. Nur die
    // Alternativtitel verbinden die beiden.
    id: 89459,
    name: "Pluto: The Last Robot",
    original: "PLUTO",
    alternates: ["Pluto"],
    firstAir: "2023-10-26",
    lastAir: "2023-10-26",
    popularity: 90,
    vote: 8.1,
    votes: 260,
    seasons: [{ n: 1, count: 8 }],
  },
  monster: {
    id: 9260,
    name: "Monster",
    original: "モンスター",
    alternates: ["Naoki Urasawa's Monster"],
    firstAir: "2004-04-07",
    lastAir: "2005-09-28",
    popularity: 120,
    vote: 8.7,
    votes: 640,
    seasons: [{ n: 1, count: 12 }, { n: 2, count: 12 }],
  },
  dark: {
    id: 70523,
    name: "Dark",
    original: "Dark",
    alternates: ["Dark"],
    firstAir: "2017-12-01",
    lastAir: "2020-06-27",
    popularity: 210,
    vote: 8.4,
    votes: 4200,
    seasons: [{ n: 1, count: 10 }, { n: 2, count: 8 }],
    countries: ["DE"],
    animated: false,
  },
  "breaking-bad": {
    id: 1396,
    name: "Breaking Bad",
    original: "Breaking Bad",
    alternates: ["Breaking Bad"],
    firstAir: "2008-01-20",
    lastAir: "2013-09-29",
    popularity: 350,
    vote: 8.9,
    votes: 13_000,
    seasons: [{ n: 1, count: 7 }, { n: 2, count: 13 }],
    countries: ["US"],
    animated: false,
  },
  // „Barakamon" fehlt absichtlich: ein Titel ohne TMDB-Eintrag muss ohne Bild
  // und ohne Fehler dastehen.
};

/** Folgentitel, damit die Versatzerkennung etwas zu vergleichen hat. */
const EPISODE_NAMES = [
  "Das Ende der Reise", "Es hat sich nichts geändert", "Die Zauberin der Asche",
  "Der Mann des Nordens", "Zwei Brüder im Kampf", "Dämmerung der Menschheit",
  "Vergeltungsschlacht", "Der lange Weg zurück", "Was bleibt", "Die Prüfung",
  "Ein Versprechen", "Der letzte Sommer",
];

function slugOf(title) {
  return title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

function normalize(raw) {
  return raw
    .normalize("NFKD")
    .toLowerCase()
    .replace(/\p{M}/gu, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

function row(slug, entry, { withDetails = false } = {}) {
  const animated = entry.animated !== false;
  return {
    id: entry.id,
    name: entry.name,
    original_name: entry.original,
    overview:
      `${entry.name} bei TMDB: eine Beschreibung, die lang genug ist, um in drei `
      + "Zeilen zu passen und dann abgeschnitten zu werden.",
    first_air_date: entry.firstAir,
    popularity: entry.popularity,
    vote_average: entry.vote,
    vote_count: entry.votes,
    genre_ids: animated ? [16, 10765] : [18],
    origin_country: entry.countries ?? ["JP"],
    poster_path: `/${slug}-poster.jpg`,
    backdrop_path: `/${slug}-backdrop.jpg`,
    ...(withDetails
      ? {
        last_air_date: entry.lastAir,
        status: "Ended",
        episode_run_time: [24],
        number_of_seasons: entry.seasons.length,
        genres: (animated ? [16, 10765] : [18]).map((id) => ({ id, name: String(id) })),
        seasons: [
          { season_number: 0, episode_count: 4, name: "Specials" },
          ...entry.seasons.map((season) => ({
            season_number: season.n,
            episode_count: season.count,
            name: `Staffel ${season.n}`,
            air_date: entry.firstAir,
          })),
        ],
      }
      : {}),
  };
}

function byId(id) {
  for (const [slug, entry] of Object.entries(SERIES)) {
    if (entry.id === Number(id)) return [slug, entry];
  }
  return [null, null];
}

/**
 * Die Suche.
 *
 * Wie das echte TMDB sucht sie **unscharf** und über alle Schreibweisen — auch
 * über die Alternativtitel, die sie selbst nicht mitliefert. Genau daraus
 * entsteht der Fall, für den es `findViaAlternates` gibt: der Vorschlag ist
 * richtig, aber sein Name belegt das nicht.
 */
function search(query) {
  const needle = normalize(query ?? "");
  if (needle.length < 2) return { page: 1, results: [], total_results: 0 };
  const hits = [];
  for (const [slug, entry] of Object.entries(SERIES)) {
    const forms = [entry.name, entry.original, slug.replace(/-/g, " "), ...entry.alternates]
      .map(normalize);
    if (forms.some((form) => form.includes(needle) || needle.includes(form))) {
      hits.push(row(slug, entry));
    }
  }
  return { page: 1, results: hits.slice(0, 20), total_results: hits.length };
}

function seasonEpisodes(entry, seasonNumber) {
  const season = entry.seasons.find((item) => item.n === Number(seasonNumber));
  if (!season) return { episodes: [] };
  const start = season.startsAt ?? 1;
  return {
    season_number: season.n,
    episodes: Array.from({ length: season.count }, (_, index) => ({
      episode_number: start + index,
      name: EPISODE_NAMES[index % EPISODE_NAMES.length],
      overview:
        "Was in dieser Folge passiert, in zwei Sätzen. Der zweite Satz ist da, "
        + "damit die Beschreibung auf der Kachel abgeschnitten wird.",
      still_path: `/still-${season.n}-${start + index}.jpg`,
      air_date: "2024-01-05",
      runtime: 24,
    })),
  };
}

/** Was TMDB als verwandt nennt — hier: die übrigen Anime dieses Nachbaus. */
function related(id) {
  const results = [];
  for (const [slug, entry] of Object.entries(SERIES)) {
    if (entry.id === Number(id)) continue;
    if (entry.animated === false) continue;
    results.push(row(slug, entry));
  }
  return { page: 1, results, total_results: results.length };
}

function feed(path, params) {
  const wantsAnime = params.get("with_genres") === "16";
  const entries = Object.entries(SERIES)
    .filter(([, entry]) => (wantsAnime ? entry.animated !== false : true));

  if (path === "trending/tv/week") {
    const ranked = entries
      .filter(([, entry]) => typeof entry.trending === "number")
      .sort((a, b) => a[1].trending - b[1].trending);
    return { page: 1, results: ranked.map(([slug, entry]) => row(slug, entry)) };
  }
  const sorted = entries.sort((a, b) => b[1].popularity - a[1].popularity);
  // Zweite Seite leer: so bricht der Client nach einer Seite ab, wie er es
  // auch beim echten TMDB täte.
  const page = Number(params.get("page") ?? "1");
  if (page > 1) return { page, results: [] };
  return { page: 1, results: sorted.map(([slug, entry]) => row(slug, entry)) };
}

/**
 * Eine TMDB-Anfrage beantworten.
 *
 * Gibt `null` zurück, wenn der Pfad nicht nachgebaut ist — der Aufrufer
 * antwortet dann mit 404, genau wie der echte Dienst.
 */
export function handleTmdb(path, params) {
  if (path === "search/tv") return search(params.get("query"));
  if (path === "trending/tv/week" || path === "tv/popular" || path === "discover/tv") {
    return feed(path, params);
  }

  const detail = /^tv\/(\d+)$/.exec(path);
  if (detail) {
    const [slug, entry] = byId(detail[1]);
    return entry ? row(slug, entry, { withDetails: true }) : null;
  }

  const images = /^tv\/(\d+)\/images$/.exec(path);
  if (images) {
    const [slug, entry] = byId(images[1]);
    if (!entry) return null;
    return {
      logos: [
        { file_path: `/${slug}-logo.svg`, iso_639_1: "de", vote_average: 9 },
        { file_path: `/${slug}-logo.png`, iso_639_1: "de", vote_average: 7 },
        { file_path: `/${slug}-logo-en.png`, iso_639_1: "en", vote_average: 8 },
      ],
    };
  }

  const alternates = /^tv\/(\d+)\/alternative_titles$/.exec(path);
  if (alternates) {
    const [, entry] = byId(alternates[1]);
    if (!entry) return null;
    return { results: entry.alternates.map((title) => ({ title, iso_3166_1: "DE" })) };
  }

  const season = /^tv\/(\d+)\/season\/(\d+)$/.exec(path);
  if (season) {
    const [, entry] = byId(season[1]);
    return entry ? seasonEpisodes(entry, season[2]) : null;
  }

  const rec = /^tv\/(\d+)\/(recommendations|similar)$/.exec(path);
  if (rec) return related(rec[1]);

  return null;
}

/** Die Titel, die dieser Nachbau kennt — der Katalog richtet sich danach. */
export const TMDB_SLUGS = Object.keys(SERIES);

/** Wie viele Staffeln der Nachbau zu einem Slug führt. Für den Katalogaufbau. */
export function seasonCountFor(slug) {
  return SERIES[slug]?.seasons.length ?? 0;
}

export { slugOf };
