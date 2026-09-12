// Die Detailseite einer Serie.
//
// ## Aufbau
//
//     Kopfbereich   Breitbild über die volle Breite, Schriftzug oder Titel,
//                   Jahr · Bewertung · Genres, Beschreibung, Fortschritt,
//                   Abspielen/Fortsetzen und Merkliste
//     Staffelwahl   Reiter oder Auswahlraster, siehe SeasonPicker
//     Folgen        16:9-Kacheln mit Standbild, Beschreibung, Laufzeit
//     Ähnliche      nur Titel, die Nori tatsächlich anbietet
//
// Der Kopfbereich ist bewusst groß (36 rem). Der vorherige Stand zeigte ein
// 30 rem hohes Bild und schob eine Posterkachel mit −12 rem darüber; auf dem
// Fernseher las sich das als Bruch mitten im Bild, und vom Breitbild blieb ein
// Streifen. Jetzt trägt das Breitbild die Fläche, und der Text steht darin —
// wie auf iPhone und Mac.
//
// Keine Download-Knöpfe: Nori lädt nichts herunter. Ein Knopf, der das
// anbietet, wäre ein Versprechen, das die App nicht hält.

import {
  PROVIDERS, type CatalogProvider, type HomeCandidate, type SeriesDetail,
} from "@nori/core";
import { HomeCatalogIndex, homeTitleFrom, progressPercent, resumePosition } from "@nori/core";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";

import { EpisodeCard } from "../components/EpisodeCard";
import { Icon } from "../components/Icon";
import { MediaCard } from "../components/MediaCard";
import { PosterImage } from "../components/PosterImage";
import { Rail } from "../components/Rail";
import { Rating } from "../components/Rating";
import { SeasonPicker } from "../components/SeasonPicker";
import { ErrorState, GridSkeleton } from "../components/States";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { covers } from "../services/covers";
import { log } from "../services/log";
import { tmdb, type SeasonArt } from "../services/tmdb";
import { useAsync } from "../hooks/useAsync";
import { useData } from "../state/data";
import { useLibrary } from "../state/library";

function isProvider(value: string | undefined): value is CatalogProvider {
  return value === "aniworld" || value === "serienstream";
}

