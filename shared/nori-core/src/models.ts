// Datenmodell von Nori, eins zu eins aus
// `native/NoriCore/Sources/NoriCore/Models.swift`.
//
// Diese Datei ist die TypeScript-Seite desselben Vertrags, den
// `config/contract.json` beschreibt. Sie erfindet **kein** zweites Modell:
// Feldnamen, Optionalität und Bedeutung sind aus dem Swift-Kern übernommen,
// damit eine `library.json` aus der iOS- oder macOS-App hier ohne Umschreiben
// gelesen werden kann und umgekehrt.
//
// Wer hier ein Feld ändert, ändert es auch in
// `native/NoriCore/Sources/NoriCore/Models.swift` und in `config/contract.json`.

/** Woher ein Titel stammt. */
export type CatalogProvider = "aniworld" | "serienstream";

export const CATALOG_PROVIDERS: CatalogProvider[] = ["aniworld", "serienstream"];

/**
 * Beschreibung einer Quelle.
 *
 * Wie im Swift-Kern bewusst als vollständige Tabelle statt als
 * „aniworld oder sonst": eine dritte Quelle muss hier einen eigenen Eintrag
 * bekommen und kann sich nicht stillschweigend wie Serienstream verhalten.
 */
export interface ProviderInfo {
  readonly id: CatalogProvider;
  readonly label: string;
  readonly kind: string;
  readonly origin: string;
  readonly catalogPath: string;
  readonly calendarPath: string;
  readonly streamPrefix: string;
}

export const PROVIDERS: Record<CatalogProvider, ProviderInfo> = {
  aniworld: {
    id: "aniworld",
    label: "AniWorld",
    kind: "Anime",
    origin: "https://aniworld.to",
    catalogPath: "/animes",
    calendarPath: "/animekalender",
    streamPrefix: "/anime/stream",
  },
  serienstream: {
    id: "serienstream",
    label: "Serienstream",
    kind: "Serien",
    origin: "https://serienstream.to",
    catalogPath: "/serien?by=genre",
    calendarPath: "/api/calendar",
    streamPrefix: "/serie",
  },
};

export function providerInfo(provider: CatalogProvider): ProviderInfo {
  return PROVIDERS[provider];
}

export function seriesPath(provider: CatalogProvider, slug: string, season?: string | null): string {
  const base = `${PROVIDERS[provider].streamPrefix}/${slug}`;
  if (!season) return base;
  if (season === "filme") return `${base}/filme`;
  return `${base}/staffel-${season}`;
}

export function episodePathFor(
  provider: CatalogProvider,
  slug: string,
  season: string,
  episode: number,
): string {
  const prefix = PROVIDERS[provider].streamPrefix;
  if (season === "filme") return `${prefix}/${slug}/filme/film-${episode}`;
  return `${prefix}/${slug}/staffel-${season || "1"}/episode-${episode}`;
}

/**
 * Was die Bibliothek zeigt — Quelle **und** Genre.
 *
 * K-Drama ist keine dritte Seite, sondern ein Genre bei Serienstream. Deshalb
 * reicht `provider` allein zum Filtern nicht.
 */
export type LibraryScope = "all" | "aniworld" | "serienstream" | "kdrama";

export const LIBRARY_SCOPES: LibraryScope[] = ["all", "aniworld", "serienstream", "kdrama"];

interface ScopeInfo {
  readonly label: string;
  readonly headline: string;
  readonly provider: CatalogProvider | null;
  readonly genre: string | null;
}

export const SCOPES: Record<LibraryScope, ScopeInfo> = {
  all: { label: "Alle", headline: "Alle Titel", provider: null, genre: null },
  aniworld: { label: "Anime", headline: "Alle Anime", provider: "aniworld", genre: null },
  serienstream: { label: "Serien", headline: "Alle Serien", provider: "serienstream", genre: null },
  kdrama: { label: "K-Drama", headline: "Alle K-Dramas", provider: "serienstream", genre: "K-Drama" },
};

/** Gehört ein Eintrag dieser Quelle in den Bereich? Nur die Quelle. */
export function scopeIncludesProvider(scope: LibraryScope, other?: CatalogProvider | null): boolean {
  const want = SCOPES[scope].provider;
  if (!want) return true;
  // Einträge ohne Quelle stammen aus einem älteren Stand und fallen nicht raus.
  if (!other) return true;
  return want === other;
}

