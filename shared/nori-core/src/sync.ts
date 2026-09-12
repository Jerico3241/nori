// Der Geräteabgleich — Ablageform, Konfliktregeln, Zusammenführung.
//
// Zeile für Zeile dieselben Regeln wie `native/NoriCore/Sources/NoriCore/
// LibrarySync.swift`. Das ist kein Zufall und keine Bequemlichkeit: laufen die
// beiden auseinander, entscheidet der Fernseher anders als das iPhone, beide
// schreiben ihr Ergebnis zurück, und die Bibliothek pendelt zwischen zwei
// Ständen. Deshalb laufen beide Fassungen gegen dieselben Fälle —
// `test/sync-fixtures.ts` und `Tests/NoriCoreTests/SyncFixtures.swift`.
//
// Hier steht keine Netzwerklogik und kein OAuth. Nur Rechnung: aus mehreren
// Ständen wird einer.

import type { CatalogProvider, RecentItem, WatchProgress } from "./models.js";
import { normalizeEpisodePath, progressKey, providerFromPath } from "./rules.js";
import { LIBRARY_SCHEMA_VERSION, type LibraryBag } from "./library.js";

/** Version der Sync-Metadaten innerhalb einer Bibliotheksdatei. */
export const LIBRARY_SYNC_FORMAT_VERSION = 1;

/**
 * Schutzgrenzen. Keine davon soll im Alltag greifen — sie halten kaputte oder
 * böswillige Fremddateien davon ab, den lokalen Stand zu beschädigen.
 */
export const LIBRARY_SYNC_LIMITS = {
  /** Eine normale Bibliothek liegt im zweistelligen Kilobyte-Bereich. */
  maxSnapshotBytes: 2 * 1024 * 1024,
  maxFavorites: 5_000,
  /** Wie im Store: der Verlauf bleibt bei 100 Einträgen. */
  maxRecents: 100,
  maxProgress: 20_000,
  maxTitles: 50_000,
  /** Wie weit ein Zeitstempel in der Zukunft liegen darf: 24 Stunden. */
  futureToleranceMs: 24 * 60 * 60 * 1000,
} as const;

/** Wann eine einzelne Einstellung zuletzt geändert wurde — nur der Zeitpunkt. */
export interface SyncStamp {
  updatedAt: number;
}

/**
 * Ob ein Titel gemerkt ist — einschließlich „nicht mehr".
 *
 * `isFavorite === false` ist der Grabstein. Ohne ihn taucht ein entfernter
 * Titel wieder auf, sobald ein Gerät mit älterem Stand synchronisiert.
 */
export interface FavoriteMark {
  isFavorite: boolean;
  updatedAt: number;
  /** Trägt `favoriteAddedAt` über den Abgleich. */
  addedAt?: number;
}

/** Was eine Bibliotheksdatei über ihre Herkunft und ihre Änderungen weiß. */
export interface SyncMeta {
  formatVersion?: number;
  /** Zufällige UUID je Installation — keine Hardware-, Konto- oder Werbekennung. */
  deviceId?: string;
  platform?: string;
  appVersion?: string;
  generatedAt?: number;
  historyClearedAt?: number;
  progressClearedAt?: number;
  preferences?: Record<string, SyncStamp>;
  /** Merkliste als Zustand statt als Liste, Schlüssel `provider|slug`. */
  favorites?: Record<string, FavoriteMark>;
  /** Einzeln aus dem Verlauf entfernte Titel, Schlüssel `provider|slug`. */
  recentsRemoved?: Record<string, number>;
}

/**
 * Welche Einstellungen abgeglichen werden.
 *
 * Nicht dabei ist alles, was zum Gerät gehört und nicht zur Person:
 * Serveradresse, TMDB-Schlüssel, Effektstufe. Die liegen auf webOS ohnehin in
 * einem eigenen Speicher (`nori.webos.settings`).
 */
export const SYNC_PREFERENCES = [
  "langPref",
  "hosterPref",
  "resumeEnabled",
  "preferredQuality",
  "autoplayNext",
  "playbackSpeed",
  "provider",
  "scope",
] as const;

export type SyncPreference = (typeof SYNC_PREFERENCES)[number];

const PROVIDER_VALUES = ["aniworld", "serienstream"];
const SCOPE_VALUES = ["all", "aniworld", "serienstream", "kdrama"];

// --- Schlüssel --------------------------------------------------------------

