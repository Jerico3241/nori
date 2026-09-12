// Nori-Server: die Provider-Schicht als HTTP-Dienst.
//
// Warum es ihn gibt: iOS und macOS rufen AniWorld und Serienstream direkt ab
// und setzen dabei Kopfzeilen, die ein Browser nicht setzen darf — vor allem
// `Referer`, ohne den viele Hoster den Stream verweigern. Auf dem Fernseher
// läuft Nori aber in einem Browser. Dieser Dienst nimmt dem Client die Abrufe
// ab, benutzt dafür denselben `shared/nori-core` und reicht den Stream mit den
// nötigen Kopfzeilen weiter.
//
// Er ist bewusst klein: node:http, keine Laufzeitabhängigkeit außer `linkedom`
// für den HTML-Parser. Gedacht für das eigene Netz (Fernseher und Server im
// selben WLAN), nicht als öffentlicher Dienst.

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { Readable } from "node:stream";
import { parseHTML } from "linkedom";

import {
  CATALOG_PROVIDERS, DirectGateway, FetchHttpClient, NORI_USER_AGENT, NoriError,
  isSafeRemoteURL, setHtmlParser,
  type CatalogProvider, type HosterOption,
} from "@nori/core";
import { rewriteM3U8 } from "./playlist.js";
import { cacheSize, clearTMDBCache, hasTMDBKey, proxyTMDB, tmdbKeyOrigin } from "./tmdb.js";

setHtmlParser((html: string) => parseHTML(html).document as unknown as Document);

/**
 * Die Version dieses Dienstes.
 *
 * Sie steht in der Antwort von `/api/health`, und der Fernseher zeigt sie in
 * den Einstellungen unter „Server: erreichbar (Version …)". Damit lässt sich
 * von der Couch aus sehen, ob der Server alt ist — etwa einer ohne
 * `/api/tmdb`.
 */
export const API_VERSION = "1.3.1";

const PORT = Number(process.env.NORI_API_PORT ?? process.env.PORT ?? 8730);
const HOST = process.env.NORI_API_HOST ?? "0.0.0.0";

// Node kann `Location` selbst auswerten; genau darauf beruht die
// Weiterleitungsverfolgung im Resolver.
const http = new FetchHttpClient({ canReadRedirects: true, timeoutMs: 25_000 });
const gateway = new DirectGateway(http);

function isProvider(value: string): value is CatalogProvider {
  return (CATALOG_PROVIDERS as string[]).includes(value);
}

function send(res: ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    ...corsHeaders(),
  });
  res.end(payload);
}

function corsHeaders(): Record<string, string> {
  // Der Fernseher lädt die App von `file://` und schickt damit `Origin: null`.
  // Eine Einschränkung auf bestimmte Ursprünge wäre hier reine Zierde.
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
  };
}

function fail(res: ServerResponse, error: unknown): void {
  if (error instanceof NoriError) {
    const status = error.kind === "notFound" ? 404 : error.kind === "network" ? 502 : 500;
    send(res, status, { error: error.message, kind: error.kind });
    return;
  }
  send(res, 500, { error: (error as Error)?.message ?? "Unbekannter Fehler", kind: "network" });
}

async function readBody(req: IncomingMessage, limit = 512 * 1024): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > limit) throw NoriError.parse("Anfrage zu groß");
    chunks.push(chunk as Buffer);
  }
  if (chunks.length === 0) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
  } catch {
    throw NoriError.parse("Ungültiges JSON");
  }
}

/**
 * Weiterreichen von Medien und Bildern.
 *
 * Die Prüfung `isSafeRemoteURL` ist hier nicht optional: ohne sie wäre der
 * Dienst ein offener Zugang zu allem, was vom Server aus erreichbar ist. Sie
 * kommt aus dem Kern und ist dieselbe, die auch die Apple-Apps benutzen.
 */
