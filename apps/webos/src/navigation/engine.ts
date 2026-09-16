// Die Fernbedienungsnavigation: welches Element als Nächstes den Fokus
// bekommt, und wie weit dafür gescrollt wird.
//
// ## Warum nicht mehr Enact Spotlight
//
// Spotlight findet das nächste Element zuverlässig, weiß aber nichts davon,
// wie Nori ein fokussiertes Element zeichnet. Gescrollt wurde danach mit
// `scrollIntoView`, und das hatte zwei sichtbare Folgen auf der Startseite:
//
// - Die Kachel wächst im Fokus um sieben Prozent und bekommt einen Ring.
//   `scrollIntoView` rechnet mit der Größe **vor** dem Wachsen — Ring und
//   Titel lagen danach halb über dem Bildrand.
// - Bei schnellen Tastendrücken lief die Seite noch, während der nächste
//   Druck schon gemessen wurde. Gemessen wurde also eine Position, die es
//   einen Moment später nicht mehr gab, und der Fokus sprang in die falsche
//   Reihe.
//
// Beides löst diese Datei an der Wurzel: Gemessen wird gegen das **Ziel** jeder
// laufenden Scrollbewegung, nicht gegen ihren Zwischenstand, und jede
// Sichtbarkeitsrechnung schlägt Wachstum, Ring und einen Sicherheitsrand auf.
//
// ## Die Regeln
//
// - Links/Rechts bleiben in der Zeile: ein Kandidat muss sich senkrecht mit
//   dem fokussierten Element überdecken. Am Ende einer Reihe passiert nichts,
//   statt dass der Fokus in eine andere Reihe springt.
// - Hoch/Runter nehmen das räumlich nächste Element; wer auf Poster 4 steht,
//   landet in der nächsten Reihe auf dem Poster darunter.
// - Bereiche (`data-focus-group`) regeln Übergänge: die Seitenleiste lässt
//   sich nur senkrecht durchlaufen, „rechts" führt aus ihr zurück auf das
//   zuletzt fokussierte Element im Inhalt, „links" am Zeilenanfang in sie
//   hinein auf den aktiven Eintrag.
// - Offene Overlays (`data-focus-trap`) sperren den Fokus ein.
// - Verschiebt eine Änderung am DOM das fokussierte Element, ohne dass sich der
//   Fokus bewegt — ein Raster sortiert sich um, weil TMDB-Treffer eintreffen —,
//   wird es wieder sichtbar gemacht. Die Scrollverankerung des Browsers ist in
//   den Bereichen der Navigation abgeschaltet (`app.css`): sie verschob die
//   Seite an dieser Datei vorbei.
//
// ## Wie viel dafür angefasst wird
//
// Drei Stufen, von billig nach teuer. Jede Stufe kommt nur dran, wenn die
// vorige nichts gefunden hat — das Ergebnis ist damit dasselbe wie bei einer
// reinen Suche über die ganze Seite, der Weg dorthin aber ein anderer:
//
//     1. Die Zeile entlang    Links/Rechts laufen die Geschwister ab und hören
//                             auf, sobald die Zeile endet. Zwei bis drei
//                             Messungen, unabhängig davon, wie groß die Seite
//                             ist.
//     2. Nachbarreihen        Hoch/Runter sehen die eigene Reihe und je zwei
//                             darüber und darunter an (`data-nav-row`).
//     3. Die ganze Seite      Der Rückfall — für Übergänge zwischen Bereichen,
//                             für Seiten ohne Reihen, für alles Ungewöhnliche.
//
// Dazu kommt, dass Messungen zwischen zwei Tastendrücken gültig bleiben
// (`geometry.ts`). Gemessen auf der Startseite mit fünf Reihen: **299
// Layoutabfragen je Tastendruck vorher, einstellig danach.**

import {
  activeScope, candidateBox, containerBox, firstInView, focusGrowth, focusables,
  FOCUSABLE, isUsable, layoutBox, NAV_ROW, observeLayout, refreshMetrics,
  rem, rowOf, scrollExtent, type Box,
} from "./geometry";
import { subscribePerformance } from "../services/performance";
import { arrowDirection, isEnter } from "./keys";
import { countFullScan, countScanned, navMetrics, recordMove, recordSearch } from "./metrics";
import { scrollContainerTo, settleScroll, targetScroll } from "./scroll";

