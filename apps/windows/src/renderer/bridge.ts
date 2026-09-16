// Was das Fenster vom Programm sieht.
//
// `window.nori` kommt aus `src/main/preload.ts` und ist eine feste Liste von
// Aufrufen. Hier bekommt sie Typen und eine Form, mit der die gemeinsame
// Anwendungsschicht etwas anfangen kann: ein `NoriGateway` wie jedes andere.
//
// Die Oberfläche merkt vom Hauptprozess damit nichts. Sie ruft
// `gateway.series(...)` auf — ob das im Fenster, in einem Server oder einen
// Prozess weiter passiert, ist ihre Sache nicht.

import {
  NoriError, isTMDBImage, providerInfo,
  type CalendarPayload, type CatalogProvider, type CatalogResult, type FetchOptions,
  type HttpClient, type HttpResponse, type NoriGateway, type PlaySource,
  type ResolveRequest, type SeriesDetail, type WatchInfo,
} from "@nori/core";

interface Reply<T> {
  ok: boolean;
  value?: T;
  kind?: string;
  message?: string;
}

export interface GoogleStatus {
  configured: boolean;
  clientId: string;
  signedIn: boolean;
  scope: string;
  expiresAt: number | null;
}

/** Was der Hauptprozess von einem Abruf zurückgibt — IPC kennt kein `Response`. */
export interface HttpReply {
  status: number;
  url: string;
  headers: [string, string][];
  body: string;
}

export interface NoriBridge {
  gateway: {
    catalog(provider: string, force: boolean): Promise<Reply<CatalogResult>>;
    series(provider: string, slug: string, season: string | null): Promise<Reply<SeriesDetail>>;
    watch(provider: string, path: string): Promise<Reply<WatchInfo>>;
    calendar(provider: string, force: boolean): Promise<Reply<CalendarPayload>>;
    resolve(request: ResolveRequest): Promise<Reply<PlaySource>>;
    configure(mode: string, serverUrl: string): Promise<{ mode: string; server: string }>;
  };
  http: { request(url: string, headers?: Record<string, string>): Promise<Reply<HttpReply>> };
  stream: { prepare(url: string, referer: string | null): Promise<boolean> };
  google: {
    status(): Promise<GoogleStatus>;
    signIn(): Promise<{ ok: boolean; value?: GoogleStatus; message?: string }>;
    cancel(): Promise<GoogleStatus>;
    signOut(): Promise<GoogleStatus>;
    revoke(): Promise<GoogleStatus>;
    accessToken(): Promise<string | null>;
  };
  window: {
    minimize(): Promise<boolean>;
    toggleMaximize(): Promise<boolean>;
    close(): Promise<boolean>;
    toggleFullscreen(): Promise<boolean>;
    exitFullscreen(): Promise<boolean>;
    isFullscreen(): Promise<boolean>;
    onFullscreen(listener: (value: boolean) => void): () => void;
  };
  openExternal(url: string): Promise<boolean>;
  versions: {
    app: string;
    electron: string;
    chrome: string;
    node: string;
    platform: string;
    arch: string;
  };
}

declare global {
  interface Window {
    nori?: NoriBridge;
  }
}

/**
 * Läuft die Oberfläche im Nori-Fenster oder in einem gewöhnlichen Browser?
 *
 * Der Entwicklungsstand (`npm run dev`) läuft im Browser, und dort gibt es die
 * Brücke nicht. Die Oberfläche muss trotzdem stehen — sonst wäre jede Änderung
 * an ihr nur mit einem vollständigen Paket zu prüfen.
 */
export function inShell(): boolean {
  return typeof window !== "undefined" && window.nori !== undefined;
}

export function bridge(): NoriBridge | null {
  return typeof window === "undefined" ? null : window.nori ?? null;
}

function unwrap<T>(reply: Reply<T>): T {
  if (reply.ok && reply.value !== undefined) return reply.value;
  throw new NoriError((reply.kind as NoriError["kind"]) ?? "network", reply.message ?? "Unbekannter Fehler");
}