async function proxy(
  req: IncomingMessage,
  res: ServerResponse,
  target: string,
  referer: string | null,
  rewritePlaylist: boolean,
): Promise<void> {
  if (!isSafeRemoteURL(target)) {
    send(res, 400, { error: "Unsichere Zieladresse", kind: "hoster" });
    return;
  }
  const headers: Record<string, string> = {
    "User-Agent": NORI_USER_AGENT,
    Accept: "*/*",
  };
  if (referer) {
    headers.Referer = referer;
    try {
      headers.Origin = new URL(referer).origin;
    } catch {
      /* ohne Origin */
    }
  }
  const range = req.headers.range;
  if (typeof range === "string") headers.Range = range;

  const upstream = await fetch(target, { headers, redirect: "follow" });
  const contentType = upstream.headers.get("content-type") ?? "application/octet-stream";
  const isPlaylist = rewritePlaylist
    && (contentType.includes("mpegurl") || new URL(target).pathname.toLowerCase().endsWith(".m3u8"));

  if (isPlaylist) {
    const text = await upstream.text();
    const body = rewriteM3U8(text, upstream.url || target, referer);
    res.writeHead(upstream.status, {
      "Content-Type": "application/vnd.apple.mpegurl",
      "Cache-Control": "no-store",
      ...corsHeaders(),
    });
    res.end(body);
    return;
  }

  const out: Record<string, string> = {
    "Content-Type": contentType,
    ...corsHeaders(),
  };
  for (const key of ["content-length", "content-range", "accept-ranges", "cache-control"]) {
    const value = upstream.headers.get(key);
    if (value) out[key] = value;
  }
  res.writeHead(upstream.status, out);
  if (!upstream.body) {
    res.end();
    return;
  }
  Readable.fromWeb(upstream.body as Parameters<typeof Readable.fromWeb>[0]).pipe(res);
}

