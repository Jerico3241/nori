// Cover-Beschaffung.
//
// Warum das nötig ist: die Katalogseiten beider Quellen sind reine Titellisten
// ohne Bilder — die Adresse des Covers steht nur auf der Detailseite, und sie
// enthält einen Zufallsanteil, lässt sich also nicht aus dem Slug bilden. Der
// Swift-Kern löst das mit `CoverIndex`: Detailseite bei Bedarf nachladen,
// höchstens vier gleichzeitig, Ergebnis dauerhaft ablegen. Hier steht dasselbe
// Verfahren.
//
// Optional kommt TMDB dazu (Backdrops und Folgenbilder). Ohne Schlüssel fragt
// Nori TMDB gar nicht erst an und zeigt die Cover der Quellen — ein gültiger
// Zustand, kein Fehler.

import { NoriClient, tmdb, type CatalogProvider, type NoriGateway } from "@nori/core";
import { log, warn } from "./log";

// v2: seit die TMDB-Suche bewertet statt die erste Zeile zu nehmen. Die
// Breitbilder aus v1 sind teilweise die falschen und werden verworfen.
const STORE_KEY = "nori.covers.v2";
const MAX_ENTRIES = 3000;
const MAX_CONCURRENT = 4;

interface CoverStore {
  source: Record<string, string>;
  backdrop: Record<string, string>;
  missing: Record<string, number>;
  /** Titel, die TMDB nachweislich nicht führt — mit Zeitstempel. */
  tmdbMissing: Record<string, number>;
}

function emptyStore(): CoverStore {
  return { source: {}, backdrop: {}, missing: {}, tmdbMissing: {} };
}

/** Wie lange ein „TMDB kennt den Titel nicht" gilt. TMDB wächst. */
const TMDB_MISS_MAX_AGE = 14 * 24 * 3_600_000;

/** Wie viele Schreibweisen höchstens gesucht werden. */
const MAX_QUERIES = 4;

function loadStore(): CoverStore {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    if (!raw) return emptyStore();
    const parsed = JSON.parse(raw) as Partial<CoverStore>;
    return {
      source: parsed.source ?? {},
      backdrop: parsed.backdrop ?? {},
      missing: parsed.missing ?? {},
      tmdbMissing: parsed.tmdbMissing ?? {},
    };
  } catch {
    return emptyStore();
  }
}

/** Woher ein Cover stammt — für die Kachel unerheblich, für die Fehlersuche nicht. */
export type CoverKind = "source" | "tmdb";

export interface CoverResult {
  url: string;
  kind: CoverKind;
}

type Listener = (slug: string) => void;

class CoverIndex {
  private store = loadStore();
  private inflight = new Map<string, Promise<string | null>>();
  private queue: (() => void)[] = [];
  private running = 0;
  private saveTimer: number | null = null;
  private listeners = new Set<Listener>();
  private gateway: NoriGateway | null = null;
  private tmdbKey = "";

