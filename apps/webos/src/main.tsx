import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { App } from "./App";
import { installNavigation } from "./navigation/engine";
import {
  error,
  installPerformanceMode,
  installPlatform,
  log,
  readSettings,
  startPerformanceProbe,
} from "@nori/app";
import { WEBOS_DEFAULTS, isWebOS, markFlexGapSupport, webOSPlatform } from "./services/webos";
import "./styles/theme.css";
import "./styles/app.css";
import "./styles/player.css";

const container = document.getElementById("root");
if (!container) throw new Error("Kein #root im Dokument");

/*
 * Unbehandelte Fehler in das Protokoll des Geräts.
 *
 * Auf einem Fernseher gibt es keine Konsole, die jemand aufklappt: Was die App
 * nicht selbst meldet, ist unauffindbar. Absichtlich **nur** protokollieren —
 * jede Ansicht hat ihre eigenen Enden (lädt, da, kaputt), und ein einzelner
 * gescheiterter Bildabruf darf sie nicht ersetzen.
 */
window.addEventListener("unhandledrejection", (event) => {
  error("app", "Unbehandelte Zusage", (event.reason as Error)?.message ?? event.reason);
});
window.addEventListener("error", (event) => {
  error("app", "Unbehandelter Fehler", event.message, event.filename, event.lineno);
});

// Vor dem ersten Rendern: Messung für den Flex-Rückfall und die
// Fernbedienungsnavigation. Die Oberfläche benutzt kein Flex-`gap` mehr, die
// Messung bleibt für das Protokoll und für eigene Erweiterungen.
const flexGap = markFlexGapSupport();
// Zuerst die Plattform: alles darunter — Bildgrößen, Hintergrundarbeit,
// Leistungsmodus — fragt von hier an sie und nicht mehr `isWebOS()`.
installPlatform(webOSPlatform);
// Der Leistungsmodus steht am Wurzelelement, bevor das erste Bild entsteht:
// sonst zeichnete der Fernseher die Oberfläche einmal voll und gleich danach
// sparsam. Gemessen wird erst nach dem ersten Bild (`startPerformanceProbe`).
installPerformanceMode(readSettings(WEBOS_DEFAULTS).performance);
installNavigation();

log(
  "app", "Start", isWebOS() ? "webOS" : "Browser",
  flexGap ? "flex-gap" : "flex-gap fehlt",
  `${window.innerWidth}×${window.innerHeight} @${window.devicePixelRatio || 1}`,
  navigator.userAgent,
);

createRoot(container).render(
  <StrictMode>
    <App />
  </StrictMode>,
);

// Der Rechenlauf für den automatischen Leistungsmodus — in einer Lücke nach
// dem ersten Bild, und nur beim allerersten Start eines Geräts.
startPerformanceProbe();
