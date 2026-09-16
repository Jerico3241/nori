// Der rechte Bereich im Player: Sprache, Hoster, Staffel, Folgen.
//
// Solange er offen ist, bleibt der Fokus darin — deshalb `restrict="self-only"`.
// Ohne das wandert der Fokus mit der linken Pfeiltaste unter den Drawer auf
// die Bedienung, die man dann nicht sieht.

import type { Episode, HosterOption, SeasonRef } from "@nori/core";
import { Icon } from "@nori/app";
import { availableLanguages, hosterRank } from "@nori/core";
import { useMemo } from "react";
import { SpotArea, SpotButton, useAutoFocus } from "../navigation/Spot";

export interface DrawerProps {
  open: boolean;
  languages: string[];
  activeLang: string;
  hosters: HosterOption[];
  activeHoster: string | null;
  seasons: SeasonRef[];
  activeSeason: string;
  episodes: Episode[];
  activeEpisode: number;
  onLanguage(lang: string): void;
  onHoster(option: HosterOption): void;
  onSeason(id: string): void;
  onEpisode(episode: Episode): void;
  onClose(): void;
}

export function PlayerDrawer(props: DrawerProps) {
  const ref = useAutoFocus(props.open);

  const langs = useMemo(
    () => (props.languages.length > 0 ? props.languages : availableLanguages(props.hosters)),
    [props.languages, props.hosters],
  );

  // Nur Hoster der gewählten Sprache, in der Reihenfolge, die auch die
  // automatische Auswahl benutzt — sonst steht oben ein anderer als der, der
  // tatsächlich zuerst probiert wird.
  const hosters = useMemo(
    () => props.hosters
      .filter((h) => h.lang.toLowerCase() === props.activeLang.toLowerCase())
      .sort((a, b) => hosterRank(a.name) - hosterRank(b.name)),
    [props.hosters, props.activeLang],
  );

  if (!props.open) return null;

  return (
    <>
      <div className="player-panel-shade" aria-hidden="true" />
      <SpotArea
        className="player-panel"
        data-scroll-y=""
        spotlightId="player-drawer"
        restrict="self-only"
        role="dialog"
        aria-label="Quelle und Folgen"
      >
        <div ref={ref}>
          <header>
            <div>
              <span className="eyebrow">Quelle</span>
              <h2>Sprache &amp; Hoster</h2>
            </div>
            <SpotButton
              className="panel-close"
              focusKey="drawer-close"
              aria-label="Schließen"
              onClick={props.onClose}
            >
              <Icon name="close" />
            </SpotButton>
          </header>

          {langs.length > 0 ? (
            <section className="panel-group">
              <h3>Sprache</h3>
              <div className="chip-grid">
                {langs.map((lang) => (
                  <SpotButton
                    key={lang}
                    className={lang === props.activeLang ? "selected" : ""}
                    aria-pressed={lang === props.activeLang}
                    focusKey={`lang-${lang}`}
                    onClick={() => props.onLanguage(lang)}
                  >
                    {labelForLang(lang)}
                  </SpotButton>
                ))}
              </div>
            </section>
          ) : null}

          <section className="panel-group">
            <h3>Hoster</h3>
            {hosters.length === 0 ? (
              <p className="muted-note">Für diese Sprache ist kein Hoster eingetragen.</p>
            ) : (
              <div className="choice-list">
                {hosters.map((option) => (
                  <SpotButton
                    key={`${option.name}|${option.redirectPath}`}
                    className={option.name === props.activeHoster ? "selected" : ""}
                    aria-pressed={option.name === props.activeHoster}
                    focusKey={`hoster-${option.name}`}
                    onClick={() => props.onHoster(option)}
                  >
                    <i className="dot" aria-hidden="true" />
                    {option.name}
                  </SpotButton>
                ))}
              </div>
            )}
          </section>

          {props.seasons.length > 1 ? (
            <section className="panel-group">
              <h3>Staffel</h3>
              <div className="chip-grid">
                {props.seasons.map((season) => (
                  <SpotButton
                    key={season.id}
                    className={season.id === props.activeSeason ? "selected" : ""}
                    aria-pressed={season.id === props.activeSeason}
                    focusKey={`pseason-${season.id}`}
                    onClick={() => props.onSeason(season.id)}
                  >
                    {season.label}
                  </SpotButton>
                ))}
              </div>
            </section>
          ) : null}

          {props.episodes.length > 0 ? (
            <section className="panel-group">
              <h3>Folgen</h3>
              <div className="episode-numbers">
                {props.episodes.map((episode) => (
                  <SpotButton
                    key={episode.path || episode.number}
                    className={episode.number === props.activeEpisode ? "selected" : ""}
                    aria-label={`Folge ${episode.number}: ${episode.germanTitle}`}
                    aria-pressed={episode.number === props.activeEpisode}
                    focusKey={`pep-${episode.number}`}
                    onClick={() => props.onEpisode(episode)}
                  >
                    {String(episode.number).padStart(2, "0")}
                  </SpotButton>
                ))}
              </div>
            </section>
          ) : null}
        </div>
      </SpotArea>
    </>
  );
}

function labelForLang(lang: string): string {
  switch (lang) {
    case "DE": return "Deutsch";
    case "GerSub": return "Deutsche Untertitel";
    case "EN": return "Englisch";
    case "JP": return "Japanisch";
    default: return lang;
  }
}
