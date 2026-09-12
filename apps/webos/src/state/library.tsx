// Merkliste, Verlauf, Fortschritt und die geteilten Wiedergabeeinstellungen.
//
// Der Zustand ist genau der aus `@nori/core/library` — dieselben Felder,
// dieselben Regeln, dasselbe Ablageformat wie die `library.json` der
// Apple-Apps. Abgelegt wird im `localStorage` des Fernsehers.
//
// Seit Schema v6 trägt jede Änderung ihre eigene Marke: wer einen Titel von
// der Merkliste nimmt, hinterlässt einen Grabstein, und wer den Verlauf löscht,
// hinterlässt einen Zeitpunkt. Ohne das brächte das nächste Gerät mit älterem
// Stand beim Abgleich alles zurück, was gerade gelöscht wurde.

import {
  continueWatching as coreContinueWatching, decodeLibrary, emptyLibrary, encodeLibrary,
  favoriteKey, findProgress, findProgressByEpisode, nextPlay as coreNextPlay, recentKey,
  rememberRecent, seasonStats as coreSeasonStats, upsertProgress,
  type CatalogProvider, type Episode, type LibraryBag, type LibraryScope, type LibraryState,
  type WatchProgress,
} from "@nori/core";
import {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode,
} from "react";
import { log, warn } from "../services/log";

const STORAGE_KEY = "nori.library";

/**
 * Eine zufällige Kennung je Installation.
 *
 * Bewusst aus nichts abgeleitet: kein Gerätename, keine Seriennummer, keine
 * Werbekennung. Sie dient nur dazu, Dateien in Drive auseinanderzuhalten und
 * bei gleichen Zeitstempeln deterministisch zu entscheiden.
 *
 * `crypto.randomUUID` gibt es auf älteren webOS-Engines nicht; der Rückfall
 * liefert dieselbe Form aus `Math.random`. Für diesen Zweck reicht das —
 * verlangt ist Eindeutigkeit unter den eigenen Geräten, nicht Unvorhersehbarkeit.
 */
function newDeviceId(): string {
  const uuid = (globalThis.crypto as Crypto | undefined)?.randomUUID;
  if (typeof uuid === "function") return uuid.call(globalThis.crypto);
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (char) => {
    const value = (Math.random() * 16) | 0;
    return (char === "x" ? value : (value & 0x3) | 0x8).toString(16);
  });
}

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
  forgetRecent(slug: string): void;
  clearHistory(): void;
  clearProgress(): void;
  exportJSON(): string;
  importJSON(raw: string): void;
  /** Der Stand **jetzt**, für den Abgleich. */
  snapshot(): LibraryBag;
  /** Einen zusammengeführten Stand übernehmen. */
  applyMerged(merged: LibraryBag): void;
  /** Wird nach jeder Änderung gerufen — der Abgleich hängt daran. */
  setChangeListener(listener: ((duringPlayback: boolean) => void) | null): void;
}

const LibraryContext = createContext<LibraryContextValue | null>(null);