/** Gehört ein Katalogeintrag in den Bereich? Quelle **und** Genre. */
export function scopeIncludesItem(scope: LibraryScope, item: CatalogItem): boolean {
  if (!scopeIncludesProvider(scope, item.provider)) return false;
  const genre = SCOPES[scope].genre;
  if (!genre) return true;
  return item.genres.some((g) => g.toLowerCase() === genre.toLowerCase());
}

export interface CatalogItem {
  slug: string;
  title: string;
  alts: string[];
  genres: string[];
  /** Vom Parser bewusst nicht gesetzt — der sieht nur HTML. Gestempelt beim Laden. */
  provider?: CatalogProvider;
}

/** Zwei Quellen können denselben Slug führen; die Kennung trägt deshalb beides. */
export function catalogItemId(item: CatalogItem): string {
  return `${item.provider ?? "?"}|${item.slug}`;
}

export interface CatalogResult {
  items: CatalogItem[];
  source: string;
  fetchedAt: number;
}

export interface SeasonRef {
  id: string;
  label: string;
}

export interface Episode {
  number: number;
  germanTitle: string;
  englishTitle: string;
  path: string;
  hosters: string[];
  languages: string[];
}

export interface SeriesDetail {
  slug: string;
  title: string;
  alts: string[];
  description: string;
  coverPath?: string | null;
  yearStart?: string | null;
  yearEnd?: string | null;
  fsk?: string | null;
  imdb?: string | null;
  genres: string[];
  seasons: SeasonRef[];
  activeSeason: string;
  episodes: Episode[];
}

export interface HosterOption {
  name: string;
  lang: string;
  langKey: string;
  redirectPath: string;
}

export interface WatchInfo {
  path: string;
  title: string;
  germanTitle: string;
  englishTitle: string;
  hosters: HosterOption[];
}

export type PlayKind = "hls" | "mp4";

/**
 * Neutrales Wiedergabeergebnis — für alle Nori-Clients dasselbe.
 *
 * `referer` ist kein Beiwerk: viele Hoster liefern das Video nur aus, wenn der
 * Abruf die Seite mitschickt, von der es stammt. AVPlayer bekommt ihn am Asset
 * gesetzt, der webOS-Client über den Nori-Server, der ihn beim Weiterreichen
 * setzt.
 */
export interface PlaySource {
  kind: PlayKind;
  url: string;
  hoster: string;
  lang: string;
  referer?: string | null;
}

export interface WatchProgress {
  slug: string;
  title: string;
  season: string;
  episode: number;
  episodePath: string;
  germanTitle: string;
  englishTitle: string;
  positionSec: number;
  durationSec: number;
  updatedAt: number;
  lang?: string | null;
  completed?: boolean | null;
  /** Seit Library-Schema v2. Optional, damit 1.x-Stände sauber dekodieren. */
  provider?: CatalogProvider | null;
}

export interface RecentItem {
  slug: string;
  title: string;
  viewedAt: number;
  provider?: CatalogProvider | null;
}

export interface AiringEntry {
  airingAt: number;
  episode: number;
  season: string;
  title: string;
  english?: string | null;
  slug: string;
  languages: string[];
  dayKey: string;
  dayLabel: string;
  coverPath?: string | null;
  provider?: CatalogProvider;
}

export interface CalendarPayload {
  upcoming: AiringEntry[];
  recent: AiringEntry[];
  fetchedAt: number;
}

export const NORI_USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

export type NoriErrorKind = "network" | "parse" | "blocked" | "notFound" | "hoster";

/** Entspricht `NoriError` im Swift-Kern — dieselben fünf Fälle. */
export class NoriError extends Error {
  readonly kind: NoriErrorKind;

  constructor(kind: NoriErrorKind, message: string) {
    super(message);
    this.name = "NoriError";
    this.kind = kind;
  }

  static network(m: string) { return new NoriError("network", m); }
  static parse(m: string) { return new NoriError("parse", m); }
  static blocked(m: string) { return new NoriError("blocked", m); }
  static notFound(m: string) { return new NoriError("notFound", m); }
  static hoster(m: string) { return new NoriError("hoster", m); }
}
