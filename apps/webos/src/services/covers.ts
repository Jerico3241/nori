// Bildbeschaffung: welches Bild zu einem Titel gehört und woher es kommt.
//
// ## Zwei Quellen, eine Reihenfolge
//
// 1. **TMDB**, wenn es einen sicheren Treffer gibt. Poster, Breitbild und
//    Schriftzug in Auflösungen, die auf einem Fernseher tragen.
// 2. **Das Cover der Quelle.** Es ist immer das richtige — AniWorld und
//    Serienstream liefern es zur Serie aus —, aber klein und ohne Breitbild.
// 3. **Der Ersatz aus dem Titel.** Kein Loch im Raster.
//
// Diese Reihenfolge ist die aus der Aufgabenstellung, und sie gilt in **beide**
// Richtungen: TMDB darf vorhandene gute Quelldaten nie durch leere
// TMDB-Werte ersetzen. Deshalb wird nirgends „TMDB hat geantwortet" mit „TMDB
// hat etwas" verwechselt — ein Treffer ohne Poster liefert kein Poster, und
// dann steht das Cover der Quelle.
//
// ## Warum die Quellcover überhaupt nachgeladen werden müssen
//
// Die Katalogseiten beider Quellen sind reine Titellisten ohne Bilder — die
// Adresse des Covers steht nur auf der Detailseite, und sie enthält einen
// Zufallsanteil, lässt sich also nicht aus dem Slug bilden. Der Swift-Kern löst
// das mit `CoverIndex`: Detailseite bei Bedarf nachladen, höchstens vier
// gleichzeitig, Ergebnis dauerhaft ablegen. Hier steht dasselbe Verfahren.

import { NoriClient, type CatalogProvider, type NoriGateway } from "@nori/core";
import { log, warn } from "./log";
import { tmdb } from "./tmdb";

const STORE_KEY = "nori.covers.v2";
const MAX_ENTRIES = 3000;
const MAX_CONCURRENT = 4;
/** Ein Fehlschlag wird eine Stunde lang nicht wiederholt. */
const MISS_MAX_AGE = 3_600_000;

interface CoverStore {
  version: number;
  source: Record<string, string>;
  missing: Record<string, number>;
}

function emptyStore(): CoverStore {
  return { version: 2, source: {}, missing: {} };
}

function loadStore(): CoverStore {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    if (!raw) return emptyStore();
    const parsed = JSON.parse(raw) as Partial<CoverStore>;
    if (parsed.version !== 2) return emptyStore();
    return {
      version: 2,
      source: parsed.source ?? {},
      missing: parsed.missing ?? {},
    };
  } catch {
    return emptyStore();
  }
}

/** Woher ein Bild stammt — für die Kachel unerheblich, für die Fehlersuche nicht. */
export type CoverKind = "source" | "tmdb";

/** Was ein Titel an Text und Zahlen beisteuert, sobald TMDB ihn kennt. */
export interface TitleDetails {
  tmdbID: number | null;
  overview: string;
  /** TMDBs Zehnerskala; die Oberfläche rechnet auf Sterne um. */
  rating: number | null;
  votes: number | null;
  logo: string | null;
  backdrop: string | null;
  poster: string | null;
}

export const NO_DETAILS: TitleDetails = {
  tmdbID: null,
  overview: "",
  rating: null,
  votes: null,
  logo: null,
  backdrop: null,
  poster: null,
};

type Listener = () => void;

export interface ArtworkRequest {
  slug: string;
  provider: CatalogProvider;
  /** Der Titel, wie die Quelle ihn führt. Ohne ihn geht keine TMDB-Suche. */
  title?: string;
  /** Alternativtitel der Quelle — der Grund, warum Eindeutschungen treffen. */
  alts?: string[];
  /** Erscheinungsjahr laut Quelle, sofern bekannt. Trennt Neuverfilmungen. */
  year?: number | null;
}

class ArtworkIndex {
  private store = loadStore();
  private inflight = new Map<string, Promise<string | null>>();
  private queue: (() => void)[] = [];
  private running = 0;
  private saveTimer: number | null = null;
  /**
   * Zuhörer je Titel, nicht ein Topf für alle.
   *
   * Vorher meldete sich jede Kachel für **jede** Bildänderung an und verglich
   * selbst, ob sie gemeint war. Auf einer Startseite mit achtzig Kacheln waren
   * das achtzig Aufrufe für ein einziges eingetroffenes Poster — achtzigmal je
   * Treffer, und Treffer kommen beim Aufbau im Sekundentakt. Jetzt erreicht
   * ein Poster genau die Kacheln, die es zeigen.
   */
  private listeners = new Map<string, Set<Listener>>();
  private anyListeners = new Set<Listener>();
  private gateway: NoriGateway | null = null;
  private unsubscribeTmdb: (() => void) | null = null;

  configure(gateway: NoriGateway): void {
    this.gateway = gateway;
    if (this.unsubscribeTmdb) return;
    // Ein TMDB-Treffer, der nach dem Rendern eintrifft, muss die Kachel
    // erreichen. Ohne diese Weitergabe stünde dort bis zum nächsten
    // Seitenwechsel weiter das Quellcover.
    this.unsubscribeTmdb = tmdb.subscribe((key) => {
      const slug = key.split("|")[1] ?? key;
      this.notify(slug);
    });
  }

