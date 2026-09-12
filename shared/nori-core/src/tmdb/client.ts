// Der Zugang zu TMDB.
//
// ## Was diese Datei zusagt
//
// **Sie wirft nie.** Kein fehlender Schlüssel, kein 401, kein 429, kein
// Netzfehler und keine unerwartete Antwort verlässt diese Datei als Ausnahme.
// Jeder Weg endet in einem leeren Ergebnis plus Befund (`TMDBStatus`). Der
// Grund ist der Normalbetrieb: TMDB ist in Nori **Beiwerk**. Ohne TMDB zeigt
// die App die Daten der Quellen — das ist ein gültiger Zustand, kein Fehler,
// und er darf keine Ansicht in einen Fehlerzustand ziehen.
//
// ## Zwei Wege zu denselben Daten
//
//     DirectTMDBTransport  — der Client fragt api.themoviedb.org selbst. Ohne
//                            eingetragenen Schlüssel mit dem mitgelieferten
//                            (siehe `key.ts`), also immer verfügbar.
//     ServerTMDBTransport  — der Client fragt den Nori-Server, der den
//                            Schlüssel hält und Antworten zwischenspeichert.
//
// Für den Fernseher ist der zweite der bessere: der Zwischenspeicher gilt dann
// für alle Geräte gemeinsam, und die Ratenbegrenzung von TMDB wird einmal
// statt je Fernseher ausgeschöpft. Beide brauchen aber **keine** Einrichtung —
// auf einem Fernseher gibt es keine Tastatur, und eine App, die vor dem ersten
// Bild einen 32-stelligen Schlüssel verlangt, zeigt nie ein Bild.

import type { HttpClient } from "../http.js";
import type { CatalogProvider } from "../models.js";
import { tmdbImageURL } from "./images.js";
import { resolveTmdbKey, type TMDBKeyOrigin } from "./key.js";
import {
  bestCandidate, candidateFromRow, searchQueries, tmdbDate,
  type TMDBCandidate,
} from "./matcher.js";
import type { TMDBEpisodeInfo, TMDBSeasonRef } from "./seasons.js";

/** Wie ein Abruf ausgegangen ist. Für die Diagnose in den Einstellungen. */
export type TMDBStatus =
  /** Antwort mit brauchbarem Inhalt. */
  | "ok"
  /** Kein Zugang eingerichtet — es wurde gar nicht gefragt. */
  | "noKey"
  /** 401 oder 403: der Schlüssel stimmt nicht oder darf das nicht. */
  | "unauthorized"
  /** 404: die Kennung gibt es dort nicht. */
  | "notFound"
  /** 429: Ratenbegrenzung. */
  | "rateLimited"
  /** Netzfehler, Zeitüberschreitung oder unlesbare Antwort. */
  | "unavailable";

export interface TMDBReply {
  status: TMDBStatus;
  body: Record<string, unknown> | null;
}

const EMPTY: TMDBReply = { status: "unavailable", body: null };

export interface TMDBTransport {
  /** Ein Abruf auf einen TMDB-Pfad ohne führenden Schrägstrich. */
  get(path: string, params: Record<string, string>): Promise<TMDBReply>;
  /** Steht überhaupt ein Zugang bereit? Ohne ihn wird nicht gefragt. */
  readonly available: boolean;
}

function statusFor(code: number): TMDBStatus {
  if (code === 200) return "ok";
  if (code === 401 || code === 403) return "unauthorized";
  if (code === 404) return "notFound";
  if (code === 429) return "rateLimited";
  return "unavailable";
}

async function readJSON(http: HttpClient, url: string): Promise<TMDBReply> {
  try {
    const res = await http.request(url, { headers: { Accept: "application/json" } });
    const status = statusFor(res.status);
    if (status !== "ok") return { status, body: null };
    const text = await res.text();
    try {
      const parsed = JSON.parse(text) as unknown;
      if (!parsed || typeof parsed !== "object") return { status: "unavailable", body: null };
      return { status: "ok", body: parsed as Record<string, unknown> };
    } catch {
      // Eine Antwort mit HTTP 200 und kaputtem JSON gibt es: Zwangsportale in
      // Hotelnetzen antworten mit ihrer eigenen Seite.
      return { status: "unavailable", body: null };
    }
  } catch {
    return EMPTY;
  }
}

