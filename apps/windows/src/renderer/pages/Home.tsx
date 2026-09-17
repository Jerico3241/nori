// Die Startseite.
//
//     Kopfbereich    ein Titel aus dem Nori-Katalog, gewählt über TMDB-Signale
//     Weiterschauen  breite Karten aus dem echten Fortschritt
//     Neu & beliebt  TMDB-Trend und -Beliebtheit, begrenzt auf Noris Bestand
//     Neue Episoden  aus dem Kalender der Quellen
//     Für dich       aus Verlauf und Merkliste, mit TMDB-Empfehlungen
//     Merkliste
//
// Welche Reihen es gibt, entscheidet `useHomeFeed` aus der gemeinsamen
// Anwendungsschicht — dieselbe Rangfolge wie auf dem Fernseher, damit Nori auf
// beiden Geräten dasselbe empfiehlt. Hier wird nur gezeichnet.

import {
  Icon, covers, performanceProfile, ratingText, titleMeta, tmdb, useData, useHomeFeed, useLibrary,
  type HomeRowView,
} from "@nori/app";
import {
  episodePathFor, progressPercent, providerFromPath, resumePosition,
  type CatalogProvider, type HomeTitle, type SeriesDetail, type WatchProgress,
} from "@nori/core";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import {
  EmptyState, ErrorState, Hero, LandscapeCard, PosterCard, Rail, RailSkeleton,
} from "../components/ui";

