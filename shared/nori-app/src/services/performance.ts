// Wie viel sich dieser Fernseher leisten kann.
//
// ## Warum nicht am Modell festmachen
//
// Ein `LG 55UA75006LA` ist der Anlass dieser Datei, aber keine Bedingung
// darin. Modellnummern zu prüfen hieße: das nächste Gerät, das genauso schwach
// ist, bekommt die Verbesserung nicht, und ein Gerät, das LG später schneller
// macht, bekommt sie für immer. Gemessen wird deshalb, was zählt — wie schnell
// dieses Gerät rechnet und wie schnell die Navigation darauf tatsächlich
// reagiert.
//
// ## Drei Signale
//
// 1. **Ein kurzer Rechenlauf.** Eine feste Menge Fließkommaarbeit, gemessen in
//    Millisekunden. Auf einem Entwicklerrechner ein paar Millisekunden, auf der
//    CPU eines Einstiegs-Fernsehers ein Vielfaches. Er läuft **nach** dem
//    ersten Bild und nur einmal je Gerät; das Ergebnis liegt danach im
//    `localStorage`.
// 2. **Was das Gerät über sich sagt.** `hardwareConcurrency` und
//    `deviceMemory`, soweit vorhanden. Beides ist ein Hinweis, kein Beweis —
//    deshalb nie allein ausschlaggebend.
// 3. **Die gemessene Fokuslatenz.** Bleibt die Navigation über viele
//    Tastendrücke träge, wechselt der automatische Modus auch dann, wenn die
//    ersten beiden Signale unauffällig waren. Das ist das ehrlichste Signal,
//    weil es genau das misst, worum es geht.
//
// ## Was der sparsame Modus ändert
//
// Nichts an den Funktionen und wenig am Aussehen. Er nimmt weiche Flächen und
// mehrschichtige Schatten zurück, lädt weniger Bilder gleichzeitig, holt
// Offscreen-Bilder später und baut die Startseite in kleineren Schritten auf.
// Farben, Abstände, Schriftgrößen, Poster, Kopfbereich und die Fokusdarstellung
// bleiben, wie sie sind — Nori soll wie Nori aussehen, nur billiger gezeichnet.

import { log } from "./log";

export type PerformanceSetting = "auto" | "full" | "lean";
export type PerformanceMode = "full" | "lean";

export interface PerformanceProfile {
  mode: PerformanceMode;
  /** Wie viele Artwork-Abrufe gleichzeitig laufen dürfen. */
  artworkConcurrency: number;
  /** Vorlauf, ab dem ein Bild geladen wird. */
  artworkMargin: string;
  /** Vorlauf, ab dem TMDB nach einem Titel gefragt wird. */
  prefetchMargin: string;
  /** Wie viele Karten der ersten Reihe sofort geladen werden. */
  eagerCards: number;
  /** Wie viele Karten eine Reihe zunächst zeichnet. */
  railWindow: number;
  /** Wie viele Reihen zusammen nachgezogen werden. */
  railChunk: number;
}

const PROFILES: Record<PerformanceMode, PerformanceProfile> = {
  full: {
    mode: "full",
    artworkConcurrency: 4,
    artworkMargin: "220px 320px",
    prefetchMargin: "320px 420px",
    eagerCards: 5,
    railWindow: 10,
    railChunk: 2,
  },
  lean: {
    mode: "lean",
    artworkConcurrency: 2,
    artworkMargin: "80px 180px",
    prefetchMargin: "160px 260px",
    eagerCards: 3,
    railWindow: 8,
    railChunk: 1,
  },
};

const PROBE_KEY = "nori.webos.tier";

/** Ab hier gilt der Rechenlauf als langsam. Siehe `probeCpu`. */
const SLOW_PROBE_MS = 16;
/** Ab dieser mittleren Fokuslatenz gilt die Bedienung als zäh. */
const SLOW_FOCUS_MS = 14;

interface Tier {
  /** Dauer des Rechenlaufs in Millisekunden. */
  probeMs: number;
  slow: boolean;
  /** Woran es festgemacht wurde — nur für den Diagnosebereich. */
  reason: string;
}

let setting: PerformanceSetting = "auto";
let tier: Tier | null = null;
let escalated = false;
const listeners = new Set<() => void>();

/**
 * Ein fester Rechenlauf.
 *
 * Absichtlich Fließkomma und Speicherzugriff gemischt, weil genau das die
 * Oberfläche kostet: Boxen rechnen, Listen sortieren, Zeichenketten bauen.
 * Die Zahl ist für sich genommen bedeutungslos — sie zählt nur im Vergleich
 * zwischen Geräten.
 */
function probeCpu(): number {
  const start = performance.now();
  const values = new Float64Array(2048);
  for (let round = 0; round < 220; round += 1) {
    for (let index = 0; index < values.length; index += 1) {
      const value = values[index] + index * 0.5 + round;
      values[index] = value - Math.floor(value / 997) * 997;
    }
  }
  // Damit kein Übersetzer die Schleife wegwirft.
  if (values[0] === Number.MAX_VALUE) log("app", "unmöglich");
  return performance.now() - start;
}

