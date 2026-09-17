// Die Quellenschicht — im Hauptprozess, nicht im Fenster.
//
// ## Warum nicht im Fenster
//
// Nori liest AniWorld und Serienstream als HTML und löst danach die Adresse
// eines Hosters auf. Beides scheitert in einem Browserfenster an drei Dingen,
// und keines davon ist zu umgehen:
//
// 1. **Herkunftsprüfung.** Ein Abruf von `file://` auf `aniworld.to` ist ein
//    fremder Ursprung; die Quellen setzen keine CORS-Kopfzeilen, also gibt es
//    keine Antwort.
// 2. **`Referer`.** Viele Hoster liefern ohne diese Kopfzeile nichts aus. Ein
//    Browser lässt sie nicht setzen — das ist der Sinn der Sperrliste für
//    verbotene Kopfzeilen.
// 3. **Weiterleitungen.** Der Resolver muss das Ziel einer Weiterleitung
//    lesen, bevor er ihr folgt. `fetch` im Browser gibt es nicht her.
//
// Der Fernseher löst das mit einem Nori-Server nebenan. Auf dem Schreibtisch
// braucht es den nicht: Der Hauptprozess **ist** Node, und dort darf ein
// Programm alles, was ein Programm darf. Dieselbe `DirectGateway` aus
// `@nori/core`, die auch `services/nori-api` benutzt — kein zweiter Weg durch
// den Quelltext, kein Server, der mitlaufen muss, kein Port, der belegt wird.
//
// Das Fenster bekommt davon eine Handvoll IPC-Kanäle zu sehen.

import { parseHTML } from "linkedom";
import {
  DirectGateway, FetchHttpClient, NoriError, setHtmlParser,
  type CalendarPayload, type CatalogProvider, type CatalogResult, type NoriGateway,
  type PlaySource, type ResolveRequest, type SeriesDetail, type WatchInfo,
} from "@nori/core";

// Einmal, bevor der erste Parser läuft. In Node gibt es keinen `DOMParser`.
setHtmlParser((html: string) => parseHTML(html).document as unknown as Document);

const http = new FetchHttpClient({ canReadRedirects: true, timeoutMs: 25_000 });
const direct = new DirectGateway(http);

/**
 * Der zweite Weg: ein Nori-Server im Netz.
 *
 * Wer schon einen betreibt — für den Fernseher zum Beispiel —, soll den
 * Schreibtisch daran hängen können: ein Zwischenspeicher für alle Geräte, eine
 * Ratenbegrenzung statt mehrerer.
 *
 * Auch dieser Weg läuft im **Hauptprozess** und nicht im Fenster. Von einer
 * `file://`-Seite aus wäre jeder Abruf an `http://192.168.1.20:8730` ein
 * fremder Ursprung, und die Inhaltsrichtlinie des Fensters lässt ohnehin nur
 * `https:` zu — zu Recht: was im Fenster läuft, soll nicht ins lokale Netz
 * telefonieren können.
 *
 * ## Nur Auskunft, kein Durchreichen
 *
 * Der Server liefert hier **Listen, Details und aufgelöste Adressen** — Bild
 * und Ton holt Nori selbst, direkt beim Hoster. Auf dem Fernseher ist das
 * andersherum, und das hat einen Grund: dort kann niemand einen `Referer`
 * setzen, also muss der Server den Stream weiterreichen. Auf dem Schreibtisch
 * setzt ihn der Hauptprozess, und dann ist der Umweg nur einer — er kostet
 * Bandbreite auf einem fremden Rechner und macht aus einer `https:`-Adresse
 * eine `http:`-Adresse, die das Fenster nach seiner eigenen Richtlinie gar
 * nicht laden dürfte.
 */
class ServerGateway implements NoriGateway {
  constructor(private readonly base: string) {}

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
      throw new NoriError((body.kind as NoriError["kind"]) ?? "network", body.error ?? `HTTP ${res.status}`);
    }
    return body as T;
  }

  catalog(provider: CatalogProvider, force = false): Promise<CatalogResult> {
    return this.get<CatalogResult>(`/api/catalog/${provider}${force ? "?force=1" : ""}`);
  }

  series(provider: CatalogProvider, slug: string, season?: string | null): Promise<SeriesDetail> {
    const query = season ? `?season=${encodeURIComponent(season)}` : "";
    return this.get<SeriesDetail>(`/api/series/${provider}/${encodeURIComponent(slug)}${query}`);
  }

  watch(provider: CatalogProvider, path: string): Promise<WatchInfo> {
    return this.get<WatchInfo>(`/api/watch/${provider}?path=${encodeURIComponent(path)}`);
  }

  calendar(provider: CatalogProvider, force = false): Promise<CalendarPayload> {
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
    const body = (await res.json().catch(() => ({}))) as PlaySource & {
      error?: string; kind?: string;
    };
    if (!res.ok) {
      throw new NoriError((body.kind as NoriError["kind"]) ?? "hoster", body.error ?? `HTTP ${res.status}`);
    }
    // `playbackUrl` — die Weiterreichung des Servers — bleibt hier bewusst
    // liegen: siehe „Nur Auskunft, kein Durchreichen" oben.
    return { ...body, referer: body.referer ?? null };
  }

  playbackURL(source: PlaySource): string {
    return source.url;
  }

  imageURL(url: string): string {
    return url;
  }
}

