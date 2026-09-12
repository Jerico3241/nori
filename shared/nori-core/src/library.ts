// Merkliste, Verlauf, Fortschritt und Einstellungen — die Regeln aus
// `LibraryStore.swift`, Schema v6.
//
// Wichtig: das abgelegte JSON hat **dieselbe Form** wie
// `~/Library/Application Support/Nori/library.json` der Apple-Apps. Eine dort
// gesicherte Datei lässt sich hier einlesen und umgekehrt — das ist die
// Voraussetzung des Geräteabgleichs über Google Drive
// (docs/google-drive-sync.md). Die Konfliktregeln liegen in `sync.ts`.

import {
  type CatalogProvider, type Episode, type LibraryScope, type RecentItem, type WatchProgress,
} from "./models.js";
import {
  isEpisodeComplete, normalizeEpisodePath, progressKey, providerFromPath, resumePosition,
} from "./rules.js";
import {
  favoriteKey, LIBRARY_SYNC_FORMAT_VERSION, SYNC_PREFERENCES,
  type FavoriteMark, type SyncMeta,
} from "./sync.js";

export const LIBRARY_SCHEMA_VERSION = 6;

/** Die Ablageform. Feldnamen wie im Swift-`Bag`. */
export interface LibraryBag {
  version?: number;
  modifiedAt?: number;
  favorites: string[];
  recents: RecentItem[];
  titles: Record<string, string>;
  progress: Record<string, WatchProgress>;
  langPref?: string;
  hosterPref?: string;
  resumeEnabled?: boolean;
  /**
   * Bevorzugte Bildhöhe: „auto", „1080", „720", „480".
   *
   * Eine Höhe und keine Bitrate, weil die Oberfläche Höhen nennt und jede
   * HLS-Master-Playlist sie mitliefert. „auto" heisst: der Spieler entscheidet.
   * Erzwingen lässt sich das nur, wo der Hoster mehrere Spuren anbietet.
   */
  preferredQuality?: string;
  autoplayNext?: boolean;
  playbackSpeed?: number;
  provider?: string;
  scope?: string;
  favoriteSource?: Record<string, string>;
  /**
   * Wann ein Titel gemerkt wurde, in Millisekunden seit 1970. Neu in v5;
   * ältere Dateien tragen das Feld nicht und bekommen es beim Dekodieren aus
   * der Reihenfolge von `favorites` abgeleitet.
   */
  favoriteAddedAt?: Record<string, number>;
  /**
   * Herkunft und Änderungsmarken für den Geräteabgleich. Neu in v6; jede
   * ältere Datei kommt ohne und bekommt den Block beim Dekodieren ergänzt.
   */
  sync?: SyncMeta;
}

export interface LibraryState {
  favorites: string[];
  recents: RecentItem[];
  titles: Record<string, string>;
  progress: Record<string, WatchProgress>;
  favoriteSource: Record<string, CatalogProvider>;
  favoriteAddedAt: Record<string, number>;
  langPref: string;
  hosterPref: string;
  resumeEnabled: boolean;
  preferredQuality: string;
  autoplayNext: boolean;
  playbackSpeed: number;
  provider: CatalogProvider;
  scope: LibraryScope;
  modifiedAt: number;
  /**
   * Zufällige Kennung dieser Installation. Leer heisst „noch keine" — wer den
   * Zustand ablegt, vergibt sie (siehe `apps/webos/src/state/library.tsx`).
   * Bewusst nicht hier erzeugt: `decodeLibrary` wird auch beim Einlesen einer
   * *fremden* Datei benutzt, und deren Kennung darf die eigene nicht ersetzen.
   */
  deviceId: string;
  historyClearedAt: number;
  progressClearedAt: number;
  preferenceStamps: Record<string, number>;
  favoriteMarks: Record<string, FavoriteMark>;
  recentsRemoved: Record<string, number>;
}

