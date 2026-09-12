// Was auf Noris Startseite steht, und warum es dort steht.
//
// Portierung von `native/NoriCore/Sources/NoriCore/HomeFeed.swift`. Diese
// Datei enthält **keine** Oberfläche und kein Netz — nur Werte und Rechnungen.
// Das ist Absicht: die Reihenfolge der Titel ist der Teil der Startseite, der
// am ehesten falsch ist und sich am schwersten ansieht. Als reine Funktion
// lässt sie sich prüfen („ein alter, stark trendender Titel steht vor einem
// neuen, den niemand kennt"), als verstreute Sortierung in einem Render nicht.
//
// Die Aufgabenteilung, die überall in dieser Datei gilt:
//
//     Nori-Provider  →  Was gibt es überhaupt?
//     TMDB           →  Was ist das, wie sieht es aus, wie aktuell/beliebt?
//
// Deshalb beginnt jede Reihe beim Nori-Katalog und wird von TMDB nur
// **angereichert und gewichtet**. Nie umgekehrt: eine TMDB-Liste, aus der
// Kacheln entstehen, könnte Titel zeigen, die Nori gar nicht abspielen kann.
//
// Zeitangaben sind durchgehend Millisekunden seit 1970 — dieselbe Einheit wie
// im gespeicherten Bibliotheksstand.

import type { AiringEntry, CatalogItem, CatalogProvider, WatchProgress } from "../models.js";
import { providerFromPath, watchRatio } from "../rules.js";
import {
  hasBackdrop as candidateHasBackdrop, normalizeTitle, scoreCandidate, stripVariants,
  type TMDBCandidate,
} from "./matcher.js";

const DAY = 86_400_000;

// MARK: - Titel

/**
 * Ein Titel, den Nori tatsächlich anbietet.
 *
 * Entsteht ausschließlich aus `CatalogItem`, also aus dem, was AniWorld oder
 * Serienstream führen. Es gibt bewusst keinen Weg, einen `HomeTitle` aus
 * TMDB-Daten zu bauen.
 */
export interface HomeTitle {
  slug: string;
  title: string;
  provider: CatalogProvider;
  genres: string[];
  alts: string[];
}

/** Zwei Quellen können denselben Slug führen — die Kennung trägt deshalb beides. */
export function homeTitleId(title: HomeTitle): string {
  return `${title.provider}|${title.slug}`;
}

export function homeTitleFrom(item: CatalogItem, fallback: CatalogProvider = "aniworld"): HomeTitle {
  return {
    slug: item.slug,
    title: item.title,
    provider: item.provider ?? fallback,
    genres: item.genres,
    alts: item.alts,
  };
}

// MARK: - Signale

/**
 * Was TMDB über einen Nori-Titel weiß, soweit es für die Reihenfolge zählt.
 *
 * Alles optional, und das ist der Normalfall, nicht die Ausnahme: ohne
 * Schlüssel, ohne Netz oder ohne sicheren Treffer bleibt die Struktur leer.
 * Die Startseite muss dann trotzdem stehen — jede Rechnung hier kommt mit
 * leeren Signalen zurecht.
 */
export interface TMDBSignals {
  tmdbID: number | null;
  popularity: number | null;
  voteAverage: number | null;
  voteCount: number | null;
  /** Erstausstrahlung der Serie. */
  firstAirDate: number | null;
  /**
   * Letzte ausgestrahlte Folge. Sagt mehr über „neu" als die Erstausstrahlung:
   * eine zehn Jahre alte Serie mit einer Staffel von letzter Woche ist neu,
   * ihre Erstausstrahlung nicht.
   */
  lastAirDate: number | null;
  /**
   * Platz in TMDBs Trendliste dieser Woche, 1-basiert. `null` heißt „steht
   * nicht drauf" — das ist keine schlechte Platzierung, sondern keine.
   */
  trendingRank: number | null;
  genreIDs: number[];
  hasBackdrop: boolean;
}

