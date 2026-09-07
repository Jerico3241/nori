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
      Spotlight.focus(node);
      return true;
    }
  }
  const first = document.querySelector<HTMLElement>(".spottable");
  if (first && isVisible(first)) {
    Spotlight.focus(first);
    return true;
  }
  return false;
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
  const current = Spotlight.getCurrent();
  if (current && document.contains(current) && isVisible(current)) return;
  const candidates = Array.from(document.querySelectorAll<HTMLElement>(".spottable"));
  const target = candidates.find(isVisible);
  if (target) {
    log("focus", "Notfokus gesetzt");
    Spotlight.focus(target);
  }
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
