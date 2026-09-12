// Welche Bildgröße wohin gehört — an einer Stelle.
//
// TMDB liefert jedes Bild in mehreren Größen, und die Adresse trägt die Größe
// als Segment (`/t/p/w342/…`). Der Kern setzt Adressen mit einer festen Größe
// zusammen (`tmdbImageURL`); hier wird daraus die Größe, die ein Fernseher an
// dieser Stelle **tatsächlich** braucht.
//
// Gerechnet wird in Bildschirmpixeln: gezeichnete CSS-Breite mal
// Pixelverhältnis. Auf einem 1080p-Panel bekommt eine Posterkachel damit
// `w342`, auf einem 4K-Panel `w780`; das Kopfbild bekommt auf 4K `original`
// statt eines auf die dreifache Breite gestreckten `w1280`. Umgekehrt lädt
// keine Kachel ein Kopfbild.

export type ImageUse = "poster" | "backdropCard" | "backdropHero" | "still" | "logo";

/** Stufen je Verwendung: bis zu dieser Pixelbreite dieses TMDB-Segment. */
const LADDER: Record<ImageUse, [number, string][]> = {
  poster: [[240, "w185"], [360, "w342"], [540, "w500"], [Infinity, "w780"]],
  backdropCard: [[800, "w780"], [Infinity, "w1280"]],
  // Bei 1080p ist der Kopfbereich knapp 1560 px breit: `w1280` ist dort ein
  // leichtes Strecken bei einem Bruchteil der Bytes. `original` erst, wenn
  // das Bild deutlich breiter gezeichnet wird — also auf 4K.
  backdropHero: [[1600, "w1280"], [Infinity, "original"]],
  still: [[320, "w300"], [520, "w454_and_h254_bestv2"], [Infinity, "original"]],
  logo: [[520, "w500"], [Infinity, "original"]],
};

/** Wie groß eine Verwendung bei 1920 CSS-Pixeln Breite gezeichnet wird, in rem. */
const RENDERED_REM: Record<ImageUse, number> = {
  poster: 19,
  backdropCard: 25,
  backdropHero: 98,
  still: 32,
  logo: 36,
};

/** Bildschirmpixel je rem. Liest die Wurzelschrift, die mit der Breite skaliert. */
function pixelsPerRem(): number {
  const size = Number.parseFloat(window.getComputedStyle(document.documentElement).fontSize) || 16;
  return size * (window.devicePixelRatio || 1);
}

const TMDB_SEGMENT = /(\/t\/p\/)([^/]+)(\/)/;

/** Die TMDB-Größe, die eine Verwendung braucht. */
export function tmdbSegmentFor(use: ImageUse): string {
  const needed = RENDERED_REM[use] * pixelsPerRem();
  for (const [limit, segment] of LADDER[use]) {
    if (needed <= limit) return segment;
  }
  return "original";
}

/**
 * Eine Bildadresse in der passenden Größe.
 *
 * Nur TMDB-Adressen werden umgeschrieben. Die Cover der Quellen gibt es in
 * genau einer Größe; sie kommen unverändert zurück.
 */
export function sizedImage(url: string | null | undefined, use: ImageUse): string | null {
  if (!url) return null;
  if (!url.includes("image.tmdb.org")) return url;
  return url.replace(TMDB_SEGMENT, `$1${tmdbSegmentFor(use)}$3`);
}
