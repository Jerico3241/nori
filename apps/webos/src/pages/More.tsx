// Mehr: die Einstellungen als große Karten.
//
//     Wiedergabe         Autoplay, Fortsetzen, Sprache, Hoster, Tempo, Sprung
//     Darstellung        Bereich, Animationen, Leistung
//     Synchronisierung   Google Drive: Zustand, abgleichen, einrichten
//     Nori               TMDB-Zustand, Verbindung, Diagnose, Verlauf, Daten
//
// Nur Einstellungen, die etwas tun. „Qualität" fehlt: die Hoster liefern je
// Folge einen einzigen Stream, und hls.js wählt bei mehreren Stufen selbst
// nach Bandbreite. Ein Schalter ohne Wirkung wäre eine Behauptung.
//
// Jede Zeile ist ein eigener Knopf. Umschalter wechseln mit OK; Zeilen mit
// Auswahl öffnen ein Menü; Zeilen mit „›" führen auf eine Unterseite, aus der
// „Zurück" hierher führt.

import { LIBRARY_SCHEMA_VERSION, LIBRARY_SCOPES, PLAYBACK_SPEEDS, SCOPES } from "@nori/core";
import { useEffect, useState, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";

import { DeviceSignInDialog, relativeTime } from "../components/DeviceSignIn";
import { Icon } from "../components/Icon";
import { Menu, type MenuOption } from "../components/Overlay";
import { Screen } from "../components/Screen";
import { useTick } from "../hooks/useTick";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotButton } from "../navigation/Spot";
import { performanceMode, performanceReason, type PerformanceSetting } from "../services/performance";
import { useTmdbState } from "../services/tmdbStatus";
import { useData } from "../state/data";
import { useLibrary } from "../state/library";
import { useSettings } from "../state/settings";
import { syncStatusLabel, useSync } from "../state/sync";

const ROUTE = "more";

export const LANGUAGES: MenuOption<string>[] = [
  { value: "DE", label: "Deutsch" },
  { value: "GerSub", label: "Deutsche Untertitel" },
  { value: "EN", label: "Englisch" },
];

export const HOSTERS = ["VOE", "Vidmoly", "Vidoza", "Lulustream", "Speedfiles", "Filemoon", "Doodstream"];

type MenuId = "lang" | "hoster" | "speed" | "seek" | "chrome" | "scope" | "performance" | null;

/**
 * Die drei Leistungsstufen.
 *
 * „Automatisch" ist die Voreinstellung und in fast allen Fällen die richtige:
 * Nori misst einmal je Gerät, wie schnell es rechnet, und beobachtet danach,
 * wie lange die Fernbedienung tatsächlich braucht. Die beiden festen Stufen
 * gibt es für den Fall, dass jemand es besser weiß — und damit sich beides auf
 * demselben Gerät vergleichen lässt.
 */
const PERFORMANCE_OPTIONS: MenuOption<PerformanceSetting>[] = [
  { value: "auto", label: "Automatisch", detail: "Nori misst Rechenleistung und Reaktionszeit" },
  { value: "full", label: "Normal", detail: "Volle Darstellung, alle Übergänge" },
  { value: "lean", label: "Optimiert", detail: "Sparsamere Effekte, weniger Bilder gleichzeitig" },
];

const PERFORMANCE_LABEL: Record<PerformanceSetting, string> = {
  auto: "Automatisch",
  full: "Normal",
  lean: "Optimiert",
};

