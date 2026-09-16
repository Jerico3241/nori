// Wo das Fenster stand, als es zuletzt zu war.
//
// Eine Desktop-App, die bei jedem Start wieder 1280 × 800 in der Bildmitte ist,
// verhält sich nicht wie eine Desktop-App. Gemerkt werden Größe, Position und
// ob maximiert — mehr nicht.
//
// Die Position wird beim Laden gegen die vorhandenen Bildschirme geprüft: Wer
// Nori auf einem zweiten Monitor hatte und ohne diesen startet, bekäme sonst
// ein Fenster außerhalb jedes sichtbaren Bereichs.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

import { app, screen, type BrowserWindow } from "electron";

export interface WindowState {
  bounds: { width: number; height: number; x?: number; y?: number };
  maximized: boolean;
}

const DEFAULT_STATE: WindowState = {
  bounds: { width: 1360, height: 860 },
  maximized: false,
};

function stateFile(): string {
  return join(app.getPath("userData"), "window-state.json");
}

/** Liegt das Fenster noch auf einem Bildschirm, der existiert? */
function visibleSomewhere(bounds: WindowState["bounds"]): boolean {
  if (bounds.x === undefined || bounds.y === undefined) return true;
  return screen.getAllDisplays().some((display) => {
    const area = display.workArea;
    // Ein Streifen von 80 px reicht: solange die Titelleiste erreichbar ist,
    // kann der Nutzer das Fenster selbst zurückholen.
    return bounds.x! + bounds.width > area.x + 80
      && bounds.x! < area.x + area.width - 80
      && bounds.y! + 80 > area.y
      && bounds.y! < area.y + area.height - 40;
  });
}

export function loadWindowState(): WindowState {
  const file = stateFile();
  if (!existsSync(file)) return DEFAULT_STATE;
  try {
    const parsed = JSON.parse(readFileSync(file, "utf8")) as Partial<WindowState>;
    const bounds = parsed.bounds;
    if (!bounds || !Number.isFinite(bounds.width) || !Number.isFinite(bounds.height)) return DEFAULT_STATE;
    const clean: WindowState = {
      bounds: {
        width: Math.max(880, Math.round(bounds.width)),
        height: Math.max(560, Math.round(bounds.height)),
        x: Number.isFinite(bounds.x) ? Math.round(bounds.x as number) : undefined,
        y: Number.isFinite(bounds.y) ? Math.round(bounds.y as number) : undefined,
      },
      maximized: parsed.maximized === true,
    };
    if (!visibleSomewhere(clean.bounds)) {
      clean.bounds.x = undefined;
      clean.bounds.y = undefined;
    }
    return clean;
  } catch {
    return DEFAULT_STATE;
  }
}

export function saveWindowState(window: BrowserWindow): void {
  try {
    // Im Vollbild oder maximiert sind die aktuellen Maße die des Bildschirms —
    // gemerkt gehört die Größe, auf die das Fenster zurückspringt.
    const bounds = window.isMaximized() || window.isFullScreen()
      ? window.getNormalBounds()
      : window.getBounds();
    const state: WindowState = {
      bounds: { width: bounds.width, height: bounds.height, x: bounds.x, y: bounds.y },
      maximized: window.isMaximized(),
    };
    const file = stateFile();
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, JSON.stringify(state), "utf8");
  } catch {
    // Ein nicht gemerkter Fensterstand ist ärgerlich, kein Grund für eine
    // Fehlermeldung beim Schließen.
  }
}
