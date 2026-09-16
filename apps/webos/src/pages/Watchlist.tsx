// Die Merkliste.
//
//     Seitenkopf   Deine Bibliothek · Merkliste · Suche · Bearbeiten
//     Übersicht    Gespeichert · Angefangen · Gesehen — über die ganze Liste
//     Chips        Alle · Ungesehen · Angefangen · Gesehen
//     Raster       Poster mit Fortschritt
//
// Keine Anime/Serien-Reiter und keine Schilder auf den Covern, wie auf iOS.
// Die Liste ist dieselbe wie in den anderen Nori-Apps (`LibraryStore`), kein
// zweites Favoritensystem.
//
// ## Was „gesehen" heißt
//
// Die Regel steht in `config/contract.json` (`rules.watchState`):
// ungesehen = kein Fortschritt; angefangen = mindestens eine Folge berührt und
// mindestens eine nicht fertig; gesehen = jede bekannte Folge fertig. Wie
// viele Folgen eine Serie insgesamt hat, weiß Nori ohne einen Abruf je Titel
// nicht — „Komplett gesehen" heißt deshalb: alles Begonnene ist beendet.
//
// ## Entfernen
//
// Über „Bearbeiten": dann entfernt OK die fokussierte Karte, statt sie zu
// öffnen. Kein langer Druck und keine Farbtaste, die man erst suchen muss —
// der Modus ist sichtbar und mit einem zweiten Druck wieder aus.

import {
  isEpisodeComplete, normalizeTitle, progressPercent, providerFromPath, type WatchProgress,
} from "@nori/core";
import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { ChipRow } from "../components/Chips";
import { Icon } from "../components/Icon";
import { PosterCard } from "../components/PosterCard";
import { Screen } from "../components/Screen";
import { EmptyState } from "../components/States";
import { useDebounced } from "../hooks/useDebounced";
import { usePersistentState } from "../hooks/usePersistentState";
import { rememberFocus, restoreFocusSoon } from "../navigation/focusMemory";
import { SpotButton } from "../navigation/Spot";
import { performanceProfile } from "../services/performance";
import { useLibrary } from "../state/library";
import { searchScore } from "../state/search";

const ROUTE = "watchlist";
type Filter = "all" | "unseen" | "started" | "seen";
type WatchState = Exclude<Filter, "all">;

interface Entry {
  slug: string;
  title: string;
  provider: ReturnType<ReturnType<typeof useLibrary>["favoriteProvider"]>;
  state: WatchState;
  latest: WatchProgress | null;
}

export function watchStateOf(entries: WatchProgress[]): WatchState {
  const touched = entries.filter((item) => item.positionSec > 0 || item.completed === true);
  if (touched.length === 0) return "unseen";
  return touched.every((item) => isEpisodeComplete(item)) ? "seen" : "started";
}

