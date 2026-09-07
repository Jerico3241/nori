// Die fokussierbaren Bausteine.
//
// `SpotButton` ist der einzige fokussierbare Grundtyp der App — alles, was die
// Fernbedienung erreichen kann, ist einer. Das hält den Fokuszustand
// einheitlich (Ring, Skalierung, Beschriftung) und verhindert die zwei
// häufigsten TV-Fehler: ein sichtbares Element, das der Fokus nicht erreicht,
// und ein fokussiertes Element, das man nicht sieht.

import SpottableHOC from "@enact/spotlight/Spottable";
import { Spotlight } from "./spotlight";
import SpotlightContainerDecorator from "@enact/spotlight/SpotlightContainerDecorator";
import {
  forwardRef, useCallback, useEffect, useRef,
  type ButtonHTMLAttributes, type HTMLAttributes, type ReactNode,
} from "react";
import { rememberFocus } from "./focusMemory";

type SpottableButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  spotlightDisabled?: boolean;
  ref?: React.Ref<HTMLButtonElement>;
};

// Der HOC von Enact reicht `ref` durch, sagt es in seinen Typen aber nicht.
const SpottableButton = SpottableHOC("button") as unknown as
  React.ComponentType<SpottableButtonProps>;

const SpotlightDiv = SpotlightContainerDecorator(
  { enterTo: "last-focused", preserveId: true },
  "div",
) as unknown as React.ComponentType<
  HTMLAttributes<HTMLDivElement> & { spotlightId?: string; spotlightDisabled?: boolean; spotlightRestrict?: string }
>;

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
  /** Eindeutig innerhalb des Bereichs — darüber findet ihn `restoreFocus`. */
  focusKey?: string;
  children?: ReactNode;
}

/**
 * Ein fokussierbarer Knopf, der sich beim Fokussieren selbst merkt und sich
 * in den sichtbaren Bereich scrollt.
 */
export const SpotButton = forwardRef<HTMLButtonElement, SpotButtonProps>(function SpotButton(
  { focusRoute, focusArea, focusKey, onFocus, className, children, ...rest },
  ref,
) {
  const handleFocus = useCallback(
    (event: React.FocusEvent<HTMLButtonElement>) => {
      if (focusRoute && focusArea && focusKey) rememberFocus(focusRoute, focusArea, focusKey);
      scrollFocusIntoView(event.currentTarget);
      onFocus?.(event);
    },
    [focusRoute, focusArea, focusKey, onFocus],
  );

  return (
    <SpottableButton
      {...rest}
      ref={ref}
      type="button"
      data-focus-key={focusKey}
      className={className}
      onFocus={handleFocus}
    >
      {children}
    </SpottableButton>
  );
});

export interface SpotAreaProps extends HTMLAttributes<HTMLDivElement> {
  spotlightId?: string;
  /** `self-only` sperrt den Fokus im Bereich ein — für Drawer und Modale. */
  restrict?: "self-first" | "self-only" | "none";
  children?: ReactNode;
}

/** Ein Spotlight-Container: merkt sich intern das zuletzt fokussierte Kind. */
export function SpotArea({ restrict = "self-first", children, ...rest }: SpotAreaProps) {
  return (
    <SpotlightDiv {...rest} spotlightRestrict={restrict}>
      {children}
    </SpotlightDiv>
  );
}

/**
 * Fokus beim Einhängen in diesen Bereich setzen — für Drawer, Modale und den
 * Player, wo der Fokus nicht dort bleiben darf, wo er vorher war.
 */
export function useAutoFocus(active: boolean, selector = ".spottable"): React.RefObject<HTMLDivElement> {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!active) return;
    let cancelled = false;
    const tick = (left: number) => {
      if (cancelled || !ref.current) return;
      const target = ref.current.querySelector<HTMLElement>(selector);
      if (target) {
        Spotlight.focus(target);
        return;
      }
      if (left > 0) window.setTimeout(() => tick(left - 1), 50);
    };
    window.setTimeout(() => tick(10), 0);
    return () => {
      cancelled = true;
    };
  }, [active, selector]);
  return ref;
}

/**
 * Das fokussierte Element sichtbar machen — ohne die Seite zu verschieben.
 *
 * `scrollIntoView({ inline: "center" })` klingt richtig und ist es fast nie:
 * es sucht sich den nächsten scrollbaren Vorfahren in der Querachse, und das
 * war bei den Einstellungen die Seite selbst. Ein Knopf am rechten Rand einer
 * Reihe hat dort die ganze Seite zur Seite geschoben — sichtbar blieb nichts.
 *
 * Deshalb hier von Hand: waagerecht wird nur eine Leiste bewegt, die
 * tatsächlich eine ist, und senkrecht bleibt es bei `nearest`.
 */
function scrollFocusIntoView(node: HTMLElement): void {
  const track = horizontalTrack(node);
  if (track) {
    const nodeBox = node.getBoundingClientRect();
    const trackBox = track.getBoundingClientRect();
    const centre = nodeBox.left - trackBox.left + track.scrollLeft - (trackBox.width - nodeBox.width) / 2;
    const target = Math.max(0, Math.min(centre, track.scrollWidth - track.clientWidth));
    if (Math.abs(target - track.scrollLeft) > 1) {
      track.scrollTo({ left: target, behavior: "smooth" });
    }
  }
  node.scrollIntoView({ block: "nearest", inline: "nearest" });
}

/** Der nächste Vorfahr, der wirklich waagerecht scrollt. */
function horizontalTrack(node: HTMLElement): HTMLElement | null {
  let current: HTMLElement | null = node.parentElement;
  while (current && current !== document.body) {
    const style = window.getComputedStyle(current);
    const scrolls = style.overflowX === "auto" || style.overflowX === "scroll";
    if (scrolls && current.scrollWidth > current.clientWidth + 1) return current;
    current = current.parentElement;
  }
  return null;
}
