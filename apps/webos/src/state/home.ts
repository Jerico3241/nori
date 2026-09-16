// Was auf der Startseite steht.
//
// ## Warum das nicht in der Ansicht steht
//
// Die vorherige Startseite bildete ihre Reihen im Rendern:
//
//     const trending = catalog.items.slice(0, 24);
//     const recentlyAdded = catalog.items.slice(24, 48);
//
// Das ist keine Reihenfolge, sondern eine Behauptung. „Beliebt" waren die
// ersten 24 Titel des Katalogs — bei AniWorld also die, deren Name mit „A"
// beginnt. Die Reihe hieß, was sie nicht war.
//
// Hier entsteht sie stattdessen aus Signalen, und die Rechnung dazu liegt im
// gemeinsamen Kern (`@nori/core/tmdb/ranking`), wo die Apple-Apps dieselbe
// benutzen und ein Test sie prüfen kann. Dieser Haken macht nur zwei Dinge:
// die Signale beschaffen und das Ergebnis in Reihen gießen.
//
// ## Die Aufgabenteilung
//
//     Nori-Provider  →  Was gibt es überhaupt?
//     TMDB           →  Was ist das, wie aktuell, wie beliebt?
//     Bibliothek     →  Was davon betrifft mich?
//
// Jede Reihe beginnt beim Nori-Katalog. Es gibt bewusst keinen Weg, aus einer
// TMDB-Zeile eine Kachel zu machen — sonst stünde dort etwas, das sich
// auswählen lässt und nichts öffnet.
//
// ## Ohne TMDB
//
// Dann bleiben die Signale leer, und „Neu & beliebt" hätte nichts zu zeigen.
// Statt die Reihe mit Katalogteilen zu füllen und weiter „beliebt" zu nennen,
// erscheint eine andere: „Neu im Katalog", gefüllt mit der Reihenfolge der
// Quelle — beide Seiten führen Neues vorn. Das ist ein echtes, wenn auch
// schwaches Signal, und die Überschrift sagt genau das.

import {
  HomeCatalogIndex, buildCandidates, heroPicks, homeTitleFrom, homeTitleId, newAndPopular,
  profileIsMeaningful, recentEpisodes, recommend, tasteProfile, topRated, watchRatio,
  type AiringEntry, type CatalogItem, type CatalogProvider, type HomeCandidate,
  type HomeTitle, type WatchProgress,
} from "@nori/core";
import { useEffect, useMemo, useRef, useState } from "react";

import { log } from "../services/log";
import { batched, whenIdle } from "../services/scheduler";
import { tmdb } from "../services/tmdb";
import { useData } from "./data";
import { useLibrary } from "./library";

/** Wie eine Reihe gezeichnet wird. */
export type HomeRowKind = "progress" | "titles" | "episodes";

export interface HomeRowView {
  id: string;
  title: string;
  kind: HomeRowKind;
  /** Eine Zeile, die die Überschrift begründet. Nur wo sie etwas erklärt. */
  note?: string;
  titles?: HomeCandidate[];
  episodes?: AiringEntry[];
  progress?: WatchProgress[];
}

export interface HomeFeedView {
  hero: HomeCandidate[];
  rows: HomeRowView[];
  /** Ob TMDB gerade Signale liefert — die Einstellungen und der Hinweistext. */
  hasSignals: boolean;
  /** Läuft noch ein TMDB-Abruf im Hintergrund? */
  enriching: boolean;
  reload(): void;
}

/** Wie viele Seed-Titel nach Empfehlungen gefragt werden. Je Seed ein Abruf. */
const MAX_SEEDS = 3;
/** Wie viele Titel je Reihe bei TMDB aufgelöst werden. Siehe `askedFor`. */
const RESOLVE_PER_ROW = 12;
const HERO_COUNT = 5;

/**
 * Die Startseite zusammenstellen.
 *
 * Zwei Durchgänge, und das ist Absicht: Der erste rechnet mit dem, was schon
 * abgelegt ist — die Seite steht damit sofort, mit dem Stand von vorhin. Der
 * zweite holt frische Listen und ersetzt sie. Ein Ladebalken auf der
 * Startseite wäre der schlechtere Tausch: TMDB braucht dafür Sekunden, und
 * ohne TMDB käme er nie weg.
 */
