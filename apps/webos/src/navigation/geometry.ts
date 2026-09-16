// Wo die Dinge stehen — einmal gemessen, nicht bei jedem Tastendruck neu.
//
// ## Das Problem
//
// Die Navigation braucht für jeden Kandidaten eine Box. Jede Box ist ein
// `getBoundingClientRect` plus `offsetWidth`/`offsetHeight`, und jede
// Brauchbarkeitsprüfung zusätzlich ein `getComputedStyle`. Auf einer
// Startseite mit fünf Reihen sind das gemessene **299 Layoutabfragen und 86
// Stilabfragen je Pfeiltaste** — auf der CPU eines Einstiegs-Fernsehers
// zweistellige Millisekunden, bevor sich überhaupt etwas bewegt.
//
// Dabei ändert sich zwischen zwei Tastendrücken fast nie etwas an der
// Geometrie. Was sich ändert, ist die **Scrollposition** — und die ist
// bekannt, ohne den Browser zu fragen.
//
// ## Die Lösung: Inhaltskoordinaten
//
// Gespeichert wird nicht die Position auf dem Bildschirm, sondern die Position
// im Inhalt:
//
//     Inhaltsmitte = Bildschirmmitte + Scrollstand aller Scrollbereiche darüber
//
// Die ist gegen Scrollen unempfindlich. Zurückgerechnet wird gegen das **Ziel**
// laufender Bewegungen (`targetScroll`), nicht gegen deren Zwischenstand —
// damit misst ein schneller zweiter Tastendruck dieselbe Geometrie wie ein
// langsamer. Genau das leistete vorher `pendingShift`; hier fällt es als
// Sonderfall weg, weil es in der Rechnung schon steckt.
//
// ## Wann der Speicher verfällt
//
// Bei jeder Änderung am DOM, die etwas verschieben kann — und das Verwerfen
// selbst kostet nichts: es erhöht eine Zahl. Gemessen wird erst wieder, wenn
// jemand fragt.
//
// Genau eine Sorte Änderung wird ausgenommen, und zwar ausdrücklich
// angeschrieben: alles unterhalb von `data-nav-quiet`. Das sind die
// Bildflächen. Ihre Größe steht im Stylesheet (`padding-top`-Verhältnis),
// alles darin liegt absolut — ein Bild, das eintrifft, ein Platzhalter, der
// verschwindet, eine Klasse `loaded`, ein Fortschrittsbalken, der wächst:
// nichts davon verschiebt eine Kachel. Das sind zugleich die häufigsten
// Änderungen der App; vorher löste jede eine Prüfung der ganzen Seite aus,
// mitten in der Navigation.
//
// Was **nicht** ausgenommen ist: eine Unterzeile, die nach einem TMDB-Treffer
// unter einer Kachel erscheint. Die ändert die Kartenhöhe — und damit die
// Anordnung des Rasters darunter.

import { isVerbose, log } from "../services/log";
import { countCached, countInvalidation, countMeasured } from "./metrics";
import { targetScroll } from "./scroll";

export const FOCUSABLE = ".spottable";

/** Bereiche, die eine eigene Reihe bilden. Siehe `localPool` in `engine.ts`. */
export const NAV_ROW = "[data-nav-row]";

/** Flächen, deren Innenleben nichts verschieben kann. */
export const NAV_QUIET = "[data-nav-quiet]";

const SCROLLER = "[data-scroll-x],[data-scroll-y]";

