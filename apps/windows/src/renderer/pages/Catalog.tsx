// Der Katalog: Suche, Schnellfilter, Raster.
//
// Dieselbe Rangfolge, dieselben Filter und dieselbe **stabile Reihenfolge** wie
// auf dem Fernseher (`stableCatalogOrder` im Kern): TMDB-Angaben, die nach dem
// Aufbau eintreffen, aktualisieren Cover, Untertitel und Bewertung — nicht die
// Reihenfolge. Sonst wanderten Karten unter dem Zeiger weg, und ein Klick
// träfe eine andere Serie als die, auf die gezeigt wurde.
//
// Was hier anders ist als auf dem Fernseher: Das Raster hat keine feste
// Spaltenzahl. Es füllt die Fensterbreite (`auto-fill`), und nachgeladen wird
// beim Scrollen statt beim Fokuswechsel.

import {
  Icon, catalogItemId, tmdb, useCatalogView, useData, useDebounced, useLibrary, usePersistentState,
  catalogOrderSession, fuzzyScore, performanceProfile, searchScore, titleMeta, yearOf,
} from "@nori/app";
import {
  LIBRARY_SCOPES, SCOPES, isNew, normalizeTitle, stableCatalogOrder,
  type HomeCandidate, type LibraryScope,
} from "@nori/core";
import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";

import { Dialog, EmptyState, ErrorState, GridSkeleton, PosterCard } from "../components/ui";

