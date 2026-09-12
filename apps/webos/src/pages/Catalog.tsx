// Der Katalog: Suche, Schnellfilter, Raster.
//
//     Seitenkopf   Entdecken · Katalog · Suchfeld · Filter
//     Chips        Alle · Neu · Beliebt · Top bewertet · häufigste Genres
//     Raster       fünf Poster je Zeile bei 1080p
//
// ## Nur echte Filter
//
// „Neu", „Beliebt" und „Top bewertet" kommen aus TMDB-Signalen; ohne TMDB sind
// sie leer, und die Seite sagt das. Im Dialog stehen Bereich (Anime/Serien/
// K-Drama), Sortierung und Erscheinungsjahr. **Status** und **Sprache** fehlen
// absichtlich: die Katalogseiten der Quellen führen beides nicht, und eine
// Abfrage je Titel wäre bei zehntausend Titeln keine Option. Ein Filter, der
// nichts filtert, wäre schlechter als keiner.
//
// ## Große Kataloge
//
// Gezeichnet werden zuerst dreißig Karten; erreicht der Fokus die letzten zwei
// Zeilen, kommen dreißig dazu. So bleibt der DOM-Baum auf einem Fernseher
// klein, und der Fokus kann trotzdem nie an einem Ende ankommen, hinter dem
// noch Titel liegen.

import {
  LIBRARY_SCOPES, SCOPES, isNew, normalizeTitle,
  type HomeCandidate, type LibraryScope,
} from "@nori/core";
import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";

import { ChipRow } from "../components/Chips";
import { Icon } from "../components/Icon";
import { titleMeta, yearOf } from "../components/meta";
import { Dialog } from "../components/Overlay";
import { PosterCard } from "../components/PosterCard";
import { Screen } from "../components/Screen";
import { EmptyState, ErrorState, GridSkeleton } from "../components/States";
import { useDebounced } from "../hooks/useDebounced";
import { usePersistentState } from "../hooks/usePersistentState";
import { focusElement } from "../navigation/engine";
import { rememberFocus, restoreFocusSoon } from "../navigation/focusMemory";
import { SpotButton } from "../navigation/Spot";
import { tmdb } from "../services/tmdb";
import { useCatalogView } from "../state/catalog";
import { useData } from "../state/data";
import { useLibrary } from "../state/library";
import { fuzzyScore, searchScore } from "../state/search";

const ROUTE = "catalog";
const PAGE = 30;

type Sort = "popular" | "az" | "rating";
type Decade = "all" | "2020" | "2010" | "2000" | "older";

const SORTS: { value: Sort; label: string }[] = [
  { value: "popular", label: "Beliebtheit" },
  { value: "az", label: "A–Z" },
  { value: "rating", label: "Bewertung" },
];

const DECADES: { value: Decade; label: string }[] = [
  { value: "all", label: "Alle Jahre" },
  { value: "2020", label: "Ab 2020" },
  { value: "2010", label: "2010–2019" },
  { value: "2000", label: "2000–2009" },
  { value: "older", label: "Vor 2000" },
];

function inDecade(year: number | null, decade: Decade): boolean {
  if (decade === "all") return true;
  if (year === null) return false;
  if (decade === "older") return year < 2000;
  const start = Number(decade);
  return decade === "2020" ? year >= 2020 : year >= start && year < start + 10;
}

function byTitle(a: HomeCandidate, b: HomeCandidate): number {
  return a.title.title.localeCompare(b.title.title, "de");
}

function byPopularity(a: HomeCandidate, b: HomeCandidate): number {
  const ra = a.signals.trendingRank ?? Infinity;
  const rb = b.signals.trendingRank ?? Infinity;
  if (ra !== rb) return ra - rb;
  const pa = a.signals.popularity ?? -1;
  const pb = b.signals.popularity ?? -1;
  if (pa !== pb) return pb - pa;
  return byTitle(a, b);
}

function byRating(a: HomeCandidate, b: HomeCandidate): number {
  const va = (a.signals.voteCount ?? 0) >= 50 ? a.signals.voteAverage ?? -1 : -1;
  const vb = (b.signals.voteCount ?? 0) >= 50 ? b.signals.voteAverage ?? -1 : -1;
  if (va !== vb) return vb - va;
  return byTitle(a, b);
}

