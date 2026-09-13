// TMDB auf dem Fernseher.
//
// Der Kern (`@nori/core/tmdb`) weiß, **wie** man TMDB fragt und **welcher**
// Treffer zählt. Diese Datei weiß, was ein Fernseher aushält:
//
// - **Höchstens vier Abrufe gleichzeitig.** Ein Raster mit sechzig Kacheln
//   löste sonst sechzig Anfragen auf einmal aus und liefe in die
//   Ratenbegrenzung — Kacheln blieben dann leer.
// - **Gleiche Fragen einmal.** Dieselbe Serie steht oft gleichzeitig in
//   Startseite, Katalog und Kalender.
// - **Alles bleibt liegen.** Ohne Ablage müsste jede Kachel nach jedem Start
//   erneut suchen, und Listen blieben minutenlang ohne Bild.
// - **Der Cache ist versioniert.** Ändert sich die Zuordnung, sind die alten
//   Treffer falsch und müssen weg — nicht „irgendwann von selbst", sondern
//   beim ersten Start danach.
// - **Voller Speicher ist ein Normalfall.** `localStorage` eines Fernsehers
//   ist klein. Jeder Schreibvorgang ist abgesichert, und bei Überlauf fliegt
//   der betroffene Abschnitt, nicht die App.
//
// Jeder Weg hier endet im Zweifel mit „nichts", nie mit einem Fehler nach
// außen. Ohne Schlüssel, ohne Netz, bei Ratenbegrenzung oder bei unerwarteten
// Daten bleibt TMDB leer und Nori zeigt die Daten der Quellen. Das ist der
// Betrieb im Normalfall, kein Sonderfall.

import {
  DirectTMDBTransport, FetchHttpClient, NoTMDBTransport, ServerTMDBTransport, TMDBClient,
  TMDB_FEEDS, alignEpisodes, alignmentIsUsable, emptySignals, feedMaxAge, pickTmdbSeason,
  tmdbImageURL,
  type CatalogProvider, type SeasonMatch, type SourceEpisodeRef, type TMDBCandidate,
  type TMDBEpisodeInfo, type TMDBFeed, type TMDBKeyOrigin, type TMDBSignals, type TMDBStatus,
} from "@nori/core";
import { log, warn } from "./log";

/**
 * Die Fassung der Ablage.
 *
 * **Erhöhen, sobald sich die Zuordnung ändert.** Die abgelegten Treffer sind
 * dann mit einer anderen Regel entstanden und teilweise falsch; sie weiter zu
 * benutzen hieße, den Fehler zu konservieren.
 *
 * v4: Ein 404 auf die **Suche** gilt nicht mehr als „gibt es nicht". TMDBs
 * Suche antwortet nie mit 404 — ein 404 kam immer vom Weg dorthin, etwa von
 * einem Nori-Server ohne `/api/tmdb`. v3 merkte ihn als belegten Fehlschlag
 * für vierzehn Tage, und jede Kachel blieb so lange ohne Bild. Die Nummer
 * steigt, damit diese Einträge beim ersten Start verschwinden.
 * v3: Fehlschläge tragen ihre Gültigkeitsdauer mit sich.
 * v2: erste Fassung mit Titelabgleich aus dem Kern, Staffelzuordnung mit
 * Versatzerkennung und Alternativtiteln. v1 waren die Backdrops aus
 * `covers.ts`, die den erstbesten Suchtreffer nahmen — die sind verworfen.
 */
const STORE_VERSION = 4;

const TITLES_KEY = `nori.tmdb.titles.v${STORE_VERSION}`;
const FEEDS_KEY = `nori.tmdb.feeds.v${STORE_VERSION}`;
const SEASONS_KEY = `nori.tmdb.seasons.v${STORE_VERSION}`;
const RELATED_KEY = `nori.tmdb.related.v${STORE_VERSION}`;

