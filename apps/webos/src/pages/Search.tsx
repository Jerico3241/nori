// Suche.
//
// Zwei Eingabewege nebeneinander: das Textfeld ruft die Systemtastatur von
// webOS auf, die Buchstabenreihe darunter kommt ohne sie aus. Ohne die zweite
// wäre die Suche auf Geräten ohne eingeblendete Tastatur nicht bedienbar; ohne
// die erste wäre sie mühsam.
//
// Gesucht wird im geladenen Katalog, nicht bei der Quelle: die Kataloge liegen
// ohnehin schon im Speicher, und eine Anfrage je Tastendruck wäre auf einem
// Fernseher spürbar langsamer als eine Filterung von zwanzigtausend Titeln.

import { scopeIncludesItem, type CatalogItem } from "@nori/core";
import { useEffect, useMemo, useRef, useState } from "react";

import { MediaCard } from "../components/MediaCard";
import { ScopeTabs } from "../components/ScopeTabs";
import { EmptyState, GridSkeleton } from "../components/States";
import { useDebounced } from "../hooks/useDebounced";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { useData } from "../state/data";
import { useLibrary } from "../state/library";
import { Icon } from "../components/Icon";

const ROUTE = "search";
const ROWS = ["ABCDEFG", "HIJKLMN", "OPQRSTU", "VWXYZ0123", "456789 "];

export function SearchPage() {
  const { scopedCatalog } = useData();
  const { state } = useLibrary();
  const catalog = scopedCatalog();
  const [query, setQuery] = useState("");
  const debounced = useDebounced(query, 380);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    // Beim Aufrufen der Seite steht der Fokus im Feld — die Tastatur von webOS
    // öffnet sich dadurch von selbst.
    const timer = window.setTimeout(() => inputRef.current?.focus(), 220);
    return () => window.clearTimeout(timer);
  }, []);

  const results = useMemo(() => {
    const needle = debounced.trim().toLowerCase();
    if (needle.length < 2) return [] as CatalogItem[];
    const scored: { item: CatalogItem; score: number }[] = [];
    for (const item of catalog.items) {
      if (!scopeIncludesItem(state.scope, item)) continue;
      const title = item.title.toLowerCase();
      let score = -1;
      if (title === needle) score = 0;
      else if (title.startsWith(needle)) score = 1;
      else if (title.includes(needle)) score = 2;
      else if (item.alts.some((alt) => alt.toLowerCase().includes(needle))) score = 3;
      if (score < 0) continue;
      scored.push({ item, score });
      if (scored.length > 600) break;
    }
    return scored
      .sort((a, b) => a.score - b.score || a.item.title.localeCompare(b.item.title, "de"))
      .slice(0, 120)
      .map((entry) => entry.item);
  }, [debounced, catalog.items, state.scope]);

  useEffect(() => {
    if (results.length === 0) return;
    return restoreFocusSoon(ROUTE, ["results"]);
  }, [results.length]);

  return (
    <div className="page search">
      <header className="page-head">
        <h1>Suche</h1>
        <ScopeTabs route={ROUTE} />
      </header>

      <div className="search-bar">
        <Icon name="search" />
        <input
          ref={inputRef}
          className="spottable"
          type="search"
          value={query}
          placeholder="Titel eingeben"
          aria-label="Suchbegriff"
          onChange={(event) => setQuery(event.target.value)}
        />
        {query ? (
          <SpotButton
            focusRoute={ROUTE}
            focusArea="keyboard"
            focusKey="clear"
            aria-label="Eingabe löschen"
            onClick={() => {
              setQuery("");
              inputRef.current?.focus();
            }}
          >
            <Icon name="close" />
          </SpotButton>
        ) : null}
      </div>

      <SpotArea className="keypad" spotlightId="search-keypad">
        {ROWS.map((row) => (
          <div className="keypad-row" key={row}>
            {Array.from(row).map((letter) => (
              <SpotButton
                key={letter}
                className="keypad-key"
                focusRoute={ROUTE}
                focusArea="keyboard"
                focusKey={`key-${letter}`}
                aria-label={letter === " " ? "Leerzeichen" : letter}
                onClick={() => setQuery((value) => value + letter)}
              >
                {letter === " " ? "␣" : letter}
              </SpotButton>
            ))}
          </div>
        ))}
        <div className="keypad-row">
          <SpotButton
            className="keypad-key wide"
            focusRoute={ROUTE}
            focusArea="keyboard"
            focusKey="key-back"
            onClick={() => setQuery((value) => value.slice(0, -1))}
          >
            Löschen
          </SpotButton>
        </div>
      </SpotArea>

      {catalog.status === "loading" && catalog.items.length === 0 ? (
        <GridSkeleton count={12} />
      ) : debounced.trim().length < 2 ? (
        <EmptyState
          title="Wonach suchst du?"
          message={`Ab zwei Zeichen wird gesucht — durchsucht werden ${catalog.items.length} Titel samt Alternativtiteln.`}
        />
      ) : results.length === 0 ? (
        <EmptyState
          title="Keine Treffer"
          message={`Für „${debounced}“ gibt es in diesem Bereich nichts.`}
        />
      ) : (
        <>
          <p className="result-count">{results.length} Treffer für „{debounced}“</p>
          <SpotArea className="media-grid" spotlightId="search-results">
            {results.map((item, index) => (
              <MediaCard
                key={`${item.provider}|${item.slug}`}
                slug={item.slug}
                title={item.title}
                provider={item.provider ?? "aniworld"}
                subtitle={item.genres[0] ?? undefined}
                focusRoute={ROUTE}
                focusArea="results"
                focusKey={`result-${item.provider}-${item.slug}`}
                eager={index < 12}
              />
            ))}
          </SpotArea>
        </>
      )}
    </div>
  );
}
