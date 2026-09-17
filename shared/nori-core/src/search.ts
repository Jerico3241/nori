// Die Titelsuche — fehlertolerant und überall dieselbe.
//
// Die Entsprechung zu `CatalogSearch` in
// `native/NoriCore/Sources/NoriCore/CatalogSearch.swift`. Sie stand vorher nur
// in der webOS-App (`apps/webos/src/state/search.ts`), obwohl an ihr nichts
// TV-spezifisch ist: ein Tippfehler auf der Bildschirmtastatur einer
// Fernbedienung ist derselbe Tippfehler wie auf einem iPhone, und ein Nutzer,
// der „Damonenjager" sucht, meint auf beiden Geräten „Dämonenjäger".
//
// In Stufen, von streng nach tolerant:
//
//     0  Titel gleich
//     1  Titel beginnt mit dem Begriff
//     2  Titel enthält den Begriff
//     3  ein Alternativtitel enthält ihn
//     4  jedes Wort des Begriffs steht irgendwo in Titel oder Alternativtiteln
//     5  jedes Wort kommt mit einem Tippfehler vor (ab vier Buchstaben einer,
//        ab sieben zwei)
//
// Verglichen wird in der Form aus `normalizeTitle`: ohne Akzente, Umlaute,
// Breitschrift und Satzzeichen. Damit findet „shingeki no kyojin" auch den
// Eintrag, der bei der Quelle „Attack on Titan" heißt — sofern einer der
// Alternativtitel die Umschrift trägt, und genau dafür stehen sie dort.

import { normalizeTitle } from "./tmdb/matcher.js";

/** Was durchsucht werden kann: ein Titel und weitere Schreibweisen. */
export interface Searchable {
  title: string;
  alts: string[];
}

/** Ab so vielen Zeichen wird überhaupt gesucht. Darunter trifft alles. */
export const SEARCH_MIN_LENGTH = 2;

/**
 * Unter so vielen strengen Treffern werden zusätzlich Tippfehler geprüft.
 *
 * Nicht immer: Stufe 5 kostet ein Vielfaches der übrigen und verdünnte sonst
 * gute Treffer mit schlechten. Wer „one piece" tippt, will nicht „One Pace"
 * dazwischen.
 */
export const FUZZY_THRESHOLD = 12;

function words(text: string): string[] {
  return text.split(" ").filter((word) => word.length > 0);
}

/** Levenshtein mit Abbruch, sobald die Grenze sicher überschritten ist. */
function withinDistance(a: string, b: string, limit: number): boolean {
  if (Math.abs(a.length - b.length) > limit) return false;
  let previous = Array.from({ length: b.length + 1 }, (_, index) => index);
  for (let i = 1; i <= a.length; i += 1) {
    const current = [i];
    let rowMin = i;
    for (let j = 1; j <= b.length; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      const value = Math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost);
      current.push(value);
      if (value < rowMin) rowMin = value;
    }
    if (rowMin > limit) return false;
    previous = current;
  }
  return previous[b.length] <= limit;
}

/**
 * Wie viele Tippfehler ein Wort verträgt.
 *
 * Ziffern vertragen **keinen**: „1998" ist kein Vertipper von „1999", sondern
 * ein anderes Jahr, eine andere Folge, eine andere Staffel. Ohne diese Regel
 * verdünnte eine Suche nach „Titel 1999" ihren einen richtigen Treffer mit
 * einem Dutzend Nachbarzahlen — gemessen an einem Katalog aus durchnummerierten
 * Titeln, und genauso wäre es bei „Staffel 2" oder „86".
 */
function tolerance(word: string): number {
  if (/\d/.test(word)) return 0;
  if (word.length >= 7) return 2;
  if (word.length >= 4) return 1;
  return 0;
}

/** Stufe 0–4, oder −1. `needle` ist bereits normalisiert. */
export function searchScore(item: Searchable, needle: string): number {
  const title = normalizeTitle(item.title);
  if (title === needle) return 0;
  if (title.startsWith(needle)) return 1;
  if (title.includes(needle)) return 2;
  const alts = item.alts.map(normalizeTitle);
  if (alts.some((alt) => alt.includes(needle))) return 3;
  const haystack = [title, ...alts].join(" ");
  const parts = words(needle);
  if (parts.length > 1 && parts.every((part) => haystack.includes(part))) return 4;
  return -1;
}

/** Stufe 5, oder −1. Teurer — nur, wenn die strengen Stufen wenig finden. */
export function fuzzyScore(item: Searchable, needle: string): number {
  const parts = words(needle).filter((part) => part.length >= 3);
  if (parts.length === 0) return -1;
  const pool = words([normalizeTitle(item.title), ...item.alts.map(normalizeTitle)].join(" "));
  const hit = parts.every((part) => {
    const limit = tolerance(part);
    return pool.some((word) =>
      word.startsWith(part) || (limit > 0 && withinDistance(part, word.slice(0, part.length + limit), limit)));
  });
  return hit ? 5 : -1;
}

/**
 * Eine Liste durchsuchen und sortiert zurückgeben — der vollständige Ablauf.
 *
 * Erst die strengen Stufen, und nur wenn die wenig finden, zusätzlich die
 * teure. Bei gleicher Stufe entscheidet `tiebreak`; ohne bleibt die
 * Eingabereihenfolge, was für einen bereits sortierten Katalog das Richtige
 * ist.
 */
export function rankSearch<T>(
  items: readonly T[],
  needle: string,
  pick: (item: T) => Searchable,
  tiebreak?: (a: T, b: T) => number,
): T[] {
  const clean = normalizeTitle(needle.trim());
  if (clean.length < SEARCH_MIN_LENGTH) return [...items];

  const scored: { item: T; score: number; index: number }[] = [];
  const matched = new Set<number>();
  items.forEach((item, index) => {
    const score = searchScore(pick(item), clean);
    if (score >= 0) {
      scored.push({ item, score, index });
      matched.add(index);
    }
  });

  if (scored.length < FUZZY_THRESHOLD) {
    items.forEach((item, index) => {
      if (matched.has(index)) return;
      const score = fuzzyScore(pick(item), clean);
      if (score >= 0) scored.push({ item, score, index });
    });
  }

  return scored
    .sort((a, b) => a.score - b.score
      || (tiebreak ? tiebreak(a.item, b.item) : 0)
      || a.index - b.index)
    .map((entry) => entry.item);
}
