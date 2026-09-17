// Die kurze Zeile unter einem Poster: Jahr · Genre · Bewertung.
//
// An einer Stelle, damit Startseite, Katalog und Detailseite dieselbe Angabe in
// derselben Reihenfolge zeigen. Das Jahr kommt von TMDB, das Genre von der
// Quelle, die Bewertung nur mit belastbarer Stimmenzahl.

import type { HomeTitle, TMDBSignals } from "@nori/core";

import { tmdb } from "./services/tmdb";

/**
 * Die Bewertung als Text, „8,4" — oder `null`, wenn sie nichts heißt.
 *
 * Fünfzig Stimmen wie in `HomeRanking`: ein Titel mit 10,0 aus zwei Stimmen
 * ist keine Auskunft, sondern eine Zufallszahl. Eine Kachel, die sie trotzdem
 * zeigt, behauptet mehr, als sie weiß.
 */
export function ratingText(
  value: number | null | undefined,
  votes?: number | null,
  minimumVotes = 50,
): string | null {
  if (value === null || value === undefined || value <= 0) return null;
  if (votes !== undefined && votes !== null && votes < minimumVotes) return null;
  return value.toFixed(1).replace(".", ",");
}

export function yearOf(title: HomeTitle, signals?: TMDBSignals | null): number | null {
  const first = signals?.firstAirDate ?? tmdb.art(title.slug, title.provider)?.firstAirDate ?? null;
  return first === null ? null : new Date(first).getUTCFullYear();
}

export function titleMeta(title: HomeTitle, signals?: TMDBSignals | null): string {
  const art = tmdb.art(title.slug, title.provider);
  const year = yearOf(title, signals);
  const rating = ratingText(art?.rating ?? signals?.voteAverage ?? null, art?.votes ?? signals?.voteCount ?? null);
  return [year ? String(year) : null, title.genres[0] ?? null, rating ? `★ ${rating}` : null]
    .filter(Boolean)
    .join(" · ");
}
