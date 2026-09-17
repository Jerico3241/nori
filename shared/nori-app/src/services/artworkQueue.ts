// Wie viele Bilder gleichzeitig entstehen dürfen.
//
// ## Das Problem
//
// Ein `<img src>` im DOM ist kein Wunsch, sondern ein Auftrag: abrufen,
// dekodieren, als Textur ablegen. Auf der Startseite standen bis zu achtzig
// davon gleichzeitig im Baum, dazu der Kopfbereich. Ein Fernseher mit knappem
// Speicher hat dann achtzig halbfertige Dekodierungen und eine Fernbedienung,
// die auf den Hauptthread wartet — genau in dem Moment, in dem jemand die
// Startseite zum ersten Mal sieht und durchblättert.
//
// `loading="lazy"` löst das nicht: Chromium setzt den Vorlauf abhängig von der
// gemessenen Verbindung und lädt auf einem schnellen Netz praktisch die ganze
// Seite. Auf einem Fernseher ist die Verbindung selten der Engpass — die CPU
// ist es.
//
// ## Die Regel
//
// Drei bis vier Bilder gleichzeitig, und wer zuerst drankommt, entscheidet
// eine Rangfolge:
//
//     0  Kopfbereich und die gerade fokussierte Kachel
//     1  Karten der ersten Reihe (`eager`)
//     2  alles andere, sobald es in Sichtweite kommt
//
// Innerhalb einer Stufe gilt die Reihenfolge der Anmeldung, und angemeldet
// wird erst beim Eintritt in den Sichtbereich — das ist von oben nach unten
// und von links nach rechts genau die Reihenfolge, in der jemand hinsieht.
//
// Ein Platz wird frei, wenn das Bild geladen ist, gescheitert ist, oder wenn
// die Kachel verschwindet. Bleibt eine Antwort ganz aus — ein Hoster, der
// hängt —, gibt eine Frist den Platz nach acht Sekunden zurück; ohne sie
// blockierte ein einziges totes Bild die ganze Seite.

import { platform } from "../platform";
import { performanceProfile, subscribePerformance } from "./performance";

export const ARTWORK_PRIORITY = {
  hero: 0,
  eager: 1,
  visible: 2,
} as const;

/** Nach dieser Zeit gilt ein Bild als aufgegeben und gibt seinen Platz frei. */
const WATCHDOG_MS = 8000;
/** Solange die Eingabe arbeitet, läuft höchstens ein Abruf. */
const BUSY_LIMIT = 1;
/** Wann nach einer blockierten Runde erneut versucht wird. */
const RETRY_MS = 120;

interface Slot {
  priority: number;
  seq: number;
  start(): void;
  cancelled: boolean;
}

export interface ArtworkSlot {
  /** Den Platz zurückgeben — geladen, gescheitert oder nicht mehr gebraucht. */
  release(): void;
}

let sequence = 0;
let running = 0;
let waiting: Slot[] = [];
let retryTimer: number | null = null;

function limit(): number {
  const profile = performanceProfile();
  return platform().isInputBusy() ? Math.min(BUSY_LIMIT, profile.artworkConcurrency) : profile.artworkConcurrency;
}

function scheduleRetry(): void {
  if (retryTimer !== null) return;
  retryTimer = window.setTimeout(() => {
    retryTimer = null;
    pump();
  }, RETRY_MS);
}

function pump(): void {
  while (waiting.length > 0 && running < limit()) {
    let bestIndex = 0;
    for (let index = 1; index < waiting.length; index += 1) {
      const entry = waiting[index];
      const best = waiting[bestIndex];
      if (entry.priority < best.priority || (entry.priority === best.priority && entry.seq < best.seq)) {
        bestIndex = index;
      }
    }
    const slot = waiting.splice(bestIndex, 1)[0];
    if (slot.cancelled) continue;
    running += 1;
    slot.start();
  }
  // Blockiert nur die Eingabe, kommt der Rest gleich dran.
  if (waiting.length > 0) scheduleRetry();
}

/**
 * Einen Platz anfordern.
 *
 * `start` wird aufgerufen, sobald einer frei ist — gegebenenfalls sofort. Der
 * Aufrufer gibt ihn über das Ergebnis zurück; ein zweiter Aufruf von
 * `release` ist wirkungslos.
 */
export function requestArtworkSlot(priority: number, start: () => void): ArtworkSlot {
  sequence += 1;
  const slot: Slot = { priority, seq: sequence, start, cancelled: false };
  let held = false;
  let watchdog: number | null = null;

  const done = () => {
    if (slot.cancelled) return;
    slot.cancelled = true;
    if (watchdog !== null) window.clearTimeout(watchdog);
    if (held) {
      running -= 1;
      pump();
      return;
    }
    const index = waiting.indexOf(slot);
    if (index >= 0) waiting.splice(index, 1);
  };

  slot.start = () => {
    held = true;
    watchdog = window.setTimeout(done, WATCHDOG_MS);
    start();
  };

  waiting.push(slot);
  pump();
  return { release: done };
}

/** Wie viele Abrufe gerade laufen und warten. Für die Diagnose und die Tests. */
export function artworkQueueState(): { running: number; waiting: number; limit: number } {
  return { running, waiting: waiting.length, limit: limit() };
}

/** Beim Seitenwechsel: wer noch wartet, wartet nicht mehr. */
export function clearArtworkQueue(): void {
  for (const slot of waiting) slot.cancelled = true;
  waiting = [];
}

subscribePerformance(pump);

declare global {
  interface Window {
    __noriArtwork?: () => { running: number; waiting: number; limit: number };
  }
}

window.__noriArtwork = artworkQueueState;
