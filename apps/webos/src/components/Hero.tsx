// Der Kopfbereich der Startseite.
//
// ## Die Fläche
//
// Er nimmt den ersten Bildschirm fast vollständig ein (44 rem von 60 rem
// Höhe). Das ist keine Geschmacksfrage: Ein Kopfbereich, der nur ein Drittel
// hoch ist, zeigt von einem 16:9-Breitbild einen Streifen, in dem selten das
// steht, worum es geht. Die Reihe darunter ragt bewusst noch ins Bild — so ist
// beim Öffnen sichtbar, dass es weitergeht.
//
// ## Der Verlauf
//
// Er ist kein Effekt, sondern Voraussetzung: ohne ihn steht weiße Schrift bei
// hellem Backdrop auf Weiß. Zwei Verläufe übereinander — einer von links für
// den Text, einer von unten für die Reihe darunter —, und der untere endet
// weich im Seitengrund. Ein harter Bildabschluss zerlegt die Seite in zwei
// Hälften.
//
// ## Logo oder Titel
//
// Wenn TMDB einen freigestellten Schriftzug hat, steht der; sonst der Titel
// als Schrift. Der Schriftzug ist der bessere, weil er die Typografie der
// Serie mitbringt — aber er ist kein Muss, und ein fehlender ist kein Mangel.

import type { CatalogProvider, SeriesDetail, WatchProgress } from "@nori/core";
import { PROVIDERS, formatClock, progressPercent, resumePosition } from "@nori/core";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { Icon } from "./Icon";
import { PosterImage } from "./PosterImage";
import { Rating } from "./Rating";

export interface HeroProps {
  detail: SeriesDetail | null;
  provider: CatalogProvider;
  slug: string;
  title: string;
  alts?: string[];
  backdrop?: string | null;
  /** Freigestellter Schriftzug von TMDB; sonst steht der Titel als Schrift. */
  logo?: string | null;
  /** Beschreibung von TMDB, wenn die Quelle keine hat. */
  overview?: string | null;
  rating?: number | null;
  votes?: number | null;
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
  const percent = props.progress ? progressPercent(props.progress) : 0;
  const description = detail?.description || props.overview || "";

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
          alts={props.alts}
          src={props.backdrop ?? detail?.coverPath ?? null}
          eager
          className="hero-poster"
        />
      </div>
      <div className="hero-vignette" />
      <div className="hero-copy">
        <span className="eyebrow">{PROVIDERS[props.provider].label}</span>
        {props.logo ? (
          <img className="hero-logo" src={props.logo} alt={props.title} />
        ) : (
          <h1>{props.title}</h1>
        )}
        <p className="hero-meta">
          <Rating value={props.rating ?? null} votes={props.votes ?? null} />
          {meta.map((part, index) => (
            <span key={part}>
              {index > 0 || props.rating ? <i aria-hidden="true">•</i> : null}
              {part}
            </span>
          ))}
        </p>
        {description ? <p className="hero-description">{description}</p> : null}

        {percent > 0 && percent < 100 ? (
          <div className="hero-progress" aria-label={`${percent} Prozent gesehen`}>
            <span className="hero-progress-bar"><i style={{ width: `${percent}%` }} /></span>
            <small>
              {props.progress?.season && props.progress?.episode
                ? `Staffel ${props.progress.season} · Folge ${props.progress.episode} · `
                : ""}
              {percent} % gesehen
            </small>
          </div>
        ) : null}

        <SpotArea className="button-row" spotlightId="hero-actions">
          <SpotButton
            className="primary"
            focusRoute="home"
            focusArea="hero"
            focusKey="play"
            onClick={props.onPlay}
          >
            <Icon name="play" />
            {resumeAt >= 8 ? `Fortsetzen · ${formatClock(resumeAt)}` : "Abspielen"}
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