function readStoredTier(): Tier | null {
  try {
    const raw = localStorage.getItem(PROBE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<Tier> & { agent?: string };
    if (parsed.agent !== navigator.userAgent) return null;
    if (typeof parsed.probeMs !== "number" || typeof parsed.slow !== "boolean") return null;
    return { probeMs: parsed.probeMs, slow: parsed.slow, reason: parsed.reason ?? "gespeichert" };
  } catch {
    return null;
  }
}

function storeTier(value: Tier): void {
  try {
    localStorage.setItem(PROBE_KEY, JSON.stringify({ ...value, agent: navigator.userAgent }));
  } catch {
    /* Ein voller Speicher ist kein Grund, langsamer zu zeichnen. */
  }
}

/** Was das Gerät über sich sagt. Ein Hinweis, nie allein ausschlaggebend. */
function declaredWeakness(): string | null {
  const nav = navigator as Navigator & { deviceMemory?: number };
  if (typeof nav.hardwareConcurrency === "number" && nav.hardwareConcurrency > 0 && nav.hardwareConcurrency <= 2) {
    return `${nav.hardwareConcurrency} Kerne`;
  }
  if (typeof nav.deviceMemory === "number" && nav.deviceMemory > 0 && nav.deviceMemory <= 1) {
    return `${nav.deviceMemory} GB`;
  }
  return null;
}

export function performanceProfile(): PerformanceProfile {
  return PROFILES[performanceMode()];
}

export function performanceMode(): PerformanceMode {
  if (setting === "full") return "full";
  if (setting === "lean") return "lean";
  if (escalated) return "lean";
  return tier?.slow ? "lean" : "full";
}

/** Woran der automatische Modus sich entschieden hat. Für die Diagnose. */
export function performanceReason(): string {
  if (setting !== "auto") return setting === "lean" ? "fest auf optimiert" : "fest auf normal";
  if (escalated) return "Fokuslatenz gemessen zu hoch";
  if (!tier) return "wird noch gemessen";
  return `${tier.reason} (${tier.probeMs.toFixed(0)} ms)`;
}

function apply(): void {
  const mode = performanceMode();
  if (document.documentElement.dataset.perf === mode) return;
  document.documentElement.dataset.perf = mode;
  log("app", "Leistungsmodus", mode, performanceReason());
  for (const listener of listeners) listener();
}

export function subscribePerformance(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function setPerformanceSetting(next: PerformanceSetting): void {
  if (setting === next) return;
  setting = next;
  // Eine ausdrückliche Wahl hebt eine frühere automatische Hochstufung auf.
  if (next !== "auto") escalated = false;
  apply();
}

/**
 * Die Messung anstoßen — nach dem ersten Bild, nicht davor.
 *
 * Der Rechenlauf kostet auf einem schwachen Gerät ein paar Dutzend
 * Millisekunden. Vor dem ersten Bild wären das ein paar Dutzend Millisekunden
 * länger Schwarz; danach fällt er in eine Lücke, die es ohnehin gibt.
 */
export function startPerformanceProbe(): void {
  if (tier) return;
  const stored = readStoredTier();
  if (stored) {
    tier = stored;
    apply();
    return;
  }
  const declared = declaredWeakness();
  const run = () => {
    if (tier) return;
    const probeMs = probeCpu();
    const slow = probeMs >= SLOW_PROBE_MS || declared !== null;
    tier = {
      probeMs,
      slow,
      reason: probeMs >= SLOW_PROBE_MS ? "Rechenlauf langsam" : declared ?? "Rechenlauf zügig",
    };
    storeTier(tier);
    apply();
  };
  const idle = (window as unknown as {
    requestIdleCallback?: (cb: () => void, options?: { timeout: number }) => number;
  }).requestIdleCallback;
  // Großzügige Frist: der Rechenlauf darf warten, bis der erste Aufbau
  // durch ist. Bis dahin gilt der gespeicherte Stand des Geräts, und beim
  // allerersten Start eben „normal".
  if (idle) idle(run, { timeout: 6000 });
  else window.setTimeout(run, 4000);
}

/**
 * Die Navigation meldet, dass sie dauerhaft zu lange braucht.
 *
 * Das überstimmt einen unauffälligen Rechenlauf: Was zählt, ist die Reaktion
 * auf die Fernbedienung, nicht eine Zahl aus einer Schleife.
 */
export function noteFocusLatency(averageMs: number, moves: number): void {
  if (escalated || setting !== "auto" || moves < 12) return;
  if (averageMs < SLOW_FOCUS_MS) return;
  escalated = true;
  log("app", "Leistungsmodus hochgestuft", `${averageMs.toFixed(1)} ms mittlere Fokuslatenz`);
  apply();
}

/** Beim Start: sofort ein Modus, damit das Stylesheet nie ohne dasteht. */
export function installPerformanceMode(initial: PerformanceSetting): void {
  setting = initial;
  const stored = readStoredTier();
  if (stored) tier = stored;
  apply();
}
