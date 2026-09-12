// Die Zuordnung zwischen einem Nori-Titel und einem TMDB-Eintrag.
//
// Eins zu eins aus `native/NoriCore/Sources/NoriCore/TMDBMatcher.swift`. Wer
// hier eine Schwelle oder eine Gewichtung ändert, ändert sie dort mit — sonst
// zeigen iPhone und Fernseher zu derselben Serie ein anderes Cover.
//
// ## Warum das nicht „Titel gleich Titel" ist
//
// AniWorld und Serienstream führen dieselbe Serie regelmäßig unter einem
// anderen Namen als TMDB — eingedeutscht, verkürzt, mit Staffelzusatz, mit
// Jahreszahl, mit oder ohne Untertitel. Ein Vergleich auf Gleichheit findet
// deshalb nur einen Bruchteil. Umgekehrt ist eine unscharfe Suche gefährlich:
// wer „Ein Stück" schreibt, darf nicht bei „One Piece" landen, und ein
// weltweit bekannter Titel darf einen unbekannten gleichen Namens nicht
// verdrängen.
//
// Die Regel dagegen: **Der Titel entscheidet, alles andere gewichtet nur.**
// Beliebtheit, Genre und Herkunftsland können einen Treffer vor einen anderen
// ziehen, aber keinen Treffer *erzeugen*. Wer die Titelschwelle nicht reißt,
// fällt raus — auch wenn er die bekannteste Serie der Welt ist.

import type { CatalogProvider } from "../models.js";

/**
 * Ein Trefferkandidat aus einer TMDB-Antwort.
 *
 * Bewusst ein eigener Typ und nicht die rohe Antwortzeile: die Bewertung ist
 * damit eine reine Funktion über Werten, die ein Test in zwei Zeilen aufbaut,
 * statt nur über eine echte HTTP-Antwort erreichbar zu sein.
 */
export interface TMDBCandidate {
  id: number;
  name: string;
  originalName: string;
  /**
   * Weitere Schreibweisen, sofern bekannt. `/search/tv` liefert keine;
   * `/tv/{id}/alternative_titles` schon.
   */
  alternateNames: string[];
  firstAirYear: number | null;
  /** Erstausstrahlung in Millisekunden seit 1970, sofern bekannt. */
  firstAirDate: number | null;
  popularity: number;
  voteAverage: number;
  voteCount: number;
  genreIDs: number[];
  originCountries: string[];
  posterPath: string | null;
  backdropPath: string | null;
  overview: string | null;
  /** Staffelzahl. Steht nur in `/tv/{id}`, nicht in der Suche. */
  seasonCount: number | null;
}

/** Ab dieser Titelnähe gilt ein Kandidat überhaupt als Treffer. */
export const TITLE_FLOOR = 80;

/** Die Genre-Kennung „Animation" bei TMDB. */
export const TMDB_GENRE_ANIMATION = 16;

export function emptyCandidate(id: number, name: string): TMDBCandidate {
  return {
    id,
    name,
    originalName: name,
    alternateNames: [],
    firstAirYear: null,
    firstAirDate: null,
    popularity: 0,
    voteAverage: 0,
    voteCount: 0,
    genreIDs: [],
    originCountries: [],
    posterPath: null,
    backdropPath: null,
    overview: null,
    seasonCount: null,
  };
}

/** Jahr aus einem TMDB-Datum (`yyyy-MM-dd`). */
export function tmdbYear(raw: unknown): number | null {
  if (typeof raw !== "string" || raw.length < 4) return null;
  const year = Number.parseInt(raw.slice(0, 4), 10);
  return Number.isFinite(year) ? year : null;
}

/**
 * TMDB-Datum als Millisekunden seit 1970.
 *
 * Fest als UTC gelesen (`…T00:00:00Z`) und nicht über `new Date("2024-01-05")`
 * mit Ortszeit: sonst hängt „welches Jahr" an der Zeitzone des Fernsehers, und
 * ein Gerät in Tokio käme auf ein anderes Ergebnis als eines in Berlin.
 */
export function tmdbDate(raw: unknown): number | null {
  if (typeof raw !== "string" || raw.length < 10) return null;
  const value = Date.parse(`${raw.slice(0, 10)}T00:00:00Z`);
  return Number.isNaN(value) ? null : value;
}

/**
 * Einen Kandidaten aus einer Antwortzeile bauen.
 *
 * Gibt `null` zurück, wenn die Zeile keine Kennung trägt — ohne die ist ein
 * Treffer wertlos, weil sich nichts nachladen lässt.
 */
