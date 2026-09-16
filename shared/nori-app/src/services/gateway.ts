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
//   „direkt"  — der Client ruft die Quellen selbst ab, wie iOS und macOS es
//               tun. Kommt ohne zusätzliche Einrichtung aus, hängt aber davon
//               ab, dass die Laufzeit fremde Abrufe erlaubt und dass der
//               Hoster ohne Referer ausliefert. Auf dem Fernseher kein Ersatz,
//               sondern der Rückfall.
//
//   „lokal"   — der Weg des Schreibtischs: derselbe Kern, aber im
//               Hauptprozess der App, wo es keine Herkunftsprüfung gibt und
//               `Referer` gesetzt werden darf. Das Fenster spricht über einen
//               Kanal mit ihm; die App meldet ihn beim Start an
//               (`registerLocalGateway`). Ist einer angemeldet, laufen auch
//               „server" und „direkt" dort — welchen der beiden, sagt das
//               Fenster dem Hauptprozess. Ohne angemeldeten Kanal bleibt es
//               bei den zwei Wegen darüber.
//
// Hosterlogik gibt es in keinem Fall doppelt: alle Wege benutzen denselben
// Kern — im Client, im Hauptprozess oder im Server.

import {
  DirectGateway, FetchHttpClient, NoriError, isTMDBImage,
  type CalendarPayload, type CatalogProvider, type CatalogResult, type NoriGateway,
  type PlaySource, type ResolveRequest, type SeriesDetail, type WatchInfo,
} from "@nori/core";
import { log } from "./log";

export type TransportMode = "server" | "direct" | "local";

let cached: { key: string; gateway: NoriGateway } | null = null;

/**
 * Der Zugang, den die App selbst mitbringt.
 *
 * Auf dem Schreibtisch ist das die Brücke in den Hauptprozess. Angemeldet wird
 * er einmal beim Start, bevor etwas gezeichnet wird.
 *
 * Ist einer angemeldet, **gilt er für jede Einstellung**. Das ist kein
 * Übergehen des Nutzers, sondern die Aufteilung der Arbeit: Welchen Weg die
 * Daten nehmen — im Programm oder über einen Nori-Server —, entscheidet dann
 * der Hauptprozess, und die Einstellung wird ihm gemeldet. Das Fenster selbst
 * darf gar nicht ins Netz: von `file://` aus ist jeder Abruf fremder Herkunft,
 * und die Inhaltsrichtlinie lässt kein `http:` zu. Ein hier gebauter Zugang
 * wäre also nicht der schnellere Weg, sondern gar keiner.
 */
let localGateway: NoriGateway | null = null;

export function registerLocalGateway(gateway: NoriGateway): void {
  localGateway = gateway;
  cached = null;
}

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
    // TMDB-Bilder gehen den kurzen Weg: sie verlangen keinen `Referer`, haben
    // keine Hotlink-Sperre und liefern die passenden Kopfzeilen für eine
    // fremde Herkunft. Über den Server geleitet wären sie nur ein Umweg — und
    // eine Last für den Server, die niemand braucht.
    if (isTMDBImage(url)) return url;
    // Cover der Quellen dagegen kommen nur mit passender Kopfzeile; über den
    // Server geleitet umgeht das sowohl Herkunftsprüfungen als auch
    // Hotlink-Sperren.
    return `${this.base}/api/image?u=${encodeURIComponent(url)}`;
  }
}

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
  // Der mitgebrachte Zugang schlägt alles: siehe `localGateway`.
  if (localGateway) return localGateway;
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

/** Was ein Nori-Server über sich sagt. */
export interface ServerInfo {
  version: string;
  /** Kann der Server TMDB? Entscheidet über den TMDB-Weg. */
  tmdb: boolean;
  /**
   * Ob dort ein eigener Schlüssel eingetragen ist (`NORI_TMDB_KEY`) oder der
   * mitgelieferte gilt. Ein älterer Server sagt dazu nichts — dann `null`.
   */
  tmdbKey: "own" | "builtIn" | null;
  tmdbCacheEntries: number;
}

/**
 * Ist der eingetragene Server erreichbar, und was kann er?
 *
 * Die Auskunft über TMDB ist der Grund, warum hier mehr als „ja" zurückkommt:
 * ohne sie müsste der Fernseher einen TMDB-Abruf wagen, um zu erfahren, ob er
 * einen wagen kann — und bei einem alten Server ohne `/api/tmdb` wäre das
 * Ergebnis „nicht erreichbar" statt „kann das nicht".
 */
export async function pingServer(serverUrl: string): Promise<ServerInfo> {
  const base = normalizeServerUrl(serverUrl);
  if (!base) throw NoriError.network("Keine gültige Adresse");
  let res: Response;
  try {
    res = await fetch(`${base}/api/health`, { headers: { Accept: "application/json" } });
  } catch (cause) {
    throw NoriError.network((cause as Error)?.message ?? "keine Verbindung");
  }
  if (!res.ok) throw NoriError.network(`HTTP ${res.status}`);
  const body = (await res.json().catch(() => ({}))) as {
    name?: string;
    version?: string;
    features?: { tmdb?: boolean; tmdbKey?: string; tmdbCacheEntries?: number };
  };
  if (body.name !== "nori-api") throw NoriError.network("Antwort stammt nicht von einem Nori-Server");
  const origin = body.features?.tmdbKey;
  return {
    version: body.version ?? "unbekannt",
    tmdb: body.features?.tmdb === true,
    tmdbKey: origin === "own" || origin === "builtIn" ? origin : null,
    tmdbCacheEntries: body.features?.tmdbCacheEntries ?? 0,
  };
}
