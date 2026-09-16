// Mehr → Diagnose.
//
// Jede Zeile ist ein echter Abruf oder eine echte Messung, keine Behauptung:
//
//     AniWorld, Serienstream   Kalender der Quelle holen, Dauer messen
//     Nori-Server              /api/health, sofern eingetragen
//     TMDB                     eine Suche
//     Google Drive             Zustand der Abgleichs-Engine
//     Player                   HLS nativ? Media Source Extensions für hls.js?
//     Persistenz               Schreiben, Lesen, Löschen im Speicher der App
//
// Keine Geheimnisse: kein Schlüssel, kein Token, kein Client-Secret — nur,
// ob etwas vorhanden ist.

import type { CatalogProvider } from "@nori/core";
import { LIBRARY_SCHEMA_VERSION, PROVIDERS } from "@nori/core";
import { useCallback, useEffect, useState } from "react";

import { Screen } from "../../components/Screen";
import { restoreFocusSoon } from "../../navigation/focusMemory";
import { SpotButton } from "../../navigation/Spot";
import { navMetrics } from "../../navigation/metrics";
import { artworkQueueState } from "../../services/artworkQueue";
import { normalizeServerUrl, pingServer } from "../../services/gateway";
import { performanceMode, performanceReason } from "../../services/performance";
import { tmdbSegmentFor, artworkPixelRatio } from "../../services/images";
import { tmdb } from "../../services/tmdb";
import { tmdbState } from "../../services/tmdbStatus";
import { useData } from "../../state/data";
import { useLibrary } from "../../state/library";
import { useSettings } from "../../state/settings";
import { syncStatusLabel, useSync } from "../../state/sync";
import { Info } from "../More";

const ROUTE = "more-diagnose";

type Tone = "ok" | "idle" | "warn" | "error";

interface Check {
  id: string;
  label: string;
  value: string;
  detail: string;
  tone: Tone;
}

function persistenceCheck(): Check {
  const key = "nori.diagnose.probe";
  try {
    const stamp = String(Date.now());
    localStorage.setItem(key, stamp);
    const back = localStorage.getItem(key);
    localStorage.removeItem(key);
    let bytes = 0;
    for (let index = 0; index < localStorage.length; index += 1) {
      const name = localStorage.key(index) ?? "";
      if (name.startsWith("nori.")) bytes += name.length + (localStorage.getItem(name)?.length ?? 0);
    }
    return {
      id: "storage",
      label: "Persistenz",
      value: back === stamp ? "Funktioniert" : "Fehler",
      detail: `Speicher der App · ${Math.round(bytes / 1024)} KB von Nori belegt · Bibliotheksschema v${LIBRARY_SCHEMA_VERSION}`,
      tone: back === stamp ? "ok" : "error",
    };
  } catch (cause) {
    return { id: "storage", label: "Persistenz", value: "Fehler", detail: (cause as Error)?.message ?? "Speicher abgelehnt", tone: "error" };
  }
}

function playerCheck(): Check {
  const video = document.createElement("video");
  const native = video.canPlayType("application/vnd.apple.mpegurl");
  const mse = typeof (window as unknown as { MediaSource?: unknown }).MediaSource !== "undefined";
  return {
    id: "player",
    label: "Player",
    value: native || mse ? "Bereit" : "Kein HLS",
    detail: `HLS nativ: ${native ? "ja" : "nein"} · Media Source (hls.js): ${mse ? "ja" : "nein"} · MP4: ${video.canPlayType("video/mp4") ? "ja" : "nein"}`,
    tone: native || mse ? "ok" : "error",
  };
}

