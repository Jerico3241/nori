// Die kurze Zeile unter einem Poster: Jahr · Genre · Bewertung.
//
// An einer Stelle, damit Startseite, Katalog und Detailseite dieselbe Angabe in
// derselben Reihenfolge zeigen. Das Jahr kommt von TMDB, das Genre von der
// Quelle, die Bewertung nur mit belastbarer Stimmenzahl.

import type { HomeTitle, TMDBSignals } from "@nori/core";

import { tmdb } from "../services/tmdb";
import { ratingText } from "./Rating";

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