  /** Auf Änderungen an genau einem Titel hören; `"*"` auf alle. */
  subscribe(slug: string, listener: Listener): () => void {
    if (slug === "*") {
      this.anyListeners.add(listener);
      return () => this.anyListeners.delete(listener);
    }
    const set = this.listeners.get(slug) ?? new Set<Listener>();
    set.add(listener);
    this.listeners.set(slug, set);
    return () => {
      set.delete(listener);
      if (set.size === 0) this.listeners.delete(slug);
    };
  }

  private key(slug: string, provider: CatalogProvider): string {
    return `${provider}|${slug}`;
  }

  /**
   * Das beste bekannte Poster, ohne etwas anzustoßen.
   *
   * TMDB vor Quelle: das Quellcover ist 220 px breit, auf einer 218 px breiten
   * Kachel eines 4K-Panels sichtbar weich.
   */
  cached(slug: string, provider: CatalogProvider): string | null {
    return tmdb.art(slug, provider)?.poster
      ?? this.store.source[this.key(slug, provider)]
      ?? null;
  }

  /** Nur das Cover der Quelle. Für den Rückfall, wenn ein TMDB-Bild scheitert. */
  sourceCover(slug: string, provider: CatalogProvider): string | null {
    return this.store.source[this.key(slug, provider)] ?? null;
  }

  backdrop(slug: string, provider: CatalogProvider): string | null {
    return tmdb.art(slug, provider)?.backdrop ?? null;
  }

  logo(slug: string, provider: CatalogProvider): string | null {
    return tmdb.art(slug, provider)?.logo ?? null;
  }

  /** Text und Zahlen von TMDB, soweit vorhanden. Ohne Abruf. */
  details(slug: string, provider: CatalogProvider): TitleDetails {
    const art = tmdb.art(slug, provider);
    if (!art) return NO_DETAILS;
    return {
      tmdbID: art.tmdbID,
      overview: art.overview,
      rating: art.rating,
      votes: art.votes,
      logo: art.logo,
      backdrop: art.backdrop,
      poster: art.poster,
    };
  }

  /**
   * Bilder besorgen: TMDB zuerst, die Quelle nur, wenn TMDB kein Poster hat.
   *
   * Vorher liefen beide gleichzeitig. Das Quellcover steht aber nur auf der
   * Detailseite der Quelle — für jede Kachel also eine ganze HTML-Seite, auch
   * für die neun von zehn, bei denen TMDB ohnehin ein schärferes Poster
   * liefert. Auf einem Fernseher mit sechzig Kacheln im Katalog waren das
   * sechzig Seiten, geparst auf einer schwachen CPU.
   *
   * Gibt das beste Poster zurück, das am Ende vorliegt.
   */
  async ensure(request: ArtworkRequest): Promise<string | null> {
    const known = this.cached(request.slug, request.provider);
    const art = request.title && tmdb.available
      ? await tmdb.ensureArt({
        slug: request.slug,
        title: request.title,
        alternates: request.alts,
        provider: request.provider,
        expectedYear: request.year ?? null,
      }).catch(() => null)
      : null;
    if (art?.poster) return art.poster;
    const source = await this.ensureSourceCover(request.slug, request.provider);
    return source ?? known;
  }

  /** Ob zu diesem Titel schon eine TMDB-Zuordnung vorliegt. */
  hasTmdb(slug: string, provider: CatalogProvider): boolean {
    return tmdb.art(slug, provider) !== null;
  }

  /**
   * Das Cover der Quelle über die Detailseite beschaffen.
   *
   * Kostet eine Seite pro Titel, aber nur einmal: das Ergebnis liegt danach im
   * `localStorage` und übersteht den Neustart.
   */
  async ensureSourceCover(slug: string, provider: CatalogProvider): Promise<string | null> {
    const key = this.key(slug, provider);
    const known = this.store.source[key];
    if (known) return known;
    const failedAt = this.store.missing[key];
    // Sonst rennt jede Rückkehr auf die Startseite erneut gegen dieselbe
    // leere Seite.
    if (failedAt && Date.now() - failedAt < MISS_MAX_AGE) return null;
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

  /** Das Breitbild, notfalls über eine TMDB-Suche. */
  async ensureBackdrop(request: ArtworkRequest): Promise<string | null> {
    if (!request.title) return this.backdrop(request.slug, request.provider);
    const art = await tmdb.ensureArt({
      slug: request.slug,
      title: request.title,
      alternates: request.alts,
      provider: request.provider,
      expectedYear: request.year ?? null,
    }).catch(() => null);
    return art?.backdrop ?? null;
  }

  /** Den Schriftzug, notfalls nachgeladen. Nur wo er auch gezeigt wird. */
  async ensureLogo(request: ArtworkRequest): Promise<string | null> {
    if (!request.title) return this.logo(request.slug, request.provider);
    return tmdb.ensureLogo({
      slug: request.slug,
      title: request.title,
      alternates: request.alts,
      provider: request.provider,
    }).catch(() => null);
  }

  /**
   * Alles verwerfen — Quellcover **und** TMDB.
   *
   * In den Einstellungen als „Bildspeicher leeren". Wer das drückt, hat ein
   * falsches Bild gesehen; dann muss auch die TMDB-Zuordnung weg, nicht nur
   * das Bild darüber.
   */
  clear(): void {
    this.store = emptyStore();
    this.save();
    tmdb.clear();
    this.notify("*");
  }

  private notify(slug: string): void {
    if (slug === "*") {
      for (const set of this.listeners.values()) {
        for (const listener of set) listener();
      }
    } else {
      const set = this.listeners.get(slug);
      if (set) for (const listener of set) listener();
    }
    for (const listener of this.anyListeners) listener();
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

export const covers = new ArtworkIndex();
