// Ein Ladezustand mit den drei Enden, die eine TV-Oberfläche braucht: lädt,
// da, kaputt. Ohne den dritten bleibt bei jedem Netzfehler eine schwarze
// Fläche stehen, und der Fernseher sieht aus, als hinge er.

import { useCallback, useEffect, useRef, useState } from "react";

export type AsyncStatus = "idle" | "loading" | "ready" | "error";

export interface AsyncState<T> {
  status: AsyncStatus;
  data: T | null;
  error: string | null;
  /** Läuft ein Nachladen, während bereits Daten stehen? */
  refreshing: boolean;
  reload(force?: boolean): void;
}

export function useAsync<T>(
  task: (force: boolean) => Promise<T>,
  deps: unknown[],
  options: { enabled?: boolean } = {},
): AsyncState<T> {
  const enabled = options.enabled ?? true;
  const [status, setStatus] = useState<AsyncStatus>("idle");
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const run = useRef(0);
  const taskRef = useRef(task);
  taskRef.current = task;

  const execute = useCallback((force: boolean) => {
    const id = ++run.current;
    setError(null);
    setStatus((current) => (current === "ready" ? current : "loading"));
    setRefreshing((prev) => prev || force);
    taskRef.current(force).then(
      (value) => {
        if (run.current !== id) return;
        setData(value);
        setStatus("ready");
        setRefreshing(false);
      },
      (cause: unknown) => {
        if (run.current !== id) return;
        setError((cause as Error)?.message ?? "Unbekannter Fehler");
        setStatus("error");
        setRefreshing(false);
      },
    );
  }, []);

  useEffect(() => {
    if (!enabled) return;
    execute(false);
    return () => {
      // Ein laufender Abruf darf einen später gerenderten Zustand nicht
      // überschreiben — die Kennung oben sorgt dafür.
      run.current += 1;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, ...deps]);

  const reload = useCallback((force = true) => execute(force), [execute]);

  return { status, data, error, refreshing, reload };
}
