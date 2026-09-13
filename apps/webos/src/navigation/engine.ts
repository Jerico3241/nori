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

import { arrowDirection, isEnter } from "./keys";

export type Direction = "left" | "right" | "up" | "down";

export const FOCUSABLE = ".spottable";

/** Wie stark eine Karte im Fokus wächst — dasselbe wie `--focus-scale-card`. */
const CARD_SCALE = 1.07;
/** Wie stark ein Knopf wächst — `--focus-scale-control`. */
const CONTROL_SCALE = 1.045;
/** Ring plus Leuchten um ein fokussiertes Element, in rem. */
const RING_REM = 0.75;
/** Sicherheitsrand zum Rand eines Scrollbereichs, in rem. */
const SAFE_REM = 3.5;
/** Dauer einer Scrollbewegung. Kurz, damit sie schnellen Drücken folgt. */
const SCROLL_MS = 170;
/** Mindestabstand zwischen zwei Wiederholungen einer gehaltenen Taste. */
const REPEAT_MS = 70;

// ---------------------------------------------------------------------------
// Maße

let remPx = 16;

function refreshRem(): void {
  const size = Number.parseFloat(window.getComputedStyle(document.documentElement).fontSize);
  remPx = Number.isFinite(size) && size > 0 ? size : 16;
}

export function rem(value: number): number {
  return value * remPx;
}

export function reducedMotion(): boolean {
  if (document.documentElement.dataset.effects === "reduced") return true;
  try {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  } catch {
    return false;
  }
}

interface Box {
  left: number;
  right: number;
  top: number;
  bottom: number;
  width: number;
  height: number;
  cx: number;
  cy: number;
}

// ---------------------------------------------------------------------------
// Scrollbewegungen mit bekanntem Ziel

interface ScrollAnimation {
  top: number;
  left: number;
  fromTop: number;
  fromLeft: number;
  start: number;
  raf: number;
}

const animations = new Map<HTMLElement, ScrollAnimation>();

/** Das Ziel einer laufenden Bewegung, sonst die aktuelle Position. */
export function targetScroll(container: HTMLElement): { top: number; left: number } {
  const running = animations.get(container);
  return running
    ? { top: running.top, left: running.left }
    : { top: container.scrollTop, left: container.scrollLeft };
}

/**
 * Wie weit ein Element noch wandert, bis alle laufenden Bewegungen seiner
 * Vorfahren angekommen sind.
 */
function pendingShift(node: HTMLElement): { dx: number; dy: number } {
  let dx = 0;
  let dy = 0;
  animations.forEach((animation, container) => {
    if (container !== node && container.contains(node)) {
      dx += container.scrollLeft - animation.left;
      dy += container.scrollTop - animation.top;
    }
  });
  return { dx, dy };
}

/**
 * Die Box eines Elements **ohne** Fokuswachstum und **nach** allen laufenden
 * Bewegungen.
 *
 * Die Mitte bleibt beim Skalieren stehen; die ungestreckte Größe liefern
 * `offsetWidth`/`offsetHeight`. Damit misst ein schneller zweiter Tastendruck
 * dieselbe Geometrie wie ein langsamer.
 */
export function layoutBox(node: HTMLElement): Box {
  const rect = node.getBoundingClientRect();
  const width = node.offsetWidth || rect.width;
  const height = node.offsetHeight || rect.height;
  const { dx, dy } = pendingShift(node);
  const cx = rect.left + rect.width / 2 + dx;
  const cy = rect.top + rect.height / 2 + dy;
  return {
    left: cx - width / 2,
    right: cx + width / 2,
    top: cy - height / 2,
    bottom: cy + height / 2,
    width,
    height,
    cx,
    cy,
  };
}

export function scrollContainerTo(
  container: HTMLElement,
  target: { top?: number; left?: number },
  instant = false,
): void {
  const running = animations.get(container);
  const top = target.top ?? running?.top ?? container.scrollTop;
  const left = target.left ?? running?.left ?? container.scrollLeft;
  if (running) window.cancelAnimationFrame(running.raf);

  const settled = Math.abs(top - container.scrollTop) < 1 && Math.abs(left - container.scrollLeft) < 1;
  if (instant || settled || reducedMotion()) {
    animations.delete(container);
    container.scrollTop = top;
    container.scrollLeft = left;
    return;
  }

  // Eine laufende Bewegung wird nicht abgewartet, sondern umgelenkt: sie
  // startet am aktuellen Zwischenstand neu, mit dem neuen Ziel.
  const animation: ScrollAnimation = {
    top,
    left,
    fromTop: container.scrollTop,
    fromLeft: container.scrollLeft,
    start: performance.now(),
    raf: 0,
  };
  const step = (now: number) => {
    const t = Math.min(1, (now - animation.start) / SCROLL_MS);
    const eased = 1 - (1 - t) * (1 - t) * (1 - t);
    container.scrollTop = animation.fromTop + (animation.top - animation.fromTop) * eased;
    container.scrollLeft = animation.fromLeft + (animation.left - animation.fromLeft) * eased;
    if (t < 1) {
      animation.raf = window.requestAnimationFrame(step);
    } else {
      container.scrollTop = animation.top;
      container.scrollLeft = animation.left;
      animations.delete(container);
    }
  };
  animation.raf = window.requestAnimationFrame(step);
  animations.set(container, animation);
}

