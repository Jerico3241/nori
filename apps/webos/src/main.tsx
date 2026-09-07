import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import SpotlightRootDecorator from "@enact/spotlight/SpotlightRootDecorator";
import Spotlight from "@enact/spotlight";

import { App } from "./App";
import { log } from "./services/log";
import { isWebOS } from "./services/webos";
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

log("app", "Start", isWebOS() ? "webOS" : "Browser", navigator.userAgent);

createRoot(container).render(
  <StrictMode>
    <Root />
  </StrictMode>,
);
