// Woher die App ihre Daten bekommt.
//
// Zwei Wege, beide liefern dieselben Modelle aus `@nori/core`:
//
//   „server"  — über `services/nori-api`. Der empfohlene Weg: der Server darf
//               `Referer` setzen, ein Browser nicht, und viele Hoster liefern
//               ohne diese Kopfzeile nichts aus. Außerdem reicht er HLS
//               weiter, womit die Herkunftsprüfung des Fernsehers keine Rolle
//               mehr spielt.
//
//   „direkt"  — der Fernseher ruft die Quellen selbst ab, wie iOS und macOS es
//               tun. Kommt ohne zusätzliche Einrichtung aus, hängt aber davon
//               ab, dass webOS der App fremde Abrufe erlaubt und dass der
//               Hoster ohne Referer ausliefert. Kein Ersatz, sondern der
//               Rückfall.
//
// Hosterlogik gibt es in keinem Fall doppelt: beide Wege benutzen denselben
// Kern, der direkte im Fernseher, der andere im Server.

import {
  DirectGateway, FetchHttpClient, NoriError,
  type CalendarPayload, type CatalogProvider, type CatalogResult, type NoriGateway,
  type PlaySource, type ResolveRequest, type SeriesDetail, type WatchInfo,
} from "@nori/core";
import { log } from "./log";

export type TransportMode = "server" | "direct";

export interface GatewayConfig {
  mode: TransportMode;
  /** Basisadresse des Nori-Servers, etwa `http://192.168.1.20:8730`. */
  serverUrl: string;
}

interface ResolveResponse extends PlaySource {
  playbackUrl?: string;
}

/** Spricht mit `services/nori-api`. */
class HttpGateway implements NoriGateway {
  private readonly base: string;

  constructor(base: string) {
    this.base = base.replace(/\/+$/, "");
  }

  private async get<T>(path: string): Promise<T> {
    let res: Response;
    try {
      res = await fetch(this.base + path, { headers: { Accept: "application/json" } });
    } catch (cause) {
      throw NoriError.network(
        `Nori-Server nicht erreichbar (${(cause as Error)?.message ?? "keine Verbindung"})`,
      );
    }
    const body = (await res.json().catch(() => ({}))) as { error?: string; kind?: string };
    if (!res.ok) {
      const message = body.error ?? `HTTP ${res.status}`;
      throw new NoriError((body.kind as NoriError["kind"]) ?? "network", message);
    }
    return body as T;
  }

  catalog(provider: CatalogProvider, force = false) {
    return this.get<CatalogResult>(`/api/catalog/${provider}${force ? "?force=1" : ""}`);
  }

  series(provider: CatalogProvider, slug: string, season?: string | null) {
    const query = season ? `?season=${encodeURIComponent(season)}` : "";
    return this.get<SeriesDetail>(`/api/series/${provider}/${encodeURIComponent(slug)}${query}`);
  }

  watch(provider: CatalogProvider, path: string) {
    return this.get<WatchInfo>(`/api/watch/${provider}?path=${encodeURIComponent(path)}`);
  }

  calendar(provider: CatalogProvider, force = false) {
    return this.get<CalendarPayload>(`/api/calendar/${provider}${force ? "?force=1" : ""}`);
  }

  async resolve(request: ResolveRequest): Promise<PlaySource> {
    let res: Response;
    try {
      res = await fetch(`${this.base}/api/resolve`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(request),
      });
    } catch (cause) {
      throw NoriError.network(
        `Nori-Server nicht erreichbar (${(cause as Error)?.message ?? "keine Verbindung"})`,
      );
    }
    const body = (await res.json().catch(() => ({}))) as ResolveResponse & { error?: string; kind?: string };
    if (!res.ok) {
      throw new NoriError((body.kind as NoriError["kind"]) ?? "hoster", body.error ?? `HTTP ${res.status}`);
    }
    // Die Weiterreichung des Servers merken; `playbackURL` gibt sie zurück.
    return { ...body, referer: body.referer ?? null, url: body.playbackUrl
      ? this.base + body.playbackUrl
      : body.url };
  }

  playbackURL(source: PlaySource): string {
    if (source.url.startsWith(this.base)) return source.url;
    const params = new URLSearchParams({ u: source.url });
    if (source.referer) params.set("r", source.referer);
    return `${this.base}/api/stream?${params.toString()}`;
  }

  imageURL(url: string): string {
    // Cover kommen von den Quellen selbst; über den Server geleitet umgeht das
    // sowohl Herkunftsprüfungen als auch Hotlink-Sperren.
    return `${this.base}/api/image?u=${encodeURIComponent(url)}`;
  }
}

let cached: { key: string; gateway: NoriGateway } | null = null;

export function normalizeServerUrl(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed) return "";
  const withScheme = /^https?:\/\//i.test(trimmed) ? trimmed : `http://${trimmed}`;
  try {
    const url = new URL(withScheme);
    if (!url.port && !/:\d+$/.test(url.host)) url.port = "8730";
    return url.origin;
  } catch {
    return "";
  }
}

export function createGateway(config: GatewayConfig): NoriGateway {
  const server = normalizeServerUrl(config.serverUrl);
  const key = `${config.mode}|${server}`;
  if (cached?.key === key) return cached.gateway;
  const gateway: NoriGateway = config.mode === "server" && server
    ? new HttpGateway(server)
    // Im Browser lässt sich `Location` einer Weiterleitung nicht auslesen;
    // der Resolver nimmt deshalb die Endadresse der gefolgten Kette.
    : new DirectGateway(new FetchHttpClient({ canReadRedirects: false, timeoutMs: 20_000 }));
  log("data", "Zugang", config.mode === "server" && server ? `Server ${server}` : "direkt");
  cached = { key, gateway };
  return gateway;
}

/** Ist der eingetragene Server erreichbar? Für die Einstellungen. */
export async function pingServer(serverUrl: string): Promise<string> {
  const base = normalizeServerUrl(serverUrl);
  if (!base) throw NoriError.network("Keine gültige Adresse");
  const res = await fetch(`${base}/api/health`, { headers: { Accept: "application/json" } });
  if (!res.ok) throw NoriError.network(`HTTP ${res.status}`);
  const body = (await res.json()) as { name?: string; version?: string };
  if (body.name !== "nori-api") throw NoriError.network("Antwort stammt nicht von einem Nori-Server");
  return body.version ?? "unbekannt";
}
