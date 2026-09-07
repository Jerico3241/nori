// Der Zugang zu den Katalogen — ein Ort, an dem die App weiß, wie sie an
// Daten kommt.
//
// Der Katalog beider Quellen wird einmal geholt und dann geteilt: Startseite,
// Explore und Suche arbeiten auf denselben Listen, statt jede für sich
// nachzuladen. Das ist auf einem Fernseher kein Feinschliff — jede zusätzliche
// Katalogseite sind hunderte Kilobyte HTML, die geparst werden wollen.

import {
  scopeIncludesItem, type CalendarPayload, type CatalogItem, type CatalogProvider,
  type NoriGateway, type SeriesDetail, type WatchInfo,
} from "@nori/core";
import {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode,
} from "react";
import { createGateway } from "../services/gateway";
import { covers } from "../services/covers";
import { log } from "../services/log";
import { useLibrary } from "./library";
import { useSettings } from "./settings";

interface CatalogSlice {
  items: CatalogItem[];
  status: "idle" | "loading" | "ready" | "error";
  error: string | null;
}

interface DataContextValue {
  gateway: NoriGateway;
  /** Katalog einer Quelle; stößt das Laden an, wenn er noch nicht da ist. */
  catalog(provider: CatalogProvider): CatalogSlice;
  /** Beide Kataloge, gefiltert nach dem eingestellten Bereich. */
  scopedCatalog(): CatalogSlice;
  reloadCatalog(provider: CatalogProvider): void;
  series(provider: CatalogProvider, slug: string, season?: string | null): Promise<SeriesDetail>;
  watch(provider: CatalogProvider, path: string): Promise<WatchInfo>;
  calendar(provider: CatalogProvider, force?: boolean): Promise<CalendarPayload>;
  online: boolean;
}

const DataContext = createContext<DataContextValue | null>(null);

const EMPTY: CatalogSlice = { items: [], status: "idle", error: null };

export function DataProvider({ children }: { children: ReactNode }) {
  const { settings } = useSettings();
  const { state: library } = useLibrary();
  const gateway = useMemo(
    () => createGateway({ mode: settings.transport, serverUrl: settings.serverUrl }),
    [settings.transport, settings.serverUrl],
  );
  const [slices, setSlices] = useState<Record<string, CatalogSlice>>({});
  const [online, setOnline] = useState(() => navigator.onLine !== false);
  const pending = useRef(new Set<string>());

  useEffect(() => {
    covers.configure(gateway, settings.tmdbKey);
  }, [gateway, settings.tmdbKey]);

  // Ein Wechsel des Zugangs macht alle geladenen Listen ungültig.
  useEffect(() => {
    setSlices({});
    pending.current.clear();
  }, [gateway]);

  useEffect(() => {
    const up = () => setOnline(true);
    const down = () => setOnline(false);
    window.addEventListener("online", up);
    window.addEventListener("offline", down);
    return () => {
      window.removeEventListener("online", up);
      window.removeEventListener("offline", down);
    };
  }, []);

  const load = useCallback((provider: CatalogProvider, force: boolean) => {
    if (pending.current.has(provider) && !force) return;
    pending.current.add(provider);
    setSlices((current) => ({
      ...current,
      [provider]: { items: current[provider]?.items ?? [], status: "loading", error: null },
    }));
    gateway.catalog(provider, force).then(
      (result) => {
        log("data", "Katalog geladen", provider, result.items.length);
        setSlices((current) => ({
          ...current,
          [provider]: { items: result.items, status: "ready", error: null },
        }));
        pending.current.delete(provider);
      },
      (cause: unknown) => {
        setSlices((current) => ({
          ...current,
          [provider]: {
            items: current[provider]?.items ?? [],
            status: "error",
            error: (cause as Error)?.message ?? "Katalog nicht ladbar",
          },
        }));
        pending.current.delete(provider);
      },
    );
  }, [gateway]);

  const catalog = useCallback((provider: CatalogProvider): CatalogSlice => {
    const slice = slices[provider];
    if (!slice) {
      // Erst nach dem Rendern anstoßen: währenddessen den Zustand zu setzen
      // wäre ein Rendern im Rendern.
      queueMicrotask(() => load(provider, false));
      return { ...EMPTY, status: "loading" };
    }
    return slice;
  }, [slices, load]);

  const scopedCatalog = useCallback((): CatalogSlice => {
    const wanted: CatalogProvider[] = library.scope === "all"
      ? ["aniworld", "serienstream"]
      : library.scope === "aniworld"
        ? ["aniworld"]
        : ["serienstream"];
    const parts = wanted.map((provider) => catalog(provider));
    const items = parts.flatMap((part) => part.items)
      .filter((item) => scopeIncludesItem(library.scope, item));
    const error = parts.find((part) => part.status === "error")?.error ?? null;
    const status: CatalogSlice["status"] = items.length > 0
      ? "ready"
      : parts.some((part) => part.status === "loading")
        ? "loading"
        : error
          ? "error"
          : "idle";
    return { items, status, error };
  }, [catalog, library.scope]);

  const value = useMemo<DataContextValue>(() => ({
    gateway,
    catalog,
    scopedCatalog,
    reloadCatalog: (provider) => load(provider, true),
    series: (provider, slug, season) => gateway.series(provider, slug, season),
    watch: (provider, path) => gateway.watch(provider, path),
    calendar: (provider, force) => gateway.calendar(provider, force),
    online,
  }), [gateway, catalog, scopedCatalog, load, online]);

  return <DataContext.Provider value={value}>{children}</DataContext.Provider>;
}

export function useData(): DataContextValue {
  const ctx = useContext(DataContext);
  if (!ctx) throw new Error("useData außerhalb von DataProvider");
  return ctx;
}
