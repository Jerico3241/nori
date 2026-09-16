// Einstellungen.
//
//     Wiedergabe      Autoplay, Fortsetzen, Sprache, Hoster, Tempo, Sprung
//     Darstellung     Bereich, Animationen, Leistung
//     Abgleich        Google Drive: Zustand, anmelden, abgleichen, trennen
//     Nori            Quelle der Daten, TMDB, Daten, Version
//
// Nur Einstellungen, die etwas tun. Kein „Qualität": die Hoster liefern je
// Folge einen einzigen Stream, und hls.js wählt bei mehreren Stufen selbst
// nach Bandbreite. Ein Schalter ohne Wirkung wäre eine Behauptung.

import {
  artworkPixelRatio, performanceMode, performanceReason, tmdbSegmentFor, useData,
  useLibrary, useSettings, useTick, type PerformanceSetting, type TmdbMode, type TransportMode,
} from "@nori/app";
import { LIBRARY_SCHEMA_VERSION, LIBRARY_SCOPES, PLAYBACK_SPEEDS, SCOPES } from "@nori/core";
import { useState } from "react";

import { bridge, inShell } from "../bridge";
import { Dialog, Row, Select, Toggle } from "../components/ui";
import { syncStatusLabel, useSync } from "../state/sync";

const LANGUAGES = [
  { value: "DE", label: "Deutsch" },
  { value: "GerSub", label: "Deutsche Untertitel" },
  { value: "EN", label: "Englisch" },
];

const HOSTERS = ["", "VOE", "Vidmoly", "Vidoza", "Lulustream", "Speedfiles", "Filemoon", "Doodstream"];

