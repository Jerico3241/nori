// Scrollbewegungen mit bekanntem Ziel.
//
// Zwei Dinge, die eine gewöhnliche Scrollanimation nicht leistet und die die
// Fernbedienungsnavigation braucht:
//
// 1. **Das Ziel ist abfragbar.** Ein zweiter Tastendruck, der eintrifft, während
//    die Seite noch läuft, misst gegen das Ziel — nicht gegen den
//    Zwischenstand, den es einen Moment später nicht mehr gibt.
// 2. **Es gibt je Bereich höchstens eine Bewegung.** Eine laufende wird
//    umgelenkt, nie gestapelt. Bei gehaltener Pfeiltaste entsteht damit keine
//    Warteschlange aus Scrollanimationen, die noch minutenlang nachläuft.
//
// Herausgelöst aus `engine.ts`, damit `geometry.ts` das Ziel einer Bewegung
// lesen kann, ohne dass die beiden Dateien sich gegenseitig einbinden.

/** Dauer einer Scrollbewegung. Kurz, damit sie schnellen Drücken folgt. */
const SCROLL_MS = 170;
/** Dieselbe Bewegung auf schwacher Hardware: kürzer, also weniger Bilder. */
const SCROLL_MS_LEAN = 110;

interface ScrollAnimation {
  top: number;
  left: number;
  fromTop: number;
  fromLeft: number;
  start: number;
  raf: number;
}

const animations = new Map<HTMLElement, ScrollAnimation>();

/**
 * Der bekannte Scrollstand je Bereich.
 *
 * `scrollTop` und `scrollLeft` sind Layoutabfragen wie `getBoundingClientRect`:
 * Wer sie liest, nachdem etwas geschrieben wurde, zwingt den Browser zu einem
 * vollständigen Layout. Und geschrieben wird bei jedem Tastendruck — jede
 * Bewegung ist ein Schreibzugriff auf genau diese Felder. Der nächste
 * Tastendruck bezahlte deshalb bisher ein volles Layout, bevor er überhaupt
 * anfing zu rechnen.
 *
 * Dabei ist der Stand bekannt: **wir** haben ihn gesetzt. Gelesen wird er nur
 * noch an zwei Stellen, an denen das Layout ohnehin sauber ist — beim ersten
 * Mal und im `scroll`-Ereignis, das der Browser nach dem Zeichnen schickt.
 */
const positions = new WeakMap<HTMLElement, { top: number; left: number }>();

function remember(container: HTMLElement, top: number, left: number): void {
  positions.set(container, { top, left });
}

/**
 * Was der Browser selbst gescrollt hat, übernehmen.
 *
 * Das Rad der Magic Remote zum Beispiel. Im `scroll`-Ereignis ist das Layout
 * fertig; die Abfrage kostet dort nichts.
 */
document.addEventListener("scroll", (event) => {
  const container = event.target;
  if (!(container instanceof HTMLElement)) return;
  // Läuft eine eigene Bewegung, gilt deren Ziel — die Zwischenstände sind
  // genau das, wogegen diese Datei gebaut ist.
  if (animations.has(container)) return;
  remember(container, container.scrollTop, container.scrollLeft);
}, true);

export function reducedMotion(): boolean {
  if (document.documentElement.dataset.effects === "reduced") return true;
  try {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  } catch {
    return false;
  }
}

function leanMode(): boolean {
  return document.documentElement.dataset.perf === "lean";
}

/** Das Ziel einer laufenden Bewegung, sonst der bekannte Stand. */
export function targetScroll(container: HTMLElement): { top: number; left: number } {
  const running = animations.get(container);
  if (running) return { top: running.top, left: running.left };
  const known = positions.get(container);
  if (known) return known;
  const fresh = { top: container.scrollTop, left: container.scrollLeft };
  positions.set(container, fresh);
  return fresh;
}

/** Den gespeicherten Stand verwerfen — nach einem Seitenwechsel oder Resize. */
export function forgetScroll(container: HTMLElement): void {
  positions.delete(container);
}

/** Läuft gerade irgendwo eine Scrollbewegung? */
export function scrolling(): boolean {
  return animations.size > 0;
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

  const from = targetScroll(container);
  const settled = Math.abs(top - from.top) < 1 && Math.abs(left - from.left) < 1;
  if (instant || settled || reducedMotion()) {
    animations.delete(container);
    container.scrollTop = top;
    container.scrollLeft = left;
    remember(container, top, left);
    return;
  }

  // Eine laufende Bewegung wird nicht abgewartet, sondern umgelenkt: sie
  // startet am aktuellen Zwischenstand neu, mit dem neuen Ziel.
  const duration = leanMode() ? SCROLL_MS_LEAN : SCROLL_MS;
  const animation: ScrollAnimation = {
    top,
    left,
    fromTop: from.top,
    fromLeft: from.left,
    start: performance.now(),
    raf: 0,
  };
  remember(container, top, left);
  const step = (now: number) => {
    const t = Math.min(1, (now - animation.start) / duration);
    const eased = 1 - (1 - t) * (1 - t) * (1 - t);
    container.scrollTop = animation.fromTop + (animation.top - animation.fromTop) * eased;
    container.scrollLeft = animation.fromLeft + (animation.left - animation.fromLeft) * eased;
    if (t < 1) {
      animation.raf = window.requestAnimationFrame(step);
    } else {
      container.scrollTop = animation.top;
      container.scrollLeft = animation.left;
      animations.delete(container);
      remember(container, animation.top, animation.left);
    }
  };
  animation.raf = window.requestAnimationFrame(step);
  animations.set(container, animation);
}

/** Alle laufenden Bewegungen sofort ans Ziel setzen. Für den Seitenwechsel. */
export function settleScroll(): void {
  animations.forEach((animation, container) => {
    window.cancelAnimationFrame(animation.raf);
    container.scrollTop = animation.top;
    container.scrollLeft = animation.left;
    remember(container, animation.top, animation.left);
  });
  animations.clear();
}