export function emptyLibrary(): LibraryState {
  return {
    favorites: [],
    recents: [],
    titles: {},
    progress: {},
    favoriteSource: {},
    favoriteAddedAt: {},
    langPref: "DE",
    hosterPref: "VOE",
    resumeEnabled: true,
    preferredQuality: "auto",
    autoplayNext: true,
    playbackSpeed: 1.0,
    provider: "aniworld",
    scope: "all",
    modifiedAt: 0,
    deviceId: "",
    historyClearedAt: 0,
    progressClearedAt: 0,
    preferenceStamps: {},
    favoriteMarks: {},
    recentsRemoved: {},
  };
}

const PROVIDER_VALUES: CatalogProvider[] = ["aniworld", "serienstream"];
const SCOPE_VALUES: LibraryScope[] = ["all", "aniworld", "serienstream", "kdrama"];

export function decodeLibrary(raw: unknown): LibraryState {
  const state = emptyLibrary();
  if (!raw || typeof raw !== "object") return state;
  const bag = raw as Partial<LibraryBag>;
  state.favorites = Array.isArray(bag.favorites) ? bag.favorites.filter((s) => typeof s === "string") : [];
  state.recents = Array.isArray(bag.recents) ? bag.recents : [];
  state.titles = isRecord(bag.titles) ? (bag.titles as Record<string, string>) : {};
  state.langPref = bag.langPref ?? "DE";
  state.hosterPref = bag.hosterPref ?? "VOE";
  state.resumeEnabled = bag.resumeEnabled ?? true;
  state.preferredQuality = bag.preferredQuality ?? "auto";
  state.autoplayNext = bag.autoplayNext ?? true;
  state.playbackSpeed = bag.playbackSpeed ?? 1.0;
  if (bag.provider && (PROVIDER_VALUES as string[]).includes(bag.provider)) {
    state.provider = bag.provider as CatalogProvider;
  }
  // Ältere Stände kennen den Bereich nicht. Sie bekommen „Alle" — das ist der
  // Sinn der gemeinsamen Bibliothek, nicht ein Verlust.
  state.scope = bag.scope && (SCOPE_VALUES as string[]).includes(bag.scope)
    ? (bag.scope as LibraryScope)
    : "all";
  state.favoriteSource = {};
  if (isRecord(bag.favoriteSource)) {
    for (const [slug, value] of Object.entries(bag.favoriteSource)) {
      if (typeof value === "string" && (PROVIDER_VALUES as string[]).includes(value)) {
        state.favoriteSource[slug] = value as CatalogProvider;
      }
    }
  }
  state.favoriteAddedAt = backfillAddedAt(
    isRecord(bag.favoriteAddedAt) ? (bag.favoriteAddedAt as Record<string, number>) : {},
    state.favorites,
  );
  state.progress = migrateProgress(isRecord(bag.progress) ? (bag.progress as Record<string, WatchProgress>) : {});
  state.modifiedAt = bag.modifiedAt ?? 0;
  adoptSyncMeta(state, bag);
  return state;
}

/**
 * Die Sync-Angaben übernehmen — und ergänzen, was eine ältere Datei nicht
 * haben kann. Das ist die Migration v5 → v6.
 *
 * Sie erfindet nichts: die Merkliste wird zu lauter „gemerkt seit
 * `favoriteAddedAt`", die Einstellungen bekommen den Änderungszeitpunkt der
 * ganzen Datei. Beides ist die beste Auskunft, die in einem v5-Stand steckt.
 *
 * Die Zeitstempel der Einstellungen werden dabei **festgeschrieben**. Liesse
 * man sie leer und fiele beim Vergleich auf `modifiedAt` zurück, würde jede
 * spätere Änderung an *einer* Einstellung alle anderen mit frischmachen — wer
 * heute die Sprache umstellt, überschriebe damit den Hoster, den ein anderes
 * Gerät gestern bewusst gewählt hat.
 *
 * Dieselbe Regel wie `LibraryStore.adoptSyncMeta` im Swift-Kern.
 */