/**
 * Fragt api.themoviedb.org direkt.
 *
 * Ohne eigenen Schlüssel mit dem mitgelieferten — siehe `key.ts`. Dieser Weg
 * ist damit immer verfügbar, und `available` ist hier nie `false`. Wer TMDB
 * nicht will, benutzt `NoTMDBTransport`; das ist eine Entscheidung, kein
 * Mangel an Einrichtung.
 */
export class DirectTMDBTransport implements TMDBTransport {
  private readonly key: string;
  /** Ob der Schlüssel eingetragen oder mitgeliefert ist. Für die Anzeige. */
  readonly keyOrigin: TMDBKeyOrigin;
  private readonly http: HttpClient;

  constructor(key: string, http: HttpClient) {
    const resolved = resolveTmdbKey(key);
    this.key = resolved.key;
    this.keyOrigin = resolved.origin;
    this.http = http;
  }

  get available(): boolean {
    return this.key.length > 0;
  }

  async get(path: string, params: Record<string, string>): Promise<TMDBReply> {
    if (!this.available) return { status: "noKey", body: null };
    const url = new URL(`https://api.themoviedb.org/3/${path}`);
    url.searchParams.set("api_key", this.key);
    for (const [name, value] of Object.entries(params)) url.searchParams.set(name, value);
    return readJSON(this.http, url.toString());
  }
}

/**
 * Fragt den Nori-Server, der den Schlüssel hält.
 *
 * Der Pfad wird unverändert durchgereicht (`/api/tmdb/<pfad>`); der Server
 * hängt den Schlüssel an und antwortet mit dem Körper von TMDB. Er antwortet
 * mit 503 und `{ kind: "noKey" }`, wenn dort keiner eingetragen ist — dann
 * steht in der Oberfläche „Server hat keinen Schlüssel" statt „nicht
 * erreichbar".
 */
export class ServerTMDBTransport implements TMDBTransport {
  private readonly base: string;
  private readonly http: HttpClient;

  constructor(baseUrl: string, http: HttpClient) {
    this.base = baseUrl.replace(/\/+$/, "");
    this.http = http;
  }

  get available(): boolean {
    return this.base.length > 0;
  }

  async get(path: string, params: Record<string, string>): Promise<TMDBReply> {
    if (!this.available) return { status: "noKey", body: null };
    const url = new URL(`${this.base}/api/tmdb/${path}`);
    for (const [name, value] of Object.entries(params)) url.searchParams.set(name, value);
    const reply = await readJSON(this.http, url.toString());
    // Der Server unterscheidet „ich habe keinen Schlüssel" von „TMDB mag
    // nicht". Ohne diese Umdeutung stünde beides als „nicht erreichbar" da.
    if (reply.status !== "ok" && reply.body === null) return reply;
    if (reply.body && reply.body.kind === "noKey") return { status: "noKey", body: null };
    return reply;
  }
}

/** Nichts abrufen. Der Zustand ohne TMDB — ausdrücklich, nicht als Unfall. */
export class NoTMDBTransport implements TMDBTransport {
  readonly available = false;

  async get(): Promise<TMDBReply> {
    return { status: "noKey", body: null };
  }
}

function rows(body: Record<string, unknown> | null, field = "results"): unknown[] {
  if (!body) return [];
  const value = body[field];
  return Array.isArray(value) ? value : [];
}

function candidates(body: Record<string, unknown> | null, field = "results"): TMDBCandidate[] {
  const out: TMDBCandidate[] = [];
  for (const row of rows(body, field)) {
    const candidate = candidateFromRow(row);
    if (candidate) out.push(candidate);
  }
  return out;
}

/** Die Ranglisten, aus denen „Neu & beliebt" und der Kopfbereich entstehen. */
export type TMDBFeed =
  /** Was diese Woche gesucht wird. Das aktuellste Signal, das TMDB hat. */
  | "trendingWeek"
  /** Dauerhaft beliebte Serien. */
  | "popular"
  /** Zeichentrick aus Japan, nach Beliebtheit. */
  | "animePopular"
  /** Serien mit Folgen aus den letzten Wochen. */
  | "airingRecently"
  /** Anime mit Folgen aus den letzten Wochen. */
  | "animeAiringRecently";

