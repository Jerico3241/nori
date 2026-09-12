// TMDB über den Nori-Server.
//
// ## Warum der Server das übernimmt
//
// Der Fernseher könnte TMDB selbst fragen — der Kern kann beides (siehe
// `DirectTMDBTransport`). Über den Server ist es trotzdem der bessere Weg:
//
// - **Ein Schlüssel statt einer je Gerät.** Wer drei Fernseher hat, trägt den
//   Schlüssel sonst dreimal ein, und jeder Umzug bedeutet dreimal Tippen mit
//   einer Fernbedienung.
// - **Ein Zwischenspeicher für alle.** Die Kennung zu „Frieren" ist auf jedem
//   Gerät dieselbe. Sie dreimal zu suchen sind zwei Anfragen zu viel.
// - **Eine Ratenbegrenzung statt mehrerer.** TMDB begrenzt je Schlüssel; ein
//   Katalogdurchlauf auf drei Geräten liefe sonst in dieselbe Grenze.
// - **Kein Schlüssel im `localStorage` eines Fernsehers.**
//
// ## Warum das kein offener Weiterreicher ist
//
// Der Pfad wird gegen eine Liste geprüft, nicht durchgereicht. Ohne diese
// Prüfung wäre `/api/tmdb/…` ein Zugang zu jedem TMDB-Endpunkt mit dem
// Schlüssel des Servers — einschließlich der schreibenden (Listen anlegen,
// Bewertungen abgeben). Was nicht auf der Liste steht, wird abgelehnt.
//
// Ebenso wird `api_key` aus den Anfrageparametern **entfernt**: sonst könnte
// ein Client einen fremden Schlüssel unterschieben und den Server als
// Verschleierung benutzen.

/** Der Schlüssel. Leer heißt: dieser Server kann kein TMDB. */
const KEY = (process.env.NORI_TMDB_KEY ?? process.env.TMDB_API_KEY ?? "").trim();

export function hasTMDBKey(): boolean {
  return KEY.length > 0;
}

/**
 * Die erlaubten Pfade, mit ihrer Gültigkeitsdauer in Millisekunden.
 *
 * Die Fristen richten sich danach, wie schnell sich die Antwort ändert: eine
 * Serienkennung ändert sich nie, der Wochentrend täglich. Bewusst großzügig —
 * ein Zwischenspeicher, der zu früh verfällt, ist einer, der nichts spart.
 */
const ROUTES: { pattern: RegExp; maxAge: number }[] = [
  { pattern: /^search\/tv$/, maxAge: 7 * 86_400_000 },
  { pattern: /^trending\/tv\/(day|week)$/, maxAge: 6 * 3_600_000 },
  { pattern: /^tv\/popular$/, maxAge: 3 * 86_400_000 },
  { pattern: /^discover\/tv$/, maxAge: 12 * 3_600_000 },
  { pattern: /^tv\/\d+$/, maxAge: 86_400_000 },
  { pattern: /^tv\/\d+\/(images|alternative_titles|external_ids)$/, maxAge: 7 * 86_400_000 },
  { pattern: /^tv\/\d+\/(recommendations|similar)$/, maxAge: 7 * 86_400_000 },
  { pattern: /^tv\/\d+\/season\/\d+$/, maxAge: 7 * 86_400_000 },
];

export function routeFor(path: string): { maxAge: number } | null {
  for (const route of ROUTES) {
    if (route.pattern.test(path)) return { maxAge: route.maxAge };
  }
  return null;
}

/**
 * Parameter, die weitergehen dürfen.
 *
 * Eine Liste und keine Sperrliste: TMDB kennt Parameter, die mehr tun als
 * filtern (`session_id` etwa), und eine Sperrliste müsste jeden davon kennen.
 */
const ALLOWED_PARAMS = new Set([
  "language", "query", "page", "include_adult", "include_image_language",
  "sort_by", "with_genres", "without_genres", "with_origin_country",
  "with_original_language", "with_status", "with_type", "first_air_date_year",
  "air_date.gte", "air_date.lte", "first_air_date.gte", "first_air_date.lte",
  "vote_count.gte", "vote_average.gte", "timezone", "region", "year",
]);

export function cleanParams(source: URLSearchParams): URLSearchParams {
  const out = new URLSearchParams();
  const names = Array.from(new Set(Array.from(source.keys()))).sort();
  for (const name of names) {
    if (!ALLOWED_PARAMS.has(name)) continue;
    const value = source.get(name);
    if (value === null || value.length > 200) continue;
    out.set(name, value);
  }
  return out;
}

