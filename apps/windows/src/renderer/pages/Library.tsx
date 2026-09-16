// Merkliste, Verlauf und Kalender — drei Listen aus derselben Bibliothek.
//
// Sie stehen zusammen in einer Datei, weil sie sich dieselbe Form teilen:
// Kopfzeile, Liste, Leerzustand. Getrennt wären es dreimal dasselbe Gerüst mit
// anderen Daten.

import {
  Icon, dayKeyOf, longDayLabel, monthLabel, performanceProfile, tmdb, useData, useLibrary, weekOf,
} from "@nori/app";
import {
  PROVIDERS, formatClock, progressPercent, providerFromPath, resumePosition,
  type AiringEntry, type CatalogProvider,
} from "@nori/core";
import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { EmptyState, GridSkeleton, LandscapeCard, PosterCard } from "../components/ui";

// ---------------------------------------------------------------------------
// Merkliste

export function WatchlistPage() {
  const navigate = useNavigate();
  const library = useLibrary();
  const { scopedCatalog } = useData();
  const catalog = scopedCatalog();
  const [editing, setEditing] = useState(false);

  const entries = useMemo(() => library.state.favorites.map((slug) => {
    const provider = library.favoriteProvider(slug);
    const item = catalog.items.find((entry) =>
      entry.slug === slug && (entry.provider ?? "aniworld") === provider);
    const progress = library.continueWatching().find((p) => p.slug === slug) ?? null;
    return {
      slug,
      provider,
      title: item?.title ?? library.state.titles[slug] ?? slug,
      alts: item?.alts ?? [],
      genres: item?.genres ?? [],
      progress,
    };
  }), [library, catalog.items]);

  const eagerCards = performanceProfile().eagerCards * 2;

  return (
    <div className="page">
      <div className="section-head">
        <h2>Merkliste</h2>
        <span>{entries.length} {entries.length === 1 ? "Titel" : "Titel"}</span>
        {entries.length > 0 ? (
          <button
            type="button"
            className={`btn${editing ? " primary" : ""}`}
            style={{ marginLeft: "1rem" }}
            onClick={() => setEditing((value) => !value)}
          >
            <Icon name={editing ? "check" : "trash"} />
            <span>{editing ? "Fertig" : "Bearbeiten"}</span>
          </button>
        ) : null}
      </div>

      {entries.length === 0 ? (
        <EmptyState
          title="Noch nichts gemerkt"
          message="Was du dir merkst, steht hier — auf jedem Gerät, sobald der Abgleich läuft."
          action={(
            <button type="button" className="btn primary" onClick={() => navigate("/katalog")}>
              Zum Katalog
            </button>
          )}
        />
      ) : (
        <div className="grid">
          {entries.map((entry, index) => (
            <PosterCard
              key={`${entry.provider}|${entry.slug}`}
              slug={entry.slug}
              provider={entry.provider}
              title={entry.title}
              alts={entry.alts}
              subtitle={entry.progress
                ? `S${entry.progress.season} · F${entry.progress.episode} · ${progressPercent(entry.progress)} %`
                : entry.genres[0] ?? null}
              percent={entry.progress ? progressPercent(entry.progress) : 0}
              eager={index < eagerCards}
              onSelect={() => {
                if (editing) library.toggleFavorite(entry.slug, entry.title, entry.provider);
                else navigate(`/titel/${entry.provider}/${encodeURIComponent(entry.slug)}`);
              }}
            />
          ))}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Verlauf

export function HistoryPage() {
  const navigate = useNavigate();
  const library = useLibrary();
  const entries = useMemo(
    () => Object.values(library.state.progress).sort((a, b) => b.updatedAt - a.updatedAt),
    [library.state.progress],
  );

  return (
    <div className="page">
      <div className="section-head">
        <h2>Verlauf</h2>
        <span>{entries.length} {entries.length === 1 ? "Folge" : "Folgen"}</span>
        {entries.length > 0 ? (
          <button
            type="button"
            className="btn danger"
            style={{ marginLeft: "1rem" }}
            onClick={() => library.clearProgress()}
          >
            <Icon name="trash" /><span>Fortschritt löschen</span>
          </button>
        ) : null}
      </div>

      {entries.length === 0 ? (
        <EmptyState
          title="Noch nichts angesehen"
          message="Sobald eine Folge läuft, steht sie hier mit ihrem Fortschritt."
        />
      ) : (
        <div className="grid wide">
          {entries.map((item, index) => {
            const provider = item.provider ?? providerFromPath(item.episodePath);
            const still = tmdb.cachedSeason(item.slug, provider, item.season)?.episodes[item.episode]?.still ?? null;
            const percent = progressPercent(item);
            return (
              <LandscapeCard
                key={`${provider}|${item.episodePath}`}
                slug={item.slug}
                provider={provider}
                title={item.title || item.slug}
                still={still}
                subtitle={`S${item.season} · F${item.episode} · ${formatClock(item.positionSec)} von ${formatClock(item.durationSec)}`}
                percent={percent}
                eager={index < 6}
                onSelect={() => navigate(
                  `/player/${provider}/${encodeURIComponent(item.slug)}`
                  + `?season=${encodeURIComponent(item.season)}&episode=${item.episode}`
                  + `&path=${encodeURIComponent(item.episodePath)}`
                  + `&at=${Math.floor(library.state.resumeEnabled ? resumePosition(item) : 0)}`,
                )}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Kalender

export function CalendarPage() {
  const navigate = useNavigate();
  const library = useLibrary();
  const { calendar } = useData();
  const [entries, setEntries] = useState<AiringEntry[] | null>(null);
  const [day, setDay] = useState(() => dayKeyOf(Date.now()));

  const scope = library.state.scope;
  useEffect(() => {
    let cancelled = false;
    const providers: CatalogProvider[] = scope === "aniworld"
      ? ["aniworld"]
      : scope === "all" ? ["aniworld", "serienstream"] : ["serienstream"];
    setEntries(null);
    void Promise.allSettled(providers.map((provider) => calendar(provider))).then((results) => {
      if (cancelled) return;
      setEntries(results.flatMap((result) =>
        result.status === "fulfilled" ? [...result.value.recent, ...result.value.upcoming] : []));
    });
    return () => {
      cancelled = true;
    };
  }, [calendar, scope]);

  const week = useMemo(() => weekOf(day), [day]);
  const byDay = useMemo(() => {
    const map = new Map<string, AiringEntry[]>();
    for (const entry of entries ?? []) {
      const key = entry.dayKey || dayKeyOf(entry.airingAt);
      const list = map.get(key) ?? [];
      list.push(entry);
      map.set(key, list);
    }
    return map;
  }, [entries]);

  const today = byDay.get(day) ?? [];

  return (
    <div className="page">
      <div className="section-head">
        <h2>Kalender</h2>
        <span>{monthLabel(day)}</span>
      </div>

      <div className="chips">
        {week.map((key) => (
          <button
            key={key}
            type="button"
            className={`chip${key === day ? " active" : ""}`}
            onClick={() => setDay(key)}
          >
            {longDayLabel(key)}
            {byDay.has(key) ? ` · ${byDay.get(key)?.length}` : ""}
          </button>
        ))}
      </div>

      {entries === null ? (
        <GridSkeleton count={6} wide />
      ) : today.length === 0 ? (
        <EmptyState
          title="Für diesen Tag ist nichts eingetragen"
          message="Die Quellen melden nur, was sie selbst führen. An einem anderen Tag steht hier meistens mehr."
        />
      ) : (
        <div className="grid wide">
          {today.map((entry, index) => {
            const provider = entry.provider ?? "aniworld";
            const extras = tmdb.cachedSeason(entry.slug, provider, entry.season)?.episodes[entry.episode] ?? null;
            return (
              <LandscapeCard
                key={`${provider}|${entry.slug}|${entry.season}|${entry.episode}`}
                slug={entry.slug}
                provider={provider}
                title={entry.title}
                still={extras?.still ?? null}
                subtitle={[
                  `S${entry.season} · F${entry.episode}`,
                  entry.languages.join(", ") || null,
                  PROVIDERS[provider].label,
                ].filter(Boolean).join(" · ")}
                eager={index < 6}
                onSelect={() => navigate(`/titel/${provider}/${encodeURIComponent(entry.slug)}`)}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}