export const TMDB_FEEDS: TMDBFeed[] = [
  "trendingWeek", "popular", "animePopular", "airingRecently", "animeAiringRecently",
];

/**
 * Wie lange eine Liste gilt, in Millisekunden.
 *
 * Der Trend wechselt täglich, die Dauerliste kaum. Kürzere Fristen brächten
 * nichts außer Anfragen: TMDB rechnet den Trend selbst nur einmal am Tag neu.
 */
export function feedMaxAge(feed: TMDBFeed): number {
  switch (feed) {
    case "trendingWeek": return 6 * 3_600_000;
    case "airingRecently":
    case "animeAiringRecently": return 12 * 3_600_000;
    default: return 3 * 86_400_000;
  }
}

/** Wie viele Seiten zu je zwanzig Zeilen. */
export function feedPages(feed: TMDBFeed): number {
  return feed === "trendingWeek" ? 2 : 2;
}

function feedPath(feed: TMDBFeed): string {
  switch (feed) {
    case "trendingWeek": return "trending/tv/week";
    case "popular": return "tv/popular";
    default: return "discover/tv";
  }
}

function isoDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/**
 * Die zusätzlichen Parameter einer Liste.
 *
 * `with_genres=16` ist bei TMDB „Animation", `with_origin_country=JP` grenzt es
 * auf japanische Produktionen ein — zusammen ist das die brauchbarste Näherung
 * an „Anime", die die Schnittstelle hergibt. Eine eigene Anime-Kennung gibt es
 * dort nicht.
 */
function feedQuery(feed: TMDBFeed, now: number): Record<string, string> {
  const from = isoDay(now - 45 * 86_400_000);
  const to = isoDay(now);
  switch (feed) {
    case "trendingWeek":
    case "popular":
      return {};
    case "animePopular":
      return { with_genres: "16", with_origin_country: "JP", sort_by: "popularity.desc" };
    case "airingRecently":
      return {
        "air_date.gte": from,
        "air_date.lte": to,
        sort_by: "popularity.desc",
        "vote_count.gte": "20",
      };
    case "animeAiringRecently":
      return {
        with_genres: "16",
        with_origin_country: "JP",
        "air_date.gte": from,
        "air_date.lte": to,
        sort_by: "popularity.desc",
      };
  }
}

export interface SeriesDetails {
  candidate: TMDBCandidate;
  seasons: TMDBSeasonRef[];
  lastAirDate: number | null;
  /** TMDBs `status`: „Returning Series", „Ended", „Canceled". */
  seriesStatus: string | null;
  /** Laufzeit einer Folge in Minuten, sofern TMDB sie führt. */
  episodeRuntime: number | null;
  homepage: string | null;
}

export interface FindResult {
  candidate: TMDBCandidate;
  /** Welcher der Suchbegriffe getroffen hat — fürs Protokoll. */
  query: string;
  /**
   * Ob der Treffer erst über die Alternativtitel von TMDB zustande kam. Für
   * das Diagnoseprotokoll: diese Treffer sind die, die früher fehlten.
   */
  viaAlternates: boolean;
}

/**
 * Die Abrufe, die Nori von TMDB braucht.
 *
 * Der Client ist zustandslos: kein Zwischenspeicher, keine Sperren, keine
 * Bündelung. Das gehört in den Client der Plattform (auf dem Fernseher in
 * `services/tmdb.ts`), weil nur der weiß, wo ein Fernseher etwas ablegen darf
 * und wie viele Abrufe er gleichzeitig verträgt.
 */
export class TMDBClient {
  private readonly transport: TMDBTransport;
  private readonly language: string;

  constructor(transport: TMDBTransport, language = "de-DE") {
    this.transport = transport;
    this.language = language;
  }

  get available(): boolean {
    return this.transport.available;
  }

  /** Eine einzelne Suche. */
  async search(query: string): Promise<{ rows: TMDBCandidate[]; status: TMDBStatus }> {
    const reply = await this.transport.get("search/tv", {
      language: this.language,
      query,
      include_adult: "false",
    });
    return { rows: candidates(reply.body), status: reply.status };
  }

