// Der Einstiegspunkt des Fensters.
//
// Die Reihenfolge ist Absicht:
//
// 1. **Plattform anmelden.** Alles darunter — Bildgrößen, Hintergrundarbeit,
//    Leistungsmodus — fragt von da an sie und nie das Betriebssystem direkt.
// 2. **Zugang anmelden.** Der Weg in den Hauptprozess, bevor die erste
//    Anfrage gestellt wird. Auch TMDB nimmt ihn.
// 3. **Leistungsmodus setzen**, bevor gezeichnet wird: sonst entstünde die
//    Oberfläche einmal voll und gleich darauf sparsam.
// 4. **Dem Hauptprozess den Weg sagen** — und darauf warten. Danach erst
//    zeichnen: sonst holt die erste Anfrage ihre Daten noch auf dem
//    voreingestellten Weg, und wer einen Nori-Server eingetragen hat, sähe
//    beim Start einmal an ihm vorbei.
// 5. Zeichnen.
// 6. Messen — in einer Lücke danach, nicht davor.

import {
  error, installPerformanceMode, installPlatform, log, readSettings, registerLocalGateway,
  registerTmdbHttpClient, startPerformanceProbe,
} from "@nori/app";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { App } from "./App";
import { BridgeHttpClient, ShellGateway, bridge, inShell } from "./bridge";
import { WINDOWS_DEFAULTS, installInputTracking, windowsPlatform } from "./platform";
import "./styles/theme.css";
import "./styles/app.css";
import "./styles/player.css";

const container = document.getElementById("root");
if (!container) throw new Error("Kein #root im Dokument");

/*
 * Unbehandelte Fehler ins Protokoll.
 *
 * Absichtlich **nur** protokollieren: jede Ansicht hat ihre eigenen Enden
 * (lädt, da, kaputt), und ein einzelner gescheiterter Bildabruf darf sie nicht
 * ersetzen.
 */
window.addEventListener("unhandledrejection", (event) => {
  error("app", "Unbehandelte Zusage", (event.reason as Error)?.message ?? event.reason);
});
window.addEventListener("error", (event) => {
  error("app", "Unbehandelter Fehler", event.message, event.filename, event.lineno);
});

installPlatform(windowsPlatform);
installInputTracking();

const api = bridge();
if (api) {
  registerLocalGateway(new ShellGateway(api));
  registerTmdbHttpClient(new BridgeHttpClient(api));
}

const settings = readSettings(WINDOWS_DEFAULTS);
installPerformanceMode(settings.performance);

// Der Hauptprozess kennt die Einstellungen nicht — sie liegen im Fenster.
// Deshalb hier, einmal vor dem ersten Rendern. Spätere Änderungen meldet
// `App` nach.
if (api) await api.gateway.configure(settings.transport, settings.serverUrl);

log(
  "app", "Start", inShell() ? "Nori für Windows" : "Browser",
  `${window.innerWidth}×${window.innerHeight} @${window.devicePixelRatio || 1}`,
  api ? `Electron ${api.versions.electron}` : navigator.userAgent,
);

createRoot(container).render(
  <StrictMode>
    <App />
  </StrictMode>,
);

startPerformanceProbe();
