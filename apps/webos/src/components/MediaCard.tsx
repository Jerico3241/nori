// Die Kachel einer Serie. 2:3-Poster, fester Platz, sichtbarer Fokus.
//
// Die Kachel ist absichtlich karg: Bild, Titel, eine Zeile darunter. Auf einem
// Fernseher stehen zwölf davon gleichzeitig im Bild, und jede zusätzliche
// Angabe kostet an jeder Kachel Platz — aus drei Metern liest niemand zwei
// Zeilen Kleinschrift nebeneinander.
//
// Die Bewertung ist die Ausnahme. Sie steht **im Bild**, oben rechts, und
// nicht unter dem Titel: dort verschiebt sie nichts, und sie ist die einzige
// Angabe, die beim Überfliegen einer Reihe wirklich hilft.

import type { CatalogProvider, WatchProgress } from "@nori/core";
import { progressPercent } from "@nori/core";
import { useNavigate } from "react-router-dom";
import { SpotButton } from "../navigation/Spot";
import { PosterImage } from "./PosterImage";
import { Rating } from "./Rating";

export interface MediaCardProps {
  slug: string;
  title: string;
  provider: CatalogProvider;
  /** Alternativtitel der Quelle — sie entscheiden über den TMDB-Treffer. */
  alts?: string[];
  coverPath?: string | null;
  badge?: string | null;
  subtitle?: string | null;
  progress?: WatchProgress | null;
  /** TMDBs Zehnerskala; ohne Stimmen wird sie nicht gezeigt. */
  rating?: number | null;
  votes?: number | null;
  focusRoute: string;
  focusArea: string;
  focusKey: string;
  eager?: boolean;
  onSelect?: () => void;
}

export function MediaCard(props: MediaCardProps) {
  const navigate = useNavigate();
  const percent = props.progress ? progressPercent(props.progress) : 0;

  return (
    <SpotButton
      className="media-card"
      focusRoute={props.focusRoute}
      focusArea={props.focusArea}
      focusKey={props.focusKey}
      aria-label={`${props.title}${props.subtitle ? `, ${props.subtitle}` : ""}`}
      onClick={() => {
        if (props.onSelect) props.onSelect();
        else navigate(`/titel/${props.provider}/${encodeURIComponent(props.slug)}`);
      }}
    >
      <div className="media-art">
        <PosterImage
          slug={props.slug}
          provider={props.provider}
          title={props.title}
          alts={props.alts}
          src={props.coverPath}
          eager={props.eager}
        />
        {props.badge ? <b className="media-badge">{props.badge}</b> : null}
        {props.rating ? (
          <span className="media-rating">
            <Rating value={props.rating} votes={props.votes} />
          </span>
        ) : null}
        {percent > 0 && percent < 100 ? (
          <span className="media-progress" aria-label={`${percent} Prozent gesehen`}>
            <i style={{ width: `${percent}%` }} />
          </span>
        ) : null}
      </div>
      <strong className="media-title">{props.title}</strong>
      {props.subtitle ? <small className="media-sub">{props.subtitle}</small> : null}
    </SpotButton>
  );
}
