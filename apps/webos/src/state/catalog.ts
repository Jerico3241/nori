// Der Katalog, wie ihn die Ansicht braucht: zusammengeführt und bewertbar.
//
// ## Dubletten
//
// Im Bereich „Alle" laufen AniWorld und Serienstream zusammen, und manche
// Serie führen beide. Zweimal dasselbe Poster nebeneinander sieht aus wie ein
// Fehler. Zusammengeführt wird aber nur, was **sicher** dasselbe ist:
//
// - dieselbe TMDB-Kennung — die stärkste Auskunft, die es gibt, oder
// - derselbe Slug **und** derselbe normalisierte Titel.
//
// Nicht über den Titel allein: „Dark" kann bei beiden Quellen eine andere
// Serie sein, und eine versteckte echte Serie ist schlimmer als eine sichtbare
// Dublette. Behalten wird bei Zeichentrick die Fassung von AniWorld, sonst die
// von Serienstream.
//
// ## Signale
//
// Jede Karte bekommt dieselben TMDB-Signale wie auf der Startseite
// (`buildCandidates` aus dem Kern): Beliebtheit, Trend, Bewertung,
// Erstausstrahlung. Daraus entstehen die Filter „Neu", „Beliebt" und
// „Top bewertet". Verfügbar ist trotzdem nur, was die Quellen führen — eine
// Karte entsteht nie aus einer TMDB-Zeile.

import {
  HomeCatalogIndex, TMDB_GENRE_ANIMATION, buildCandidates, homeTitleFrom, normalizeTitle,
  type CatalogItem, type HomeCandidate,
} from "@nori/core";
import { useEffect, useMemo, useState } from "react";

import { tmdb } from "../services/tmdb";
import { useData } from "./data";
import { useLibrary } from "./library";

export function dedupeCatalog(items: CatalogItem[]): CatalogItem[] {
  const out: CatalogItem[] = [];
  const byKey = new Map<string, number>();
  for (const item of items) {
    const provider = item.provider ?? "aniworld";
    const art = tmdb.art(item.slug, provider);
    const keys = [
      art ? `tmdb:${art.tmdbID}` : null,
      `slug:${item.slug}|${normalizeTitle(item.title)}`,
    ].filter((key): key is string => key !== null);

    const existing = keys.map((key) => byKey.get(key)).find((index) => index !== undefined);
    if (existing === undefined) {
      keys.forEach((key) => byKey.set(key, out.length));
      out.push(item);
      continue;
    }
    const animated = art?.genreIDs.includes(TMDB_GENRE_ANIMATION) ?? false;
    const preferred = animated ? "aniworld" : "serienstream";
    if ((out[existing].provider ?? "aniworld") !== preferred && provider === preferred) {
      out[existing] = item;
    }
    keys.forEach((key) => byKey.set(key, existing));
  }
  return out;
}

export function useCatalogView() {
  const { scopedCatalog, tmdbRoute } = useData();
  const library = useLibrary();
  const catalog = scopedCatalog();
  const [generation, setGeneration] = useState(0);

  // TMDB-Treffer gebündelt übernehmen. Jeder einzelne hieße: alle Karten neu
  // bewerten — bei zehntausend Titeln spürbar auf einem Fernseher.
  useEffect(() => {
    let timer: number | null = null;
    const stop = tmdb.subscribe(() => {
      if (timer !== null) return;
      timer = window.setTimeout(() => {
        timer = null;
        setGeneration((value) => value + 1);
      }, 1500);
    });
    return () => {
      stop();
      if (timer !== null) window.clearTimeout(timer);
    };
  }, []);

  // Die Ranglisten braucht „Beliebt" auch dann, wenn die Startseite nie
  // geöffnet wurde.
  useEffect(() => {
    if (!tmdb.available) return undefined;
    let cancelled = false;
    void tmdb.ensureFeeds().then(() => {
      if (!cancelled) setGeneration((value) => value + 1);
    });
    return () => {
      cancelled = true;
    };
  }, [tmdbRoute.effective]);

  const items = useMemo(() => {
    void generation;
    return library.state.scope === "all" ? dedupeCatalog(catalog.items) : catalog.items;
  }, [catalog.items, library.state.scope, generation]);

  const favorites = library.state.favorites;
  const candidates = useMemo<HomeCandidate[]>(() => {
    void generation;
    const titles = items.map((item) => homeTitleFrom(item));
    const signals = tmdb.cachedSignals();
    return buildCandidates({
      catalog: titles,
      index: new HomeCatalogIndex(titles),
      trending: signals.trending,
      popular: signals.popular,
      airing: signals.airing,
      favorites: new Set(favorites),
      known: tmdb.knownSignals(),
      now: Date.now(),
    });
  }, [items, favorites, generation]);

  return { catalog, items, candidates };
}