  configure(gateway: NoriGateway, tmdbKey: string): void {
    this.gateway = gateway;
    this.tmdbKey = tmdbKey.trim();
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Bereits bekannte Adresse, ohne etwas anzustoßen. */
  cached(slug: string, provider: CatalogProvider): string | null {
    return this.store.source[this.key(slug, provider)] ?? null;
  }

  backdrop(slug: string, provider: CatalogProvider): string | null {
    return this.store.backdrop[this.key(slug, provider)] ?? null;
  }

  /**
   * Cover besorgen. Mehrfache Aufrufe für denselben Titel führen zu einem
   * Abruf; mehr als vier laufen nie gleichzeitig.
   */
  async ensure(slug: string, provider: CatalogProvider): Promise<string | null> {
    const key = this.key(slug, provider);
    const known = this.store.source[key];
    if (known) return known;
    const failedAt = this.store.missing[key];
    // Ein Fehlschlag wird eine Stunde lang nicht wiederholt: sonst rennt jede
    // Rückkehr auf die Startseite erneut gegen dieselbe leere Seite.
    if (failedAt && Date.now() - failedAt < 3_600_000) return null;
    const running = this.inflight.get(key);
    if (running) return running;

    const task = this.schedule(async () => {
      try {
        const detail = await this.gateway?.series(provider, slug);
        const raw = detail?.coverPath ?? null;
        const url = raw ? NoriClient.coverURL(raw, provider) : null;
        if (url) {
          this.store.source[key] = url;
          this.trim();
          this.save();
          this.notify(slug);
          return url;
        }
        this.store.missing[key] = Date.now();
        this.save();
        return null;
      } catch (cause) {
        this.store.missing[key] = Date.now();
        this.save();
        log("data", "Cover nicht gefunden", slug, (cause as Error)?.message);
        return null;
      } finally {
        this.inflight.delete(key);
      }
    });
    this.inflight.set(key, task);
    return task;
  }

  /**
   * Backdrop über TMDB, wenn ein Schlüssel eingetragen ist.
   *
   * ## Was hier vorher stand
   *
   * Eine einzige Suche mit dem Titel der Quelle, und daraus
   * `results.find((row) => row.backdrop_path)` — also **die erste Zeile mit
   * einem Bild**, ohne jede Prüfung, ob sie überhaupt zu der gesuchten Serie
   * gehört. Der Apple-Kern bewertet seit Langem (`TMDBMatcher`) und lehnt
   * Treffer ab, die nicht am Titel hängen; der Fernseher tat das nicht.
   * Dieselbe Serie konnte dadurch auf iPhone und Fernseher verschiedene
   * Bilder zeigen, und auf dem Fernseher das falsche.
   *
   * Jetzt läuft dieselbe Bewertung wie auf Apple, aus `@nori/core`.
   */
  async ensureBackdrop(slug: string, title: string, provider: CatalogProvider): Promise<string | null> {
    if (!this.tmdbKey) return null;
    const key = this.key(slug, provider);
    const known = this.store.backdrop[key];
    if (known) return known;
    const missedAt = this.store.tmdbMissing[key];
    if (missedAt && Date.now() - missedAt < TMDB_MISS_MAX_AGE) return null;

    let answered = false;
    for (const query of tmdb.queries(title).slice(0, MAX_QUERIES)) {
      const outcome = await this.searchTmdb(query);
      if (outcome.failure) {
        // Schlüssel abgelehnt oder Ratenbegrenzung gilt für jede weitere
        // Anfrage genauso — und darf nie als „gibt es nicht" abgelegt werden.
        if (outcome.failure === "unauthorized" || outcome.failure === "rateLimited") return null;
        continue;
      }
      answered = true;
      const candidates = outcome.rows.map(tmdb.candidateFromRow).filter((c): c is tmdb.TmdbCandidate => c !== null);
      const hit = tmdb.best(candidates, query, provider);
      if (!hit) continue;
      const url = tmdb.imageURL(hit.backdropPath, "backdropHero");
      if (!url) {
        // Die Serie stimmt, sie hat nur kein Breitbild. Das ist eine
        // Auskunft, kein Fehlschlag — und kein Grund weiterzusuchen.
        this.store.tmdbMissing[key] = Date.now();
        this.save();
        return null;
      }
      this.store.backdrop[key] = url;
      this.save();
      this.notify(slug);
      return url;
    }

    // Nur merken, wenn TMDB überhaupt geantwortet hat.
    if (answered) {
      this.store.tmdbMissing[key] = Date.now();
      this.save();
    }
    return null;
  }

  /** Eine Suche, die zwischen „nichts gefunden" und „nicht geantwortet" trennt. */
  private async searchTmdb(query: string): Promise<{ rows: tmdb.TmdbRow[]; failure: tmdb.TmdbFailure | null }> {
    const search = new URL("https://api.themoviedb.org/3/search/tv");
    search.searchParams.set("api_key", this.tmdbKey);
    search.searchParams.set("query", query);
    search.searchParams.set("language", "de-DE");
    search.searchParams.set("include_adult", "false");
    try {
      const res = await fetch(search.toString());
      const failure = tmdb.failureFromStatus(res.status);
      if (failure) return { rows: [], failure };
      const body = (await res.json()) as { results?: tmdb.TmdbRow[] };
      return { rows: body.results ?? [], failure: null };
    } catch (cause) {
      // Bewusst ohne die Adresse: sie trägt den Schlüssel.
      warn("data", "TMDB nicht erreichbar", (cause as Error)?.message);
      return { rows: [], failure: "network" };
    }
  }

  clear(): void {
    this.store = emptyStore();
    this.save();
  }

  private key(slug: string, provider: CatalogProvider): string {
    return `${provider}|${slug}`;
  }

  private notify(slug: string): void {
    for (const listener of this.listeners) listener(slug);
  }

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

  private trim(): void {
    const keys = Object.keys(this.store.source);
    if (keys.length <= MAX_ENTRIES) return;
    // Ältestes zuerst: die Einfügereihenfolge des Objekts reicht dafür aus,
    // und ein Fernseher soll für einen Cache keine Zeitstempel mitführen.
    for (const key of keys.slice(0, keys.length - MAX_ENTRIES)) {
      delete this.store.source[key];
    }
  }

  private save(): void {
    if (this.saveTimer !== null) window.clearTimeout(this.saveTimer);
    this.saveTimer = window.setTimeout(() => {
      try {
        localStorage.setItem(STORE_KEY, JSON.stringify(this.store));
      } catch (cause) {
        // Voller Speicher ist auf einem Fernseher ein realer Zustand. Dann
        // lieber den Cache wegwerfen als jede weitere Ablage scheitern lassen.
        warn("data", "Cover-Cache voll, wird geleert", (cause as Error)?.message);
        this.store = emptyStore();
        try {
          localStorage.setItem(STORE_KEY, JSON.stringify(this.store));
        } catch {
          /* aufgeben */
        }
      }
    }, 600);
  }
}

export const covers = new CoverIndex();