export function CatalogPage() {
  const [params] = useSearchParams();
  const { reloadCatalog } = useData();
  const library = useLibrary();
  const { catalog, items, candidates } = useCatalogView();

  const [query, setQuery] = usePersistentState("catalog.query", "");
  const [chip, setChip] = usePersistentState("catalog.chip", "all");
  const [sort, setSort] = usePersistentState<Sort>("catalog.sort", "popular");
  const [decade, setDecade] = usePersistentState<Decade>("catalog.decade", "all");
  const [limit, setLimit] = usePersistentState("catalog.limit", PAGE);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const debounced = useDebounced(query, 350);
  const inputRef = useRef<HTMLInputElement>(null);
  const wantsSearch = params.get("suche") === "1";

  const genres = useMemo(() => {
    const counts = new Map<string, number>();
    for (const item of items) {
      for (const genre of item.genres) counts.set(genre, (counts.get(genre) ?? 0) + 1);
    }
    return Array.from(counts.entries())
      .filter(([, count]) => count >= 3)
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], "de"))
      .slice(0, 6)
      .map(([name]) => name);
  }, [items]);

  const results = useMemo(() => {
    const now = Date.now();
    let list = candidates;
    if (chip === "new") list = list.filter((candidate) => isNew(candidate.signals, now));
    else if (chip === "popular") {
      list = list.filter((candidate) =>
        candidate.signals.trendingRank !== null || (candidate.signals.popularity ?? 0) > 0);
    } else if (chip === "top") {
      list = list.filter((candidate) =>
        (candidate.signals.voteCount ?? 0) >= 200 && (candidate.signals.voteAverage ?? 0) > 0);
    } else if (chip.startsWith("genre:")) {
      const wanted = chip.slice(6).toLowerCase();
      list = list.filter((candidate) => candidate.title.genres.some((genre) => genre.toLowerCase() === wanted));
    }
    if (decade !== "all") list = list.filter((candidate) => inDecade(yearOf(candidate.title, candidate.signals), decade));

    const needle = normalizeTitle(debounced.trim());
    if (needle.length >= 2) {
      const scored: { candidate: HomeCandidate; score: number }[] = [];
      for (const candidate of list) {
        const score = searchScore(candidate.title, needle);
        if (score >= 0) scored.push({ candidate, score });
      }
      // Tippfehler nur, wenn die strengen Stufen wenig finden — sie kosten
      // ein Vielfaches und würden sonst gute Treffer mit schlechten verdünnen.
      if (scored.length < 12) {
        const found = new Set(scored.map((entry) => entry.candidate));
        for (const candidate of list) {
          if (found.has(candidate)) continue;
          const score = fuzzyScore(candidate.title, needle);
          if (score >= 0) scored.push({ candidate, score });
        }
      }
      return scored
        .sort((a, b) => a.score - b.score || byPopularity(a.candidate, b.candidate))
        .map((entry) => entry.candidate);
    }

    const order = chip === "top" || sort === "rating" ? byRating : sort === "az" ? byTitle : byPopularity;
    return [...list].sort(order);
  }, [candidates, chip, decade, debounced, sort]);

  // Ein anderer Filter fängt oben an. Beim ersten Aufbau nicht: dort steht die
  // Anzahl, die beim Verlassen gezeichnet war, damit der Fokus seine Karte
  // wiederfindet.
  const firstRun = useRef(true);
  useEffect(() => {
    if (firstRun.current) {
      firstRun.current = false;
      return;
    }
    setLimit(PAGE);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chip, sort, decade, debounced, library.state.scope]);

  useEffect(() => {
    if (wantsSearch) {
      const timer = window.setTimeout(() => {
        if (inputRef.current) focusElement(inputRef.current, { instant: true });
      }, 60);
      return () => window.clearTimeout(timer);
    }
    return restoreFocusSoon(ROUTE, ["grid", "chips", "top"], { initial: ".catalog-grid .spottable" });
  }, [wantsSearch]);

  const visible = results.slice(0, Math.max(PAGE, limit));
  const activeFilters = (library.state.scope !== "all" ? 1 : 0) + (decade !== "all" ? 1 : 0) + (sort !== "popular" ? 1 : 0);
  const needsTmdb = chip === "new" || chip === "popular" || chip === "top" || decade !== "all";
  const headline = debounced.trim().length >= 2
    ? `Suche „${debounced.trim()}“`
    : SCOPES[library.state.scope].headline;
  const sortLabel = debounced.trim().length >= 2
    ? "Beste Treffer"
    : chip === "top" ? "Bewertung ↓" : `${SORTS.find((entry) => entry.value === sort)?.label ?? ""} ↓`;

  const resetFilters = () => {
    setChip("all");
    setSort("popular");
    setDecade("all");
    setQuery("");
  };

  return (
    <Screen
      route={ROUTE}
      eyebrow="Entdecken"
      title="Katalog"
      className="catalog"
      actions={(
        <>
          <label className="searchbar">
            <Icon name="search" />
            <input
              ref={inputRef}
              className="spottable search-input"
              data-focus-key="catalog-search"
              type="search"
              value={query}
              placeholder="Titel, Originaltitel, Genre …"
              aria-label="Katalog durchsuchen"
              onFocus={() => rememberFocus(ROUTE, "top", "catalog-search")}
              onChange={(event) => setQuery(event.target.value)}
            />
          </label>
          {query ? (
            <SpotButton className="glassbtn" focusRoute={ROUTE} focusArea="top" focusKey="search-clear" onClick={() => setQuery("")}>
              <Icon name="close" />
              Leeren
            </SpotButton>
          ) : null}
          <SpotButton
            className="glassbtn"
            focusRoute={ROUTE}
            focusArea="top"
            focusKey="filter-open"
            aria-haspopup="dialog"
            onClick={() => setFiltersOpen(true)}
          >
            <Icon name="filter" />
            {activeFilters > 0 ? `Filter · ${activeFilters}` : "Filter"}
          </SpotButton>
        </>
      )}
    >
      <ChipRow
        label="Schnellfilter"
        route={ROUTE}
        area="chips"
        value={chip}
        onChange={setChip}
        options={[
          { value: "all", label: "Alle" },
          { value: "new", label: "Neu" },
          { value: "popular", label: "Beliebt" },
          { value: "top", label: "Top bewertet" },
          ...genres.map((genre) => ({ value: `genre:${genre}`, label: genre })),
        ]}
      />

      <div className="section-head">
        <h2>{headline}</h2>
        <span>{results.length} {results.length === 1 ? "Ergebnis" : "Ergebnisse"} · {sortLabel}</span>
      </div>

      {catalog.status === "error" && items.length === 0 ? (
        <ErrorState
          title="Katalog nicht ladbar"
          message={catalog.error ?? "Unbekannter Fehler"}
          onRetry={() => {
            reloadCatalog("aniworld");
            reloadCatalog("serienstream");
          }}
        />
      ) : catalog.status === "loading" && items.length === 0 ? (
        <GridSkeleton />
      ) : visible.length === 0 ? (
        <EmptyState
          title="Keine Titel gefunden"
          message={needsTmdb && !tmdb.available
            ? "Neu, Beliebt, Top bewertet und das Erscheinungsjahr kommen von TMDB — und TMDB ist ausgeschaltet."
            : "Mit dieser Suche oder diesen Filtern bleibt nichts übrig."}
          action={(
            <SpotButton className="hero-btn primary" focusRoute={ROUTE} focusArea="chips" focusKey="filters-reset" onClick={resetFilters}>
              Filter zurücksetzen
            </SpotButton>
          )}
        />
      ) : (
        <div className="catalog-grid">
          {visible.map((candidate, index) => (
            <PosterCard
              key={`${candidate.title.provider}|${candidate.title.slug}`}
              slug={candidate.title.slug}
              provider={candidate.title.provider}
              title={candidate.title.title}
              alts={candidate.title.alts}
              subtitle={titleMeta(candidate.title, candidate.signals)}
              focusRoute={ROUTE}
              focusArea="grid"
              focusKey={`grid-${candidate.title.provider}-${candidate.title.slug}`}
              eager={index < 10}
              onFocus={() => {
                if (index >= visible.length - 10 && visible.length < results.length) {
                  setLimit((current) => Math.max(current, visible.length) + PAGE);
                }
              }}
            />
          ))}
        </div>
      )}

      <Dialog
        open={filtersOpen}
        onClose={() => setFiltersOpen(false)}
        eyebrow="Katalog"
        title="Filter"
        id="catalog-filters"
        initial=".chip.active"
      >
        <div className="dialog-group">
          <h3>Bereich</h3>
          <ChipRow<LibraryScope>
            label="Bereich"
            route={ROUTE}
            area="filter-scope"
            value={library.state.scope}
            onChange={(scope) => library.setScope(scope)}
            options={LIBRARY_SCOPES.map((scope) => ({ value: scope, label: SCOPES[scope].label }))}
          />
        </div>
        <div className="dialog-group">
          <h3>Sortierung</h3>
          <ChipRow<Sort> label="Sortierung" route={ROUTE} area="filter-sort" value={sort} onChange={setSort} options={SORTS} />
        </div>
        <div className="dialog-group">
          <h3>Erscheinungsjahr</h3>
          <ChipRow<Decade> label="Erscheinungsjahr" route={ROUTE} area="filter-year" value={decade} onChange={setDecade} options={DECADES} />
          <p className="dialog-note">
            Nach der Erstausstrahlung laut TMDB. Titel ohne sichere TMDB-Zuordnung fallen bei
            einer Jahresauswahl heraus.
          </p>
        </div>
        <div className="dialog-actions">
          <SpotButton className="hero-btn" focusKey="filter-reset" onClick={resetFilters}>
            Zurücksetzen
          </SpotButton>
          <SpotButton className="hero-btn primary" focusKey="filter-done" onClick={() => setFiltersOpen(false)}>
            Fertig
          </SpotButton>
        </div>
      </Dialog>
    </Screen>
  );
}