  /**
   * Die Serie zu einem Nori-Titel finden.
   *
   * Geht die Suchbegriffe aus `searchQueries` in absteigender Güte durch und
   * hört beim ersten Treffer über der Titelschwelle auf. Gibt `null` zurück,
   * wenn keiner passt — **das ist eine Antwort**: lieber kein Treffer als der
   * einer fremden Serie.
   */
  async findSeries(input: {
    title: string;
    alternates?: string[];
    provider: CatalogProvider;
    expectedYear?: number | null;
    requirePoster?: boolean;
    /**
     * Bei einem Fehlschlag noch die Alternativtitel des besten TMDB-Vorschlags
     * prüfen. Siehe `findViaAlternates` — ein zusätzlicher Abruf, aber nur bei
     * einem Titel, der sonst gar keinen Treffer hätte.
     */
    useAlternateTitles?: boolean;
  }): Promise<{ result: FindResult | null; status: TMDBStatus }> {
    const queries = searchQueries(input.title, input.alternates ?? []);
    let status: TMDBStatus = this.transport.available ? "unavailable" : "noKey";
    /** Der oberste Vorschlag von TMDB zum genauesten Begriff. */
    let topSuggestion: { candidate: TMDBCandidate; query: string } | null = null;

    for (const query of queries) {
      const { rows: found, status: replyStatus } = await this.search(query);
      status = replyStatus;
      // Ein ungültiger Schlüssel oder eine Ratenbegrenzung wird nicht durch
      // weitere Begriffe besser — das wären nur zusätzliche 401.
      if (replyStatus === "unauthorized" || replyStatus === "rateLimited") {
        return { result: null, status };
      }
      if (found.length === 0) continue;
      if (!topSuggestion) topSuggestion = { candidate: found[0], query };
      const best = bestCandidate(found, query, {
        kind: input.provider,
        expectedYear: input.expectedYear ?? null,
        requirePoster: input.requirePoster ?? false,
      });
      if (best) return { result: { candidate: best, query, viaAlternates: false }, status: "ok" };
    }

    if ((input.useAlternateTitles ?? true) && topSuggestion) {
      const verified = await this.findViaAlternates(topSuggestion.candidate, queries, input);
      if (verified) return { result: verified, status: "ok" };
    }
    return { result: null, status };
  }

  /**
   * Einen Fehlschlag über die Alternativtitel von TMDB retten.
   *
   * ## Der Fall, um den es geht
   *
   * AniWorld führt „Sousou no Frieren", TMDB heißt der Eintrag „Frieren:
   * Beyond Journey's End". Die Titelnähe ist damit null — kein gemeinsames
   * Wort, keine Enthaltung. TMDBs **eigene** Suche findet den Eintrag
   * trotzdem, sie sucht unscharf und über alle Schreibweisen.
   *
   * Diesen Vorschlag einfach zu übernehmen, wäre genau der Fehler, den
   * `TITLE_FLOOR` verhindert: TMDB liefert auch zu „Frieren" die erstbeste
   * Serie, wenn es die richtige nicht führt. Deshalb wird stattdessen die
   * **Datenlage verbessert und dieselbe Schwelle erneut angelegt**: die
   * Alternativtitel des Vorschlags werden nachgeladen und der Kandidat damit
   * neu bewertet. „Sousou no Frieren" steht dort — der Treffer entsteht also
   * weiter über einen Titelabgleich, nicht über Vertrauen.
   *
   * Kostet einen Abruf, und nur bei einem Titel, der sonst leer bliebe.
   */
  private async findViaAlternates(
    suggestion: TMDBCandidate,
    queries: string[],
    input: {
      provider: CatalogProvider;
      expectedYear?: number | null;
      requirePoster?: boolean;
    },
  ): Promise<FindResult | null> {
    const { titles } = await this.alternativeTitles(suggestion.id);
    if (titles.length === 0) return null;
    const enriched: TMDBCandidate = {
      ...suggestion,
      alternateNames: [...suggestion.alternateNames, ...titles],
    };
    for (const query of queries) {
      const best = bestCandidate([enriched], query, {
        kind: input.provider,
        expectedYear: input.expectedYear ?? null,
        requirePoster: input.requirePoster ?? false,
      });
      if (best) return { candidate: best, query, viaAlternates: true };
    }
    return null;
  }

