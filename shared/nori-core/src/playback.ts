// Was der Player entscheidet, ohne etwas abzuspielen.
//
// Die Entsprechung zu `native/NoriCore/Sources/NoriCore/Playback.swift`. Hier
// steht, was auf jedem Gerät gleich sein muss: wie lange der Countdown zur
// nächsten Folge läuft, und was nach einem gescheiterten Stream passiert.
//
// Ohne diese Datei stand beides dreimal da und dreimal anders: acht Sekunden
// Countdown auf iPhone und Mac, zehn auf dem Fernseher — und beim Hosterwechsel
// nach einem Fehler nahm iOS einfach den nächsten der Liste, ohne zu merken,
// dass es derselbe war, der eben nicht funktioniert hat.
//
// Nichts hier macht Netzwerkarbeit. Die Wiederherstellung ist eine
// Zustandsmaschine aus reinen Funktionen: der Aufrufer meldet einen
// Fehlschlag, fragt nach dem nächsten Schritt und führt ihn aus.

import { type HosterOption } from "./models.js";
import { orderHosters } from "./hoster/resolver.js";

// MARK: - Nächste Folge

/**
 * Sekunden Countdown, bevor die nächste Folge startet.
 *
 * Steht auch in `config/contract.json` unter `rules.autoplay`. Wer den Wert
 * ändert, ändert ihn dort, hier und in `Playback.swift`.
 */
export const AUTOPLAY_COUNTDOWN_SEC = 10;

/**
 * Ab wie viel Rest einer Folge der Countdown angeboten wird.
 *
 * Die Folge gilt ab 90 % als abgeschlossen (`isEpisodeComplete`); der
 * Countdown erscheint erst kurz vor dem Ende, damit er nicht über dem
 * Abspann von zehn Minuten Rest hängt.
 */
export const AUTOPLAY_TAIL_SEC = 30;

/** Soll der Countdown jetzt laufen? */
export function shouldOfferNextEpisode(
  positionSec: number,
  durationSec: number,
  hasNext: boolean,
  autoplayEnabled: boolean,
): boolean {
  if (!hasNext || !autoplayEnabled) return false;
  if (durationSec < 20) return false;
  return positionSec >= durationSec - AUTOPLAY_TAIL_SEC;
}

// MARK: - Quellen und Fehlschläge

/** Eine Quelle, so wie sie sich wiedererkennen lässt. */
export interface SourceRef {
  hoster: string;
  lang: string;
}

/** „voe|de" — kleingeschrieben, damit Schreibweisen der Quellen nicht trennen. */
export function sourceKey(ref: SourceRef): string {
  return `${ref.hoster.toLowerCase()}|${ref.lang.toLowerCase()}`;
}

/**
 * Wie viele Quellen je Folge automatisch durchprobiert werden.
 *
 * Eine Grenze, weil ein Hoster, der eine Schutzseite ausliefert, das für alle
 * tut: ohne sie liefe der Player die ganze Liste durch, jedes Mal mit einem
 * vollständigen Abruf, und der Fernseher hinge minutenlang in „Stream wird
 * geholt …".
 */
export const MAX_AUTOMATIC_SOURCE_SWITCHES = 3;

/** Wie oft dieselbe Quelle nach einem Fehlschlag noch einmal versucht wird. */
export const MAX_SAME_SOURCE_RETRIES = 1;

export interface RecoveryState {
  /** Quellen, die für diese Folge schon gescheitert sind. */
  failed: string[];
  /** Wie viele automatische Wechsel bisher stattfanden. */
  switches: number;
  /** Wie oft die aktuelle Quelle schon wiederholt wurde. */
  sameRetries: number;
  /** Zu welcher Folge der Stand gehört — `provider|episodePath`. */
  episode: string;
}

export function emptyRecovery(episode = ""): RecoveryState {
  return { failed: [], switches: 0, sameRetries: 0, episode };
}

/**
 * Den Stand auf eine Folge setzen. Bei einer anderen Folge beginnt er neu:
 * dass VOE bei Folge 3 nichts lieferte, sagt über Folge 4 nichts.
 */
export function recoveryForEpisode(state: RecoveryState, episode: string): RecoveryState {
  return state.episode === episode ? state : emptyRecovery(episode);
}

/** Eine Quelle ist gescheitert. */
export function noteSourceFailure(state: RecoveryState, current: SourceRef | null): RecoveryState {
  if (!current) return { ...state, sameRetries: state.sameRetries + 1 };
  const key = sourceKey(current);
  return {
    ...state,
    failed: state.failed.includes(key) ? state.failed : [...state.failed, key],
    sameRetries: state.sameRetries + 1,
  };
}

/**
 * Eine Quelle spielt. Der Zähler für Wiederholungen fällt zurück, die Liste
 * der gescheiterten bleibt — sie gilt weiter für diese Folge.
 */
export function noteSourceSuccess(state: RecoveryState): RecoveryState {
  return { ...state, sameRetries: 0 };
}

export type RecoveryStep =
  /** Dieselbe Quelle noch einmal — ein Abbruch kann ein Aussetzer gewesen sein. */
  | { kind: "retry" }
  /** Eine andere Quelle. */
  | { kind: "switch"; option: HosterOption }
  /** Nichts mehr übrig. `reason` steht so in der Oberfläche. */
  | { kind: "giveUp"; reason: string };