/**
 * Schlüssel eines Merklisteneintrags: `provider|slug`.
 *
 * Mit Quelle, nicht nur mit Slug. Dieselbe Serie gibt es bei AniWorld und bei
 * Serienstream, und „gemerkt" ist eine Aussage über eine davon — genau wie der
 * Fortschritt, der nach `provider|episodePath` getrennt ist.
 */
export function favoriteKey(slug: string, provider: CatalogProvider): string {
  return `${provider}|${slug}`;
}

/** Schlüssel eines Verlaufseintrags: `provider|slug`. */
export function recentKey(slug: string, provider: CatalogProvider): string {
  return `${provider}|${slug}`;
}

export function slugFromSyncKey(key: string): string {
  const index = key.indexOf("|");
  return index < 0 ? key : key.slice(index + 1);
}

export function providerFromSyncKey(key: string): CatalogProvider | null {
  const index = key.indexOf("|");
  if (index < 0) return null;
  const raw = key.slice(0, index);
  return PROVIDER_VALUES.includes(raw) ? (raw as CatalogProvider) : null;
}

// --- Zeitstempel ------------------------------------------------------------

/**
 * Einen Zeitstempel auf etwas Verwendbares zurechtstutzen.
 *
 * Uhren laufen auseinander, und auf einem Fernseher, der ohne Netz startet,
 * laufen sie auch mal auf 1970 oder ins Jahr 2106. Eine Zukunft von Jahren
 * würde jede echte Änderung für Jahre schlagen und den Abgleich einfrieren.
 * Also: nichts Negatives, kein `NaN`, höchstens einen Tag voraus.
 */
export function sanitizedStamp(value: number | undefined | null, now: number): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) return 0;
  if (value > now + LIBRARY_SYNC_LIMITS.futureToleranceMs) return now;
  return value;
}

// --- Zusammenführen ---------------------------------------------------------

interface Ranked<T> {
  value: T;
  stamp: number;
  deviceId: string;
}

/**
 * Der Rang ist immer ein Paar: Zeitstempel zuerst, danach die Gerätekennung.
 *
 * Die zweite Hälfte ist der Grund, warum dieselben Dateien immer dasselbe
 * Ergebnis liefern — egal, in welcher Reihenfolge Drive sie herausgibt.
 */
function prefer<T>(current: Ranked<T> | undefined, next: Ranked<T>): Ranked<T> {
  if (!current) return next;
  if (next.stamp !== current.stamp) return next.stamp > current.stamp ? next : current;
  return next.deviceId > current.deviceId ? next : current;
}

/**
 * Mehrere Gerätestände zu einem verrechnen.
 *
 * Rein: keine Uhr ausser `now`, kein Netz, keine Ablage, kein Zustand. Die
 * Reihenfolge der Eingaben ist ohne Bedeutung — `merge(A, B, C)` ist
 * `merge(C, A, B)`. Das ist die Eigenschaft, die den Abgleich verlässlich
 * macht; Drive gibt Dateien in beliebiger Reihenfolge heraus.
 */