  /** `/tv/{id}` — Staffelliste, letzte Ausstrahlung, Status. */
  async series(id: number): Promise<{ details: SeriesDetails | null; status: TMDBStatus }> {
    const reply = await this.transport.get(`tv/${id}`, { language: this.language });
    if (!reply.body) return { details: null, status: reply.status };
    const candidate = candidateFromRow(reply.body);
    if (!candidate) return { details: null, status: "unavailable" };

    const seasons: TMDBSeasonRef[] = [];
    for (const row of rows(reply.body, "seasons")) {
      if (!row || typeof row !== "object") continue;
      const raw = row as Record<string, unknown>;
      const seasonNumber = typeof raw.season_number === "number" ? raw.season_number : null;
      if (seasonNumber === null) continue;
      seasons.push({
        seasonNumber,
        episodeCount: typeof raw.episode_count === "number" ? raw.episode_count : 0,
        name: typeof raw.name === "string" ? raw.name : null,
        airDate: typeof raw.air_date === "string" ? raw.air_date : null,
      });
    }

    const runtimes = reply.body.episode_run_time;
    const runtime = Array.isArray(runtimes)
      ? runtimes.find((value): value is number => typeof value === "number" && value > 0) ?? null
      : null;

    return {
      details: {
        candidate,
        seasons,
        lastAirDate: tmdbDate(reply.body.last_air_date),
        seriesStatus: typeof reply.body.status === "string" ? reply.body.status : null,
        episodeRuntime: runtime,
        homepage: typeof reply.body.homepage === "string" ? reply.body.homepage : null,
      },
      status: "ok",
    };
  }

  /**
   * `/tv/{id}/alternative_titles` — weitere Schreibweisen.
   *
   * Der Grund, warum ein Titel wie „Sousou no Frieren" auch dann zugeordnet
   * bleibt, wenn die Quelle ihn als „Frieren: Nach dem Ende der Reise" führt:
   * die Bewertung vergleicht gegen diese Liste mit.
   */
  async alternativeTitles(id: number): Promise<{ titles: string[]; status: TMDBStatus }> {
    const reply = await this.transport.get(`tv/${id}/alternative_titles`, {});
    const out: string[] = [];
    for (const row of rows(reply.body, "results")) {
      if (!row || typeof row !== "object") continue;
      const title = (row as Record<string, unknown>).title;
      if (typeof title === "string" && title.trim()) out.push(title.trim());
    }
    return { titles: out, status: reply.status };
  }

  /**
   * `/tv/{id}/images` — der freigestellte Schriftzug.
   *
   * `include_image_language` ist nicht optional: ohne den Parameter filtert
   * TMDB nach der Sprache der Anfrage und liefert für die meisten Serien eine
   * leere Liste. `null` steht für Logos ohne Sprachkennzeichnung — bei Anime
   * oft die einzigen.
   */
  async logo(id: number): Promise<{ url: string | null; status: TMDBStatus }> {
    const reply = await this.transport.get(`tv/${id}/images`, {
      include_image_language: "de,en,null",
    });
    const path = bestLogoPath(rows(reply.body, "logos"));
    return { url: tmdbImageURL(path, "logo"), status: reply.status };
  }

  /** `/tv/{id}/season/{n}` — Folgentitel, Beschreibungen, Standbilder. */
  async season(
    id: number,
    season: number,
    language = this.language,
  ): Promise<{ episodes: TMDBEpisodeInfo[]; status: TMDBStatus }> {
    const reply = await this.transport.get(`tv/${id}/season/${season}`, { language });
    const out: TMDBEpisodeInfo[] = [];
    for (const row of rows(reply.body, "episodes")) {
      if (!row || typeof row !== "object") continue;
      const raw = row as Record<string, unknown>;
      const number = typeof raw.episode_number === "number" ? raw.episode_number : null;
      if (number === null) continue;
      out.push({
        episodeNumber: number,
        title: typeof raw.name === "string" ? raw.name : null,
        overview: typeof raw.overview === "string" ? raw.overview : null,
        // Das Zuschnittsformat von TMDB selbst: 454×254, also 16:9 — genau die
        // Form, in der die Folgenliste es zeigt.
        still: tmdbImageURL(typeof raw.still_path === "string" ? raw.still_path : null, "still"),
        airDate: typeof raw.air_date === "string" ? raw.air_date : null,
        // TMDB liefert die Laufzeit teils als 0, wenn sie unbekannt ist. Null
        // Minuten ist keine Auskunft, sondern eine Lücke.
        runtime: typeof raw.runtime === "number" && raw.runtime > 0 ? raw.runtime : null,
      });
    }
    return { episodes: out, status: reply.status };
  }