function adoptSyncMeta(state: LibraryState, bag: Partial<LibraryBag>): void {
  const meta = isRecord(bag.sync) ? (bag.sync as SyncMeta) : undefined;
  state.deviceId = typeof meta?.deviceId === "string" ? meta.deviceId : "";
  state.historyClearedAt = meta?.historyClearedAt ?? 0;
  state.progressClearedAt = meta?.progressClearedAt ?? 0;
  state.recentsRemoved = isRecord(meta?.recentsRemoved) ? { ...meta.recentsRemoved } : {};

  const stamps = isRecord(meta?.preferences) ? meta.preferences : undefined;
  if (stamps && Object.keys(stamps).length > 0) {
    state.preferenceStamps = {};
    for (const [key, stamp] of Object.entries(stamps)) {
      if (typeof stamp?.updatedAt === "number") state.preferenceStamps[key] = stamp.updatedAt;
    }
  } else {
    const anchor = state.modifiedAt;
    state.preferenceStamps = {};
    for (const key of SYNC_PREFERENCES) state.preferenceStamps[key] = anchor;
  }

  const marks = isRecord(meta?.favorites) ? meta.favorites : undefined;
  if (marks && Object.keys(marks).length > 0) {
    state.favoriteMarks = { ...marks };
  } else {
    state.favoriteMarks = {};
    for (const slug of state.favorites) {
      const provider = state.favoriteSource[slug] ?? state.provider;
      const stamp = state.favoriteAddedAt[slug] ?? state.modifiedAt;
      state.favoriteMarks[favoriteKey(slug, provider)] = {
        isFavorite: true,
        updatedAt: stamp,
        addedAt: stamp,
      };
    }
  }
}

/**
 * Fehlende Merkzeitpunkte aus der Reihenfolge ergänzen — dieselbe Regel wie
 * `LibraryStore.backfillAddedAt` im Swift-Kern.
 *
 * Vor v5 gab es das Feld nicht; in `favorites` steht das zuletzt Gemerkte
 * vorn, und genau das wird hier zu Zeitpunkten. Der Anker liegt unterhalb
 * aller bekannten Werte, damit ein abgeleiteter keinen echten überholt.
 * Zeitpunkte zu Slugs, die nicht mehr gemerkt sind, fallen weg.
 */
export function backfillAddedAt(
  stored: Record<string, number>,
  favorites: string[],
): Record<string, number> {
  const out: Record<string, number> = {};
  for (const slug of favorites) {
    const value = stored[slug];
    if (typeof value === "number" && Number.isFinite(value)) out[slug] = value;
  }
  const missing = favorites.filter((slug) => out[slug] === undefined);
  if (missing.length === 0) return out;
  const known = Object.values(out);
  const step = 60_000;
  let stamp = known.length > 0 ? Math.min(...known) : Date.now();
  for (const slug of missing) {
    stamp -= step;
    out[slug] = stamp;
  }
  return out;
}

export function encodeLibrary(state: LibraryState): LibraryBag {
  return {
    version: LIBRARY_SCHEMA_VERSION,
    modifiedAt: state.modifiedAt,
    favorites: state.favorites,
    recents: state.recents,
    titles: state.titles,
    progress: state.progress,
    langPref: state.langPref,
    hosterPref: state.hosterPref,
    resumeEnabled: state.resumeEnabled,
    preferredQuality: state.preferredQuality,
    autoplayNext: state.autoplayNext,
    playbackSpeed: state.playbackSpeed,
    provider: state.provider,
    scope: state.scope,
    favoriteSource: state.favoriteSource,
    favoriteAddedAt: state.favoriteAddedAt,
    sync: {
      formatVersion: LIBRARY_SYNC_FORMAT_VERSION,
      deviceId: state.deviceId,
      platform: "webos",
      generatedAt: state.modifiedAt,
      historyClearedAt: state.historyClearedAt,
      progressClearedAt: state.progressClearedAt,
      preferences: Object.fromEntries(
        Object.entries(state.preferenceStamps).map(([key, updatedAt]) => [key, { updatedAt }]),
      ),
      favorites: state.favoriteMarks,
      recentsRemoved: state.recentsRemoved,
    },
  };
}

