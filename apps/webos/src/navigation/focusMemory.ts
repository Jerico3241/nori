// Fokusgedächtnis.
//
// Der Punkt, an dem sich eine TV-App entscheidet: Wer auf der Startseite den
// siebten Titel einer Reihe öffnet und zurückgeht, muss wieder auf dem siebten
// stehen — nicht am Anfang der Reihe.
//
// Spotlight kann das für Container („enterTo: last-focused"), verliert es aber,
// sobald der Container ausgehängt wird — und genau das passiert bei jedem
// Seitenwechsel. Deshalb hält Nori zusätzlich selbst fest, welches Element in
// welchem Bereich zuletzt den Fokus hatte, und stellt es nach dem Aufbau der
// Seite wieder her.

import { Spotlight } from "./spotlight";
import { log } from "../services/log";

/** Schlüssel: `<Routenschlüssel>::<Bereich>`, Wert: `data-focus-key` des Elements. */
const memory = new Map<string, string>();

export function rememberFocus(route: string, area: string, key: string): void {
  memory.set(`${route}::${area}`, key);
}

export function recallFocus(route: string, area: string): string | null {
  return memory.get(`${route}::${area}`) ?? null;
}

export function forgetRoute(route: string): void {
  for (const key of Array.from(memory.keys())) {
    if (key.startsWith(`${route}::`)) memory.delete(key);
  }
}

/**
 * Das gemerkte Element einer Seite fokussieren, sonst das erste.
 *
 * Gibt zurück, ob überhaupt etwas fokussiert werden konnte. Der Aufrufer
 * probiert es sonst im nächsten Bild noch einmal — Bilder und Listen kommen
 * asynchron, und ein Fokusversuch auf einen leeren Baum ginge ins Leere.
 */
export function restoreFocus(route: string, areas: string[]): boolean {
  for (const area of areas) {
    const key = recallFocus(route, area);
    if (!key) continue;
    const selector = `[data-focus-key="${cssEscape(key)}"]`;
    const node = document.querySelector<HTMLElement>(selector);
    if (node && isVisible(node)) {
      log("focus", "wiederhergestellt", route, area, key);
      return takeFocus(node);
    }
  }
  const first = firstSpottable();
  if (first) return takeFocus(first);
  return false;
}

/**
 * Fokus setzen und **nachprüfen, dass er angekommen ist**.
 *
 * `Spotlight.focus` nimmt ihn nicht immer an: Ein Container, der im selben
 * Bild neu eingehängt wurde, ist Spotlight noch nicht bekannt, und der Aufruf
 * tut dann schlicht nichts — ohne es zu sagen. Genau das trat auf, als ein
 * Katalogabruf mitten im Betrieb wegfiel: die Reihen wurden neu gezeichnet,
 * der Fokus lag danach auf `body`, und der Fernseher reagierte auf keine
 * Taste mehr.
 *
 * `element.focus()` als Rückfall ist kein Umgehen von Spotlight — es liest den
 * Fokus des Dokuments und zieht nach.
 */
function takeFocus(node: HTMLElement): boolean {
  Spotlight.focus(node);
  if (document.activeElement === node) return true;
  node.focus();
  return document.activeElement === node;
}

/**
 * Das erste sinnvoll fokussierbare Element — Inhalt vor Rahmen.
 *
 * Der Unterschied ist bei jedem Kaltstart zu sehen: Die Seitenleiste steht im
 * Dokument vor dem Inhalt, und ein `querySelector(".spottable")` fand deshalb
 * immer sie. Nori begann also mit fokussierter Seitenleiste — die klappt bei
 * Fokus auf und verdeckte den halben Kopfbereich, bevor überhaupt eine Taste
 * gedrückt war. Auf einem Fernseher ist der erste Bildschirm aber das, was man
 * am längsten ansieht.
 *
 * Deshalb zuerst im Hauptbereich suchen und nur dann im ganzen Dokument. Die
 * Seitenleiste bleibt über „links" erreichbar, sie ist nur nicht mehr der
 * Anfang.
 */
function firstSpottable(): HTMLElement | null {
  const roots: ParentNode[] = [];
  const main = document.querySelector(".app-main");
  if (main) roots.push(main);
  roots.push(document);
  for (const root of roots) {
    for (const node of Array.from(root.querySelectorAll<HTMLElement>(".spottable"))) {
      if (isVisible(node)) return node;
    }
  }
  return null;
}

/**
 * Nach dem Aufbau der Seite wiederholt versuchen, den Fokus zu setzen.
 *
 * Es darf keinen Zustand geben, in dem nichts fokussiert ist — sonst reagiert
 * die Fernbedienung scheinbar gar nicht. Deshalb wird über mehrere Bilder
 * hinweg nachgefasst, statt einmal zu raten.
 */
export function restoreFocusSoon(route: string, areas: string[], attempts = 12): () => void {
  let cancelled = false;
  let left = attempts;
  const tick = () => {
    if (cancelled) return;
    if (restoreFocus(route, areas)) return;
    left -= 1;
    if (left <= 0) return;
    window.setTimeout(tick, 60);
  };
  window.setTimeout(tick, 0);
  return () => {
    cancelled = true;
  };
}

/** Nichts fokussiert? Dann irgendetwas Sichtbares fokussieren. */
export function ensureFocus(): void {
  const current = document.activeElement;
  if (current instanceof HTMLElement
    && current !== document.body
    && document.contains(current)
    && isVisible(current)) {
    return;
  }
  const target = firstSpottable();
  if (!target) return;
  if (takeFocus(target)) log("focus", "Notfokus gesetzt");
}

function isVisible(node: HTMLElement): boolean {
  if (node.hasAttribute("disabled")) return false;
  const rect = node.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return false;
  const style = window.getComputedStyle(node);
  return style.visibility !== "hidden" && style.display !== "none" && style.opacity !== "0";
}

/** `CSS.escape` gibt es auf webOS 6 nicht durchgängig. */
function cssEscape(value: string): string {
  return value.replace(/["\\]/g, "\\$&");
}