export function useHomeFeed(): HomeFeedView {
  const { scopedCatalog, calendar, tmdbRoute } = useData();
  const library = useLibrary();
  const catalog = scopedCatalog();
  const scope = library.state.scope;

  const [airing, setAiring] = useState<AiringEntry[]>([]);
  /** Hochgezählt, sobald TMDB etwas Neues hat — stößt die Rechnung neu an. */
  const [generation, setGeneration] = useState(0);
  const [enriching, setEnriching] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);
  const enrichedFor = useRef("");

  // Kalender liefert „Neue Folgen"; scheitert er, fällt nur diese Reihe weg.
  useEffect(() => {
    let cancelled = false;
    const providers: CatalogProvider[] = scope === "aniworld"
      ? ["aniworld"]
      : scope === "all"
        ? ["aniworld", "serienstream"]
        : ["serienstream"];
    Promise.allSettled(providers.map((provider) => calendar(provider))).then((results) => {
      if (cancelled) return;
      const entries = results.flatMap((result) =>
        (result.status === "fulfilled" ? result.value.recent : []));
      setAiring(entries);
    });
    return () => {
      cancelled = true;
    };
  }, [calendar, scope, reloadToken]);

  /**
   * Ein TMDB-Treffer, der später eintrifft, muss die Reihenfolge erreichen —
   * aber nicht jeder einzeln.
   *
   * Beim ersten Aufbau trifft im Sekundentakt einer ein, und jeder davon
   * bedeutet: alle Kandidaten neu bauen, alle Reihen neu ranken. Bei einem
   * Katalog mit zehntausend Titeln ist das je Treffer ein neues Feld mit
   * zehntausend Objekten. Auf einem Fernseher ist das der Unterschied zwischen
   * einer Seite, die sich bedienen lässt, und einer, die stockt.
   *
   * Deshalb gebündelt: höchstens alle 900 ms, und nie mitten in einem
   * Tastendruck — `batched` schiebt die Runde auf, solange die Fernbedienung
   * arbeitet, und holt sie nach, sobald sie ruht. Die Kacheln selbst bekommen
   * ihre Bilder unabhängig davon sofort; die hängen am Bildindex, nicht hier.
   */
  useEffect(() => {
    const update = batched(900, () => setGeneration((value) => value + 1));
    const stop = tmdb.subscribe(() => update.schedule());
    return () => {
      stop();
      update.cancel();
    };
  }, []);

  const titles = useMemo<HomeTitle[]>(
    () => catalog.items.map((item: CatalogItem) => homeTitleFrom(item)),
    [catalog.items],
  );

  const index = useMemo(() => new HomeCatalogIndex(titles), [titles]);

  // Ranglisten und Empfehlungen nachladen — einmal je Katalogstand, nicht bei
  // jedem Rendern.
  useEffect(() => {
    if (titles.length === 0) return;
    const stamp = `${tmdbRoute.effective}|${titles.length}|${reloadToken}`;
    if (enrichedFor.current === stamp) return;
    enrichedFor.current = stamp;
    if (!tmdb.available) return;

    let cancelled = false;
    setEnriching(true);
    void tmdb.ensureFeeds(reloadToken > 0).then(() => {
      if (cancelled) return;
      setGeneration((value) => value + 1);
    }).finally(() => {
      if (!cancelled) setEnriching(false);
    });
    return () => {
      cancelled = true;
    };
  }, [titles.length, tmdbRoute.effective, reloadToken]);

  const profile = useMemo(() => {
    void generation;
    return tasteProfile({
      progress: Object.values(library.state.progress),
      favorites: library.state.favorites,
      favoriteSource: library.state.favoriteSource,
      catalog: titles,
      signals: tmdb.knownSignals(),
      now: Date.now(),
    });
  }, [titles, library.state.progress, library.state.favorites, library.state.favoriteSource, generation]);

  /**
   * Empfehlungen zu den meistgesehenen Titeln nachladen.
   *
   * Je Seed ein Abruf — deshalb wenige. Ohne diesen Schritt bliebe „Für dich"
   * eine reine Genreüberschneidung; mit ihm kennt die Reihe Zusammenhänge, die
   * kein Genre abbildet (dieselben Macher, dieselbe Vorlage).
   */
  const seedKey = profile.seeds.slice(0, MAX_SEEDS).join(",");
  useEffect(() => {
    if (!tmdb.available || !seedKey) return;
    let cancelled = false;
    const seeds = seedKey.split(",").map(Number).filter(Number.isFinite);
    Promise.allSettled(seeds.map((seed) => tmdb.ensureRelated(seed))).then(() => {
      if (!cancelled) setGeneration((value) => value + 1);
    });
    return () => {
      cancelled = true;
    };
  }, [seedKey]);

  const feed = useMemo<Omit<HomeFeedView, "reload">>(() => {
    // `generation` wird gelesen, damit die Rechnung nach einem TMDB-Treffer
    // erneut läuft. Ohne diese Zeile hielte React das Ergebnis für unverändert.
    void generation;

    const signals = tmdb.cachedSignals();
    const known = tmdb.knownSignals();
    const progressList = Object.values(library.state.progress);

    const watched = new Map<string, number>();
    for (const item of progressList) {
      const id = `${item.provider ?? "aniworld"}|${item.slug}`;
      watched.set(id, Math.max(watched.get(id) ?? 0, watchRatio(item)));
    }

    const now = Date.now();
    const freshEpisodes = new Set<string>();
    for (const entry of airing) {
      if (now - entry.airingAt > 7 * 86_400_000) continue;
      freshEpisodes.add(`${entry.provider ?? "aniworld"}|${entry.slug}`);
    }

    const candidates = buildCandidates({
      catalog: titles,
      index,
      trending: signals.trending,
      popular: signals.popular,
      airing: signals.airing,
      watched,
      favorites: new Set(library.state.favorites),
      freshEpisodes,
      known,
      now,
    });

    const byId = new Map(candidates.map((candidate) => [homeTitleId(candidate.title), candidate]));
    const hasSignals = candidates.some((candidate) => candidate.signals.tmdbID !== null);

    // Der Tag als Anker für die Rotation des Kopfbereichs: innerhalb eines
    // Tages stabil, am nächsten ein anderer Titel.
    const day = Math.floor(now / 86_400_000);
    const hero = heroPicks(candidates, now, day, { limit: HERO_COUNT });
    const shown = new Set(hero.map((candidate) => homeTitleId(candidate.title)));

    const rows: HomeRowView[] = [];

    const continueList = library.continueWatching();
    if (continueList.length > 0) {
      rows.push({ id: "continue", title: "Weiterschauen", kind: "progress", progress: continueList });
      for (const item of continueList) {
        shown.add(`${item.provider ?? "aniworld"}|${item.slug}`);
      }
    }

    const popular = newAndPopular(candidates, now, { excluding: shown, limit: 20 });
    if (popular.length > 0) {
      rows.push({ id: "popular", title: "Neu & beliebt", kind: "titles", titles: popular });
      for (const candidate of popular) shown.add(homeTitleId(candidate.title));
    } else if (candidates.length > 0) {
      // Ohne TMDB-Signale gibt es keine Beliebtheit. Die Reihenfolge der
      // Quelle ist eine schwächere Auskunft — und die Überschrift sagt es.
      const fresh = candidates
        .filter((candidate) => !shown.has(homeTitleId(candidate.title)))
        .slice(0, 20);
      if (fresh.length > 0) {
        rows.push({
          id: "fresh",
          title: "Neu im Katalog",
          kind: "titles",
          note: tmdb.available
            ? "Reihenfolge der Quelle — TMDB hat zu diesem Bereich noch keine Angaben."
            : "Reihenfolge der Quelle. Mit TMDB entsteht daraus „Neu & beliebt“.",
          titles: fresh,
        });
        for (const candidate of fresh) shown.add(homeTitleId(candidate.title));
      }
    }

    const availableIds = new Set(titles.map(homeTitleId));
    const episodes = recentEpisodes(airing, now, { availableIds, limit: 12 });
    if (episodes.length > 0) {
      rows.push({ id: "episodes", title: "Neue Episoden", kind: "episodes", episodes });
    }

    const recommended = new Map<number, number>();
    for (const seed of profile.seeds.slice(0, MAX_SEEDS)) {
      for (const row of tmdb.cachedRelated(seed)) {
        recommended.set(row.id, (recommended.get(row.id) ?? 0) + 1);
      }
    }

    if (profileIsMeaningful(profile)) {
      const picks = recommend(candidates, profile, { recommended, excluding: shown, limit: 20 });
      if (picks.length > 0) {
        rows.push({
          id: "foryou",
          title: "Für dich",
          kind: "titles",
          note: recommended.size > 0
            ? "Aus deinem Verlauf und Titeln, die TMDB dazu nennt."
            : "Aus deinem Verlauf und deiner Merkliste.",
          titles: picks,
        });
        for (const candidate of picks) shown.add(homeTitleId(candidate.title));
      }
    } else if (hasSignals) {
      // Zu wenig Verlauf für eine Empfehlung. Dann heißt die Reihe auch nicht
      // „Für dich" — sie wäre eine zweite Beliebtheitsliste mit falschem Namen.
      const picks = topRated(candidates, { excluding: shown, minimumVotes: 200, limit: 20 });
      if (picks.length > 0) {
        rows.push({
          id: "discover",
          title: "Entdecke etwas Neues",
          kind: "titles",
          note: "Bestbewertete Titel bei TMDB. „Für dich“ erscheint, sobald Nori deinen Verlauf kennt.",
          titles: picks,
        });
        for (const candidate of picks) shown.add(homeTitleId(candidate.title));
      }
    }

    const watchlist = library.state.favorites
      .map((slug) => byId.get(`${library.favoriteProvider(slug)}|${slug}`)
        ?? fallbackCandidate(slug, library.state.titles[slug] ?? slug, library.favoriteProvider(slug)))
      .slice(0, 20);
    if (watchlist.length > 0) {
      rows.push({ id: "watchlist", title: "Merkliste", kind: "titles", titles: watchlist });
    }

    return { hero, rows, hasSignals, enriching };
  }, [titles, index, airing, library, profile, generation, enriching]);

  /**
   * Die Titel, die auf der Startseite stehen, bei TMDB nachschlagen.
   *
   * Das hing vorher an den Kacheln: jede Titelreihe lud ihre ersten sieben
   * Bilder sofort, und **weil** sie das tat, wurden dieselben sieben Titel bei
   * TMDB aufgelöst — und erst dadurch konnten sie in der Rangfolge steigen.
   * Ein Nebeneffekt des Bildladens hielt die Startseite zusammen.
   *
   * Seit Bilder erst beim Hinsehen geladen werden, trägt dieser Nebeneffekt
   * nicht mehr. Deshalb steht die Nachfrage jetzt dort, wo sie hingehört: bei
   * dem, was die Reihenfolge braucht. Sie läuft in Leerlaufpausen, fragt jeden
   * Titel höchstens einmal je Sitzung und rührt kein Bild an.
   */
  const askedFor = useRef(new Set<string>());
  useEffect(() => {
    if (!tmdb.available) return undefined;
    const wanted: HomeTitle[] = [
      ...feed.hero.map((candidate) => candidate.title),
      ...feed.rows.flatMap((row) => (row.titles ?? []).slice(0, RESOLVE_PER_ROW).map((c) => c.title)),
    ];
    const fresh = wanted.filter((title) => !askedFor.current.has(homeTitleId(title)));
    if (fresh.length === 0) return undefined;
    for (const title of fresh) askedFor.current.add(homeTitleId(title));
    // Ausdrücklich **ohne** Abbruch beim nächsten Durchgang: die Reihen ändern
    // sich mit jedem eintreffenden Treffer, und ein Aufräumen würde genau die
    // Nachfrage abbrechen, die den nächsten Treffer bringt. Die Arbeit ist
    // klein, einmalig je Titel und in sich abgeschlossen.
    whenIdle(() => {
      for (const title of fresh) {
        void tmdb.ensureArt({
          slug: title.slug,
          title: title.title,
          alternates: title.alts,
          provider: title.provider,
          expectedYear: null,
        }).catch(() => null);
      }
    }, 500);
    return undefined;
  }, [feed.hero, feed.rows]);

  useEffect(() => {
    log("data", "Startseite", feed.rows.map((row) => `${row.title}:${rowSize(row)}`).join(" "));
  }, [feed.rows]);

  return {
    ...feed,
    reload: () => setReloadToken((value) => value + 1),
  };
}

function rowSize(row: HomeRowView): number {
  return row.titles?.length ?? row.episodes?.length ?? row.progress?.length ?? 0;
}

/**
 * Ein Kandidat für einen gemerkten Titel, der nicht im geladenen Katalog steht.
 *
 * Kommt vor: die Merkliste kommt aus der Bibliothek und kennt auch Titel aus
 * einem Bereich, der gerade nicht geladen ist. Die Kachel soll trotzdem
 * erscheinen — gemerkt ist gemerkt.
 */
function fallbackCandidate(slug: string, title: string, provider: CatalogProvider): HomeCandidate {
  return {
    title: { slug, title, provider, genres: [], alts: [] },
    signals: {
      tmdbID: null,
      popularity: null,
      voteAverage: null,
      voteCount: null,
      firstAirDate: null,
      lastAirDate: null,
      trendingRank: null,
      genreIDs: [],
      hasBackdrop: false,
    },
    watchedRatio: 0,
    inWatchlist: true,
    hasFreshEpisode: false,
  };
}