const PAGE = 36;

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
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { reloadCatalog } = useData();
  const library = useLibrary();
  const { catalog, items, candidates, representative } = useCatalogView();
  const [orderSession] = useState(() => catalogOrderSession("catalog-windows", true));

  const [query, setQuery] = usePersistentState("catalog.query", "");
  const [chip, setChip] = usePersistentState("catalog.chip", "all");
  const [sort, setSort] = usePersistentState<Sort>("catalog.sort", "popular");
  const [decade, setDecade] = usePersistentState<Decade>("catalog.decade", "all");
  const [limit, setLimit] = useState(PAGE);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const debounced = useDebounced(query, 300);
  const input = useRef<HTMLInputElement>(null);
  const sentinel = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (params.get("suche") === "1") input.current?.focus();
  }, [params]);

  const genres = useMemo(() => {
    const counts = new Map<string, number>();
    for (const item of items) {
      for (const genre of item.genres) counts.set(genre, (counts.get(genre) ?? 0) + 1);
    }
    return Array.from(counts.entries())
      .filter(([, count]) => count >= 3)
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], "de"))
      .slice(0, 8)
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
    if (decade !== "all") {
      list = list.filter((candidate) => inDecade(yearOf(candidate.title, candidate.signals), decade));
    }

    const needle = normalizeTitle(debounced.trim());
    if (needle.length >= 2) {
      const scored: { candidate: HomeCandidate; score: number }[] = [];
      for (const candidate of list) {
        const score = searchScore(candidate.title, needle);
        if (score >= 0) scored.push({ candidate, score });
      }
      // Tippfehler nur, wenn die strengen Stufen wenig finden — sie kosten ein
      // Vielfaches und verdünnten sonst gute Treffer mit schlechten.
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

  const view = JSON.stringify([library.state.scope, chip, sort, decade, debounced.trim()]);
  const shown = useMemo(() => {
    const idOf = (candidate: HomeCandidate) => `${candidate.title.provider}|${candidate.title.slug}`;
    const byId = new Map<string, HomeCandidate>();
    for (const candidate of candidates) {
      const id = idOf(candidate);
      byId.set(id, candidate);
      orderSession.known.set(id, candidate);
    }
    const available = new Set(catalog.items.map(catalogItemId));
    orderSession.order = stableCatalogOrder(
      orderSession.order, view, results.map(idOf), available, (id) => representative.get(id) ?? id,
    );
    return orderSession.order.ids
      .map((id) => byId.get(id) ?? orderSession.known.get(id))
      .filter((candidate): candidate is HomeCandidate => Boolean(candidate));
  }, [candidates, catalog.items, orderSession, representative, results, view]);

  useEffect(() => setLimit(PAGE), [chip, sort, decade, debounced, library.state.scope]);

  /**
   * Nachladen beim Scrollen.
   *
   * Ein Beobachter am Ende des Rasters statt eines Scroll-Handlers: der
   * meldet sich genau einmal, wenn das Ende in Sicht kommt, und kostet
   * dazwischen nichts.
   */
  const visible = shown.slice(0, limit);
  useEffect(() => {
    const node = sentinel.current;
    if (!node || visible.length >= shown.length) return undefined;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) setLimit((current) => current + PAGE);
    }, { rootMargin: "600px 0px" });
    observer.observe(node);
    return () => observer.disconnect();
  }, [visible.length, shown.length]);

  const eagerCards = performanceProfile().eagerCards * 2;
  const activeFilters = (library.state.scope !== "all" ? 1 : 0) + (decade !== "all" ? 1 : 0) + (sort !== "popular" ? 1 : 0);
  const needsTmdb = chip === "new" || chip === "popular" || chip === "top" || decade !== "all";
  const headline = debounced.trim().length >= 2 ? `Suche „${debounced.trim()}“` : SCOPES[library.state.scope].headline;

  return (
    <div className="page">
      <div className="chips">
        {[
          { value: "all", label: "Alle" },
          { value: "new", label: "Neu" },
          { value: "popular", label: "Beliebt" },
          { value: "top", label: "Top bewertet" },
          ...genres.map((genre) => ({ value: `genre:${genre}`, label: genre })),
        ].map((option) => (
          <button
            key={option.value}
            type="button"
            className={`chip${option.value === chip ? " active" : ""}`}
            aria-pressed={option.value === chip}
            onClick={() => setChip(option.value)}
          >
            {option.label}
          </button>
        ))}
        <button
          type="button"
          className={`chip${activeFilters > 0 ? " active" : ""}`}
          onClick={() => setFiltersOpen(true)}
        >
          <Icon name="filter" />
          {activeFilters > 0 ? ` Filter · ${activeFilters}` : " Filter"}
        </button>
      </div>

      <div className="section-head">
        <h2>{headline}</h2>
        <span>
          {shown.length} {shown.length === 1 ? "Ergebnis" : "Ergebnisse"}
          {" · "}
          {debounced.trim().length >= 2 ? "Beste Treffer" : SORTS.find((entry) => entry.value === sort)?.label}
        </span>
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
        <GridSkeleton count={18} />
      ) : visible.length === 0 ? (
        <EmptyState
          title="Keine Titel gefunden"
          message={needsTmdb && !tmdb.available
            ? "Neu, Beliebt, Top bewertet und das Erscheinungsjahr kommen von TMDB — und TMDB ist ausgeschaltet."
            : "Mit dieser Suche oder diesen Filtern bleibt nichts übrig."}
          action={(
            <button
              type="button"
              className="btn primary"
              onClick={() => { setChip("all"); setSort("popular"); setDecade("all"); setQuery(""); }}
            >
              Filter zurücksetzen
            </button>
          )}
        />
      ) : (
        <>
          <div className="grid">
            {visible.map((candidate, index) => (
              <PosterCard
                key={`${candidate.title.provider}|${candidate.title.slug}`}
                slug={candidate.title.slug}
                provider={candidate.title.provider}
                title={candidate.title.title}
                alts={candidate.title.alts}
                subtitle={titleMeta(candidate.title, candidate.signals)}
                eager={index < eagerCards}
                onSelect={() => navigate(
                  `/titel/${candidate.title.provider}/${encodeURIComponent(candidate.title.slug)}`,
                )}
              />
            ))}
          </div>
          <div ref={sentinel} style={{ height: 1 }} />
        </>
      )}

      <Dialog
        open={filtersOpen}
        title="Filter"
        description="Bereich, Sortierung und Erscheinungsjahr. Das Jahr kommt von TMDB — Titel ohne sichere Zuordnung fallen bei einer Jahresauswahl heraus."
        onClose={() => setFiltersOpen(false)}
        actions={(
          <>
            <button
              type="button"
              className="btn"
              onClick={() => { setChip("all"); setSort("popular"); setDecade("all"); setQuery(""); }}
            >
              Zurücksetzen
            </button>
            <button type="button" className="btn primary" onClick={() => setFiltersOpen(false)}>Fertig</button>
          </>
        )}
      >
        <div className="card-panel">
          <h3>Bereich</h3>
          <div className="chips">
            {LIBRARY_SCOPES.map((scope) => (
              <button
                key={scope}
                type="button"
                className={`chip${library.state.scope === scope ? " active" : ""}`}
                onClick={() => library.setScope(scope as LibraryScope)}
              >
                {SCOPES[scope].label}
              </button>
            ))}
          </div>
          <h3>Sortierung</h3>
          <div className="chips">
            {SORTS.map((option) => (
              <button
                key={option.value}
                type="button"
                className={`chip${sort === option.value ? " active" : ""}`}
                onClick={() => setSort(option.value)}
              >
                {option.label}
              </button>
            ))}
          </div>
          <h3>Erscheinungsjahr</h3>
          <div className="chips">
            {DECADES.map((option) => (
              <button
                key={option.value}
                type="button"
                className={`chip${decade === option.value ? " active" : ""}`}
                onClick={() => setDecade(option.value)}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>
      </Dialog>
    </div>
  );
}

/** Das Suchfeld der Kopfzeile — steht in `App.tsx`, wirkt hier. */
export function CatalogSearchField() {
  const [query, setQuery] = usePersistentState("catalog.query", "");
  const navigate = useNavigate();
  return (
    <label className="search">
      <Icon name="search" />
      <input
        type="search"
        value={query}
        placeholder="Titel, Originaltitel, Genre …"
        aria-label="Katalog durchsuchen"
        onChange={(event) => {
          setQuery(event.target.value);
          if (!window.location.hash.startsWith("#/katalog")) navigate("/katalog");
        }}
      />
    </label>
  );
}
