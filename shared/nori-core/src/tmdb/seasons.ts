// Staffel- und Folgenzuordnung zwischen Nori-Quelle und TMDB.
//
// ## Warum „Staffel 2 → TMDB-Staffel 2" nicht reicht
//
// AniWorld und TMDB teilen dieselbe Serie regelmäßig anders auf:
//
// - **Attack on Titan.** TMDB führt „Final Season" als eine Staffel mit
//   fortlaufender Zählung; AniWorld bricht sie in „Staffel 4" und eine weitere
//   Staffel auf, die wieder bei Folge 1 beginnt. Eine Zuordnung nach Nummer
//   zeigt dann zu Folge 1 das Standbild von Folge 1 — gemeint ist aber
//   Folge 17.
// - **Jujutsu Kaisen, Frieren.** Hier passt die Nummer, aber die Folgenzahl
//   weicht ab, weil die Quelle Specials mitzählt oder nicht.
// - **Detektiv Conan.** Über tausend Folgen, bei TMDB in Staffeln geschnitten,
//   die es bei der Quelle nicht gibt.
// - **„Filme".** Ein eigener Abschnitt ohne Staffelnummer. TMDB kennt dafür
//   Staffel 0 („Specials") — die Zuordnung wäre geraten.
//
// Deshalb zwei Stufen, und beide dürfen ausdrücklich „nichts" antworten:
//
//     pickTmdbSeason    — welche TMDB-Staffel gehört zu dieser Quellstaffel?
//     alignEpisodes     — welche TMDB-Folge gehört zu dieser Quellfolge?
//
// Die Grundregel ist dieselbe wie beim Titelabgleich: **lieber keine Angabe
// als eine falsche.** Ein Standbild aus der falschen Folge ist schlimmer als
// ein leerer Platz — es verrät im Zweifel die Handlung.

import { normalizeTitle } from "./matcher.js";

/** Eine Staffel, wie TMDB sie in `/tv/{id}` führt. */
export interface TMDBSeasonRef {
  seasonNumber: number;
  episodeCount: number;
  name?: string | null;
  airDate?: string | null;
}

/** Eine Folge, wie TMDB sie in `/tv/{id}/season/{n}` führt. */
export interface TMDBEpisodeInfo {
  episodeNumber: number;
  title: string | null;
  overview: string | null;
  /** Vollständige Bildadresse, nicht der rohe TMDB-Pfad. */
  still: string | null;
  airDate: string | null;
  /** Laufzeit in Minuten; `null`, wenn TMDB sie nicht führt. */
  runtime: number | null;
}

export type SeasonConfidence =
  /** Nummer **und** Folgenzahl passen zusammen. */
  | "exact"
  /** Die Nummern weichen ab, aber genau eine Staffel hat dieselbe Folgenzahl. */
  | "counted"
  /**
   * Nur die Nummer passt; die Folgenzahl widerspricht deutlich. Brauchbar erst
   * mit einer Bestätigung über die Folgentitel (siehe `alignEpisodes`).
   */
  | "weak";

export interface SeasonMatch {
  seasonNumber: number;
  confidence: SeasonConfidence;
  /** Für das Diagnoseprotokoll. Deutsch, wie alle Oberflächentexte. */
  reason: string;
}

export interface PickSeasonInput {
  /** Die Staffelkennung der Quelle: „1", „2", „filme". */
  sourceSeason: string;
  /** Wie viele Folgen die Quelle in dieser Staffel führt; 0 heißt unbekannt. */
  sourceEpisodeCount: number;
  tmdbSeasons: TMDBSeasonRef[];
}

/**
 * Wie weit Folgenzahlen auseinanderliegen dürfen und noch als dieselbe
 * Staffel gelten.
 *
 * Zwei Folgen absolut, damit ein mitgezähltes Special oder ein Recap nicht
 * schon einen Treffer verhindert; zusätzlich ein Anteil, weil bei einer
 * Staffel mit fünfzig Folgen zwei Folgen Abweichung nichts heißen, bei einer
 * mit sechs dagegen ein Drittel.
 */
function countsAgree(a: number, b: number): boolean {
  if (a <= 0 || b <= 0) return true;
  const gap = Math.abs(a - b);
  return gap <= Math.max(2, Math.round(Math.max(a, b) * 0.15));
}

/**
 * Welche TMDB-Staffel zu einer Quellstaffel gehört — oder keine.
 *
 * Staffel 0 („Specials") wird nie gewählt: was dort liegt, ordnet TMDB selbst
 * nur lose zu, und die Quellen führen Specials meist als eigene Folgen der
 * regulären Staffeln.
 */
