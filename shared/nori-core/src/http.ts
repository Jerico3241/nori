// Die einzige Netzwerkschicht des Kerns.
//
// Absichtlich klein und austauschbar: auf dem Fernseher ist das `fetch` des
// Browsers, im Nori-Server das von Node. Wo sich beide unterscheiden — vor
// allem beim Umgang mit Weiterleitungen — steht das hier an einer Stelle und
// nicht in jedem Aufrufer.

import { NORI_USER_AGENT, NoriError } from "./models.js";

export interface FetchOptions {
  headers?: Record<string, string>;
  /** `manual` heißt: die 3xx-Antwort selbst auswerten, nicht folgen. */
  redirect?: "follow" | "manual";
  signal?: AbortSignal;
}

export interface HttpResponse {
  status: number;
  /** Die tatsächlich angesteuerte Adresse — nach allen gefolgten Weiterleitungen. */
  url: string;
  headers: Headers;
  text(): Promise<string>;
}

export interface HttpClient {
  request(url: string, options?: FetchOptions): Promise<HttpResponse>;
  /** Kann diese Laufzeit Weiterleitungen selbst auswerten (`redirect: "manual"`)? */
  readonly canReadRedirects: boolean;
}

export interface FetchHttpClientOptions {
  fetchImpl?: typeof fetch;
  /** Node kann die `Location`-Kopfzeile lesen, ein Browser nicht. */
  canReadRedirects?: boolean;
  timeoutMs?: number;
  /**
   * Wird jeder Anfrage vorangestellt. Der webOS-Client setzt hier den
   * Nori-Server ein, damit die Quellen nicht direkt vom Fernseher abgerufen
   * werden müssen.
   */
  rewrite?: (url: string) => string;
}

export class FetchHttpClient implements HttpClient {
  readonly canReadRedirects: boolean;
  private readonly fetchImpl: typeof fetch;
  private readonly timeoutMs: number;
  private readonly rewrite?: (url: string) => string;

  constructor(options: FetchHttpClientOptions = {}) {
    const impl = options.fetchImpl ?? globalThis.fetch;
    if (!impl) throw new Error("Keine fetch-Umsetzung vorhanden.");
    this.fetchImpl = impl.bind(globalThis);
    this.canReadRedirects = options.canReadRedirects ?? false;
    this.timeoutMs = options.timeoutMs ?? 20_000;
    this.rewrite = options.rewrite;
  }

  async request(url: string, options: FetchOptions = {}): Promise<HttpResponse> {
    const target = this.rewrite ? this.rewrite(url) : url;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    const signal = options.signal
      ? anySignal([options.signal, controller.signal])
      : controller.signal;
    try {
      const res = await this.fetchImpl(target, {
        headers: options.headers,
        redirect: options.redirect ?? "follow",
        signal,
      });
      return {
        status: res.status,
        url: res.url || target,
        headers: res.headers,
        text: () => res.text(),
      };
    } catch (error) {
      if ((error as Error)?.name === "AbortError") {
        throw NoriError.network("Zeitüberschreitung");
      }
      throw NoriError.network((error as Error)?.message ?? "Netzwerkfehler");
    } finally {
      clearTimeout(timer);
    }
  }
}

/** `AbortSignal.any` gibt es erst ab Chromium 116; webOS 6 hat es nicht. */
function anySignal(signals: AbortSignal[]): AbortSignal {
  const controller = new AbortController();
  for (const signal of signals) {
    if (signal.aborted) {
      controller.abort();
      break;
    }
    signal.addEventListener("abort", () => controller.abort(), { once: true });
  }
  return controller.signal;
}

export const BROWSE_HEADERS: Record<string, string> = {
  "User-Agent": NORI_USER_AGENT,
  Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  "Accept-Language": "de-DE,de;q=0.9,en;q=0.8",
};