export function mergeLibrarySnapshots(snapshots: LibraryBag[], now: number): LibraryBag {
  const inputs = snapshots.map((snapshot) => normalizedSnapshot(snapshot, now));
  if (inputs.length === 0) {
    return { version: LIBRARY_SCHEMA_VERSION, modifiedAt: 0, favorites: [], recents: [], titles: {}, progress: {} };
  }

  // Löschmarken zuerst: sie filtern alles Weitere.
  const historyClearedAt = Math.max(0, ...inputs.map((input) => input.sync?.historyClearedAt ?? 0));
  const progressClearedAt = Math.max(0, ...inputs.map((input) => input.sync?.progressClearedAt ?? 0));

  const out: LibraryBag = {
    version: LIBRARY_SCHEMA_VERSION,
    modifiedAt: 0,
    favorites: [],
    recents: [],
    titles: {},
    progress: {},
  };

  // --- Einstellungen --------------------------------------------------------
  //
  // Je Einstellung gewinnt der jüngste Änderungszeitpunkt, und der Wert kommt
  // aus derselben Datei. Ein globales `modifiedAt` reicht dafür nicht: wer auf
  // dem Mac die Sprache umstellt und auf dem TV Autoplay, verlöre sonst eine
  // der beiden Änderungen komplett.
  const preferences: Record<string, SyncStamp> = {};
  for (const preference of SYNC_PREFERENCES) {
    let best: Ranked<LibraryBag> | undefined;
    for (const input of inputs) {
      // Ohne eigenen Zeitstempel zählt der Stand der ganzen Datei. Das
      // betrifft nur Dateien aus Schema v5, die den Block nicht kennen.
      const stamp = input.sync?.preferences?.[preference]?.updatedAt ?? input.modifiedAt ?? 0;
      best = prefer(best, { value: input, stamp, deviceId: input.sync?.deviceId ?? "" });
    }
    if (!best) continue;
    applyPreference(preference, best.value, out);
    preferences[preference] = { updatedAt: best.stamp };
  }

  // --- Merkliste ------------------------------------------------------------
  const marks = new Map<string, Ranked<FavoriteMark>>();
  for (const input of inputs) {
    const deviceId = input.sync?.deviceId ?? "";
    for (const [key, mark] of Object.entries(favoriteMarksOf(input))) {
      marks.set(key, prefer(marks.get(key), { value: mark, stamp: mark.updatedAt, deviceId }));
    }
  }

  const favoriteMarks: Record<string, FavoriteMark> = {};
  interface FavoriteEntry {
    slug: string;
    provider: CatalogProvider;
    addedAt: number;
    updatedAt: number;
    deviceId: string;
  }
  const entries: FavoriteEntry[] = [];
  for (const [key, ranked] of marks) {
    favoriteMarks[key] = ranked.value;
    const provider = providerFromSyncKey(key);
    if (!ranked.value.isFavorite || !provider) continue;
    entries.push({
      slug: slugFromSyncKey(key),
      provider,
      addedAt: ranked.value.addedAt ?? ranked.value.updatedAt,
      updatedAt: ranked.value.updatedAt,
      deviceId: ranked.deviceId,
    });
  }

  // Ein Slug kann nur eine Quelle tragen — `favoriteSource` ist nach Slug
  // geschlüsselt. Stehen beide Quellen auf „gemerkt", gewinnt der jüngere.
  const bySlug = new Map<string, FavoriteEntry>();
  for (const entry of entries) {
    const existing = bySlug.get(entry.slug);
    if (existing) {
      const keep = existing.updatedAt > entry.updatedAt
        || (existing.updatedAt === entry.updatedAt && existing.deviceId >= entry.deviceId);
      if (keep) continue;
    }
    bySlug.set(entry.slug, entry);
  }

  // Sortiert wie im Store: zuletzt Gemerktes vorn. Bei gleichem Zeitpunkt
  // entscheidet der Slug, damit nichts von einer Hash-Ordnung abhängt.
  const ordered = Array.from(bySlug.values())
    .sort((a, b) => (a.addedAt !== b.addedAt ? b.addedAt - a.addedAt : (a.slug < b.slug ? -1 : 1)))
    .slice(0, LIBRARY_SYNC_LIMITS.maxFavorites);

  out.favorites = ordered.map((entry) => entry.slug);
  out.favoriteSource = {};
  out.favoriteAddedAt = {};
  for (const entry of ordered) {
    out.favoriteSource[entry.slug] = entry.provider;
    out.favoriteAddedAt[entry.slug] = entry.addedAt;
  }

  // --- Fortschritt ----------------------------------------------------------
  //
  // Identität wie überall sonst: `provider|normalisierter episodePath`.
  // Jüngstes `updatedAt` gewinnt, bei Gleichstand die grössere Gerätekennung.
  const progress = new Map<string, Ranked<WatchProgress>>();
  for (const input of inputs) {
    const deviceId = input.sync?.deviceId ?? "";
    for (const item of Object.values(input.progress)) {
      if (item.updatedAt <= progressClearedAt) continue;
      const key = progressKey(item.episodePath, item.provider);
      progress.set(key, prefer(progress.get(key), { value: item, stamp: item.updatedAt, deviceId }));
    }
  }
  out.progress = {};
  for (const [key, ranked] of Array.from(progress.entries())
    .sort((a, b) => b[1].stamp - a[1].stamp)
    .slice(0, LIBRARY_SYNC_LIMITS.maxProgress)) {
    out.progress[key] = ranked.value;
  }

  // --- Verlauf --------------------------------------------------------------
  let removed: Record<string, number> = {};
  for (const input of inputs) {
    for (const [key, stamp] of Object.entries(input.sync?.recentsRemoved ?? {})) {
      removed[key] = Math.max(removed[key] ?? 0, stamp);
    }
  }

  const recents = new Map<string, Ranked<RecentItem>>();
  for (const input of inputs) {
    const deviceId = input.sync?.deviceId ?? "";
    const fallback = providerOf(input.provider);
    for (const item of input.recents) {
      const key = recentKey(item.slug, item.provider ?? fallback);
      if (item.viewedAt <= historyClearedAt || item.viewedAt <= (removed[key] ?? 0)) continue;
      recents.set(key, prefer(recents.get(key), { value: item, stamp: item.viewedAt, deviceId }));
    }
  }
  out.recents = Array.from(recents.entries())
    .sort((a, b) => (a[1].stamp !== b[1].stamp ? b[1].stamp - a[1].stamp : (a[0] < b[0] ? -1 : 1)))
    .slice(0, LIBRARY_SYNC_LIMITS.maxRecents)
    .map(([, ranked]) => ranked.value);

  // Grabsteine, die `historyClearedAt` ohnehin erschlägt, fallen weg. Sonst
  // wüchse die Datei mit jedem einzeln entfernten Eintrag für immer.
  removed = Object.fromEntries(Object.entries(removed).filter(([, stamp]) => stamp > historyClearedAt));

  // --- Titel ----------------------------------------------------------------
  const titles = new Map<string, Ranked<string>>();
  for (const input of inputs) {
    const deviceId = input.sync?.deviceId ?? "";
    const stamp = input.sync?.generatedAt ?? input.modifiedAt ?? 0;
    for (const [slug, title] of Object.entries(input.titles)) {
      if (!title) continue;
      titles.set(slug, prefer(titles.get(slug), { value: title, stamp, deviceId }));
    }
  }
  out.titles = {};
  for (const [slug, ranked] of Array.from(titles.entries()).slice(0, LIBRARY_SYNC_LIMITS.maxTitles)) {
    out.titles[slug] = ranked.value;
  }

  out.modifiedAt = Math.max(0, ...inputs.map((input) => input.modifiedAt ?? 0));
  out.sync = {
    formatVersion: LIBRARY_SYNC_FORMAT_VERSION,
    historyClearedAt,
    progressClearedAt,
    preferences,
    favorites: favoriteMarks,
    recentsRemoved: removed,
  };
  return out;
}

