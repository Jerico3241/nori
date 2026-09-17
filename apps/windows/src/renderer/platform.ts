// Was der geteilte Unterbau über diesen Schreibtisch wissen darf.
//
// Vier Fragen (`shared/nori-app/src/platform.ts`), und jede hat auf dem
// Desktop eine andere Antwort als auf dem Fernseher.

import type { DeviceSettings, NoriPlatform } from "@nori/app";

import { bridge, inShell } from "./bridge";

/**
 * „Die Eingabe arbeitet gerade."
 *
 * Auf dem Fernseher heißt das: der Fokus bewegt sich. Auf dem Schreibtisch
 * heißt es: es wird gescrollt oder gezogen. In beiden Fällen ist es derselbe
 * Hauptthread, um den es geht — und derselbe Unterschied zwischen einer
 * Oberfläche, die mitkommt, und einer, die hakt.
 *
 * Gemessen wird am Ereignis, nicht geraten: Scroll- und Zeigerereignisse
 * setzen einen Zeitstempel, und „beschäftigt" gilt für die nächsten 140 ms.
 */
const BUSY_MS = 140;
let busyUntil = 0;

function markBusy(): void {
  busyUntil = performance.now() + BUSY_MS;
}

export function installInputTracking(): void {
  const options = { passive: true, capture: true } as const;
  window.addEventListener("wheel", markBusy, options);
  window.addEventListener("scroll", markBusy, options);
  window.addEventListener("pointermove", markBusy, options);
  window.addEventListener("keydown", markBusy, options);
}

/**
 * Die Zeichenfläche in echten Bildpunkten.
 *
 * Auf dem Schreibtisch ist `devicePixelRatio` tatsächlich die Wahrheit — er
 * beschreibt dort die Skalierung, mit der Windows zeichnet (125 %, 150 %,
 * 200 %). Anders als auf dem Fernseher, wo er das Panel beschreibt und nicht
 * die Fläche. Begrenzt wird trotzdem: jenseits des Doppelten wächst nur die
 * Dekodierzeit, nicht das Bild.
 */
function surfaceWidth(): number {
  const ratio = Math.min(window.devicePixelRatio || 1, 2);
  return (window.innerWidth || 1280) * ratio;
}

export const windowsPlatform: NoriPlatform = {
  kind: "windows",
  surfaceWidth,
  isInputBusy: () => performance.now() < busyUntil,
  openExternal(url) {
    const api = bridge();
    if (api) void api.openExternal(url);
    else window.open(url, "_blank", "noopener,noreferrer");
  },
  exit() {
    const api = bridge();
    if (api) void api.window.close();
    else window.close();
  },
};

/**
 * Womit dieser Rechner startet, wenn noch nichts eingestellt ist.
 *
 * `local` heißt: die Quellenschicht läuft im Hauptprozess. Kein Server, keine
 * Einrichtung, kein Port. Im Browser — dem Entwicklungsstand — gibt es die
 * Brücke nicht; dort bleibt es beim direkten Weg, der an der Herkunftsprüfung
 * scheitern kann und genau deshalb kein Auslieferungszustand ist.
 */
export const WINDOWS_DEFAULTS: Partial<DeviceSettings> = {
  transport: inShell() ? "local" : "direct",
  tmdbMode: "direct",
  serverUrl: "",
};
