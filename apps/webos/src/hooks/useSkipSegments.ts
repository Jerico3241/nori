// Überspringbare Abschnitte einer Folge — Intro, Outro, Zusammenfassung.
//
// Die AniWorld-/Serienstream-Quellen liefern **keine** verlässlichen
// Intro-/Outro-Zeitmarken. Deshalb gibt dieser Hook im aktuellen Stand immer
// eine leere Liste zurück: „Intro überspringen“ erscheint nicht. Das ist die
// saubere Vorbereitung — ein geratener 90-Sekunden-Wert wäre falsch und bleibt
// aus.
//
// Die Schnittstelle steht: liefert ein Provider später zuverlässige Marken,
// wird dieser Hook erweitert, ohne dass der Player dafür geändert werden
// muss. Das Modell selbst (`SkipSegment`, `activeSkipSegment`) liegt im
// gemeinsamen Kern und ist geräteübergreifend dasselbe.
import { type SkipSegment } from "@nori/core";

/**
 * Liefert die überspringbaren Abschnitte der laufenden Folge.
 *
 * Im aktuellen Stand immer leer — siehe Dateikopf. Der Aufruf ist bewusst ein
 * Hook und kein konstanter Export, damit ein späterer Anbieter asynchron
 * Marken nachladen kann, ohne die Aufrufstellen anzufassen.
 */
export function useSkipSegments(): SkipSegment[] {
  return EMPTY;
}

const EMPTY: SkipSegment[] = [];
