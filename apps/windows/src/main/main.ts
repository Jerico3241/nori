// Nori für Windows — der Hauptprozess.
//
// ## Was er tut
//
//     Fenster        Größe merken, Vollbild, Menüleiste weg
//     Quellen        `DirectGateway` aus dem Kern, ohne Herkunftsprüfung
//     Streams        `Referer` setzen, wo ein Hoster ihn verlangt
//     Google         Anmeldung im Systembrowser, Tokens verschlüsselt
//     Daten          alles unter `userData` (`%APPDATA%\\Nori`)
//
// ## Was er nicht mehr tut
//
// Die vorherige Windows-Fassung startete einen Nitro-Server als eigenen
// Prozess und zeigte in einem Fenster `http://127.0.0.1:17321`. Das hieß: ein
// zweiter Node-Prozess, ein belegter Port, eine Wartezeit beim Start, ein
// Fehlerbild („Server antwortet nicht"), und ein Web-Bündel, dessen Quelltext
// gar nicht im Repository liegt. Nichts davon ist nötig — der Hauptprozess ist
// selbst Node, und die Quellenschicht läuft direkt darin.
//
// ## Sicherheit
//
// Das Fenster läuft mit `contextIsolation`, ohne `nodeIntegration` und mit
// `sandbox`. Es sieht ausschließlich, was `preload.ts` über `contextBridge`
// freigibt — eine feste Liste von Kanälen, keine offene Brücke. Fremde
// Adressen gehen in den Systembrowser, nie in ein Nori-Fenster.

import { join } from "node:path";

import {
  BrowserWindow, Menu, app, ipcMain, nativeTheme, session, shell,
} from "electron";
import type { CatalogProvider, ResolveRequest } from "@nori/core";

import { configureGateway, httpRequest, mainGateway } from "./gateway";
import { accessToken, cancelSignIn, revoke, signIn, signOut, status } from "./google";
import { loadWindowState, saveWindowState } from "./windowState";

const ROOT = join(__dirname, "..");
/** Die Fastschwarz-Fläche aus `theme.css` — das Fenster soll nie weiß blitzen. */
const BACKGROUND = "#03070d";

app.setAppUserModelId("de.nori.app");
// Eine zweite Instanz würde dieselbe Bibliothek aus zwei Fenstern schreiben.
if (!app.requestSingleInstanceLock()) app.quit();

let mainWindow: BrowserWindow | null = null;

/**
 * Hoster, die ohne `Referer` nichts ausliefern.
 *
 * Der Resolver kennt zu jeder Adresse die Seite, von der sie stammt. Ein
 * `<video src>` im Fenster kann die Kopfzeile nicht setzen — der Hauptprozess
 * schon, und zwar genau für die Adressen, um die es geht. Kein Proxy, kein
 * Zwischenspeichern, kein zweiter Weg durch den Quelltext.
 */
const referers = new Map<string, string>();

/** Ein Protokolleintrag mit festem Präfix — nie mit Adressen samt Abfrage. */
function log(message: string): void {
  console.log(`[Nori:Windows] ${message}`);
}

function refererFor(url: string): string | null {
  for (const [prefix, referer] of referers) {
    if (url.startsWith(prefix)) return referer;
  }
  return null;
}

function installStreamHeaders(): void {
  session.defaultSession.webRequest.onBeforeSendHeaders((details, callback) => {
    const referer = refererFor(details.url);
    if (!referer) {
      callback({ requestHeaders: details.requestHeaders });
      return;
    }
    callback({
      requestHeaders: {
        ...details.requestHeaders,
        Referer: referer,
        Origin: new URL(referer).origin,
      },
    });
  });
}

