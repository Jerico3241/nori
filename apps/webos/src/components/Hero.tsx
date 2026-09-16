// Der Kopfbereich — auf der Startseite und auf der Detailseite derselbe Aufbau.
//
// Breitbild als Fläche, darüber ein Verlauf von links, darauf Schriftzug oder
// Titel, Metadaten, Beschreibung und die Aktionen. Der Verlauf ist kein
// Effekt, sondern Voraussetzung: ohne ihn stünde weiße Schrift auf hellem
// Artwork.
//
// Die Beschreibung ist auf drei Zeilen begrenzt und die Höhe fest. Ein Titel
// mit langem Text schiebt damit weder die Aktionen noch die Reihe darunter.

import type { CatalogProvider } from "@nori/core";
import { useEffect, useState, type ReactNode } from "react";

import { sizedImage } from "../services/images";
import { Artwork } from "./Artwork";

export interface HeroProps {
  variant: "home" | "detail";
  slug: string;
  provider: CatalogProvider;
  title: string;
  alts?: string[];
  eyebrow?: string;
  backdrop?: string | null;
  logo?: string | null;
  meta: string[];
  rating?: string | null;
  description?: string;
  progress?: { percent: number; label: string } | null;
  actions: ReactNode;
}

export function Hero(props: HeroProps) {
  const [logoFailed, setLogoFailed] = useState(false);
  useEffect(() => setLogoFailed(false), [props.logo]);
  const logo = props.logo && !logoFailed ? sizedImage(props.logo, "logo") : null;

  return (
    <section className={`hero hero-${props.variant}`} data-reveal="" aria-label={props.title}>
      <div className="hero-media" data-nav-quiet="">
        <Artwork
          kind="hero"
          src={props.backdrop}
          slug={props.slug}
          provider={props.provider}
          title={props.title}
          alts={props.alts}
          eager
        />
      </div>
      <div className="hero-shade" aria-hidden="true" />
      <div className="hero-copy">
        {props.eyebrow ? <div className="eyebrow">{props.eyebrow}</div> : null}
        {logo ? (
          <img className="hero-logo" src={logo} alt={props.title} onError={() => setLogoFailed(true)} />
        ) : (
          <h2 className="hero-title">{props.title}</h2>
        )}
        {props.meta.length > 0 || props.rating ? (
          <div className="meta">
            {props.meta.join(" · ")}
            {props.rating ? (
              <>
                {props.meta.length > 0 ? " · " : ""}
                <span className="star">★ {props.rating}</span>
              </>
            ) : null}
          </div>
        ) : null}
        <p className="hero-text">{props.description ?? ""}</p>
        {props.progress && props.progress.percent > 0 && props.progress.percent < 100 ? (
          <div className="hero-progress" aria-label={props.progress.label}>
            <span className="hero-progress-bar"><i style={{ width: `${props.progress.percent}%` }} /></span>
            <small>{props.progress.label}</small>
          </div>
        ) : null}
        <div className="hero-actions" data-nav-row="">{props.actions}</div>
      </div>
    </section>
  );
}
