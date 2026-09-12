// Suche im geladenen Katalog — fehlertolerant, weil eine Fernbedienung tippt.
//
// Auf dem Fernseher entsteht jedes Zeichen über eine Bildschirmtastatur.
// Tippfehler sind dort häufiger und teurer als am Rechner, und ein Ä gibt es
// nicht. Deshalb in Stufen, von streng nach tolerant:
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
// Breitschrift und Satzzeichen — „Damonenjager" trifft „Dämonenjäger".

import { normalizeTitle } from "@nori/core";

export interface Searchable {
  title: string;
  alts: string[];
}

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

function tolerance(word: string): number {
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
