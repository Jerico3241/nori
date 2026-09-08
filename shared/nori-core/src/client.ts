// Zugang zu den Quellen — dieselben Abrufe und Prüfungen wie `AniworldClient`
// im Swift-Kern, samt der Zwischenspeicher-Fristen (Katalog 30 min, Serie
// 10 min, Kalender 20 min).

import { BROWSE_HEADERS, type HttpClient } from "./http.js";
import {
  NoriError, PROVIDERS,
  type CalendarPayload, type CatalogProvider, type CatalogResult,
  type SeriesDetail, type WatchInfo,
} from "./models.js";
import { looksBlocked } from "./hoster/safety.js";
import * as aniworld from "./parse/aniworld.js";
import * as serienstream from "./parse/serienstream.js";
import { packCalendar, toAniworldPath } from "./parse/common.js";
import { seriesPath } from "./models.js";

interface CacheEntry<T> {
  value: T;
  expiresAt: number;
}

export class NoriClient {
  private readonly http: HttpClient;
  private readonly catalogs = new Map<CatalogProvider, CacheEntry<CatalogResult>>();
  private readonly series = new Map<string, CacheEntry<SeriesDetail>>();
  private readonly calendars = new Map<CatalogProvider, CacheEntry<CalendarPayload>>();

  constructor(http: HttpClient) {
    this.http = http;
  }

  async getCatalog(provider: CatalogProvider, force = false): Promise<CatalogResult> {
    const hit = this.catalogs.get(provider);
    if (!force && hit && hit.expiresAt > Date.now()) return hit.value;
    const html = await this.fetchPage(PROVIDERS[provider].catalogPath, provider);
    const items = provider === "serienstream"
      ? serienstream.parseCatalog(html)
      : aniworld.parseCatalog(html);
    // Der Parser sieht nur HTML und weiß nicht, welche Seite er liest. Die
    // Quelle kommt deshalb hier dazu.
    for (const item of items) item.provider = provider;
    // Anzahl mitgeben: 0 heißt blockiert oder Markup geändert, eine kleine
    // Zahl heißt, dass der Parser nur noch teilweise greift.
    if (items.length < 20) {
      throw NoriError.parse(
        `${PROVIDERS[provider].label}: Katalog unvollständig, nur ${items.length} Einträge gelesen`,
      );
    }
    const result: CatalogResult = { items, source: "live", fetchedAt: Date.now() };
    this.catalogs.set(provider, { value: result, expiresAt: Date.now() + 30 * 60_000 });
    return result;
  }

  async getSeries(
    provider: CatalogProvider,
    slug: string,
    season?: string | null,
  ): Promise<SeriesDetail> {
    const key = `${provider}::${slug}::${season ?? "default"}`;
    const hit = this.series.get(key);
    if (hit && hit.expiresAt > Date.now()) return hit.value;
    const html = await this.fetchPage(seriesPath(provider, slug, season), provider);
    const hasSeries = html.includes("series-title") || html.includes("seasonEpisodesList")
      || html.includes("episode-row") || html.includes("seriesCoverBox");
    if (!hasSeries) throw NoriError.notFound("Serie nicht gefunden");
    const detail = provider === "serienstream"
      ? serienstream.parseSeries(html, slug, season)
      : aniworld.parseSeries(html, slug, season);
    const low = detail.title.toLowerCase();
    if (low === "alle animes" || low === "alle serien") {
      throw NoriError.notFound("Serie nicht gefunden");
    }
    this.series.set(key, { value: detail, expiresAt: Date.now() + 10 * 60_000 });
    return detail;
  }

  async getWatch(provider: CatalogProvider, path: string): Promise<WatchInfo> {
    const clean = toAniworldPath(path);
    const ok = provider === "serienstream" ? clean.startsWith("/serie/") : clean.startsWith("/anime/stream/");
    if (!ok) throw NoriError.parse("Ungültiger Pfad");
    const html = await this.fetchPage(clean, provider);
    const info = provider === "serienstream"
      ? serienstream.parseWatch(html, clean)
      : aniworld.parseWatch(html, clean);
    if (info.hosters.length === 0) throw NoriError.parse("Keine Hoster gefunden");
    return info;
  }

  async getCalendar(provider: CatalogProvider, force = false): Promise<CalendarPayload> {
    const hit = this.calendars.get(provider);
    if (!force && hit && hit.expiresAt > Date.now()) return hit.value;
    let payload: CalendarPayload;
    if (provider === "serienstream") {
      const raw = await this.fetchJSON(PROVIDERS[provider].calendarPath, provider);
      payload = packCalendar(serienstream.parseCalendar(raw));
    } else {
      const html = await this.fetchPage(PROVIDERS[provider].calendarPath, provider);
      payload = packCalendar(aniworld.parseCalendar(html));
    }
    for (const entry of payload.upcoming) entry.provider = provider;
    for (const entry of payload.recent) entry.provider = provider;
    if (payload.upcoming.length + payload.recent.length < 3) {
      throw NoriError.parse("Kalender unvollständig");
    }
    this.calendars.set(provider, { value: payload, expiresAt: Date.now() + 20 * 60_000 });
    return payload;
  }

  async fetchPage(path: string, provider: CatalogProvider): Promise<string> {
    const html = await this.fetchText(path, provider, BROWSE_HEADERS.Accept);
    if (looksBlocked(html)) {
      throw NoriError.blocked(`${PROVIDERS[provider].label} nicht erreichbar`);
    }
    return html;
  }

  private async fetchText(path: string, provider: CatalogProvider, accept: string): Promise<string> {
    const url = path.startsWith("http") ? path : PROVIDERS[provider].origin + path;
    const res = await this.http.request(url, { headers: { ...BROWSE_HEADERS, Accept: accept } });
    if (res.status >= 400) throw NoriError.network(`HTTP ${res.status}`);
    return res.text();
  }

  private async fetchJSON(path: string, provider: CatalogProvider): Promise<unknown> {
    const text = await this.fetchText(path, provider, "application/json");
    try {
      return JSON.parse(text) as unknown;
    } catch {
      throw NoriError.parse("Kalender: unlesbare Antwort");
    }
  }

  /** Cover-Adresse relativ zur Quelle auflösen; AVIF und Query bleiben erhalten. */
  static coverURL(path: string | null | undefined, provider: CatalogProvider): string | null {
    if (!path) return null;
    const raw = path.trim();
    if (!raw) return null;
    try {
      const url = new URL(raw, PROVIDERS[provider].origin + "/");
      if (url.protocol !== "https:" && url.protocol !== "http:") return null;
      return url.toString();
    } catch {
      return null;
    }
  }

  clearCaches(): void {
    this.catalogs.clear();
    this.series.clear();
    this.calendars.clear();
  }
}
