// Die Staffelwahl.
//
// ## Warum es zwei Formen gibt
//
// Bis zu acht Staffeln passen als Reiterleiste nebeneinander, und die ist die
// bessere Form: die Auswahl ist sichtbar, ein Tastendruck weit entfernt und
// braucht kein Öffnen.
//
// Darüber wird sie unbrauchbar. Detektiv Conan hat bei AniWorld über dreißig
// Staffeln; als waagerechte Leiste heißt das dreißigmal „rechts" durch eine
// Leiste, die sich unter dem Fokus wegscrollt, und der Weg zurück in die
// Folgenliste ist genauso lang. Ab neun Staffeln erscheint deshalb ein Knopf,
// der ein Auswahlraster öffnet: ein Bildschirm, in dem sich mit allen vier
// Richtungen navigieren lässt.
//
// ## Was das Raster können muss
//
// - **Fokus einsperren** (`restrict="self-only"`). Ohne das wandert der Fokus
//   mit „links" unter das Overlay auf die Seite darunter, die man nicht sieht.
// - **Beim Öffnen den aktiven Eintrag fokussieren**, nicht den ersten. Wer bei
//   Staffel 24 steht, will nicht bei Staffel 1 anfangen.
// - **Mit Zurück schließen**, ohne die Ansicht zu verlassen. Das leistet der
//   Zurück-Stapel aus `navigation/back`.

import type { SeasonRef } from "@nori/core";
import { useEffect, useRef, useState } from "react";
import { useBackHandler } from "../navigation/back";
import { SpotArea, SpotButton, focusWithin } from "../navigation/Spot";
import { Icon } from "./Icon";

/** Ab wie vielen Staffeln die Leiste zum Raster wird. */
export const SEASON_SHEET_THRESHOLD = 9;

export interface SeasonPickerProps {
  seasons: SeasonRef[];
  active: string;
  route: string;
  onPick(id: string): void;
  stats?(id: string): { watched: number; total: number } | null;
}

export function SeasonPicker(props: SeasonPickerProps) {
  if (props.seasons.length < SEASON_SHEET_THRESHOLD) return <SeasonTabs {...props} />;
  return <SeasonSheet {...props} />;
}

/** Die Leiste: bis acht Staffeln. */
function SeasonTabs({ seasons, active, route, onPick, stats }: SeasonPickerProps) {
  return (
    <SpotArea className="season-selector" spotlightId={`seasons-${route}`}>
      {seasons.map((season) => {
        const info = stats?.(season.id) ?? null;
        return (
          <SpotButton
            key={season.id}
            className={season.id === active ? "selected" : ""}
            aria-pressed={season.id === active}
            focusRoute={route}
            focusArea="seasons"
            focusKey={`season-${season.id}`}
            onClick={() => onPick(season.id)}
          >
            {season.label}
            {info && info.total > 0 ? <small>{info.watched}/{info.total}</small> : null}
          </SpotButton>
        );
      })}
    </SpotArea>
  );
}

/** Der Knopf samt Auswahlraster: ab neun Staffeln. */
function SeasonSheet({ seasons, active, route, onPick, stats }: SeasonPickerProps) {
  const [open, setOpen] = useState(false);
  const sheet = useRef<HTMLDivElement>(null);
  const current = seasons.find((season) => season.id === active) ?? seasons[0];

  useBackHandler(() => {
    if (!open) return false;
    setOpen(false);
    return true;
  }, open);

  // Beim Öffnen auf den aktiven Eintrag, nicht auf den ersten. Wer bei Staffel
  // 24 steht, will nicht bei Staffel 1 anfangen.
  useEffect(() => {
    if (!open) return;
    const stop = focusWithin(sheet.current, ".season-grid .selected");
    // Die aktive Staffel kann bei dreißig Einträgen unterhalb des Sichtbaren
    // liegen. Das Scrollen braucht denselben Anlauf wie der Fokus.
    const timer = window.setTimeout(() => {
      sheet.current?.querySelector(".season-grid .selected")
        ?.scrollIntoView({ block: "center" });
    }, 120);
    return () => {
      stop();
      window.clearTimeout(timer);
    };
  }, [open]);

  return (
    <>
      <SpotArea className="season-trigger" spotlightId={`seasons-${route}`}>
        <SpotButton
          className="selected"
          focusRoute={route}
          focusArea="seasons"
          focusKey="season-open"
          aria-haspopup="dialog"
          aria-expanded={open}
          onClick={() => setOpen(true)}
        >
          <Icon name="layers" />
          {current?.label ?? "Staffel"}
          <small>{seasons.length} Staffeln</small>
        </SpotButton>
      </SpotArea>

      {open ? (
        <>
          <div className="season-shade" aria-hidden="true" />
          <SpotArea
            className="season-sheet"
            spotlightId={`season-sheet-${route}`}
            restrict="self-only"
            role="dialog"
            aria-label="Staffel wählen"
          >
            <div ref={sheet}>
              <header>
                <h2>Staffel wählen</h2>
                <SpotButton
                  className="panel-close"
                  focusKey="season-close"
                  aria-label="Schließen"
                  onClick={() => setOpen(false)}
                >
                  <Icon name="close" />
                </SpotButton>
              </header>
              <div className="season-grid">
                {seasons.map((season) => {
                  const info = stats?.(season.id) ?? null;
                  const done = info && info.total > 0 && info.watched >= info.total;
                  return (
                    <SpotButton
                      key={season.id}
                      className={season.id === active ? "selected" : ""}
                      aria-pressed={season.id === active}
                      focusKey={`sheet-season-${season.id}`}
                      onClick={() => {
                        onPick(season.id);
                        setOpen(false);
                      }}
                    >
                      <span className="season-name">{season.label}</span>
                      {info && info.total > 0 ? (
                        <small>{done ? "gesehen" : `${info.watched}/${info.total}`}</small>
                      ) : null}
                    </SpotButton>
                  );
                })}
              </div>
            </div>
          </SpotArea>
        </>
      ) : null}
    </>
  );
}
