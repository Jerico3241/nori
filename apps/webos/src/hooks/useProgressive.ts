// Nicht alles auf einmal zeichnen.
//
// ## Reihen
//
// Die Startseite hat bis zu sieben Reihen; auf den Bildschirm passen der
// Kopfbereich und eine. Alle sieben im ersten Durchgang zu zeichnen heißt: der
// Fernseher baut sechs Reihen auf, die niemand sieht, bevor er auf die erste
// Taste reagiert. Gemessen war das der größte einzelne Block beim Aufbau.
//
// Deshalb kommen sie in Schritten: die ersten sofort, der Rest in
// Leerlaufpausen. Wer sofort nach unten drückt, wartet höchstens auf einen
// Schritt — und während navigiert wird, ruht das Nachziehen ganz, damit es
// sich nicht mit der Fernbedienung um den Hauptthread streitet.
//
// ## Karten in einer Reihe
//
// Dasselbe waagerecht. Eine Reihe führt bis zu zwanzig Titel, sichtbar sind
// bei 1080p sieben bis acht. Gezeichnet werden zunächst zehn; erreicht der
// Fokus die letzten drei, kommen weitere dazu — dasselbe Verfahren, das der
// Katalog seit jeher für sein Raster benutzt.
//
// Die erreichte Breite bleibt je Reihe gemerkt, über den Seitenwechsel hinweg.
// Das ist kein Feinschliff, sondern Voraussetzung: das Fokusgedächtnis sucht
// beim Zurückkehren die Karte, auf der man stand, über ihren
// `data-focus-key`. Stünde die Reihe wieder bei zehn, wäre Karte 14 nicht da
// und der Fokus landete am Anfang.

import { useCallback, useEffect, useRef, useState } from "react";

import { navigating } from "../navigation/engine";
import { performanceProfile } from "../services/performance";
import { whenIdle } from "../services/scheduler";

/**
 * Wie viele von `total` Abschnitten gerade eingehängt sein sollen.
 *
 * Der erste Schritt steht sofort; danach wächst die Zahl in Leerlaufpausen.
 */
export function useProgressiveRows(total: number): number {
  const chunk = Math.max(1, performanceProfile().railChunk);
  const base = chunk + 1;
  /*
   * Gezählt wird das Nachgezogene, nicht die Gesamtzahl.
   *
   * Der Unterschied ist wichtig, weil die Reihen der Startseite **nachträglich
   * dazukommen**: der erste Durchgang kennt nur „Neu & beliebt", die übrigen
   * entstehen, sobald TMDB antwortet. Ein gemerkter Gesamtstand bliebe bei der
   * Zahl von damals stehen und deckelte die Seite dauerhaft.
   */
  const [extra, setExtra] = useState(0);
  const mounted = Math.min(total, base + extra);

  useEffect(() => {
    if (mounted >= total) return undefined;
    // Während die Fernbedienung arbeitet, nichts nachziehen — der nächste
    // Leerlauf kommt ohnehin gleich.
    return whenIdle(() => {
      setExtra((current) => (navigating() ? current : current + chunk));
    });
  }, [mounted, total, chunk]);

  return mounted;
}

/** Die erreichte Breite je Reihe — überlebt den Seitenwechsel. */
const railWidths = new Map<string, number>();

export interface RailWindow {
  /** Wie viele Karten gezeichnet werden. */
  count: number;
  /** Beim Fokus auf Karte `index` aufrufen. */
  reached(index: number): void;
}

/** Ein wachsendes Fenster über die Karten einer Reihe. */
export function useRailWindow(id: string, total: number): RailWindow {
  const step = Math.max(4, performanceProfile().railWindow);
  const base = Math.max(step, railWidths.get(id) ?? 0);
  // Wie oben: gemerkt wird der Zuwachs. Eine Reihe, die erst vier Titel hatte
  // und später zwanzig, darf nicht bei vier stehen bleiben.
  const [extra, setExtra] = useState(0);
  const count = Math.min(total, base + extra);
  const latest = useRef(count);
  latest.current = count;

  const reached = useCallback((index: number) => {
    // Steht die Reihe schon vollständig, ändert ein weiterer Schritt nichts —
    // außer einem Durchgang durch React, mitten im Tastendruck.
    if (latest.current >= total) return;
    if (index < latest.current - 3) return;
    /*
     * Erst im nächsten Bild verbreitern.
     *
     * Der Aufruf kommt aus dem `focus`-Ereignis, und React arbeitet solche
     * Ereignisse sofort ab: das Nachlegen von acht Karten läge damit **im**
     * Tastendruck und verlängerte genau die Reaktion, um die es hier geht.
     * Drei Karten Vorlauf bedeuten bei gehaltener Taste rund zweihundert
     * Millisekunden Luft — ein Bild später ist früh genug.
     */
    window.requestAnimationFrame(() => {
      setExtra((current) => {
        const next = current + step;
        railWidths.set(id, Math.min(total, base + next));
        return next;
      });
    });
  }, [id, total, step, base]);

  return { count, reached };
}

/** Für Tests und den Seitenwechsel: alle gemerkten Breiten vergessen. */
export function resetRailWindows(): void {
  railWidths.clear();
}