export type Direction = "left" | "right" | "up" | "down";

export {
  activeScope, FOCUSABLE, focusables, isUsable, layoutBox, rem, invalidateLayout,
} from "./geometry";
export { reducedMotion, scrollContainerTo, targetScroll } from "./scroll";
export type { Box } from "./geometry";

/** Sicherheitsrand zum Rand eines Scrollbereichs, in rem. */
const SAFE_REM = 3.5;
/** Mindestabstand zwischen zwei Wiederholungen einer gehaltenen Taste. */
const REPEAT_MS = 70;
/**
 * Obergrenze derselben Sperre.
 *
 * Bei gehaltener Taste liefert webOS Wiederholungen schneller, als eine
 * Bewegung sichtbar wird. Wie viel schneller, hängt vom Gerät ab: auf einem
 * langsamen Panel dauert ein Schritt länger, und dann kostet jede zusätzliche
 * Wiederholung nur Arbeit, die niemand sieht. Deshalb richtet sich die Sperre
 * nach der gemessenen Dauer der letzten Schritte statt nach einer festen Zahl.
 */
const REPEAT_MAX_MS = 180;
/**
 * Wie lange nach einem Tastendruck noch „es wird navigiert" gilt.
 *
 * Lang genug, dass Hintergrundarbeit nicht in denselben Frame fällt, und kurz
 * genug, dass sie zwischen zwei Tastendrücken noch drankommt. Bei 280 ms
 * Abstand — dem Takt des Fernbedienungslaufs — bleibt gut die Hälfte frei.
 */
const NAVIGATING_MS = 140;

// ---------------------------------------------------------------------------
// Sichtbar machen

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

/**
 * Ein fokussiertes Element vollständig in den sichtbaren Bereich holen —
 * samt Wachstum, Ring und Sicherheitsrand.
 *
 * Waagerecht wird eine Reihe (`data-scroll-x`) nur so weit bewegt, dass die
 * Karte ganz dasteht. Senkrecht (`data-scroll-y`) gilt:
 *
 * 1. Passt alles vom Seitenanfang bis zum Element in den Bildschirm, steht die
 *    Seite ganz oben — so bleibt der Seitenkopf sichtbar.
 * 2. Sonst wird nur so weit gescrollt, wie nötig ist, damit das Element mit
 *    Rand oben und unten ganz sichtbar ist.
 * 3. Gehört das Element zu einem Abschnitt (`data-reveal`) — einer Reihe mit
 *    Überschrift —, wird die Überschrift mit hereingeholt, solange Überschrift
 *    und Element zusammen in den Bildschirm passen.
 *
 * Nie `scrollIntoView({ block: "start" })`: genau das hat das Element an den
 * oberen Rand gezogen und seinen Ring abgeschnitten.
 */