export function DetailsPage() {
  const params = useParams<{ provider: string; slug: string }>();
  const [search] = useSearchParams();
  const navigate = useNavigate();
  const { series, scopedCatalog } = useData();
  const library = useLibrary();

  const provider: CatalogProvider = isProvider(params.provider) ? params.provider : "aniworld";
  const slug = decodeURIComponent(params.slug ?? "");
  const route = `details:${provider}:${slug}`;

  // Eine Staffel in der Adresse: der Player springt so zurück in die Staffel,
  // aus der er kam.
  const [season, setSeason] = useState<string | null>(search.get("season"));
  const [art, setArt] = useState(() => covers.details(slug, provider));
  const [seasonArt, setSeasonArt] = useState<SeasonArt | null>(null);
  const [similar, setSimilar] = useState<HomeCandidate[]>([]);

  const base = useAsync<SeriesDetail>(() => series(provider, slug), [provider, slug]);

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

  const title = detail?.title ?? library.state.titles[slug] ?? slug;
  const alts = useMemo(() => base.data?.alts ?? [], [base.data]);

  // Verlauf schreiben und die Bilder besorgen.
  //
  // Bewusst nur an den geladenen Daten hängend: `library` ändert sich bei jedem
  // Fortschritts-Tick, und der soll keinen Verlaufseintrag schreiben.
  useEffect(() => {
    if (!base.data) return;
    library.remember(slug, base.data.title, provider);
    let cancelled = false;
    const request = { slug, provider, title: base.data.title, alts: base.data.alts };
    const year = Number.parseInt(base.data.yearStart ?? "", 10);
    void covers.ensure({ ...request, year: Number.isFinite(year) ? year : null }).then(() => {
      if (!cancelled) setArt(covers.details(slug, provider));
    });
    void covers.ensureLogo(request).then(() => {
      if (!cancelled) setArt(covers.details(slug, provider));
    });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [base.data, provider, slug]);

  // Folgentitel, Beschreibungen und Standbilder der gezeigten Staffel.
  useEffect(() => {
    if (!base.data || episodes.length === 0) return;
    let cancelled = false;
    setSeasonArt(tmdb.cachedSeason(slug, provider, activeSeason));
    void tmdb.ensureSeason({
      slug,
      provider,
      title: base.data.title,
      alternates: base.data.alts,
      season: activeSeason,
      episodes,
      expectedSeasons: base.data.seasons.length,
    }).then((found) => {
      if (!cancelled) setSeasonArt(found);
    }).catch((cause: unknown) => {
      log("tmdb", "Staffeldaten nicht ladbar", slug, activeSeason, (cause as Error)?.message);
    });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [base.data, provider, slug, activeSeason, episodes.length]);

  /**
   * Ähnliche Titel.
   *
   * Der Weg ist absichtlich der Umweg: TMDB nennt Empfehlungen, und jede davon
   * wird über den **Nori-Katalog** zurückgeführt. Was Nori nicht anbietet,
   * fällt weg. Eine Empfehlung, die sich auswählen lässt und nichts öffnet,
   * ist schlechter als eine Reihe weniger.
   */
  const catalog = scopedCatalog();
  const catalogIndex = useMemo(
    () => new HomeCatalogIndex(catalog.items.map((item) => homeTitleFrom(item))),
    [catalog.items],
  );

  useEffect(() => {
    const id = art.tmdbID;
    if (!id || catalog.items.length === 0) return;
    let cancelled = false;
    void tmdb.ensureRelated(id).then((rows) => {
      if (cancelled) return;
      const seen = new Set<string>([`${provider}|${slug}`]);
      const out: HomeCandidate[] = [];
      for (const row of rows) {
        const match = catalogIndex.match(row);
        if (!match) continue;
        const key = `${match.provider}|${match.slug}`;
        if (seen.has(key)) continue;
        seen.add(key);
        out.push({
          title: match,
          signals: {
            tmdbID: row.id,
            popularity: row.popularity,
            voteAverage: row.voteAverage,
            voteCount: row.voteCount,
            firstAirDate: row.firstAirDate,
            lastAirDate: null,
            trendingRank: null,
            genreIDs: row.genreIDs,
            hasBackdrop: Boolean(row.backdropPath),
          },
          watchedRatio: 0,
          inWatchlist: library.isFavorite(match.slug),
          hasFreshEpisode: false,
        });
        if (out.length >= 16) break;
      }
      // Nur setzen, wenn sich etwas geändert hat. Ein neues, gleiches Feld
      // löst ein Rendern aus, und ein Rendern löst diesen Effekt wieder aus —
      // das war die Schleife, die den Fernseher hat hängen lassen.
      setSimilar((current) => (sameTitles(current, out) ? current : out));
    }).catch(() => setSimilar((current) => (current.length === 0 ? current : [])));
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [art.tmdbID, catalogIndex, catalog.items.length, provider, slug]);

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
    const path = episodes.find((episode) => episode.number === number)?.path ?? "";
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
  const seasonCount = (detail?.seasons ?? [])
    .filter((season) => Number.parseInt(season.id, 10) > 0).length;
  const latest = library.progressForEpisode(slug, activeSeason, plan.episode, undefined, provider);
  const heroPercent = latest ? progressPercent(latest) : 0;
  const description = detail?.description || art.overview || "";

  return (
    <div className="page details">
      <div className="details-backdrop">
        <PosterImage
          slug={slug}
          provider={provider}
          title={title}
          alts={alts}
          src={art.backdrop ?? detail?.coverPath ?? null}
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
            alts={alts}
            src={art.poster ?? detail?.coverPath ?? null}
            eager
          />
        </div>
        <div className="details-copy">
          <span className="eyebrow">{PROVIDERS[provider].label}</span>
          {art.logo ? (
            <img className="details-logo" src={art.logo} alt={title} />
          ) : (
            <h1>{title}</h1>
          )}
          <p className="hero-meta">
            <Rating value={art.rating} votes={art.votes} />
            {[
              detail?.yearStart ? (detail.yearEnd && detail.yearEnd !== detail.yearStart
                ? `${detail.yearStart}–${detail.yearEnd}` : detail.yearStart) : null,
              detail?.fsk ? `FSK ${detail.fsk}` : null,
              // Nur gezählte Staffeln. „Filme" steht in derselben Liste, ist
              // aber keine Staffel — „3 Staffeln" über zwei Staffeln und einem
              // Filmabschnitt ist eine falsche Zahl.
              seasonCount > 1 ? `${seasonCount} Staffeln` : null,
              seasonInfo.total > 0 ? `${seasonInfo.watched}/${seasonInfo.total} gesehen` : null,
            ].filter(Boolean).map((part, index) => (
              <span key={String(part)}>
                {index > 0 || art.rating ? <i aria-hidden="true">•</i> : null}
                {part}
              </span>
            ))}
          </p>
          {detail?.genres.length ? (
            <p className="details-genres">{detail.genres.join(" · ")}</p>
          ) : null}
          {description ? <p className="hero-description">{description}</p> : null}
          {alts.length ? (
            <p className="details-alts">Auch bekannt als: {alts.slice(0, 3).join(", ")}</p>
          ) : null}

          {heroPercent > 0 && heroPercent < 100 ? (
            <div className="hero-progress" aria-label={`${heroPercent} Prozent gesehen`}>
              <span className="hero-progress-bar"><i style={{ width: `${heroPercent}%` }} /></span>
              <small>Folge {plan.episode} · {heroPercent} % gesehen</small>
            </div>
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
            <SeasonPicker
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
                extras={seasonArt?.episodes[episode.number] ?? null}
                progress={library.progressForEpisode(
                  slug, activeSeason, episode.number, episode.path, provider,
                )}
                focusRoute={route}
                focusArea="episodes"
                onSelect={() => {
                  const item = library.progressForEpisode(
                    slug, activeSeason, episode.number, episode.path, provider,
                  );
                  openEpisode(
                    episode.number,
                    library.state.resumeEnabled ? resumePosition(item) : 0,
                  );
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

      {similar.length > 0 ? (
        <div className="details-similar">
          <Rail
            title="Ähnliche Titel"
            id={`similar-${slug}`}
            count={similar.length}
            note="Von TMDB empfohlen — gezeigt wird nur, was Nori auch hat."
          >
            {similar.map((candidate, index) => (
              <MediaCard
                key={`${candidate.title.provider}|${candidate.title.slug}`}
                slug={candidate.title.slug}
                title={candidate.title.title}
                provider={candidate.title.provider}
                alts={candidate.title.alts}
                subtitle={candidate.title.genres[0] ?? undefined}
                rating={candidate.signals.voteAverage}
                votes={candidate.signals.voteCount}
                focusRoute={route}
                focusArea="similar"
                focusKey={`similar-${candidate.title.provider}-${candidate.title.slug}`}
                eager={index < 6}
              />
            ))}
          </Rail>
        </div>
      ) : null}
    </div>
  );
}

/** Zwei Vorschlagslisten auf Gleichheit prüfen — über die Kennungen. */
function sameTitles(a: HomeCandidate[], b: HomeCandidate[]): boolean {
  if (a.length !== b.length) return false;
  return a.every((candidate, index) =>
    candidate.title.slug === b[index].title.slug
    && candidate.title.provider === b[index].title.provider);
}