export function MorePage() {
  const navigate = useNavigate();
  const library = useLibrary();
  const sync = useSync();
  const { settings, update } = useSettings();
  const { tmdbRoute } = useData();
  const [menu, setMenu] = useState<MenuId>(null);

  useEffect(() => restoreFocusSoon(ROUTE, ["playback", "display", "sync", "nori"], {
    initial: '[data-focus-key="set-autoplay"]',
    ready: true,
  }), []);

  // Neu gezeichnet wird, wenn TMDB den Zustand wechselt — nicht im Takt.
  const tmdbInfo = useTmdbState();
  // „Zuletzt vor 3 Minuten" soll auch nach drei Minuten auf der Seite stimmen.
  useTick(30_000, sync.lastSuccessfulSync !== null);
  const lang = LANGUAGES.find((entry) => entry.value === library.state.langPref)?.label ?? library.state.langPref;

  return (
    <Screen route={ROUTE} eyebrow="Nori" title="Mehr" className="more">
      <div className="settings-grid">
        <section className="setting-card" data-nav-row="" aria-label="Wiedergabe">
          <h3>Wiedergabe</h3>
          <Toggle area="playback" id="set-autoplay" label="Autoplay" hint="Nächste Folge automatisch starten" value={library.state.autoplayNext} onChange={(value) => library.setPreference({ autoplayNext: value })} />
          <Toggle area="playback" id="set-resume" label="Fortsetzen" hint="An der letzten Stelle weiter — ab 8 Sekunden" value={library.state.resumeEnabled} onChange={(value) => library.setPreference({ resumeEnabled: value })} />
          <Row area="playback" id="set-lang" label="Bevorzugte Sprache" hint="Wird gewählt, wenn die Folge sie anbietet" value={lang} onClick={() => setMenu("lang")} />
          <Row area="playback" id="set-hoster" label="Bevorzugter Hoster" hint="Zuerst probiert, danach die Rangfolge" value={library.state.hosterPref || "Automatisch"} onClick={() => setMenu("hoster")} />
          <Row area="playback" id="set-speed" label="Geschwindigkeit" value={`${library.state.playbackSpeed.toLocaleString("de-DE")}×`} onClick={() => setMenu("speed")} />
          <Row area="playback" id="set-seek" label="Sprung mit ← →" value={`${settings.seekStep} s`} onClick={() => setMenu("seek")} />
          <Row area="playback" id="set-chrome" label="Bedienung ausblenden nach" value={`${settings.controlsTimeout} s`} onClick={() => setMenu("chrome")} />
        </section>

        <section className="setting-card" data-nav-row="" aria-label="Darstellung">
          <h3>Darstellung</h3>
          <Row area="display" id="set-scope" label="Bereich" hint="Gilt für Start, Katalog und Kalender" value={SCOPES[library.state.scope].label} onClick={() => setMenu("scope")} />
          <Toggle area="display" id="set-effects" label="Animationen reduzieren" hint="Weniger Bewegung, flüssiger auf älteren Fernsehern" value={settings.reduceEffects} onChange={(value) => update({ reduceEffects: value })} />
          <Row
            area="display"
            id="set-performance"
            label="Leistung"
            hint={settings.performance === "auto"
              ? `Automatisch — gerade ${performanceMode() === "lean" ? "optimiert" : "normal"} (${performanceReason()})`
              : "Feste Stufe statt Messung"}
            value={PERFORMANCE_LABEL[settings.performance]}
            onClick={() => setMenu("performance")}
          />
        </section>

        <section className="setting-card" data-nav-row="" aria-label="Synchronisierung">
          <h3>Synchronisierung</h3>
          <Info label="Google Drive" hint="Merkliste, Verlauf, Fortschritt und Einstellungen — keine Videos" value={syncStatusLabel(sync)} tone={sync.status === "idle" ? "ok" : sync.status === "error" || sync.needsReauthorization ? "error" : "idle"} />
          {/* Die Anmeldung ist ein Knopf — direkt hier, ohne Umweg über eine Unterseite. */}
          {!sync.isConfigured ? null : sync.needsReauthorization ? (
            <Row area="sync" id="set-sync-connect" label="Erneut anmelden" hint="Die Berechtigung gilt nicht mehr" value="" chevron onClick={() => sync.connect()} />
          ) : sync.status === "disconnected" || sync.status === "authorizing" ? (
            <Row area="sync" id="set-sync-connect" label="Mit Google Drive verbinden" hint="Anmeldung per QR-Code auf dem Smartphone" value="" chevron onClick={() => sync.connect()} />
          ) : (
            <Row area="sync" id="set-sync-now" label="Jetzt synchronisieren" hint={sync.lastSuccessfulSync ? `Zuletzt ${relativeTime(sync.lastSuccessfulSync)}` : "Noch nicht abgeglichen"} value="" chevron onClick={() => sync.syncNow()} />
          )}
          <Row area="sync" id="set-sync" label="Abgleich verwalten" hint={sync.isConfigured ? "Trennen, Zugriff widerrufen, Zustand" : "Diese Fassung wurde ohne Google-Abgleich gebaut"} value="" chevron onClick={() => navigate("/mehr/abgleich")} />
        </section>

        <section className="setting-card" data-nav-row="" aria-label="Nori">
          <h3>Nori</h3>
          <Info label="TMDB" hint={tmdbInfo.detail} value={tmdbInfo.label} tone={tmdbInfo.tone} />
          <Row area="nori" id="set-connection" label="Verbindung & TMDB" hint={tmdbRoute.effective === "server" ? "Über den Nori-Server" : tmdbRoute.effective === "direct" ? "Dieser Fernseher fragt selbst" : "TMDB aus"} value="" chevron onClick={() => navigate("/mehr/verbindung")} />
          <Row area="nori" id="set-diagnose" label="Diagnose" hint="Quellen, TMDB, Drive, Player, Speicher prüfen" value="" chevron onClick={() => navigate("/mehr/diagnose")} />
          <Row area="nori" id="set-history" label="Verlauf" hint={`${Object.keys(library.state.progress).length} Folgen mit Fortschritt`} value="" chevron onClick={() => navigate("/mehr/verlauf")} />
          <Row area="nori" id="set-data" label="Daten" hint="Bibliothek ausgeben, einlesen, zurücksetzen" value="" chevron onClick={() => navigate("/mehr/daten")} />
          <Toggle area="nori" id="set-debug" label="Diagnoseprotokoll" hint="Protokoll mit [Nori:webOS] und Diagnose des Google-Zugangs" value={settings.debug} onChange={(value) => update({ debug: value })} />
          <Info label="Version" hint={`Bibliotheksschema v${LIBRARY_SCHEMA_VERSION}`} value={__NORI_WEBOS_VERSION__} tone="idle" />
        </section>
      </div>

      {sync.pending ? <DeviceSignInDialog /> : null}

      <Menu open={menu === "lang"} onClose={() => setMenu(null)} eyebrow="Wiedergabe" title="Bevorzugte Sprache" id="menu-lang" value={library.state.langPref} options={LANGUAGES} onPick={(value) => library.setPreference({ langPref: value })} />
      <Menu open={menu === "hoster"} onClose={() => setMenu(null)} eyebrow="Wiedergabe" title="Bevorzugter Hoster" id="menu-hoster" value={HOSTERS.find((name) => name.toLowerCase() === library.state.hosterPref.toLowerCase()) ?? null} options={HOSTERS.map((name) => ({ value: name, label: name }))} onPick={(value) => library.setPreference({ hosterPref: value })} />
      <Menu open={menu === "speed"} onClose={() => setMenu(null)} eyebrow="Wiedergabe" title="Geschwindigkeit" id="menu-speed" value={String(library.state.playbackSpeed)} options={PLAYBACK_SPEEDS.map((speed) => ({ value: String(speed), label: `${speed.toLocaleString("de-DE")}×` }))} onPick={(value) => library.setPreference({ playbackSpeed: Number(value) })} />
      <Menu open={menu === "seek"} onClose={() => setMenu(null)} eyebrow="Wiedergabe" title="Sprung mit ← →" id="menu-seek" value={String(settings.seekStep)} options={[5, 10, 15, 30].map((step) => ({ value: String(step), label: `${step} Sekunden` }))} onPick={(value) => update({ seekStep: Number(value) })} />
      <Menu open={menu === "chrome"} onClose={() => setMenu(null)} eyebrow="Wiedergabe" title="Bedienung ausblenden nach" id="menu-chrome" value={String(settings.controlsTimeout)} options={[3, 4, 5, 8].map((seconds) => ({ value: String(seconds), label: `${seconds} Sekunden` }))} onPick={(value) => update({ controlsTimeout: Number(value) })} />
      <Menu open={menu === "performance"} onClose={() => setMenu(null)} eyebrow="Darstellung" title="Leistung" id="menu-performance" value={settings.performance} options={PERFORMANCE_OPTIONS} onPick={(value) => update({ performance: value })} />
      <Menu open={menu === "scope"} onClose={() => setMenu(null)} eyebrow="Darstellung" title="Bereich" id="menu-scope" value={library.state.scope} options={LIBRARY_SCOPES.map((scope) => ({ value: scope, label: SCOPES[scope].label, detail: SCOPES[scope].headline }))} onPick={(value) => library.setScope(value)} />
    </Screen>
  );
}

