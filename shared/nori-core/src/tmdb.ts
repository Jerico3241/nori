// TMDB-Zuordnung und Bildadressen — die TypeScript-Seite.
//
// Das Gegenstück zu `native/NoriCore/Sources/NoriCore/TMDBMatcher.swift`,
// `TMDBImages.swift` und `TMDBArtwork.swift`. Wie beim übrigen Kern gilt: Die
// Regeln stehen zweimal, weil TypeScript kein Swift einbinden kann, und sie
// müssen gleich bleiben. Maßgeblich ist `config/contract.json`.
//
// Warum das hier überhaupt liegt und nicht in der webOS-App: Die Fernseh-App
// hatte ihre eigene, viel kürzere Fassung — sie nahm aus der TMDB-Antwort
// schlicht die erste Zeile mit einem Breitbild. Damit bekam „Die Melancholie
// der Haruhi Suzumiya" das Bild irgendeiner Serie, die TMDB zufällig
// vornedran sortierte. Dieselbe Bewertung wie auf Apple ist die einzige Art,
// wie beide Plattformen dasselbe anzeigen.

import type { CatalogProvider } from "./models.js";

/** Ein Trefferkandidat aus einer TMDB-Antwort. */
export interface TmdbCandidate {
  id: number;
  name: string;
  originalName: string;
  /** Weitere Schreibweisen. `/search/tv` liefert keine, `/alternative_titles` schon. */
  alternateNames: string[];
  firstAirYear: number | null;
  popularity: number;
  voteAverage: number;
  genreIds: number[];
  originCountries: string[];
  posterPath: string | null;
  backdropPath: string | null;
  overview: string | null;
}

/** Eine Zeile einer TMDB-Antwort, so wie sie über das Netz kommt. */
export interface TmdbRow {
  id?: unknown;
  name?: unknown;
  original_name?: unknown;
  first_air_date?: unknown;
  popularity?: unknown;
  vote_average?: unknown;
  genre_ids?: unknown;
  origin_country?: unknown;
  poster_path?: unknown;
  backdrop_path?: unknown;
  overview?: unknown;
}

