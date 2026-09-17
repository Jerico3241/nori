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

import { batched } from "../services/scheduler";
import { tmdb } from "../services/tmdb";
import { useData } from "./data";
import { useLibrary } from "./library";

/** Die stabile Kennung eines Katalogeintrags — dieselbe wie Key und Fokusschlüssel der Karte. */
export function catalogItemId(item: CatalogItem): string {
  return `${item.provider ?? "aniworld"}|${item.slug}`;
}

export interface DedupedCatalog {
  items: CatalogItem[];
  /**
   * Kennung → Kennung der Vertreterin ihrer Gruppe. Dieselbe Serie aus zwei
   * Quellen landet in derselben Gruppe; welche Fassung sie vertritt, kann sich
   * mit einem TMDB-Treffer ändern.
   */
  representative: Map<string, string>;
}

export function dedupeCatalog(items: CatalogItem[]): CatalogItem[] {
  return dedupeCatalogWithGroups(items).items;
}

export function dedupeCatalogWithGroups(items: CatalogItem[]): DedupedCatalog {
  const out: CatalogItem[] = [];
  const byKey = new Map<string, number>();
  const slotOf = new Map<string, number>();
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
      slotOf.set(catalogItemId(item), out.length);
      out.push(item);
      continue;
    }
    const animated = art?.genreIDs.includes(TMDB_GENRE_ANIMATION) ?? false;
    const preferred = animated ? "aniworld" : "serienstream";
    if ((out[existing].provider ?? "aniworld") !== preferred && provider === preferred) {
      out[existing] = item;
    }
    keys.forEach((key) => byKey.set(key, existing));
    slotOf.set(catalogItemId(item), existing);
  }
  const representative = new Map<string, string>();
  for (const [id, slot] of slotOf) representative.set(id, catalogItemId(out[slot]));
  return { items: out, representative };
}

export function useCatalogView() {
  const { scopedCatalog, tmdbRoute } = useData();
  const library = useLibrary();
  const catalog = scopedCatalog();
  const [generation, setGeneration] = useState(0);

  // TMDB-Treffer gebündelt übernehmen. Jeder einzelne hieße: alle Karten neu
  // bewerten — bei zehntausend Titeln spürbar auf einem Fernseher. Und nicht
  // mitten in einem Tastendruck: `batched` schiebt die Runde auf, solange die
  // Fernbedienung arbeitet.
  useEffect(() => {
    const update = batched(1500, () => setGeneration((value) => value + 1));
    const stop = tmdb.subscribe(() => update.schedule());
    return () => {
      stop();
      update.cancel();
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

  const deduped = useMemo<DedupedCatalog>(() => {
    void generation;
    return library.state.scope === "all"
      ? dedupeCatalogWithGroups(catalog.items)
      : { items: catalog.items, representative: new Map<string, string>() };
  }, [catalog.items, library.state.scope, generation]);
  const items = deduped.items;

  const favorites = library.state.favorites;
  /*
   * Titel und Index hängen am Katalog, nicht an TMDB.
   *
   * Sie standen mit in der Rechnung darunter und entstanden deshalb bei jedem
   * gebündelten TMDB-Treffer neu — bei zehntausend Titeln zehntausend neue
   * Objekte und ein neu aufgebauter Index, alle zwei Sekunden, für eine
   * Zuordnung, die sich nicht geändert hat.
   */
  const titles = useMemo(() => items.map((item) => homeTitleFrom(item)), [items]);
  const index = useMemo(() => new HomeCatalogIndex(titles), [titles]);

  const candidates = useMemo<HomeCandidate[]>(() => {
    void generation;
    const signals = tmdb.cachedSignals();
    return buildCandidates({
      catalog: titles,
      index,
      trending: signals.trending,
      popular: signals.popular,
      airing: signals.airing,
      favorites: new Set(favorites),
      known: tmdb.knownSignals(),
      now: Date.now(),
    });
  }, [titles, index, favorites, generation]);

  return { catalog, items, candidates, representative: deduped.representative };
}
