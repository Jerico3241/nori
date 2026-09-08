// Entdecken: der ganze Katalog mit Filtern.
//
// Alle Filter sind Knopfreihen, keine Auswahlfelder — ein Dropdown lässt sich
// mit einer Fernbedienung nur mit Mühe bedienen, weil es den Fokus in eine
// Liste entführt, die man nicht sieht.

import { scopeIncludesItem, type CatalogItem } from "@nori/core";
import { useEffect, useMemo, useState } from "react";

import { MediaCard } from "../components/MediaCard";
import { ScopeTabs } from "../components/ScopeTabs";
import { EmptyState, ErrorState, GridSkeleton } from "../components/States";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { useData } from "../state/data";
import { useLibrary } from "../state/library";

const ROUTE = "explore";
const PAGE_SIZE = 60;

type Sorting = "alpha" | "genre" | "new";

export function ExplorePage() {
  const { scopedCatalog, reloadCatalog } = useData();
  const { state } = useLibrary();
  const catalog = scopedCatalog();
  const [genre, setGenre] = useState<string | null>(null);
  const [sorting, setSorting] = useState<Sorting>("alpha");
  const [page, setPage] = useState(0);

  const genres = useMemo(() => {
    const counts = new Map<string, number>();
    for (const item of catalog.items) {
      for (const g of item.genres) counts.set(g, (counts.get(g) ?? 0) + 1);
    }
    return Array.from(counts.entries())
      .filter(([, count]) => count >= 3)
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], "de"))
      .slice(0, 24)
      .map(([name, count]) => ({ name, count }));
  }, [catalog.items]);

  const filtered = useMemo(() => {
    let items: CatalogItem[] = catalog.items.filter((item) => scopeIncludesItem(state.scope, item));
    if (genre) {
      items = items.filter((item) =>
        item.genres.some((g) => g.toLowerCase() === genre.toLowerCase()));
    }
    if (sorting === "alpha") {
      items = [...items].sort((a, b) => a.title.localeCompare(b.title, "de"));
    } else if (sorting === "genre") {
      items = [...items].sort((a, b) =>
        (a.genres[0] ?? "").localeCompare(b.genres[0] ?? "", "de") || a.title.localeCompare(b.title, "de"));
    }
    // „Neu" ist die Reihenfolge der Quelle: beide Seiten führen Neues vorn.
    return items;
  }, [catalog.items, genre, sorting, state.scope]);

  const pages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const visible = filtered.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE);

  useEffect(() => setPage(0), [genre, sorting, state.scope]);
  useEffect(() => {
    if (catalog.status !== "ready") return;
    return restoreFocusSoon(ROUTE, ["grid", "filters", "scope"]);
  }, [catalog.status]);

  return (
    <div className="page explore">
      <header className="page-head">
        <h1>Entdecken</h1>
        <ScopeTabs route={ROUTE} />
      </header>

      <SpotArea className="filter-row" spotlightId="explore-sort">
        {([["alpha", "A–Z"], ["new", "Neu"], ["genre", "Nach Genre"]] as [Sorting, string][])
          .map(([value, label]) => (
            <SpotButton
              key={value}
              className={sorting === value ? "selected" : ""}
              aria-pressed={sorting === value}
              focusRoute={ROUTE}
              focusArea="filters"
              focusKey={`sort-${value}`}
              onClick={() => setSorting(value)}
            >
              {label}
            </SpotButton>
          ))}
      </SpotArea>

      {genres.length > 0 ? (
        <SpotArea className="filter-row genres" spotlightId="explore-genres">
          <SpotButton
            className={genre === null ? "selected" : ""}
            aria-pressed={genre === null}
            focusRoute={ROUTE}
            focusArea="filters"
            focusKey="genre-all"
            onClick={() => setGenre(null)}
          >
            Alle Genres
          </SpotButton>
          {genres.map((entry) => (
            <SpotButton
              key={entry.name}
              className={genre === entry.name ? "selected" : ""}
              aria-pressed={genre === entry.name}
              focusRoute={ROUTE}
              focusArea="filters"
              focusKey={`genre-${entry.name}`}
              onClick={() => setGenre(entry.name)}
            >
              {entry.name}
              <small>{entry.count}</small>
            </SpotButton>
          ))}
        </SpotArea>
      ) : null}

      {catalog.status === "error" && catalog.items.length === 0 ? (
        <ErrorState
          title="Katalog nicht ladbar"
          message={catalog.error ?? "Unbekannter Fehler"}
          onRetry={() => {
            reloadCatalog("aniworld");
            reloadCatalog("serienstream");
          }}
        />
      ) : catalog.status === "loading" && catalog.items.length === 0 ? (
        <GridSkeleton />
      ) : visible.length === 0 ? (
        <EmptyState
          title="Keine Treffer"
          message="Mit dieser Auswahl bleibt nichts übrig. Ein anderes Genre oder ein anderer Bereich hilft."
        />
      ) : (
        <>
          <p className="result-count">
            {filtered.length} Titel{genre ? ` in „${genre}“` : ""}
            {pages > 1 ? ` · Seite ${page + 1} von ${pages}` : ""}
          </p>
          <SpotArea className="media-grid" spotlightId={`explore-grid-${page}`}>
            {visible.map((item, index) => (
              <MediaCard
                key={`${item.provider}|${item.slug}`}
                slug={item.slug}
                title={item.title}
                provider={item.provider ?? "aniworld"}
                subtitle={item.genres[0] ?? undefined}
                focusRoute={ROUTE}
                focusArea="grid"
                focusKey={`grid-${item.provider}-${item.slug}`}
                eager={index < 12}
              />
            ))}
          </SpotArea>
          {pages > 1 ? (
            <SpotArea className="pagination" spotlightId="explore-pages">
              <SpotButton
                disabled={page === 0}
                spotlightDisabled={page === 0}
                focusRoute={ROUTE}
                focusArea="pagination"
                focusKey="page-prev"
                onClick={() => setPage((value) => Math.max(0, value - 1))}
              >
                Vorherige Seite
              </SpotButton>
              <span className="page-indicator">{page + 1} / {pages}</span>
              <SpotButton
                disabled={page + 1 >= pages}
                spotlightDisabled={page + 1 >= pages}
                focusRoute={ROUTE}
                focusArea="pagination"
                focusKey="page-next"
                onClick={() => setPage((value) => Math.min(pages - 1, value + 1))}
              >
                Nächste Seite
              </SpotButton>
            </SpotArea>
          ) : null}
        </>
      )}
    </div>
  );
}