function createWindow(): void {
  const state = loadWindowState();
  mainWindow = new BrowserWindow({
    ...state.bounds,
    minWidth: 880,
    minHeight: 560,
    backgroundColor: BACKGROUND,
    title: "Nori",
    autoHideMenuBar: true,
    show: false,
    icon: join(ROOT, "build", "icon.png"),
    webPreferences: {
      preload: join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false,
      // Die Oberfläche liegt neben der EXE und wird von `file://` geladen.
      webSecurity: true,
    },
  });
  if (state.maximized) mainWindow.maximize();
  // Erst zeigen, wenn etwas zu sehen ist — ein leeres Fenster, das kurz
  // aufblitzt, sieht nach Fehler aus.
  mainWindow.once("ready-to-show", () => mainWindow?.show());
  Menu.setApplicationMenu(null);

  mainWindow.on("close", () => {
    if (mainWindow) saveWindowState(mainWindow);
  });
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
  const sendFullscreen = () => {
    mainWindow?.webContents.send("nori:fullscreen", mainWindow.isFullScreen());
  };
  mainWindow.on("enter-full-screen", sendFullscreen);
  mainWindow.on("leave-full-screen", sendFullscreen);

  // Nori öffnet keine zweiten Fenster. Was hier ankommt, gehört in den
  // Systembrowser des Nutzers.
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/i.test(url)) void shell.openExternal(url);
    return { action: "deny" };
  });
  // Und niemand navigiert dieses Fenster irgendwohin.
  mainWindow.webContents.on("will-navigate", (event, url) => {
    if (url !== mainWindow?.webContents.getURL()) {
      event.preventDefault();
      if (/^https?:/i.test(url)) void shell.openExternal(url);
    }
  });

  const devServer = process.env.NORI_DEV_SERVER;
  if (devServer) void mainWindow.loadURL(devServer);
  else void mainWindow.loadFile(join(ROOT, "dist", "index.html"));
}

function registerIpc(): void {
  ipcMain.handle("nori:catalog", (_e, provider: CatalogProvider, force: boolean) =>
    mainGateway.catalog(provider, force));
  ipcMain.handle("nori:series", (_e, provider: CatalogProvider, slug: string, season: string | null) =>
    mainGateway.series(provider, slug, season));
  ipcMain.handle("nori:watch", (_e, provider: CatalogProvider, path: string) =>
    mainGateway.watch(provider, path));
  ipcMain.handle("nori:calendar", (_e, provider: CatalogProvider, force: boolean) =>
    mainGateway.calendar(provider, force));
  ipcMain.handle("nori:resolve", (_e, request: ResolveRequest) => mainGateway.resolve(request));
  // TMDB — und sonst nichts: `httpRequest` prüft das Ziel.
  ipcMain.handle("nori:http", (_e, url: string, headers: Record<string, string> | undefined) =>
    httpRequest(url, { headers }));
  ipcMain.handle("nori:configure", (_e, mode: string, serverUrl: string) => {
    const chosen = configureGateway(mode, serverUrl);
    log(`Zugang: ${chosen.server || "im Programm"}`);
    return chosen;
  });

  ipcMain.handle("nori:stream-headers", (_e, url: string, referer: string | null) => {
    // Nur der Ursprung als Schlüssel: eine HLS-Wiedergabe holt neben der
    // Playlist noch Segmente, und die liegen unter derselben Adresse.
    try {
      const origin = new URL(url).origin;
      if (referer) referers.set(origin, referer);
      else referers.delete(origin);
    } catch {
      /* eine unbrauchbare Adresse braucht keine Kopfzeile */
    }
    return true;
  });

  ipcMain.handle("nori:google-status", () => status());
  ipcMain.handle("nori:google-sign-in", async () => {
    try {
      return { ok: true as const, value: await signIn() };
    } catch (cause) {
      return { ok: false as const, message: (cause as Error)?.message ?? "Anmeldung fehlgeschlagen" };
    }
  });
  ipcMain.handle("nori:google-cancel", () => {
    cancelSignIn();
    return status();
  });
  ipcMain.handle("nori:google-sign-out", () => signOut());
  ipcMain.handle("nori:google-revoke", () => revoke());
  ipcMain.handle("nori:google-token", () => accessToken());

  ipcMain.handle("nori:window", (_e, action: string) => {
    const win = mainWindow;
    if (!win) return false;
    switch (action) {
      case "minimize": win.minimize(); return true;
      case "maximize": win.isMaximized() ? win.unmaximize() : win.maximize(); return true;
      case "close": win.close(); return true;
      case "fullscreen": win.setFullScreen(!win.isFullScreen()); return win.isFullScreen();
      case "fullscreen-exit": win.setFullScreen(false); return false;
      case "is-fullscreen": return win.isFullScreen();
      default: return false;
    }
  });

  ipcMain.handle("nori:open-external", (_e, url: string) => {
    if (/^https?:/i.test(url)) void shell.openExternal(url);
    return true;
  });
}

app.on("second-instance", () => {
  if (!mainWindow) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.focus();
});

app.whenReady().then(() => {
  nativeTheme.themeSource = "dark";
  installStreamHeaders();
  registerIpc();
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  cancelSignIn();
  app.quit();
});