export function SettingsPage() {
  const library = useLibrary();
  const { settings, update, reset } = useSettings();
  const { tmdbRoute } = useData();
  const sync = useSync();
  const [revokeOpen, setRevokeOpen] = useState(false);
  const [importText, setImportText] = useState<string | null>(null);
  const [importNote, setImportNote] = useState<string | null>(null);
  // „Zuletzt vor 3 Minuten" soll auch nach drei Minuten stimmen.
  useTick(30_000, sync.lastSuccessfulSync !== null);

  const versions = bridge()?.versions;

  return (
    <div className="page">
      <div className="section-head"><h2>Einstellungen</h2></div>

      <div className="settings">
        <section className="card-panel" aria-label="Wiedergabe">
          <h3>Wiedergabe</h3>
          <Toggle
            label="Autoplay"
            hint="Nächste Folge automatisch starten"
            value={library.state.autoplayNext}
            onChange={(value) => library.setPreference({ autoplayNext: value })}
          />
          <Toggle
            label="Fortsetzen"
            hint="An der letzten Stelle weiter — ab 8 Sekunden"
            value={library.state.resumeEnabled}
            onChange={(value) => library.setPreference({ resumeEnabled: value })}
          />
          <Select
            label="Bevorzugte Sprache"
            hint="Wird gewählt, wenn die Folge sie anbietet"
            value={library.state.langPref}
            options={LANGUAGES}
            onChange={(value) => library.setPreference({ langPref: value })}
          />
          <Select
            label="Bevorzugter Hoster"
            hint="Zuerst probiert, danach die Rangfolge"
            value={library.state.hosterPref}
            options={HOSTERS.map((name) => ({ value: name, label: name || "Automatisch" }))}
            onChange={(value) => library.setPreference({ hosterPref: value })}
          />
          <Select
            label="Geschwindigkeit"
            value={String(library.state.playbackSpeed)}
            options={PLAYBACK_SPEEDS.map((speed) => ({
              value: String(speed),
              label: `${speed.toLocaleString("de-DE")}×`,
            }))}
            onChange={(value) => library.setPreference({ playbackSpeed: Number(value) })}
          />
          <Select
            label="Sprung mit ← →"
            value={String(settings.seekStep)}
            options={[5, 10, 15, 30].map((step) => ({ value: String(step), label: `${step} Sekunden` }))}
            onChange={(value) => update({ seekStep: Number(value) })}
          />
          <Select
            label="Bedienung ausblenden nach"
            value={String(settings.controlsTimeout)}
            options={[3, 4, 5, 8].map((seconds) => ({ value: String(seconds), label: `${seconds} Sekunden` }))}
            onChange={(value) => update({ controlsTimeout: Number(value) })}
          />
        </section>

        <section className="card-panel" aria-label="Darstellung">
          <h3>Darstellung</h3>
          <Select
            label="Bereich"
            hint="Gilt für Start, Katalog und Kalender"
            value={library.state.scope}
            options={LIBRARY_SCOPES.map((scope) => ({ value: scope, label: SCOPES[scope].label }))}
            onChange={(value) => library.setScope(value)}
          />
          <Toggle
            label="Animationen reduzieren"
            hint="Weniger Bewegung — hilft auch bei Bewegungsempfindlichkeit"
            value={settings.reduceEffects}
            onChange={(value) => update({ reduceEffects: value })}
          />
          <Select<PerformanceSetting>
            label="Leistung"
            hint={settings.performance === "auto"
              ? `Automatisch — gerade ${performanceMode() === "lean" ? "optimiert" : "normal"} (${performanceReason()})`
              : "Feste Stufe statt Messung"}
            value={settings.performance}
            options={[
              { value: "auto", label: "Automatisch" },
              { value: "full", label: "Normal" },
              { value: "lean", label: "Optimiert" },
            ]}
            onChange={(value) => update({ performance: value })}
          />
        </section>

        <section className="card-panel" aria-label="Abgleich">
          <h3>Abgleich</h3>
          <Row
            label="Google Drive"
            hint="Merkliste, Verlauf, Fortschritt und Einstellungen — keine Videos"
            value={<span className={`badge ${sync.status === "error" ? "error" : sync.signedIn ? "ok" : ""}`}>
              {syncStatusLabel(sync)}
            </span>}
          />
          {!sync.isConfigured ? (
            <Row
              label="Nicht verfügbar"
              hint="Diese Fassung wurde ohne Google-Zugangsdaten gebaut. Ohne sie gibt es keinen Abgleich; die Bibliothek bleibt lokal vollständig."
            />
          ) : !sync.signedIn ? (
            <Row
              label="Mit Google anmelden"
              hint="Öffnet den Systembrowser. Nori bekommt Zugriff auf seinen eigenen Ordner, auf nichts sonst."
              value={sync.signingIn ? "läuft …" : ""}
              onClick={sync.signingIn ? undefined : sync.connect}
            />
          ) : (
            <>
              <Row
                label="Jetzt abgleichen"
                hint={sync.lastSuccessfulSync
                  ? `Zuletzt ${relativeTime(sync.lastSuccessfulSync)}`
                  : "Noch nicht abgeglichen"}
                onClick={sync.syncNow}
                icon="refresh"
              />
              <Toggle
                label="Mit Fernseher teilen"
                hint="Legt denselben Stand zusätzlich im sichtbaren Ordner „Nori“ ab. Nur so kommt der Fernseher daran."
                value={sync.shareWithTv}
                onChange={sync.setShareWithTv}
              />
              <Row
                label="Dieses Gerät trennen"
                hint="Hört auf abzugleichen. In Drive wird nichts gelöscht, andere Geräte machen weiter."
                onClick={sync.disconnect}
              />
              <Row
                label="Google-Zugriff widerrufen"
                hint="Zieht die Berechtigung für alle Geräte an diesem Konto zurück."
                onClick={() => setRevokeOpen(true)}
              />
            </>
          )}
          {sync.lastError ? <Row label="Letzter Fehler" hint={sync.lastError} /> : null}
        </section>

        <section className="card-panel" aria-label="Nori">
          <h3>Nori</h3>
          <Select<TransportMode>
            label="Quelle der Daten"
            hint={inShell()
              ? "„Im Programm“ holt AniWorld und Serienstream direkt — ohne Server, ohne Einrichtung."
              : "Im Browser gibt es den Weg über das Programm nicht."}
            value={settings.transport}
            // Im Programm gibt es „direkt aus dem Fenster“ nicht: das Fenster
            // lädt von `file://` und kommt an keine fremde Adresse. Beide Wege
            // laufen im Hauptprozess — der eine liest die Quellen selbst, der
            // andere fragt einen Nori-Server.
            options={inShell()
              ? [
                { value: "local" as const, label: "Im Programm" },
                { value: "server" as const, label: "Über einen Nori-Server" },
              ]
              : [
                { value: "direct" as const, label: "Direkt aus dem Fenster" },
                { value: "server" as const, label: "Über einen Nori-Server" },
              ]}
            onChange={(value) => update({ transport: value })}
          />
          {settings.transport === "server" ? (
            <div className="row">
              <span className="row-copy">
                <b>Serveradresse</b>
                <small>Etwa 192.168.1.20:8730</small>
              </span>
              <span className="row-value">
                <input
                  className="select"
                  style={{ width: "12rem" }}
                  value={settings.serverUrl}
                  placeholder="192.168.1.20:8730"
                  aria-label="Serveradresse"
                  onChange={(event) => update({ serverUrl: event.target.value })}
                />
              </span>
            </div>
          ) : null}
          <Select<TmdbMode>
            label="TMDB"
            hint={`Titelbilder, Beschreibungen und Bewertungen · gerade ${tmdbRoute.effective}`}
            value={settings.tmdbMode}
            options={[
              { value: "direct", label: "Dieser Rechner fragt selbst" },
              { value: "server", label: "Über den Nori-Server" },
              { value: "off", label: "Aus" },
            ]}
            onChange={(value) => update({ tmdbMode: value })}
          />
          <Row
            label="Bibliothek"
            hint={`${library.state.favorites.length} gemerkt · ${Object.keys(library.state.progress).length} Folgen mit Fortschritt · Schema v${LIBRARY_SCHEMA_VERSION}`}
            value={<button
              type="button"
              className="btn"
              onClick={() => {
                void navigator.clipboard.writeText(library.exportJSON()).then(
                  () => setImportNote("In die Zwischenablage kopiert."),
                  () => setImportNote("Die Zwischenablage war nicht erreichbar."),
                );
              }}
            >
              Ausgeben
            </button>}
          />
          <Row
            label="Bibliothek einlesen"
            hint="Nimmt einen fremden Stand dazu — ersetzt nichts. Dieselbe Regel wie beim Geräteabgleich."
            onClick={() => { setImportText(""); setImportNote(null); }}
          />
          <Row
            label="Einstellungen zurücksetzen"
            hint="Nur die Geräteeinstellungen. Merkliste und Verlauf bleiben."
            onClick={reset}
          />
          <Row
            label="Version"
            hint={versions
              ? `Electron ${versions.electron} · Chromium ${versions.chrome} · Node ${versions.node} · ${versions.arch}`
              : "Im Browser"}
            value={__NORI_APP_VERSION__}
          />
          <Row
            label="Artwork"
            hint={`Poster ${tmdbSegmentFor("poster")} · Kopfbild ${tmdbSegmentFor("backdropHero")} · Schriftzug ${tmdbSegmentFor("logo")}`}
            value={`Faktor ${artworkPixelRatio().toFixed(2)}`}
          />
        </section>
      </div>

      <Dialog
        open={revokeOpen}
        title="Google-Zugriff widerrufen?"
        description="Das gilt für alle Geräte an diesem Konto — auch für iPhone, iPad, Mac und Fernseher. Die Dateien in Drive bleiben liegen."
        onClose={() => setRevokeOpen(false)}
        actions={(
          <>
            <button type="button" className="btn" onClick={() => setRevokeOpen(false)}>Abbrechen</button>
            <button
              type="button"
              className="btn danger"
              onClick={() => { sync.revoke(); setRevokeOpen(false); }}
            >
              Widerrufen
            </button>
          </>
        )}
      />

      <Dialog
        open={importText !== null}
        title="Bibliothek einlesen"
        description="Den ausgegebenen Text hier einfügen. Was fehlt, kommt dazu; was es schon gibt, bleibt in der neueren Fassung."
        onClose={() => setImportText(null)}
        actions={(
          <>
            <button type="button" className="btn" onClick={() => setImportText(null)}>Abbrechen</button>
            <button
              type="button"
              className="btn primary"
              onClick={() => {
                try {
                  const added = library.importJSON(importText ?? "");
                  setImportNote(`${added.favorites} gemerkt, ${added.progress} Folgen übernommen.`);
                  setImportText(null);
                } catch (cause) {
                  setImportNote((cause as Error)?.message ?? "Der Text ließ sich nicht lesen.");
                }
              }}
            >
              Einlesen
            </button>
          </>
        )}
      >
        <textarea
          className="select"
          style={{ width: "100%", height: "9rem", padding: "0.5rem", resize: "vertical" }}
          value={importText ?? ""}
          aria-label="Bibliothek als Text"
          onChange={(event) => setImportText(event.target.value)}
        />
      </Dialog>

      {importNote ? (
        <Dialog open title="Hinweis" description={importNote} onClose={() => setImportNote(null)} />
      ) : null}
    </div>
  );
}

/** „vor 3 Minuten" — dieselbe Formulierung wie auf dem Fernseher. */
export function relativeTime(at: number): string {
  const seconds = Math.max(0, Math.round((Date.now() - at) / 1000));
  if (seconds < 45) return "gerade eben";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `vor ${minutes} ${minutes === 1 ? "Minute" : "Minuten"}`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `vor ${hours} ${hours === 1 ? "Stunde" : "Stunden"}`;
  const days = Math.round(hours / 24);
  return `vor ${days} ${days === 1 ? "Tag" : "Tagen"}`;
}
