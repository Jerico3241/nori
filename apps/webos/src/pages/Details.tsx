// Die Detailseite: Backdrop und Kopfdaten oben, Staffeln und Folgen darunter.

import { PROVIDERS, type CatalogProvider, type SeriesDetail } from "@nori/core";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";

import { EpisodeCard } from "../components/EpisodeCard";
import { Icon } from "../components/Icon";
import { PosterImage } from "../components/PosterImage";
import { SeasonTabs } from "../components/SeasonTabs";
import { ErrorState, GridSkeleton } from "../components/States";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { covers } from "../services/covers";
import { useAsync } from "../hooks/useAsync";
import { useData } from "../state/data";
import { useLibrary } from "../state/library";

function isProvider(value: string | undefined): value is CatalogProvider {
  return value === "aniworld" || value === "serienstream";
}

export function DetailsPage() {
  const params = useParams<{ provider: string; slug: string }>();
  const navigate = useNavigate();
  const { series } = useData();
  const library = useLibrary();

  const provider: CatalogProvider = isProvider(params.provider) ? params.provider : "aniworld";
  const slug = decodeURIComponent(params.slug ?? "");
  const route = `details:${provider}:${slug}`;

  const [season, setSeason] = useState<string | null>(null);
  const [backdrop, setBackdrop] = useState<string | null>(() => covers.backdrop(slug, provider));

  const base = useAsync<SeriesDetail>(
    () => series(provider, slug),
    [provider, slug],
  );

  // Die Folgen einer anderen Staffel kommen von einer eigenen Seite. Der Kopf
  // bleibt dabei stehen — es wird nur die Liste ausgetauscht.
  const seasonData = useAsync<SeriesDetail>(
    () => series(provider, slug, season),
    [provider, slug, season],
    { enabled: Boolean(season) && season !== base.data?.activeSeason },
  );

  const detail = (season && season !== base.data?.activeSeason ? seasonData.data : base.data) ?? base.data;
  const activeSeason = season ?? base.data?.activeSeason ?? "1";
  const episodes = useMemo(() => {
    const list = detail?.episodes ?? [];
    return [...list].sort((a, b) => a.number - b.number);
  }, [detail]);

  useEffect(() => {
    if (!base.data) return;
    library.remember(slug, base.data.title, provider);
    void covers.ensureBackdrop(slug, base.data.title, provider).then((url) => {
      if (url) setBackdrop(url);
    });
    // Bewusst nur an den geladenen Daten hängend: `library` ändert sich bei
    // jedem Fortschritts-Tick, und der soll keinen Verlaufseintrag schreiben.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [base.data, provider, slug]);

  useEffect(() => {
    if (base.status !== "ready") return;
    return restoreFocusSoon(route, ["episodes", "actions", "seasons"]);
  }, [base.status, route, activeSeason]);

  const stats = useCallback(
    (id: string) => (id === activeSeason
      ? library.seasonStats(slug, id, episodes, provider)
      : null),
    [activeSeason, episodes, library, provider, slug],
  );

  const openEpisode = useCallback((number: number, at = 0) => {
    const path = episodes.find((ep) => ep.number === number)?.path ?? "";
    navigate(
      `/player/${provider}/${encodeURIComponent(slug)}`
      + `?season=${encodeURIComponent(activeSeason)}&episode=${number}`
      + `&path=${encodeURIComponent(path)}&at=${Math.floor(at)}`,
    );
  }, [activeSeason, episodes, navigate, provider, slug]);

  if (base.status === "error") {
    return (
      <div className="page">
        <ErrorState
          title="Seite nicht ladbar"
          message={base.error ?? "Unbekannter Fehler"}
          onRetry={() => base.reload()}
        />
      </div>
    );
  }

  const plan = detail
    ? library.nextPlay(slug, activeSeason, episodes, provider)
    : { episode: 1, resumeAt: 0, kind: "play" as const };
  const seasonInfo = library.seasonStats(slug, activeSeason, episodes, provider);
  const title = detail?.title ?? slug;

  return (
    <div className="page details">
      <div className="details-backdrop">
        <PosterImage
          slug={slug}
          provider={provider}
          title={title}
          src={backdrop ?? detail?.coverPath ?? null}
          eager
          className="hero-poster"
        />
        <div className="hero-vignette" />
      </div>

      <div className="details-head">
        <div className="details-poster">
          <PosterImage
            slug={slug}
            provider={provider}
            title={title}
            src={detail?.coverPath ?? null}
            eager
          />
        </div>
        <div className="details-copy">
          <span className="eyebrow">{PROVIDERS[provider].label}</span>
          <h1>{title}</h1>
          <p className="hero-meta">
            {[
              detail?.yearStart ? (detail.yearEnd && detail.yearEnd !== detail.yearStart
                ? `${detail.yearStart}–${detail.yearEnd}` : detail.yearStart) : null,
              detail?.fsk ? `FSK ${detail.fsk}` : null,
              detail?.imdb ? `IMDb ${detail.imdb}` : null,
              seasonInfo.total > 0 ? `${seasonInfo.watched}/${seasonInfo.total} gesehen` : null,
            ].filter(Boolean).map((part, index) => (
              <span key={String(part)}>
                {index > 0 ? <i aria-hidden="true">•</i> : null}
                {part}
              </span>
            ))}
          </p>
          {detail?.genres.length ? (
            <p className="details-genres">{detail.genres.join(" · ")}</p>
          ) : null}
          {detail?.description ? <p className="hero-description">{detail.description}</p> : null}
          {detail?.alts.length ? (
            <p className="details-alts">Auch bekannt als: {detail.alts.join(", ")}</p>
          ) : null}

          <SpotArea className="button-row" spotlightId={`details-actions-${slug}`}>
            <SpotButton
              className="primary"
              focusRoute={route}
              focusArea="actions"
              focusKey="play"
              onClick={() => openEpisode(plan.episode, plan.resumeAt)}
            >
              <Icon name="play" />
              {plan.kind === "resume"
                ? `Fortsetzen · Folge ${plan.episode}`
                : plan.kind === "next"
                  ? `Weiter · Folge ${plan.episode}`
                  : `Abspielen · Folge ${plan.episode}`}
            </SpotButton>
            <SpotButton
              focusRoute={route}
              focusArea="actions"
              focusKey="favorite"
              aria-pressed={library.isFavorite(slug)}
              onClick={() => library.toggleFavorite(slug, title, provider)}
            >
              <Icon name={library.isFavorite(slug) ? "check" : "bookmark"} />
              {library.isFavorite(slug) ? "Auf Merkliste" : "Merkliste"}
            </SpotButton>
          </SpotArea>
        </div>
      </div>

      <section className="episode-section">
        <header className="episode-heading">
          <h2>Folgen</h2>
          {detail?.seasons.length ? (
            <SeasonTabs
              seasons={detail.seasons}
              active={activeSeason}
              route={route}
              stats={stats}
              onPick={(id) => setSeason(id)}
            />
          ) : null}
        </header>

        {seasonData.status === "loading" && season !== base.data?.activeSeason ? (
          <GridSkeleton count={8} />
        ) : null}

        {seasonData.status === "error" && season !== base.data?.activeSeason ? (
          <ErrorState
            title="Staffel nicht ladbar"
            message={seasonData.error ?? "Unbekannter Fehler"}
            onRetry={() => seasonData.reload()}
          />
        ) : null}

        {episodes.length > 0 ? (
          <SpotArea className="episode-grid" spotlightId={`episodes-${slug}-${activeSeason}`}>
            {episodes.map((episode) => (
              <EpisodeCard
                key={episode.path || episode.number}
                episode={episode}
                progress={library.progressForEpisode(
                  slug, activeSeason, episode.number, episode.path, provider,
                )}
                focusRoute={route}
                focusArea="episodes"
                onSelect={() => {
                  const item = library.progressForEpisode(
                    slug, activeSeason, episode.number, episode.path, provider,
                  );
                  openEpisode(episode.number, library.state.resumeEnabled && item ? item.positionSec : 0);
                }}
              />
            ))}
          </SpotArea>
        ) : base.status === "ready" ? (
          <p className="muted-note">Für diese Staffel sind keine Folgen eingetragen.</p>
        ) : (
          <GridSkeleton count={8} />
        )}
      </section>
    </div>
  );
}
