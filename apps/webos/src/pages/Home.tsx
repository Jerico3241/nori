// Die Startseite.
//
// Aufbau wie in den Apple-Apps: Kopfbereich, dann Reihen. Welche Reihen das
// sind und in welcher Reihenfolge, entscheidet `useHomeFeed` — hier wird nur
// gezeichnet. Das ist die eigentliche Änderung gegenüber dem vorherigen Stand,
// der seine Reihen im Rendern bildete und „beliebt" zu den ersten 24 Titeln
// des Katalogs sagte.
//
// Es erscheinen nur Reihen, für die es tatsächlich Daten gibt — eine leere
// „Neue Episoden"-Reihe ist schlechter als keine.

import {
  episodePathFor, progressPercent, providerFromPath, resumePosition,
  type AiringEntry, type CatalogProvider, type HomeCandidate, type SeriesDetail, type WatchProgress,
} from "@nori/core";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { Hero } from "../components/Hero";
import { MediaCard } from "../components/MediaCard";
import { Rail } from "../components/Rail";
import { ScopeTabs } from "../components/ScopeTabs";
import { EmptyState, ErrorState, RailSkeleton } from "../components/States";
import { WideCard } from "../components/WideCard";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { covers } from "../services/covers";
import { log } from "../services/log";
import { tmdb } from "../services/tmdb";
import { useData } from "../state/data";
import { useHomeFeed, type HomeRowView } from "../state/home";
import { useLibrary } from "../state/library";

const ROUTE = "home";