/**
 * Die Merkliste einer Datei als Zustandsabbildung — auch dann, wenn die Datei
 * den Block gar nicht hat.
 *
 * Der zweite Fall ist der wichtige: eine Datei aus Schema v5 trägt nur eine
 * Liste. Sie wird hier zu lauter `isFavorite: true` mit dem Merkzeitpunkt als
 * Rang. Damit überschreibt ein alter Stand nicht die Grabsteine eines neuen —
 * ein Grabstein von heute schlägt einen Merkzeitpunkt von gestern.
 */
function favoriteMarksOf(input: LibraryBag): Record<string, FavoriteMark> {
  const marks = input.sync?.favorites;
  if (marks && Object.keys(marks).length > 0) return marks;
  const fallback = providerOf(input.provider);
  const out: Record<string, FavoriteMark> = {};
  for (const slug of input.favorites) {
    const raw = input.favoriteSource?.[slug];
    const provider = raw && PROVIDER_VALUES.includes(raw) ? (raw as CatalogProvider) : fallback;
    const addedAt = input.favoriteAddedAt?.[slug] ?? input.modifiedAt ?? 0;
    out[favoriteKey(slug, provider)] = { isFavorite: true, updatedAt: addedAt, addedAt };
  }
  return out;
}

function providerOf(raw: string | undefined): CatalogProvider {
  return raw && PROVIDER_VALUES.includes(raw) ? (raw as CatalogProvider) : "aniworld";
}

function applyPreference(preference: SyncPreference, source: LibraryBag, target: LibraryBag): void {
  switch (preference) {
    case "langPref": target.langPref = source.langPref; break;
    case "hosterPref": target.hosterPref = source.hosterPref; break;
    case "resumeEnabled": target.resumeEnabled = source.resumeEnabled; break;
    case "preferredQuality": target.preferredQuality = source.preferredQuality; break;
    case "autoplayNext": target.autoplayNext = source.autoplayNext; break;
    case "playbackSpeed": target.playbackSpeed = source.playbackSpeed; break;
    case "provider": target.provider = source.provider; break;
    case "scope": target.scope = source.scope; break;
  }
}