const MAX_CONCURRENT = 4;
/**
 * Wie lange ein Fehlschlag gilt, bevor erneut gesucht wird.
 *
 * Gemerkt wird nur eine Auskunft: „gesucht, TMDB hat geantwortet, nichts hat
 * die Titelschwelle erreicht". Das ist eine Aussage über den heutigen
 * Datenstand — TMDB wächst, und gerade bei frischen Anime kommt der Eintrag oft
 * Tage später. Ein halber Tag.
 *
 * Ratenbegrenzung, abgelehnter Schlüssel, Netzfehler und ein 404 vom Weg
 * dorthin gelten überhaupt nicht als Fehlschlag — sie werden nie gemerkt.
 */
const MISS_MAX_AGE = 12 * 3_600_000;
/** Wie lange die Angaben zu einem Titel gelten. */
const TITLE_MAX_AGE = 21 * 86_400_000;
/** Wie lange eine Staffel gilt. Folgentitel ändern sich kaum. */
const SEASON_MAX_AGE = 14 * 86_400_000;
const RELATED_MAX_AGE = 7 * 86_400_000;

const MAX_TITLES = 2500;
const MAX_SEASONS = 240;
const MAX_RELATED = 60;

/** Was Nori zu einem Titel von TMDB weiß. */
export interface TitleArt {
  tmdbID: number;
  poster: string | null;
  backdrop: string | null;
  /** Freigestellter Schriftzug. Wird nur geholt, wo er auch gezeigt wird. */
  logo: string | null;
  /** `""` heißt „nachgeschlagen, TMDB hat keine" — nicht „noch nicht gefragt". */
  overview: string;
  /** TMDBs Zehnerskala. */
  rating: number | null;
  votes: number | null;
  firstAirDate: number | null;
  lastAirDate: number | null;
  genreIDs: number[];
  /** Ob der Treffer über die Alternativtitel von TMDB entstand. */
  viaAlternates: boolean;
  fetchedAt: number;
}

export interface SeasonArt {
  match: SeasonMatch;
  /** Quellfolgennummer → TMDB-Angaben. Leer heißt „nicht belegbar". */
  episodes: Record<number, TMDBEpisodeInfo>;
  offset: number;
  fetchedAt: number;
}

/** Ein gemerkter Fehlschlag: wann, und wie lange er gilt. */
interface TitleMiss {
  at: number;
  maxAge: number;
}

interface TitleStore {
  version: number;
  art: Record<string, TitleArt>;
  /** Schlüssel → Fehlschlag. */
  missing: Record<string, TitleMiss>;
}

interface FeedStore {
  version: number;
  feeds: Partial<Record<TMDBFeed, { rows: TMDBCandidate[]; fetchedAt: number }>>;
}

interface SeasonStore {
  version: number;
  seasons: Record<string, SeasonArt>;
}

interface RelatedStore {
  version: number;
  related: Record<string, { rows: TMDBCandidate[]; fetchedAt: number }>;
}

export type TmdbMode = "server" | "direct" | "off";

export interface TmdbConfig {
  mode: TmdbMode;
  /** Nur für `direct`. */
  key: string;
  /** Nur für `server`. Die Basisadresse des Nori-Servers. */
  serverUrl: string;
}

/** Was die Einstellungen über den Zustand von TMDB anzeigen. */
export interface TmdbDiagnostics {
  mode: TmdbMode;
  available: boolean;
  /**
   * Ob der benutzte Schlüssel eingetragen oder mitgeliefert ist.
   *
   * `null` im Serverbetrieb: dort hält der Server den Schlüssel, und welcher
   * es ist, sagt seine Antwort auf `/api/health` — nicht dieser Dienst.
   */
  keyOrigin: TMDBKeyOrigin | null;
  lastStatus: TMDBStatus | null;
  titles: number;
  misses: number;
  seasons: number;
  feeds: number;
  /** Treffer, die erst über die Alternativtitel von TMDB zustande kamen. */
  viaAlternates: number;
}

type Listener = (key: string) => void;

function readStore<T extends { version: number }>(key: string, empty: T): T {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return empty;
    const parsed = JSON.parse(raw) as Partial<T>;
    // Eine Ablage aus einer anderen Fassung wird nicht gelesen, sondern
    // verworfen. Genau dafür steht die Nummer im Schlüssel *und* im Inhalt:
    // der Schlüssel trennt die Dateien, der Inhalt fängt einen von Hand
    // manipulierten Stand.
    if (parsed.version !== empty.version) return empty;
    return { ...empty, ...parsed };
  } catch {
    return empty;
  }
}

