// Die Detailseite einer Serie.
//
//     Seitenkopf   Quelle · Zurück
//     Hero         Breitbild, Schriftzug oder Titel, Jahr · Genres · Staffeln ·
//                  Bewertung, Beschreibung, Fortschritt, Aktionen
//     Staffel      Knopf, der ein Auswahlmenü öffnet · Folgenzahl · gesehen
//     Folgen       drei 16:9-Karten je Zeile
//     Ähnliche     nur Titel, die Nori tatsächlich anbietet
//
// Staffel und Folgenraster stehen in **einem** Abschnitt (`data-reveal`): wer
// auf die erste Folge wechselt, sieht die Staffelzeile darüber mit.
//
// Keine Download-Knöpfe: Nori lädt nichts herunter.

import {
  HomeCatalogIndex, PROVIDERS, homeTitleFrom, isEpisodeComplete, progressPercent, resumePosition,
  seasonProgressLabel, watchStateText,
  type CatalogProvider, type HomeCandidate, type SeasonEpisodes, type SeriesDetail,
} from "@nori/core";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";

import { EpisodeCard } from "../components/EpisodeCard";
import { Hero } from "../components/Hero";
import {
  covers,
  Icon,
  log,
  performanceProfile,
  titleMeta,
  tmdb,
  useAsync,
  useData,
  useLibrary,
  usePersistentState,
  type SeasonArt,
} from "@nori/app";
import { Dialog, Menu } from "../components/Overlay";
import { PosterCard } from "../components/PosterCard";
import { Rail } from "../components/Rail";
import { ratingText } from "../components/Rating";
import { Screen } from "../components/Screen";
import { ErrorState } from "../components/States";
import { recallFocus, restoreFocusSoon } from "../navigation/focusMemory";
import { SpotButton } from "../navigation/Spot";

