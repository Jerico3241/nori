import { useEffect, useState } from "react";

/**
 * Selten neu zeichnen, damit eine Zeitangabe in Worten stimmt.
 *
 * Für „vor 5 Minuten": der Text entsteht beim Rendern aus `Date.now()`, und
 * ohne neues Rendern bliebe er stehen. Die Wörter wechseln frühestens nach 45
 * Sekunden, also reicht ein Takt von einer halben Minute — und nur, solange es
 * überhaupt eine Angabe gibt.
 */
export function useTick(intervalMs: number, enabled = true): void {
  const [, setTick] = useState(0);
  useEffect(() => {
    if (!enabled) return undefined;
    const timer = window.setInterval(() => setTick((value) => value + 1), intervalMs);
    return () => window.clearInterval(timer);
  }, [intervalMs, enabled]);
}