function read(): LibraryState {
  let state: LibraryState;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    state = raw ? decodeLibrary(JSON.parse(raw)) : emptyLibrary();
  } catch (cause) {
    warn("app", "Bibliothek nicht lesbar, starte leer", cause);
    state = emptyLibrary();
  }
  // Die Kennung wird beim ersten Start vergeben und danach nie wieder. Käme
  // sie bei jedem Start neu, läge in Drive für denselben Fernseher nach einer
  // Woche ein Dutzend Dateien.
  if (!state.deviceId) state = { ...state, deviceId: newDeviceId() };
  return state;
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

  // Der Abgleich hängt hier dran. Ein `ref` und kein State: das Ändern des
  // Melders soll nicht die ganze Bibliothek neu zeichnen.
  const listener = useRef<((duringPlayback: boolean) => void) | null>(null);

  const patch = useCallback((
    updater: (current: LibraryState) => LibraryState,
    options: { duringPlayback?: boolean } = {},
  ) => {
    setState((current) => ({ ...updater(current), modifiedAt: Date.now() }));
    // Gemeldet wird nur, *dass* sich etwas geändert hat. Wann daraus ein
    // Upload wird, entscheidet der Zeitplan der Engine — der Fortschritt wird
    // während der Wiedergabe im Sekundentakt geschrieben, und eine Netzanfrage
    // pro Sekunde wäre weder Drive noch dem Fernseher zumutbar.
    listener.current?.(options.duringPlayback === true);
  }, []);

  const value = useMemo<LibraryContextValue>(() => ({
    state,
    isFavorite: (slug) => state.favorites.includes(slug),
    toggleFavorite: (slug, title, provider) => patch((current) => {
      const has = current.favorites.includes(slug);
      const now = Date.now();
      const source = has ? (current.favoriteSource[slug] ?? provider) : provider;
      const favorites = has
        ? current.favorites.filter((s) => s !== slug)
        : [slug, ...current.favorites];
      const favoriteSource = { ...current.favoriteSource };
      const favoriteAddedAt = { ...current.favoriteAddedAt };
      const titles = { ...current.titles };
      if (has) {
        delete favoriteSource[slug];
        delete favoriteAddedAt[slug];
      } else {
        favoriteSource[slug] = provider;
        favoriteAddedAt[slug] = now;
        titles[slug] = title;
      }
      // Der Grabstein. Ohne ihn wäre „entfernt" nur die Abwesenheit eines
      // Eintrags, und jedes Gerät mit älterem Stand legte ihn wieder hin.
      const favoriteMarks = {
        ...current.favoriteMarks,
        [favoriteKey(slug, source)]: has
          ? { isFavorite: false, updatedAt: now }
          : { isFavorite: true, updatedAt: now, addedAt: now },
      };
      log("data", has ? "aus Merkliste" : "auf Merkliste", slug);
      return { ...current, favorites, favoriteSource, favoriteAddedAt, favoriteMarks, titles };
    }),
    favoriteProvider: (slug) => state.favoriteSource[slug] ?? state.provider,
    remember: (slug, title, provider) => patch((current) => {
      // Wer den Titel erneut öffnet, hebt sein früheres „aus dem Verlauf
      // nehmen" auf. Bliebe der Grabstein stehen, verschwände der Eintrag beim
      // nächsten Abgleich wieder.
      const recentsRemoved = { ...current.recentsRemoved };
      delete recentsRemoved[recentKey(slug, provider)];
      return {
        ...current,
        titles: { ...current.titles, [slug]: title },
        recents: rememberRecent(current.recents, slug, title, provider),
        recentsRemoved,
      };
    }),
    saveProgress: (item) => patch((current) => ({
      ...current,
      progress: upsertProgress(current.progress, item),
      titles: item.title ? { ...current.titles, [item.slug]: item.title } : current.titles,
    }), { duringPlayback: true }),
    progressFor: (path, provider) => findProgress(state.progress, path, provider),
    progressForEpisode: (slug, season, episode, path, provider) =>
      findProgressByEpisode(state.progress, slug, season, episode, path, provider),
    continueWatching: () => coreContinueWatching(state.progress),
    seasonStats: (slug, season, episodes, provider) =>
      coreSeasonStats(state.progress, slug, season, episodes, provider),
    nextPlay: (slug, season, episodes, provider) =>
      coreNextPlay(state.progress, slug, season, episodes, provider, state.resumeEnabled),
    // Je Einstellung ein eigener Zeitstempel. Ein globales `modifiedAt` reicht
    // dafür nicht: wer auf dem Mac die Sprache umstellt und hier das Autoplay,
    // verlöre sonst eine der beiden Änderungen komplett.
    setPreference: (next) => patch((current) => ({
      ...current, ...next, preferenceStamps: stamped(current.preferenceStamps, Object.keys(next)),
    })),
    setScope: (scope) => patch((current) => ({
      ...current, scope, preferenceStamps: stamped(current.preferenceStamps, ["scope"]),
    })),
    forgetRecent: (slug) => patch((current) => {
      const gone = current.recents.filter((item) => item.slug === slug);
      if (gone.length === 0) return current;
      const now = Date.now();
      const recentsRemoved = { ...current.recentsRemoved };
      for (const item of gone) {
        recentsRemoved[recentKey(slug, item.provider ?? current.provider)] = now;
      }
      return { ...current, recents: current.recents.filter((item) => item.slug !== slug), recentsRemoved };
    }),
    clearHistory: () => patch((current) => ({
      ...current,
      recents: [],
      historyClearedAt: Date.now(),
      // Einzelne Grabsteine sind damit erledigt — die Marke erschlägt sie alle.
      recentsRemoved: {},
    })),
    clearProgress: () => patch((current) => ({
      ...current, progress: {}, progressClearedAt: Date.now(),
    })),
    exportJSON: () => JSON.stringify(encodeLibrary(state), null, 2),
    importJSON: (raw) => {
      const decoded = decodeLibrary(JSON.parse(raw));
      // Die eigene Kennung gehört zur Installation und nicht zu den Daten:
      // übernähme der Fernseher die des Geräts, von dem der Stand stammt,
      // schrieben beide in dieselbe Drive-Datei.
      setState({ ...decoded, deviceId: state.deviceId, modifiedAt: Date.now() });
    },
    snapshot: () => encodeLibrary(state),
    applyMerged: (merged) => {
      const decoded = decodeLibrary(merged);
      setState({ ...decoded, deviceId: state.deviceId });
    },
    setChangeListener: (next) => { listener.current = next; },
  }), [state, patch]);

  return <LibraryContext.Provider value={value}>{children}</LibraryContext.Provider>;
}

/** Die genannten Einstellungen auf „gerade geändert" setzen. */
function stamped(current: Record<string, number>, keys: string[]): Record<string, number> {
  const next = { ...current };
  const now = Date.now();
  for (const key of keys) next[key] = now;
  return next;
}

export function useLibrary(): LibraryContextValue {
  const ctx = useContext(LibraryContext);
  if (!ctx) throw new Error("useLibrary außerhalb von LibraryProvider");
  return ctx;
}
