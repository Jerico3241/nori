// Die Detailseite einer Serie.
//
//     Kopfbereich   Breitbild, Schriftzug oder Titel, Jahr · Genres · Staffeln ·
//                   Bewertung, Beschreibung, Fortschritt, Aktionen
//     Staffel       Auswahlfeld · Folgenzahl · wie viel gesehen
//     Folgen        Liste mit Standbild, Titel, Laufzeit, Zustand
//     Ähnliche      nur Titel, die Nori tatsächlich anbietet
//
// Kein Herunterladen: Nori lädt nichts herunter. Keine Reiter „Details /
// Episoden": auf einem Fenster ist beides gleichzeitig zu sehen, und ein
// Reiter, der etwas versteckt, das daneben Platz hätte, ist eine Erfindung aus
// der Zeit kleiner Bildschirme.

import {
  Icon, covers, log, performanceProfile, ratingText, titleMeta, tmdb, useAsync, useData,
  useLibrary, usePersistentState, type SeasonArt,
} from "@nori/app";
import {
  HomeCatalogIndex, PROVIDERS, formatClock, homeTitleFrom, isEpisodeComplete, progressPercent,
  resumePosition, type CatalogProvider, type HomeCandidate, type SeriesDetail,
} from "@nori/core";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";

import { EpisodeRow, ErrorState, GridSkeleton, Hero, PosterCard, Rail } from "../components/ui";

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

  // Die Staffel übersteht den Weg in den Player und zurück.
  const [storedSeason, setSeason] = usePersistentState<string | null>(`${route}.season`, null);
  const season = search.get("season") ?? storedSeason;
  const [, setArtVersion] = useState(0);
  const [seasonArt, setSeasonArt] = useState<SeasonArt | null>(null);
  const [similar, setSimilar] = useState<HomeCandidate[]>([]);

  const base = useAsync<SeriesDetail>(() => series(provider, slug), [provider, slug]);
  const wantsOther = Boolean(season) && Boolean(base.data) && season !== base.data?.activeSeason;
  const seasonData = useAsync<SeriesDetail>(
    () => series(provider, slug, season),
    [provider, slug, season],
    { enabled: wantsOther },
  );
  // Nur Daten der gewünschten Staffel gelten. Während eine andere lädt, stehen
  // Platzhalter da — nicht die Folgen der vorherigen unter neuem Namen.
  const detail = wantsOther
    ? (seasonData.data?.activeSeason === season ? seasonData.data : null)
    : base.data;
  const activeSeason = season ?? base.data?.activeSeason ?? "1";
  const episodes = useMemo(
    () => [...(detail?.episodes ?? [])].sort((a, b) => a.number - b.number),
    [detail],
  );

  const title = base.data?.title ?? library.state.titles[slug] ?? slug;
  const art = covers.details(slug, provider);

  useEffect(() => {
    if (!base.data) return undefined;
    library.remember(slug, base.data.title, provider);
    let cancelled = false;
    const request = { slug, provider, title: base.data.title, alts: base.data.alts };
    const year = Number.parseInt(base.data.yearStart ?? "", 10);
    void covers.ensure({ ...request, year: Number.isFinite(year) ? year : null }).then(() => {
      if (!cancelled) setArtVersion((value) => value + 1);
    });
    void covers.ensureLogo(request).then(() => {
      if (!cancelled) setArtVersion((value) => value + 1);
    });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [base.data, provider, slug]);

  // Folgentitel, Laufzeiten und Standbilder der gezeigten Staffel.
  useEffect(() => {
    if (!base.data || episodes.length === 0) return undefined;
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

  /** Ähnliche Titel: TMDB nennt sie, der Nori-Katalog entscheidet. */
  const catalog = scopedCatalog();
  const catalogIndex = useMemo(
    () => new HomeCatalogIndex(catalog.items.map((item) => homeTitleFrom(item))),
    [catalog.items],
  );

  useEffect(() => {
    const id = art.tmdbID;
    if (!id || catalog.items.length === 0) return undefined;
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
      setSimilar((current) => (sameTitles(current, out) ? current : out));
    }).catch(() => setSimilar((current) => (current.length === 0 ? current : [])));
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [art.tmdbID, catalogIndex, catalog.items.length, provider, slug]);

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
  const stats = library.seasonStats(slug, activeSeason, episodes, provider);
  const seasons = base.data?.seasons ?? [];
  const seasonCount = seasons.filter((entry) => Number.parseInt(entry.id, 10) > 0).length;
  const latest = library.progressForEpisode(slug, activeSeason, plan.episode, undefined, provider);
  const favorite = library.isFavorite(slug);
  const rating = ratingText(art.rating, art.votes);
  const years = base.data?.yearStart
    ? (base.data.yearEnd && base.data.yearEnd !== base.data.yearStart
      ? `${base.data.yearStart}–${base.data.yearEnd}`
      : base.data.yearStart)
    : null;
  const parts = [
    years,
    seasonCount > 0 ? `${seasonCount} ${seasonCount === 1 ? "Staffel" : "Staffeln"}` : null,
    ...(base.data?.genres ?? []).slice(0, 3),
  ].filter(Boolean);
  const eagerCards = performanceProfile().eagerCards;

  return (
    <>
      <Hero
        slug={slug}
        provider={provider}
        title={title}
        alts={base.data?.alts}
        eyebrow={`${PROVIDERS[provider].label} · ${PROVIDERS[provider].kind}`}
        backdrop={art.backdrop}
        logo={art.logo}
        meta={(
          <>
            {parts.join(" · ")}
            {rating ? <span className="star">{parts.length ? " · " : ""}★ {rating}</span> : null}
          </>
        )}
        description={base.data?.description || art.overview || ""}
        progress={latest && progressPercent(latest) > 0 ? {
          percent: progressPercent(latest),
          label: `Staffel ${activeSeason} · Folge ${plan.episode} · ${progressPercent(latest)} % gesehen`,
        } : null}
        actions={(
          <>
            <button
              type="button"
              className="btn primary"
              onClick={() => openEpisode(plan.episode, library.state.resumeEnabled ? plan.resumeAt : 0)}
            >
              <Icon name="play" />
              <span>
                {plan.kind === "resume"
                  ? `Fortsetzen · F${plan.episode}`
                  : plan.kind === "next" ? `Weiter · F${plan.episode}` : "Jetzt ansehen"}
              </span>
            </button>
            <button
              type="button"
              className="btn"
              aria-pressed={favorite}
              onClick={() => library.toggleFavorite(slug, title, provider)}
            >
              <Icon name={favorite ? "heartFilled" : "heart"} />
              <span>{favorite ? "Gemerkt" : "Merkliste"}</span>
            </button>
          </>
        )}
      />

      <div className="page wide">
        <section className="section">
          <div className="season-row">
            {seasons.length > 1 ? (
              <select
                className="select"
                aria-label="Staffel wählen"
                value={activeSeason}
                onChange={(event) => setSeason(event.target.value)}
              >
                {seasons.map((entry) => (
                  <option key={entry.id} value={entry.id}>{entry.label}</option>
                ))}
              </select>
            ) : (
              <h2>{seasons[0]?.label ?? "Folgen"}</h2>
            )}
            <span className="row-value">
              {detail === null
                ? "Folgen werden geladen …"
                : `${episodes.length} ${episodes.length === 1 ? "Folge" : "Folgen"}`
                  + (stats.total > 0 && stats.watched > 0 ? ` · ${stats.watched} von ${stats.total} gesehen` : "")}
            </span>
          </div>

          {wantsOther && seasonData.status === "error" ? (
            <ErrorState
              title="Staffel nicht ladbar"
              message={seasonData.error ?? "Unbekannter Fehler"}
              onRetry={() => seasonData.reload()}
            />
          ) : detail === null ? (
            <GridSkeleton count={6} wide />
          ) : episodes.length === 0 ? (
            <p className="row-copy"><small>Für diese Staffel sind keine Folgen eingetragen.</small></p>
          ) : (
            <div className="grid episodes">
              {episodes.map((episode) => {
                const extras = seasonArt?.episodes[episode.number] ?? null;
                const progress = library.progressForEpisode(slug, activeSeason, episode.number, episode.path, provider);
                const done = isEpisodeComplete(progress);
                const resumeAt = resumePosition(progress);
                const percent = progressPercent(progress);
                const label = episode.germanTitle || extras?.title || episode.englishTitle || `Folge ${episode.number}`;
                return (
                  <EpisodeRow
                    key={episode.path || episode.number}
                    number={episode.number}
                    label={label}
                    meta={[
                      extras?.runtime ? `${extras.runtime} Min.` : null,
                      episode.languages.length > 0 ? episode.languages.join(" · ") : null,
                    ].filter(Boolean).join(" · ")}
                    state={done
                      ? "Gesehen"
                      : resumeAt >= 8
                        ? `Fortsetzen bei ${formatClock(resumeAt)}`
                        : percent > 0 ? `${percent} % gesehen` : null}
                    done={done}
                    still={extras?.still ?? null}
                    slug={slug}
                    provider={provider}
                    seriesTitle={title}
                    percent={percent}
                    onSelect={() => openEpisode(episode.number, library.state.resumeEnabled ? resumeAt : 0)}
                  />
                );
              })}
            </div>
          )}
        </section>

        {similar.length > 0 ? (
          <Rail title="Ähnliche Titel" note="Von TMDB empfohlen — nur, was Nori auch hat">
            {similar.map((candidate, index) => (
              <PosterCard
                key={`${candidate.title.provider}|${candidate.title.slug}`}
                slug={candidate.title.slug}
                provider={candidate.title.provider}
                title={candidate.title.title}
                alts={candidate.title.alts}
                subtitle={titleMeta(candidate.title, candidate.signals)}
                eager={index < eagerCards}
                onSelect={() => navigate(
                  `/titel/${candidate.title.provider}/${encodeURIComponent(candidate.title.slug)}`,
                )}
              />
            ))}
          </Rail>
        ) : null}
      </div>
    </>
  );
}

function sameTitles(a: HomeCandidate[], b: HomeCandidate[]): boolean {
  if (a.length !== b.length) return false;
  return a.every((entry, index) =>
    entry.title.slug === b[index].title.slug && entry.title.provider === b[index].title.provider);
}
