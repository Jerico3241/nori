// Verlauf: zuletzt Gesehenes mit Fortschritt, direkt fortsetzbar.

import { providerFromPath, progressPercent, formatClock } from "@nori/core";
import { useEffect, useMemo } from "react";
import { useNavigate } from "react-router-dom";

import { PosterImage } from "../components/PosterImage";
import { EmptyState } from "../components/States";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { useLibrary } from "../state/library";
import { Icon } from "../components/Icon";

const ROUTE = "history";

export function HistoryPage() {
  const library = useLibrary();
  const navigate = useNavigate();

  // Fortschritt zuerst — der sagt, wo jemand tatsächlich steht. Danach die
  // reinen Aufrufe aus `recents`, die kein Weiterschauen bedeuten.
  const entries = useMemo(() => {
    const progress = Object.values(library.state.progress)
      .sort((a, b) => b.updatedAt - a.updatedAt)
      .slice(0, 60);
    return progress;
  }, [library.state.progress]);

  useEffect(() => {
    if (entries.length === 0) return;
    return restoreFocusSoon(ROUTE, ["list"]);
  }, [entries.length]);

  return (
    <div className="page history">
      <header className="page-head">
        <h1>Verlauf</h1>
        <SpotArea className="filter-row" spotlightId="history-actions">
          {entries.length > 0 ? (
            <SpotButton
              focusRoute={ROUTE}
              focusArea="actions"
              focusKey="clear-progress"
              onClick={() => library.clearProgress()}
            >
              Verlauf leeren
            </SpotButton>
          ) : null}
        </SpotArea>
      </header>

      {entries.length === 0 ? (
        <EmptyState
          title="Noch nichts angesehen"
          message="Sobald eine Folge läuft, steht sie hier mit ihrem Fortschritt."
        />
      ) : (
        <SpotArea className="history-list" spotlightId="history-list">
          {entries.map((item) => {
            const provider = item.provider ?? providerFromPath(item.episodePath);
            const percent = progressPercent(item);
            return (
              <SpotButton
                key={`${provider}|${item.episodePath}`}
                className="history-item"
                focusRoute={ROUTE}
                focusArea="list"
                focusKey={`hist-${provider}-${item.episodePath}`}
                onClick={() => navigate(
                  `/player/${provider}/${encodeURIComponent(item.slug)}`
                  + `?season=${encodeURIComponent(item.season)}&episode=${item.episode}`
                  + `&path=${encodeURIComponent(item.episodePath)}`,
                )}
              >
                <span className="history-art">
                  <PosterImage
                    slug={item.slug}
                    provider={provider}
                    title={item.title || item.slug}
                  />
                </span>
                <span className="history-copy">
                  <strong>{item.title || item.slug}</strong>
                  <small>
                    Staffel {item.season} · Folge {item.episode}
                    {item.germanTitle ? ` · ${item.germanTitle}` : ""}
                  </small>
                  <span className="history-progress">
                    <i style={{ width: `${percent}%` }} />
                  </span>
                  <small className="muted">
                    {percent >= 100 ? "Gesehen" : `${formatClock(item.positionSec)} von ${formatClock(item.durationSec)} · ${percent} %`}
                    {" · "}
                    {new Intl.DateTimeFormat("de-DE", { dateStyle: "medium", timeStyle: "short" })
                      .format(new Date(item.updatedAt))}
                  </small>
                </span>
                <span className="history-play"><Icon name="play" /></span>
              </SpotButton>
            );
          })}
        </SpotArea>
      )}
    </div>
  );
}
