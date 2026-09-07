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

import { NoriClient, type CatalogProvider, type NoriGateway } from "@nori/core";
import { log, warn } from "./log";

const STORE_KEY = "nori.covers.v1";
const MAX_ENTRIES = 3000;
const MAX_CONCURRENT = 4;

interface CoverStore {
  source: Record<string, string>;
  backdrop: Record<string, string>;
  missing: Record<string, number>;
}

function emptyStore(): CoverStore {
  return { source: {}, backdrop: {}, missing: {} };
}

function loadStore(): CoverStore {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    if (!raw) return emptyStore();
    const parsed = JSON.parse(raw) as Partial<CoverStore>;
    return {
      source: parsed.source ?? {},
      backdrop: parsed.backdrop ?? {},
      missing: parsed.missing ?? {},
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

  /** Backdrop über TMDB, wenn ein Schlüssel eingetragen ist. */
  async ensureBackdrop(slug: string, title: string, provider: CatalogProvider): Promise<string | null> {
    if (!this.tmdbKey) return null;
    const key = this.key(slug, provider);
    const known = this.store.backdrop[key];
    if (known) return known;
    try {
      const type = provider === "aniworld" ? "tv" : "tv";
      const search = new URL(`https://api.themoviedb.org/3/search/${type}`);
      search.searchParams.set("api_key", this.tmdbKey);
      search.searchParams.set("query", title);
      search.searchParams.set("language", "de-DE");
      const res = await fetch(search.toString());
      if (!res.ok) return null;
      const body = (await res.json()) as { results?: { backdrop_path?: string | null }[] };
      const path = body.results?.find((row) => row.backdrop_path)?.backdrop_path;
      if (!path) return null;
      const url = `https://image.tmdb.org/t/p/w1280${path}`;
      this.store.backdrop[key] = url;
      this.save();
      this.notify(slug);
      return url;
    } catch (cause) {
      warn("data", "TMDB nicht erreichbar", (cause as Error)?.message);
      return null;
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
