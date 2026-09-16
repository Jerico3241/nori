// Welche Bildgröße wohin gehört — an einer Stelle.
//
// TMDB liefert jedes Bild in mehreren Größen, und die Adresse trägt die Größe
// als Segment (`/t/p/w342/…`). Der Kern setzt Adressen mit einer festen Größe
// zusammen (`tmdbImageURL`); hier wird daraus die Größe, die ein Gerät an
// dieser Stelle **tatsächlich** braucht.
//
// ## Warum nicht einfach `devicePixelRatio`
//
// Das war der vorherige Stand, und er war auf genau der Hardware falsch, für
// die diese App gedacht ist. Ein webOS-Paket mit `"resolution": "1920x1080"`
// zeichnet in 1920 × 1080 **logischen wie physischen** Bildpunkten; den Rest
// erledigt der Skalierer des Panels. Viele 4K-Geräte melden trotzdem
// `devicePixelRatio === 2`, weil sie das Panel beschreiben und nicht die
// Fläche, auf der die App zeichnet.
//
// Die Folge war messbar: Posterkacheln kamen als `w780` statt `w342` (5,2× so
// viele Bildpunkte zu dekodieren), der Kopfbereich als `original` — bei TMDB
// regelmäßig 3840 × 2160 —, und der Schriftzug ebenfalls als `original`, eine
// PNG-Datei mit Alphakanal in voller Größe. Nichts davon war zu sehen; alles
// davon kostete Speicher, Dekodierzeit und Bandbreite auf dem schwächsten
// Gerät.
//
// Deshalb gilt hier: **ein Bild braucht nie mehr Bildpunkte, als die
// Zeichenfläche hergibt.** Wie breit die ist, beantwortet die Plattform
// (`platform().surfaceWidth()`): auf webOS die Auflösung aus `appinfo.json`,
// auf dem Desktop das Fenster mal seiner DPI-Skalierung, im Browser das echte
// Pixelverhältnis. Gerechnet wird dann in Bildschirmpixeln: gezeichnete
// CSS-Breite mal diesem Verhältnis.

import { platform } from "../platform";

export type ImageUse = "poster" | "backdropCard" | "backdropHero" | "still" | "logo";

/** Stufen je Verwendung: bis zu dieser Pixelbreite dieses TMDB-Segment. */
const LADDER: Record<ImageUse, [number, string][]> = {
  poster: [[240, "w185"], [360, "w342"], [540, "w500"], [Infinity, "w780"]],
  backdropCard: [[800, "w780"], [Infinity, "w1280"]],
  // Bei 1080p ist der Kopfbereich knapp 1560 px breit: `w1280` ist dort ein
  // leichtes Strecken bei einem Bruchteil der Bytes. `original` erst, wenn
  // das Bild deutlich breiter gezeichnet wird — also auf einer 4K-Fläche.
  backdropHero: [[1600, "w1280"], [Infinity, "original"]],
  still: [[320, "w300"], [520, "w454_and_h254_bestv2"], [Infinity, "original"]],
  // Der Schriftzug liegt über dem Breitbild und ist höchstens ein Drittel so
  // breit. `original` ist dafür bei TMDB oft ein PNG in Plakatgröße.
  logo: [[420, "w300"], [900, "w500"], [Infinity, "original"]],
};

/** Wie groß eine Verwendung bei 1920 CSS-Pixeln Breite gezeichnet wird, in rem. */
const RENDERED_REM: Record<ImageUse, number> = {
  poster: 19,
  backdropCard: 25,
  backdropHero: 98,
  still: 32,
  logo: 36,
};

/**
 * Das Verhältnis, mit dem CSS-Pixel in Bildpunkte umgerechnet werden.
 *
 * Nie mehr, als die Zeichenfläche hergibt, und nie mehr als das Vierfache —
 * jenseits davon wächst nur die Dekodierzeit.
 */
export function artworkPixelRatio(): number {
  const width = window.innerWidth || 1920;
  return Math.max(0.5, Math.min(platform().surfaceWidth() / width, 4));
}

/**
 * Bildschirmpixel je rem — gemessen, aber nicht bei jedem Bild neu.
 *
 * `getComputedStyle` ist eine Stilabfrage, und diese Funktion lief bisher bei
 * **jedem Zeichnen jeder Kachel**. Auf einer Startseite mit achtzig Kacheln
 * waren das achtzig Abfragen je Durchgang für eine Zahl, die sich nur ändert,
 * wenn sich das Fenster ändert.
 */
let pixelsPerRemCache: number | null = null;

function pixelsPerRem(): number {
  if (pixelsPerRemCache !== null) return pixelsPerRemCache;
  const size = Number.parseFloat(window.getComputedStyle(document.documentElement).fontSize) || 16;
  pixelsPerRemCache = size * artworkPixelRatio();
  return pixelsPerRemCache;
}

/** Nach einer Größenänderung neu messen. */
export function resetImageMetrics(): void {
  pixelsPerRemCache = null;
}

window.addEventListener("resize", resetImageMetrics);

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
