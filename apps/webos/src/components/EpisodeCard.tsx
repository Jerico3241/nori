// Eine Folge als 16:9-Karte im Raster der Detailseite.
//
//     Standbild        was kommt — mit Balken, wenn begonnen, mit Haken, wenn gesehen
//     Nummer + Titel   welche Folge
//     Fußzeile         Laufzeit · Sprache
//     Zustand          „Fortsetzen bei 12:40", „Gesehen"
//
// Keine Beschreibung auf der Karte: TMDB schreibt dort regelmäßig, wie die
// Folge ausgeht, und auf einem Raster von drei Karten je Zeile liest man sie
// ungewollt mit.
//
// Die Karte hat eine feste Höhe. Titel ohne Text, Titel mit zwei Zeilen und
// ein spät geladenes Standbild ändern daran nichts — die Zeile darunter bleibt
// an ihrem Platz und mit ihr der Fokus.

import type { CatalogProvider, Episode, WatchProgress } from "@nori/core";
import { formatClock, isEpisodeComplete, progressPercent, resumePosition } from "@nori/core";

import { SpotButton } from "../navigation/Spot";
import { Artwork } from "./Artwork";
import { Icon } from "./Icon";

export interface EpisodeExtras {
  title?: string | null;
  still?: string | null;
  runtime?: number | null;
}

export function EpisodeCard({
  episode, slug, provider, seriesTitle, progress, focusRoute, extras, marking, onSelect,
}: {
  episode: Episode;
  slug: string;
  provider: CatalogProvider;
  seriesTitle: string;
  progress: WatchProgress | null;
  focusRoute: string;
  extras?: EpisodeExtras | null;
  /**
   * „Sehstand ändern" ist an: OK setzt die Folge auf gesehen oder ungesehen,
   * statt sie abzuspielen.
   *
   * Derselbe Griff wie „Bearbeiten" in der Merkliste — kein langer Druck und
   * keine Farbtaste, die man erst suchen muss. Eine Fernbedienung hat eine
   * Taste dafür, und die ist bereits belegt.
   */
  marking?: boolean;
  onSelect(): void;
}) {
  const percent = progressPercent(progress);
  const done = isEpisodeComplete(progress);
  const resumeAt = resumePosition(progress);

  // Die Quelle zuerst: ihr Titel ist der, unter dem die Folge dort läuft.
  // TMDB füllt nur, was die Quelle nicht hat.
  const label = episode.germanTitle || extras?.title || episode.englishTitle || `Folge ${episode.number}`;
  const meta = [
    extras?.runtime ? `${extras.runtime} Min.` : null,
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
      card
      className={`ep-card${done ? " done" : ""}${marking ? " marking" : ""}`}
      focusRoute={focusRoute}
      focusArea="episodes"
      focusKey={`episode-${episode.number}`}
      aria-label={marking
        ? `Folge ${episode.number}: ${label}, ${done ? "als ungesehen markieren" : "als gesehen markieren"}`
        : `Folge ${episode.number}: ${label}${state ? `, ${state}` : ""}`}
      aria-pressed={marking ? done : undefined}
      onClick={onSelect}
    >
      <span className="card-art ep-thumb">
        <Artwork
          kind="still"
          src={extras?.still}
          slug={slug}
          provider={provider}
          title={seriesTitle}
          passive
        />
        <span className="ep-number" aria-hidden="true">{episode.number}</span>
        {done ? <span className="ep-done"><Icon name="check" />Gesehen</span> : null}
        {marking ? (
          <span className="ep-mark">
            <Icon name={done ? "close" : "check"} />
            {done ? "Ungesehen" : "Gesehen"}
          </span>
        ) : null}
        {percent > 0 && !done ? (
          <span className="card-progress" aria-hidden="true"><i style={{ width: `${percent}%` }} /></span>
        ) : null}
      </span>
      <span className="ep-body">
        <span className="ep-title">{episode.number}. {label}</span>
        <span className="ep-meta">{meta || " "}</span>
        <span className={`ep-state${done ? " done" : ""}`}>{state ?? " "}</span>
      </span>
    </SpotButton>
  );
}
