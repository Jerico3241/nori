// Zustand einer Ansicht, der das Verlassen der Ansicht übersteht.
//
// Wer im Katalog „Top bewertet" wählt, das zwanzigste Poster öffnet und
// zurückgeht, muss wieder in „Top bewertet" auf dem zwanzigsten Poster stehen.
// Mit `useState` wäre der Filter beim Zurückkehren weg — und mit ihm die
// Karte, auf die der Fokus zurück soll.
//
// Nur im Arbeitsspeicher: nach einem Neustart beginnt die Ansicht frisch, wie
// man es von einem Fernseher erwartet.

import { useCallback, useState } from "react";

const store = new Map<string, unknown>();

export function usePersistentState<T>(key: string, initial: T): [T, (next: T | ((current: T) => T)) => void] {
  const [value, setValue] = useState<T>(() => (store.has(key) ? (store.get(key) as T) : initial));
  const update = useCallback((next: T | ((current: T) => T)) => {
    setValue((current) => {
      const resolved = typeof next === "function" ? (next as (current: T) => T)(current) : next;
      store.set(key, resolved);
      return resolved;
    });
  }, [key]);
  return [value, update];
}