export function candidateFromRow(row: unknown): TMDBCandidate | null {
  if (!row || typeof row !== "object") return null;
  const raw = row as Record<string, unknown>;
  const id = typeof raw.id === "number" ? raw.id : null;
  if (id === null) return null;

  const name = typeof raw.name === "string" ? raw.name : "";
  const originalName = typeof raw.original_name === "string" ? raw.original_name : "";
  const aired = raw.first_air_date;

  const genreIDs = Array.isArray(raw.genre_ids)
    ? raw.genre_ids.filter((value): value is number => typeof value === "number")
    // `/tv/{id}` liefert `genres: [{ id, name }]` statt `genre_ids`.
    : Array.isArray(raw.genres)
      ? (raw.genres as unknown[])
        .map((entry) => (entry && typeof entry === "object"
          ? (entry as Record<string, unknown>).id
          : null))
        .filter((value): value is number => typeof value === "number")
      : [];

  return {
    id,
    name,
    originalName: originalName || name,
    alternateNames: [],
    firstAirYear: tmdbYear(aired),
    firstAirDate: tmdbDate(aired),
    popularity: typeof raw.popularity === "number" ? raw.popularity : 0,
    voteAverage: typeof raw.vote_average === "number" ? raw.vote_average : 0,
    voteCount: typeof raw.vote_count === "number" ? raw.vote_count : 0,
    genreIDs,
    originCountries: Array.isArray(raw.origin_country)
      ? raw.origin_country.filter((value): value is string => typeof value === "string")
      : [],
    posterPath: typeof raw.poster_path === "string" ? raw.poster_path : null,
    backdropPath: typeof raw.backdrop_path === "string" ? raw.backdrop_path : null,
    overview: typeof raw.overview === "string" ? raw.overview : null,
    seasonCount: typeof raw.number_of_seasons === "number" ? raw.number_of_seasons : null,
  };
}

export function hasPoster(candidate: TMDBCandidate): boolean {
  return Boolean(candidate.posterPath);
}

export function hasBackdrop(candidate: TMDBCandidate): boolean {
  return Boolean(candidate.backdropPath);
}

// MARK: - Normalisierung

/**
 * Ein Titel auf seine vergleichbare Form.
 *
 * Kleingeschrieben, ohne Akzente, ohne Satzzeichen, ohne Mehrfach-Leerzeichen.
 * Damit sind „Re:ZERO – Starting Life in Another World" und „Re Zero Starting
 * Life in Another World" dasselbe, und „Pokémon" trifft „Pokemon".
 *
 * `NFKD` statt `NFD`: das faltet zusätzlich Breitvarianten (ＡＢＣ → ABC), was
 * der Swift-Seite mit `.widthInsensitive` entspricht — japanische Titel stehen
 * bei den Quellen regelmäßig in Breitschrift.
 *
 * Nicht entfernt werden Ziffern: „86" und „91 Days" sind Titel, keine Zählung.
 */
export function normalizeTitle(raw: string): string {
  const folded = raw.normalize("NFKD").toLowerCase();
  let out = "";
  let lastWasSpace = true;
  for (const char of folded) {
    // Kombinierende Zeichen sind nach NFKD die abgetrennten Akzente.
    if (/\p{M}/u.test(char)) continue;
    if (/[\p{L}\p{N}]/u.test(char)) {
      out += char;
      lastWasSpace = false;
    } else if (!lastWasSpace) {
      out += " ";
      lastWasSpace = true;
    }
  }
  return out.replace(/\s+$/, "");
}

/**
 * Was nach dem Abziehen von Jahres- und Staffelangaben übrig bleibt.
 *
 * AniWorld hängt „(2024)" an, Serienstream „Staffel 2", und bei Anime steht
 * regelmäßig „2nd Season", „Final Season", „Part 2" oder „Cour 2" im Titel.
 * TMDB führt alle diese Fassungen unter **einem** Serieneintrag — die Zusätze
 * müssen also weg, sonst findet die Suche gar nichts.
 *
 * Das Ergebnis ist bereits normalisiert.
 */
export function stripVariants(raw: string): string {
  let text = normalizeTitle(raw);
  const patterns: RegExp[] = [
    /\s*\b(19|20)\d{2}\b\s*$/gi,
    /\s*\b(staffel|season|saison|serie|part|teil|cour)\s+\d+\b/gi,
    /\s*\b\d+\s*(staffel|season)\b/gi,
    // Der bestimmte Artikel gehört **in** den Ausdruck, nicht in eine zweite
    // Zeile danach: „The Final Season" ohne ihn ergibt „… the" und findet
    // nichts. Das war der gemessene Fall bei Shingeki no Kyojin.
    /\s*\b(the\s+)?(final|last|second|third|fourth|fifth|zweite|dritte|vierte)\s+(staffel|season)\b/gi,
    /\s*\b\d+(st|nd|rd|th)\s+season\b/gi,
  ];
  for (const pattern of patterns) text = text.replace(pattern, " ");
  return normalizeTitle(text);
}

