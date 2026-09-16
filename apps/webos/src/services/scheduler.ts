// Wann Hintergrundarbeit laufen darf.
//
// Auf einem Fernseher gibt es genau einen Thread, der zählt, und genau eine
// Sache, die darauf sofort passieren muss: die Reaktion auf die Fernbedienung.
// Alles andere — TMDB-Treffer einarbeiten, Reihen neu bewerten, Reihen
// nachziehen — ist wichtig, aber nie dringend.
//
// Zwei Werkzeuge, mehr braucht es nicht:
//
//     whenIdle       etwas tun, wenn gerade nichts läuft
//     batched        etwas gebündelt tun, aber nicht mitten im Tastendruck
//
// Beide mit Rückfall für Browser ohne `requestIdleCallback` — webOS 6 fährt
// Chrome 79 und hat es, ältere Stände nicht.

import { navigating } from "../navigation/engine";

interface IdleWindow {
  requestIdleCallback?: (callback: () => void, options?: { timeout: number }) => number;
  cancelIdleCallback?: (handle: number) => void;
}

/** Etwas erledigen, wenn gerade nichts Wichtigeres läuft. */
export function whenIdle(callback: () => void, timeout = 400): () => void {
  const host = window as unknown as IdleWindow;
  if (host.requestIdleCallback && host.cancelIdleCallback) {
    const handle = host.requestIdleCallback(callback, { timeout });
    return () => host.cancelIdleCallback?.(handle);
  }
  const timer = window.setTimeout(callback, Math.min(timeout, 60));
  return () => window.clearTimeout(timer);
}

/** Wie lange nach einem Tastendruck noch gewartet wird, bevor es weitergeht. */
const DEFER_MS = 120;
/** So oft darf eine Arbeit der Navigation ausweichen, dann läuft sie. */
const MAX_DEFERRALS = 3;

export interface Batched {
  /** Anmelden. Mehrfaches Anmelden vor dem Ablauf ist ein Durchlauf. */
  schedule(): void;
  cancel(): void;
}

/**
 * Eine Arbeit bündeln — und sie nicht ausgerechnet dann tun, wenn jemand
 * gerade durch die Startseite läuft.
 *
 * Der Aufschub ist beschränkt: verschoben wird jeweils um ein Sechstel einer
 * Sekunde, und sobald die Navigation ruht, läuft es. Eine gehaltene Taste kann
 * die Arbeit damit hinauszögern, aber nie verhindern.
 */
export function batched(delayMs: number, run: () => void): Batched {
  let timer: number | null = null;
  let deferrals = 0;
  const fire = () => {
    // Höchstens dreimal ausweichen. Wer die Pfeiltaste festhält, schiebt die
    // Arbeit sonst beliebig lange vor sich her — und auf der Startseite ist
    // genau diese Arbeit das, was die Reihen überhaupt füllt.
    if (navigating() && deferrals < MAX_DEFERRALS) {
      deferrals += 1;
      timer = window.setTimeout(fire, DEFER_MS);
      return;
    }
    timer = null;
    deferrals = 0;
    run();
  };
  return {
    schedule() {
      if (timer !== null) return;
      timer = window.setTimeout(fire, delayMs);
    },
    cancel() {
      if (timer !== null) window.clearTimeout(timer);
      timer = null;
      deferrals = 0;
    },
  };
}