/**
 * Alte Stände auf `provider|episodePath` umschlüsseln.
 *
 * Ohne das verlieren bestehende Installationen ihren Fortschritt: v1 legte
 * denselben Eintrag mehrfach ab (je Sprache, je Pfadform). Bei Dubletten
 * gewinnt der jüngste `updatedAt`.
 */
export function migrateProgress(old: Record<string, WatchProgress>): Record<string, WatchProgress> {
  const migrated: Record<string, WatchProgress> = {};
  for (const value of Object.values(old)) {
    if (!value || typeof value !== "object") continue;
    const item: WatchProgress = {
      ...value,
      episodePath: normalizeEpisodePath(value.episodePath ?? ""),
    };
    item.provider = item.provider ?? providerFromPath(item.episodePath);
    const key = progressKey(item.episodePath, item.provider);
    const existing = migrated[key];
    if (!existing || item.updatedAt > existing.updatedAt) migrated[key] = item;
  }
  return migrated;
}

export function upsertProgress(
  progress: Record<string, WatchProgress>,
  item: WatchProgress,
): Record<string, WatchProgress> {
  const path = normalizeEpisodePath(item.episodePath);
  const next: WatchProgress = { ...item, episodePath: path };
  next.provider = next.provider ?? providerFromPath(path);
  if (next.durationSec >= 20 && next.positionSec >= next.durationSec * 0.9) next.completed = true;
  const out = { ...progress };
  out[progressKey(path, next.provider)] = next;
  // Reste älterer Schlüsselformen desselben Eintrags entfernen.
  for (const [key, existing] of Object.entries(out)) {
    if (key === progressKey(path, next.provider)) continue;
    const sameEpisode = normalizeEpisodePath(existing.episodePath) === path;
    const sameProvider = (existing.provider ?? providerFromPath(existing.episodePath)) === next.provider;
    if (sameEpisode && sameProvider) delete out[key];
  }
  return out;
}

export function findProgress(
  progress: Record<string, WatchProgress>,
  path: string,
  provider?: CatalogProvider | null,
): WatchProgress | null {
  const clean = normalizeEpisodePath(path);
  if (provider) {
    const direct = progress[progressKey(clean, provider)];
    if (direct) return direct;
  }
  const bare = progress[clean];
  if (bare) return bare;
  let best: WatchProgress | null = null;
  for (const item of Object.values(progress)) {
    if (normalizeEpisodePath(item.episodePath) !== clean) continue;
    if (provider && (item.provider ?? providerFromPath(item.episodePath)) !== provider) continue;
    if (!best || item.updatedAt > best.updatedAt) best = item;
  }
  return best;
}

export function findProgressByEpisode(
  progress: Record<string, WatchProgress>,
  slug: string,
  season: string,
  episode: number,
  path?: string,
  provider?: CatalogProvider | null,
): WatchProgress | null {
  if (path) {
    const byPath = findProgress(progress, path, provider);
    if (byPath) return byPath;
  }
  let best: WatchProgress | null = null;
  for (const item of Object.values(progress)) {
    if (item.slug !== slug || item.season !== season || item.episode !== episode) continue;
    if (provider && (item.provider ?? providerFromPath(item.episodePath)) !== provider) continue;
    if (!best || item.updatedAt > best.updatedAt) best = item;
  }
  return best;
}

/** Je Serie der jüngste unfertige Eintrag, nach Zeit sortiert, höchstens 16. */
export function continueWatching(progress: Record<string, WatchProgress>): WatchProgress[] {
  const latest = new Map<string, WatchProgress>();
  for (const item of Object.values(progress)) {
    const provider = item.provider ?? providerFromPath(item.episodePath);
    const key = `${provider}|${item.slug}`;
    const current = latest.get(key);
    if (!current || item.updatedAt > current.updatedAt) latest.set(key, item);
  }
  return Array.from(latest.values())
    .filter((item) => !isEpisodeComplete(item)
      && (item.positionSec < item.durationSec * 0.96 || item.durationSec < 20))
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, 16);
}

