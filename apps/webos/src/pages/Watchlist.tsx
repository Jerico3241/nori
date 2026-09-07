// Merkliste — dieselbe Liste wie in den Apple-Apps, nur als Raster.

import { useEffect } from "react";

import { MediaCard } from "../components/MediaCard";
import { EmptyState } from "../components/States";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotArea } from "../navigation/Spot";
import { useLibrary } from "../state/library";

const ROUTE = "watchlist";

export function WatchlistPage() {
  const library = useLibrary();
  const slugs = library.state.favorites;

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
          {slugs.map((slug, index) => (
            <MediaCard
              key={slug}
              slug={slug}
              title={library.state.titles[slug] ?? slug}
              provider={library.favoriteProvider(slug)}
              focusRoute={ROUTE}
              focusArea="grid"
              focusKey={`fav-${slug}`}
              eager={index < 12}
            />
          ))}
        </SpotArea>
      )}
    </div>
  );
}
