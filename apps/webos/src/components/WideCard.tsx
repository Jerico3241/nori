// Eine Kachel im Breitformat — für Folgen, nicht für Serien.
//
// ## Warum es diese Form zusätzlich gibt
//
// „Weiterschauen" und „Neue Episoden" zeigen eine **Folge**, keine Serie. Ein
// 2:3-Poster sagt darüber nichts: es ist dasselbe Bild wie in jeder anderen
// Reihe, und die Angabe, um die es geht („Staffel 2, Folge 7, 18 Minuten
// verbleiben"), müsste unter dem Titel als Kleinschrift mitlaufen.
//
// Ein 16:9-Standbild mit Fortschrittsbalken beantwortet dieselbe Frage im
// Bild. Dieselbe Entscheidung wie auf iPhone und Mac, wo die
// Weiterschauen-Reihe ebenfalls breit ist.
//
// Der Rückfall ist gestaffelt: Standbild der Folge → Breitbild der Serie →
// Poster → Buchstabe. Eine Reihe, in der jede zweite Kachel leer ist, wäre
// schlechter als eine mit Postern.

import type { CatalogProvider } from "@nori/core";
import { useEffect, useState } from "react";
import { covers } from "../services/covers";
import { SpotButton } from "../navigation/Spot";
import { useData } from "../state/data";
import { Icon } from "./Icon";

export interface WideCardProps {
  slug: string;
  provider: CatalogProvider;
  title: string;
  alts?: string[];
  /** Die Zeile unter dem Titel: „Staffel 1 · Folge 7". */
  subtitle?: string | null;
  /** Eine dritte Zeile, kleiner: verbleibende Zeit, Sprache, Uhrzeit. */
  footnote?: string | null;
  /** Standbild der Folge, wenn TMDB eines hat. */
  still?: string | null;
  /** 0 bis 100. Nur zwischen den Enden wird ein Balken gezeichnet. */
  percent?: number;
  focusRoute: string;
  focusArea: string;
  focusKey: string;
  eager?: boolean;
  onSelect(): void;
}

export function WideCard(props: WideCardProps) {
  const { gateway } = useData();
  const [art, setArt] = useState<string | null>(
    () => props.still ?? covers.backdrop(props.slug, props.provider) ?? covers.cached(props.slug, props.provider),
  );
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    setFailed(false);
    setArt(props.still
      ?? covers.backdrop(props.slug, props.provider)
      ?? covers.cached(props.slug, props.provider));
  }, [props.still, props.slug, props.provider]);

  // Breitbild und Poster kommen beide erst mit dem TMDB-Treffer.
  useEffect(() => {
    if (props.still) return;
    let cancelled = false;
    void covers.ensure({
      slug: props.slug,
      provider: props.provider,
      title: props.title,
      alts: props.alts,
    }).then(() => {
      if (cancelled) return;
      const best = covers.backdrop(props.slug, props.provider)
        ?? covers.cached(props.slug, props.provider);
      if (best) setArt(best);
    });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.slug, props.provider, props.still]);

  const percent = Math.round(props.percent ?? 0);
  const initials = props.title.replace(/[^\p{L}\p{N} ]/gu, "").trim().split(/\s+/)
    .slice(0, 2).map((word) => word[0] ?? "").join("").toUpperCase() || "N";

  return (
    <SpotButton
      className="wide-card"
      focusRoute={props.focusRoute}
      focusArea={props.focusArea}
      focusKey={props.focusKey}
      aria-label={`${props.title}${props.subtitle ? `, ${props.subtitle}` : ""}`}
      onClick={props.onSelect}
    >
      <span className="wide-art">
        {art && !failed ? (
          <img
            src={gateway.imageURL(art, props.provider)}
            alt=""
            loading={props.eager ? "eager" : "lazy"}
            onError={() => setFailed(true)}
          />
        ) : (
          <span className="poster-fallback">{initials}</span>
        )}
        <i className="wide-play"><Icon name="play" /></i>
        {percent > 0 && percent < 100 ? (
          <span className="wide-progress" aria-label={`${percent} Prozent gesehen`}>
            <i style={{ width: `${percent}%` }} />
          </span>
        ) : null}
      </span>
      <span className="wide-copy">
        <strong>{props.title}</strong>
        {props.subtitle ? <small>{props.subtitle}</small> : null}
        {props.footnote ? <small className="muted">{props.footnote}</small> : null}
      </span>
    </SpotButton>
  );
}
