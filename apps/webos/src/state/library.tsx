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
//
// ## Oberfläche und Ablage haben verschiedene Takte
//
// Der Zustand für die Oberfläche ändert sich sofort. In den `localStorage`
// geschrieben wird gebündelt: eine Änderung an Merkliste oder Einstellungen
// nach spätestens 400 ms, der Fortschritt während der Wiedergabe höchstens
// alle zehn Sekunden. Jeder Schreibvorgang serialisiert die ganze Bibliothek
// synchron — auf einem Fernseher genug, um Bilder zu kosten.
//
// Verloren geht dabei nichts, was zählt: Pause, Folgenende, das Verlassen des
// Players und das Wegschalten der App (`visibilitychange`, `pagehide`)
// schreiben sofort (`flush`).

import {
  continueWatching as coreContinueWatching, decodeLibrary, emptyLibrary, encodeLibrary,
  favoriteKey, findProgress, findProgressByEpisode, mergeLibrarySnapshots,
  nextPlay as coreNextPlay, recentKey,
  rememberRecent, seasonStats as coreSeasonStats, upsertProgress,
  type CatalogProvider, type Episode, type LibraryBag, type LibraryScope, type LibraryState,
  type WatchProgress,
} from "@nori/core";
import {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode,
} from "react";
import { log, warn } from "../services/log";

const STORAGE_KEY = "nori.library";

