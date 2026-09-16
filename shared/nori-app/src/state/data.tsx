// Der Zugang zu den Katalogen — ein Ort, an dem die App weiß, wie sie an
// Daten kommt.
//
// Der Katalog beider Quellen wird einmal geholt und dann geteilt: Startseite,
// Explore und Suche arbeiten auf denselben Listen, statt jede für sich
// nachzuladen. Das ist auf einem Fernseher kein Feinschliff — jede zusätzliche
// Katalogseite sind hunderte Kilobyte HTML, die geparst werden wollen.
//
// Hier wird außerdem entschieden, **welchen Weg TMDB nimmt**. Die Einstellung
// nennt einen Wunsch („über den Server"), erreichbar ist aber nur, was auch
// eingerichtet ist. Diese Umrechnung steht an einer Stelle, damit nicht jede
// Ansicht sie selbst anstellt — und damit die Einstellungen anzeigen können,
// was tatsächlich gilt.

import {
  scopeIncludesItem, type CalendarPayload, type CatalogItem, type CatalogProvider,
  type NoriGateway, type SeriesDetail, type WatchInfo,
} from "@nori/core";
import {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode,
} from "react";
import { createGateway, normalizeServerUrl } from "../services/gateway";
import { covers } from "../services/covers";
import { log } from "../services/log";
import { tmdb, type TmdbMode } from "../services/tmdb";
import { useLibrary } from "./library";
import { useSettings } from "./settings";

interface CatalogSlice {
  items: CatalogItem[];
  status: "idle" | "loading" | "ready" | "error";
  error: string | null;
}

/** Welcher TMDB-Weg gilt, und warum nicht der gewünschte. */
export interface TmdbRoute {
  /** Was eingestellt ist. */
  wanted: TmdbMode;
  /** Was tatsächlich benutzt wird. */
  effective: TmdbMode;
  /** Deutscher Satz für die Einstellungen; leer, wenn beides übereinstimmt. */
  note: string;
}

interface DataContextValue {
  gateway: NoriGateway;
  /** Katalog einer Quelle; stößt das Laden an, wenn er noch nicht da ist. */
  catalog(provider: CatalogProvider): CatalogSlice;
  /**
   * Beide Kataloge, gefiltert nach dem eingestellten Bereich.
   *
   * Gibt bei gleichem Stand **dasselbe Objekt** zurück, nicht ein gleiches.
   * Das ist keine Feinheit: Eine Ansicht, die daraus mit `useMemo` etwas
   * ableitet — der Katalogindex der Detailseite etwa —, rechnet sonst bei
   * jedem Rendern neu, und wenn sie dabei Zustand setzt, rendert sie endlos.
   * Genau das ist passiert: die Detailseite lief in eine Schleife, und der
   * Fernseher reagierte auf keine Taste mehr.
   */
  scopedCatalog(): CatalogSlice;
  reloadCatalog(provider: CatalogProvider): void;
  series(provider: CatalogProvider, slug: string, season?: string | null): Promise<SeriesDetail>;
  watch(provider: CatalogProvider, path: string): Promise<WatchInfo>;
  calendar(provider: CatalogProvider, force?: boolean): Promise<CalendarPayload>;
  online: boolean;
  tmdbRoute: TmdbRoute;
}

const DataContext = createContext<DataContextValue | null>(null);

const EMPTY: CatalogSlice = { items: [], status: "idle", error: null };

/**
 * Aus Wunsch und Einrichtung den tatsächlichen TMDB-Weg bestimmen.
 *
 * **TMDB ist nie unkonfiguriert.** Ohne eingetragenen Schlüssel greift der
 * mitgelieferte aus dem Kern (`BUILT_IN_TMDB_KEY`) — auf einem Fernseher gibt
 * es keine Tastatur, und eine App, die vor dem ersten Bild einen 32-stelligen
 * Schlüssel verlangt, zeigt nie ein Bild. „Aus" gibt es nur, weil jemand es
 * ausdrücklich wählt.
 *
 * Bleibt ein Fall, der eine Erklärung braucht: „über den Server", aber es ist
 * keiner eingetragen — dann fragt der Fernseher selbst, und die Einstellungen
 * sagen das, statt einen Weg zu behaupten, den es nicht gibt.
 */
