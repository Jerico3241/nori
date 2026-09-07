// Der Kopfbereich der Startseite.
//
// Große Fläche, wenig Text: Titel, drei Angaben, drei Zeilen Beschreibung,
// drei Knöpfe. Was darüber hinausgeht, liest auf drei Metern niemand. Der
// Verlauf über dem Bild ist kein Effekt, sondern Voraussetzung — ohne ihn
// steht weiße Schrift bei hellem Backdrop auf Weiß.

import type { CatalogProvider, SeriesDetail, WatchProgress } from "@nori/core";
import { PROVIDERS, formatClock, resumePosition } from "@nori/core";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { Icon } from "./Icon";
import { PosterImage } from "./PosterImage";

export interface HeroProps {
  detail: SeriesDetail | null;
  provider: CatalogProvider;
  slug: string;
  title: string;
  backdrop?: string | null;
  progress?: WatchProgress | null;
  isFavorite: boolean;
  onPlay(): void;
  onDetails(): void;
  onToggleFavorite(): void;
  /** Punkte für die Auswahl unter dem Hero. */
  pages?: { index: number; total: number; onPick(index: number): void };
}

export function Hero(props: HeroProps) {
  const { detail } = props;
  const resumeAt = props.progress ? resumePosition(props.progress) : 0;
  const meta = [
    detail?.yearStart ? (detail.yearEnd && detail.yearEnd !== detail.yearStart
      ? `${detail.yearStart}–${detail.yearEnd}`
      : detail.yearStart) : null,
    detail?.genres.slice(0, 3).join(" · ") || null,
    detail?.fsk ? `FSK ${detail.fsk}` : null,
    PROVIDERS[props.provider].kind,
  ].filter(Boolean) as string[];

  return (
    <section className="hero" aria-label={props.title}>
      <div className="hero-backdrop">
        <PosterImage
          slug={props.slug}
          provider={props.provider}
          title={props.title}
          src={props.backdrop ?? detail?.coverPath ?? null}
          eager
          className="hero-poster"
        />
      </div>
      <div className="hero-vignette" />
      <div className="hero-copy">
        <span className="eyebrow">{PROVIDERS[props.provider].label}</span>
        <h1>{props.title}</h1>
        <p className="hero-meta">
          {meta.map((part, index) => (
            <span key={part}>
              {index > 0 ? <i aria-hidden="true">•</i> : null}
              {part}
            </span>
          ))}
        </p>
        {detail?.description ? <p className="hero-description">{detail.description}</p> : null}
        <SpotArea className="button-row" spotlightId="hero-actions">
          <SpotButton
            className="primary"
            focusRoute="home"
            focusArea="hero"
            focusKey="play"
            onClick={props.onPlay}
          >
            <Icon name="play" />
            {resumeAt >= 8 ? `Folge fortsetzen · ${formatClock(resumeAt)}` : "Abspielen"}
          </SpotButton>
          <SpotButton
            focusRoute="home"
            focusArea="hero"
            focusKey="details"
            onClick={props.onDetails}
          >
            <Icon name="info" />
            Details
          </SpotButton>
          <SpotButton
            focusRoute="home"
            focusArea="hero"
            focusKey="favorite"
            aria-pressed={props.isFavorite}
            onClick={props.onToggleFavorite}
          >
            <Icon name={props.isFavorite ? "check" : "bookmark"} />
            {props.isFavorite ? "Auf Merkliste" : "Merkliste"}
          </SpotButton>
        </SpotArea>
        {props.pages && props.pages.total > 1 ? (
          <SpotArea className="hero-pages" spotlightId="hero-pages">
            {Array.from({ length: props.pages.total }, (_, index) => (
              <SpotButton
                key={index}
                className={index === props.pages!.index ? "active" : ""}
                focusRoute="home"
                focusArea="hero-pages"
                focusKey={`page-${index}`}
                aria-label={`Vorschlag ${index + 1} von ${props.pages!.total}`}
                onClick={() => props.pages!.onPick(index)}
              />
            ))}
          </SpotArea>
        ) : null}
      </div>
    </section>
  );
}