/**
 * Suchbegriffe zu einem Titel, in absteigender Güte.
 *
 * Die Reihenfolge ist die Reihenfolge der Versuche: erst der Titel, wie die
 * Quelle ihn führt, dann seine Alternativtitel, dann der Teil vor einem
 * Doppelpunkt, zuletzt die um Staffel- und Jahresangaben bereinigte Fassung.
 * Die steht hinten, weil sie am meisten weglässt und damit am ehesten einen
 * falschen Nachbarn trifft.
 *
 * Rohform, nicht normalisiert: TMDB sucht selbst unscharf und kommt mit
 * Satzzeichen besser zurecht als mit einer entkernten Zeichenkette.
 */
export function searchQueries(title: string, alternates: string[] = []): string[] {
  const out: string[] = [];
  const seen = new Set<string>();

  const add = (raw: string) => {
    const cleaned = raw.replace(/\s*\(\d{4}\)\s*/g, " ").trim();
    if (cleaned.length < 2) return;
    const key = normalizeTitle(cleaned);
    if (!key || seen.has(key)) return;
    seen.add(key);
    out.push(cleaned);
  };

  add(title);
  for (const alt of alternates) add(alt);
  // „Titel: Untertitel" steht bei TMDB oft nur als „Titel".
  for (const candidate of [title, ...alternates]) {
    const colon = candidate.indexOf(":");
    if (colon > 0) add(candidate.slice(0, colon));
  }
  for (const candidate of [title, ...alternates]) add(stripVariants(candidate));
  return out;
}

// MARK: - Titelnähe

function codePointLength(value: string): number {
  return Array.from(value).length;
}

function pairScore(a: string, b: string): number {
  if (a === b) return 400;
  // Enthalten, aber ähnlich lang: „Attack on Titan" in „Attack on Titan Final
  // Season" ist derselbe Titel, „Bleach" in „Bleach Thousand-Year Blood War"
  // auch. „One" in „One Piece" dagegen nicht — deshalb das Längenverhältnis.
  const aLen = codePointLength(a);
  const bLen = codePointLength(b);
  const longer = aLen >= bLen ? a : b;
  const shorter = aLen >= bLen ? b : a;
  const shortLen = Math.min(aLen, bLen);
  const longLen = Math.max(aLen, bLen);
  if (shortLen < 3) return 0;
  const ratio = shortLen / longLen;
  if (longer.includes(shorter)) {
    if (ratio >= 0.7) return 260;
    // Der Anfang zählt nur bei einem Wort, das für sich steht. „One" steckt am
    // Anfang von „One Piece", ist aber kein Titel, sondern ein Zahlwort — fünf
    // Zeichen sind die Grenze, an der die Verwechslungsgefahr abreißt.
    if (longer.startsWith(shorter) && shortLen >= 5) return 180;
    return ratio >= 0.4 ? 110 : 0;
  }
  // Gemeinsame Wörter. Fängt die Fälle, in denen dieselbe Serie in beiden
  // Fassungen dieselben Hauptwörter trägt, nur anders verbunden.
  const wordsA = new Set(a.split(" ").filter((word) => word.length >= 3));
  const wordsB = new Set(b.split(" ").filter((word) => word.length >= 3));
  if (wordsA.size === 0 || wordsB.size === 0) return 0;
  let overlap = 0;
  for (const word of wordsA) if (wordsB.has(word)) overlap += 1;
  const union = new Set([...wordsA, ...wordsB]).size;
  const jaccard = overlap / union;
  if (jaccard >= 0.8) return 150;
  if (jaccard >= 0.6) return 95;
  return 0;
}

/**
 * Wie nah zwei Titel beieinander liegen: 0 (nichts) bis 400 (identisch).
 *
 * Die Stufen sind grob und absichtlich nicht stetig. Eine feinkörnige
 * Ähnlichkeit — Levenshtein etwa — verleitet dazu, knappe Werte doch noch zu
 * nehmen; hier gibt es „gleich", „steckt drin", „fängt an mit", „gemeinsame
 * Wörter" und „nein".
 */
export function titleScore(query: string, candidate: TMDBCandidate): number {
  const names = [candidate.name, candidate.originalName, ...candidate.alternateNames]
    .filter((name) => name.length > 0);
  let best = 0;
  for (const form of [normalizeTitle(query), stripVariants(query)]) {
    if (!form) continue;
    for (const name of names) {
      for (const variant of [normalizeTitle(name), stripVariants(name)]) {
        if (!variant) continue;
        best = Math.max(best, pairScore(form, variant));
      }
    }
  }
  return best;
}