export function seasonStats(
  progress: Record<string, WatchProgress>,
  slug: string,
  season: string,
  episodes: Episode[],
  provider: CatalogProvider,
): { watched: number; total: number; pct: number } {
  const watched = episodes.filter((ep) =>
    isEpisodeComplete(findProgressByEpisode(progress, slug, season, ep.number, ep.path, provider)),
  ).length;
  const total = episodes.length;
  return { watched, total, pct: total === 0 ? 0 : Math.round((watched / total) * 100) };
}

/** Wurde in dieser Staffel überhaupt schon etwas angeschaut? */
export function hasProgress(
  progress: Record<string, WatchProgress>,
  slug: string,
  season: string,
  provider: CatalogProvider,
): boolean {
  return Object.values(progress).some((item) =>
    item.slug === slug
    && item.season === season
    && (item.provider ?? providerFromPath(item.episodePath)) === provider
    && (item.positionSec > 0 || item.completed === true));
}

export type NextPlayKind = "play" | "resume" | "next";

export interface NextPlay {
  episode: number;
  resumeAt: number;
  kind: NextPlayKind;
}

/** Was der große Knopf auf der Detailseite tut — Regel aus dem Swift-Kern. */
export function nextPlay(
  progress: Record<string, WatchProgress>,
  slug: string,
  season: string,
  episodes: Episode[],
  provider: CatalogProvider,
  resumeEnabled: boolean,
): NextPlay {
  if (episodes.length === 0) return { episode: 1, resumeAt: 0, kind: "play" };
  const relevant = Object.values(progress).filter((item) =>
    item.slug === slug && (item.provider ?? providerFromPath(item.episodePath)) === provider);
  const latest = relevant.reduce<WatchProgress | null>(
    (acc, item) => (!acc || item.updatedAt > acc.updatedAt ? item : acc), null);
  if (latest && latest.season === season && !isEpisodeComplete(latest)
    && episodes.some((ep) => ep.number === latest.episode)) {
    const at = resumeEnabled ? resumePosition(latest) : 0;
    return { episode: latest.episode, resumeAt: at, kind: at >= 8 ? "resume" : "play" };
  }
  const started = hasProgress(progress, slug, season, provider);
  const sorted = [...episodes].sort((a, b) => a.number - b.number);
  for (const ep of sorted) {
    const item = findProgressByEpisode(progress, slug, season, ep.number, ep.path, provider);
    if (!isEpisodeComplete(item)) {
      const at = resumeEnabled ? resumePosition(item) : 0;
      if (at >= 8) return { episode: ep.number, resumeAt: at, kind: "resume" };
      return { episode: ep.number, resumeAt: at, kind: started ? "next" : "play" };
    }
  }
  return { episode: sorted[0].number, resumeAt: 0, kind: "play" };
}

export function nextEpisode(current: Episode, episodes: Episode[]): Episode | null {
  const sorted = [...episodes].sort((a, b) => a.number - b.number);
  const index = sorted.findIndex((ep) => ep.number === current.number);
  if (index < 0) return null;
  return sorted[index + 1] ?? null;
}

export function previousEpisode(current: Episode, episodes: Episode[]): Episode | null {
  const sorted = [...episodes].sort((a, b) => a.number - b.number);
  const index = sorted.findIndex((ep) => ep.number === current.number);
  if (index <= 0) return null;
  return sorted[index - 1] ?? null;
}

export function rememberRecent(
  recents: RecentItem[],
  slug: string,
  title: string,
  provider: CatalogProvider,
): RecentItem[] {
  const next = recents.filter((item) => item.slug !== slug);
  next.unshift({ slug, title, viewedAt: Date.now(), provider });
  return next.slice(0, 100);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
