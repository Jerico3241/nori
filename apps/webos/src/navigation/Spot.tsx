// Die fokussierbaren Bausteine.
//
// `SpotButton` ist der einzige fokussierbare Grundtyp der App — alles, was die
// Fernbedienung erreichen kann, ist einer. Das hält den Fokuszustand
// einheitlich und verhindert die zwei häufigsten TV-Fehler: ein sichtbares
// Element, das der Fokus nicht erreicht, und ein fokussiertes Element, das man
// nicht sieht.
//
// Die Namen (`spotlightDisabled`, `restrict`) stammen aus der Zeit mit Enact
// Spotlight und sind geblieben, damit der Player unverändert bleibt. Dahinter
// steht jetzt `navigation/engine.ts`.

import {
  forwardRef, useCallback, useEffect, useLayoutEffect, useRef,
  type ButtonHTMLAttributes, type HTMLAttributes, type ReactNode,
} from "react";
import { focusElement, focusables, isTransientFocus, isUsable } from "./engine";
import { rememberFocus } from "./focusMemory";

export interface SpotButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  /**
   * Nimmt den Knopf aus der Fernbedienungsnavigation, ohne ihn zu verstecken —
   * für Bedienelemente, die gerade unsichtbar sind (ausgeblendete Player-Leiste)
   * oder ins Leere führen (keine nächste Folge).
   */
  spotlightDisabled?: boolean;
  /** Route und Bereich, unter denen der Fokus gemerkt wird. */
  focusRoute?: string;
  focusArea?: string;
  /** Eindeutig innerhalb der Route — darüber findet ihn `restoreFocus`. */
  focusKey?: string;
  /** Karten wachsen im Fokus stärker; die Scrollrechnung muss das wissen. */
  card?: boolean;
  children?: ReactNode;
}

export const SpotButton = forwardRef<HTMLButtonElement, SpotButtonProps>(function SpotButton(
  { focusRoute, focusArea, focusKey, spotlightDisabled, card, onFocus, className, children, ...rest },
  ref,
) {
  const handleFocus = useCallback(
    (event: React.FocusEvent<HTMLButtonElement>) => {
      if (focusRoute && focusArea && focusKey && !isTransientFocus()) rememberFocus(focusRoute, focusArea, focusKey);
      onFocus?.(event);
    },
    [focusRoute, focusArea, focusKey, onFocus],
  );

  return (
    <button
      {...rest}
      ref={ref}
      type="button"
      tabIndex={spotlightDisabled ? -1 : 0}
      data-focus-key={focusKey}
      data-focus-card={card ? "" : undefined}
      data-nav-disabled={spotlightDisabled ? "true" : undefined}
      className={`spottable${className ? ` ${className}` : ""}`}
      onFocus={handleFocus}
    >
      {children}
    </button>
  );
});

export interface SpotAreaProps extends HTMLAttributes<HTMLDivElement> {
  spotlightId?: string;
  /** `self-only` sperrt den Fokus im Bereich ein — für Menüs und Dialoge. */
  restrict?: "self-first" | "self-only" | "none";
  children?: ReactNode;
}

/**
 * Ein Bereich. Mit `restrict="self-only"` ein Overlay, das den Fokus
 * einsperrt und ihn beim Schließen an das Element zurückgibt, von dem aus es
 * geöffnet wurde.
 */
export function SpotArea({ restrict = "self-first", spotlightId, children, ...rest }: SpotAreaProps) {
  const trap = restrict === "self-only";
  const node = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    if (!trap) return undefined;
    const opener = document.activeElement;
    const area = node.current;
    return () => {
      // Noch **bevor** React das Overlay aus dem Dokument nimmt: diese Aufräumung
      // läuft, solange das fokussierte Element darin noch steht. Den Fokus jetzt
      // zurückzugeben heißt, dass er nie verloren geht — sonst hätte die
      // Rückholung der Navigation im selben Bild das nächstgelegene Element
      // gewählt statt des Knopfes, der das Overlay geöffnet hat.
      const openerUsable = opener instanceof HTMLElement && document.contains(opener) && isUsable(opener)
        && !(area?.contains(opener) ?? false);
      if (openerUsable && area?.contains(document.activeElement)) {
        focusElement(opener);
        return;
      }
      window.setTimeout(() => {
        const active = document.activeElement;
        const lost = !active || active === document.body || !document.contains(active);
        if (lost && openerUsable) focusElement(opener);
      }, 0);
    };
  }, [trap]);

  return (
    <div {...rest} ref={node} data-area={spotlightId} data-focus-trap={trap ? "" : undefined}>
      {children}
    </div>
  );
}

/**
 * Den Fokus in einen Bereich setzen und **nachprüfen, dass er dort ankam**.
 *
 * Wiederholt, bis `document.activeElement` tatsächlich im Bereich liegt: ein
 * Overlay, das im selben Bild erst eingehängt wird, hat beim ersten Versuch
 * manchmal noch keine Größe.
 */
export function focusWithin(
  root: HTMLElement | null,
  selector = ".spottable",
  attempts = 20,
): () => void {
  let cancelled = false;
  const tick = (left: number) => {
    if (cancelled || !root) return;
    if (root.contains(document.activeElement)) return;
    const preferred = root.querySelector<HTMLElement>(selector);
    const target = isUsable(preferred) ? preferred : focusables(root)[0];
    if (target && focusElement(target, { instant: true })) return;
    if (left > 0) window.setTimeout(() => tick(left - 1), 50);
  };
  window.setTimeout(() => tick(attempts), 0);
  return () => {
    cancelled = true;
  };
}

/** Fokus beim Einhängen in diesen Bereich setzen. */
export function useAutoFocus(active: boolean, selector = ".spottable"): React.RefObject<HTMLDivElement> {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!active) return undefined;
    return focusWithin(ref.current, selector);
  }, [active, selector]);
  return ref;
}