function str(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function num(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

/**
 * Aus einer Zeile der TMDB-Antwort. `null`, wenn die Zeile keine Kennung
 * trägt — ohne die ist ein Treffer wertlos, weil sich nichts nachladen lässt.
 */
export function candidateFromRow(row: TmdbRow): TmdbCandidate | null {
  if (typeof row.id !== "number") return null;
  const aired = str(row.first_air_date);
  const name = str(row.name);
  return {
    id: row.id,
    name,
    originalName: str(row.original_name) || name,
    alternateNames: [],
    firstAirYear: aired.length >= 4 ? Number.parseInt(aired.slice(0, 4), 10) || null : null,
    popularity: num(row.popularity),
    voteAverage: num(row.vote_average),
    genreIds: Array.isArray(row.genre_ids) ? row.genre_ids.filter((v): v is number => typeof v === "number") : [],
    originCountries: Array.isArray(row.origin_country)
      ? row.origin_country.filter((v): v is string => typeof v === "string")
      : [],
    posterPath: typeof row.poster_path === "string" && row.poster_path ? row.poster_path : null,
    backdropPath: typeof row.backdrop_path === "string" && row.backdrop_path ? row.backdrop_path : null,
    overview: typeof row.overview === "string" ? row.overview : null,
  };
}

// ---------------------------------------------------------------- Normalisierung

/**
 * Ein Titel auf seine vergleichbare Form: klein, ohne Akzente, ohne
 * Satzzeichen. Ziffern bleiben — „86" und „91 Days" sind Titel, keine Zählung.
 */
export function normalize(raw: string): string {
  return raw
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

const VARIANT_PATTERNS: RegExp[] = [
  /\s*\b(19|20)\d{2}\b\s*$/gi,
  /\s*\b(staffel|season|saison|serie|part|teil|cour)\s+\d+\b/gi,
  /\s*\b\d+\s*(staffel|season)\b/gi,
  // Der bestimmte Artikel gehört mit in den Ausdruck: „The Final Season"
  // wurde sonst von der Zeile darüber zu „the" abgeräumt.
  /\s*\b(the\s+)?(final|last|second|third|fourth|fifth|zweite|dritte|vierte)\s+(staffel|season)\b/gi,
  /\s*\b\d+(st|nd|rd|th)\s+season\b/gi,
];

/** Was nach dem Abziehen von Jahres- und Staffelangaben übrig bleibt. */
export function stripVariants(raw: string): string {
  let text = normalize(raw);
  for (const pattern of VARIANT_PATTERNS) {
    text = text.replace(pattern, " ");
  }
  return normalize(text);
}

/**
 * Suchbegriffe zu einem Titel, in absteigender Güte.
 *
 * Die Reihenfolge ist die Reihenfolge der Versuche: erst der Titel der
 * Quelle, dann die Alternativtitel, dann der Teil vor einem Doppelpunkt,
 * zuletzt die um Staffel- und Jahresangaben bereinigte Fassung. Die steht
 * hinten, weil sie am meisten weglässt.
 */
export function queries(title: string, alternates: string[] = []): string[] {
  const out: string[] = [];
  const seen = new Set<string>();

  const add = (raw: string): void => {
    const cleaned = raw.replace(/\s*\(\d{4}\)\s*/g, " ").trim();
    if (cleaned.length < 2) return;
    const key = normalize(cleaned);
    if (!key || seen.has(key)) return;
    seen.add(key);
    out.push(cleaned);
  };

  add(title);
  for (const alt of alternates) add(alt);
  for (const candidate of [title, ...alternates]) {
    const colon = candidate.indexOf(":");
    if (colon > 0) add(candidate.slice(0, colon));
  }
  for (const candidate of [title, ...alternates]) add(stripVariants(candidate));
  return out;
}

// ---------------------------------------------------------------- Titelnähe

/** Ab dieser Titelnähe gilt ein Kandidat überhaupt als Treffer. */
export const TITLE_FLOOR = 80;

function pairScore(a: string, b: string): number {
  if (a === b) return 400;
  const longer = a.length >= b.length ? a : b;
  const shorter = a.length >= b.length ? b : a;
  if (shorter.length < 3) return 0;
  const ratio = shorter.length / longer.length;
  if (longer.includes(shorter)) {
    if (ratio >= 0.7) return 260;
    if (longer.startsWith(shorter) && shorter.length >= 5) return 180;
    return ratio >= 0.4 ? 110 : 0;
  }
  const wordsA = new Set(a.split(" ").filter((w) => w.length >= 3));
  const wordsB = new Set(b.split(" ").filter((w) => w.length >= 3));
  if (wordsA.size === 0 || wordsB.size === 0) return 0;
  let overlap = 0;
  for (const word of wordsA) if (wordsB.has(word)) overlap += 1;
  const union = new Set([...wordsA, ...wordsB]).size;
  const jaccard = overlap / union;
  if (jaccard >= 0.8) return 150;
  if (jaccard >= 0.6) return 95;
  return 0;
}

/** Wie nah zwei Titel beieinander liegen: 0 (nichts) bis 400 (identisch). */
export function titleScore(query: string, candidate: TmdbCandidate): number {
  const names = [candidate.name, candidate.originalName, ...candidate.alternateNames].filter((n) => n.length > 0);
  let best = 0;
  for (const form of [normalize(query), stripVariants(query)]) {
    if (!form) continue;
    for (const name of names) {
      for (const variant of [normalize(name), stripVariants(name)]) {
        if (!variant) continue;
        best = Math.max(best, pairScore(form, variant));
      }
    }
  }
  return best;
}

export interface ScoreOptions {
  expectedYear?: number | null;
  requirePoster?: boolean;
}

/**
 * Wie gut ein Kandidat zu einer Suche passt. `null`, wenn der Titel die
 * Schwelle nicht erreicht.
 *
 * Der Titel entscheidet, alles andere gewichtet nur: Beliebtheit, Genre und
 * Herkunftsland können einen Treffer vor einen anderen ziehen, aber keinen
 * Treffer erzeugen.
 */
export function score(
  candidate: TmdbCandidate,
  query: string,
  kind: CatalogProvider,
  options: ScoreOptions = {},
): number | null {
  const title = titleScore(query, candidate);
  if (title < TITLE_FLOOR) return null;

  let total = title;
  const animated = candidate.genreIds.includes(16);
  const japanese = candidate.originCountries.includes("JP");
  if (kind === "aniworld") {
    if (animated) total += 120;
    if (japanese) total += 60;
  } else {
    if (animated && japanese) total -= 90;
    else if (japanese) total -= 20;
    if (candidate.originCountries.some((c) => ["US", "GB", "DE", "CA", "AU", "KR"].includes(c))) total += 40;
  }

  const expectedYear = options.expectedYear ?? null;
  if (expectedYear !== null && candidate.firstAirYear !== null) {
    const gap = Math.abs(expectedYear - candidate.firstAirYear);
    if (gap === 0) total += 60;
    else if (gap === 1) total += 25;
    else if (gap >= 4) total -= 70;
  }

  total += Math.min(candidate.popularity, 40);
  return total;
}

/** Der beste Kandidat, oder `null`. Lieber nichts als das Falsche. */
export function best(
  candidates: TmdbCandidate[],
  query: string,
  kind: CatalogProvider,
  options: ScoreOptions = {},
): TmdbCandidate | null {
  let winner: { score: number; candidate: TmdbCandidate } | null = null;
  for (const candidate of candidates) {
    if (options.requirePoster && !candidate.posterPath) continue;
    const value = score(candidate, query, kind, options);
    if (value === null) continue;
    if (!winner || value > winner.score) winner = { score: value, candidate };
  }
  return winner?.candidate ?? null;
}

// ---------------------------------------------------------------- Bildadressen

const IMAGE_HOST = "https://image.tmdb.org/t/p/";

/**
 * Die Größen sind nach Verwendungszweck benannt, nicht nach Pixeln — und sie
 * stehen an genau einer Stelle. Vorher setzte die webOS-App ihre Adressen
 * selbst zusammen und benutzte dabei eine Breite, die im Apple-Kern nicht
 * vorkommt.
 */
export const TMDB_SIZES = {
  posterThumb: "w185",
  posterCard: "w342",
  posterHero: "w780",
  backdropCard: "w780",
  backdropHero: "w1280",
  logo: "w500",
  still: "w454_and_h254_bestv2",
} as const;

export type TmdbImageSize = keyof typeof TMDB_SIZES;

/**
 * Vollständige Adresse zu einem TMDB-Bildpfad.
 *
 * `null`, wenn der Pfad fehlt oder leer ist: TMDB schreibt für ein fehlendes
 * Bild `null`, manche Antworten auch `""`. Beides heißt „kein Bild", nicht
 * „Bild an der Adresse …/t/p/w342".
 *
 * Eine bereits vollständige Adresse wird unverändert zurückgegeben, damit
 * nichts doppelt zusammengesetzt wird.
 */
export function imageURL(path: string | null | undefined, size: TmdbImageSize): string | null {
  if (!path) return null;
  if (path.startsWith("http://") || path.startsWith("https://")) return path;
  const clean = path.startsWith("/") ? path : `/${path}`;
  return IMAGE_HOST + TMDB_SIZES[size] + clean;
}

/** Stammt eine Adresse von TMDB? Entscheidet, ob ein Referer nötig ist. */
export function isTmdbImage(url: string): boolean {
  try {
    return new URL(url).hostname.endsWith("image.tmdb.org");
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------- Logos

export interface TmdbImageRow {
  file_path?: unknown;
  iso_639_1?: unknown;
  vote_average?: unknown;
  vote_count?: unknown;
}

/** Deutsch vor Englisch vor sprachlos vor allem anderen. */
export function languageRank(iso: string | null | undefined): number {
  if (iso === "de") return 0;
  if (iso === "en") return 1;
  if (iso === null || iso === undefined || iso === "") return 2;
  return 3;
}

/** Das brauchbarste Logo aus einer `/images`-Antwort. SVG fällt heraus. */
export function bestLogoPath(rows: TmdbImageRow[]): string | null {
  const usable = rows.filter((row) => {
    const path = typeof row.file_path === "string" ? row.file_path : "";
    return path.length > 0 && !path.toLowerCase().endsWith(".svg");
  });
  if (usable.length === 0) return null;
  const sorted = [...usable].sort((a, b) => {
    const ra = languageRank(typeof a.iso_639_1 === "string" ? a.iso_639_1 : null);
    const rb = languageRank(typeof b.iso_639_1 === "string" ? b.iso_639_1 : null);
    if (ra !== rb) return ra - rb;
    const va = num(a.vote_average);
    const vb = num(b.vote_average);
    if (va !== vb) return vb - va;
    return num(b.vote_count) - num(a.vote_count);
  });
  return (sorted[0]?.file_path as string) ?? null;
}

// ---------------------------------------------------------------- Fehlschläge

/**
 * Warum ein Abruf nichts ergab. Entspricht `TMDBFailure` auf der Swift-Seite.
 *
 * Genau ein Fall rechtfertigt ein dauerhaftes Merken: HTTP 404. Alles andere
 * darf beim nächsten Versuch wieder gefragt werden — sonst macht eine einzige
 * Ratenbegrenzung aus „gerade nicht erreichbar" ein „gibt es nicht".
 */
export type TmdbFailure =
  | "noKey"
  | "notFound"
  | "unauthorized"
  | "rateLimited"
  | "server"
  | "network"
  | "malformed";

export function failureFromStatus(status: number): TmdbFailure | null {
  if (status >= 200 && status < 300) return null;
  if (status === 401 || status === 403) return "unauthorized";
  if (status === 404) return "notFound";
  if (status === 429) return "rateLimited";
  return "server";
}

export function isDefinitive(failure: TmdbFailure): boolean {
  return failure === "notFound";
}
