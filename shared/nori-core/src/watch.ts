// Der Sehstand eines Titels: herleiten, und von Hand setzen.
//
// Die Entsprechung zu `native/NoriCore/Sources/NoriCore/WatchMarks.swift` und
// zu `watchSummary` aus `WatchlistModel.swift`. Beide Kerne rechnen hier
// dasselbe, weil beide denselben Stand aus Google Drive lesen: würde der
// Fernseher „gesehen" anders herleiten als das iPhone, zeigten zwei Geräte
// auf identischen Daten zwei verschiedene Bibliotheken.
//
// ## Warum „ungesehen" kein Löschen ist
//
// Ein Eintrag, der lokal verschwindet, kommt beim nächsten Abgleich vom
// nächsten Gerät zurück — die Zusammenführung kennt für Fortschritt keinen
// Grabstein je Eintrag, nur den globalen `progressClearedAt`. „Als ungesehen
// markieren" schreibt deshalb einen **neuen, leeren** Stand mit frischem
// Zeitstempel: Position 0, nicht abgeschlossen. Der gewinnt die
// Zusammenführung regulär, und `watchSummary` zählt ihn wie „nie angefasst",
// weil dort nur zählt, was Position > 0 oder `completed` trägt.
//
// Genau deshalb sind das hier reine Funktionen, die **Einträge zurückgeben**
// statt eine Ablage zu verändern: der Aufrufer schreibt sie in einem Zug
// (`LibraryStore.upsert(contentsOf:)`, `saveProgressBatch`), und der Abgleich
// bekommt eine Meldung statt vierundzwanzig.

import { type CatalogProvider, type Episode, type WatchProgress } from "./models.js";
import {
  isEpisodeComplete, nowMs, progressKey, providerFromPath, watchRatio,
} from "./rules.js";

/** Der persönliche Stand zu einem Titel. Wie `WatchState` im Swift-Kern. */
export type WatchState = "unseen" | "started" | "seen";

export const WATCH_STATE_LABELS: Record<WatchState, string> = {
  unseen: "Ungesehen",
  started: "Angefangen",
  seen: "Gesehen",
};

/**
 * Was aus dem Fortschritt eines Titels herausgelesen werden kann.
 *
 * `ratio` ist der Stand **in der zuletzt gesehenen Folge**, nicht der Anteil
 * gesehener Folgen an der Serie — die Gesamtzahl der Folgen steht nur auf der
 * Detailseite der Quelle und ist offline nicht bekannt. Dieselbe Einschränkung
 * wie in `WatchSummary` im Swift-Kern, und derselbe Grund.
 */
export interface WatchSummary {
  state: WatchState;
  ratio: number;
  season: string | null;
  episode: number | null;
  completedEpisodes: number;
  lastWatched: number | null;
}

export const EMPTY_WATCH_SUMMARY: WatchSummary = {
  state: "unseen",
  ratio: 0,
  season: null,
  episode: null,
  completedEpisodes: 0,
  lastWatched: null,
};

/**
 * Den Stand eines Titels aus seinem Fortschritt herleiten.
 *
 * `entries` sind **alle** Einträge zu diesem Titel und dieser Quelle; die
 * Auswahl trifft der Aufrufer, weil derselbe Slug bei AniWorld und
 * Serienstream stehen kann und die beiden Stände einander nicht überschreiben
 * dürfen.
 */
export function watchSummary(entries: WatchProgress[]): WatchSummary {
  // Ein Eintrag mit Position 0 und ohne Abschluss entsteht schon beim bloßen
  // Öffnen einer Folge — und beim Zurücksetzen von Hand. Er ist kein
  // „angefangen".
  const touched = entries.filter((item) => item.positionSec > 0 || item.completed === true);
  if (touched.length === 0) return { ...EMPTY_WATCH_SUMMARY };

  const completed = touched.filter((item) => isEpisodeComplete(item));
  const latest = touched.reduce<WatchProgress | null>(
    (best, item) => (!best || item.updatedAt > best.updatedAt ? item : best), null);
  const lastWatched = latest?.updatedAt ?? null;

  if (completed.length === touched.length) {
    return {
      state: "seen",
      ratio: 1,
      season: latest?.season ?? null,
      episode: latest?.episode ?? null,
      completedEpisodes: completed.length,
      lastWatched,
    };
  }

  // Der Balken zeigt die Folge, in der zuletzt etwas lief — auch dann, wenn
  // sie schon durch ist und nur die Folge danach aussteht.
  const current = latest && !isEpisodeComplete(latest)
    ? latest
    : touched.filter((item) => !isEpisodeComplete(item))
      .reduce<WatchProgress | null>((best, item) => (!best || item.updatedAt > best.updatedAt ? item : best), null);

  return {
    state: "started",
    ratio: watchRatio(current),
    season: current?.season ?? latest?.season ?? null,
    episode: current?.episode ?? latest?.episode ?? null,
    completedEpisodes: completed.length,
    lastWatched,
  };
}

