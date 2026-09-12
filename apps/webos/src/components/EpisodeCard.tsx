// Eine Folge als 16:9-Karte.
//
// ## Was auf der Karte steht, und warum in dieser Reihenfolge
//
//     Standbild        was kommt
//     Nummer + Titel   welche Folge
//     Beschreibung     worum es geht
//     Fußzeile         Laufzeit · Erscheinungsdatum · Sprache
//     Balken/Haken     wo ich stehe
//
// Die Beschreibung ist auf zwei Zeilen begrenzt. Nicht aus Platznot — die
// Karte hätte Platz für vier —, sondern weil eine Folgenbeschreibung die
// nächste verrät: TMDB schreibt dort regelmäßig, wie die Folge ausgeht. Zwei
// Zeilen sind genug für „worum geht es", zu wenig für „wie endet es".
//
// Alle Größen sind so gesetzt, dass sie aus drei Metern lesbar bleiben: der
// Titel bei 20 px, die Beschreibung bei 17, die Fußzeile bei 16. Kleiner wird
// hier nichts, auch wenn dann eine Zeile weniger passt.

import type { Episode, WatchProgress } from "@nori/core";
import { formatClock, isEpisodeComplete, progressPercent, resumePosition } from "@nori/core";
import { SpotButton } from "../navigation/Spot";
import { Icon } from "./Icon";

/** Was TMDB zu dieser Folge beisteuert. Alles davon ist freiwillig. */
export interface EpisodeExtras {
  title?: string | null;
  overview?: string | null;
  still?: string | null;
  airDate?: string | null;
  /** Laufzeit in Minuten. */
  runtime?: number | null;
}

export function EpisodeCard({ episode, progress, focusRoute, focusArea, extras, onSelect }: {
  episode: Episode;
  progress: WatchProgress | null;
  focusRoute: string;
  focusArea: string;
  extras?: EpisodeExtras | null;
  onSelect(): void;
}) {
  const percent = progressPercent(progress);
  const done = isEpisodeComplete(progress);
  const resumeAt = resumePosition(progress);

  // Die Quelle zuerst: ihr Titel ist immer der, unter dem die Folge dort
  // läuft. TMDB füllt nur, was die Quelle nicht hat.
  const label = episode.germanTitle
    || extras?.title
    || episode.englishTitle
    || `Folge ${episode.number}`;

  const footnote = [
    extras?.runtime ? `${extras.runtime} min` : null,
    formatAirDate(extras?.airDate),
    episode.languages.length > 0 ? episode.languages.join(" · ") : null,
  ].filter(Boolean).join(" · ");

  const state = done
    ? "Gesehen"
    : resumeAt >= 8
      ? `Fortsetzen bei ${formatClock(resumeAt)}`
      : percent > 0
        ? `${percent} % gesehen`
        : null;

  return (
    <SpotButton
      className={`episode-card ${done ? "done" : ""}`}
      focusRoute={focusRoute}
      focusArea={focusArea}
      focusKey={`episode-${episode.number}`}
      aria-label={`Folge ${episode.number}: ${label}${state ? `, ${state}` : ""}`}
      onClick={onSelect}
    >
      <span className="episode-art">
        {extras?.still ? <img src={extras.still} alt="" loading="lazy" /> : null}
        {/*
          Mit Standbild ein kleines Schild, ohne eines die große Zahl.
          Die große Zahl füllt eine leere Kachel und ist dort richtig; über
          einem Bild steht sie halbdurchsichtig auf wechselndem Untergrund und
          ist mal zu lesen, mal nicht — während die Nummer im Text darunter
          ohnehin steht.
        */}
        <b className={`episode-number ${extras?.still ? "on-art" : ""}`}>{episode.number}</b>
        {done ? <i className="episode-done"><Icon name="check" /></i> : null}
        <i className="episode-play"><Icon name="play" /></i>
        {percent > 0 && !done ? (
          <span className="episode-progress"><i style={{ width: `${percent}%` }} /></span>
        ) : null}
      </span>
      <span className="episode-copy">
        <strong>
          <span className="episode-index">{episode.number}.</span>
          {label}
        </strong>
        {extras?.overview ? <span className="episode-overview">{extras.overview}</span> : null}
        {footnote ? <small className="episode-footnote">{footnote}</small> : null}
        {state ? <small className={done ? "episode-state done" : "episode-state"}>{state}</small> : null}
      </span>
    </SpotButton>
  );
}

/**
 * TMDBs `yyyy-MM-dd` als deutsches Datum.
 *
 * Ohne `Intl` als Rückfall der rohe Wert: auf webOS 6 ist `Intl` vorhanden,
 * aber eine fehlende Zeitzonendatenbank hat dort schon Ausnahmen erzeugt — und
 * für ein Datum unter einer Folgenkachel lohnt kein Absturz.
 */
function formatAirDate(raw: string | null | undefined): string | null {
  if (!raw || raw.length < 10) return null;
  const stamp = Date.parse(`${raw.slice(0, 10)}T00:00:00Z`);
  if (Number.isNaN(stamp)) return null;
  try {
    return new Intl.DateTimeFormat("de-DE", {
      timeZone: "UTC", day: "2-digit", month: "2-digit", year: "numeric",
    }).format(new Date(stamp));
  } catch {
    return raw.slice(0, 10);
  }
}