export function HomePage() {
  const navigate = useNavigate();
  const { scopedCatalog, reloadCatalog, series, online } = useData();
  const library = useLibrary();
  const catalog = scopedCatalog();
  const feed = useHomeFeed();

  const [heroIndex, setHeroIndex] = useState(0);
  const [heroDetail, setHeroDetail] = useState<SeriesDetail | null>(null);
  const [heroArt, setHeroArt] = useState<{ backdrop: string | null; logo: string | null }>(
    { backdrop: null, logo: null },
  );

  const hero = feed.hero[Math.min(heroIndex, Math.max(0, feed.hero.length - 1))] ?? null;
  const heroTitle = hero?.title ?? null;

  // Der Kopfbereich braucht mehr als eine Kachel: Beschreibung, Jahr, Genres
  // und die Folgenliste für „Fortsetzen". Das ist ein Abruf, und nur für den
  // einen gezeigten Titel.
  useEffect(() => {
    if (!heroTitle) return;
    let cancelled = false;
    setHeroDetail(null);
    setHeroArt({
      backdrop: covers.backdrop(heroTitle.slug, heroTitle.provider),
      logo: covers.logo(heroTitle.slug, heroTitle.provider),
    });
    series(heroTitle.provider, heroTitle.slug).then(
      (detail) => {
        if (!cancelled) setHeroDetail(detail);
      },
      (cause: unknown) => log("data", "Hero-Detail nicht ladbar", heroTitle.slug, (cause as Error)?.message),
    );

    const request = {
      slug: heroTitle.slug,
      provider: heroTitle.provider,
      title: heroTitle.title,
      alts: heroTitle.alts,
    };
    void covers.ensureBackdrop(request).then((backdrop) => {
      if (!cancelled && backdrop) setHeroArt((current) => ({ ...current, backdrop }));
    });
    // Der Schriftzug kostet einen eigenen Abruf — deshalb nur hier, wo er
    // auch gezeigt wird.
    void covers.ensureLogo(request).then((logo) => {
      if (!cancelled && logo) setHeroArt((current) => ({ ...current, logo }));
    });
    return () => {
      cancelled = true;
    };
  }, [heroTitle, series]);

  useEffect(() => restoreFocusSoon(ROUTE, ["continue", "popular", "hero", "sidebar"]), []);

  const openTitle = useCallback((provider: CatalogProvider, slug: string) => {
    navigate(`/titel/${provider}/${encodeURIComponent(slug)}`);
  }, [navigate]);

  const playEpisode = useCallback((
    provider: CatalogProvider,
    slug: string,
    season: string,
    episode: number,
    path: string,
    at = 0,
  ) => {
    navigate(
      `/player/${provider}/${encodeURIComponent(slug)}`
      + `?season=${encodeURIComponent(season)}&episode=${episode}`
      + `&path=${encodeURIComponent(path)}&at=${Math.floor(at)}`,
    );
  }, [navigate]);

  /** Der Fortschritt, der zum Kopfbereich gehört — für Balken und Knopfschrift. */
  const heroProgress = useMemo<WatchProgress | null>(() => {
    if (!heroTitle) return null;
    const list = library.continueWatching();
    return list.find((item) =>
      item.slug === heroTitle.slug
      && (item.provider ?? providerFromPath(item.episodePath)) === heroTitle.provider) ?? null;
  }, [heroTitle, library]);

  const playHero = useCallback(() => {
    if (!heroTitle) return;
    if (heroProgress) {
      playEpisode(
        heroTitle.provider, heroTitle.slug, heroProgress.season, heroProgress.episode,
        heroProgress.episodePath, library.state.resumeEnabled ? resumePosition(heroProgress) : 0,
      );
      return;
    }
    if (!heroDetail) {
      openTitle(heroTitle.provider, heroTitle.slug);
      return;
    }
    const plan = library.nextPlay(
      heroTitle.slug, heroDetail.activeSeason, heroDetail.episodes, heroTitle.provider,
    );
    const path = heroDetail.episodes.find((episode) => episode.number === plan.episode)?.path
      ?? episodePathFor(heroTitle.provider, heroTitle.slug, heroDetail.activeSeason, plan.episode);
    playEpisode(
      heroTitle.provider, heroTitle.slug, heroDetail.activeSeason, plan.episode, path, plan.resumeAt,
    );
  }, [heroTitle, heroDetail, heroProgress, library, openTitle, playEpisode]);

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
            feed.reload();
          }}
        />
      </div>
    );
  }

  const heroDetails = heroTitle ? covers.details(heroTitle.slug, heroTitle.provider) : null;

  return (
    <div className="page home">
      <ScopeTabs route={ROUTE} />

      {hero && heroTitle ? (
        <Hero
          detail={heroDetail}
          provider={heroTitle.provider}
          slug={heroTitle.slug}
          title={heroDetail?.title ?? heroTitle.title}
          alts={heroTitle.alts}
          backdrop={heroArt.backdrop}
          logo={heroArt.logo}
          overview={heroDetails?.overview}
          rating={heroDetails?.rating ?? null}
          votes={heroDetails?.votes ?? null}
          progress={heroProgress}
          isFavorite={library.isFavorite(heroTitle.slug)}
          onPlay={playHero}
          onDetails={() => openTitle(heroTitle.provider, heroTitle.slug)}
          onToggleFavorite={() => library.toggleFavorite(
            heroTitle.slug, heroDetail?.title ?? heroTitle.title, heroTitle.provider,
          )}
          pages={{ index: heroIndex, total: feed.hero.length, onPick: setHeroIndex }}
        />
      ) : null}

      <div className={`home-rails ${hero ? "" : "no-hero"}`}>
        {catalog.status === "loading" && catalog.items.length === 0 ? (
          <section className="rail">
            <header><h2>Wird geladen …</h2></header>
            <RailSkeleton />
          </section>
        ) : null}

        {feed.rows.map((row) => (
          <HomeRail
            key={row.id}
            row={row}
            onOpenTitle={openTitle}
            onPlayEpisode={playEpisode}
          />
        ))}

        {catalog.status === "ready" && catalog.items.length === 0 ? (
          <EmptyState
            title="Nichts in diesem Bereich"
            message="Für diesen Bereich kamen keine Titel zurück. Ein anderer Bereich oder ein erneuter Versuch hilft meistens."
          />
        ) : null}
      </div>
    </div>
  );
}