export function pickTmdbSeason(input: PickSeasonInput): SeasonMatch | null {
  const number = Number.parseInt(input.sourceSeason, 10);
  if (!Number.isFinite(number) || number <= 0) return null;

  const usable = input.tmdbSeasons.filter((season) => season.seasonNumber >= 1);
  if (usable.length === 0) return null;

  const same = usable.find((season) => season.seasonNumber === number) ?? null;
  if (same && countsAgree(input.sourceEpisodeCount, same.episodeCount)) {
    return {
      seasonNumber: same.seasonNumber,
      confidence: "exact",
      reason: `Staffel ${number} bei beiden, ${same.episodeCount} Folgen bei TMDB`,
    };
  }

  // Die Nummer passt nicht (oder ihre Folgenzahl widerspricht). Genau eine
  // Staffel mit derselben Folgenzahl ist ein belastbares Zeichen — mehrere
  // sind keines, dann bliebe die Wahl geraten.
  if (input.sourceEpisodeCount > 0) {
    const byCount = usable.filter((season) => season.episodeCount === input.sourceEpisodeCount);
    if (byCount.length === 1) {
      return {
        seasonNumber: byCount[0].seasonNumber,
        confidence: "counted",
        reason: `über die Folgenzahl ${input.sourceEpisodeCount} auf TMDB-Staffel ${byCount[0].seasonNumber}`,
      };
    }
  }

  if (same) {
    return {
      seasonNumber: same.seasonNumber,
      confidence: "weak",
      reason: `Nummer passt, Folgenzahl nicht (Quelle ${input.sourceEpisodeCount}, TMDB ${same.episodeCount})`,
    };
  }

  return null;
}

/** Eine Quellfolge, soweit die Zuordnung sie braucht. */
export interface SourceEpisodeRef {
  number: number;
  germanTitle?: string | null;
  englishTitle?: string | null;
}

export interface EpisodeAlignment {
  /**
   * Um wie viel die TMDB-Zählung vorausläuft. `alignEpisodes` bestätigt einen
   * Versatz nur über Folgentitel, nie durch Raten.
   */
  offset: number;
  /**
   * Ob mindestens ein Folgentitel der Quelle einen TMDB-Folgentitel getroffen
   * hat. Ohne diese Bestätigung darf eine Zuordnung mit `confidence: "weak"`
   * nicht benutzt werden.
   */
  confirmed: boolean;
  /** Quellfolgennummer → TMDB-Folge. Enthält nur belegte Paare. */
  pairs: Map<number, TMDBEpisodeInfo>;
}

/**
 * Ein Folgentitel, sofern es einer ist.
 *
 * TMDB füllt unbenannte Folgen mit einem Platzhalter aus Wort und Nummer:
 * „Folge 11" auf Deutsch, „Episode 11" auf Englisch. Das ist kein Titel,
 * sondern dieselbe Nummer noch einmal. Geprüft wird die **Form**, nicht die
 * Übereinstimmung mit einer Nummer: eine Folge, die bei der Quelle als 11 und
 * bei TMDB als 12 geführt wird, trüge sonst weiterhin „Folge 12" als
 * vermeintlichen Titel.
 *
 * Dieselbe Regel wie `EpisodeInfo.namedTitle` im Swift-Kern.
 */
export function namedEpisodeTitle(raw: string | null | undefined): string | null {
  const trimmed = (raw ?? "").trim();
  if (!trimmed) return null;
  return /^(folge|episode|ep\.?)\s*\d+$/i.test(trimmed) ? null : trimmed;
}

/**
 * Die Titel einer Quellfolge, die für einen Vergleich taugen.
 *
 * Die Quellen schreiben in `germanTitle` gelegentlich selbst „Folge 3" — das
 * ist genauso wenig ein Titel wie bei TMDB und würde sonst jede Folge auf jede
 * andere passen lassen.
 */
function comparableTitles(episode: SourceEpisodeRef): string[] {
  const out: string[] = [];
  for (const raw of [episode.germanTitle, episode.englishTitle]) {
    const named = namedEpisodeTitle(raw);
    if (!named) continue;
    const key = normalizeTitle(named);
    // Sehr kurze Titel („Ende", „Zwei") treffen zu leicht zufällig.
    if (key.length >= 5) out.push(key);
  }
  return out;
}

/**
 * Mindestens so viele übereinstimmende Titel, sonst gilt kein Versatz als
 * belegt. Dieselbe Zahl wie `TMDBSeasonMap.minimumAnchors` in Swift.
 */
const MINIMUM_ANCHORS = 3;

/** Und mindestens dieser Anteil der benennbaren Quellfolgen. */
const MINIMUM_SHARE = 0.5;