export function emptySignals(): TMDBSignals {
  return {
    tmdbID: null,
    popularity: null,
    voteAverage: null,
    voteCount: null,
    firstAirDate: null,
    lastAirDate: null,
    trendingRank: null,
    genreIDs: [],
    hasBackdrop: false,
  };
}

export function signalsAreEmpty(signals: TMDBSignals): boolean {
  return signals.tmdbID === null && signals.popularity === null && signals.trendingRank === null;
}

/** Ein Titel mit allem, was die Reihenfolge braucht. */
export interface HomeCandidate {
  title: HomeTitle;
  signals: TMDBSignals;
  /** Wie weit der Titel gesehen ist, 0 bis 1. Aus dem Fortschritt, nicht aus TMDB. */
  watchedRatio: number;
  inWatchlist: boolean;
  /** Hat Nori zu dem Titel in den letzten Tagen eine neue Folge gesehen? */
  hasFreshEpisode: boolean;
}

export function candidateId(candidate: HomeCandidate): string {
  return homeTitleId(candidate.title);
}

// MARK: - Reihenfolge

/** Was „neu" heißt: neunzig Tage. */
export const NEW_WINDOW = 90 * DAY;

/**
 * Ist der Titel im Sinne der Reihe „neu"?
 *
 * Maßgeblich ist die **letzte** Ausstrahlung, ersatzweise die erste. Eine
 * laufende Staffel einer alten Serie ist neu; eine alte Serie ohne neue Folgen
 * nicht, egal wie beliebt sie ist.
 */
export function isNew(signals: TMDBSignals, now: number): boolean {
  const reference = signals.lastAirDate ?? signals.firstAirDate;
  if (reference === null) return false;
  const age = now - reference;
  return age >= -14 * DAY && age <= NEW_WINDOW;
}

/**
 * Der Punktwert für „Neu & beliebt".
 *
 * Vier Beiträge, bewusst in dieser Größenordnung:
 *
 * - **Trend (0–140).** TMDBs Wochenliste. Das stärkste Signal, weil es als
 *   einziges sagt, was *gerade jetzt* gesucht wird.
 * - **Beliebtheit (0–60), logarithmisch.** TMDBs `popularity` ist nach oben
 *   offen und extrem schief verteilt — linear gewichtet schöbe ein einziger
 *   Ausreißer alles andere aus der Reihe.
 * - **Aktualität (0–90).** Fällt über das Fenster linear ab. Eine neue Folge
 *   aus Noris eigenem Kalender zählt zusätzlich.
 * - **Bewertung (−12…+24), nur mit Grundlage.** Unter 50 Stimmen zählt sie
 *   gar nicht. Sonst stünde ein Titel mit 10,0 aus zwei Stimmen vor einer
 *   weltweit laufenden Serie.
 *
 * Ein durchgesehener Titel wird gedämpft: „Neu & beliebt" soll etwas zeigen,
 * das man noch vor sich hat.
 */
export function newAndPopularScore(candidate: HomeCandidate, now: number): number {
  const signals = candidate.signals;
  let score = 0;

  if (signals.trendingRank !== null && signals.trendingRank > 0) {
    score += Math.max(0, 140 - (signals.trendingRank - 1) * 3.5);
  }

  if (signals.popularity !== null && signals.popularity > 0) {
    score += Math.min(60, 9 * Math.log2(1 + signals.popularity));
  }

  const reference = signals.lastAirDate ?? signals.firstAirDate;
  if (reference !== null) {
    const age = now - reference;
    if (age <= NEW_WINDOW) {
      // Auch noch nicht ausgestrahlte Folgen („age" negativ) zählen voll: eine
      // Serie, die diese Woche anläuft, ist das Neueste, was es gibt.
      score += 90 * (1 - Math.max(0, age) / NEW_WINDOW);
    }
  }
  if (candidate.hasFreshEpisode) score += 35;

  if (signals.voteAverage !== null && signals.voteCount !== null && signals.voteCount >= 50) {
    const confidence = Math.min(1, signals.voteCount / 500);
    score += Math.max(-12, Math.min(24, (signals.voteAverage - 6.5) * 8)) * confidence;
  }

  // Schon gesehen heißt nicht „uninteressant", aber es gehört nach hinten.
  score *= 1 - 0.45 * Math.min(1, candidate.watchedRatio);

  return score;
}

