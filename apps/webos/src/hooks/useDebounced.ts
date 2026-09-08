import { useEffect, useState } from "react";

/**
 * Verzögerter Wert.
 *
 * Für die Suche: bei jedem Tastendruck eine Anfrage zu stellen belastet den
 * Fernseher und die Quelle gleichermaßen. 380 ms sind lang genug, um Tippen
 * zusammenzufassen, und kurz genug, dass es sich nach Live-Suche anfühlt.
 */
export function useDebounced<T>(value: T, delay = 380): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = window.setTimeout(() => setDebounced(value), delay);
    return () => window.clearTimeout(timer);
  }, [value, delay]);
  return debounced;
}