function HomeRail({ row, onOpenTitle, onPlayEpisode }: {
  row: HomeRowView;
  onOpenTitle(provider: CatalogProvider, slug: string): void;
  onPlayEpisode(
    provider: CatalogProvider, slug: string, season: string, episode: number, path: string, at?: number,
  ): void;
}) {
  const library = useLibrary();

  if (row.kind === "progress" && row.progress) {
    return (
      <Rail title={row.title} id={row.id} count={row.progress.length} note={row.note}>
        {row.progress.map((item, index) => {
          const provider = item.provider ?? providerFromPath(item.episodePath);
          const season = tmdb.cachedSeason(item.slug, provider, item.season);
          const still = season?.episodes[item.episode]?.still ?? null;
          const remaining = Math.max(0, item.durationSec - item.positionSec);
          return (
            <WideCard
              key={`${provider}|${item.slug}|${item.episode}`}
              slug={item.slug}
              provider={provider}
              title={item.title || item.slug}
              still={still}
              subtitle={`Staffel ${item.season} · Folge ${item.episode}`}
              footnote={remaining > 60
                ? `noch ${Math.round(remaining / 60)} min`
                : item.germanTitle || null}
              percent={progressPercent(item)}
              focusRoute={ROUTE}
              focusArea={row.id}
              focusKey={`${row.id}-${provider}-${item.slug}`}
              eager={index < 4}
              onSelect={() => onPlayEpisode(
                provider, item.slug, item.season, item.episode, item.episodePath,
                library.state.resumeEnabled ? resumePosition(item) : 0,
              )}
            />
          );
        })}
      </Rail>
    );
  }

  if (row.kind === "episodes" && row.episodes) {
    return (
      <Rail title={row.title} id={row.id} count={row.episodes.length} note={row.note}>
        {row.episodes.map((entry, index) => (
          <EpisodeRailCard key={entryKey(entry)} entry={entry} index={index} onOpenTitle={onOpenTitle} />
        ))}
      </Rail>
    );
  }

  if (!row.titles || row.titles.length === 0) return null;

  return (
    <Rail title={row.title} id={row.id} count={row.titles.length} note={row.note}>
      {row.titles.map((candidate, index) => (
        <TitleRailCard key={candidateKey(candidate)} candidate={candidate} area={row.id} index={index} />
      ))}
    </Rail>
  );
}

function EpisodeRailCard({ entry, index, onOpenTitle }: {
  entry: AiringEntry;
  index: number;
  onOpenTitle(provider: CatalogProvider, slug: string): void;
}) {
  const provider = entry.provider ?? "aniworld";
  const season = tmdb.cachedSeason(entry.slug, provider, entry.season);
  const extras = season?.episodes[entry.episode] ?? null;
  return (
    <WideCard
      slug={entry.slug}
      provider={provider}
      title={entry.title}
      still={extras?.still ?? null}
      subtitle={`Staffel ${entry.season} · Folge ${entry.episode}`}
      footnote={extras?.title || (entry.languages.length > 0 ? entry.languages.join(" · ") : null)}
      focusRoute={ROUTE}
      focusArea="episodes"
      focusKey={`episodes-${provider}-${entry.slug}-${entry.episode}`}
      eager={index < 4}
      onSelect={() => onOpenTitle(provider, entry.slug)}
    />
  );
}

function TitleRailCard({ candidate, area, index }: {
  candidate: HomeCandidate;
  area: string;
  index: number;
}) {
  const { title } = candidate;
  const details = covers.details(title.slug, title.provider);
  return (
    <MediaCard
      slug={title.slug}
      title={title.title}
      provider={title.provider}
      alts={title.alts}
      subtitle={title.genres[0] ?? undefined}
      rating={details.rating ?? candidate.signals.voteAverage}
      votes={details.votes ?? candidate.signals.voteCount}
      focusRoute={ROUTE}
      focusArea={area}
      focusKey={`${area}-${title.provider}-${title.slug}`}
      eager={index < 8}
    />
  );
}

function candidateKey(candidate: HomeCandidate): string {
  return `${candidate.title.provider}|${candidate.title.slug}`;
}

function entryKey(entry: AiringEntry): string {
  return `${entry.provider}|${entry.slug}|${entry.season}|${entry.episode}`;
}
