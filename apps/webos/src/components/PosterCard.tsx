// Die Kachel einer Serie: 2:3-Poster, Titel, eine Zeile darunter.
//
// Keine Anime/Serie-Schilder auf dem Cover und keine Bewertung im Bild: aus
// drei Metern liest niemand Kleinschrift auf wechselndem Untergrund. Was eine
// Kachel über sich sagt, steht darunter, in derselben Schriftgröße auf jeder
// Kachel.

import type { CatalogProvider } from "@nori/core";
import type { ReactNode } from "react";
import { useNavigate } from "react-router-dom";

import { SpotButton } from "../navigation/Spot";
import { Artwork } from "./Artwork";

export interface PosterCardProps {
  slug: string;
  provider: CatalogProvider;
  title: string;
  alts?: string[];
  subtitle?: string | null;
  /** 0 bis 100. Ein Balken nur, wenn größer als null. */
  percent?: number;
  focusRoute: string;
  focusArea: string;
  focusKey: string;
  eager?: boolean;
  overlay?: ReactNode;
  className?: string;
  onSelect?: () => void;
  /** Für Raster, die beim Erreichen des Endes nachlegen. */
  onFocus?: () => void;
}

export function PosterCard(props: PosterCardProps) {
  const navigate = useNavigate();
  const percent = Math.max(0, Math.min(100, Math.round(props.percent ?? 0)));
  return (
    <SpotButton
      card
      className={`poster-card${props.className ? ` ${props.className}` : ""}`}
      focusRoute={props.focusRoute}
      focusArea={props.focusArea}
      focusKey={props.focusKey}
      aria-label={`${props.title}${props.subtitle ? `, ${props.subtitle}` : ""}`}
      onFocus={props.onFocus}
      onClick={() => {
        if (props.onSelect) props.onSelect();
        else navigate(`/titel/${props.provider}/${encodeURIComponent(props.slug)}`);
      }}
    >
      <span className="card-art poster-art">
        <Artwork
          kind="poster"
          slug={props.slug}
          provider={props.provider}
          title={props.title}
          alts={props.alts}
          eager={props.eager}
        />
        {percent > 0 ? (
          <span className="card-progress" aria-hidden="true"><i style={{ width: `${percent}%` }} /></span>
        ) : null}
        {props.overlay}
      </span>
      <span className="card-title">{props.title}</span>
      {props.subtitle ? <span className="card-sub">{props.subtitle}</span> : null}
    </SpotButton>
  );
}