interface Scored {
  candidate: HomeCandidate;
  score: number;
}

/**
 * Absteigend nach Punkten, bei Gleichstand nach Kennung.
 *
 * Der zweite Schlüssel ist kein Schönheitsfehler: ohne ihn ist die Reihenfolge
 * gleichwertiger Titel unbestimmt, und die Startseite würde sich bei jedem
 * Neuaufbau anders sortieren.
 */
function ordered(scored: Scored[]): HomeCandidate[] {
  return [...scored]
    .sort((a, b) => (a.score !== b.score
      ? b.score - a.score
      : candidateId(a.candidate).localeCompare(candidateId(b.candidate))))
    .map((entry) => entry.candidate);
}

export interface RowOptions {
  /**
   * Kennungen, die schon woanders stehen — der Kopfbereich vor allem. Dieselben
   * fünf Titel in Hero und erster Reihe lassen die Seite kürzer wirken.
   */
  excluding?: Set<string>;
  limit?: number;
}

/** „Neu & beliebt", fertig sortiert. */
export function newAndPopular(
  candidates: HomeCandidate[],
  now: number,
  options: RowOptions = {},
): HomeCandidate[] {
  const excluding = options.excluding ?? new Set<string>();
  const scored: Scored[] = [];
  for (const candidate of candidates) {
    if (excluding.has(candidateId(candidate))) continue;
    if (signalsAreEmpty(candidate.signals)) continue;
    const score = newAndPopularScore(candidate, now);
    if (score <= 0) continue;
    scored.push({ candidate, score });
  }
  return ordered(scored).slice(0, options.limit ?? 20);
}

/**
 * Reine Trendreihe: was diese Woche läuft, ohne Aktualitätsanteil.
 *
 * Eigene Reihe nur dort, wo sie sich von „Neu & beliebt" wirklich
 * unterscheidet — sonst stünde zweimal dasselbe untereinander. Der Aufrufer
 * prüft das über `excluding`.
 */
export function trending(candidates: HomeCandidate[], options: RowOptions = {}): HomeCandidate[] {
  const excluding = options.excluding ?? new Set<string>();
  const scored: Scored[] = [];
  for (const candidate of candidates) {
    if (excluding.has(candidateId(candidate))) continue;
    const rank = candidate.signals.trendingRank;
    if (rank === null) continue;
    // Negativ, damit dieselbe absteigende Sortierung greift: Platz 1 ist der
    // beste, nicht der schlechteste.
    scored.push({ candidate, score: -rank });
  }
  return ordered(scored).slice(0, options.limit ?? 20);
}

/** Top bewertet — aber nur mit belastbarer Stimmenzahl. */
export function topRated(
  candidates: HomeCandidate[],
  options: RowOptions & { minimumVotes?: number } = {},
): HomeCandidate[] {
  const excluding = options.excluding ?? new Set<string>();
  const minimumVotes = options.minimumVotes ?? 300;
  const scored: Scored[] = [];
  for (const candidate of candidates) {
    if (excluding.has(candidateId(candidate))) continue;
    const { voteAverage, voteCount } = candidate.signals;
    if (voteAverage === null || voteCount === null) continue;
    if (voteCount < minimumVotes || voteAverage <= 0) continue;
    scored.push({ candidate, score: voteAverage });
  }
  return ordered(scored).slice(0, options.limit ?? 20);
}

