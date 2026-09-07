// Merkliste, Verlauf, Fortschritt und die geteilten Wiedergabeeinstellungen.
//
// Der Zustand ist genau der aus `@nori/core/library` — dieselben Felder,
// dieselben Regeln, dasselbe Ablageformat wie die `library.json` der
// Apple-Apps. Abgelegt wird im `localStorage` des Fernsehers; exportieren und
// einlesen geht über die Einstellungen, damit ein Stand von Hand übernommen
// werden kann, solange es keinen Abgleichdienst gibt.

import {
  continueWatching as coreContinueWatching, decodeLibrary, emptyLibrary, encodeLibrary,
  findProgress, findProgressByEpisode, nextPlay as coreNextPlay, rememberRecent,
  seasonStats as coreSeasonStats, upsertProgress,
  type CatalogProvider, type Episode, type LibraryScope, type LibraryState, type WatchProgress,
} from "@nori/core";
import {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode,
} from "react";
import { log, warn } from "../services/log";

const STORAGE_KEY = "nori.library";

interface LibraryContextValue {
  state: LibraryState;
  isFavorite(slug: string): boolean;
  toggleFavorite(slug: string, title: string, provider: CatalogProvider): void;
  favoriteProvider(slug: string): CatalogProvider;
  remember(slug: string, title: string, provider: CatalogProvider): void;
  saveProgress(item: WatchProgress): void;
  progressFor(path: string, provider?: CatalogProvider | null): WatchProgress | null;
  progressForEpisode(
    slug: string, season: string, episode: number, path?: string, provider?: CatalogProvider | null,
  ): WatchProgress | null;
  continueWatching(): WatchProgress[];
  seasonStats(slug: string, season: string, episodes: Episode[], provider: CatalogProvider): {
    watched: number; total: number; pct: number;
  };
  nextPlay(slug: string, season: string, episodes: Episode[], provider: CatalogProvider): {
    episode: number; resumeAt: number; kind: "play" | "resume" | "next";
  };
  setPreference(patch: Partial<Pick<LibraryState,
    "langPref" | "hosterPref" | "resumeEnabled" | "autoplayNext" | "playbackSpeed" | "provider" | "scope">>): void;
  setScope(scope: LibraryScope): void;
  clearHistory(): void;
  clearProgress(): void;
  exportJSON(): string;
  importJSON(raw: string): void;
}

const LibraryContext = createContext<LibraryContextValue | null>(null);

function read(): LibraryState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return emptyLibrary();
    return decodeLibrary(JSON.parse(raw));
  } catch (cause) {
    warn("app", "Bibliothek nicht lesbar, starte leer", cause);
    return emptyLibrary();
  }
}

export function LibraryProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<LibraryState>(read);
  const writeTimer = useRef<number | null>(null);

  // Gebündelt schreiben: der Fortschritt wird während der Wiedergabe im
  // Sekundentakt aktualisiert, und jeder Schreibvorgang in den localStorage
  // ist synchron — auf einem Fernseher genug, um Bilder zu kosten.
  useEffect(() => {
    if (writeTimer.current !== null) window.clearTimeout(writeTimer.current);
    writeTimer.current = window.setTimeout(() => {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(encodeLibrary(state)));
      } catch (cause) {
        warn("app", "Bibliothek nicht speicherbar", cause);
      }
    }, 400);
    return () => {
      if (writeTimer.current !== null) window.clearTimeout(writeTimer.current);
    };
  }, [state]);

  const patch = useCallback((updater: (current: LibraryState) => LibraryState) => {
    setState((current) => ({ ...updater(current), modifiedAt: Date.now() }));
  }, []);

  const value = useMemo<LibraryContextValue>(() => ({
    state,
    isFavorite: (slug) => state.favorites.includes(slug),
    toggleFavorite: (slug, title, provider) => patch((current) => {
      const has = current.favorites.includes(slug);
      const favorites = has
        ? current.favorites.filter((s) => s !== slug)
        : [slug, ...current.favorites];
      const favoriteSource = { ...current.favoriteSource };
      const titles = { ...current.titles };
      if (has) delete favoriteSource[slug];
      else {
        favoriteSource[slug] = provider;
        titles[slug] = title;
      }
      log("data", has ? "aus Merkliste" : "auf Merkliste", slug);
      return { ...current, favorites, favoriteSource, titles };
    }),
    favoriteProvider: (slug) => state.favoriteSource[slug] ?? state.provider,
    remember: (slug, title, provider) => patch((current) => ({
      ...current,
      titles: { ...current.titles, [slug]: title },
      recents: rememberRecent(current.recents, slug, title, provider),
    })),
    saveProgress: (item) => patch((current) => ({
      ...current,
      progress: upsertProgress(current.progress, item),
      titles: item.title ? { ...current.titles, [item.slug]: item.title } : current.titles,
    })),
    progressFor: (path, provider) => findProgress(state.progress, path, provider),
    progressForEpisode: (slug, season, episode, path, provider) =>
      findProgressByEpisode(state.progress, slug, season, episode, path, provider),
    continueWatching: () => coreContinueWatching(state.progress),
    seasonStats: (slug, season, episodes, provider) =>
      coreSeasonStats(state.progress, slug, season, episodes, provider),
    nextPlay: (slug, season, episodes, provider) =>
      coreNextPlay(state.progress, slug, season, episodes, provider, state.resumeEnabled),
    setPreference: (next) => patch((current) => ({ ...current, ...next })),
    setScope: (scope) => patch((current) => ({ ...current, scope })),
    clearHistory: () => patch((current) => ({ ...current, recents: [] })),
    clearProgress: () => patch((current) => ({ ...current, progress: {} })),
    exportJSON: () => JSON.stringify(encodeLibrary(state), null, 2),
    importJSON: (raw) => {
      const decoded = decodeLibrary(JSON.parse(raw));
      setState({ ...decoded, modifiedAt: Date.now() });
    },
  }), [state, patch]);

  return <LibraryContext.Provider value={value}>{children}</LibraryContext.Provider>;
}

export function useLibrary(): LibraryContextValue {
  const ctx = useContext(LibraryContext);
  if (!ctx) throw new Error("useLibrary außerhalb von LibraryProvider");
  return ctx;
}
