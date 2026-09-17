// Was ein Tastendruck kostet — gezählt, nicht geschätzt.
//
// „Die Navigation ruckelt" ist keine Größe, mit der sich arbeiten lässt. Diese
// Datei macht drei daraus:
//
//     Fokuslatenz            keydown → Fokus steht
//     Vermessene Elemente    wie viele Boxen der Browser dafür liefern musste
//     Betrachtete Elemente   wie groß der Suchraum war
//
// Die Zähler laufen immer mit — es sind drei Additionen je Tastendruck, und
// ohne sie wäre jede Aussage über „vorher/nachher" eine Behauptung. Ausgegeben
// wird nur mit eingeschaltetem Entwicklerschalter; im Regelbetrieb entsteht
// kein einziger Protokolleintrag.
//
// `window.__noriNav` ist der Zugang für `test/perf-bench.mjs` und für den
// Diagnosebereich. Es ist ein reines Zahlenobjekt, kein Steuerpult: nichts
// daran verändert das Verhalten der App.

import { isVerbose, log, noteFocusLatency } from "@nori/app";

export interface NavMetrics {
  /** Tastendrücke seit dem Start. */
  moves: number;
  /** Vom Browser neu vermessene Elemente. Der teure Teil. */
  measured: number;
  /** Aus dem Zwischenspeicher beantwortete Messungen. */
  cached: number;
  /** Elemente, die überhaupt als Ziel infrage kamen. */
  scanned: number;
  /** Wie oft die örtliche Suche nicht reichte und die ganze Seite dran war. */
  fullScans: number;
  /** Wie oft der Geometriespeicher verworfen wurde. */
  invalidations: number;
  /** Letzte Fokuslatenz in Millisekunden — Taste bis Fokus steht. */
  lastMs: number;
  /**
   * Davon die reine Suche: welches Element als Nächstes drankommt.
   *
   * Der Rest ist `focus()`, das Sichtbarmachen und die Arbeit, die React an
   * das Fokusereignis hängt. Getrennt zu messen lohnt, weil nur der erste Teil
   * dieser Datei gehört.
   */
  searchMs: number;
  /** Gleitender Mittelwert der Fokuslatenz. */
  averageMs: number;
  /** Längste gemessene Fokuslatenz. */
  worstMs: number;
}

const metrics: NavMetrics = {
  moves: 0,
  measured: 0,
  cached: 0,
  scanned: 0,
  fullScans: 0,
  invalidations: 0,
  lastMs: 0,
  searchMs: 0,
  averageMs: 0,
  worstMs: 0,
};

declare global {
  interface Window {
    __noriNav?: NavMetrics;
  }
}

window.__noriNav = metrics;

export function navMetrics(): NavMetrics {
  return metrics;
}

export function countMeasured(): void {
  metrics.measured += 1;
}

export function countCached(): void {
  metrics.cached += 1;
}

export function countScanned(amount: number): void {
  metrics.scanned += amount;
}

export function countFullScan(): void {
  metrics.fullScans += 1;
}

export function countInvalidation(): void {
  metrics.invalidations += 1;
}

/**
 * Die Dauer eines Tastendrucks festhalten.
 *
 * Der gleitende Mittelwert ist bewusst träge (Faktor 0,25): er steuert die
 * Wiederholsperre der gehaltenen Taste, und die soll nicht bei jedem Ausreißer
 * springen.
 */
export function recordSearch(durationMs: number): void {
  metrics.searchMs = durationMs;
}

export function recordMove(durationMs: number, dir: string, poolSize: number): void {
  metrics.moves += 1;
  metrics.lastMs = durationMs;
  metrics.averageMs = metrics.moves === 1
    ? durationMs
    : metrics.averageMs + (durationMs - metrics.averageMs) * 0.25;
  if (durationMs > metrics.worstMs) metrics.worstMs = durationMs;
  // Erst fragen, dann formatieren: ohne Entwicklerschalter entsteht nicht
  // einmal die Zeichenkette.
  if (isVerbose()) log("nav", "Fokus", dir, `${durationMs.toFixed(1)} ms`, `${poolSize} Kandidaten`);
  // Bleibt die Bedienung zäh, entscheidet das den automatischen
  // Leistungsmodus — die Messung an der Sache selbst, nicht am Modellnamen.
  noteFocusLatency(metrics.averageMs, metrics.moves);
}

export function resetNavMetrics(): void {
  metrics.moves = 0;
  metrics.measured = 0;
  metrics.cached = 0;
  metrics.scanned = 0;
  metrics.fullScans = 0;
  metrics.invalidations = 0;
  metrics.lastMs = 0;
  metrics.searchMs = 0;
  metrics.averageMs = 0;
  metrics.worstMs = 0;
}