  /**
   * Was TMDB zu einem Titel als verwandt nennt.
   *
   * `/recommendations` und `/similar` beantworten unterschiedliche Fragen: das
   * eine „was haben Leute außerdem gesehen", das andere „was ähnelt sich
   * inhaltlich". Beides zusammen ist breiter als eines allein.
   */
  async related(id: number): Promise<{ rows: TMDBCandidate[]; status: TMDBStatus }> {
    const [recommended, similar] = await Promise.all([
      this.transport.get(`tv/${id}/recommendations`, { language: this.language, page: "1" }),
      this.transport.get(`tv/${id}/similar`, { language: this.language, page: "1" }),
    ]);
    const seen = new Set<number>();
    const out: TMDBCandidate[] = [];
    for (const candidate of [...candidates(recommended.body), ...candidates(similar.body)]) {
      if (seen.has(candidate.id)) continue;
      seen.add(candidate.id);
      out.push(candidate);
    }
    const status: TMDBStatus = recommended.status === "ok" || similar.status === "ok"
      ? "ok"
      : recommended.status;
    return { rows: out, status };
  }

  /** Eine Rangliste, über alle ihre Seiten. */
  async feed(
    feed: TMDBFeed,
    now = Date.now(),
  ): Promise<{ rows: TMDBCandidate[]; status: TMDBStatus }> {
    const path = feedPath(feed);
    const extra = feedQuery(feed, now);
    const seen = new Set<number>();
    const out: TMDBCandidate[] = [];
    let status: TMDBStatus = this.transport.available ? "unavailable" : "noKey";
    for (let page = 1; page <= feedPages(feed); page += 1) {
      const reply = await this.transport.get(path, {
        language: this.language,
        include_adult: "false",
        page: String(page),
        ...extra,
      });
      status = reply.status;
      const found = candidates(reply.body);
      if (found.length === 0) break;
      for (const candidate of found) {
        if (seen.has(candidate.id)) continue;
        seen.add(candidate.id);
        out.push(candidate);
      }
    }
    return { rows: out, status: out.length > 0 ? "ok" : status };
  }
}

/**
 * Das brauchbarste Logo aus der TMDB-Antwort.
 *
 * Deutsch vor Englisch vor sprachlos, und **PNG vor SVG**: ein `<img>` mit
 * SVG-Quelle zeichnet webOS 6 nicht zuverlässig, das Logo bliebe unsichtbar.
 * Bei gleicher Sprache entscheidet die Bewertung.
 */
export function bestLogoPath(logos: unknown[]): string | null {
  const rank = (row: Record<string, unknown>): number => {
    switch (row.iso_639_1) {
      case "de": return 0;
      case "en": return 1;
      default: return 2;
    }
  };
  const usable: Record<string, unknown>[] = [];
  for (const row of logos) {
    if (!row || typeof row !== "object") continue;
    const raw = row as Record<string, unknown>;
    const path = raw.file_path;
    if (typeof path !== "string" || !path) continue;
    if (path.toLowerCase().endsWith(".svg")) continue;
    usable.push(raw);
  }
  if (usable.length === 0) return null;
  usable.sort((a, b) => {
    if (rank(a) !== rank(b)) return rank(a) - rank(b);
    const va = typeof a.vote_average === "number" ? a.vote_average : 0;
    const vb = typeof b.vote_average === "number" ? b.vote_average : 0;
    return vb - va;
  });
  const path = usable[0].file_path;
  return typeof path === "string" ? path : null;
}