interface Entry {
  body: string;
  status: number;
  expiresAt: number;
}

/**
 * Ein Zwischenspeicher im Arbeitsspeicher, kein Stapel auf der Platte.
 *
 * Der Dienst ist für das eigene Netz gedacht und läuft dort tagelang; ein
 * Neustart darf die Antworten wieder holen. Eine Datei dafür anzulegen wäre
 * Aufwand für den Fall, der ohnehin selten ist.
 */
const cache = new Map<string, Entry>();
const MAX_ENTRIES = 600;

/** Gleichzeitige Anfragen auf denselben Schlüssel teilen sich einen Abruf. */
const inflight = new Map<string, Promise<Entry>>();

export function cacheSize(): number {
  return cache.size;
}

export function clearTMDBCache(): void {
  cache.clear();
}

export interface TMDBProxyResult {
  status: number;
  body: string;
  /** Ob die Antwort aus dem Zwischenspeicher kam — für die Diagnose. */
  cached: boolean;
}

/**
 * Einen TMDB-Abruf beantworten.
 *
 * Wirft nie. Ein Fehler wird zur Antwort, weil der Client damit ohnehin
 * umgehen muss: für ihn ist TMDB Beiwerk, und eine fehlende Antwort darf keine
 * Ansicht in einen Fehlerzustand ziehen.
 */
export async function proxyTMDB(path: string, params: URLSearchParams): Promise<TMDBProxyResult> {
  const route = routeFor(path);
  if (!route) {
    return {
      status: 404,
      body: JSON.stringify({ error: `TMDB-Pfad nicht freigegeben: ${path}`, kind: "notFound" }),
      cached: false,
    };
  }
  if (!hasTMDBKey()) {
    // 503 und nicht 401: der Schlüssel fehlt hier, nicht beim Client. Das
    // `kind` macht daraus in der Oberfläche „Server hat keinen Schlüssel"
    // statt „nicht erreichbar".
    return {
      status: 503,
      body: JSON.stringify({
        error: "Dieser Nori-Server hat keinen TMDB-Schlüssel (NORI_TMDB_KEY).",
        kind: "noKey",
      }),
      cached: false,
    };
  }

  const clean = cleanParams(params);
  const key = `${path}?${clean.toString()}`;
  const now = Date.now();

  const known = cache.get(key);
  if (known && known.expiresAt > now) {
    return { status: known.status, body: known.body, cached: true };
  }

  const running = inflight.get(key);
  if (running) {
    const entry = await running;
    return { status: entry.status, body: entry.body, cached: true };
  }

  const task = fetchUpstream(path, clean, route.maxAge, known ?? null);
  inflight.set(key, task);
  let entry: Entry;
  try {
    entry = await task;
  } finally {
    inflight.delete(key);
  }

  // Nur brauchbare Antworten ablegen. Eine 429 zu speichern hieße, die
  // Ratenbegrenzung für Stunden festzuschreiben.
  if (entry.status === 200) {
    if (cache.size >= MAX_ENTRIES) {
      const oldest = cache.keys().next();
      if (!oldest.done) cache.delete(oldest.value);
    }
    cache.set(key, entry);
  }
  return { status: entry.status, body: entry.body, cached: false };
}

async function fetchUpstream(
  path: string,
  params: URLSearchParams,
  maxAge: number,
  stale: Entry | null,
): Promise<Entry> {
  const url = new URL(`https://api.themoviedb.org/3/${path}`);
  for (const [name, value] of params) url.searchParams.set(name, value);
  url.searchParams.set("api_key", KEY);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15_000);
  try {
    const res = await fetch(url.toString(), {
      headers: { Accept: "application/json" },
      signal: controller.signal,
    });
    const body = await res.text();
    if (res.status !== 200) {
      // Ein abgelaufener, aber vorhandener Stand ist besser als ein Fehler:
      // bei einer Ratenbegrenzung bleiben die Kacheln damit bebildert.
      if (stale) return { ...stale, expiresAt: Date.now() + 60_000 };
      return { status: res.status, body, expiresAt: 0 };
    }
    return { status: 200, body, expiresAt: Date.now() + maxAge };
  } catch (error) {
    if (stale) return { ...stale, expiresAt: Date.now() + 60_000 };
    const message = (error as Error)?.name === "AbortError"
      ? "TMDB antwortet nicht (Zeitüberschreitung)"
      : (error as Error)?.message ?? "TMDB nicht erreichbar";
    return {
      status: 502,
      body: JSON.stringify({ error: message, kind: "network" }),
      expiresAt: 0,
    };
  } finally {
    clearTimeout(timer);
  }
}