/**
 * Die Titel, aus denen der Kopfbereich wählt.
 *
 * Zwei Bedingungen, die für die übrigen Reihen nicht gelten:
 *
 * - **Es muss ein Breitbild geben.** Der Kopfbereich ist auf dem Fernseher
 *   fast der ganze erste Bildschirm. Ein 2:3-Poster darin ist entweder
 *   zerschnitten oder von Balken umgeben.
 * - **Nicht durchgesehen.** „Abspielen" auf einer Serie, die man beendet hat,
 *   ist ein leeres Versprechen.
 *
 * Die Auswahl **rotiert** über `day`: aus den besten Kandidaten wird abhängig
 * vom Tag gewählt, innerhalb eines Tages stabil. Ohne das stünde dort
 * wochenlang derselbe Titel; mit Zufall stünde bei jedem Neuzeichnen ein
 * anderer, was beim Scrollen aussieht wie ein Fehler.
 */
export function heroPicks(
  candidates: HomeCandidate[],
  now: number,
  day: number,
  options: { poolSize?: number; limit?: number } = {},
): HomeCandidate[] {
  const scored: Scored[] = [];
  for (const candidate of candidates) {
    if (!candidate.signals.hasBackdrop) continue;
    if (candidate.watchedRatio >= 0.95) continue;
    const score = newAndPopularScore(candidate, now);
    if (score <= 0) continue;
    scored.push({ candidate, score });
  }
  const pool = ordered(scored).slice(0, options.poolSize ?? 8);
  if (pool.length === 0) return [];
  const offset = ((day % pool.length) + pool.length) % pool.length;
  return [...pool.slice(offset), ...pool.slice(0, offset)].slice(0, options.limit ?? 5);
}

// MARK: - Persönliche Empfehlung

/**
 * Was der Nutzer offenbar mag.
 *
 * Ausschließlich aus lokalen Daten: Fortschritt, Merkliste, Verlauf. Es geht
 * nichts an TMDB heraus, um ein Profil zu bilden — TMDB wird nur gefragt,
 * welche Titel zu einer bereits gesehenen Serie passen.
 */
export interface TasteProfile {
  /** Genrename (normalisiert) → Gewicht. */
  genreWeights: Map<string, number>;
  /**
   * TMDB-Genrekennung → Gewicht. Getrennt, weil die Quellen ihre Genres anders
   * benennen als TMDB und eine Übersetzungstabelle nur eine weitere
   * Fehlerquelle wäre.
   */
  tmdbGenreWeights: Map<number, number>;
  /** Alles, womit der Nutzer schon zu tun hatte — `provider|slug`. */
  touched: Set<string>;
  /** Was abgeschlossen ist. Wird härter ausgefiltert als bloß Angefangenes. */
  completed: Set<string>;
  /** TMDB-Kennungen der meistgesehenen Titel, absteigend. */
  seeds: number[];
}

/**
 * Reicht das für eine echte Empfehlung?
 *
 * Zwei angefangene Titel sind kein Geschmack. Darunter zeigt die Startseite
 * ausdrücklich etwas anderes, statt „Für dich" mit einer zweiten
 * Beliebtheitsliste zu füllen.
 */
export function profileIsMeaningful(profile: TasteProfile): boolean {
  return profile.touched.size >= 3 && profile.genreWeights.size > 0;
}

export interface ProfileInput {
  progress: WatchProgress[];
  favorites: string[];
  favoriteSource: Record<string, CatalogProvider>;
  catalog: HomeTitle[];
  signals: Map<string, TMDBSignals>;
  now: number;
}

/**
 * Das Profil aus dem, was lokal vorliegt.
 *
 * Gewichtet nach Nähe und Menge: ein abgeschlossener Titel wiegt am
 * schwersten, ein angefangener nach Sehanteil, ein gemerkter fest aber
 * weniger. Kürzlich Gesehenes wiegt mehr als lange Zurückliegendes.
 */
