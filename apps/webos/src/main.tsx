import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import SpotlightRootDecorator from "@enact/spotlight/SpotlightRootDecorator";
import Spotlight from "@enact/spotlight";

import { App } from "./App";
import { error, log } from "./services/log";
import { isWebOS, markFlexGapSupport } from "./services/webos";
import "./styles/theme.css";
import "./styles/app.css";
import "./styles/player.css";

// Zeigermodus aus: auf einem Fernseher gibt es keinen Zeiger, und im
// Zeigermodus zeichnet Spotlight keinen Fokusring. Die Magic Remote schaltet
// ihn bei Bewegung wieder ein — das ist gewollt, sie ist ja ein Zeiger.
Spotlight.setPointerMode(false);

const Root = SpotlightRootDecorator(
  { noAutoFocus: false },
  App,
) as unknown as React.ComponentType;

const container = document.getElementById("root");
if (!container) throw new Error("Kein #root im Dokument");

/*
 * Unbehandelte Fehler in das Protokoll des Geräts.
 *
 * Auf einem Fernseher gibt es keine Konsole, die jemand aufklappt: Was die App
 * nicht selbst meldet, ist unauffindbar. Eine abgewiesene Zusage, die niemand
 * abfängt, sieht dort aus wie „die Kachel bleibt einfach leer" — und genau das
 * ist der Zustand, der sich ohne diese zwei Zeilen nicht erklären lässt.
 *
 * Absichtlich **nur** protokollieren: Ein Fehlerbildschirm über der ganzen App
 * wäre die falsche Antwort. Jede Ansicht hat ihre eigenen Enden (lädt, da,
 * kaputt), und ein einzelner gescheiterter Bildabruf darf sie nicht ersetzen.
 */
window.addEventListener("unhandledrejection", (event) => {
  error("app", "Unbehandelte Zusage", (event.reason as Error)?.message ?? event.reason);
});
window.addEventListener("error", (event) => {
  error("app", "Unbehandelter Fehler", event.message, event.filename, event.lineno);
});

// Vor dem ersten Rendern messen, damit der Rückfall schon beim Aufbau gilt.
const flexGap = markFlexGapSupport();

log(
  "app", "Start", isWebOS() ? "webOS" : "Browser",
  flexGap ? "flex-gap" : "flex-gap fehlt, Ränder statt Abstände",
  navigator.userAgent,
);

createRoot(container).render(
  <StrictMode>
    <Root />
  </StrictMode>,
);