let gateway: NoriGateway = direct;
let serverBase = "";

/** Eine Adresse wie `192.168.1.20:8730` auf `http://192.168.1.20:8730` bringen. */
function normalizeServerUrl(raw: string): string {
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

/**
 * Den Weg wählen. Das Fenster meldet ihn nach jeder Änderung der
 * Einstellungen; ohne Meldung gilt der direkte.
 */
export function configureGateway(mode: string, serverUrl: string): { mode: string; server: string } {
  const server = mode === "server" ? normalizeServerUrl(serverUrl) : "";
  if (server) {
    if (server !== serverBase) gateway = new ServerGateway(server);
    serverBase = server;
    return { mode: "server", server };
  }
  gateway = direct;
  serverBase = "";
  return { mode: "local", server: "" };
}

/**
 * Was ein Fehler dem Fenster erzählen darf.
 *
 * Über IPC kommt kein `Error` unverändert an — Electron serialisiert nur
 * einfache Werte. Damit die Oberfläche weiter zwischen „kein Netz" und „Hoster
 * kaputt" unterscheiden kann, geht die Art mit.
 */
export interface GatewayFailure {
  ok: false;
  kind: string;
  message: string;
}

export interface GatewaySuccess<T> {
  ok: true;
  value: T;
}

export type GatewayReply<T> = GatewaySuccess<T> | GatewayFailure;

async function attempt<T>(run: () => Promise<T>): Promise<GatewayReply<T>> {
  try {
    return { ok: true, value: await run() };
  } catch (cause) {
    if (cause instanceof NoriError) {
      return { ok: false, kind: cause.kind, message: cause.message };
    }
    return { ok: false, kind: "network", message: (cause as Error)?.message ?? "Unbekannter Fehler" };
  }
}

export const mainGateway = {
  catalog(provider: CatalogProvider, force: boolean): Promise<GatewayReply<CatalogResult>> {
    return attempt(() => gateway.catalog(provider, force));
  },
  series(provider: CatalogProvider, slug: string, season: string | null): Promise<GatewayReply<SeriesDetail>> {
    return attempt(() => gateway.series(provider, slug, season));
  },
  watch(provider: CatalogProvider, path: string): Promise<GatewayReply<WatchInfo>> {
    return attempt(() => gateway.watch(provider, path));
  },
  calendar(provider: CatalogProvider, force: boolean): Promise<GatewayReply<CalendarPayload>> {
    return attempt(() => gateway.calendar(provider, force));
  },
  resolve(request: ResolveRequest): Promise<GatewayReply<PlaySource>> {
    return attempt(() => gateway.resolve(request));
  },
};

/**
 * Ein einzelner Abruf für das Fenster — mit enger Leine.
 *
 * Gebraucht wird er für TMDB. Direkt ginge das im Fenster zwar (`https:`,
 * CORS-freundlich), über einen Nori-Server aber nicht: der spricht `http:` im
 * Heimnetz, und die Inhaltsrichtlinie des Fensters lässt das zu Recht nicht
 * zu. Statt zwei Wege zu pflegen, nimmt TMDB immer diesen.
 *
 * **Kein offener Weg ins Netz.** Erlaubt sind genau zwei Ziele: TMDB und der
 * eingetragene Nori-Server. Alles andere wird abgelehnt — das Fenster soll
 * über diesen Kanal nicht zu einem Werkzeug werden, mit dem sich ein
 * eingeschleustes Skript im Heimnetz umsieht.
 */
const TMDB_ORIGINS = new Set(["https://api.themoviedb.org", "https://image.tmdb.org"]);

function allowedTarget(url: string): boolean {
  try {
    const origin = new URL(url).origin;
    if (TMDB_ORIGINS.has(origin)) return true;
    return serverBase !== "" && origin === serverBase;
  } catch {
    return false;
  }
}

export interface HttpReply {
  status: number;
  url: string;
  headers: [string, string][];
  body: string;
}

export async function httpRequest(
  url: string,
  options: { headers?: Record<string, string> } = {},
): Promise<GatewayReply<HttpReply>> {
  if (!allowedTarget(url)) {
    return { ok: false, kind: "network", message: "Ziel nicht freigegeben" };
  }
  return attempt(async () => {
    const res = await http.request(url, { headers: options.headers });
    return {
      status: res.status,
      url: res.url,
      headers: [...res.headers.entries()] as [string, string][],
      body: await res.text(),
    };
  });
}