class TmdbService {
  private titles: TitleStore = readStore(TITLES_KEY, { version: STORE_VERSION, art: {}, missing: {} });
  private feedStore: FeedStore = readStore(FEEDS_KEY, { version: STORE_VERSION, feeds: {} });
  private seasonStore: SeasonStore = readStore(SEASONS_KEY, { version: STORE_VERSION, seasons: {} });
  private relatedStore: RelatedStore = readStore(RELATED_KEY, { version: STORE_VERSION, related: {} });

  private client = new TMDBClient(new NoTMDBTransport());
  private config: TmdbConfig = { mode: "off", key: "", serverUrl: "" };
  private keyOrigin: TMDBKeyOrigin | null = null;
  private lastStatus: TMDBStatus | null = null;

  private readonly inflight = new Map<string, Promise<unknown>>();
  private readonly queue: (() => void)[] = [];
  private running = 0;
  private readonly listeners = new Set<Listener>();
  private readonly statusListeners = new Set<() => void>();
  private readonly saveTimers = new Map<string, number>();

  /**
   * Den Zugang einstellen.
   *
   * Ein Wechsel des Weges (Server ↔ direkt) macht die **Treffer nicht
   * ungültig**: es ist dieselbe Datenbank, nur ein anderer Weg dorthin. Ein
   * Wechsel auf „aus" wirft ebenfalls nichts weg — wer TMDB wieder einschaltet,
   * soll nicht von vorn anfangen.
   */
  configure(config: TmdbConfig): void {
    const same = config.mode === this.config.mode
      && config.key === this.config.key
      && config.serverUrl === this.config.serverUrl;
    if (same) return;
    this.config = config;
    this.lastStatus = null;
    // Nach dem Tausch des Zugangs unten — erst dann stimmt `available`.
    queueMicrotask(() => {
      for (const listener of this.statusListeners) listener();
    });
    // Kein Umschreiben von Adressen und keine Weiterleitungsauswertung: TMDB
    // antwortet direkt, und im Serverbetrieb sitzt der Nori-Server davor.
    const http = new FetchHttpClient({ canReadRedirects: false, timeoutMs: 15_000 });
    if (config.mode === "server" && config.serverUrl) {
      this.client = new TMDBClient(new ServerTMDBTransport(config.serverUrl, http));
      this.keyOrigin = null;
    } else if (config.mode === "direct") {
      // Ohne eingetragenen Schlüssel nimmt `DirectTMDBTransport` den
      // mitgelieferten. Der direkte Weg ist damit immer benutzbar.
      const transport = new DirectTMDBTransport(config.key, http);
      this.client = new TMDBClient(transport);
      this.keyOrigin = transport.keyOrigin;
    } else {
      this.client = new TMDBClient(new NoTMDBTransport());
      this.keyOrigin = null;
    }
    log(
      "tmdb", "Zugang", config.mode,
      this.client.available ? "bereit" : "aus",
      this.keyOrigin === "own" ? "eigener Schlüssel"
        : this.keyOrigin === "builtIn" ? "mitgelieferter Schlüssel" : "",
    );
  }