// ---------------------------------------------------------------------------
// Sichtbar machen

/** Wie weit ein fokussiertes Element auf jeder Seite über seine Box ragt. */
function focusGrowth(node: HTMLElement): { x: number; y: number } {
  const scale = node.hasAttribute("data-focus-card") ? CARD_SCALE : CONTROL_SCALE;
  const width = node.offsetWidth;
  const height = node.offsetHeight;
  const ring = rem(RING_REM);
  return {
    x: (width * (scale - 1)) / 2 + ring,
    y: (height * (scale - 1)) / 2 + ring,
  };
}

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
  const growth = focusGrowth(node);

  const track = node.parentElement?.closest<HTMLElement>("[data-scroll-x]") ?? null;
  if (track) {
    const box = layoutBox(node);
    const bounds = track.getBoundingClientRect();
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
    next = clamp(next, 0, Math.max(0, track.scrollWidth - track.clientWidth));
    if (Math.abs(next - current) >= 1) scrollContainerTo(track, { left: next }, instant);
  }

  const page = node.closest<HTMLElement>("[data-scroll-y]");
  if (!page) return;
  const box = layoutBox(node);
  const bounds = page.getBoundingClientRect();
  const safe = rem(SAFE_REM);
  const safeTop = bounds.top + safe;
  const safeBottom = bounds.bottom - safe;

  let top = box.top - growth.y;
  const bottom = box.bottom + growth.y;

  const section = node.parentElement?.closest<HTMLElement>("[data-reveal]") ?? null;
  if (section && page.contains(section) && section !== page) {
    const sectionTop = section.getBoundingClientRect().top + pendingShift(section).dy;
    if (bottom - sectionTop <= safeBottom - safeTop) top = Math.min(top, sectionTop);
  }

  const current = targetScroll(page).top;
  const maxScroll = Math.max(0, page.scrollHeight - page.clientHeight);
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

export function isUsable(node: Element | null): node is HTMLElement {
  if (!(node instanceof HTMLElement)) return false;
  if ((node as HTMLButtonElement).disabled) return false;
  if (node.getAttribute("data-nav-disabled") === "true") return false;
  if (node.offsetWidth === 0 && node.offsetHeight === 0) return false;
  if (window.getComputedStyle(node).visibility === "hidden") return false;
  if (node.closest("[aria-hidden='true']")) return false;
  return true;
}

/** Das oberste offene Overlay, sonst das ganze Dokument. */
export function activeScope(): HTMLElement {
  const traps = document.querySelectorAll<HTMLElement>("[data-focus-trap]");
  for (let index = traps.length - 1; index >= 0; index -= 1) {
    const trap = traps[index];
    if (trap.getClientRects().length > 0) return trap;
  }
  return document.body;
}

export function focusables(root: ParentNode): HTMLElement[] {
  const out: HTMLElement[] = [];
  const nodes = root.querySelectorAll<HTMLElement>(FOCUSABLE);
  for (let index = 0; index < nodes.length; index += 1) {
    if (isUsable(nodes[index])) out.push(nodes[index]);
  }
  return out;
}

function groupOf(node: HTMLElement): HTMLElement | null {
  return node.parentElement?.closest<HTMLElement>("[data-focus-group]") ?? null;
}

/** Zuletzt fokussiertes Element je Bereich. */
const groupMemory = new WeakMap<HTMLElement, HTMLElement>();

