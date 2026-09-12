// Merkliste — dieselbe Liste wie in den Apple-Apps, nur als Raster.
//
// Die Reihenfolge ist die des Merkzeitpunkts, das Jüngste vorn: `favorites`
// führt es so, und `favoriteAddedAt` (Schema v5) hält es auch über einen
// Abgleich hinweg fest.
//
// Auf jeder Kachel steht zusätzlich, wo man in der Serie steht — das ist die
// Frage, mit der man eine Merkliste öffnet. Die Angabe kommt aus dem
// Fortschritt, nicht aus einem Zähler: wie viele Folgen eine Serie insgesamt
// hat, weiß Nori ohne einen Abruf je Titel nicht (siehe `rules.watchState` in
// `config/contract.json`).

import { progressPercent, providerFromPath, type WatchProgress } from "@nori/core";
import { useEffect, useMemo } from "react";

import { MediaCard } from "../components/MediaCard";
import { EmptyState } from "../components/States";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotArea } from "../navigation/Spot";
import { covers } from "../services/covers";
import { useLibrary } from "../state/library";

const ROUTE = "watchlist";

export function WatchlistPage() {
  const library = useLibrary();
  const slugs = library.state.favorites;

  /** Je Serie der jüngste Fortschritt — für Balken und Zeile unter dem Titel. */
  const progressBySlug = useMemo(() => {
    const out = new Map<string, WatchProgress>();
    for (const item of Object.values(library.state.progress)) {
      const key = `${item.provider ?? providerFromPath(item.episodePath)}|${item.slug}`;
      const existing = out.get(key);
      if (!existing || item.updatedAt > existing.updatedAt) out.set(key, item);
    }
    return out;
  }, [library.state.progress]);

  useEffect(() => {
    if (slugs.length === 0) return;
    return restoreFocusSoon(ROUTE, ["grid"]);
  }, [slugs.length]);

  return (
    <div className="page">
      <header className="page-head">
        <h1>Merkliste</h1>
        {slugs.length > 0 ? <p className="result-count">{slugs.length} Titel</p> : null}
      </header>

      {slugs.length === 0 ? (
        <EmptyState
          title="Noch nichts gemerkt"
          message="Auf einer Detailseite legt „Merkliste“ einen Titel hier ab. Die Liste ist dieselbe wie in den anderen Nori-Apps."
        />
      ) : (
        <SpotArea className="media-grid" spotlightId="watchlist-grid">
          {slugs.map((slug, index) => {
            const provider = library.favoriteProvider(slug);
            const details = covers.details(slug, provider);
            const progress = progressBySlug.get(`${provider}|${slug}`) ?? null;
            const percent = progress ? progressPercent(progress) : 0;
            return (
              <MediaCard
                key={slug}
                slug={slug}
                title={library.state.titles[slug] ?? slug}
                provider={provider}
                progress={progress}
                rating={details.rating}
                votes={details.votes}
                subtitle={progress
                  ? `S${progress.season} · F${progress.episode}${percent >= 100 ? " · gesehen" : ` · ${percent} %`}`
                  : undefined}
                focusRoute={ROUTE}
                focusArea="grid"
                focusKey={`fav-${slug}`}
                eager={index < 12}
              />
            );
          })}
        </SpotArea>
      )}
    </div>
  );
}
