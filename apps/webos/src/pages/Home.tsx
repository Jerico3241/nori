// Die Startseite.
//
// Aufbau wie eine Streaming-App: Hero, dann Reihen. Es erscheinen nur Reihen,
// für die es tatsächlich Daten gibt — eine leere „Neue Folgen"-Reihe ist
// schlechter als keine.

import {
  PROVIDERS, episodePathFor, providerFromPath,
  type AiringEntry, type CatalogItem, type CatalogProvider, type SeriesDetail,
} from "@nori/core";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { Hero } from "../components/Hero";
import { MediaCard } from "../components/MediaCard";
import { Rail } from "../components/Rail";
import { EmptyState, ErrorState, RailSkeleton } from "../components/States";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { covers } from "../services/covers";
import { log } from "../services/log";
import { useData } from "../state/data";
import { useLibrary } from "../state/library";
import { ScopeTabs } from "../components/ScopeTabs";

const ROUTE = "home";
const HERO_COUNT = 5;

export function HomePage() {
  const navigate = useNavigate();
  const { scopedCatalog, reloadCatalog, series, calendar, online } = useData();
  const library = useLibrary();
  const catalog = scopedCatalog();

  const [heroIndex, setHeroIndex] = useState(0);
  const [heroDetail, setHeroDetail] = useState<SeriesDetail | null>(null);
  const [heroBackdrop, setHeroBackdrop] = useState<string | null>(null);
  const [airing, setAiring] = useState<AiringEntry[]>([]);

  const continueList = useMemo(() => library.continueWatching(), [library]);

  /**
   * Die Hero-Kandidaten.
   *
   * Zuerst das Angefangene — wer die App öffnet, will meist weiterschauen.
   * Danach Titel von der Merkliste, dann der Katalog. Die Auswahl ist an den
   * Tag gebunden, damit der Hero nicht bei jedem Rendern springt.
   */
  const heroItems = useMemo(() => {
    const out: { slug: string; title: string; provider: CatalogProvider }[] = [];
    const seen = new Set<string>();
    const push = (slug: string, title: string, provider: CatalogProvider) => {
      const key = `${provider}|${slug}`;
      if (seen.has(key) || out.length >= HERO_COUNT) return;
      seen.add(key);
      out.push({ slug, title, provider });
    };
    for (const item of continueList) {
      push(item.slug, item.title || item.slug, item.provider ?? providerFromPath(item.episodePath));
    }
    for (const slug of library.state.favorites) {
      push(slug, library.state.titles[slug] ?? slug, library.favoriteProvider(slug));
    }
    if (catalog.items.length > 0) {
      const day = Math.floor(Date.now() / 86_400_000);
      for (let i = 0; out.length < HERO_COUNT && i < HERO_COUNT * 4; i += 1) {
        const item = catalog.items[(day * 31 + i * 977) % catalog.items.length];
        if (item?.provider) push(item.slug, item.title, item.provider);
      }
    }
    return out;
  }, [continueList, library, catalog.items]);

  const hero = heroItems[Math.min(heroIndex, Math.max(0, heroItems.length - 1))] ?? null;

  useEffect(() => {
    if (!hero) return;
    let cancelled = false;
    setHeroDetail(null);
    setHeroBackdrop(covers.backdrop(hero.slug, hero.provider));
    series(hero.provider, hero.slug).then(
      (detail) => {
        if (!cancelled) setHeroDetail(detail);
      },
      (cause: unknown) => log("data", "Hero-Detail nicht ladbar", hero.slug, (cause as Error)?.message),
    );
    void covers.ensureBackdrop(hero.slug, hero.title, hero.provider).then((url) => {
      if (!cancelled && url) setHeroBackdrop(url);
    });
    return () => {
      cancelled = true;
    };
  }, [hero, series]);

  // Kalender liefert „Neue Folgen"; scheitert er, fällt nur diese Reihe weg.
  useEffect(() => {
    let cancelled = false;
    const providers: CatalogProvider[] = library.state.scope === "aniworld"
      ? ["aniworld"]
      : library.state.scope === "all"
        ? ["aniworld", "serienstream"]
        : ["serienstream"];
    Promise.allSettled(providers.map((provider) => calendar(provider))).then((results) => {
      if (cancelled) return;
      const entries = results.flatMap((result) =>
        result.status === "fulfilled" ? result.value.recent : []);
      setAiring(entries.sort((a, b) => b.airingAt - a.airingAt).slice(0, 20));
    });
    return () => {
      cancelled = true;
    };
  }, [calendar, library.state.scope]);

  useEffect(() => restoreFocusSoon(ROUTE, ["continue", "trending", "hero", "sidebar"]), []);

  const openTitle = useCallback((provider: CatalogProvider, slug: string) => {
    navigate(`/titel/${provider}/${encodeURIComponent(slug)}`);
  }, [navigate]);

  const playHero = useCallback(() => {
    if (!hero) return;
    const detail = heroDetail;
    if (!detail) {
      openTitle(hero.provider, hero.slug);
      return;
    }
    const plan = library.nextPlay(hero.slug, detail.activeSeason, detail.episodes, hero.provider);
    const path = detail.episodes.find((ep) => ep.number === plan.episode)?.path
      ?? episodePathFor(hero.provider, hero.slug, detail.activeSeason, plan.episode);
    navigate(
      `/player/${hero.provider}/${encodeURIComponent(hero.slug)}`
      + `?season=${encodeURIComponent(detail.activeSeason)}&episode=${plan.episode}`
      + `&path=${encodeURIComponent(path)}&at=${Math.floor(plan.resumeAt)}`,
    );
  }, [hero, heroDetail, library, navigate, openTitle]);

  if (catalog.status === "error" && catalog.items.length === 0) {
    return (
      <div className="page">
        <ScopeTabs route={ROUTE} />
        <ErrorState
          title={online ? "Katalog nicht ladbar" : "Keine Verbindung"}
          message={catalog.error ?? "Nori konnte keine Verbindung zum Server herstellen."}
          onRetry={() => {
            reloadCatalog("aniworld");
            reloadCatalog("serienstream");
          }}
        />
      </div>
    );
  }

  const trending = catalog.items.slice(0, 24);
  const recentlyAdded = catalog.items.slice(24, 48);
  const watchlist = library.state.favorites.slice(0, 20);

  return (
    <div className="page home">
      <ScopeTabs route={ROUTE} />
      {hero ? (
        <Hero
          detail={heroDetail}
          provider={hero.provider}
          slug={hero.slug}
          title={heroDetail?.title ?? hero.title}
          backdrop={heroBackdrop}
          progress={library.progressFor(
            heroDetail?.episodes[0]?.path ?? "", hero.provider,
          ) ?? continueList.find((item) => item.slug === hero.slug) ?? null}
          isFavorite={library.isFavorite(hero.slug)}
          onPlay={playHero}
          onDetails={() => openTitle(hero.provider, hero.slug)}
          onToggleFavorite={() =>
            library.toggleFavorite(hero.slug, heroDetail?.title ?? hero.title, hero.provider)}
          pages={{
            index: heroIndex,
            total: heroItems.length,
            onPick: setHeroIndex,
          }}
        />
      ) : null}

      <div className="home-rails">
        {continueList.length > 0 ? (
          <Rail title="Weiterschauen" id="rail-continue" count={continueList.length}>
            {continueList.map((item, index) => {
              const provider = item.provider ?? providerFromPath(item.episodePath);
              return (
                <MediaCard
                  key={`${provider}|${item.slug}|${item.episode}`}
                  slug={item.slug}
                  title={item.title || item.slug}
                  provider={provider}
                  progress={item}
                  badge={`S${item.season} · F${item.episode}`}
                  subtitle={item.germanTitle || undefined}
                  focusRoute={ROUTE}
                  focusArea="continue"
                  focusKey={`continue-${provider}-${item.slug}`}
                  eager={index < 8}
                  onSelect={() => navigate(
                    `/player/${provider}/${encodeURIComponent(item.slug)}`
                    + `?season=${encodeURIComponent(item.season)}&episode=${item.episode}`
                    + `&path=${encodeURIComponent(item.episodePath)}`,
                  )}
                />
              );
            })}
          </Rail>
        ) : null}

        {catalog.status === "loading" && catalog.items.length === 0 ? (
          <section className="rail">
            <header><h2>Beliebt</h2></header>
            <RailSkeleton />
          </section>
        ) : null}

        {trending.length > 0 ? (
          <Rail title="Beliebt" id="rail-trending" count={catalog.items.length}>
            {trending.map((item, index) => (
              <CatalogCard key={`${item.provider}|${item.slug}`} item={item} area="trending" index={index} />
            ))}
          </Rail>
        ) : null}

        {airing.length > 0 ? (
          <Rail title="Neue Folgen" id="rail-airing" count={airing.length}>
            {airing.map((entry) => (
              <MediaCard
                key={`${entry.provider}|${entry.slug}|${entry.season}|${entry.episode}`}
                slug={entry.slug}
                title={entry.title}
                provider={entry.provider ?? "aniworld"}
                coverPath={entry.coverPath}
                badge={`S${entry.season} · F${entry.episode}`}
                subtitle={entry.languages.join(" · ") || undefined}
                focusRoute={ROUTE}
                focusArea="airing"
                focusKey={`airing-${entry.slug}-${entry.episode}`}
              />
            ))}
          </Rail>
        ) : null}

        {recentlyAdded.length > 0 ? (
          <Rail title="Zuletzt aufgenommen" id="rail-new">
            {recentlyAdded.map((item, index) => (
              <CatalogCard key={`${item.provider}|${item.slug}`} item={item} area="new" index={index} />
            ))}
          </Rail>
        ) : null}

        {watchlist.length > 0 ? (
          <Rail title="Merkliste" id="rail-watchlist" count={library.state.favorites.length}>
            {watchlist.map((slug) => (
              <MediaCard
                key={slug}
                slug={slug}
                title={library.state.titles[slug] ?? slug}
                provider={library.favoriteProvider(slug)}
                focusRoute={ROUTE}
                focusArea="watchlist"
                focusKey={`watchlist-${slug}`}
              />
            ))}
          </Rail>
        ) : null}

        {catalog.status === "ready" && catalog.items.length === 0 ? (
          <EmptyState
            title="Nichts in diesem Bereich"
            message={`Für „${PROVIDERS[library.state.provider].label}" kamen keine Titel zurück. Ein anderer Bereich oder ein erneuter Versuch hilft meistens.`}
          />
        ) : null}
      </div>
    </div>
  );
}

function CatalogCard({ item, area, index }: { item: CatalogItem; area: string; index: number }) {
  return (
    <MediaCard
      slug={item.slug}
      title={item.title}
      provider={item.provider ?? "aniworld"}
      subtitle={item.genres[0] ?? undefined}
      focusRoute={ROUTE}
      focusArea={area}
      focusKey={`${area}-${item.provider}-${item.slug}`}
      eager={index < 8}
    />
  );
}