interface Candidate {
  node: HTMLElement;
  box: Box;
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
      if (dir === "right" ? box.cx <= from.cx + 1 : box.cx >= from.cx - 1) continue;
      const gap = dir === "right" ? box.left - from.right : from.left - box.right;
      if (gap < -Math.min(from.width, box.width) * 0.3) continue;
      const overlap = Math.min(from.bottom, box.bottom) - Math.max(from.top, box.top);
      if (overlap <= Math.min(from.height, box.height) * 0.2) continue;
      const value = Math.max(0, gap) + Math.abs(from.cy - box.cy) * 0.6;
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

/** Das oberste, dann linkeste Element, das gerade im Bild steht. */
function firstInView(candidates: HTMLElement[]): HTMLElement | null {
  let best: { node: HTMLElement; box: Box } | null = null;
  const height = window.innerHeight;
  for (const node of candidates) {
    const box = layoutBox(node);
    if (box.bottom < 0 || box.top > height) continue;
    if (!best || box.top < best.box.top - 4 || (Math.abs(box.top - best.box.top) <= 4 && box.left < best.box.left)) {
      best = { node, box };
    }
  }
  return best?.node ?? candidates[0] ?? null;
}

/** Welches Element beim Betreten eines Bereichs den Fokus bekommt. */
function entryFor(group: HTMLElement, pick: HTMLElement | null): HTMLElement | null {
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
  return pick ?? firstInView(focusables(group));
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
  const from = layoutBox(current);
  const pool: Candidate[] = [];
  for (const node of focusables(scope)) {
    if (node === current) continue;
    const nodeGroup = groupOf(node);
    if (lockedVertical && nodeGroup !== group) continue;
    // Die Seitenleiste betritt man nur mit „links" — nicht, weil unter dem
    // letzten Knopf einer Seite zufällig ein Eintrag der Leiste liegt.
    if (nodeGroup && nodeGroup !== group && nodeGroup.hasAttribute("data-focus-only-left") && dir !== "left") continue;
    pool.push({ node, box: layoutBox(node) });
  }
  let best = pick(from, pool, dir);

  if (!best && group) {
    const fallback = group.getAttribute(`data-focus-fallback-${dir}`);
    const target = fallback ? groupByName(scope, fallback) : null;
    if (target) best = entryFor(target, null);
  } else if (best) {
    const target = groupOf(best);
    if (target && target !== group) best = entryFor(target, best);
  }

  if (!best) return false;
  focusElement(best);
  return true;
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
    if (event.repeat && now - lastMove < REPEAT_MS) return;
    lastMove = now;
    moveFocus(dir);
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

let layoutCheckScheduled = false;

/**
 * Hat eine Änderung am DOM das fokussierte Element verschoben, ohne dass sich
 * der Fokus bewegt hat, wird es wieder sichtbar gemacht.
 *
 * Sichtbar gemacht wird sonst nur bei `focusin`. Sortiert sich aber ein Raster
 * um, wandert die fokussierte Karte womöglich in eine andere Zeile — und
 * niemand holt sie zurück. Gemessen wird wie überall gegen das Ziel laufender
 * Bewegungen (`layoutBox`); hat sich nichts verschoben, passiert nichts. Mit
 * Zeiger (Magic Remote) wird nicht gescrollt.
 */
function scheduleLayoutCheck(): void {
  if (layoutCheckScheduled) return;
  layoutCheckScheduled = true;
  window.requestAnimationFrame(() => {
    layoutCheckScheduled = false;
    const active = document.activeElement;
    if (pointerMode || !lastFocused || active !== lastFocusedNode || !isUsable(active)) return;
    if (active.hasAttribute("data-no-reveal")) return;
    const box = layoutBox(active);
    if (Math.abs(box.cx - lastFocused.cx) < 1 && Math.abs(box.cy - lastFocused.cy) < 1) return;
    reveal(active);
    const settled = layoutBox(active);
    lastFocused = { key: lastFocused.key, cx: settled.cx, cy: settled.cy };
  });
}

let installed = false;

/** Einmal beim Start. */
export function installNavigation(): void {
  if (installed) return;
  installed = true;
  refreshRem();
  window.addEventListener("resize", refreshRem);
  window.addEventListener("keydown", onKeyDown);
  document.addEventListener("focusin", onFocusIn);
  document.addEventListener("focusout", (event) => {
    if (!event.relatedTarget) scheduleRecover();
  });
  // Ein fokussiertes Element, das aus dem Dokument genommen wird, meldet
  // in älteren Chromium-Ständen kein `focusout`. Die Beobachtung fängt das.
  new MutationObserver(() => {
    const active = document.activeElement;
    if (lastFocused && (!active || active === document.body)) scheduleRecover();
    else scheduleLayoutCheck();
  }).observe(document.body, { childList: true, subtree: true });

  // Magic Remote: ein Zeiger. Er fokussiert, worauf er zeigt, ohne zu
  // scrollen — scrollen tut dort das Rad.
  document.addEventListener("mousemove", () => {
    if (pointerMode) return;
    pointerMode = true;
    document.documentElement.dataset.pointer = "on";
  }, { passive: true });
  document.addEventListener("mouseover", (event) => {
    if (!pointerMode) return;
    const target = event.target instanceof Element ? event.target.closest<HTMLElement>(FOCUSABLE) : null;
    if (!isUsable(target) || !activeScope().contains(target) || document.activeElement === target) return;
    target.focus({ preventScroll: true });
  });
  document.documentElement.dataset.pointer = "off";
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