/** Der Wert, nach dem „Fortschritt" sortiert — wie `WatchSummary.sortValue`. */
export function watchSortValue(summary: WatchSummary): number {
  return summary.completedEpisodes + Math.min(Math.max(summary.ratio, 0), 1);
}

/** Die Zeile unter dem Titel: „S1 · F7 · 58 %". */
export function watchStateText(summary: WatchSummary): string {
  if (summary.state === "unseen") return "Noch nicht begonnen";
  if (summary.state === "seen") return "Komplett gesehen";
  const percent = Math.round(summary.ratio * 100);
  if (summary.season === null || summary.episode === null) return `Angefangen · ${percent} %`;
  const label = summary.season === "filme" ? "Filme" : `S${summary.season}`;
  return `${label} · F${summary.episode} · ${percent} %`;
}

/** Alle Fortschrittseinträge eines Titels bei einer Quelle. */
export function entriesForSeries(
  progress: Record<string, WatchProgress>,
  slug: string,
  provider: CatalogProvider,
): WatchProgress[] {
  return Object.values(progress).filter((item) =>
    item.slug === slug && (item.provider ?? providerFromPath(item.episodePath)) === provider);
}

/** Der Stand eines Titels, direkt aus der Ablage. */
export function seriesWatchSummary(
  progress: Record<string, WatchProgress>,
  slug: string,
  provider: CatalogProvider,
): WatchSummary {
  return watchSummary(entriesForSeries(progress, slug, provider));
}

// MARK: - Von Hand setzen

/** Welcher Titel, welche Staffel, welche Quelle. */
export interface MarkTarget {
  slug: string;
  title: string;
  season: string;
  provider: CatalogProvider;
}

/**
 * Eine Folge als gesehen oder ungesehen markieren.
 *
 * Eine bekannte Laufzeit bleibt stehen: sie beim Abhaken auf null zu setzen
 * wäre ein Verlust, und beim Zurücksetzen brauchte die Folge sie sofort wieder,
 * sobald jemand sie erneut abspielt.
 */
export function markEpisode(
  progress: Record<string, WatchProgress>,
  target: MarkTarget,
  episode: Episode,
  seen: boolean,
  now: number = nowMs(),
): WatchProgress {
  const known = knownEntry(progress, target, episode);
  const duration = known?.durationSec ?? 0;
  return {
    slug: target.slug,
    title: target.title,
    season: target.season,
    episode: episode.number,
    episodePath: episode.path,
    germanTitle: episode.germanTitle,
    englishTitle: episode.englishTitle,
    positionSec: seen ? duration : 0,
    durationSec: duration,
    updatedAt: now,
    lang: known?.lang,
    completed: seen,
    provider: target.provider,
  };
}

/** Eine ganze Staffel auf einmal. */
export function markSeason(
  progress: Record<string, WatchProgress>,
  target: MarkTarget,
  episodes: Episode[],
  seen: boolean,
  now: number = nowMs(),
): WatchProgress[] {
  return episodes.map((episode) => markEpisode(progress, target, episode, seen, now));
}

/** Eine Staffel je Eintrag — für „ganze Serie", wo die Folgen geladen wurden. */
export interface SeasonEpisodes {
  season: string;
  episodes: Episode[];
}

