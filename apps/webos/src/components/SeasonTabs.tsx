// Staffeln als waagerechte Reiter.
//
// Beim Wechsel wird nur die Folgenliste getauscht — die Seite bleibt stehen,
// der Fokus springt in die neue Liste statt an den Seitenanfang.

import type { SeasonRef } from "@nori/core";
import { SpotArea, SpotButton } from "../navigation/Spot";

export function SeasonTabs({ seasons, active, route, onPick, stats }: {
  seasons: SeasonRef[];
  active: string;
  route: string;
  onPick(id: string): void;
  stats?(id: string): { watched: number; total: number } | null;
}) {
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