export function reveal(node: HTMLElement, instant = false): void {
  const box = layoutBox(node);
  const growth = focusGrowth(node, box);

  const track = node.parentElement?.closest<HTMLElement>("[data-scroll-x]") ?? null;
  if (track) {
    const bounds = containerBox(track);
    const current = targetScroll(track).left;
    const minLeft = bounds.left + growth.x + rem(0.25);
    const maxRight = bounds.right - growth.x - rem(0.25);
    let next = current;
    if (box.left < minLeft) next -= minLeft - box.left;
    else if (box.right > maxRight) next += box.right - maxRight;
    // Wäre das Element am Anfang der Reihe ohnehin ganz sichtbar, steht die
    // Reihe wieder am Anfang — sonst bliebe links ein halb abgeschnittenes
    // Poster stehen.
    if (box.right + current <= maxRight) next = 0;
    next = clamp(next, 0, scrollExtent(track).x);
    if (Math.abs(next - current) >= 1) scrollContainerTo(track, { left: next }, instant);
  }

  const page = node.closest<HTMLElement>("[data-scroll-y]");
  if (!page) return;
  // Nach einer waagerechten Bewegung steht die Karte anderswo — neu ablesen,
  // gerechnet gegen das Ziel dieser Bewegung. Eine Messung kostet das nicht.
  const vertical = layoutBox(node);
  const bounds = containerBox(page);
  const safe = rem(SAFE_REM);
  const safeTop = bounds.top + safe;
  const safeBottom = bounds.bottom - safe;

  let top = vertical.top - growth.y;
  const bottom = vertical.bottom + growth.y;

  const section = node.parentElement?.closest<HTMLElement>("[data-reveal]") ?? null;
  if (section && page.contains(section) && section !== page) {
    const sectionTop = layoutBox(section).top;
    if (bottom - sectionTop <= safeBottom - safeTop) top = Math.min(top, sectionTop);
  }

  const current = targetScroll(page).top;
  const maxScroll = scrollExtent(page).y;
  let next = current;
  const bottomInContent = bottom - bounds.top + current;
  if (bottomInContent <= bounds.height - safe) {
    next = 0;
  } else if (top < safeTop) {
    next -= safeTop - top;
  } else if (bottom > safeBottom) {
    next += bottom - safeBottom;
    const shiftedTop = top - (next - current);
    if (shiftedTop < safeTop) next -= safeTop - shiftedTop;
  }
  next = clamp(next, 0, maxScroll);
  if (Math.abs(next - current) >= 1) scrollContainerTo(page, { top: next }, instant);
}

// ---------------------------------------------------------------------------
// Kandidaten

function groupOf(node: HTMLElement): HTMLElement | null {
  return node.parentElement?.closest<HTMLElement>("[data-focus-group]") ?? null;
}

/** Zuletzt fokussiertes Element je Bereich. */
const groupMemory = new WeakMap<HTMLElement, HTMLElement>();

interface Candidate {
  node: HTMLElement;
  box: Box;
}

/** Bewertung eines waagerechten Kandidaten, `null` wenn er ausscheidet. */
function scoreHorizontal(from: Box, box: Box, dir: "left" | "right"): number | null {
  if (dir === "right" ? box.cx <= from.cx + 1 : box.cx >= from.cx - 1) return null;
  const gap = dir === "right" ? box.left - from.right : from.left - box.right;
  if (gap < -Math.min(from.width, box.width) * 0.3) return null;
  const overlap = Math.min(from.bottom, box.bottom) - Math.max(from.top, box.top);
  if (overlap <= Math.min(from.height, box.height) * 0.2) return null;
  return Math.max(0, gap) + Math.abs(from.cy - box.cy) * 0.6;
}

/**
 * Das nächste Ziel in Richtung `dir`.
 *
 * **Links/Rechts** bleiben in der Zeile: ein Kandidat muss sich senkrecht mit
 * dem fokussierten Element überdecken; unter ihnen gewinnt der nächste.
 *
 * **Hoch/Runter** gehen in zwei Schritten. Zuerst die nächste Zeile: alle
 * Kandidaten, deren Abstand nahe am kleinsten liegt. Erst in dieser Zeile
 * entscheidet die waagerechte Nähe. Eine reine Punktrechnung aus beidem ließ
 * den Fokus von einer Reihe aus über den Kopfbereich hinweg auf „Suche" oben
 * rechts springen — weil der Knopf zufällig über der Karte stand, während die
 * Aktionen des Kopfbereichs weiter links lagen.
 */