export function HomePage() {
  const navigate = useNavigate();
  const { scopedCatalog, reloadCatalog, series, online } = useData();
  const library = useLibrary();
  const catalog = scopedCatalog();
  const feed = useHomeFeed();
  const [heroDetail, setHeroDetail] = useState<SeriesDetail | null>(null);
  const [, setArtVersion] = useState(0);

  const heroTitle = useMemo<HomeTitle | null>(() => {
    if (feed.hero[0]) return feed.hero[0].title;
    const recent = library.continueWatching()[0];
    if (recent) {
      const provider = recent.provider ?? providerFromPath(recent.episodePath);
      const match = catalog.items.find((item) =>
        item.slug === recent.slug && (item.provider ?? "aniworld") === provider);
      return {
        slug: recent.slug,
        title: match?.title ?? (recent.title || recent.slug),
        provider,
        genres: match?.genres ?? [],
        alts: match?.alts ?? [],
      };
    }
    const first = catalog.items[0];
    return first
      ? { slug: first.slug, title: first.title, provider: first.provider ?? "aniworld", genres: first.genres, alts: first.alts }
      : null;
  }, [feed.hero, library, catalog.items]);
  const heroKey = heroTitle ? `${heroTitle.provider}|${heroTitle.slug}` : "";

  useEffect(() => {
    if (!heroTitle) return undefined;
    let cancelled = false;
    setHeroDetail(null);
    series(heroTitle.provider, heroTitle.slug).then(
      (detail) => {
        if (!cancelled) setHeroDetail(detail);
      },
      () => undefined,
    );
    const request = { slug: heroTitle.slug, provider: heroTitle.provider, title: heroTitle.title, alts: heroTitle.alts };
    void covers.ensureBackdrop(request).then(() => {
      if (!cancelled) setArtVersion((value) => value + 1);
    });
    void covers.ensureLogo(request).then(() => {
      if (!cancelled) setArtVersion((value) => value + 1);
    });
    return () => {
      cancelled = true;
    };
    // Nur am Titel hängend: `heroTitle` ist bei jedem Fortschrittstick ein neues Objekt.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [heroKey, series]);

  const openTitle = useCallback((provider: CatalogProvider, slug: string) => {
    navigate(`/titel/${provider}/${encodeURIComponent(slug)}`);
  }, [navigate]);

  const playEpisode = useCallback((
    provider: CatalogProvider, slug: string, season: string, episode: number, path: string, at = 0,
  ) => {
    navigate(
      `/player/${provider}/${encodeURIComponent(slug)}`
      + `?season=${encodeURIComponent(season)}&episode=${episode}`
      + `&path=${encodeURIComponent(path)}&at=${Math.floor(at)}`,
    );
  }, [navigate]);

  const heroProgress = useMemo<WatchProgress | null>(() => {
    if (!heroTitle) return null;
    return library.continueWatching().find((item) =>
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
    const plan = library.nextPlay(heroTitle.slug, heroDetail.activeSeason, heroDetail.episodes, heroTitle.provider);
    const path = heroDetail.episodes.find((episode) => episode.number === plan.episode)?.path
      ?? episodePathFor(heroTitle.provider, heroTitle.slug, heroDetail.activeSeason, plan.episode);
    playEpisode(heroTitle.provider, heroTitle.slug, heroDetail.activeSeason, plan.episode, path, plan.resumeAt);
  }, [heroTitle, heroDetail, heroProgress, library, openTitle, playEpisode]);

  if (catalog.status === "error" && catalog.items.length === 0) {
    return (
      <div className="page">
        <ErrorState
          title={online ? "Katalog nicht ladbar" : "Keine Verbindung"}
          message={catalog.error ?? "Nori konnte keine Verbindung herstellen."}
          onRetry={() => {
            reloadCatalog("aniworld");
            reloadCatalog("serienstream");
            feed.reload();
          }}
        />
      </div>
    );
  }

  const art = heroTitle ? covers.details(heroTitle.slug, heroTitle.provider) : null;
  const favorite = heroTitle ? library.isFavorite(heroTitle.slug) : false;
  const years = heroDetail?.yearStart
    ? (heroDetail.yearEnd && heroDetail.yearEnd !== heroDetail.yearStart
      ? `${heroDetail.yearStart}–${heroDetail.yearEnd}`
      : heroDetail.yearStart)
    : null;
  const genres = (heroDetail?.genres.length ? heroDetail.genres : heroTitle?.genres ?? []).slice(0, 3);
  const rating = ratingText(art?.rating ?? null, art?.votes ?? null);
  const heroPercent = heroProgress ? progressPercent(heroProgress) : 0;

  return (
    <>
      {heroTitle ? (
        <Hero
          slug={heroTitle.slug}
          provider={heroTitle.provider}
          title={heroDetail?.title ?? heroTitle.title}
          alts={heroTitle.alts}
          eyebrow={heroProgress ? "Weiterschauen" : "Heute im Fokus"}
          backdrop={art?.backdrop ?? null}
          logo={art?.logo ?? null}
          meta={(
            <>
              {[years, ...genres].filter(Boolean).join(" · ")}
              {rating ? <span className="star">{genres.length || years ? " · " : ""}★ {rating}</span> : null}
            </>
          )}
          description={heroDetail?.description || art?.overview || ""}
          progress={heroProgress ? {
            percent: heroPercent,
            label: `Staffel ${heroProgress.season} · Folge ${heroProgress.episode} · ${heroPercent} % gesehen`,
          } : null}
          actions={(
            <>
              <button type="button" className="btn primary" onClick={playHero}>
                <Icon name="play" /><span>{heroProgress ? "Weiter ansehen" : "Jetzt ansehen"}</span>
              </button>
              <button
                type="button"
                className="btn"
                aria-pressed={favorite}
                onClick={() => library.toggleFavorite(heroTitle.slug, heroDetail?.title ?? heroTitle.title, heroTitle.provider)}
              >
                <Icon name={favorite ? "heartFilled" : "heart"} /><span>{favorite ? "Gemerkt" : "Merkliste"}</span>
              </button>
              <button type="button" className="btn" onClick={() => openTitle(heroTitle.provider, heroTitle.slug)}>
                <Icon name="info" /><span>Mehr</span>
              </button>
            </>
          )}
        />
      ) : null}

      <div className="page wide">
        {catalog.status === "loading" && catalog.items.length === 0 ? (
          <section className="section">
            <div className="section-head"><h2>Wird geladen …</h2></div>
            <RailSkeleton />
          </section>
        ) : null}

        {feed.rows.map((row, index) => (
          <HomeRail
            key={row.id}
            row={row}
            first={index === 0}
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
    </>
  );
}

function HomeRail({ row, first, onOpenTitle, onPlayEpisode }: {
  row: HomeRowView;
  first: boolean;
  onOpenTitle(provider: CatalogProvider, slug: string): void;
  onPlayEpisode(provider: CatalogProvider, slug: string, season: string, episode: number, path: string, at?: number): void;
}) {
  const library = useLibrary();
  // Nur die oberste Reihe lädt ihre ersten Bilder ohne Umweg über den
  // Sichtbarkeitsbeobachter — alles andere kommt, wenn es ins Bild kommt.
  const eagerCards = first ? performanceProfile().eagerCards : 0;

  if (row.kind === "progress" && row.progress) {
    return (
      <Rail title={row.title} note="Zuletzt angesehen">
        {row.progress.map((item, index) => {
          const provider = item.provider ?? providerFromPath(item.episodePath);
          const still = tmdb.cachedSeason(item.slug, provider, item.season)?.episodes[item.episode]?.still ?? null;
          const remaining = Math.max(0, item.durationSec - item.positionSec);
          return (
            <LandscapeCard
              key={`${provider}|${item.slug}|${item.season}|${item.episode}`}
              slug={item.slug}
              provider={provider}
              title={item.title || item.slug}
              still={still}
              subtitle={`S${item.season} · F${item.episode}${remaining > 60 ? ` · noch ${Math.round(remaining / 60)} Min.` : ""}`}
              percent={progressPercent(item)}
              eager={index < eagerCards}
              onSelect={() => onPlayEpisode(
                provider, item.slug, item.season, item.episode, item.episodePath,
                library.state.resumeEnabled ? resumePosition(item) : 0,
              )}
              onRemove={() => library.removeFromContinueWatching(item.slug, provider)}
            />
          );
        })}
      </Rail>
    );
  }

  if (row.kind === "episodes" && row.episodes) {
    return (
      <Rail title={row.title} note="Aus dem Kalender der Quellen">
        {row.episodes.map((entry, index) => {
          const provider = entry.provider ?? "aniworld";
          const extras = tmdb.cachedSeason(entry.slug, provider, entry.season)?.episodes[entry.episode] ?? null;
          return (
            <LandscapeCard
              key={`${provider}|${entry.slug}|${entry.season}|${entry.episode}`}
              slug={entry.slug}
              provider={provider}
              title={entry.title}
              still={extras?.still ?? null}
              subtitle={[`S${entry.season} · F${entry.episode}`, entry.languages.join(", ") || null]
                .filter(Boolean).join(" · ")}
              eager={index < eagerCards}
              onSelect={() => onOpenTitle(provider, entry.slug)}
            />
          );
        })}
      </Rail>
    );
  }

  if (!row.titles || row.titles.length === 0) return null;
  return (
    <Rail title={row.title} note={row.note ?? (row.id === "popular" ? "Aktuell in Nori" : undefined)}>
      {row.titles.map((candidate, index) => (
        <PosterCard
          key={`${candidate.title.provider}|${candidate.title.slug}`}
          slug={candidate.title.slug}
          provider={candidate.title.provider}
          title={candidate.title.title}
          alts={candidate.title.alts}
          subtitle={titleMeta(candidate.title, candidate.signals)}
          eager={index < eagerCards}
          onSelect={() => onOpenTitle(candidate.title.provider, candidate.title.slug)}
        />
      ))}
    </Rail>
  );
}
