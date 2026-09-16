// Der Kalender.
//
//     Heute   Wochenleiste, darunter die Folgen des gewählten Tages
//     Woche   Wochenleiste, darunter alle Tage der Woche nacheinander
//     Monat   Monatsraster mit Anzahl je Tag, darunter der gewählte Tag
//
// Die Daten kommen von den Quellen — was sie veröffentlichen oder
// verfügbar machen. TMDB steuert nur Standbild und Folgentitel bei.
//
// **Keine erfundenen Uhrzeiten.** `airingAt` trägt immer eine Zeit, auch wenn
// die Quelle keine nannte; dann steht dort Mitternacht. Gezeigt wird eine
// Uhrzeit deshalb nur bei `hasTime === true`, sonst allein das Datum.

import {
  NoriClient, PROVIDERS, SCOPES, LIBRARY_SCOPES,
  type AiringEntry, type CatalogProvider, type LibraryScope,
} from "@nori/core";
import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { ChipRow } from "../components/Chips";
import { Menu } from "../components/Overlay";
import { Screen } from "../components/Screen";
import { EmptyState, ErrorState } from "../components/States";
import {
  addMonths,
  Artwork,
  dayKeyOf,
  dayNumber,
  Icon,
  longDayLabel,
  monthGrid,
  monthLabel,
  sameMonth,
  tmdb,
  useAsync,
  useData,
  useLibrary,
  usePersistentState,
  WEEKDAY_SHORT,
  weekOf,
} from "@nori/app";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotButton } from "../navigation/Spot";
import { focusElement } from "../navigation/engine";

const ROUTE = "calendar";
type Mode = "today" | "week" | "month";

function timeOf(ms: number): string {
  try {
    return new Intl.DateTimeFormat("de-DE", { timeZone: "Europe/Berlin", hour: "2-digit", minute: "2-digit" })
      .format(new Date(ms));
  } catch {
    return "";
  }
}

