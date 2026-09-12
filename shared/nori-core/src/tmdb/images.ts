// Die Adressen der TMDB-Bilder — an einer Stelle.
//
// Eins zu eins aus `native/NoriCore/Sources/NoriCore/TMDBImages.swift`. TMDB
// liefert in seinen Antworten nur Pfade („/abc123.jpg"); die vollständige
// Adresse entsteht erst aus Host, Größenkürzel und Pfad. Stünde dieses
// Zusammensetzen an mehreren Stellen, lädt irgendwann eine 218 px breite
// Kachel ein 1280 px breites Bild — bei sechzig Kacheln sind das Megabyte für
// nichts.
//
// Die Größen sind nach **Verwendungszweck** benannt, nicht nach Pixeln. Die
// Kürzel führt TMDB in `/configuration`; sie sind seit Jahren unverändert und
// hier fest hinterlegt, statt beim Start einen Abruf dafür aufzuwenden.

const HOST = "https://image.tmdb.org/t/p/";

/** Wofür das Bild gebraucht wird. */
export type TMDBImageSize =
  /** Kleine Kachel in einer Liste. */
  | "posterThumb"
  /** Posterkachel einer Reihe — auf dem Fernseher 218 px breit. */
  | "posterCard"
  /** Poster als Kopfbild, wenn kein Breitbild vorliegt. */
  | "posterHero"
  /** Breitbild auf einer Weiterschauen-Kachel. */
  | "backdropCard"
  /** Breitbild über die volle Bildschirmbreite. */
  | "backdropHero"
  /** Freigestellter Schriftzug. */
  | "logo"
  /** Standbild einer Folge. TMDBs eigener 16:9-Zuschnitt. */
  | "still";

const SEGMENTS: Record<TMDBImageSize, string> = {
  posterThumb: "w185",
  posterCard: "w342",
  posterHero: "w780",
  backdropCard: "w780",
  // Auf einem 1080p-Panel deckt w1280 die volle Breite ab; w1920 gibt es bei
  // TMDB nicht, `original` wäre ein Vielfaches an Bytes für dasselbe Bild.
  backdropHero: "w1280",
  logo: "w500",
  still: "w454_and_h254_bestv2",
};

/**
 * Vollständige Adresse zu einem TMDB-Bildpfad.
 *
 * Gibt `null` zurück, wenn der Pfad fehlt oder leer ist — TMDB schreibt für
 * ein fehlendes Bild `null`, manche Antworten auch `""`. Beides heißt „kein
 * Bild", nicht „Bild an der Adresse `…/t/p/w342`".
 */
export function tmdbImageURL(path: string | null | undefined, size: TMDBImageSize): string | null {
  if (!path) return null;
  // Eine fertige Adresse kommt unverändert zurück. Der Aufrufer weiß nicht
  // immer, ob er einen TMDB-Pfad oder eine gespeicherte Adresse in der Hand
  // hat — zweimal zusammengesetzt entstünde `…/w342/https://…`.
  if (path.startsWith("http://") || path.startsWith("https://")) return path;
  const clean = path.startsWith("/") ? path : `/${path}`;
  return HOST + SEGMENTS[size] + clean;
}

/**
 * Stammt eine Adresse von TMDB?
 *
 * Entscheidet, ob ein Bildabruf über den Nori-Server laufen muss: AniWorld und
 * Serienstream liefern ihre Cover nur mit passendem `Referer` aus, TMDB
 * verlangt keinen und ist ohne Umweg schneller.
 */
export function isTMDBImage(url: string): boolean {
  try {
    return new URL(url).hostname.endsWith("image.tmdb.org");
  } catch {
    return false;
  }
}