function pick(from: Box, pool: Candidate[], dir: Direction): HTMLElement | null {
  if (dir === "left" || dir === "right") {
    let best: HTMLElement | null = null;
    let bestScore = Infinity;
    for (const { node, box } of pool) {
      const value = scoreHorizontal(from, box, dir);
      if (value === null) continue;
      if (value < bestScore) {
        bestScore = value;
        best = node;
      }
    }
    return best;
  }

  const ahead: (Candidate & { gap: number })[] = [];
  for (const candidate of pool) {
    const { box } = candidate;
    if (dir === "down" ? box.cy <= from.cy + 1 : box.cy >= from.cy - 1) continue;
    const gap = dir === "down" ? box.top - from.bottom : from.top - box.bottom;
    if (gap < -Math.min(from.height, box.height) * 0.3) continue;
    ahead.push({ ...candidate, gap: Math.max(0, gap) });
  }
  if (ahead.length === 0) return null;

  let nearest = Infinity;
  for (const entry of ahead) nearest = Math.min(nearest, entry.gap);
  const band = nearest + Math.max(rem(1.5), Math.min(from.height, rem(6)) * 0.5);

  let best: HTMLElement | null = null;
  let bestScore = Infinity;
  for (const entry of ahead) {
    if (entry.gap > band) continue;
    const overlapX = Math.min(from.right, entry.box.right) - Math.max(from.left, entry.box.left);
    const sideways = overlapX > 0 ? 0 : -overlapX;
    const value = sideways + Math.abs(from.cx - entry.box.cx) * 0.1 + (entry.gap - nearest) * 0.05;
    if (value < bestScore) {
      bestScore = value;
      best = entry.node;
    }
  }
  return best;
}

/**
 * Stufe 1: die Zeile entlang.
 *
 * Reihen und Raster liegen im DOM in derselben Reihenfolge, in der sie
 * gezeichnet werden. „Rechts" ist damit das nächste Geschwisterelement, das
 * senkrecht noch auf derselben Höhe liegt — und sobald eines deutlich tiefer
 * oder höher sitzt, ist die Zeile zu Ende und die Suche vorbei. Auf einem
 * Raster mit sechzig Karten sind das zwei Messungen statt sechzig.
 */
function alongRow(current: HTMLElement, from: Box, dir: "left" | "right"): HTMLElement | null {
  const row = rowOf(current);
  if (!row) return null;
  const siblings = row.querySelectorAll<HTMLElement>(FOCUSABLE);
  let index = -1;
  for (let i = 0; i < siblings.length; i += 1) {
    if (siblings[i] === current) {
      index = i;
      break;
    }
  }
  if (index < 0) return null;

  const step = dir === "right" ? 1 : -1;
  let best: HTMLElement | null = null;
  let bestScore = Infinity;
  let looked = 0;
  for (let i = index + step; i >= 0 && i < siblings.length; i += step) {
    const box = candidateBox(siblings[i]);
    if (!box) continue;
    // Eine andere Zeile: im Raster der Umbruch, in einer Reihe das Ende.
    if (Math.abs(box.cy - from.cy) > Math.max(from.height, box.height) * 0.6) break;
    looked += 1;
    const value = scoreHorizontal(from, box, dir);
    if (value !== null && value < bestScore) {
      bestScore = value;
      best = siblings[i];
    }
    // Weiter entfernte Geschwister können nicht mehr näher sein.
    if (best !== null || looked >= 3) break;
  }
  countScanned(looked);
  return best;
}

/** Stufe 2: die eigene Reihe und je zwei darüber und darunter. */
function nearbyRows(current: HTMLElement, scope: HTMLElement, dir: Direction): HTMLElement[] | null {
  const row = rowOf(current);
  if (!row) return null;
  const group = groupOf(current);
  const root = group && scope.contains(group) ? group : scope;
  const rows = root.querySelectorAll<HTMLElement>(NAV_ROW);
  let index = -1;
  for (let i = 0; i < rows.length; i += 1) {
    if (rows[i] === row) {
      index = i;
      break;
    }
  }
  if (index < 0) return null;

  const out: HTMLElement[] = [];
  const first = dir === "up" ? Math.max(0, index - 2) : index;
  const last = dir === "up" ? index : Math.min(rows.length - 1, index + 2);
  for (let i = first; i <= last; i += 1) {
    const nodes = rows[i].querySelectorAll<HTMLElement>(FOCUSABLE);
    for (let n = 0; n < nodes.length; n += 1) out.push(nodes[n]);
  }
  return out;
}