export function Row({ area, id, label, hint, value, chevron, onClick, route = ROUTE }: {
  area: string;
  id: string;
  label: string;
  hint?: string;
  value: ReactNode;
  chevron?: boolean;
  onClick(): void;
  route?: string;
}) {
  return (
    <SpotButton className="setting-row" focusRoute={route} focusArea={area} focusKey={id} onClick={onClick}>
      <span className="setting-copy">
        <b>{label}</b>
        {hint ? <small>{hint}</small> : null}
      </span>
      <span className="setting-value">
        {value}
        {chevron || value ? <Icon name="chevronRight" /> : null}
      </span>
    </SpotButton>
  );
}

export function Toggle({ area, id, label, hint, value, onChange, route = ROUTE }: {
  area: string;
  id: string;
  label: string;
  hint?: string;
  value: boolean;
  onChange(next: boolean): void;
  route?: string;
}) {
  return (
    <SpotButton
      className="setting-row"
      role="switch"
      aria-checked={value}
      focusRoute={route}
      focusArea={area}
      focusKey={id}
      onClick={() => onChange(!value)}
    >
      <span className="setting-copy">
        <b>{label}</b>
        {hint ? <small>{hint}</small> : null}
      </span>
      <span className="setting-value">
        <span className="toggle-text">{value ? "An" : "Aus"}</span>
        <span className={`toggle${value ? " on" : ""}`} aria-hidden="true" />
      </span>
    </SpotButton>
  );
}

/** Eine Zeile ohne Handlung: nur Auskunft, deshalb nicht fokussierbar. */
export function Info({ label, hint, value, tone }: {
  label: string;
  hint?: string;
  value: ReactNode;
  tone: "ok" | "idle" | "warn" | "error";
}) {
  return (
    <div className="setting-row info">
      <span className="setting-copy">
        <b>{label}</b>
        {hint ? <small>{hint}</small> : null}
      </span>
      <span className={`status-pill ${tone}`}>{value}</span>
    </div>
  );
}