export function tasteProfile(input: ProfileInput): TasteProfile {
  const out: TasteProfile = {
    genreWeights: new Map(),
    tmdbGenreWeights: new Map(),
    touched: new Set(),
    completed: new Set(),
    seeds: [],
  };
  const seedWeights = new Map<number, number>();
  const byID = new Map<string, HomeTitle>();
  for (const title of input.catalog) {
    const id = homeTitleId(title);
    if (!byID.has(id)) byID.set(id, title);
  }

  const add = (title: HomeTitle, weight: number) => {
    if (weight <= 0) return;
    for (const genre of title.genres.slice(0, 4)) {
      const key = normalizeTitle(genre);
      if (!key) continue;
      out.genreWeights.set(key, (out.genreWeights.get(key) ?? 0) + weight);
    }
    const signal = input.signals.get(homeTitleId(title));
    if (!signal) return;
    for (const genre of signal.genreIDs.slice(0, 4)) {
      out.tmdbGenreWeights.set(genre, (out.tmdbGenreWeights.get(genre) ?? 0) + weight);
    }
    if (signal.tmdbID !== null) {
      seedWeights.set(signal.tmdbID, (seedWeights.get(signal.tmdbID) ?? 0) + weight);
    }
  };

  // Fortschritt, je Serie zusammengefasst: zehn Folgen derselben Serie sind
  // ein Interesse, nicht zehn.
  const perSeries = new Map<string, { ratio: number; updated: number }>();
  for (const item of input.progress) {
    const provider = item.provider ?? providerFromPath(item.episodePath);
    const key = `${provider}|${item.slug}`;
    const ratio = watchRatio(item);
    const existing = perSeries.get(key);
    perSeries.set(key, {
      ratio: Math.max(existing?.ratio ?? 0, ratio),
      updated: Math.max(existing?.updated ?? 0, item.updatedAt),
    });
  }

  for (const [key, entry] of perSeries) {
    out.touched.add(key);
    if (entry.ratio >= 0.9) out.completed.add(key);
    const title = byID.get(key);
    if (!title) continue;
    const days = Math.max(0, input.now - entry.updated) / DAY;
    const recency = 1 / (1 + days / 60);
    add(title, (0.6 + entry.ratio) * recency);
  }

  for (const slug of input.favorites) {
    const provider = input.favoriteSource[slug];
    const match = byID.get(`${provider ?? ""}|${slug}`)
      ?? input.catalog.find((title) => title.slug === slug);
    if (!match) continue;
    out.touched.add(homeTitleId(match));
    add(match, 0.7);
  }

  out.seeds = [...seedWeights.entries()]
    .sort((a, b) => (a[1] === b[1] ? a[0] - b[0] : b[1] - a[1]))
    .slice(0, 6)
    .map(([id]) => id);
  return out;
}

/**
 * Wie gut ein Titel zum Profil passt.
 *
 * `recommended` sind TMDB-Kennungen, die TMDB selbst als ähnlich zu den
 * Seed-Titeln genannt hat, mit der Zahl der Nennungen. Das ist das stärkste
 * Einzelsignal — es kennt Zusammenhänge, die kein Genre abbildet (dieselben
 * Macher, dieselbe Vorlage, dieselbe Zuschauerschaft).
 */
