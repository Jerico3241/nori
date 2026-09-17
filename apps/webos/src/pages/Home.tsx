// Die Startseite.
//
//     Seitenkopf     Willkommen zurück · Start · Suche
//     Hero           ein Titel aus dem Nori-Katalog, gewählt über TMDB-Signale
//     Weiterschauen  breite Karten aus dem echten Fortschritt
//     Neu & beliebt  TMDB-Trend und -Beliebtheit, begrenzt auf Noris Bestand
//     Neue Episoden  aus dem Kalender der Quellen
//     Für dich       aus Verlauf und Merkliste, mit TMDB-Empfehlungen
//     Merkliste
//
// Welche Reihen es gibt, entscheidet `useHomeFeed`; hier wird gezeichnet. Es
// erscheinen nur Reihen, für die es Daten gibt — eine leere Reihe ist
// schlechter als keine.

import {
  episodePathFor, progressPercent, providerFromPath, resumePosition,
  type AiringEntry, type CatalogProvider, type HomeCandidate, type HomeTitle, type SeriesDetail,
  type WatchProgress,
} from "@nori/core";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { Hero } from "../components/Hero";
import { Icon } from "../components/Icon";
import { LandscapeCard } from "../components/LandscapeCard";
import { titleMeta } from "../components/meta";
import { PosterCard } from "../components/PosterCard";
import { Rail } from "../components/Rail";
import { ratingText } from "../components/Rating";
import { Screen } from "../components/Screen";
import { EmptyState, ErrorState, RailSkeleton } from "../components/States";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotButton } from "../navigation/Spot";
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
  const [heroDetail, setHeroDetail] = useState<SeriesDetail | null>(null);
  const [, setArtVersion] = useState(0);

  /**
   * Der Titel im Kopfbereich.
   *
   * Erste Wahl ist die Rotation aus `heroPicks` (braucht TMDB, weil ein
   * Breitbild da sein muss). Ohne TMDB der zuletzt geschaute Titel, sonst der
   * erste des Katalogs — immer ein echter Nori-Titel, nie ein Beispiel.
   */
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
      (cause: unknown) => log("data", "Hero-Detail nicht ladbar", heroTitle.slug, (cause as Error)?.message),
    );
    const request = { slug: heroTitle.slug, provider: heroTitle.provider, title: heroTitle.title, alts: heroTitle.alts };
    void covers.ensureBackdrop(request).then(() => {
      if (!cancelled) setArtVersion((value) => value + 1);
    });
    // Der Schriftzug kostet einen eigenen Abruf — deshalb nur hier.
    void covers.ensureLogo(request).then(() => {
      if (!cancelled) setArtVersion((value) => value + 1);
    });
    return () => {
      cancelled = true;
    };
    // Nur am Titel hängend: `heroTitle` ist bei jedem Fortschrittstick ein neues Objekt.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [heroKey, series]);

  useEffect(() => restoreFocusSoon(
    ROUTE,
    ["hero", "continue", "popular", "fresh", "episodes", "foryou", "discover", "watchlist", "top"],
    { initial: '[data-focus-key="hero-play"]' },
  ), []);

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

  const searchButton = (
    <SpotButton
      className="glassbtn"
      focusRoute={ROUTE}
      focusArea="top"
      focusKey="top-search"
      onClick={() => navigate("/katalog?suche=1")}
    >
      <Icon name="search" />
      Suche
    </SpotButton>
  );

  if (catalog.status === "error" && catalog.items.length === 0) {
    return (
      <Screen route={ROUTE} eyebrow="Willkommen zurück" title="Start" actions={searchButton}>
        <ErrorState
          title={online ? "Katalog nicht ladbar" : "Keine Verbindung"}
          message={catalog.error ?? "Nori konnte keine Verbindung herstellen."}
          onRetry={() => {
            reloadCatalog("aniworld");
            reloadCatalog("serienstream");
            feed.reload();
          }}
        />
      </Screen>
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
  const heroPercent = heroProgress ? progressPercent(heroProgress) : 0;

  return (
    <Screen route={ROUTE} eyebrow="Willkommen zurück" title="Start" actions={searchButton} className="home">
      {heroTitle ? (
        <Hero
          variant="home"
          slug={heroTitle.slug}
          provider={heroTitle.provider}
          title={heroDetail?.title ?? heroTitle.title}
          alts={heroTitle.alts}
          eyebrow={heroProgress ? "Weiterschauen" : "Heute im Fokus"}
          backdrop={art?.backdrop ?? null}
          logo={art?.logo ?? null}
          meta={[years, ...genres].filter((part): part is string => Boolean(part))}
          rating={ratingText(art?.rating ?? null, art?.votes ?? null)}
          description={heroDetail?.description || art?.overview || ""}
          progress={heroProgress ? {
            percent: heroPercent,
            label: `Staffel ${heroProgress.season} · Folge ${heroProgress.episode} · ${heroPercent} % gesehen`,
          } : null}
          actions={(
            <>
              <SpotButton
                className="hero-btn primary"
                focusRoute={ROUTE}
                focusArea="hero"
                focusKey="hero-play"
                onClick={playHero}
              >
                <Icon name="play" />
                {heroProgress ? "Weiter ansehen" : "Jetzt ansehen"}
              </SpotButton>
              <SpotButton
                className="hero-btn"
                focusRoute={ROUTE}
                focusArea="hero"
                focusKey="hero-favorite"
                aria-pressed={favorite}
                onClick={() => library.toggleFavorite(heroTitle.slug, heroDetail?.title ?? heroTitle.title, heroTitle.provider)}
              >
                <Icon name={favorite ? "heartFilled" : "heart"} />
                {favorite ? "Gemerkt" : "Merkliste"}
              </SpotButton>
              <SpotButton
                className="hero-btn"
                focusRoute={ROUTE}
                focusArea="hero"
                focusKey="hero-more"
                aria-label="Mehr zu diesem Titel"
                onClick={() => openTitle(heroTitle.provider, heroTitle.slug)}
              >
                <Icon name="more" />
                Mehr
              </SpotButton>
            </>
          )}
        />
      ) : catalog.status === "loading" ? (
        <section className="hero hero-home hero-skeleton" aria-hidden="true" />
      ) : null}

      {catalog.status === "loading" && catalog.items.length === 0 ? (
        <section className="section rail-section">
          <div className="section-head"><h2>Wird geladen …</h2></div>
          <RailSkeleton />
        </section>
      ) : null}

      {feed.rows.map((row) => (
        <HomeRail key={row.id} row={row} onOpenTitle={openTitle} onPlayEpisode={playEpisode} />
      ))}

      {catalog.status === "ready" && catalog.items.length === 0 ? (
        <EmptyState
          title="Nichts in diesem Bereich"
          message="Für diesen Bereich kamen keine Titel zurück. Ein anderer Bereich oder ein erneuter Versuch hilft meistens."
        />
      ) : null}
    </Screen>
  );
}

function HomeRail({ row, onOpenTitle, onPlayEpisode }: {
  row: HomeRowView;
  onOpenTitle(provider: CatalogProvider, slug: string): void;
  onPlayEpisode(provider: CatalogProvider, slug: string, season: string, episode: number, path: string, at?: number): void;
}) {
  const library = useLibrary();
  /**
   * „Entfernen": OK nimmt die Serie aus der Reihe, statt sie fortzusetzen.
   *
   * Derselbe sichtbare Modus wie „Bearbeiten" in der Merkliste. Gelöscht wird
   * dabei nichts — die angefangenen Folgen werden auf null zurückgesetzt, und
   * was abgeschlossen ist, bleibt abgeschlossen (`WatchMarks` im Kern).
   */
  const [editing, setEditing] = useState(false);

  if (row.kind === "progress" && row.progress) {
    return (
      <Rail
        id={row.id}
        title={row.title}
        note={editing ? "OK entfernt einen Titel" : "Zuletzt angesehen"}
      >
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
              focusRoute={ROUTE}
              focusArea={row.id}
              focusKey={`${row.id}-${provider}-${item.slug}`}
              eager={index < 4}
              overlay={editing ? <span className="card-remove"><Icon name="trash" />Entfernen</span> : null}
              onSelect={() => {
                if (editing) {
                  library.removeFromContinueWatching(item.slug, provider);
                  return;
                }
                onPlayEpisode(
                  provider, item.slug, item.season, item.episode, item.episodePath,
                  library.state.resumeEnabled ? resumePosition(item) : 0,
                );
              }}
            />
          );
        })}
        {/*
          Der Knopf steht am **Ende** der Reihe, nicht über ihr.
          In der Kopfzeile wäre er ein Fokusstopp zwischen Hero und erster
          Karte: jedes „runter" von „Jetzt ansehen" landete auf einem Knopf
          statt auf dem, was man weiterschauen will. Am Ende erreicht ihn, wer
          ohnehin durch die Reihe fährt — und niemand sonst.
        */}
        <SpotButton
          card
          className={`rail-action${editing ? " active" : ""}`}
          focusRoute={ROUTE}
          focusArea={row.id}
          focusKey={`${row.id}-edit`}
          aria-pressed={editing}
          onClick={() => setEditing((value) => !value)}
        >
          <Icon name={editing ? "check" : "trash"} />
          <span className="card-title">{editing ? "Fertig" : "Titel entfernen"}</span>
        </SpotButton>
      </Rail>
    );
  }

  if (row.kind === "episodes" && row.episodes) {
    return (
      <Rail id={row.id} title={row.title} note="Aus dem Kalender der Quellen">
        {row.episodes.map((entry, index) => (
          <EpisodeRailCard key={entryKey(entry)} entry={entry} index={index} onOpenTitle={onOpenTitle} />
        ))}
      </Rail>
    );
  }

  if (!row.titles || row.titles.length === 0) return null;
  return (
    <Rail id={row.id} title={row.title} note={row.note ?? (row.id === "popular" ? "Aktuell in Nori" : undefined)}>
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
  const extras = tmdb.cachedSeason(entry.slug, provider, entry.season)?.episodes[entry.episode] ?? null;
  return (
    <LandscapeCard
      slug={entry.slug}
      provider={provider}
      title={entry.title}
      still={extras?.still ?? null}
      subtitle={[`S${entry.season} · F${entry.episode}`, entry.languages.join(", ") || null].filter(Boolean).join(" · ")}
      focusRoute={ROUTE}
      focusArea="episodes"
      focusKey={`episodes-${provider}-${entry.slug}-${entry.season}-${entry.episode}`}
      eager={index < 4}
      onSelect={() => onOpenTitle(provider, entry.slug)}
    />
  );
}

function TitleRailCard({ candidate, area, index }: { candidate: HomeCandidate; area: string; index: number }) {
  const { title } = candidate;
  return (
    <PosterCard
      slug={title.slug}
      provider={title.provider}
      title={title.title}
      alts={title.alts}
      subtitle={titleMeta(title, candidate.signals)}
      focusRoute={ROUTE}
      focusArea={area}
      focusKey={`${area}-${title.provider}-${title.slug}`}
      eager={index < 7}
    />
  );
}

function candidateKey(candidate: HomeCandidate): string {
  return `${candidate.title.provider}|${candidate.title.slug}`;
}

function entryKey(entry: AiringEntry): string {
  return `${entry.provider}|${entry.slug}|${entry.season}|${entry.episode}`;
}
