// Die Regeln aus `Models.swift` und `contract.json`, unverändert übernommen.
//
// Sie entscheiden, was „gesehen" heißt, wo fortgesetzt wird und wie der
// Fortschritt geschlüsselt ist. Weicht ein Client hier ab, zeigt er einen
// anderen Stand als die anderen Nori-Apps auf denselben Daten.

import { CATALOG_PROVIDERS, PROVIDERS, type CatalogProvider, type WatchProgress } from "./models.js";

/**
 * Aus dem Pfad einer Folge ableiten, zu welcher Quelle sie gehört.
 *
 * Über `streamPrefix` jeder Quelle, nicht über eine einzelne Abfrage mit
 * AniWorld als Sonst-Zweig: eine dritte Quelle wäre damit stillschweigend als
 * Anime verbucht — und weil der Fortschritt danach geschlüsselt ist, hätte das
 * den Stand vertauscht, nicht bloß ein Etikett.
 */
export function providerFromPath(path: string): CatalogProvider {
  for (const provider of CATALOG_PROVIDERS) {
    if (path.includes(PROVIDERS[provider].streamPrefix + "/")) return provider;
  }
  return "aniworld";
}

export function normalizeEpisodePath(raw: string): string {
  let path = raw;
  if (path.startsWith("http")) {
    try {
      path = new URL(path).pathname;
    } catch {
      /* unverändert lassen */
    }
  }
  while (path.endsWith("/")) path = path.slice(0, -1);
  return path;
}

export function progressKey(path: string, provider?: CatalogProvider | null): string {
  const clean = normalizeEpisodePath(path);
  if (!provider) return clean;
  return `${provider}|${clean}`;
}

export function progressId(item: WatchProgress): string {
  return progressKey(item.episodePath, item.provider ?? providerFromPath(item.episodePath));
}

/** `completed == true` ODER (Dauer ≥ 20 s UND Position ≥ 90 % der Dauer). */
export function isEpisodeComplete(item?: WatchProgress | null): boolean {
  if (!item) return false;
  if (item.completed === true) return true;
  return item.durationSec >= 20 && item.positionSec >= item.durationSec * 0.9;
}

export function watchRatio(item?: WatchProgress | null): number {
  if (!item) return 0;
  if (isEpisodeComplete(item)) return 1;
  if (item.durationSec < 8) return 0;
  return Math.min(1, Math.max(0, item.positionSec / item.durationSec));
}

/** Fertig → 0; unter 8 s → 0; sonst die gespeicherte Position. */
export function resumePosition(item?: WatchProgress | null): number {
  if (!item || isEpisodeComplete(item)) return 0;
  if (item.positionSec < 8) return 0;
  return item.positionSec;
}

export function formatClock(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const r = s % 60;
  const pad = (n: number) => String(n).padStart(2, "0");
  if (h > 0) return `${h}:${pad(m)}:${pad(r)}`;
  return `${m}:${pad(r)}`;
}

/** Reihenfolge der Hoster aus contract.json. Kleiner ist besser. */
export function hosterRank(name: string): number {
  const n = name.toLowerCase().replace(/[^a-z]/g, "");
  if (n.includes("voe")) return 0;
  if (n.includes("vidmoly")) return 1;
  if (n.includes("vidoza")) return 2;
  if (n.includes("lulu")) return 3;
  if (n.includes("speedfiles")) return 4;
  if (n.includes("filemoon")) return 5;
  if (n.includes("dood")) return 9;
  return 7;
}

export const PLAYBACK_SPEEDS = [0.75, 1.0, 1.25, 1.5, 2.0];
export const LANGUAGE_ORDER = ["DE", "GerSub", "EN"];

/** Der Fortschritt einer Folge, aber lesbar: „68 %". */
export function progressPercent(item?: WatchProgress | null): number {
  return Math.round(watchRatio(item) * 100);
}

/** Millisekunden seit 1970 — überall in Nori das Zeitformat für Bibliotheksdaten. */
export function nowMs(): number {
  return Date.now();
}