export function DiagnosticsPage() {
  const { gateway, catalog } = useData();
  const { settings } = useSettings();
  const library = useLibrary();
  const sync = useSync();
  const [checks, setChecks] = useState<Record<string, Check>>({});
  const [running, setRunning] = useState(false);

  const put = (check: Check) => setChecks((current) => ({ ...current, [check.id]: check }));

  const run = useCallback(async () => {
    setRunning(true);
    put(persistenceCheck());
    put(playerCheck());

    const providers: CatalogProvider[] = ["aniworld", "serienstream"];
    const providerTasks = providers.map(async (provider) => {
      const label = PROVIDERS[provider].label;
      put({ id: provider, label, value: "Wird geprüft …", detail: "", tone: "idle" });
      const started = Date.now();
      const slice = catalog(provider);
      try {
        const payload = await gateway.calendar(provider, true);
        put({
          id: provider,
          label,
          value: "Erreichbar",
          detail: `Kalender in ${Date.now() - started} ms · ${payload.upcoming.length + payload.recent.length} Einträge · Katalog: ${slice.status === "ready" ? `${slice.items.length} Titel` : slice.status}`,
          tone: "ok",
        });
      } catch (cause) {
        put({ id: provider, label, value: "Fehler", detail: (cause as Error)?.message ?? "nicht erreichbar", tone: "error" });
      }
    });

    const serverTask = (async () => {
      const base = settings.transport === "server" ? normalizeServerUrl(settings.serverUrl) : "";
      if (!base) {
        put({ id: "server", label: "Nori-Server", value: "Nicht eingetragen", detail: "Der Fernseher ruft die Quellen direkt ab.", tone: "idle" });
        return;
      }
      try {
        const info = await pingServer(base);
        put({ id: "server", label: "Nori-Server", value: "Erreichbar", detail: `Version ${info.version} · TMDB ${info.tmdb ? "ja" : "nein"}`, tone: "ok" });
      } catch (cause) {
        put({ id: "server", label: "Nori-Server", value: "Fehler", detail: (cause as Error)?.message ?? "nicht erreichbar", tone: "error" });
      }
    })();

    const tmdbTask = (async () => {
      put({ id: "tmdb", label: "TMDB", value: "Wird geprüft …", detail: "", tone: "idle" });
      const { status, ms } = await tmdb.probe();
      const state = tmdbState(tmdb.diagnostics());
      const d = tmdb.diagnostics();
      put({
        id: "tmdb",
        label: "TMDB",
        value: state.label,
        detail: `${status === "ok" ? `Antwort in ${ms} ms` : state.detail} · ${d.titles} Titel zugeordnet · ${d.misses} ohne Treffer`,
        tone: state.tone,
      });
    })();

    await Promise.allSettled([...providerTasks, serverTask, tmdbTask]);
    setRunning(false);
  }, [catalog, gateway, settings.serverUrl, settings.transport]);

  useEffect(() => {
    void run();
    // Einmal beim Öffnen; danach über den Knopf.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => restoreFocusSoon(ROUTE, ["diagnose"], { initial: '[data-focus-key="diagnose-run"]', ready: true }), []);

  const order = ["aniworld", "serienstream", "server", "tmdb", "player", "storage"];
  const nav = navMetrics();
  const queue = artworkQueueState();
  const driveTone: Tone = sync.status === "idle" ? "ok" : sync.status === "error" ? "error" : "idle";

  return (
    <Screen
      route={ROUTE}
      eyebrow="Mehr"
      title="Diagnose"
      className="more-sub"
      actions={(
        <SpotButton className="glassbtn" focusRoute={ROUTE} focusArea="diagnose" focusKey="diagnose-run" disabled={running} onClick={() => void run()}>
          {running ? "Prüfung läuft …" : "Erneut prüfen"}
        </SpotButton>
      )}
    >
      <div className="settings-grid single">
        <section className="setting-card" data-nav-row="" aria-label="Prüfungen">
          <h3>Zustand</h3>
          {order.map((id) => checks[id]).filter((check): check is Check => Boolean(check)).map((check) => (
            <Info key={check.id} label={check.label} hint={check.detail} value={check.value} tone={check.tone} />
          ))}
          <Info
            label="Google Drive"
            hint={sync.isConfigured
              ? `Abgleich ${sync.lastSuccessfulSync ? `zuletzt ${new Date(sync.lastSuccessfulSync).toLocaleString("de-DE")}` : "noch nie gelaufen"}`
                + ` · Zugang ${sync.diagnostics.origin === "build" ? "aus dem Build" : "aus einer früheren Fassung"}`
              : "Diese Fassung wurde ohne Google-Abgleich gebaut"}
            value={syncStatusLabel(sync)}
            tone={driveTone}
          />
          <Info
            label="Bibliothek"
            hint={`Kennung dieses Geräts ${library.state.deviceId ? "vorhanden" : "fehlt"} · ${library.state.favorites.length} gemerkt`}
            value={`${Object.keys(library.state.progress).length} Folgen`}
            tone="idle"
          />
          <Info label="Bildschirm" hint={`Pixelverhältnis ${window.devicePixelRatio || 1}`} value={`${window.innerWidth} × ${window.innerHeight}`} tone="idle" />
        </section>

        {/*
          * Leistung — Messwerte, keine Schalter.
          *
          * Was hier steht, ist genau das, womit sich „die Navigation ruckelt"
          * überprüfen lässt, ohne einen Rechner an den Fernseher zu hängen:
          * wie lange ein Tastendruck braucht, wie viel dafür vermessen wurde
          * und in welcher Auflösung Bilder geholt werden. Eingestellt wird
          * nichts davon hier, sondern unter Mehr → Darstellung → Leistung.
          */}
        <section className="setting-card" data-nav-row="" aria-label="Leistung">
          <h3>Leistung</h3>
          <Info
            label="Modus"
            hint={performanceReason()}
            value={performanceMode() === "lean" ? "Optimiert" : "Normal"}
            tone="idle"
          />
          <Info
            label="Fokuslatenz"
            hint={`${nav.moves} Tastendrücke · davon Zielsuche zuletzt ${nav.searchMs.toFixed(1)} ms · schlechtester ${nav.worstMs.toFixed(0)} ms`}
            value={nav.moves > 0 ? `${nav.averageMs.toFixed(1)} ms im Mittel` : "noch nicht gemessen"}
            tone={nav.moves === 0 ? "idle" : nav.averageMs < 50 ? "ok" : nav.averageMs < 100 ? "warn" : "error"}
          />
          <Info
            label="Vermessene Elemente"
            hint={`${nav.cached} aus dem Zwischenspeicher · ${nav.fullScans} vollständige Durchläufe · ${nav.invalidations} Verwürfe`}
            value={`${nav.measured} Messungen`}
            tone="idle"
          />
          <Info
            label="Artwork"
            hint={`Poster ${tmdbSegmentFor("poster")} · Kopfbild ${tmdbSegmentFor("backdropHero")} · Schriftzug ${tmdbSegmentFor("logo")}`}
            value={`Faktor ${artworkPixelRatio().toFixed(2)}`}
            tone="idle"
          />
          <Info
            label="Bildabrufe"
            hint={`höchstens ${queue.limit} gleichzeitig`}
            value={`${queue.running} laufen · ${queue.waiting} warten`}
            tone="idle"
          />
        </section>
      </div>
    </Screen>
  );
}