/**
 * Was nach einem Fehlschlag zu tun ist.
 *
 * Eine Quelle, der ein Fehlschlag **zugeordnet** werden konnte, ist damit
 * verbraucht: es geht zur nächsten in der Rangfolge aus
 * `config/contract.json`, ohne die schon gescheiterten. Wiederholt wird nur,
 * was sich nicht zuordnen ließ — ein Abbruch, bevor überhaupt ein Hoster
 * feststand, ist meistens das Netz und nicht die Quelle.
 *
 * Bewusst **keine** zweite Runde je Hoster: jeder Versuch ist ein
 * vollständiger Abruf, und vier davon dauern auf einem Fernseher schon lange
 * genug. Wer eine gescheiterte Quelle trotzdem will, wählt sie von Hand — die
 * Auswahl in der Bedienung bleibt vollständig.
 *
 * Ist das Budget aufgebraucht oder nichts mehr übrig, wird aufgegeben statt
 * im Kreis gelaufen.
 */
export function planRecovery(
  state: RecoveryState,
  options: HosterOption[],
  current: SourceRef | null,
  preferredHoster?: string | null,
): RecoveryStep {
  if (current && state.sameRetries <= MAX_SAME_SOURCE_RETRIES
    && !state.failed.includes(sourceKey(current))) {
    return { kind: "retry" };
  }
  if (state.switches >= MAX_AUTOMATIC_SOURCE_SWITCHES) {
    return { kind: "giveUp", reason: "Mehrere Quellen hintereinander lieferten keinen Stream." };
  }
  const next = remainingSources(state, options, current?.lang ?? null, preferredHoster)[0];
  if (!next) return { kind: "giveUp", reason: "Kein weiterer Hoster verfügbar." };
  return { kind: "switch", option: next };
}

/** Ein Wechsel wurde ausgeführt. */
export function noteSourceSwitch(state: RecoveryState): RecoveryState {
  return { ...state, switches: state.switches + 1, sameRetries: 0 };
}

/**
 * Welche Quellen noch übrig sind — in der Rangfolge, ohne die gescheiterten.
 *
 * `lang` grenzt auf die laufende Sprache ein; ohne Angabe zählen alle. Die
 * Oberfläche benutzt dieselbe Liste für „Andere Quelle", damit dort nichts
 * steht, was der Player gerade ausgeschlossen hat.
 */
export function remainingSources(
  state: RecoveryState,
  options: HosterOption[],
  lang?: string | null,
  preferredHoster?: string | null,
): HosterOption[] {
  const pool = lang
    ? options.filter((option) => option.lang.toLowerCase() === lang.toLowerCase())
    : options;
  return orderHosters(pool, preferredHoster ?? null)
    .filter((option) => !state.failed.includes(sourceKey({ hoster: option.name, lang: option.lang })));
}

// MARK: - Übersprungmarken

/**
 * Ein Abschnitt, den man überspringen kann.
 *
 * **Es gibt dafür heute keine Datenquelle.** Weder AniWorld noch Serienstream
 * nennen Zeitmarken, und TMDB kennt sie nicht. Erfundene Zeiten wären
 * schlimmer als keine: ein „Intro überspringen" nach festen 90 Sekunden
 * schneidet bei der Hälfte der Serien mitten in die Handlung.
 *
 * Deshalb steht hier nur die Form — Modell, Prüfung und die Frage „liegt
 * gerade eine Marke an?". Wer später eine Quelle anbindet, füllt
 * `SkipSegmentSource` und muss an den Oberflächen nichts mehr bauen.
 */
export type SkipKind = "intro" | "outro" | "recap";

export interface SkipSegment {
  type: SkipKind;
  /** Sekunden seit Beginn der Folge. */
  start: number;
  end: number;
}

export const SKIP_LABELS: Record<SkipKind, string> = {
  intro: "Intro überspringen",
  outro: "Abspann überspringen",
  recap: "Rückblick überspringen",
};

/** Woher Marken kommen könnten. Umgesetzt ist bisher keine Quelle. */
export interface SkipSegmentSource {
  readonly name: string;
  segments(ref: {
    provider: string;
    slug: string;
    season: string;
    episode: number;
    durationSec: number;
  }): Promise<SkipSegment[]>;
}

/**
 * Marken auf Plausibilität prüfen.
 *
 * Eine fremde Quelle darf die Wiedergabe nicht kaputtmachen: negative Zeiten,
 * vertauschte Grenzen, Marken jenseits der Laufzeit und solche unter zwei
 * Sekunden fallen weg. Überlappende werden zusammengefasst.
 */
export function sanitizeSkipSegments(raw: SkipSegment[], durationSec: number): SkipSegment[] {
  const limit = durationSec > 0 ? durationSec : Number.POSITIVE_INFINITY;
  const clean = raw
    .map((segment) => ({
      type: segment.type,
      start: Math.max(0, Math.min(segment.start, segment.end)),
      end: Math.min(limit, Math.max(segment.start, segment.end)),
    }))
    .filter((segment) => segment.end - segment.start >= 2)
    .sort((a, b) => a.start - b.start);

  const out: SkipSegment[] = [];
  for (const segment of clean) {
    const last = out[out.length - 1];
    if (last && last.type === segment.type && segment.start <= last.end) {
      last.end = Math.max(last.end, segment.end);
      continue;
    }
    out.push({ ...segment });
  }
  return out;
}

/** Die Marke, die an dieser Stelle angeboten wird — oder keine. */
export function activeSkipSegment(segments: SkipSegment[], positionSec: number): SkipSegment | null {
  for (const segment of segments) {
    if (positionSec >= segment.start && positionSec < segment.end) return segment;
  }
  return null;
}