/**
 * Eine Fremddatei auf brauchbare Werte zurechtstutzen, bevor sie in die
 * Rechnung geht.
 *
 * Was hier durchfällt, ist einzeln unbrauchbar — nicht die ganze Datei. Ein
 * Fortschrittseintrag ohne Pfad verschwindet, der Rest bleibt. Eine Datei
 * komplett zu verwerfen, weil ein Feld nicht stimmt, wäre der teurere Fehler.
 */
export function normalizedSnapshot(raw: LibraryBag, now: number): LibraryBag {
  const out: LibraryBag = { ...raw };
  out.modifiedAt = sanitizedStamp(raw.modifiedAt, now);

  const progress: Record<string, WatchProgress> = {};
  for (const value of Object.values(raw.progress ?? {})) {
    if (!value || typeof value !== "object") continue;
    const item: WatchProgress = { ...value, episodePath: normalizeEpisodePath(value.episodePath ?? "") };
    if (!item.episodePath || !item.slug) continue;
    item.provider = item.provider ?? providerFromPath(item.episodePath);
    item.updatedAt = sanitizedStamp(item.updatedAt, now);
    item.positionSec = Number.isFinite(item.positionSec) ? Math.max(0, item.positionSec) : 0;
    item.durationSec = Number.isFinite(item.durationSec) ? Math.max(0, item.durationSec) : 0;
    const key = progressKey(item.episodePath, item.provider);
    const existing = progress[key];
    if (existing && existing.updatedAt >= item.updatedAt) continue;
    progress[key] = item;
  }
  out.progress = progress;

  out.recents = (Array.isArray(raw.recents) ? raw.recents : [])
    .filter((item) => item && typeof item === "object" && Boolean(item.slug))
    .map((item) => ({ ...item, viewedAt: sanitizedStamp(item.viewedAt, now) }));

  out.favorites = (Array.isArray(raw.favorites) ? raw.favorites : []).filter((slug) => typeof slug === "string" && slug !== "");
  out.titles = Object.fromEntries(
    Object.entries(raw.titles ?? {}).filter(([slug, title]) => slug !== "" && typeof title === "string" && title !== ""),
  );

  // Werte, die der Enum nicht kennt, fliegen raus statt die App auf einen
  // unbekannten Zustand zu setzen.
  if (out.provider !== undefined && !PROVIDER_VALUES.includes(out.provider)) out.provider = undefined;
  if (out.scope !== undefined && !SCOPE_VALUES.includes(out.scope)) out.scope = undefined;
  if (out.playbackSpeed !== undefined
    && (!Number.isFinite(out.playbackSpeed) || out.playbackSpeed <= 0 || out.playbackSpeed > 4)) {
    out.playbackSpeed = undefined;
  }

  const meta: SyncMeta = { ...(raw.sync ?? {}) };
  meta.generatedAt = sanitizedStamp(meta.generatedAt, now);
  meta.historyClearedAt = sanitizedStamp(meta.historyClearedAt, now);
  meta.progressClearedAt = sanitizedStamp(meta.progressClearedAt, now);

  const stamps: Record<string, SyncStamp> = {};
  for (const [key, stamp] of Object.entries(meta.preferences ?? {})) {
    if (!(SYNC_PREFERENCES as readonly string[]).includes(key)) continue;
    stamps[key] = { updatedAt: sanitizedStamp(stamp?.updatedAt, now) };
  }
  meta.preferences = stamps;

  const marks: Record<string, FavoriteMark> = {};
  for (const [key, mark] of Object.entries(meta.favorites ?? {})) {
    if (!mark || typeof mark !== "object") continue;
    if (!providerFromSyncKey(key) || slugFromSyncKey(key) === "") continue;
    marks[key] = {
      isFavorite: mark.isFavorite === true,
      updatedAt: sanitizedStamp(mark.updatedAt, now),
      addedAt: mark.addedAt === undefined ? undefined : sanitizedStamp(mark.addedAt, now),
    };
  }
  meta.favorites = marks;

  const removed: Record<string, number> = {};
  for (const [key, stamp] of Object.entries(meta.recentsRemoved ?? {})) {
    removed[key] = sanitizedStamp(stamp, now);
  }
  meta.recentsRemoved = removed;

  out.sync = meta;
  return out;
}