/**
 * Quellfolgen auf TMDB-Folgen legen.
 *
 * Zuerst wird über die Folgentitel geprüft, ob die TMDB-Zählung versetzt ist:
 * bei „Attack on Titan Final Season Part 2" beginnt die Quelle wieder bei
 * Folge 1, TMDB zählt ab 17 weiter.
 *
 * Wann ein Versatz als **belegt** gilt, steht in `config/contract.json` und
 * gleichlautend in `TMDBSeasonMap.offset` auf der Swift-Seite. Drei Bedingungen
 * zugleich:
 *
 * 1. Mindestens `MINIMUM_ANCHORS` übereinstimmende Titel — oder, wenn die
 *    Staffel überhaupt weniger benannte Folgen hat, alle davon.
 * 2. Mindestens `MINIMUM_SHARE` der benennbaren Quellfolgen.
 * 3. Kein zweiter Versatz mit gleich vielen Belegen. Zwei gleich gut belegte
 *    Versätze sind kein Ergebnis, sondern ein Münzwurf.
 *
 * Wird keiner belegt, bleibt es bei Versatz 0 — also der Zählung, die beide
 * Seiten ohnehin behaupten. Danach wird nach Nummer plus Versatz zugeordnet.
 * Folgen ohne Gegenstück bleiben ohne Eintrag; das ist der Normalfall, wenn die
 * Quelle mehr Folgen führt als die TMDB-Staffel.
 */
export function alignEpisodes(
  sourceEpisodes: SourceEpisodeRef[],
  tmdbEpisodes: TMDBEpisodeInfo[],
): EpisodeAlignment {
  const byNumber = new Map<number, TMDBEpisodeInfo>();
  for (const episode of tmdbEpisodes) byNumber.set(episode.episodeNumber, episode);

  // Titel → TMDB-Folgennummern. Mehrere, weil Serien gleichnamige Folgen
  // haben („Teil 1"/„Teil 2" tragen bei TMDB oft denselben Namen).
  const titleIndex = new Map<string, number[]>();
  for (const episode of tmdbEpisodes) {
    const named = namedEpisodeTitle(episode.title);
    if (!named) continue;
    const key = normalizeTitle(named);
    if (key.length < 5) continue;
    const bucket = titleIndex.get(key);
    if (bucket) bucket.push(episode.episodeNumber);
    else titleIndex.set(key, [episode.episodeNumber]);
  }

  const offsets = new Map<number, number>();
  let matches = 0;
  let namedSources = 0;
  for (const episode of sourceEpisodes) {
    const keys = comparableTitles(episode);
    if (keys.length === 0) continue;
    namedSources += 1;
    // Je Quellfolge zählt jeder Versatz höchstens einmal — sonst zählte eine
    // Folge, deren deutscher und englischer Titel bei TMDB gleich heißen,
    // doppelt.
    const seen = new Set<number>();
    for (const key of keys) {
      for (const number of titleIndex.get(key) ?? []) {
        const offset = number - episode.number;
        if (seen.has(offset)) continue;
        seen.add(offset);
        offsets.set(offset, (offsets.get(offset) ?? 0) + 1);
      }
    }
    if (seen.size > 0) matches += 1;
  }

  // Nach Belegen sortiert, bei Gleichstand der kleinere Betrag zuerst — damit
  // die Reihenfolge nicht von der Einfügereihenfolge der Map abhängt und
  // TypeScript und Swift dieselbe Rangliste bilden.
  const ranked = [...offsets.entries()].sort((a, b) =>
    a[1] === b[1] ? Math.abs(a[0]) - Math.abs(b[0]) : b[1] - a[1]);

  let offset = 0;
  const top = ranked[0];
  if (top && namedSources > 0) {
    const enoughAnchors = top[1] >= Math.min(MINIMUM_ANCHORS, namedSources);
    const enoughShare = top[1] >= namedSources * MINIMUM_SHARE;
    // Ein zweiter Versatz mit gleich vielen Belegen ist keine Zuordnung.
    // Häufig bei Serien, deren Folgen alle „Folge n" heißen — die filtert
    // `namedEpisodeTitle` zwar heraus, aber nicht jede Wiederholung.
    const unambiguous = !(ranked.length > 1 && ranked[1][1] === top[1]);
    if (enoughAnchors && enoughShare && unambiguous) offset = top[0];
  }

  const pairs = new Map<number, TMDBEpisodeInfo>();
  for (const episode of sourceEpisodes) {
    const found = byNumber.get(episode.number + offset);
    if (found) pairs.set(episode.number, found);
  }

  return { offset, confirmed: matches > 0, pairs };
}

/**
 * Darf die Zuordnung benutzt werden?
 *
 * Eine Staffel, deren Nummer passt, deren Folgenzahl aber deutlich abweicht
 * (`weak`), wird nur angezeigt, wenn ein Folgentitel sie bestätigt hat. Sonst
 * bleiben die Folgenkacheln bei den Angaben der Quelle — die sind immer
 * richtig, nur karg.
 */
export function alignmentIsUsable(match: SeasonMatch, alignment: EpisodeAlignment): boolean {
  if (match.confidence !== "weak") return true;
  return alignment.confirmed;
}
