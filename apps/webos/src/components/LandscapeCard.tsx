// Eine 16:9-Karte — für Folgen, nicht für Serien.
//
// „Weiterschauen" und „Neue Episoden" zeigen eine **Folge**. Ein Standbild mit
// Fortschrittsbalken beantwortet „wo stehe ich" im Bild; ein Poster wäre
// dasselbe Bild wie in jeder anderen Reihe. Rückfall: Standbild → Breitbild der
// Serie → Poster → Buchstabe.

import type { CatalogProvider } from "@nori/core";
import type { ReactNode } from "react";

import { SpotButton } from "../navigation/Spot";
import { Artwork, Icon } from "@nori/app";

export interface LandscapeCardProps {
  slug: string;
  provider: CatalogProvider;
  title: string;
  alts?: string[];
  still?: string | null;
  subtitle?: string | null;
  percent?: number;
  focusRoute: string;
  focusArea: string;
  focusKey: string;
  eager?: boolean;
  /** Ein Schild über dem Bild — sagt, was OK gerade tut. */
  overlay?: ReactNode;
  /** Für Reihen, die beim Erreichen ihres Endes nachlegen. */
  onFocus?: () => void;
  onSelect(): void;
}

export function LandscapeCard(props: LandscapeCardProps) {
  const percent = Math.max(0, Math.min(100, Math.round(props.percent ?? 0)));
  return (
    <SpotButton
      card
      className="land-card"
      focusRoute={props.focusRoute}
      focusArea={props.focusArea}
      focusKey={props.focusKey}
      aria-label={`${props.title}${props.subtitle ? `, ${props.subtitle}` : ""}`}
      onFocus={props.onFocus}
      onClick={props.onSelect}
    >
      <span className="card-art land-art" data-nav-quiet="">
        <Artwork
          kind={props.still ? "still" : "backdrop"}
          src={props.still}
          slug={props.slug}
          provider={props.provider}
          title={props.title}
          alts={props.alts}
          eager={props.eager}
        />
        <span className="land-play" aria-hidden="true"><Icon name="play" /></span>
        {percent > 0 && percent < 100 ? (
          <span className="card-progress" aria-label={`${percent} Prozent gesehen`}>
            <i style={{ width: `${percent}%` }} />
          </span>
        ) : null}
        {props.overlay}
      </span>
      <span className="card-title">{props.title}</span>
      {props.subtitle ? <span className="card-sub">{props.subtitle}</span> : null}
    </SpotButton>
  );
}