export function WatchlistPage() {
  const library = useLibrary();
  const navigate = useNavigate();
  const [filter, setFilter] = usePersistentState<Filter>("watchlist.filter", "all");
  const [query, setQuery] = usePersistentState("watchlist.query", "");
  const [editing, setEditing] = useState(false);
  const debounced = useDebounced(query, 250);

  const entries = useMemo<Entry[]>(() => {
    const bySeries = new Map<string, WatchProgress[]>();
    for (const item of Object.values(library.state.progress)) {
      const key = `${item.provider ?? providerFromPath(item.episodePath)}|${item.slug}`;
      const list = bySeries.get(key) ?? [];
      list.push(item);
      bySeries.set(key, list);
    }
    return library.state.favorites.map((slug) => {
      const provider = library.favoriteProvider(slug);
      const progress = bySeries.get(`${provider}|${slug}`) ?? [];
      const latest = [...progress].sort((a, b) => b.updatedAt - a.updatedAt)[0] ?? null;
      return { slug, title: library.state.titles[slug] ?? slug, provider, state: watchStateOf(progress), latest };
    });
  }, [library]);

  const stats = useMemo(() => ({
    saved: entries.length,
    started: entries.filter((entry) => entry.state === "started").length,
    seen: entries.filter((entry) => entry.state === "seen").length,
  }), [entries]);

  const visible = useMemo(() => {
    const needle = normalizeTitle(debounced.trim());
    return entries.filter((entry) =>
      (filter === "all" || entry.state === filter)
      && (needle.length < 2 || searchScore({ title: entry.title, alts: [] }, needle) >= 0));
  }, [entries, filter, debounced]);

  useEffect(() => restoreFocusSoon(ROUTE, ["grid", "chips", "top"], {
    initial: ".catalog-grid .spottable",
    ready: true,
  }), []);

  const subtitle = (entry: Entry): string => {
    if (entry.state === "unseen") return "Noch nicht begonnen";
    if (entry.state === "seen") return "Komplett gesehen";
    const latest = entry.latest;
    if (!latest) return "Angefangen";
    return `S${latest.season} · F${latest.episode} · ${progressPercent(latest)} %`;
  };

  return (
    <Screen
      route={ROUTE}
      eyebrow="Deine Bibliothek"
      title="Merkliste"
      className="watchlist"
      actions={entries.length > 0 ? (
        <>
          <label className="searchbar compact">
            <Icon name="search" />
            <input
              className="spottable search-input"
              data-focus-key="watchlist-search"
              type="search"
              value={query}
              placeholder="Merkliste durchsuchen …"
              aria-label="Merkliste durchsuchen"
              onFocus={() => rememberFocus(ROUTE, "top", "watchlist-search")}
              onChange={(event) => setQuery(event.target.value)}
            />
          </label>
          <SpotButton
            className={`glassbtn${editing ? " on" : ""}`}
            focusRoute={ROUTE}
            focusArea="top"
            focusKey="edit"
            aria-pressed={editing}
            onClick={() => setEditing((value) => !value)}
          >
            <Icon name={editing ? "check" : "trash"} />
            {editing ? "Fertig" : "Bearbeiten"}
          </SpotButton>
        </>
      ) : null}
    >
      {entries.length === 0 ? (
        <EmptyState
          title="Noch nichts gespeichert"
          message="Auf einer Detailseite legt „Merkliste“ einen Titel hier ab. Die Liste ist dieselbe wie in den anderen Nori-Apps."
          action={(
            <SpotButton className="hero-btn primary" focusRoute={ROUTE} focusArea="top" focusKey="open-catalog" onClick={() => navigate("/katalog")}>
              Katalog öffnen
            </SpotButton>
          )}
        />
      ) : (
        <>
          <div className="summary-card">
            <strong>Deine Merkliste</strong>
            <p>Gespeicherte Titel und wo du in jedem stehst.</p>
            <div className="stats">
              <div className="stat"><b>{stats.saved}</b><span>Gespeichert</span></div>
              <div className="stat"><b>{stats.started}</b><span>Angefangen</span></div>
              <div className="stat"><b>{stats.seen}</b><span>Gesehen</span></div>
            </div>
          </div>

          <ChipRow<Filter>
            label="Schnellfilter"
            route={ROUTE}
            area="chips"
            value={filter}
            onChange={setFilter}
            options={[
              { value: "all", label: "Alle" },
              { value: "unseen", label: "Ungesehen" },
              { value: "started", label: "Angefangen" },
              { value: "seen", label: "Gesehen" },
            ]}
          />

          {editing ? (
            <p className="edit-hint">
              <Icon name="info" />
              OK entfernt den Titel von der Merkliste. „Fertig“ beendet das Bearbeiten.
            </p>
          ) : null}

          {visible.length === 0 ? (
            <EmptyState
              title="Keine Titel gefunden"
              message="Passe die Suche oder den Filter an."
              action={(
                <SpotButton className="hero-btn" focusRoute={ROUTE} focusArea="chips" focusKey="reset" onClick={() => { setFilter("all"); setQuery(""); }}>
                  Filter zurücksetzen
                </SpotButton>
              )}
            />
          ) : (
            <div className={`catalog-grid${editing ? " editing" : ""}`} data-nav-row="">
              {visible.map((entry, index) => (
                <PosterCard
                  key={entry.slug}
                  slug={entry.slug}
                  provider={entry.provider}
                  title={entry.title}
                  subtitle={subtitle(entry)}
                  percent={entry.state === "seen" ? 100 : entry.state === "started" && entry.latest ? progressPercent(entry.latest) : 0}
                  focusRoute={ROUTE}
                  focusArea="grid"
                  focusKey={`fav-${entry.slug}`}
                  eager={index < performanceProfile().eagerCards}
                  overlay={editing ? <span className="card-remove"><Icon name="trash" />Entfernen</span> : null}
                  onSelect={editing
                    ? () => library.toggleFavorite(entry.slug, entry.title, entry.provider)
                    : undefined}
                />
              ))}
            </div>
          )}
        </>
      )}
    </Screen>
  );
}
