// Der TMDB-Schlüssel.
//
// ## Die Regel und ihre eine Ausnahme
//
// Im Nori-Repository gilt: **keine Schlüssel im Quelltext.** Ein Schlüssel
// dort liegt in jedem Klon, in jedem Build und dauerhaft in der Git-Historie;
// wer ihn sperrt, sperrt ihn für alle Installationen zugleich.
//
// Für den TMDB-Schlüssel hat der Betreiber eine Ausnahme entschieden — für
// eine private App in einem privaten Repository. Die Apple-Seite hat sie in
// `TMDBKeyStore.builtIn` (`native/NoriCore/Sources/NoriCore/AniworldClient.swift`),
// `tools/check-apple-sources.py` kennt sie als einzige erlaubte Zeile, und
// `CLAUDE.md` nennt sie. Dies hier ist dieselbe Ausnahme für die
// JavaScript-Seite, mit demselben Schlüssel.
//
// Was das heißt, gehört trotzdem aufgeschrieben: der Schlüssel steckt damit
// auch im gebauten `.ipk`, und aus dem lässt er sich herausziehen. Wird das
// Repository je öffentlich, ist er es auch.
//
// ## Warum ein eingebauter Schlüssel hier mehr wiegt als auf dem iPhone
//
// Auf einem Fernseher gibt es keine Tastatur. Einen 32-stelligen Hex-Schlüssel
// mit einer Fernbedienung über eine Bildschirmtastatur einzugeben, ist die
// Sorte Einrichtung, die niemand macht — und ohne Schlüssel zeigt Nori nur die
// kleinen Cover der Quellen. Deshalb ist der mitgelieferte Schlüssel hier der
// Normalfall und nicht der Rückfall.
//
// ## Die Reihenfolge
//
// Ein eigener Schlüssel hat immer Vorrang. Wer einen einträgt — am Gerät oder
// über `NORI_TMDB_KEY` am Server —, benutzt seinen eigenen; das ist der Weg,
// auf dem sich die Ratenbegrenzung von der geteilten Kennung trennen lässt.

/**
 * Der mitgelieferte Schlüssel.
 *
 * Derselbe wie in `TMDBKeyStore.builtIn` auf der Apple-Seite. Wird er dort
 * getauscht, gehört er hier mitgetauscht — sonst zeigt der Fernseher zu
 * derselben Serie andere Daten als das iPhone, und zwar ohne Fehlermeldung.
 */
export const BUILT_IN_TMDB_KEY = "30d39455d8ae27f049ab32c4b4bd608d";

/** Woher der benutzte Schlüssel kommt. Für die Anzeige, nie für die Logik. */
export type TMDBKeyOrigin = "own" | "builtIn";

export interface ResolvedTMDBKey {
  key: string;
  origin: TMDBKeyOrigin;
}

/**
 * Den zu benutzenden Schlüssel bestimmen.
 *
 * Gibt **immer** einen zurück: ohne eigenen den mitgelieferten. Einen Zustand
 * „kein Schlüssel" gibt es damit nicht mehr — wer TMDB nicht will, schaltet es
 * in den Einstellungen ausdrücklich ab, und das ist eine andere Entscheidung
 * als „ich habe noch nichts eingetragen".
 */
export function resolveTmdbKey(own?: string | null): ResolvedTMDBKey {
  const trimmed = (own ?? "").trim();
  if (trimmed) return { key: trimmed, origin: "own" };
  return { key: BUILT_IN_TMDB_KEY, origin: "builtIn" };
}