export function tasteScore(
  candidate: HomeCandidate,
  profile: TasteProfile,
  recommended: Map<number, number> = new Map(),
): number {
  let score = 0;

  const id = candidate.signals.tmdbID;
  if (id !== null) {
    const hits = recommended.get(id);
    if (hits !== undefined) {
      // Von mehreren Seed-Titeln empfohlen zu werden wiegt mehr als von einem,
      // aber nicht linear — sonst gewinnt immer derselbe große Nachbar.
      score += 120 + 40 * Math.log2(hits + 1);
    }
  }

  let total = 0;
  for (const value of profile.genreWeights.values()) total += value;
  if (total > 0) {
    let overlap = 0;
    for (const genre of candidate.title.genres.slice(0, 4)) {
      overlap += profile.genreWeights.get(normalizeTitle(genre)) ?? 0;
    }
    score += 100 * Math.min(1, overlap / total);
  }

  let tmdbTotal = 0;
  for (const value of profile.tmdbGenreWeights.values()) tmdbTotal += value;
  if (tmdbTotal > 0) {
    let overlap = 0;
    for (const genre of candidate.signals.genreIDs.slice(0, 4)) {
      overlap += profile.tmdbGenreWeights.get(genre) ?? 0;
    }
    score += 60 * Math.min(1, overlap / tmdbTotal);
  }

  // Qualität als Beimischung, nicht als Hauptsache: eine Empfehlung soll
  // passen, nicht bloß gut bewertet sein.
  const { voteAverage, voteCount, popularity } = candidate.signals;
  if (voteAverage !== null && voteCount !== null && voteCount >= 100) {
    score += Math.max(0, (voteAverage - 6) * 6);
  }
  if (popularity !== null && popularity > 0) {
    score += Math.min(20, 3 * Math.log2(1 + popularity));
  }

  return score;
}

/**
 * „Für dich", fertig sortiert.
 *
 * Was ausdrücklich **nicht** darin steht: abgeschlossene Serien (sie sind
 * vorbei), angefangene Serien (die stehen in „Weiterschauen") und Titel ohne
 * jede Verbindung zum Profil — eine Empfehlung mit null Punkten ist keine
 * Empfehlung, sondern ein Lückenfüller.
 */
export function recommend(
  candidates: HomeCandidate[],
  profile: TasteProfile,
  options: RowOptions & { recommended?: Map<number, number> } = {},
): HomeCandidate[] {
  const excluding = options.excluding ?? new Set<string>();
  const recommended = options.recommended ?? new Map<number, number>();
  const scored: Scored[] = [];
  for (const candidate of candidates) {
    const id = candidateId(candidate);
    if (excluding.has(id)) continue;
    if (profile.touched.has(id)) continue;
    const value = tasteScore(candidate, profile, recommended);
    if (value <= 25) continue;
    scored.push({ candidate, score: value });
  }
  return ordered(scored).slice(0, options.limit ?? 20);
}

// MARK: - Neue Folgen

export function airingId(entry: AiringEntry): string {
  return `${entry.provider ?? ""}|${entry.slug}|${entry.season}|${entry.episode}|${entry.languages.join(",")}`;
}

/**
 * Die neuen Folgen, chronologisch — die neueste zuerst.
 *
 * Ausdrücklich **nicht** nach Beliebtheit: „Neue Episoden" beantwortet die
 * Frage „was ist seit gestern dazugekommen", und darauf ist die einzige
 * richtige Antwort eine Zeitachse.
 *
 * `availableIds` (`provider|slug`) filtert auf Serien, die im geladenen
 * Nori-Katalog stehen: ein Kalendereintrag zu einem Titel, den der Katalog
 * nicht führt, ließe sich auswählen und liefe ins Leere.
 */