async function handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
  const path = url.pathname.replace(/\/+$/, "") || "/";

  if (req.method === "OPTIONS") {
    res.writeHead(204, corsHeaders());
    res.end();
    return;
  }

  if (path === "/" || path === "/api" || path === "/api/health") {
    send(res, 200, {
      name: "nori-api",
      version: API_VERSION,
      providers: CATALOG_PROVIDERS,
      // Woran ein Client erkennt, was dieser Server kann. Ohne das müsste der
      // Fernseher einen TMDB-Abruf wagen, um zu erfahren, ob er einen wagen
      // kann.
      features: {
        tmdb: hasTMDBKey(),
        // „own", wenn NORI_TMDB_KEY gesetzt ist, sonst „builtIn". Der
        // Fernseher zeigt das in den Einstellungen an — den Schlüssel selbst
        // gibt der Dienst nie heraus.
        tmdbKey: tmdbKeyOrigin(),
        tmdbCacheEntries: cacheSize(),
      },
      endpoints: [
        "/api/catalog/:provider",
        "/api/series/:provider/:slug?season=",
        "/api/watch/:provider?path=",
        "/api/calendar/:provider",
        "POST /api/resolve",
        "/api/stream?u=&r=",
        "/api/image?u=",
        "/api/tmdb/*",
      ],
    });
    return;
  }

  const segments = path.split("/").filter(Boolean);

  if (segments[0] !== "api") {
    send(res, 404, { error: "Unbekannter Pfad", kind: "notFound" });
    return;
  }

  try {
    switch (segments[1]) {
      case "catalog": {
        const provider = segments[2] ?? "";
        if (!isProvider(provider)) throw NoriError.notFound("Unbekannte Quelle");
        const force = url.searchParams.get("force") === "1";
        send(res, 200, await gateway.catalog(provider, force));
        return;
      }
      case "series": {
        const provider = segments[2] ?? "";
        const slug = segments[3] ?? "";
        if (!isProvider(provider)) throw NoriError.notFound("Unbekannte Quelle");
        if (!slug) throw NoriError.parse("Kein Slug angegeben");
        const season = url.searchParams.get("season");
        send(res, 200, await gateway.series(provider, decodeURIComponent(slug), season));
        return;
      }
      case "watch": {
        const provider = segments[2] ?? "";
        if (!isProvider(provider)) throw NoriError.notFound("Unbekannte Quelle");
        const episodePath = url.searchParams.get("path") ?? "";
        if (!episodePath) throw NoriError.parse("Kein Pfad angegeben");
        send(res, 200, await gateway.watch(provider, episodePath));
        return;
      }
      case "calendar": {
        const provider = segments[2] ?? "";
        if (!isProvider(provider)) throw NoriError.notFound("Unbekannte Quelle");
        const force = url.searchParams.get("force") === "1";
        send(res, 200, await gateway.calendar(provider, force));
        return;
      }
      case "resolve": {
        if (req.method !== "POST") throw NoriError.parse("Nur POST");
        const body = (await readBody(req)) as {
          provider?: string;
          episodePath?: string;
          hosters?: HosterOption[];
          pick?: HosterOption;
          preferredHoster?: string;
          preferredLang?: string;
          skip?: string[];
        };
        const provider = body.provider ?? "";
        if (!isProvider(provider)) throw NoriError.notFound("Unbekannte Quelle");
        const source = await gateway.resolve({
          provider,
          episodePath: body.episodePath ?? "",
          hosters: Array.isArray(body.hosters) ? body.hosters : [],
          pick: body.pick,
          preferredHoster: body.preferredHoster,
          preferredLang: body.preferredLang,
          skip: body.skip,
        });
        // Die Adresse, die der Client tatsächlich lädt: über diesen Dienst,
        // damit der `Referer` mitgeht.
        const params = new URLSearchParams({ u: source.url });
        if (source.referer) params.set("r", source.referer);
        send(res, 200, { ...source, playbackUrl: `/api/stream?${params.toString()}` });
        return;
      }
      case "stream": {
        const target = url.searchParams.get("u");
        if (!target) throw NoriError.parse("Keine Adresse angegeben");
        await proxy(req, res, target, url.searchParams.get("r"), true);
        return;
      }
      case "image": {
        const target = url.searchParams.get("u");
        if (!target) throw NoriError.parse("Keine Adresse angegeben");
        await proxy(req, res, target, url.searchParams.get("r"), false);
        return;
      }
      case "tmdb": {
        // Der Rest des Pfades ist der TMDB-Pfad. Er wird in `proxyTMDB` gegen
        // eine Liste geprüft, nicht durchgereicht — siehe src/tmdb.ts.
        const tmdbPath = segments.slice(2).join("/");
        if (!tmdbPath) throw NoriError.parse("Kein TMDB-Pfad angegeben");
        if (req.method === "DELETE") {
          clearTMDBCache();
          send(res, 200, { cleared: true });
          return;
        }
        const result = await proxyTMDB(tmdbPath, url.searchParams);
        res.writeHead(result.status, {
          "Content-Type": "application/json; charset=utf-8",
          // Der Client hat seinen eigenen Zwischenspeicher; dieser hier ist
          // der gemeinsame. Ein zusätzlicher im Browser des Fernsehers würde
          // nur die Frage aufwerfen, welcher der beiden gilt.
          "Cache-Control": "no-store",
          "X-Nori-TMDB-Cache": result.cached ? "hit" : "miss",
          ...corsHeaders(),
        });
        res.end(result.body);
        return;
      }
      default:
        send(res, 404, { error: "Unbekannter Pfad", kind: "notFound" });
    }
  } catch (error) {
    if (!res.headersSent) fail(res, error);
    else res.end();
  }
}

const server = createServer((req, res) => {
  void handle(req, res).catch((error: unknown) => {
    if (!res.headersSent) fail(res, error);
    else res.end();
  });
});

server.listen(PORT, HOST, () => {
  console.log(`[Nori:api] hört auf http://${HOST}:${PORT}`);
});