/**
 * Der Zugang über den Hauptprozess.
 *
 * Welchen Weg der nimmt — die Quellen selbst lesen oder einen Nori-Server
 * fragen —, steht hier nirgends: das meldet die Oberfläche einmal über
 * `gateway.configure`, und danach ist es die Sache des Hauptprozesses.
 *
 * Zwei Aufrufe von `NoriGateway` geben eine Adresse **sofort** zurück, nicht
 * als Zusage: `playbackURL` und `imageURL`. Über IPC ist aber alles eine
 * Zusage. Beide kommen deshalb ohne Rückfrage aus — und dürfen das, weil auf
 * dem Schreibtisch beide Antworten dieselbe sind: **die Adresse selbst**.
 *
 * Bild und Ton holt Nori hier immer direkt beim Hoster, auch wenn die Listen
 * von einem Nori-Server kommen. Was einem Fernseher fehlt, um das zu können,
 * hat ein Programm: den `Referer`. Der Hauptprozess setzt ihn, und `resolve`
 * und `imageURL` melden ihm vorher an, wofür.
 */
export class ShellGateway implements NoriGateway {
  constructor(private readonly api: NoriBridge) {}

  async catalog(provider: CatalogProvider, force = false): Promise<CatalogResult> {
    return unwrap(await this.api.gateway.catalog(provider, force));
  }

  async series(provider: CatalogProvider, slug: string, season?: string | null): Promise<SeriesDetail> {
    return unwrap(await this.api.gateway.series(provider, slug, season ?? null));
  }

  async watch(provider: CatalogProvider, path: string): Promise<WatchInfo> {
    return unwrap(await this.api.gateway.watch(provider, path));
  }

  async calendar(provider: CatalogProvider, force = false): Promise<CalendarPayload> {
    return unwrap(await this.api.gateway.calendar(provider, force));
  }

  async resolve(request: ResolveRequest): Promise<PlaySource> {
    const source = unwrap(await this.api.gateway.resolve(request));
    // Den `Referer` gleich hinterlegen: der Player ruft danach nur noch
    // `playbackURL` auf, und der erste Abruf kommt unmittelbar danach. Im
    // Serverbetrieb verwirft der Hauptprozess das — dort setzt er die
    // Kopfzeile selbst.
    await this.api.stream.prepare(source.url, source.referer ?? null);
    return source;
  }

  playbackURL(source: PlaySource): string {
    return source.url;
  }

  imageURL(url: string, provider: CatalogProvider): string {
    // TMDB liefert ohne Kopfzeile aus; die Cover der Quellen nicht.
    if (!isTMDBImage(url)) {
      void this.api.stream.prepare(url, `${providerInfo(provider).origin}/`);
    }
    return url;
  }
}

/**
 * Abrufe durch den Hauptprozess — für TMDB.
 *
 * Der Kern kennt seine Netzwerkschicht als `HttpClient` und fragt nicht, wer
 * dahintersteht. Hier steht der Hauptprozess dahinter, und der lässt nur TMDB
 * und den eingetragenen Nori-Server durch.
 *
 * `canReadRedirects` bleibt `false`: TMDB leitet nicht um, und eine Zusage
 * mehr über die Brücke würde daran nichts ändern.
 */
export class BridgeHttpClient implements HttpClient {
  readonly canReadRedirects = false;

  constructor(private readonly api: NoriBridge) {}

  async request(url: string, options: FetchOptions = {}): Promise<HttpResponse> {
    const reply = await this.api.http.request(url, options.headers);
    if (!reply.ok || !reply.value) {
      throw NoriError.network(reply.message ?? "Abruf fehlgeschlagen");
    }
    const { status, url: finalUrl, headers, body } = reply.value;
    return {
      status,
      url: finalUrl || url,
      headers: new Headers(headers),
      text: () => Promise.resolve(body),
    };
  }
}