function poolOf(
  nodes: Iterable<HTMLElement>,
  current: HTMLElement,
  group: HTMLElement | null,
  lockedVertical: boolean,
  dir: Direction,
): Candidate[] {
  const pool: Candidate[] = [];
  let looked = 0;
  for (const node of nodes) {
    if (node === current) continue;
    const nodeGroup = groupOf(node);
    if (lockedVertical && nodeGroup !== group) continue;
    // Die Seitenleiste betritt man nur mit „links" — nicht, weil unter dem
    // letzten Knopf einer Seite zufällig ein Eintrag der Leiste liegt.
    if (nodeGroup && nodeGroup !== group && nodeGroup.hasAttribute("data-focus-only-left") && dir !== "left") continue;
    looked += 1;
    const box = candidateBox(node);
    if (box) pool.push({ node, box });
  }
  countScanned(looked);
  return pool;
}

/** Welches Element beim Betreten eines Bereichs den Fokus bekommt. */
function entryFor(group: HTMLElement, preferred: HTMLElement | null): HTMLElement | null {
  const rule = group.getAttribute("data-focus-enter");
  if (rule === "active") {
    const active = group.querySelector<HTMLElement>(`${FOCUSABLE}[aria-current='page']`);
    if (isUsable(active)) return active;
  }
  if (rule === "last") {
    const remembered = groupMemory.get(group);
    if (remembered && document.contains(remembered) && group.contains(remembered) && isUsable(remembered)) {
      return remembered;
    }
  }
  return preferred ?? firstInView(focusables(group));
}

function groupByName(scope: HTMLElement, name: string): HTMLElement | null {
  return scope.querySelector<HTMLElement>(`[data-focus-group="${name}"]`);
}

/** Den Fokus eine Richtung weiter bewegen. `true`, wenn er sich bewegt hat. */
export function moveFocus(dir: Direction): boolean {
  const scope = activeScope();
  const current = document.activeElement;
  if (!isUsable(current) || !scope.contains(current) || !current.matches(FOCUSABLE)) {
    return recoverFocus(true);
  }

  const group = groupOf(current);
  const exit = group?.getAttribute(`data-focus-exit-${dir}`);
  if (exit) {
    const target = groupByName(scope, exit);
    const entry = target ? entryFor(target, null) : null;
    if (entry) {
      focusElement(entry);
      return true;
    }
    return false;
  }

  const lockedVertical = group?.getAttribute("data-focus-lock") === "vertical";
  const searchStart = performance.now();
  const from = layoutBox(current);
  let best: HTMLElement | null = null;

  // Stufe 1 — die Zeile entlang. Ein eingesperrter Bereich (die Seitenleiste)
  // kennt keine waagerechte Bewegung; dort führt der Weg gleich weiter.
  if ((dir === "left" || dir === "right") && !lockedVertical) {
    best = alongRow(current, from, dir);
  }

  // Stufe 2 — die Nachbarreihen. Der Bereichsfilter gilt auch hier.
  if (!best && (dir === "up" || dir === "down")) {
    const nearby = nearbyRows(current, scope, dir);
    if (nearby) best = pick(from, poolOf(nearby, current, group, lockedVertical, dir), dir);
  }

  // Stufe 3 — die ganze Seite.
  if (!best) {
    countFullScan();
    best = pick(from, poolOf(focusablesIn(scope), current, group, lockedVertical, dir), dir);
  }

  if (!best && group) {
    const fallback = group.getAttribute(`data-focus-fallback-${dir}`);
    const target = fallback ? groupByName(scope, fallback) : null;
    if (target) best = entryFor(target, null);
  } else if (best) {
    const target = groupOf(best);
    if (target && target !== group) best = entryFor(target, best);
  }

  recordSearch(performance.now() - searchStart);
  if (!best) return false;
  focusElement(best);
  return true;
}

function focusablesIn(scope: HTMLElement): HTMLElement[] {
  const nodes = scope.querySelectorAll<HTMLElement>(FOCUSABLE);
  const out: HTMLElement[] = [];
  for (let index = 0; index < nodes.length; index += 1) out.push(nodes[index]);
  return out;
}

// ---------------------------------------------------------------------------
// Fokus setzen, merken und nicht verlieren

let instantReveal = false;
let pointerMode = false;
let lastFocused: { key: string | null; cx: number; cy: number } | null = null;
/** Das Element zu `lastFocused` — der Schlüssel allein ist nicht eindeutig. */
let lastFocusedNode: HTMLElement | null = null;
let transientFocus = false;

