// Eine Folge als 16:9-Karte.
//
// Nummer, Titel, Fortschrittsbalken und ein Haken für „gesehen". Der Balken
// steht direkt an der Karte, nicht in einer Zeile darunter: aus drei Metern
// muss die Zuordnung ohne Suchen erkennbar sein.

import type { Episode, WatchProgress } from "@nori/core";
import { isEpisodeComplete, progressPercent } from "@nori/core";
import { SpotButton } from "../navigation/Spot";
import { Icon } from "./Icon";

export function EpisodeCard({ episode, progress, focusRoute, focusArea, thumbnail, onSelect }: {
  episode: Episode;
  progress: WatchProgress | null;
  focusRoute: string;
  focusArea: string;
  thumbnail?: string | null;
  onSelect(): void;
}) {
  const percent = progressPercent(progress);
  const done = isEpisodeComplete(progress);
  const label = episode.germanTitle || episode.englishTitle || `Folge ${episode.number}`;

  return (
    <SpotButton
      className={`episode-card ${done ? "done" : ""}`}
      focusRoute={focusRoute}
      focusArea={focusArea}
      focusKey={`episode-${episode.number}`}
      aria-label={`Folge ${episode.number}: ${label}${percent > 0 ? `, ${percent} Prozent gesehen` : ""}`}
      onClick={onSelect}
    >
      <span className="episode-art">
        {thumbnail ? <img src={thumbnail} alt="" loading="lazy" /> : null}
        <b className="episode-number">{episode.number}</b>
        {done ? <i className="episode-done"><Icon name="check" /></i> : null}
        <i className="episode-play"><Icon name="play" /></i>
        {percent > 0 && !done ? (
          <span className="episode-progress"><i style={{ width: `${percent}%` }} /></span>
        ) : null}
      </span>
      <span className="episode-copy">
        <strong>{label}</strong>
        <small>
          {done
            ? "Gesehen"
            : percent > 0
              ? `${percent} % gesehen`
              : episode.languages.join(" · ") || episode.englishTitle || "Noch nicht gesehen"}
        </small>
      </span>
    </SpotButton>
  );
}
