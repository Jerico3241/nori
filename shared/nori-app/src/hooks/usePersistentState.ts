// Zustand einer Ansicht, der das Verlassen der Ansicht übersteht.
//
// Wer im Katalog „Top bewertet" wählt, das zwanzigste Poster öffnet und
// zurückgeht, muss wieder in „Top bewertet" auf dem zwanzigsten Poster stehen.
// Mit `useState` wäre der Filter beim Zurückkehren weg — und mit ihm die
// Karte, auf die der Fokus zurück soll.
//
// Nur im Arbeitsspeicher: nach einem Neustart beginnt die Ansicht frisch, wie
// man es von einem Fernseher erwartet.
//
// ## Ein Schlüssel, ein Wert — auch über Komponenten hinweg
//
// Wer denselben Schlüssel benutzt, meint denselben Wert. Auf dem Fernseher
// fiel das nie auf: dort steht das Suchfeld **in** der Katalogseite, also gab
// es je Schlüssel genau einen Nutzer. Auf dem Schreibtisch steht es in der
// Kopfzeile und das Raster in der Seite darunter — zwei Komponenten, ein
// Schlüssel. Ohne gemeinsamen Stand schrieb die eine in die Ablage und die
// andere las sie nie: Getippt wurde, gefiltert wurde nicht.
//
// Deshalb ist die Ablage die Quelle, und wer an einem Schlüssel hängt,
// erfährt jede Änderung daran.

import { useCallback, useEffect, useRef, useState } from "react";

const store = new Map<string, unknown>();
const listeners = new Map<string, Set<(value: unknown) => void>>();

export function usePersistentState<T>(key: string, initial: T): [T, (next: T | ((current: T) => T)) => void] {
  const [value, setValue] = useState<T>(() => (store.has(key) ? (store.get(key) as T) : initial));
  // Der zuletzt gültige Wert, ohne auf das nächste Zeichnen zu warten: eine
  // Funktion als Aktualisierung muss den Stand von eben sehen, nicht den vom
  // letzten Bild.
  const latest = useRef<T>(value);
  latest.current = value;

  useEffect(() => {
    const listener = (next: unknown) => setValue(next as T);
    let set = listeners.get(key);
    if (!set) {
      set = new Set();
      listeners.set(key, set);
    }
    set.add(listener);
    // Beim Anmelden den Stand übernehmen — er kann sich geändert haben,
    // während diese Komponente nicht da war.
    if (store.has(key)) setValue(store.get(key) as T);
    return () => {
      set.delete(listener);
      if (set.size === 0) listeners.delete(key);
    };
  }, [key]);

  const update = useCallback((next: T | ((current: T) => T)) => {
    const resolved = typeof next === "function"
      ? (next as (current: T) => T)(latest.current)
      : next;
    if (store.get(key) === resolved && store.has(key)) return;
    store.set(key, resolved);
    latest.current = resolved;
    for (const listener of listeners.get(key) ?? []) listener(resolved);
  }, [key]);

  return [value, update];
}