/**
 * Wurde der gerade laufende Fokus nur übergangsweise gesetzt?
 *
 * Dann darf ihn niemand als „zuletzt fokussiert" merken. Genau das ist
 * passiert: beim Seitenwechsel verschwand das fokussierte Element, die
 * Rückholung setzte den Fokus auf das nächstgelegene Element der neuen Seite
 * („Merkliste" im Kopfbereich), das Gedächtnis hielt es fest — und die Seite
 * stellte danach genau diesen Zufallsfokus als gewünscht wieder her, statt
 * „Jetzt ansehen".
 */
export function isTransientFocus(): boolean {
  return transientFocus;
}

/** Fokus setzen, ohne dass der Browser selbst scrollt. */
export function focusElement(
  node: HTMLElement,
  options: { instant?: boolean; transient?: boolean } = {},
): boolean {
  if (options.instant) instantReveal = true;
  // `focus()` löst `focus`/`focusin` synchron aus — die Markierung gilt also
  // genau für die Ereignisse dieses Aufrufs.
  transientFocus = options.transient === true;
  try {
    node.focus({ preventScroll: true });
  } finally {
    transientFocus = false;
  }
  const arrived = document.activeElement === node;
  // Stand der Fokus schon dort, kommt kein `focusin` — sichtbar machen muss
  // man trotzdem, etwa nach dem Wiederherstellen einer Scrollposition.
  if (arrived && options.instant && instantReveal) {
    instantReveal = false;
    reveal(node, true);
  }
  instantReveal = false;
  return arrived;
}

