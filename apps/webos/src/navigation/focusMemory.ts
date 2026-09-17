// Fokusgedächtnis.
//
// Wer auf der Startseite in „Neu & beliebt" das vierte Poster öffnet und
// zurückgeht, muss wieder auf dem vierten Poster stehen — mit derselben
// Scrollposition, nicht am Anfang der Reihe und nicht im Kopfbereich.
//
// Eine Ansicht wird beim Seitenwechsel ausgehängt; mit ihr gehen Fokus und
// Scrollstand verloren. Deshalb hält Nori beides selbst fest: je Route den
// Schlüssel (`data-focus-key`) des zuletzt fokussierten Elements und den
// Scrollstand von Seite und Reihen.

import { log } from "@nori/app";
import {
  FOCUSABLE, applyScrollSnapshot, focusElement, focusables, isUsable, recoverFocus,
  takeScrollSnapshot, type ScrollSnapshot,
} from "./engine";

/** Schlüssel: `<Route>::<Bereich>`, Wert: `data-focus-key` des Elements. */
const memory = new Map<string, string>();
/** Route → letzter Bereich, damit nicht jede Seite alle Bereiche aufzählen muss. */
const lastArea = new Map<string, string>();
const scrollMemory = new Map<string, ScrollSnapshot>();

export function rememberFocus(route: string, area: string, key: string): void {
  memory.set(`${route}::${area}`, key);
  lastArea.set(route, area);
}

export function recallFocus(route: string, area: string): string | null {
  return memory.get(`${route}::${area}`) ?? null;
}

export function forgetRoute(route: string): void {
  Array.from(memory.keys()).forEach((key) => {
    if (key.startsWith(`${route}::`)) memory.delete(key);
  });
  lastArea.delete(route);
  scrollMemory.delete(route);
}

export function saveScroll(route: string, root: HTMLElement | null): void {
  if (root) scrollMemory.set(route, takeScrollSnapshot(root));
}

function cssEscape(value: string): string {
  return value.replace(/["\\]/g, "\\$&");
}

function screenRoot(): HTMLElement | null {
  return document.querySelector<HTMLElement>(".app-main [data-scroll-y]");
}

/** Der zuletzt gemerkte Schlüssel einer Route — genau einer. */
function lastRemembered(route: string): string | null {
  const area = lastArea.get(route);
  return area ? recallFocus(route, area) : null;
}

/** Gemerkte Schlüssel der übrigen Bereiche, in der Reihenfolge der Seite. */
function otherRemembered(route: string, areas: string[]): string[] {
  const out: string[] = [];
  for (const area of areas) {
    const key = recallFocus(route, area);
    if (key && !out.includes(key)) out.push(key);
  }
  return out;
}

export interface RestoreOptions {
  /** Worauf der Fokus beim ersten Öffnen soll, etwa `[data-focus-key="hero-play"]`. */
  initial?: string;
  /** Ist der Inhalt vollständig da? Bis dahin wird auf das Gemerkte gewartet. */
  ready?: boolean;
}

/**
 * Den Fokus einer Seite setzen: das Gemerkte, sonst das Vorgesehene, sonst das
 * erste Element im Inhalt.
 *
 * Wiederholt, bis es klappt: Reihen und Bilder kommen asynchron. Solange das
 * gemerkte Element noch nicht gezeichnet ist, steht der Fokus vorläufig im
 * Inhalt — nie nirgends —, und der Versuch läuft weiter. Erst wenn der Inhalt
 * fertig ist, gibt er das Gemerkte auf.
 */
export function restoreFocusSoon(
  route: string,
  areas: string[],
  options: RestoreOptions = {},
): () => void {
  let cancelled = false;
  let attempts = 0;
  // Rund viereinhalb Sekunden: so lange darf ein Katalog über das Netz
  // brauchen, bevor der Fokus sich mit dem Erstbesten zufriedengibt.
  const maxAttempts = options.ready === true ? 24 : 60;

  const find = (main: HTMLElement | null, key: string): HTMLElement | null => {
    const node = main?.querySelector<HTMLElement>(`[data-focus-key="${cssEscape(key)}"]`) ?? null;
    return isUsable(node) ? node : null;
  };

  const tick = () => {
    if (cancelled) return;
    attempts += 1;
    const main = document.querySelector<HTMLElement>(".app-main");
    const root = screenRoot();
    const wanted = lastRemembered(route);
    const exhausted = attempts >= maxAttempts;

    // Nur der **zuletzt** gemerkte Schlüssel zählt, solange gewartet wird. Ein
    // älterer aus einem anderen Bereich (der Kopfbereich vom ersten Besuch)
    // wäre sofort da und würde das gemerkte Poster vier der Reihe darunter
    // überholen, bevor die Reihe geladen ist.
    const remembered = wanted ? find(main, wanted) : null;
    if (remembered) {
      const snapshot = scrollMemory.get(route);
      if (root && snapshot) applyScrollSnapshot(root, snapshot);
      focusElement(remembered, { instant: true });
      log("focus", "wiederhergestellt", route, wanted);
      return;
    }

    const initial = options.initial && main ? main.querySelector<HTMLElement>(options.initial) : null;

    if (!wanted || exhausted) {
      if (exhausted) {
        for (const key of otherRemembered(route, areas)) {
          const node = find(main, key);
          if (node) {
            focusElement(node, { instant: true });
            return;
          }
        }
      }
      if (isUsable(initial)) {
        focusElement(initial, { instant: true });
        return;
      }
      if (exhausted && main) {
        const first = focusables(main)[0];
        if (first) focusElement(first, { instant: true });
        return;
      }
    } else if (!isUsable(document.activeElement) && main) {
      // Vorläufig, damit die Fernbedienung nicht tot wirkt — und ausdrücklich
      // ohne gemerkt zu werden, sonst überschriebe er das Gewünschte.
      const temporary = isUsable(initial) ? initial : focusables(main)[0];
      if (temporary) focusElement(temporary, { instant: true, transient: true });
    }
    if (!exhausted) window.setTimeout(tick, 75);
  };

  window.setTimeout(tick, 0);
  return () => {
    cancelled = true;
  };
}

/** Nichts fokussiert? Dann das Naheliegende. */
export function ensureFocus(): void {
  const active = document.activeElement;
  if (isUsable(active) && active !== document.body && active.matches(FOCUSABLE)) return;
  if (active instanceof HTMLInputElement && isUsable(active)) return;
  recoverFocus();
}