  get available(): boolean {
    return this.client.available;
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /**
   * Nur Wechsel des Zustands — nicht jeder Treffer.
   *
   * Getrennt von `subscribe`: dort meldet sich jede nachgeladene Serie, und
   * wer nur „Verbunden/Fehler" anzeigt, rechnete sonst bei jedem Cover neu.
   * Die Einstellungen zeichneten dafür vorher alle drei Sekunden neu.
   */
  subscribeStatus(listener: () => void): () => void {
    this.statusListeners.add(listener);
    return () => this.statusListeners.delete(listener);
  }

  /** Das, was „Verbunden" oder „Fehler" entscheidet — ohne die Ablagen zu zählen. */
  status(): { available: boolean; lastStatus: TMDBStatus | null } {
    return { available: this.available, lastStatus: this.lastStatus };
  }

  private setStatus(status: TMDBStatus | null): void {
    if (this.lastStatus === status) return;
    this.lastStatus = status;
    for (const listener of this.statusListeners) listener();
  }

  diagnostics(): TmdbDiagnostics {
    let viaAlternates = 0;
    for (const entry of Object.values(this.titles.art)) {
      if (entry.viaAlternates) viaAlternates += 1;
    }
    return {
      mode: this.config.mode,
      available: this.available,
      keyOrigin: this.keyOrigin,
      lastStatus: this.lastStatus,
      titles: Object.keys(this.titles.art).length,
      misses: Object.keys(this.titles.missing).length,
      seasons: Object.keys(this.seasonStore.seasons).length,
      feeds: Object.keys(this.feedStore.feeds).length,
      viaAlternates,
    };
  }

  // MARK: - Titel

  private titleKey(slug: string, provider: CatalogProvider): string {
    return `${provider}|${slug}`;
  }

  /** Was schon dasteht, ohne einen Abruf. Für den ersten Aufbau einer Ansicht. */
  art(slug: string, provider: CatalogProvider): TitleArt | null {
    const entry = this.titles.art[this.titleKey(slug, provider)];
    if (!entry) return null;
    return entry;
  }

  /**
   * Die abgelegten Angaben als Signale für die Startseite.
   *
   * Für Titel, die auf keiner TMDB-Rangliste stehen, sind das die einzigen
   * Signale, die es gibt — ohne sie bliebe „Neu & beliebt" auf die wenigen
   * Titel der Ranglisten beschränkt.
   */
  knownSignals(): Map<string, TMDBSignals> {
    const out = new Map<string, TMDBSignals>();
    for (const [key, entry] of Object.entries(this.titles.art)) {
      out.set(key, {
        ...emptySignals(),
        tmdbID: entry.tmdbID,
        voteAverage: entry.rating,
        voteCount: entry.votes,
        firstAirDate: entry.firstAirDate,
        lastAirDate: entry.lastAirDate,
        genreIDs: entry.genreIDs,
        hasBackdrop: Boolean(entry.backdrop),
      });
    }
    return out;
  }

  /**
   * Die Angaben zu einem Titel besorgen.
   *
   * Zwei Abrufe im besten Fall: die Suche und `/tv/{id}`. Der zweite bringt
   * Staffelliste und letzte Ausstrahlung — beides braucht die Startseite für
   * „neu", und beides steht nicht in der Suchantwort.
   */
  async ensureArt(input: {
    slug: string;
    title: string;
    alternates?: string[];
    provider: CatalogProvider;
    expectedYear?: number | null;
    expectedSeasons?: number | null;
  }): Promise<TitleArt | null> {
    const key = this.titleKey(input.slug, input.provider);
    const known = this.titles.art[key];
    if (known && Date.now() - known.fetchedAt < TITLE_MAX_AGE) return known;
    if (!this.available) return known ?? null;

    const miss = this.titles.missing[key];
    if (miss && Date.now() - miss.at < miss.maxAge) return known ?? null;

    return this.once(`art:${key}`, () => this.schedule(async () => {
      const { result, status } = await this.client.findSeries({
        title: input.title,
        alternates: input.alternates,
        provider: input.provider,
        expectedYear: input.expectedYear ?? null,
      });
      this.setStatus(status);
      if (!result) {
        // Nur einen echten Fehlschlag merken: TMDB hat geantwortet, und nichts
        // passte. Bei 401, 429, einem Netzfehler oder einem 404 vom Server hat
        // TMDB nichts über den Titel gesagt.
        if (status === "ok") {
          this.titles.missing[key] = { at: Date.now(), maxAge: MISS_MAX_AGE };
          this.save(TITLES_KEY, () => this.titles);
        }
        return known ?? null;
      }

      const candidate = result.candidate;
      const { details } = await this.client.series(candidate.id);
      const entry: TitleArt = {
        tmdbID: candidate.id,
        poster: tmdbImageURL(candidate.posterPath, "posterHero"),
        backdrop: tmdbImageURL(candidate.backdropPath, "backdropHero"),
        logo: known?.logo ?? null,
        overview: candidate.overview ?? "",
        rating: candidate.voteAverage > 0 ? candidate.voteAverage : null,
        votes: candidate.voteCount > 0 ? candidate.voteCount : null,
        firstAirDate: candidate.firstAirDate,
        lastAirDate: details?.lastAirDate ?? null,
        genreIDs: candidate.genreIDs,
        viaAlternates: result.viaAlternates,
        fetchedAt: Date.now(),
      };
      this.titles.art[key] = entry;
      delete this.titles.missing[key];
      this.trimTitles();
      this.save(TITLES_KEY, () => this.titles);
      this.notify(key);
      log("tmdb", "Treffer", input.slug, candidate.id, result.viaAlternates ? "(über Alternativtitel)" : "");
      return entry;
    }));
  }

  /**
   * Das Logo nachladen.
   *
   * Ein eigener Abruf, deshalb nur dort aufrufen, wo es sichtbar wird — im
   * Kopfbereich der Startseite und auf der Detailseite. `null` bleibt `null`:
   * viele Serien haben keinen freigestellten Schriftzug, und der Titel als
   * Schrift ist dort der richtige Rückfall, kein Notbehelf.
   */
  async ensureLogo(input: {
    slug: string;
    title: string;
    alternates?: string[];
    provider: CatalogProvider;
  }): Promise<string | null> {
    const key = this.titleKey(input.slug, input.provider);
    const known = this.titles.art[key];
    if (known?.logo) return known.logo;
    if (!this.available) return null;

    // Die Zuordnung **vor** dem Einreihen holen, nicht darin. Stand sie im
    // eingereihten Auftrag, belegte der einen der vier Plätze und wartete auf
    // einen fünften — waren alle vier so belegt, stand TMDB für den Rest der
    // Sitzung still. Genau das war „TMDB lädt manchmal gar nicht mehr".
    const art = known ?? await this.ensureArt(input);
    if (!art) return null;
    if (art.logo) return art.logo;

    return this.once(`logo:${key}`, () => this.schedule(async () => {
      const { url, status } = await this.client.logo(art.tmdbID);
      this.setStatus(status);
      if (!url) return null;
      const entry = this.titles.art[key];
      if (entry) {
        entry.logo = url;
        this.save(TITLES_KEY, () => this.titles);
        this.notify(key);
      }
      return url;
    }));
  }

  // MARK: - Staffeln und Folgen

  private seasonKey(slug: string, provider: CatalogProvider, season: string): string {
    return `${provider}|${slug}|${season}`;
  }

  cachedSeason(slug: string, provider: CatalogProvider, season: string): SeasonArt | null {
    return this.seasonStore.seasons[this.seasonKey(slug, provider, season)] ?? null;
  }

  /**
   * Folgentitel, Beschreibungen und Standbilder einer Staffel.
   *
   * Hier steckt die eigentliche Vorsicht: AniWorld und TMDB teilen dieselbe
   * Serie anders auf. Die Zuordnung läuft deshalb über `pickTmdbSeason` und
   * `alignEpisodes` aus dem Kern, und eine unsichere Zuordnung liefert
   * ausdrücklich **nichts** statt der Folgen einer anderen Staffel.
   *
   * Deutsch zuerst, Englisch als Lückenfüller: TMDB pflegt die deutschen Texte
   * lückenhaft, bei Anime fast gar nicht. Fehlt mehr als die Hälfte, wird die
   * englische Fassung nachgeholt und füllt nur die Lücken.
   */
  async ensureSeason(input: {
    slug: string;
    title: string;
    alternates?: string[];
    provider: CatalogProvider;
    season: string;
    episodes: SourceEpisodeRef[];
    /** Wie viele Staffeln die Quelle führt — hilft der Titelzuordnung. */
    expectedSeasons?: number | null;
  }): Promise<SeasonArt | null> {
    const key = this.seasonKey(input.slug, input.provider, input.season);
    const known = this.seasonStore.seasons[key];
    if (known && Date.now() - known.fetchedAt < SEASON_MAX_AGE) return known;
    if (!this.available) return known ?? null;
    // „Filme" und andere Sonderabschnitte tragen keine Staffelnummer. TMDB
    // kennt Staffel 0 für Specials, aber die Zuordnung wäre geraten.
    const number = Number.parseInt(input.season, 10);
    if (!Number.isFinite(number) || number <= 0) return null;

    // Außerhalb der Warteschlange, aus demselben Grund wie bei `ensureLogo`.
    const art = await this.ensureArt({
      slug: input.slug,
      title: input.title,
      alternates: input.alternates,
      provider: input.provider,
      expectedSeasons: input.expectedSeasons,
    });
    if (!art) return known ?? null;

    return this.once(`season:${key}`, () => this.schedule(async () => {
      const { details } = await this.client.series(art.tmdbID);
      if (!details) return known ?? null;

      const match = pickTmdbSeason({
        sourceSeason: input.season,
        sourceEpisodeCount: input.episodes.length,
        tmdbSeasons: details.seasons,
      });
      if (!match) {
        log("tmdb", "Staffel nicht zuordenbar", input.slug, input.season);
        return null;
      }

      const episodes = await this.fetchSeasonEpisodes(art.tmdbID, match.seasonNumber);
      if (episodes.length === 0) return null;

      const alignment = alignEpisodes(input.episodes, episodes);
      if (!alignmentIsUsable(match, alignment)) {
        log("tmdb", "Staffelzuordnung unsicher, keine Folgendaten", input.slug, input.season, match.reason);
        return null;
      }

      const mapped: Record<number, TMDBEpisodeInfo> = {};
      for (const [number_, info] of alignment.pairs) mapped[number_] = info;

      const entry: SeasonArt = {
        match,
        episodes: mapped,
        offset: alignment.offset,
        fetchedAt: Date.now(),
      };
      this.seasonStore.seasons[key] = entry;
      this.trimSeasons();
      this.save(SEASONS_KEY, () => this.seasonStore);
      this.notify(key);
      log(
        "tmdb", "Staffel", input.slug, input.season, "→ TMDB", match.seasonNumber,
        match.confidence, alignment.offset ? `Versatz ${alignment.offset}` : "",
      );
      return entry;
    }));
  }

  private async fetchSeasonEpisodes(id: number, season: number): Promise<TMDBEpisodeInfo[]> {
    const german = await this.client.season(id, season, "de-DE");
    this.lastStatus = german.status;
    let episodes = german.episodes;
    const withText = episodes.filter((episode) => (episode.overview ?? "").length > 0).length;
    if (episodes.length === 0 || withText * 2 < episodes.length) {
      const english = await this.client.season(id, season, "en-US");
      if (episodes.length === 0) {
        episodes = english.episodes;
      } else {
        const byNumber = new Map(english.episodes.map((episode) => [episode.episodeNumber, episode]));
        episodes = episodes.map((episode) => {
          const fallback = byNumber.get(episode.episodeNumber);
          if (!fallback) return episode;
          return {
            ...episode,
            title: episode.title || fallback.title,
            overview: episode.overview || fallback.overview,
            still: episode.still ?? fallback.still,
            runtime: episode.runtime ?? fallback.runtime,
          };
        });
      }
    }
    return episodes;
  }

  // MARK: - Ranglisten

  cachedFeed(feed: TMDBFeed): TMDBCandidate[] {
    return this.feedStore.feeds[feed]?.rows ?? [];
  }

  /** Alle abgelegten Listen, ohne einen einzigen Abruf. */
  cachedSignals(): { trending: TMDBCandidate[]; popular: TMDBCandidate[]; airing: TMDBCandidate[] } {
    return {
      trending: this.cachedFeed("trendingWeek"),
      popular: [...this.cachedFeed("popular"), ...this.cachedFeed("animePopular")],
      airing: [...this.cachedFeed("airingRecently"), ...this.cachedFeed("animeAiringRecently")],
    };
  }

  /**
   * Die Ranglisten, notfalls frisch geholt.
   *
   * Zehn Abrufe im schlechtesten Fall (fünf Listen zu zwei Seiten) — und das
   * höchstens alle sechs Stunden. Die naheliegende Alternative wäre, für jeden
   * der tausenden Katalogtitel `/tv/{id}` zu holen; das sind tausende Anfragen
   * für eine Reihe mit zwanzig Kacheln.
   */
  async ensureFeeds(force = false): Promise<{ trending: TMDBCandidate[]; popular: TMDBCandidate[]; airing: TMDBCandidate[] }> {
    if (!this.available) return this.cachedSignals();
    const now = Date.now();
    await Promise.all(TMDB_FEEDS.map((feed) => this.ensureFeed(feed, now, force)));
    return this.cachedSignals();
  }

  private ensureFeed(feed: TMDBFeed, now: number, force: boolean): Promise<TMDBCandidate[]> {
    const known = this.feedStore.feeds[feed];
    if (!force && known && now - known.fetchedAt < feedMaxAge(feed)) {
      return Promise.resolve(known.rows);
    }
    return this.once(`feed:${feed}`, () => this.schedule(async () => {
      const { rows, status } = await this.client.feed(feed, now);
      this.setStatus(status);
      // Ein leerer Abruf überschreibt keinen brauchbaren Stand. Ohne das leerte
      // ein einzelner Netzfehler die halbe Startseite.
      if (rows.length === 0) return known?.rows ?? [];
      this.feedStore.feeds[feed] = { rows, fetchedAt: Date.now() };
      this.save(FEEDS_KEY, () => this.feedStore);
      this.notify(`feed:${feed}`);
      return rows;
    }));
  }

  // MARK: - Ähnliche Titel

  cachedRelated(tmdbID: number): TMDBCandidate[] {
    return this.relatedStore.related[String(tmdbID)]?.rows ?? [];
  }

  async ensureRelated(tmdbID: number): Promise<TMDBCandidate[]> {
    const key = String(tmdbID);
    const known = this.relatedStore.related[key];
    if (known && Date.now() - known.fetchedAt < RELATED_MAX_AGE) return known.rows;
    if (!this.available) return known?.rows ?? [];

    return this.once(`related:${key}`, () => this.schedule(async () => {
      const { rows, status } = await this.client.related(tmdbID);
      this.setStatus(status);
      if (rows.length === 0) return known?.rows ?? [];
      this.relatedStore.related[key] = { rows, fetchedAt: Date.now() };
      this.trimRelated();
      this.save(RELATED_KEY, () => this.relatedStore);
      this.notify(`related:${key}`);
      return rows;
    }));
  }

  // MARK: - Diagnose

  /**
   * Ein echter Abruf, um den Zustand zu belegen.
   *
   * Für die Diagnose: „verbunden" soll heißen, dass TMDB gerade geantwortet
   * hat — nicht, dass ein Schlüssel eingetragen ist.
   */
  async probe(): Promise<{ status: TMDBStatus; ms: number }> {
    if (!this.available) return { status: "noKey", ms: 0 };
    const started = Date.now();
    const { status } = await this.client.search("Frieren");
    this.setStatus(status);
    return { status, ms: Date.now() - started };
  }

  /** Ablagen älterer Fassungen belegen den knappen Speicher — beim Start weg. */
  dropOldVersions(): void {
    for (let version = 1; version < STORE_VERSION; version += 1) {
      for (const prefix of ["titles", "feeds", "seasons", "related"]) {
        try {
          localStorage.removeItem(`nori.tmdb.${prefix}.v${version}`);
        } catch {
          /* aufgeben */
        }
      }
    }
  }

  // MARK: - Aufräumen

  /**
   * Alles verwerfen.
   *
   * In den Einstellungen als „Bildspeicher leeren". Der Fall dahinter: eine
   * Serie hat sichtbar das falsche Bild. Dann muss sich das von der Couch aus
   * beheben lassen, ohne die App neu zu installieren.
   */
  clear(): void {
    this.titles = { version: STORE_VERSION, art: {}, missing: {} };
    this.feedStore = { version: STORE_VERSION, feeds: {} };
    this.seasonStore = { version: STORE_VERSION, seasons: {} };
    this.relatedStore = { version: STORE_VERSION, related: {} };
    for (const key of [TITLES_KEY, FEEDS_KEY, SEASONS_KEY, RELATED_KEY]) {
      try {
        localStorage.removeItem(key);
      } catch {
        /* aufgeben */
      }
    }
    // Auch die Ablagen älterer Fassungen — sonst belegen sie den knappen
    // Speicher des Fernsehers für immer.
    for (let version = 1; version < STORE_VERSION; version += 1) {
      for (const prefix of ["titles", "feeds", "seasons", "related"]) {
        try {
          localStorage.removeItem(`nori.tmdb.${prefix}.v${version}`);
        } catch {
          /* aufgeben */
        }
      }
    }
    this.notify("*");
  }

  /** Nur die gemerkten Fehlschläge. Für „nochmal suchen" ohne Bildverlust. */
  retryMisses(): void {
    this.titles.missing = {};
    this.save(TITLES_KEY, () => this.titles);
    this.notify("*");
  }

  private trimTitles(): void {
    const keys = Object.keys(this.titles.art);
    if (keys.length > MAX_TITLES) {
      for (const key of keys.slice(0, keys.length - MAX_TITLES)) delete this.titles.art[key];
    }
    // Abgelaufene Fehlschläge kosten nur Platz.
    const now = Date.now();
    for (const [key, miss] of Object.entries(this.titles.missing)) {
      if (now - miss.at > miss.maxAge) delete this.titles.missing[key];
    }
  }

  private trimSeasons(): void {
    const keys = Object.keys(this.seasonStore.seasons);
    if (keys.length <= MAX_SEASONS) return;
    for (const key of keys.slice(0, keys.length - MAX_SEASONS)) {
      delete this.seasonStore.seasons[key];
    }
  }

  private trimRelated(): void {
    const keys = Object.keys(this.relatedStore.related);
    if (keys.length <= MAX_RELATED) return;
    for (const key of keys.slice(0, keys.length - MAX_RELATED)) {
      delete this.relatedStore.related[key];
    }
  }

  // MARK: - Werkzeug

  private notify(key: string): void {
    for (const listener of this.listeners) listener(key);
  }

  /**
   * Gleiche Fragen teilen sich einen Abruf.
   *
   * Der Rückgabewert ist absichtlich derselbe `Promise`: zwei Kacheln, die
   * gleichzeitig dieselbe Serie brauchen, warten auf denselben Abruf statt
   * zwei anzustoßen.
   */
  private once<T>(key: string, task: () => Promise<T>): Promise<T> {
    const running = this.inflight.get(key) as Promise<T> | undefined;
    if (running) return running;
    const promise = task().finally(() => this.inflight.delete(key));
    this.inflight.set(key, promise);
    return promise;
  }

  /** Höchstens vier gleichzeitig; der Rest wartet in der Reihe. */
  private schedule<T>(task: () => Promise<T>): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const start = () => {
        this.running += 1;
        task().then(resolve, reject).finally(() => {
          this.running -= 1;
          const next = this.queue.shift();
          if (next) next();
        });
      };
      if (this.running < MAX_CONCURRENT) start();
      else this.queue.push(start);
    });
  }

  /**
   * Gebündelt schreiben, und jeden Schreibvorgang absichern.
   *
   * Voller Speicher ist auf einem Fernseher ein realer Zustand. Dann fliegt
   * der betroffene Abschnitt — lieber ohne Bilder weiterlaufen als bei jeder
   * weiteren Ablage scheitern.
   */
  private save(key: string, snapshot: () => unknown): void {
    const existing = this.saveTimers.get(key);
    if (existing !== undefined) window.clearTimeout(existing);
    this.saveTimers.set(key, window.setTimeout(() => {
      this.saveTimers.delete(key);
      try {
        localStorage.setItem(key, JSON.stringify(snapshot()));
      } catch (cause) {
        warn("tmdb", "Ablage voll, Abschnitt wird geleert", key, (cause as Error)?.message);
        try {
          localStorage.removeItem(key);
        } catch {
          /* aufgeben */
        }
        if (key === TITLES_KEY) this.titles = { version: STORE_VERSION, art: {}, missing: {} };
        if (key === FEEDS_KEY) this.feedStore = { version: STORE_VERSION, feeds: {} };
        if (key === SEASONS_KEY) this.seasonStore = { version: STORE_VERSION, seasons: {} };
        if (key === RELATED_KEY) this.relatedStore = { version: STORE_VERSION, related: {} };
      }
    }, 800));
  }
}

export const tmdb = new TmdbService();
tmdb.dropOldVersions();
