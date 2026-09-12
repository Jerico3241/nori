// Der Kalender.
//
// Zwei Ansichten, mehr braucht ein Fernseher nicht: „Heute" und „Woche". Eine
// Monatsansicht wäre auf drei Metern eine Tabelle mit Text in Streichholzgröße.

import { PROVIDERS, formatClock, type AiringEntry, type CatalogProvider } from "@nori/core";
import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { PosterImage } from "../components/PosterImage";
import { ScopeTabs } from "../components/ScopeTabs";
import { EmptyState, ErrorState, RailSkeleton } from "../components/States";
import { useAsync } from "../hooks/useAsync";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { tmdb } from "../services/tmdb";
import { useData } from "../state/data";
import { useLibrary } from "../state/library";

const ROUTE = "calendar";
type View = "today" | "week";

export function CalendarPage() {
  const { calendar } = useData();
  const { state } = useLibrary();
  const navigate = useNavigate();
  const [view, setView] = useState<View>("today");

  const providers = useMemo<CatalogProvider[]>(
    () => (state.scope === "aniworld"
      ? ["aniworld"]
      : state.scope === "all"
        ? ["aniworld", "serienstream"]
        : ["serienstream"]),
    [state.scope],
  );

  const data = useAsync<AiringEntry[]>(
    async (force) => {
      const results = await Promise.allSettled(providers.map((p) => calendar(p, force)));
      const entries = results.flatMap((result) =>
        result.status === "fulfilled" ? [...result.value.upcoming, ...result.value.recent] : []);
      if (entries.length === 0) {
        const reason = results.find((r) => r.status === "rejected");
        if (reason && reason.status === "rejected") {
          throw reason.reason as Error;
        }
      }
      return entries.sort((a, b) => a.airingAt - b.airingAt);
    },
    [providers.join(",")],
  );

  const grouped = useMemo(() => {
    const entries = data.data ?? [];
    const limit = view === "today"
      ? new Date().toISOString().slice(0, 10)
      : null;
    const map = new Map<string, { label: string; items: AiringEntry[] }>();
    for (const entry of entries) {
      if (limit && entry.dayKey !== limit) continue;
      const bucket = map.get(entry.dayKey) ?? { label: entry.dayLabel, items: [] };
      bucket.items.push(entry);
      map.set(entry.dayKey, bucket);
    }
    const days = Array.from(map.entries()).sort((a, b) => a[0].localeCompare(b[0]));
    return view === "week" ? days.slice(0, 7) : days;
  }, [data.data, view]);

  useEffect(() => {
    if (data.status !== "ready") return;
    return restoreFocusSoon(ROUTE, ["days", "views"]);
  }, [data.status, view]);

  return (
    <div className="page calendar">
      <header className="page-head">
        <h1>Kalender</h1>
        <ScopeTabs route={ROUTE} />
      </header>

      <SpotArea className="filter-row" spotlightId="calendar-views">
        {([["today", "Heute"], ["week", "Woche"]] as [View, string][]).map(([value, label]) => (
          <SpotButton
            key={value}
            className={view === value ? "selected" : ""}
            aria-pressed={view === value}
            focusRoute={ROUTE}
            focusArea="views"
            focusKey={`view-${value}`}
            onClick={() => setView(value)}
          >
            {label}
          </SpotButton>
        ))}
        <SpotButton
          focusRoute={ROUTE}
          focusArea="views"
          focusKey="reload"
          onClick={() => data.reload(true)}
        >
          {data.refreshing ? "Wird geladen …" : "Aktualisieren"}
        </SpotButton>
      </SpotArea>

      {data.status === "loading" && !data.data ? (
        <RailSkeleton />
      ) : data.status === "error" ? (
        <ErrorState
          title="Kalender nicht ladbar"
          message={data.error ?? "Unbekannter Fehler"}
          onRetry={() => data.reload(true)}
        />
      ) : grouped.length === 0 ? (
        <EmptyState
          title={view === "today" ? "Heute nichts angekündigt" : "Diese Woche nichts angekündigt"}
          message="Die Quelle hat für diesen Zeitraum keine Folgen eingetragen."
        />
      ) : (
        grouped.map(([dayKey, bucket]) => (
          <section className="calendar-day" key={dayKey}>
            <h2>{bucket.label}</h2>
            <SpotArea className="calendar-list" spotlightId={`calendar-${dayKey}`}>
              {bucket.items.map((entry) => (
                <SpotButton
                  key={`${entry.provider}|${entry.slug}|${entry.season}|${entry.episode}|${entry.languages.join()}`}
                  className="calendar-item"
                  focusRoute={ROUTE}
                  focusArea="days"
                  focusKey={`cal-${entry.slug}-${entry.season}-${entry.episode}`}
                  onClick={() => navigate(
                    `/titel/${entry.provider ?? "aniworld"}/${encodeURIComponent(entry.slug)}`,
                  )}
                >
                  <span className="calendar-time">{timeOf(entry.airingAt)}</span>
                  <span className="calendar-art">
                    <PosterImage
                      slug={entry.slug}
                      provider={entry.provider ?? "aniworld"}
                      title={entry.title}
                      src={entry.coverPath}
                    />
                  </span>
                  <span className="calendar-copy">
                    <strong>{entry.title}</strong>
                    <small>
                      Staffel {entry.season} · Folge {entry.episode}
                      {entry.languages.length ? ` · ${entry.languages.join(", ")}` : ""}
                      {/*
                        Im Bereich „Alle" laufen beide Quellen zusammen, und
                        dieselbe Serie steht dort oft zweimal — einmal je
                        Quelle. Ohne diese Angabe sieht das aus wie ein Fehler
                        statt wie zwei Einträge.
                      */}
                      {state.scope === "all" ? ` · ${PROVIDERS[entry.provider ?? "aniworld"].label}` : ""}
                    </small>
                    {/*
                      Der Folgentitel von TMDB, sofern die Serie schon
                      zugeordnet ist. Ohne Abruf: der Kalender zeigt dutzende
                      Einträge, und der Titel ist hier eine Zugabe, nicht die
                      Auskunft.
                    */}
                    {episodeTitle(entry) ? (
                      <small className="calendar-episode">{episodeTitle(entry)}</small>
                    ) : null}
                  </span>
                </SpotButton>
              ))}
            </SpotArea>
          </section>
        ))
      )}
    </div>
  );
}

/** Uhrzeit in Berliner Zeit — dieselbe, mit der die Quellen rechnen. */
function timeOf(ms: number): string {
  try {
    return new Intl.DateTimeFormat("de-DE", {
      timeZone: "Europe/Berlin", hour: "2-digit", minute: "2-digit",
    }).format(new Date(ms));
  } catch {
    return formatClock(0);
  }
}

/** Der Folgentitel aus dem TMDB-Zwischenspeicher, falls einer dasteht. */
function episodeTitle(entry: AiringEntry): string | null {
  const season = tmdb.cachedSeason(entry.slug, entry.provider ?? "aniworld", entry.season);
  return season?.episodes[entry.episode]?.title ?? null;
}