/**
 * Eine ganze Serie als gesehen markieren.
 *
 * Braucht die Folgenlisten aller Staffeln; die holt der Aufrufer, weil nur er
 * weiß, was schon geladen ist und was erst noch über das Netz kommt. Der
 * umgekehrte Weg — „Serie als ungesehen" — kommt mit
 * `resetSeriesProgress` ohne Netz aus.
 */
export function markSeries(
  progress: Record<string, WatchProgress>,
  series: { slug: string; title: string; provider: CatalogProvider },
  seasons: SeasonEpisodes[],
  seen: boolean,
  now: number = nowMs(),
): WatchProgress[] {
  const out: WatchProgress[] = [];
  for (const entry of seasons) {
    const target: MarkTarget = { ...series, season: entry.season };
    for (const episode of entry.episodes) out.push(markEpisode(progress, target, episode, seen, now));
  }
  return out;
}

/**
 * Jeden bekannten Fortschritt einer Serie zurücksetzen — ohne Folgenliste.
 *
 * Das ist „Serie als ungesehen" und zugleich „Fortschritt vergessen": was Nori
 * nicht kennt, ist ohnehin ungesehen, und was es kennt, wird auf null gesetzt
 * statt gelöscht (siehe Kopf dieser Datei).
 */
export function resetSeriesProgress(
  progress: Record<string, WatchProgress>,
  slug: string,
  provider: CatalogProvider,
  now: number = nowMs(),
): WatchProgress[] {
  return entriesForSeries(progress, slug, provider)
    .filter((item) => item.positionSec > 0 || item.completed === true)
    .map((item) => resetEntry(item, now));
}

/** Eine einzelne Staffel vergessen, ohne die übrigen anzurühren. */
export function resetSeasonProgress(
  progress: Record<string, WatchProgress>,
  slug: string,
  season: string,
  provider: CatalogProvider,
  now: number = nowMs(),
): WatchProgress[] {
  return entriesForSeries(progress, slug, provider)
    .filter((item) => item.season === season && (item.positionSec > 0 || item.completed === true))
    .map((item) => resetEntry(item, now));
}

/**
 * „Aus Weiterschauen entfernen".
 *
 * Nur die angefangenen Einträge der Serie werden zurückgesetzt —
 * abgeschlossene Folgen bleiben abgeschlossen. Die Reihe sucht sich je Serie
 * den jüngsten unfertigen Eintrag (`continueWatching`); ist keiner mehr übrig,
 * verschwindet die Serie dort, ohne dass jemand „gesehen" verliert.
 */
export function removeFromContinueWatching(
  progress: Record<string, WatchProgress>,
  slug: string,
  provider: CatalogProvider,
  now: number = nowMs(),
): WatchProgress[] {
  return entriesForSeries(progress, slug, provider)
    .filter((item) => !isEpisodeComplete(item) && item.positionSec > 0)
    .map((item) => resetEntry(item, now));
}

/** Einen Eintrag auf „nie angefasst" setzen, Laufzeit und Sprache behalten. */
export function resetEntry(item: WatchProgress, now: number = nowMs()): WatchProgress {
  return { ...item, positionSec: 0, completed: false, updatedAt: now };
}

// MARK: - Zählstände

/** Wie viele Folgen einer Serie abgeschlossen sind, über alle Staffeln. */
export function seriesCompletedCount(
  progress: Record<string, WatchProgress>,
  slug: string,
  provider: CatalogProvider,
): number {
  return entriesForSeries(progress, slug, provider).filter((item) => isEpisodeComplete(item)).length;
}

/** „7 von 12 gesehen" — oder null, wenn es nichts zu sagen gibt. */
export function seasonProgressLabel(watched: number, total: number): string | null {
  if (total <= 0 || watched <= 0) return null;
  return `${watched} von ${total} gesehen`;
}

function knownEntry(
  progress: Record<string, WatchProgress>,
  target: MarkTarget,
  episode: Episode,
): WatchProgress | null {
  const direct = progress[progressKey(episode.path, target.provider)];
  if (direct) return direct;
  for (const item of Object.values(progress)) {
    if (item.slug !== target.slug || item.season !== target.season || item.episode !== episode.number) continue;
    if ((item.provider ?? providerFromPath(item.episodePath)) !== target.provider) continue;
    return item;
  }
  return null;
}
