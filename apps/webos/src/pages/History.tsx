// Mehr → Verlauf: zuletzt Gesehenes mit Fortschritt, direkt fortsetzbar.
//
// Breite Zeilen wie im Kalender — eine Folge, kein Poster. Ohne Abruf je
// Eintrag: Standbilder und Folgentitel stehen dort, wo die Detailseite sie
// schon geladen hat.

import { formatClock, progressPercent, providerFromPath, resumePosition, type CatalogProvider } from "@nori/core";
import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { Artwork } from "../components/Artwork";
import { Icon } from "../components/Icon";
import { Dialog } from "../components/Overlay";
import { Screen } from "../components/Screen";
import { EmptyState } from "../components/States";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotButton } from "../navigation/Spot";
import { tmdb } from "../services/tmdb";
import { useLibrary } from "../state/library";

const ROUTE = "history";

export function HistoryPage() {
  const library = useLibrary();
  const navigate = useNavigate();
  const [confirm, setConfirm] = useState(false);

  const entries = useMemo(
    () => Object.values(library.state.progress).sort((a, b) => b.updatedAt - a.updatedAt).slice(0, 60),
    [library.state.progress],
  );

  useEffect(() => restoreFocusSoon(ROUTE, ["list"], { initial: ".release-list .spottable", ready: true }), []);

  return (
    <Screen
      route={ROUTE}
      eyebrow="Mehr"
      title="Verlauf"
      className="history"
      actions={entries.length > 0 ? (
        <SpotButton className="glassbtn" focusRoute={ROUTE} focusArea="top" focusKey="clear" onClick={() => setConfirm(true)}>
          <Icon name="trash" />
          Verlauf leeren
        </SpotButton>
      ) : null}
    >
      {entries.length === 0 ? (
        <EmptyState title="Noch nichts angesehen" message="Sobald eine Folge läuft, steht sie hier mit ihrem Fortschritt." />
      ) : (
        <div className="release-list" data-nav-row="">
          {entries.map((item) => {
            const provider = item.provider ?? providerFromPath(item.episodePath);
            const percent = progressPercent(item);
            const extras = tmdb.cachedSeason(item.slug, provider, item.season)?.episodes[item.episode] ?? null;
            return (
              <SpotButton
                key={`${provider}|${item.episodePath}`}
                className="release"
                focusRoute={ROUTE}
                focusArea="list"
                focusKey={`hist-${provider}-${item.episodePath}`}
                onClick={() => navigate(
                  `/player/${provider}/${encodeURIComponent(item.slug)}`
                  + `?season=${encodeURIComponent(item.season)}&episode=${item.episode}`
                  + `&path=${encodeURIComponent(item.episodePath)}`
                  + `&at=${library.state.resumeEnabled ? Math.floor(resumePosition(item)) : 0}`,
                )}
              >
                <span className="card-art rel-thumb">
                  <Artwork kind={extras?.still ? "still" : "backdrop"} src={extras?.still} slug={item.slug} provider={provider} title={item.title || item.slug} passive />
                  {percent > 0 && percent < 100 ? <span className="card-progress"><i style={{ width: `${percent}%` }} /></span> : null}
                </span>
                <span className="rel-copy">
                  <span className="rel-title">{item.title || item.slug}</span>
                  <span className="rel-meta">
                    Staffel {item.season} · Folge {item.episode}
                    {episodeLabel(item.slug, provider, item.season, item.episode, item.germanTitle)}
                  </span>
                  <span className="rel-episode">
                    {percent >= 100 ? "Gesehen" : `${formatClock(item.positionSec)} von ${formatClock(item.durationSec)} · ${percent} %`}
                  </span>
                </span>
                <span className="timepill quiet">
                  {new Intl.DateTimeFormat("de-DE", { dateStyle: "medium", timeStyle: "short" }).format(new Date(item.updatedAt))}
                </span>
              </SpotButton>
            );
          })}
        </div>
      )}

      <Dialog open={confirm} onClose={() => setConfirm(false)} eyebrow="Verlauf" title="Verlauf leeren?" id="history-confirm" initial='[data-focus-key="history-cancel"]'>
        <p className="dialog-text">
          Der Fortschritt aller Folgen wird gelöscht. Mit Google Drive gilt das für alle Geräte. Die Merkliste bleibt.
        </p>
        <div className="dialog-actions">
          <SpotButton className="hero-btn" focusKey="history-cancel" onClick={() => setConfirm(false)}>Abbrechen</SpotButton>
          <SpotButton
            className="hero-btn primary"
            focusKey="history-confirm"
            onClick={() => {
              library.clearProgress();
              setConfirm(false);
            }}
          >
            Verlauf leeren
          </SpotButton>
        </div>
      </Dialog>
    </Screen>
  );
}

/** Der Folgentitel: die Quelle zuerst, TMDB als Lückenfüller. */
function episodeLabel(slug: string, provider: CatalogProvider, season: string, episode: number, germanTitle: string): string {
  if (germanTitle) return ` · ${germanTitle}`;
  const fromTmdb = tmdb.cachedSeason(slug, provider, season)?.episodes[episode]?.title;
  return fromTmdb ? ` · ${fromTmdb}` : "";
}