const EPISODE_PAGE = 30;

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

  // Die Staffel übersteht den Weg in den Player und zurück — sonst stünde der
  // Fokus nach „Zurück" auf Folge 3 der falschen Staffel.
  const [storedSeason, setSeason] = usePersistentState<string | null>(`${route}.season`, null);
  const season = search.get("season") ?? storedSeason;
  const [, setArtVersion] = useState(0);
  const [seasonArt, setSeasonArt] = useState<SeasonArt | null>(null);
  const [similar, setSimilar] = useState<HomeCandidate[]>([]);
  const [seasonMenu, setSeasonMenu] = useState(false);
  const [infoOpen, setInfoOpen] = useState(false);
  /**
   * „Sehstand ändern": OK setzt eine Folge auf gesehen oder ungesehen, statt
   * sie abzuspielen. Derselbe sichtbare Modus wie „Bearbeiten" in der
   * Merkliste — eine Fernbedienung hat keinen langen Druck und kein
   * Kontextmenü.
   */
  const [marking, setMarking] = useState(false);
  /** „Serie als gesehen" holt die übrigen Staffeln nach. */
  const [markingSeries, setMarkingSeries] = useState(false);
  const [limit, setLimit] = useState(() => {
    const remembered = recallFocus(route, "episodes");
    const number = remembered ? Number(remembered.replace("episode-", "")) : 0;
    return Math.max(EPISODE_PAGE, Number.isFinite(number) ? number + 12 : 0);
  });

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
  const alts = useMemo(() => base.data?.alts ?? [], [base.data]);
  const art = covers.details(slug, provider);

  // Verlauf schreiben und Bilder besorgen. Nur an den geladenen Daten hängend:
  // `library` ändert sich bei jedem Fortschrittstick.
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

  /**
   * Ähnliche Titel: TMDB nennt Empfehlungen, und jede wird über den
   * **Nori-Katalog** zurückgeführt. Was Nori nicht anbietet, fällt weg.
   */
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
      // Nur setzen, wenn sich etwas geändert hat — ein gleiches neues Feld
      // löste sonst ein Rendern und damit diesen Effekt erneut aus.
      setSimilar((current) => (sameTitles(current, out) ? current : out));
    }).catch(() => setSimilar((current) => (current.length === 0 ? current : [])));
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [art.tmdbID, catalogIndex, catalog.items.length, provider, slug]);

  useEffect(() => {
    if (base.status !== "ready") return undefined;
    return restoreFocusSoon(route, ["episodes", "actions", "seasons", "similar"], {
      initial: '[data-focus-key="play"]',
    });
  }, [base.status, route]);

  const openEpisode = useCallback((number: number, at = 0) => {
    const path = episodes.find((episode) => episode.number === number)?.path ?? "";
    navigate(
      `/player/${provider}/${encodeURIComponent(slug)}`
      + `?season=${encodeURIComponent(activeSeason)}&episode=${number}`
      + `&path=${encodeURIComponent(path)}&at=${Math.floor(at)}`,
    );
  }, [activeSeason, episodes, navigate, provider, slug]);

  /**
   * Die ganze Serie abhaken.
   *
   * Die einzige Stelle hier, die dafür Netz braucht: die Folgenliste jeder
   * Staffel steht nur auf der Seite der Quelle. Die schon geladene Staffel
   * wird nicht noch einmal geholt, und geschrieben wird am Ende **einmal** —
   * auf einem Fernseher ist ein Schreibvorgang je Folge sichtbar.
   */
  const markSeriesSeen = useCallback(async () => {
    const detailNow = detail;
    if (!detailNow || markingSeries) return;
    setMarkingSeries(true);
    try {
      const loaded: SeasonEpisodes[] = [{ season: activeSeason, episodes }];
      for (const ref of detailNow.seasons) {
        if (ref.id === activeSeason) continue;
        try {
          const other = await series(provider, slug, ref.id);
          if (other.episodes.length > 0) loaded.push({ season: ref.id, episodes: other.episodes });
        } catch (cause) {
          log("data", "Staffel nicht ladbar", slug, ref.id, (cause as Error)?.message);
        }
      }
      library.setSeriesWatched(slug, title, loaded, provider);
    } finally {
      setMarkingSeries(false);
      setInfoOpen(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [detail, markingSeries, activeSeason, episodes, provider, slug, title]);

  const back = (
    <SpotButton className="glassbtn" focusRoute={route} focusArea="top" focusKey="back" onClick={() => navigate(-1)}>
      <Icon name="back" />
      Zurück
    </SpotButton>
  );
  const eyebrow = `${PROVIDERS[provider].label} · ${PROVIDERS[provider].kind}`;

  if (base.status === "error") {
    return (
      <Screen route={route} eyebrow={eyebrow} title={title} actions={back}>
        <ErrorState title="Seite nicht ladbar" message={base.error ?? "Unbekannter Fehler"} onRetry={() => base.reload()} />
      </Screen>
    );
  }

  const plan = detail
    ? library.nextPlay(slug, activeSeason, episodes, provider)
    : { episode: 1, resumeAt: 0, kind: "play" as const };
  const stats = library.seasonStats(slug, activeSeason, episodes, provider);
  // „7 von 12 gesehen" — der Text kommt aus dem Kern, damit iPhone, Mac und
  // Fernseher denselben schreiben.
  const seasonLabelText = seasonProgressLabel(stats.watched, stats.total);
  const seriesSummary = library.seriesWatchSummary(slug, provider);
  const seasons = base.data?.seasons ?? [];
  const seasonCount = seasons.filter((entry) => Number.parseInt(entry.id, 10) > 0).length;
  const latest = library.progressForEpisode(slug, activeSeason, plan.episode, undefined, provider);
  const heroPercent = latest ? progressPercent(latest) : 0;
  const favorite = library.isFavorite(slug);
  const years = base.data?.yearStart
    ? (base.data.yearEnd && base.data.yearEnd !== base.data.yearStart
      ? `${base.data.yearStart}–${base.data.yearEnd}`
      : base.data.yearStart)
    : null;
  const seasonLabel = seasons.find((entry) => entry.id === activeSeason)?.label ?? `Staffel ${activeSeason}`;
  const visibleEpisodes = episodes.slice(0, limit);
  const loadingEpisodes = base.status !== "ready" || (wantsOther && !detail);

  return (
    <Screen route={route} eyebrow={eyebrow} actions={back} className="details">
      <Hero
        variant="detail"
        slug={slug}
        provider={provider}
        title={title}
        alts={alts}
        backdrop={art.backdrop}
        logo={art.logo}
        meta={[
          years,
          base.data?.genres.slice(0, 3).join(" · ") || null,
          seasonCount > 1 ? `${seasonCount} Staffeln` : null,
          base.data?.fsk ? `FSK ${base.data.fsk}` : null,
        ].filter((part): part is string => Boolean(part))}
        rating={ratingText(art.rating, art.votes)}
        description={base.data?.description || art.overview || ""}
        progress={heroPercent > 0 ? {
          percent: heroPercent,
          label: `Folge ${plan.episode} · ${heroPercent} % gesehen`,
        } : null}
        actions={(
          <>
            <SpotButton
              className="hero-btn primary"
              focusRoute={route}
              focusArea="actions"
              focusKey="play"
              disabled={loadingEpisodes || episodes.length === 0}
              onClick={() => openEpisode(plan.episode, plan.resumeAt)}
            >
              <Icon name="play" />
              {plan.kind === "resume"
                ? `Weiter ansehen · F${plan.episode}`
                : plan.kind === "next"
                  ? `Weiter mit Folge ${plan.episode}`
                  : "Jetzt ansehen"}
            </SpotButton>
            <SpotButton
              className="hero-btn"
              focusRoute={route}
              focusArea="actions"
              focusKey="favorite"
              aria-pressed={favorite}
              onClick={() => library.toggleFavorite(slug, title, provider)}
            >
              <Icon name={favorite ? "heartFilled" : "heart"} />
              {favorite ? "Gemerkt" : "Merkliste"}
            </SpotButton>
            <SpotButton
              className="hero-btn"
              focusRoute={route}
              focusArea="actions"
              focusKey="more"
              aria-haspopup="dialog"
              onClick={() => setInfoOpen(true)}
            >
              <Icon name="more" />
              Mehr
            </SpotButton>
          </>
        )}
      />

      <section className="season-section" data-reveal="" aria-label="Folgen">
        <div className="season-row" data-nav-row="">
          {seasons.length > 1 ? (
            <SpotButton
              className="chip active season-trigger"
              focusRoute={route}
              focusArea="seasons"
              focusKey="season-open"
              aria-haspopup="dialog"
              onClick={() => setSeasonMenu(true)}
            >
              {seasonLabel}
              <Icon name="chevronDown" />
            </SpotButton>
          ) : (
            <span className="season-label">{seasonLabel}</span>
          )}
          <span className="season-count">
            {loadingEpisodes
              ? "Folgen werden geladen …"
              : `${episodes.length} ${episodes.length === 1 ? "Folge" : "Folgen"}`
                + (seasonLabelText ? ` · ${seasonLabelText}` : "")}
          </span>
          {episodes.length > 0 ? (
            <SpotButton
              className={`chip season-mark${marking ? " active" : ""}`}
              focusRoute={route}
              focusArea="seasons"
              focusKey="season-mark"
              aria-pressed={marking}
              onClick={() => setMarking((value) => !value)}
            >
              <Icon name={marking ? "close" : "check"} />
              {marking ? "Fertig" : "Sehstand"}
            </SpotButton>
          ) : null}
        </div>

        {marking ? (
          <p className="muted-note">
            OK setzt eine Folge auf gesehen oder ungesehen. Abspielen geht nach „Fertig" wieder.
          </p>
        ) : null}

        {wantsOther && seasonData.status === "error" ? (
          <ErrorState title="Staffel nicht ladbar" message={seasonData.error ?? "Unbekannter Fehler"} onRetry={() => seasonData.reload()} />
        ) : loadingEpisodes ? (
          <div className="episode-grid" aria-hidden="true">
            {Array.from({ length: 6 }, (_, index) => (
              <div className="ep-card skeleton" key={index}>
                <div className="card-art ep-thumb" />
                <div className="ep-body"><div className="skeleton-line" /></div>
              </div>
            ))}
          </div>
        ) : episodes.length === 0 ? (
          <p className="muted-note">Für diese Staffel sind keine Folgen eingetragen.</p>
        ) : (
          <div className="episode-grid" data-nav-row="">
            {visibleEpisodes.map((episode, index) => (
              <div
                key={episode.path || episode.number}
                className="ep-slot"
                onFocus={() => {
                  if (index >= visibleEpisodes.length - 6 && visibleEpisodes.length < episodes.length) {
                    setLimit((current) => current + EPISODE_PAGE);
                  }
                }}
              >
                <EpisodeCard
                  episode={episode}
                  slug={slug}
                  provider={provider}
                  seriesTitle={title}
                  extras={seasonArt?.episodes[episode.number] ?? null}
                  progress={library.progressForEpisode(slug, activeSeason, episode.number, episode.path, provider)}
                  focusRoute={route}
                  marking={marking}
                  onSelect={() => {
                    const item = library.progressForEpisode(slug, activeSeason, episode.number, episode.path, provider);
                    if (marking) {
                      library.setWatched(
                        !isEpisodeComplete(item), slug, title, activeSeason, episode, provider,
                      );
                      return;
                    }
                    openEpisode(episode.number, library.state.resumeEnabled ? resumePosition(item) : 0);
                  }}
                />
              </div>
            ))}
          </div>
        )}
      </section>

      {similar.length > 0 ? (
        <Rail id={`similar-${slug}`} title="Ähnliche Titel" note="Von TMDB empfohlen — nur, was Nori auch hat">
          {similar.map((candidate, index) => (
            <PosterCard
              key={`${candidate.title.provider}|${candidate.title.slug}`}
              slug={candidate.title.slug}
              provider={candidate.title.provider}
              title={candidate.title.title}
              alts={candidate.title.alts}
              subtitle={titleMeta(candidate.title, candidate.signals)}
              focusRoute={route}
              focusArea="similar"
              focusKey={`similar-${candidate.title.provider}-${candidate.title.slug}`}
              eager={index < performanceProfile().eagerCards}
            />
          ))}
        </Rail>
      ) : null}

      <Menu
        open={seasonMenu}
        onClose={() => setSeasonMenu(false)}
        eyebrow={title}
        title="Staffel wählen"
        id="season"
        value={activeSeason}
        options={seasons.map((entry) => ({ value: entry.id, label: entry.label }))}
        onPick={(id) => {
          setSeason(id);
          setLimit(EPISODE_PAGE);
        }}
      />

      <Dialog open={infoOpen} onClose={() => setInfoOpen(false)} eyebrow="Mehr zu" title={title} id="details-info">
        <div className="dialog-actions wrap">
          <SpotButton
            className="hero-btn"
            focusKey="info-season-seen"
            disabled={episodes.length === 0}
            onClick={() => {
              library.setSeasonWatched(true, slug, title, activeSeason, episodes, provider);
              setInfoOpen(false);
            }}
          >
            <Icon name="check" />
            Staffel gesehen
          </SpotButton>
          <SpotButton
            className="hero-btn"
            focusKey="info-season-unseen"
            disabled={episodes.length === 0}
            onClick={() => {
              library.setSeasonWatched(false, slug, title, activeSeason, episodes, provider);
              setInfoOpen(false);
            }}
          >
            <Icon name="close" />
            Staffel ungesehen
          </SpotButton>
          <SpotButton
            className="hero-btn"
            focusKey="info-series-seen"
            disabled={markingSeries || episodes.length === 0}
            onClick={() => void markSeriesSeen()}
          >
            <Icon name="check" />
            {markingSeries ? "Wird markiert …" : "Serie gesehen"}
          </SpotButton>
          <SpotButton
            className="hero-btn"
            focusKey="info-series-reset"
            disabled={seriesSummary.state === "unseen"}
            onClick={() => {
              library.resetSeriesProgress(slug, provider);
              setInfoOpen(false);
            }}
          >
            <Icon name="trash" />
            Fortschritt vergessen
          </SpotButton>
        </div>

        <dl className="info-list">
          <dt>Sehstand</dt>
          <dd>{watchStateText(seriesSummary)}</dd>
          {alts.length > 0 ? (<><dt>Auch bekannt als</dt><dd>{alts.slice(0, 4).join(" · ")}</dd></>) : null}
          {years ? (<><dt>Jahre</dt><dd>{years}</dd></>) : null}
          {base.data?.genres.length ? (<><dt>Genres</dt><dd>{base.data.genres.join(" · ")}</dd></>) : null}
          {base.data?.fsk ? (<><dt>Altersfreigabe</dt><dd>FSK {base.data.fsk}</dd></>) : null}
          <dt>Quelle</dt>
          <dd>{PROVIDERS[provider].label} — bestimmt, was abspielbar ist</dd>
          <dt>TMDB</dt>
          <dd>{art.tmdbID ? `Zugeordnet (Kennung ${art.tmdbID})` : "Keine sichere Zuordnung — Daten der Quelle"}</dd>
        </dl>
        <div className="dialog-actions">
          <SpotButton className="hero-btn primary" focusKey="info-close" onClick={() => setInfoOpen(false)}>
            Schließen
          </SpotButton>
        </div>
      </Dialog>
    </Screen>
  );
}

function sameTitles(a: HomeCandidate[], b: HomeCandidate[]): boolean {
  if (a.length !== b.length) return false;
  return a.every((candidate, index) =>
    candidate.title.slug === b[index].title.slug && candidate.title.provider === b[index].title.provider);
}