export interface Box {
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
// Maße der Wurzel

let remPx = 16;
let cardScale = 1.07;
let controlScale = 1.045;
let ringRemValue = 0.75;

/**
 * Schriftgröße, Fokuswachstum und Ringbreite aus dem Stylesheet lesen.
 *
 * Diese Werte standen früher als Zahlen in der Navigation **und** in
 * `theme.css`. Zwei Zahlen, die gleich bleiben müssen, laufen auseinander;
 * seit der Leistungsmodus sie ändert, wäre das eine Frage der Zeit gewesen.
 * Jetzt gibt es nur noch die im Stylesheet, und die Scrollrechnung liest sie.
 */
export function refreshMetrics(): void {
  const style = window.getComputedStyle(document.documentElement);
  const size = Number.parseFloat(style.fontSize);
  remPx = Number.isFinite(size) && size > 0 ? size : 16;
  const card = Number.parseFloat(style.getPropertyValue("--focus-scale-card"));
  const control = Number.parseFloat(style.getPropertyValue("--focus-scale-control"));
  const ring = Number.parseFloat(style.getPropertyValue("--focus-ring-rem"));
  cardScale = Number.isFinite(card) && card >= 1 ? card : 1.07;
  controlScale = Number.isFinite(control) && control >= 1 ? control : 1.045;
  ringRemValue = Number.isFinite(ring) && ring >= 0 ? ring : 0.75;
  invalidateLayout("Maße");
}

export function rem(value: number): number {
  return value * remPx;
}

/** Ring plus Leuchten um ein fokussiertes Element, in rem. */
export function ringRem(): number {
  return ringRemValue;
}

/** Wie weit ein fokussiertes Element auf jeder Seite über seine Box ragt. */
export function focusGrowth(node: HTMLElement, box: Box): { x: number; y: number } {
  const scale = node.hasAttribute("data-focus-card") ? cardScale : controlScale;
  const ring = rem(ringRemValue);
  return {
    x: (box.width * (scale - 1)) / 2 + ring,
    y: (box.height * (scale - 1)) / 2 + ring,
  };
}

// ---------------------------------------------------------------------------
// Der Speicher

let epoch = 1;

interface Entry {
  epoch: number;
  width: number;
  height: number;
  /** Mitte in Inhaltskoordinaten — unabhängig vom Scrollstand. */
  cx: number;
  cy: number;
  scrollers: HTMLElement[];
  usable: boolean;
}

const entries = new WeakMap<HTMLElement, Entry>();
const containerEntries = new WeakMap<HTMLElement, { epoch: number; box: Box }>();
const extentEntries = new WeakMap<HTMLElement, { epoch: number; x: number; y: number }>();

export function invalidateLayout(reason?: string): void {
  epoch += 1;
  countInvalidation();
  if (reason && isVerbose()) log("nav", "Geometrie verworfen", reason);
}

export function layoutEpoch(): number {
  return epoch;
}

function scrollersOf(node: HTMLElement): HTMLElement[] {
  const out: HTMLElement[] = [];
  let parent = node.parentElement;
  while (parent) {
    if (parent.matches(SCROLLER)) out.push(parent);
    parent = parent.parentElement;
  }
  return out;
}

function shift(scrollers: HTMLElement[]): { x: number; y: number } {
  let x = 0;
  let y = 0;
  for (const scroller of scrollers) {
    const target = targetScroll(scroller);
    x += target.left;
    y += target.top;
  }
  return { x, y };
}

function isReachable(node: HTMLElement, width: number, height: number): boolean {
  if ((node as HTMLButtonElement).disabled) return false;
  if (node.getAttribute("data-nav-disabled") === "true") return false;
  if (width === 0 && height === 0) return false;
  if (node.closest("[aria-hidden='true']")) return false;
  // `visibility: hidden` ist der einzige Fall, für den es keine billigere
  // Auskunft gibt. Er kommt genau einmal vor — die ausgeblendete Bedienung im
  // Player —, und dank des Speichers landet die Abfrage nicht mehr bei jedem
  // Tastendruck im Browser.
  return window.getComputedStyle(node).visibility !== "hidden";
}

function entryFor(node: HTMLElement): Entry {
  const known = entries.get(node);
  if (known && known.epoch === epoch) {
    countCached();
    return known;
  }
  countMeasured();
  const rect = node.getBoundingClientRect();
  const width = node.offsetWidth || rect.width;
  const height = node.offsetHeight || rect.height;
  const scrollers = scrollersOf(node);
  let x = 0;
  let y = 0;
  for (const scroller of scrollers) {
    x += scroller.scrollLeft;
    y += scroller.scrollTop;
  }
  const entry: Entry = {
    epoch,
    width,
    height,
    cx: rect.left + rect.width / 2 + x,
    cy: rect.top + rect.height / 2 + y,
    scrollers,
    usable: isReachable(node, width, height),
  };
  entries.set(node, entry);
  return entry;
}

function boxFrom(entry: Entry): Box {
  const offset = shift(entry.scrollers);
  const cx = entry.cx - offset.x;
  const cy = entry.cy - offset.y;
  return {
    left: cx - entry.width / 2,
    right: cx + entry.width / 2,
    top: cy - entry.height / 2,
    bottom: cy + entry.height / 2,
    width: entry.width,
    height: entry.height,
    cx,
    cy,
  };
}

/**
 * Die Box eines Elements — ohne Fokuswachstum, nach allen laufenden
 * Bewegungen, aus dem Speicher, wenn sich seither nichts geändert hat.
 */
export function layoutBox(node: HTMLElement): Box {
  return boxFrom(entryFor(node));
}

/** Ob ein Element die Fernbedienung erreichen kann. Aus demselben Speicher. */
export function isUsable(node: Element | null): node is HTMLElement {
  if (!(node instanceof HTMLElement)) return false;
  return entryFor(node).usable;
}

/** Box **und** Erreichbarkeit in einem Zug — der Weg der Kandidatensuche. */
export function candidateBox(node: HTMLElement): Box | null {
  const entry = entryFor(node);
  return entry.usable ? boxFrom(entry) : null;
}

/**
 * Die Ränder eines Scrollbereichs.
 *
 * Eigener Speicher, weil ein Scrollbereich weder mitscrollt noch wächst: seine
 * Ränder sind über die gesamte Sitzung dieselben.
 */
export function containerBox(node: HTMLElement): Box {
  const known = containerEntries.get(node);
  if (known && known.epoch === epoch) {
    countCached();
    return known.box;
  }
  countMeasured();
  const rect = node.getBoundingClientRect();
  const box: Box = {
    left: rect.left,
    right: rect.right,
    top: rect.top,
    bottom: rect.bottom,
    width: rect.width,
    height: rect.height,
    cx: rect.left + rect.width / 2,
    cy: rect.top + rect.height / 2,
  };
  containerEntries.set(node, { epoch, box });
  return box;
}

/**
 * Wie weit sich ein Scrollbereich überhaupt bewegen lässt.
 *
 * `scrollHeight` und `clientHeight` sind Layoutabfragen wie jede andere, und
 * sie standen bisher am Ende jeder Sichtbarkeitsrechnung — also bei jedem
 * Tastendruck. Sie ändern sich, wenn Inhalt dazukommt; genau dann verfällt
 * auch der übrige Speicher.
 */
export function scrollExtent(container: HTMLElement): { x: number; y: number } {
  const known = extentEntries.get(container);
  if (known && known.epoch === epoch) {
    countCached();
    return known;
  }
  countMeasured();
  const extent = {
    epoch,
    x: Math.max(0, container.scrollWidth - container.clientWidth),
    y: Math.max(0, container.scrollHeight - container.clientHeight),
  };
  extentEntries.set(container, extent);
  return extent;
}

// ---------------------------------------------------------------------------
// Beobachtung

/** Kann diese Änderung etwas verschieben oder erreichbar machen? */
function matters(record: MutationRecord): boolean {
  const target = record.target instanceof Element ? record.target : null;
  return target === null || target.closest(NAV_QUIET) === null;
}

let observer: MutationObserver | null = null;
let pending = false;

/**
 * Die Beobachtung starten.
 *
 * Gebündelt über `requestAnimationFrame`: React hängt beim Aufbau einer Reihe
 * viele Knoten nacheinander ein, und die Seite soll dafür einmal verfallen,
 * nicht zwanzigmal.
 */
export function observeLayout(onChange: () => void): void {
  if (observer) return;
  observer = new MutationObserver((records) => {
    for (const record of records) {
      if (!matters(record)) continue;
      // Sofort verwerfen, nicht erst im nächsten Bild: zwischen der Änderung
      // und dem nächsten Bild kann ein Tastendruck liegen, und der darf nicht
      // mit veralteten Boxen rechnen. Verwerfen kostet eine Addition.
      invalidateLayout();
      // Die **Folge** daraus — das fokussierte Element notfalls wieder
      // sichtbar machen — ist dagegen teuer und wird gebündelt.
      if (pending) return;
      pending = true;
      window.requestAnimationFrame(() => {
        pending = false;
        onChange();
      });
      return;
    }
  });
  observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["class", "style", "aria-hidden", "data-nav-disabled", "disabled", "tabindex"],
  });
}

export function stopObservingLayout(): void {
  observer?.disconnect();
  observer = null;
}

// ---------------------------------------------------------------------------
// Kandidaten

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

/** Die Reihe, in der ein Element liegt. */
export function rowOf(node: HTMLElement): HTMLElement | null {
  return node.closest<HTMLElement>(NAV_ROW);
}

/** Das oberste, dann linkeste Element, das gerade im Bild steht. */
export function firstInView(candidates: HTMLElement[]): HTMLElement | null {
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
