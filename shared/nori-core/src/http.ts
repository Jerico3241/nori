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
      throw NoriError.network(describeNetworkError(error, target));
    } finally {
      clearTimeout(timer);
    }
  }
}

/** Nur der Name des Rechners — nie die Abfrage, die dahinter steht. */
function hostOf(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return "Die Quelle";
  }
}

/**
 * Was wirklich schiefging.
 *
 * Nodes `fetch` meldet **jeden** Verbindungsfehler als „fetch failed" und
 * hängt den Grund in `cause`. In der Oberfläche stand damit ein Satz, der
 * nichts sagt — und der Unterschied zwischen „die Adresse ist nicht
 * auflösbar" und „niemand nimmt ab" ist genau der, den jemand zum
 * Weiterkommen braucht. Auf dem Schreibtisch ist das der Regelfall: dort
 * ruft Nori die Quellen selbst ab, und wenn der Internetanbieter ihre
 * Adressen sperrt, sieht der Nutzer sonst nur „fetch failed".
 *
 * Im Browser gibt es `cause` nicht; dort bleibt es bei der Meldung, die
 * ohnehin schon deutlicher ist.
 */
export function describeNetworkError(error: unknown, url: string): string {
  const message = (error as Error)?.message ?? "Netzwerkfehler";
  const cause = (error as { cause?: { code?: string; message?: string } })?.cause;
  if (!cause) return message;
  const host = hostOf(url);
  // Ein Grund ohne Kennung ist immer noch ein Grund — „bad port" sagt mehr
  // als „fetch failed".
  if (!cause.code) return cause.message ? `${host}: ${cause.message}` : message;
  const code = cause.code;

  switch (code) {
    case "ENOTFOUND":
    case "EAI_AGAIN":
      return `${host} ist nicht auflösbar. Häufig sperrt der Internetanbieter `
        + "die Adresse im DNS — ein anderer DNS-Server oder ein VPN hilft dann.";
    case "ECONNREFUSED":
      return `${host} nimmt keine Verbindung an.`;
    case "ECONNRESET":
    case "UND_ERR_SOCKET":
      return `${host} hat die Verbindung abgebrochen.`;
    case "ETIMEDOUT":
    case "UND_ERR_CONNECT_TIMEOUT":
      return `${host} antwortet nicht.`;
    case "EPROTO":
    case "ERR_TLS_CERT_ALTNAME_INVALID":
    case "UNABLE_TO_VERIFY_LEAF_SIGNATURE":
    case "CERT_HAS_EXPIRED":
      return `Die gesicherte Verbindung zu ${host} kam nicht zustande (${code}).`;
    default:
      return `${host}: ${cause?.message ?? code}`;
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