/** Bis eine gewöhnliche Änderung im Speicher steht. */
const WRITE_DELAY_MS = 400;
/** Höchstens so lange bleibt Fortschritt aus der laufenden Wiedergabe ungeschrieben. */
const PLAYBACK_WRITE_DELAY_MS = 10_000;

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
  /**
   * Einen fremden Stand **dazunehmen**, nicht ersetzen.
   *
   * Die Regel dazu steht im Kern (`mergeLibrarySnapshots`) — dieselbe, die
   * auch der Geräteabgleich benutzt. Wirft bei ungültigem JSON; der Aufrufer
   * muss das anzeigen, statt stillschweigend nichts zu tun.
   */
  importJSON(raw: string): { favorites: number; progress: number };
  /** Der Stand **jetzt**, für den Abgleich. */
  snapshot(): LibraryBag;
  /** Einen zusammengeführten Stand übernehmen. */
  applyMerged(merged: LibraryBag): void;
  /** Wird nach jeder Änderung gerufen — der Abgleich hängt daran. */
  setChangeListener(listener: ((duringPlayback: boolean) => void) | null): void;
  /** Was noch nicht im Speicher steht, jetzt schreiben. */
  flush(): void;
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

  /**
   * Der jüngste Stand, synchron.
   *
   * `state` ist der Stand des letzten Renderns. Wer unmittelbar nach einer
   * Änderung schreibt — der Player beim Verlassen: erst sichern, dann
   * `flush` —, braucht den Stand danach, nicht den davor.
   */
  const current = useRef(state);
  /** Was zuletzt im Speicher gelandet ist. Ein unveränderter Stand wird nicht erneut geschrieben. */
  const written = useRef<LibraryState | null>(null);
  const writeTimer = useRef<number | null>(null);
  const writeDue = useRef(0);

  const flush = useCallback(() => {
    if (writeTimer.current !== null) {
      window.clearTimeout(writeTimer.current);
      writeTimer.current = null;
    }
    const next = current.current;
    if (written.current === next) return;
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(encodeLibrary(next)));
      written.current = next;
    } catch (cause) {
      warn("app", "Bibliothek nicht speicherbar", cause);
    }
  }, []);

  /**
   * Das Schreiben einplanen.
   *
   * Ein früherer Termin gewinnt: eine Änderung an der Merkliste wartet nicht
   * auf den Takt der Wiedergabe. Ein späterer verschiebt einen bestehenden
   * aber nicht — sonst schöbe jeder Fortschrittstick das Schreiben immer
   * weiter hinaus, und es käme nie dazu.
   */
  const scheduleWrite = useCallback((delay: number) => {
    const due = Date.now() + delay;
    if (writeTimer.current !== null) {
      if (writeDue.current <= due) return;
      window.clearTimeout(writeTimer.current);
    }
    writeDue.current = due;
    writeTimer.current = window.setTimeout(() => {
      writeTimer.current = null;
      flush();
    }, delay);
  }, [flush]);

  const commit = useCallback((next: LibraryState, delay: number) => {
    current.current = next;
    setState(next);
    scheduleWrite(delay);
  }, [scheduleWrite]);

  // Einmal beim Start: eine frisch vergebene Gerätekennung muss in den Speicher.
  useEffect(() => {
    scheduleWrite(WRITE_DELAY_MS);
  }, [scheduleWrite]);

  // Der letzte verlässliche Moment. webOS meldet das Wegschalten der App über
  // `visibilitychange`; ob danach noch etwas läuft, entscheidet das System.
  useEffect(() => {
    const onVisibility = () => {
      if (document.visibilityState === "hidden") flush();
    };
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("pagehide", flush);
    return () => {
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("pagehide", flush);
      flush();
    };
  }, [flush]);

  // Der Abgleich hängt hier dran. Ein `ref` und kein State: das Ändern des
  // Melders soll nicht die ganze Bibliothek neu zeichnen.
  const listener = useRef<((duringPlayback: boolean) => void) | null>(null);

  const patch = useCallback((
    updater: (current: LibraryState) => LibraryState,
    options: { duringPlayback?: boolean } = {},
  ) => {
    const before = current.current;
    const updated = updater(before);
    // Nichts geändert heißt: nichts schreiben und nichts abgleichen.
    if (updated === before) return;
    const playback = options.duringPlayback === true;
    commit({ ...updated, modifiedAt: Date.now() }, playback ? PLAYBACK_WRITE_DELAY_MS : WRITE_DELAY_MS);
    // Gemeldet wird nur, *dass* sich etwas geändert hat. Wann daraus ein
    // Upload wird, entscheidet der Zeitplan der Engine — der Fortschritt wird
    // während der Wiedergabe regelmäßig geschrieben, und eine Netzanfrage je
    // Tick wäre weder Drive noch dem Fernseher zumutbar.
    listener.current?.(playback);
  }, [commit]);

  const value = useMemo<LibraryContextValue>(() => ({
    state,
    isFavorite: (slug) => state.favorites.includes(slug),
    toggleFavorite: (slug, title, provider) => patch((before) => {
      const has = before.favorites.includes(slug);
      const now = Date.now();
      const source = has ? (before.favoriteSource[slug] ?? provider) : provider;
      const favorites = has
        ? before.favorites.filter((s) => s !== slug)
        : [slug, ...before.favorites];
      const favoriteSource = { ...before.favoriteSource };
      const favoriteAddedAt = { ...before.favoriteAddedAt };
      const titles = { ...before.titles };
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
        ...before.favoriteMarks,
        [favoriteKey(slug, source)]: has
          ? { isFavorite: false, updatedAt: now }
          : { isFavorite: true, updatedAt: now, addedAt: now },
      };
      log("data", has ? "aus Merkliste" : "auf Merkliste", slug);
      return { ...before, favorites, favoriteSource, favoriteAddedAt, favoriteMarks, titles };
    }),
    favoriteProvider: (slug) => state.favoriteSource[slug] ?? state.provider,
    remember: (slug, title, provider) => patch((before) => {
      // Wer den Titel erneut öffnet, hebt sein früheres „aus dem Verlauf
      // nehmen" auf. Bliebe der Grabstein stehen, verschwände der Eintrag beim
      // nächsten Abgleich wieder.
      const recentsRemoved = { ...before.recentsRemoved };
      delete recentsRemoved[recentKey(slug, provider)];
      return {
        ...before,
        titles: { ...before.titles, [slug]: title },
        recents: rememberRecent(before.recents, slug, title, provider),
        recentsRemoved,
      };
    }),
    saveProgress: (item) => patch((before) => ({
      ...before,
      progress: upsertProgress(before.progress, item),
      titles: item.title ? { ...before.titles, [item.slug]: item.title } : before.titles,
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
    //
    // Nur, was sich tatsächlich ändert, bekommt eine Marke. Der Player setzt
    // Hoster und Sprache bei jedem Start; derselbe Wert mit frischer Marke
    // überschriebe beim nächsten Abgleich die bewusste Wahl eines anderen
    // Geräts.
    setPreference: (next) => patch((before) => {
      const changed = (Object.keys(next) as (keyof typeof next)[])
        .filter((key) => before[key] !== next[key]);
      if (changed.length === 0) return before;
      return { ...before, ...next, preferenceStamps: stamped(before.preferenceStamps, changed) };
    }),
    setScope: (scope) => patch((before) => (before.scope === scope ? before : {
      ...before, scope, preferenceStamps: stamped(before.preferenceStamps, ["scope"]),
    })),
    forgetRecent: (slug) => patch((before) => {
      const gone = before.recents.filter((item) => item.slug === slug);
      if (gone.length === 0) return before;
      const now = Date.now();
      const recentsRemoved = { ...before.recentsRemoved };
      for (const item of gone) {
        recentsRemoved[recentKey(slug, item.provider ?? before.provider)] = now;
      }
      return { ...before, recents: before.recents.filter((item) => item.slug !== slug), recentsRemoved };
    }),
    clearHistory: () => patch((before) => ({
      ...before,
      recents: [],
      historyClearedAt: Date.now(),
      // Einzelne Grabsteine sind damit erledigt — die Marke erschlägt sie alle.
      recentsRemoved: {},
    })),
    clearProgress: () => patch((before) => ({
      ...before, progress: {}, progressClearedAt: Date.now(),
    })),
    exportJSON: () => JSON.stringify(encodeLibrary(current.current), null, 2),
    importJSON: (raw) => {
      const decoded = decodeLibrary(JSON.parse(raw) as unknown);
      const before = current.current;
      // Zusammenführen und nicht ersetzen: eine eingelesene Datei von letzter
      // Woche darf den Fortschritt von heute Abend nicht löschen. Dieselbe
      // Regel wie beim Geräteabgleich, damit von Hand eingelesen und über
      // Drive abgeglichen nicht zu zwei verschiedenen Ergebnissen führen.
      const merged = decodeLibrary(mergeLibrarySnapshots(
        [encodeLibrary(before), encodeLibrary(decoded)],
        Date.now(),
      ));
      // Die eigene Kennung gehört zur Installation und nicht zu den Daten:
      // übernähme der Fernseher die des Geräts, von dem der Stand stammt,
      // schrieben beide in dieselbe Drive-Datei.
      commit({ ...merged, deviceId: before.deviceId, modifiedAt: Date.now() }, WRITE_DELAY_MS);
      log("data", "Bibliothek zusammengeführt",
        `${merged.favorites.length} gemerkt`,
        `${Object.keys(merged.progress).length} Folgen`);
      return {
        favorites: merged.favorites.length,
        progress: Object.keys(merged.progress).length,
      };
    },
    snapshot: () => encodeLibrary(current.current),
    applyMerged: (merged) => {
      const decoded = decodeLibrary(merged);
      commit({ ...decoded, deviceId: current.current.deviceId }, WRITE_DELAY_MS);
    },
    setChangeListener: (next) => { listener.current = next; },
    flush,
  }), [state, patch, commit, flush]);

  return <LibraryContext.Provider value={value}>{children}</LibraryContext.Provider>;
}

/** Die genannten Einstellungen auf „gerade geändert" setzen. */
function stamped(before: Record<string, number>, keys: string[]): Record<string, number> {
  const next = { ...before };
  const now = Date.now();
  for (const key of keys) next[key] = now;
  return next;
}

export function useLibrary(): LibraryContextValue {
  const ctx = useContext(LibraryContext);
  if (!ctx) throw new Error("useLibrary außerhalb von LibraryProvider");
  return ctx;
}