export interface ScoreOptions {
  /**
   * Die Quelle des Nori-Titels. AniWorld führt Anime, Serienstream
   * Realserien — das ist ein starkes Signal, wenn zwei Einträge gleich heißen.
   */
  kind: CatalogProvider;
  /** Erscheinungsjahr laut Quelle, sofern bekannt. */
  expectedYear?: number | null;
  /** Staffelzahl laut Quelle, sofern bekannt. */
  expectedSeasons?: number | null;
}

/**
 * Wie gut ein Kandidat zu einer Suche passt.
 *
 * Gibt `null` zurück, wenn der Titel die Schwelle nicht erreicht. Ein `null`
 * ist hier eine Antwort, kein Fehler: lieber gar kein Cover als das einer
 * fremden Serie.
 */
export function scoreCandidate(
  candidate: TMDBCandidate,
  query: string,
  options: ScoreOptions,
): number | null {
  const title = titleScore(query, candidate);
  if (title < TITLE_FLOOR) return null;

  let score = title;

  const animated = candidate.genreIDs.includes(TMDB_GENRE_ANIMATION);
  const japanese = candidate.originCountries.includes("JP");
  if (options.kind === "aniworld") {
    if (animated) score += 120;
    if (japanese) score += 60;
  } else {
    // Ein japanischer Zeichentrick unter den Realserien ist fast immer der
    // falsche Eintrag — dieselbe Marke gibt es oft als Anime **und** als
    // Realverfilmung.
    if (animated && japanese) score -= 90;
    else if (japanese) score -= 20;
    if (candidate.originCountries.some((code) => ["US", "GB", "DE", "CA", "AU", "KR"].includes(code))) {
      score += 40;
    }
  }

  // Jahr. Ein Treffer im selben Jahr ist ein starkes Zeichen, ein weit
  // entferntes Jahr ein Warnzeichen — aber kein Ausschluss: Neuverfilmungen
  // tragen denselben Namen, und die Quellen führen das Jahr oft gar nicht.
  const expectedYear = options.expectedYear ?? null;
  if (expectedYear !== null && candidate.firstAirYear !== null) {
    const gap = Math.abs(expectedYear - candidate.firstAirYear);
    if (gap === 0) score += 60;
    else if (gap === 1) score += 25;
    else if (gap >= 4) score -= 70;
  }

  // Staffelzahl. Schwach gewichtet: die Quellen zählen Specials und Filme mal
  // mit, mal nicht.
  const expectedSeasons = options.expectedSeasons ?? null;
  if (expectedSeasons !== null && candidate.seasonCount !== null
    && expectedSeasons > 0 && candidate.seasonCount > 0) {
    score += Math.abs(expectedSeasons - candidate.seasonCount) <= 1 ? 15 : -15;
  }

  // Beliebtheit nur als Stichentscheid. Gedeckelt, damit sie einen schwächeren
  // Titeltreffer nie überholen kann: der Abstand zwischen zwei Titelstufen ist
  // stets größer als dieser Deckel.
  score += Math.min(candidate.popularity, 40);

  return score;
}

export interface BestOptions extends ScoreOptions {
  /**
   * Für die Cover-Suche zwingend — ein Treffer ohne Poster liefert kein Cover.
   * Für die Kennungssuche nicht: eine Serie ohne Poster hat trotzdem Folgen
   * mit Bild und Text.
   */
  requirePoster?: boolean;
}

/** Der beste Kandidat, oder `null`. */
export function bestCandidate(
  candidates: TMDBCandidate[],
  query: string,
  options: BestOptions,
): TMDBCandidate | null {
  let winner: { score: number; candidate: TMDBCandidate } | null = null;
  for (const candidate of candidates) {
    if (options.requirePoster && !hasPoster(candidate)) continue;
    const score = scoreCandidate(candidate, query, options);
    if (score === null) continue;
    if (!winner || score > winner.score) winner = { score, candidate };
  }
  return winner ? winner.candidate : null;
}

/** Dieselbe Auswahl auf den rohen Zeilen einer TMDB-Antwort. */
export function bestRow(
  rows: unknown[],
  query: string,
  options: BestOptions,
): TMDBCandidate | null {
  const candidates: TMDBCandidate[] = [];
  for (const row of rows) {
    const candidate = candidateFromRow(row);
    if (candidate) candidates.push(candidate);
  }
  return bestCandidate(candidates, query, options);
}