export function resolveTmdbRoute(input: {
  wanted: TmdbMode;
  serverUrl: string;
  key: string;
}): TmdbRoute {
  if (input.wanted === "off") return { wanted: "off", effective: "off", note: "" };

  if (input.wanted === "server") {
    if (input.serverUrl) return { wanted: "server", effective: "server", note: "" };
    return {
      wanted: "server",
      effective: "direct",
      note: input.key.trim()
        ? "Kein Nori-Server eingetragen — dieser Fernseher fragt TMDB selbst, mit dem eigenen Schlüssel."
        : "Kein Nori-Server eingetragen — dieser Fernseher fragt TMDB selbst, mit dem mitgelieferten Schlüssel.",
    };
  }

  return { wanted: "direct", effective: "direct", note: "" };
}

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

  const serverBase = useMemo(
    () => (settings.transport === "server" ? normalizeServerUrl(settings.serverUrl) : ""),
    [settings.transport, settings.serverUrl],
  );

  /**
   * Der gewählte Weg als Zeichenkette — und nicht dasselbe wie `gateway`.
   *
   * Auf dem Fernseher wechselt mit dem Weg auch das Zugangsobjekt, auf dem
   * Schreibtisch nicht: dort ist der Zugang immer derselbe Kanal in den
   * Hauptprozess, und welchen Weg der nimmt, ist seine Sache. Geladene Listen
   * gelten trotzdem nicht mehr, wenn der Weg wechselt — also hängt alles, was
   * daran hängt, an dieser Zeichenkette und nicht am Objekt.
   */
  const route = `${settings.transport}|${serverBase}`;

  const tmdbRoute = useMemo(
    () => resolveTmdbRoute({
      wanted: settings.tmdbMode,
      serverUrl: serverBase,
      key: settings.tmdbKey,
    }),
    [settings.tmdbMode, serverBase, settings.tmdbKey],
  );

  useEffect(() => {
    tmdb.configure({
      mode: tmdbRoute.effective,
      key: settings.tmdbKey,
      serverUrl: serverBase,
    });
  }, [tmdbRoute.effective, settings.tmdbKey, serverBase]);

  useEffect(() => {
    covers.configure(gateway);
  }, [gateway]);

  // Ein Wechsel des Zugangs macht alle geladenen Listen ungültig.
  useEffect(() => {
    setSlices({});
    pending.current.clear();
  }, [route]);

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
    // `route` steht mit in der Liste, damit ein Wechsel des Weges die Listen
    // wirklich neu holt — auf dem Schreibtisch bleibt `gateway` dabei gleich.
  }, [gateway, route]);

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

  /** Welche Quellen der eingestellte Bereich braucht. */
  const wanted = useMemo<CatalogProvider[]>(
    () => (library.scope === "all"
      ? ["aniworld", "serienstream"]
      : library.scope === "aniworld"
        ? ["aniworld"]
        : ["serienstream"]),
    [library.scope],
  );

  // Das Laden anstoßen gehört in einen Effekt, nicht in die Rechnung darunter:
  // eine `useMemo`, die dabei Zustand setzt, ist ein Rendern im Rendern.
  useEffect(() => {
    for (const provider of wanted) load(provider, false);
  }, [wanted, load]);

  const scoped = useMemo<CatalogSlice>(() => {
    const parts = wanted.map((provider) => slices[provider] ?? { ...EMPTY, status: "loading" as const });
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
  }, [slices, wanted, library.scope]);

  const scopedCatalog = useCallback(() => scoped, [scoped]);

  const value = useMemo<DataContextValue>(() => ({
    gateway,
    catalog,
    scopedCatalog,
    reloadCatalog: (provider) => load(provider, true),
    series: (provider, slug, season) => gateway.series(provider, slug, season),
    watch: (provider, path) => gateway.watch(provider, path),
    calendar: (provider, force) => gateway.calendar(provider, force),
    online,
    tmdbRoute,
  }), [gateway, catalog, scopedCatalog, load, online, tmdbRoute]);

  return <DataContext.Provider value={value}>{children}</DataContext.Provider>;
}

export function useData(): DataContextValue {
  const ctx = useContext(DataContext);
  if (!ctx) throw new Error("useData außerhalb von DataProvider");
  return ctx;
}