export function CalendarPage() {
  const { calendar } = useData();
  const library = useLibrary();
  const navigate = useNavigate();
  const today = dayKeyOf(Date.now());
  const [mode, setMode] = usePersistentState<Mode>("calendar.mode", "today");
  const [selected, setSelected] = usePersistentState("calendar.day", today);
  const [scopeMenu, setScopeMenu] = useState(false);

  const providers = useMemo<CatalogProvider[]>(() => {
    const scope = library.state.scope;
    return scope === "aniworld" ? ["aniworld"] : scope === "all" ? ["aniworld", "serienstream"] : ["serienstream"];
  }, [library.state.scope]);

  const data = useAsync<AiringEntry[]>(
    async (force) => {
      const results = await Promise.allSettled(providers.map((provider) => calendar(provider, force)));
      const entries = results.flatMap((result) =>
        (result.status === "fulfilled" ? [...result.value.upcoming, ...result.value.recent] : []));
      if (entries.length === 0) {
        const failure = results.find((result) => result.status === "rejected");
        if (failure && failure.status === "rejected") throw failure.reason as Error;
      }
      const seen = new Set<string>();
      return entries
        .filter((entry) => {
          const key = `${entry.provider}|${entry.slug}|${entry.season}|${entry.episode}|${entry.dayKey}|${entry.languages.join()}`;
          if (seen.has(key)) return false;
          seen.add(key);
          return true;
        })
        .sort((a, b) => a.airingAt - b.airingAt);
    },
    [providers.join(",")],
  );

  const byDay = useMemo(() => {
    const map = new Map<string, AiringEntry[]>();
    for (const entry of data.data ?? []) {
      const list = map.get(entry.dayKey) ?? [];
      list.push(entry);
      map.set(entry.dayKey, list);
    }
    return map;
  }, [data.data]);

  useEffect(() => {
    if (data.status !== "ready") return undefined;
    return restoreFocusSoon(ROUTE, ["days", "releases", "modes"], {
      initial: `[data-focus-key="day-${selected}"], [data-focus-key="mday-${selected}"]`,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data.status]);

  const week = weekOf(selected);
  const countLabel = (count: number) => `${count} ${count === 1 ? "Folge" : "Folgen"}`;

  const dayButton = (key: string, prefix: "day" | "mday", dim = false) => {
    const count = byDay.get(key)?.length ?? 0;
    return (
      <SpotButton
        key={`${prefix}-${key}`}
        className={`day${key === selected ? " active" : ""}${key === today ? " today" : ""}${dim ? " dim" : ""}`}
        focusRoute={ROUTE}
        focusArea="days"
        focusKey={`${prefix}-${key}`}
        aria-pressed={key === selected}
        aria-label={`${longDayLabel(key)}, ${countLabel(count)}`}
        onClick={() => {
          setSelected(key);
          if (mode === "week") {
            // In der Woche springt der Tag zu seinen Folgen.
            const first = document.querySelector<HTMLElement>(`[data-day-group="${key}"] .release`);
            if (first) focusElement(first);
          }
        }}
      >
        {prefix === "day" ? <small>{WEEKDAY_SHORT[week.indexOf(key)]}</small> : null}
        <strong>{dayNumber(key)}</strong>
        <span className="day-count">{count > 0 ? count : "–"}</span>
      </SpotButton>
    );
  };

  const releaseList = (entries: AiringEntry[]) => (
    <div className="release-list" data-nav-row="">
      {entries.map((entry) => (
        <ReleaseRow
          key={`${entry.provider}|${entry.slug}|${entry.season}|${entry.episode}|${entry.languages.join()}`}
          entry={entry}
          showProvider={library.state.scope === "all"}
          onOpen={() => navigate(`/titel/${entry.provider ?? "aniworld"}/${encodeURIComponent(entry.slug)}`)}
        />
      ))}
    </div>
  );

  let body: JSX.Element;
  if (data.status === "loading" && !data.data) {
    body = <div className="release-list skeleton-list" aria-hidden="true">{[0, 1, 2].map((i) => <div className="release skeleton" key={i} />)}</div>;
  } else if (data.status === "error") {
    body = <ErrorState title="Kalender nicht ladbar" message={data.error ?? "Unbekannter Fehler"} onRetry={() => data.reload(true)} />;
  } else if (mode === "week") {
    const days = week.filter((key) => (byDay.get(key)?.length ?? 0) > 0);
    body = days.length === 0 ? (
      <EmptyState title="Diese Woche nichts eingetragen" message="Die Quellen haben für diese Woche keine Folgen veröffentlicht." />
    ) : (
      <>
        {days.map((key) => (
          <section className="day-group" data-reveal="" data-day-group={key} key={key}>
            <div className="section-head">
              <h2>{key === today ? `Heute · ${longDayLabel(key)}` : longDayLabel(key)}</h2>
              <span>{countLabel(byDay.get(key)?.length ?? 0)}</span>
            </div>
            {releaseList(byDay.get(key) ?? [])}
          </section>
        ))}
      </>
    );
  } else {
    const entries = byDay.get(selected) ?? [];
    body = (
      <section className="day-group" data-reveal="">
        <div className="section-head">
          <h2>{selected === today ? `Heute · ${countLabel(entries.length)}` : `${longDayLabel(selected)} · ${countLabel(entries.length)}`}</h2>
          <span>{selected === today ? longDayLabel(selected) : ""}</span>
        </div>
        {entries.length === 0 ? (
          <EmptyState title="An diesem Tag nichts eingetragen" message="Die Quellen haben für diesen Tag keine Folgen veröffentlicht." />
        ) : releaseList(entries)}
      </section>
    );
  }

  return (
    <Screen
      route={ROUTE}
      eyebrow="Veröffentlichungen"
      title="Kalender"
      className="calendar"
      actions={(
        <>
          <SpotButton className="glassbtn" focusRoute={ROUTE} focusArea="top" focusKey="scope-open" aria-haspopup="dialog" onClick={() => setScopeMenu(true)}>
            <Icon name="filter" />
            {SCOPES[library.state.scope].label}
          </SpotButton>
          <SpotButton className="glassbtn" focusRoute={ROUTE} focusArea="top" focusKey="reload" onClick={() => data.reload(true)}>
            <Icon name="refresh" />
            {data.refreshing ? "Wird geladen …" : "Aktualisieren"}
          </SpotButton>
        </>
      )}
    >
      <ChipRow<Mode>
        label="Ansicht"
        route={ROUTE}
        area="modes"
        value={mode}
        onChange={(next) => {
          setMode(next);
          if (next === "today") setSelected(today);
        }}
        options={[
          { value: "today", label: "Heute" },
          { value: "week", label: "Woche" },
          { value: "month", label: "Monat" },
        ]}
      />

      {mode === "month" ? (
        <section className="month" data-reveal="">
          <div className="month-head" data-nav-row="">
            <SpotButton className="glassbtn" focusRoute={ROUTE} focusArea="days" focusKey="month-prev" onClick={() => setSelected(addMonths(selected, -1))}>
              <Icon name="back" />
              Vormonat
            </SpotButton>
            <h2>{monthLabel(selected)}</h2>
            <SpotButton className="glassbtn" focusRoute={ROUTE} focusArea="days" focusKey="month-next" onClick={() => setSelected(addMonths(selected, 1))}>
              Nächster Monat
              <Icon name="chevronRight" />
            </SpotButton>
          </div>
          <div className="month-grid" data-nav-row="">
            {WEEKDAY_SHORT.map((label) => <div className="month-weekday" key={label}>{label}</div>)}
            {monthGrid(selected).map((key) => dayButton(key, "mday", !sameMonth(key, selected)))}
          </div>
        </section>
      ) : (
        <div className="weekstrip" data-nav-row="">{week.map((key) => dayButton(key, "day"))}</div>
      )}

      {body}

      <Menu<LibraryScope>
        open={scopeMenu}
        onClose={() => setScopeMenu(false)}
        eyebrow="Kalender"
        title="Bereich"
        id="calendar-scope"
        value={library.state.scope}
        options={LIBRARY_SCOPES.map((scope) => ({ value: scope, label: SCOPES[scope].label }))}
        onPick={(scope) => library.setScope(scope)}
      />
    </Screen>
  );
}

function ReleaseRow({ entry, showProvider, onOpen }: { entry: AiringEntry; showProvider: boolean; onOpen(): void }) {
  const provider = entry.provider ?? "aniworld";
  const extras = tmdb.cachedSeason(entry.slug, provider, entry.season)?.episodes[entry.episode] ?? null;
  const cover = entry.coverPath ? NoriClient.coverURL(entry.coverPath, provider) : null;
  const meta = [
    `Staffel ${entry.season}`,
    `Folge ${entry.episode}`,
    entry.languages.length ? entry.languages.join(" · ") : null,
    showProvider ? PROVIDERS[provider].label : null,
  ].filter(Boolean).join(" · ");
  return (
    <SpotButton
      className="release"
      focusRoute={ROUTE}
      focusArea="releases"
      focusKey={`rel-${provider}-${entry.slug}-${entry.season}-${entry.episode}-${entry.dayKey}`}
      onClick={onOpen}
    >
      <span className="card-art rel-thumb">
        <Artwork kind={extras?.still ? "still" : "backdrop"} src={extras?.still} fallback={cover} slug={entry.slug} provider={provider} title={entry.title} />
      </span>
      <span className="rel-copy">
        <span className="rel-title">{entry.title}</span>
        <span className="rel-meta">{meta}</span>
        {extras?.title ? <span className="rel-episode">{extras.title}</span> : null}
      </span>
      {/* Nur eine Uhrzeit, die die Quelle genannt hat. Sonst gar keine — auch kein „ganztägig". */}
      {entry.hasTime === true ? <span className="timepill">{timeOf(entry.airingAt)}</span> : <span />}
    </SpotButton>
  );
}