export function recentEpisodes(
  entries: AiringEntry[],
  now: number,
  options: { availableIds?: Set<string>; limit?: number } = {},
): AiringEntry[] {
  const usable: AiringEntry[] = [];
  for (const entry of entries) {
    if (entry.airingAt > now) continue;
    if (options.availableIds) {
      const key = `${entry.provider ?? ""}|${entry.slug}`;
      if (!options.availableIds.has(key)) continue;
    }
    usable.push(entry);
  }

  usable.sort((a, b) => (a.airingAt !== b.airingAt
    ? b.airingAt - a.airingAt
    : airingId(a).localeCompare(airingId(b))));

  // Eine Serie, die heute vier Folgen in vier Sprachen bekommen hat, füllt
  // sonst die ganze Reihe allein.
  const seen = new Set<string>();
  const out: AiringEntry[] = [];
  const limit = options.limit ?? 12;
  for (const entry of usable) {
    const key = `${entry.provider ?? ""}|${entry.slug}|${entry.season}|${entry.episode}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(entry);
    if (out.length >= limit) break;
  }
  return out;
}

// MARK: - Rückweg von TMDB zu Nori

/**
 * Nachschlagewerk: zu einer TMDB-Zeile den Nori-Titel finden, falls es ihn gibt.
 *
 * Das ist die Stelle, an der die Grundregel durchgesetzt wird. TMDBs
 * Ranglisten enthalten überwiegend Titel, die Nori **nicht** anbietet — sie
 * ungefiltert zu zeigen hieße, Kacheln zu bauen, die beim Auswählen nichts
 * öffnen. Hier fällt alles heraus, was nicht im geladenen Katalog steht.
 *
 * Umgekehrt wird nie gesucht: es gibt keinen Weg, aus einer TMDB-Zeile einen
 * Nori-Titel zu *erzeugen*.
 */
export class HomeCatalogIndex {
  /**
   * Normalisierter Titel → Nori-Titel. Mehrere, weil zwei Quellen dieselbe
   * Serie führen können und weil Titel selten, aber doch doppelt vorkommen.
   */
  private readonly buckets = new Map<string, HomeTitle[]>();

  constructor(titles: HomeTitle[]) {
    for (const title of titles) {
      const forms = new Set<string>();
      for (const raw of [title.title, ...title.alts]) {
        const plain = normalizeTitle(raw);
        if (plain) forms.add(plain);
        const stripped = stripVariants(raw);
        if (stripped) forms.add(stripped);
      }
      for (const form of forms) {
        const bucket = this.buckets.get(form);
        if (bucket) bucket.push(title);
        else this.buckets.set(form, [title]);
      }
    }
  }

  get isEmpty(): boolean {
    return this.buckets.size === 0;
  }

  /**
   * Der passende Nori-Titel, oder `null`.
   *
   * Zwei Stufen, und beide sind nötig: Der Eimer findet schnell die Handvoll
   * Titel, die überhaupt in Frage kommen; die Bewertung entscheidet dann, ob
   * einer davon wirklich passt. Ohne die zweite Stufe würde „Hunter" aus dem
   * Eimer von „Hunter x Hunter" gezogen, nur weil beide dieselbe verkürzte
   * Form haben.
   */
  match(candidate: TMDBCandidate): HomeTitle | null {
    const forms: string[] = [];
    for (const raw of [candidate.name, candidate.originalName, ...candidate.alternateNames]) {
      if (!raw) continue;
      forms.push(normalizeTitle(raw));
      forms.push(stripVariants(raw));
    }

    let best: { score: number; title: HomeTitle } | null = null;
    const checked = new Set<string>();
    for (const form of forms) {
      if (!form) continue;
      const bucket = this.buckets.get(form);
      if (!bucket) continue;
      for (const title of bucket) {
        const id = homeTitleId(title);
        if (checked.has(id)) continue;
        checked.add(id);
        // Gegen **alle** Schreibweisen der Quelle prüfen, nicht nur gegen ihren
        // Haupttitel. Sonst scheitert genau der Fall, für den der Eimer den
        // Treffer überhaupt gefunden hat: AniWorld führt „Dämonenjäger", TMDB
        // „Demon Slayer" — verbunden sind die beiden allein über den
        // Alternativtitel.
        let score: number | null = null;
        for (const query of [title.title, ...title.alts]) {
          const value = scoreCandidate(candidate, query, { kind: title.provider });
          if (value === null) continue;
          score = Math.max(score ?? 0, value);
        }
        if (score === null) continue;
        if (!best || score > best.score) best = { score, title };
      }
    }
    return best ? best.title : null;
  }
}

export interface SignalsInput {
  catalog: HomeTitle[];
  index?: HomeCatalogIndex;
  /** TMDBs Wochenliste, in ihrer Reihenfolge. Nur hier ist der Platz ein Signal. */
  trending?: TMDBCandidate[];
  /** Dauerhaft beliebte Titel. Reihenfolge ohne Bedeutung. */
  popular?: TMDBCandidate[];
  /**
   * Titel mit Folgen aus den letzten Wochen. Ihre bloße Zugehörigkeit ist das
   * Aktualitätssignal — die Listenzeilen von TMDB führen kein `last_air_date`.
   */
  airing?: TMDBCandidate[];
  /** Sehanteil je `provider|slug`, 0 bis 1. */
  watched?: Map<string, number>;
  favorites?: Set<string>;
  /** Kennungen, zu denen Noris Kalender in den letzten Tagen eine Folge meldete. */
  freshEpisodes?: Set<string>;
  /**
   * Bereits bekannte Signale je `provider|slug` — etwa die TMDB-Kennung und
   * Bewertung aus der Cover-Suche. Sie sind für Titel, die auf keiner
   * Rangliste stehen, die einzigen, die es gibt.
   */
  known?: Map<string, TMDBSignals>;
  now: number;
}

/**
 * Aus TMDB-Listen und lokalem Stand die bewertbaren Kandidaten bauen.
 *
 * Rein und ohne Netz — die Listen kommen fertig herein. Damit lässt sich in
 * einem Test durchspielen, was sonst nur mit einem TMDB-Schlüssel und der
 * Laune der Ratenbegrenzung zu sehen wäre.
 */
export function buildCandidates(input: SignalsInput): HomeCandidate[] {
  const lookup = input.index ?? new HomeCatalogIndex(input.catalog);
  const signals = new Map<string, TMDBSignals>();
  for (const [id, known] of input.known ?? new Map<string, TMDBSignals>()) {
    signals.set(id, { ...known, genreIDs: [...known.genreIDs] });
  }

  const absorb = (rows: TMDBCandidate[], rank: boolean, recentlyAired: boolean) => {
    rows.forEach((row, offset) => {
      const title = lookup.match(row);
      if (!title) return;
      const id = homeTitleId(title);
      const entry = signals.get(id) ?? emptySignals();
      entry.tmdbID = entry.tmdbID ?? row.id;
      entry.popularity = Math.max(entry.popularity ?? 0, row.popularity);
      if (row.voteCount > (entry.voteCount ?? 0)) {
        entry.voteCount = row.voteCount;
        entry.voteAverage = row.voteAverage;
      }
      entry.firstAirDate = entry.firstAirDate ?? row.firstAirDate;
      if (recentlyAired) {
        // Die Liste ist über `air_date` gefiltert — die Serie hat also
        // nachweislich in den letzten Wochen gesendet. Das Datum genau zu
        // kennen bräuchte einen Abruf pro Titel; für „ist das neu" reicht die
        // Zugehörigkeit.
        entry.lastAirDate = Math.max(entry.lastAirDate ?? 0, input.now - 14 * DAY);
      }
      if (rank && entry.trendingRank === null) entry.trendingRank = offset + 1;
      if (entry.genreIDs.length === 0) entry.genreIDs = row.genreIDs;
      entry.hasBackdrop = entry.hasBackdrop || candidateHasBackdrop(row);
      signals.set(id, entry);
    });
  };

  absorb(input.trending ?? [], true, false);
  absorb(input.popular ?? [], false, false);
  absorb(input.airing ?? [], false, true);

  const watched = input.watched ?? new Map<string, number>();
  const favorites = input.favorites ?? new Set<string>();
  const fresh = input.freshEpisodes ?? new Set<string>();

  return input.catalog.map((title) => {
    const id = homeTitleId(title);
    return {
      title,
      signals: signals.get(id) ?? emptySignals(),
      watchedRatio: watched.get(id) ?? 0,
      inWatchlist: favorites.has(title.slug),
      hasFreshEpisode: fresh.has(id),
    };
  });
}