function cssEscape(value: string): string {
  return value.replace(/["\\]/g, "\\$&");
}

/**
 * Den Fokus zurückholen, wenn er verloren gegangen ist.
 *
 * Zuerst auf dasselbe Element, wenn es neu gezeichnet wurde (gleicher
 * `data-focus-key`), dann auf das Element, das der alten Stelle am nächsten
 * liegt, zuletzt auf das oberste sichtbare. Ein Neuladen der Daten verschiebt
 * den Fokus damit nicht auf eine andere Karte.
 */
export function recoverFocus(force = false): boolean {
  const current = document.activeElement;
  const scope = activeScope();
  if (!force && isUsable(current) && current !== document.body && scope.contains(current)) return false;

  const candidates = focusables(scope);
  if (candidates.length === 0) return false;

  // Ein neu gezeichnetes Element mit demselben Schlüssel ist dasselbe Element:
  // das darf gemerkt werden. Alles darunter ist ein Notbehelf.
  if (lastFocused?.key) {
    const same = scope.querySelector<HTMLElement>(`[data-focus-key="${cssEscape(lastFocused.key)}"]`);
    if (isUsable(same)) return focusElement(same);
  }

  const main = scope === document.body ? document.querySelector<HTMLElement>(".app-main") : null;
  const pool = main ? focusables(main) : candidates;
  const list = pool.length > 0 ? pool : candidates;

  if (lastFocused) {
    let nearest: HTMLElement | null = null;
    let distance = Infinity;
    for (const node of list) {
      const box = layoutBox(node);
      const d = Math.hypot(box.cx - lastFocused.cx, box.cy - lastFocused.cy);
      if (d < distance) {
        distance = d;
        nearest = node;
      }
    }
    if (nearest) return focusElement(nearest, { transient: true });
  }
  const first = firstInView(list);
  return first ? focusElement(first, { transient: true }) : false;
}

function isTextInput(node: Element | null): node is HTMLInputElement | HTMLTextAreaElement {
  if (node instanceof HTMLTextAreaElement) return true;
  if (!(node instanceof HTMLInputElement)) return false;
  return !["button", "checkbox", "radio", "range", "submit"].includes(node.type);
}

/** Darf eine Pfeiltaste ein Textfeld verlassen, oder bewegt sie den Cursor? */
function inputMayLeave(node: HTMLInputElement | HTMLTextAreaElement, dir: Direction): boolean {
  if (dir === "up" || dir === "down") return true;
  let start: number | null = null;
  let end: number | null = null;
  try {
    start = node.selectionStart;
    end = node.selectionEnd;
  } catch {
    return true;
  }
  if (start === null || end === null) return true;
  if (dir === "left") return start === 0 && end === 0;
  return start >= node.value.length;
}

let lastMove = 0;
let navigatingUntil = 0;

/** Wird gerade navigiert? Hintergrundarbeit hält sich dann zurück. */
export function navigating(): boolean {
  return performance.now() < navigatingUntil;
}

/**
 * Wie schnell eine gehaltene Taste wiederholen darf.
 *
 * Die Untergrenze ist dieselbe wie vorher. Braucht ein Schritt auf diesem
 * Gerät länger, wird die Sperre entsprechend größer: mehr Wiederholungen, als
 * das Panel zeichnen kann, sind keine schnellere Bedienung, sondern nur eine
 * längere Warteschlange.
 */
function repeatGuard(): number {
  const average = navMetrics().averageMs;
  if (!Number.isFinite(average) || average <= 0) return REPEAT_MS;
  return clamp(average * 1.6, REPEAT_MS, REPEAT_MAX_MS);
}

function onKeyDown(event: KeyboardEvent): void {
  if (event.defaultPrevented) return;
  const dir = arrowDirection(event);
  const active = document.activeElement;

  if (dir) {
    if (isTextInput(active) && !inputMayLeave(active, dir)) return;
    if (pointerMode) {
      pointerMode = false;
      document.documentElement.dataset.pointer = "off";
    }
    event.preventDefault();
    const now = performance.now();
    // Eine gehaltene Taste liefert Wiederholungen schneller, als eine
    // Scrollbewegung sichtbar wird. Gedrosselt bleibt jeder Schritt einer.
    if (event.repeat && now - lastMove < repeatGuard()) return;
    lastMove = now;
    navigatingUntil = now + NAVIGATING_MS;
    const before = navMetrics().measured;
    moveFocus(dir);
    recordMove(performance.now() - now, dir, navMetrics().measured - before);
    return;
  }

  if (isEnter(event) && active instanceof HTMLElement && active.matches(FOCUSABLE) && !isTextInput(active)) {
    event.preventDefault();
    if (event.repeat) return;
    active.click();
  }
}

function onFocusIn(event: FocusEvent): void {
  const node = event.target;
  if (!(node instanceof HTMLElement) || !node.matches(FOCUSABLE)) return;
  const group = groupOf(node);
  if (group) groupMemory.set(group, node);
  const instant = instantReveal;
  instantReveal = false;
  if (!pointerMode && !node.hasAttribute("data-no-reveal")) reveal(node, instant);
  const box = layoutBox(node);
  lastFocused = { key: node.getAttribute("data-focus-key"), cx: box.cx, cy: box.cy };
  lastFocusedNode = node;
}

let recoverScheduled = false;

function scheduleRecover(): void {
  if (recoverScheduled) return;
  recoverScheduled = true;
  window.requestAnimationFrame(() => {
    recoverScheduled = false;
    const active = document.activeElement;
    if (!active || active === document.body || !document.contains(active)) recoverFocus();
  });
}

/**
 * Hat eine Änderung am DOM das fokussierte Element verschoben, ohne dass sich
 * der Fokus bewegt hat, wird es wieder sichtbar gemacht.
 *
 * Sichtbar gemacht wird sonst nur bei `focusin`. Sortiert sich aber ein Raster
 * um, wandert die fokussierte Karte womöglich in eine andere Zeile — und
 * niemand holt sie zurück. Gemessen wird wie überall gegen das Ziel laufender
 * Bewegungen; hat sich nichts verschoben, passiert nichts. Mit Zeiger (Magic
 * Remote) wird nicht gescrollt.
 *
 * Aufgerufen wird das nur noch aus der gefilterten Beobachtung in
 * `geometry.ts` — ein eintreffendes Poster löst es nicht mehr aus.
 */
function afterLayoutChange(): void {
  const active = document.activeElement;
  if (lastFocused && (!active || active === document.body)) {
    scheduleRecover();
    return;
  }
  if (pointerMode || !lastFocused || active !== lastFocusedNode || !isUsable(active)) return;
  if (active.hasAttribute("data-no-reveal")) return;
  const box = layoutBox(active);
  if (Math.abs(box.cx - lastFocused.cx) < 1 && Math.abs(box.cy - lastFocused.cy) < 1) return;
  reveal(active);
  const settled = layoutBox(active);
  lastFocused = { key: lastFocused.key, cx: settled.cx, cy: settled.cy };
}

let installed = false;

/** Einmal beim Start. */
export function installNavigation(): void {
  if (installed) return;
  installed = true;
  refreshMetrics();
  window.addEventListener("resize", () => {
    refreshMetrics();
    settleScroll();
  });
  // Der sparsame Modus zeichnet einen schmaleren Ring und ein kleineres
  // Wachstum. Beides steht im Stylesheet, und die Scrollrechnung liest es —
  // also muss sie nach einem Wechsel noch einmal hinsehen.
  subscribePerformance(refreshMetrics);
  window.addEventListener("keydown", onKeyDown);
  document.addEventListener("focusin", onFocusIn);
  document.addEventListener("focusout", (event) => {
    if (!event.relatedTarget) scheduleRecover();
  });
  // Ein fokussiertes Element, das aus dem Dokument genommen wird, meldet
  // in älteren Chromium-Ständen kein `focusout`. Die Beobachtung fängt das —
  // und verwirft zugleich die vermessene Geometrie.
  observeLayout(afterLayoutChange);

  // Magic Remote: ein Zeiger. Er fokussiert, worauf er zeigt, ohne zu
  // scrollen — scrollen tut dort das Rad.
  document.addEventListener("mousemove", () => {
    if (pointerMode) return;
    pointerMode = true;
    document.documentElement.dataset.pointer = "on";
  }, { passive: true });
  // webOS meldet, wenn der Zeiger der Magic Remote verschwindet — nach ein
  // paar Sekunden Ruhe oder beim Wechsel auf die Pfeiltasten. Dann gilt wieder
  // der Tastenmodus: der Fokus steht sichtbar auf dem zuletzt gezeigten
  // Element und konkurriert nicht mehr mit einem Hover, den es nicht mehr gibt.
  document.addEventListener("cursorStateChange", (event) => {
    const visible = (event as CustomEvent<{ visibility?: boolean }>).detail?.visibility;
    if (visible !== false || !pointerMode) return;
    pointerMode = false;
    document.documentElement.dataset.pointer = "off";
    const active = document.activeElement;
    if (isUsable(active) && active.matches(FOCUSABLE)) reveal(active);
    else recoverFocus(true);
  });
  document.addEventListener("mouseover", (event) => {
    if (!pointerMode) return;
    const target = event.target instanceof Element ? event.target.closest<HTMLElement>(FOCUSABLE) : null;
    if (!isUsable(target) || !activeScope().contains(target) || document.activeElement === target) return;
    target.focus({ preventScroll: true });
  });
  document.documentElement.dataset.pointer = "off";
  // Die Reihen scrollen selbst; ihr Scrollstand steckt in der Rechnung, nicht
  // in den gespeicherten Boxen. Ein Rad- oder Zeigerscroll ändert daran
  // nichts — außer am Scrollstand, und den liest `targetScroll` ohnehin frisch.
}

// ---------------------------------------------------------------------------
// Scrollstand je Ansicht

export interface ScrollSnapshot {
  top: number;
  rails: Record<string, number>;
}

export function takeScrollSnapshot(root: HTMLElement): ScrollSnapshot {
  const rails: Record<string, number> = {};
  root.querySelectorAll<HTMLElement>("[data-scroll-x][data-scroll-key]").forEach((track) => {
    rails[track.getAttribute("data-scroll-key") ?? ""] = targetScroll(track).left;
  });
  return { top: targetScroll(root).top, rails };
}

export function applyScrollSnapshot(root: HTMLElement, snapshot: ScrollSnapshot): void {
  root.querySelectorAll<HTMLElement>("[data-scroll-x][data-scroll-key]").forEach((track) => {
    const left = snapshot.rails[track.getAttribute("data-scroll-key") ?? ""];
    if (typeof left === "number") scrollContainerTo(track, { left }, true);
  });
  scrollContainerTo(root, { top: snapshot.top }, true);
}
