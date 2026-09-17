// Die Brücke zwischen Fenster und Hauptprozess — und alles, was das Fenster
// vom Betriebssystem je zu sehen bekommt.
//
// Kein `nodeIntegration`, kein `remote`, kein `ipcRenderer` im Fenster: hier
// steht eine feste Liste von Aufrufen, und was nicht darin steht, gibt es für
// die Oberfläche nicht. Das ist der Unterschied zwischen einer Brücke und
// einem offenen Tor — ein eingeschleustes Skript aus einer Hoster-Seite käme
// über diese Liste nicht an das Dateisystem.
//
// Was hier ausdrücklich **nicht** hinausgeht: das Refresh-Token. Das Fenster
// bekommt nur ein Zugriffstoken, das eine Stunde gilt.

import { contextBridge, ipcRenderer } from "electron";

const bridge = {
  /** Woher die Daten kommen: derselbe Kern wie überall, nur im Hauptprozess. */
  gateway: {
    catalog: (provider: string, force: boolean) => ipcRenderer.invoke("nori:catalog", provider, force),
    series: (provider: string, slug: string, season: string | null) =>
      ipcRenderer.invoke("nori:series", provider, slug, season),
    watch: (provider: string, path: string) => ipcRenderer.invoke("nori:watch", provider, path),
    calendar: (provider: string, force: boolean) => ipcRenderer.invoke("nori:calendar", provider, force),
    resolve: (request: unknown) => ipcRenderer.invoke("nori:resolve", request),
    /** Welchen Weg der Hauptprozess nehmen soll — nach jeder Einstellung. */
    configure: (mode: string, serverUrl: string) => ipcRenderer.invoke("nori:configure", mode, serverUrl),
  },

  /**
   * Ein Abruf durch den Hauptprozess — für TMDB.
   *
   * Der Hauptprozess lässt nur TMDB und den eingetragenen Nori-Server zu; was
   * hier hineingeht, ist also kein freier Zugang ins Netz.
   */
  http: {
    request: (url: string, headers?: Record<string, string>) =>
      ipcRenderer.invoke("nori:http", url, headers),
  },

  /** Den `Referer` für eine Streamadresse hinterlegen, bevor sie geladen wird. */
  stream: {
    prepare: (url: string, referer: string | null) =>
      ipcRenderer.invoke("nori:stream-headers", url, referer),
  },

  google: {
    status: () => ipcRenderer.invoke("nori:google-status"),
    signIn: () => ipcRenderer.invoke("nori:google-sign-in"),
    cancel: () => ipcRenderer.invoke("nori:google-cancel"),
    signOut: () => ipcRenderer.invoke("nori:google-sign-out"),
    revoke: () => ipcRenderer.invoke("nori:google-revoke"),
    accessToken: () => ipcRenderer.invoke("nori:google-token"),
  },

  window: {
    minimize: () => ipcRenderer.invoke("nori:window", "minimize"),
    toggleMaximize: () => ipcRenderer.invoke("nori:window", "maximize"),
    close: () => ipcRenderer.invoke("nori:window", "close"),
    toggleFullscreen: () => ipcRenderer.invoke("nori:window", "fullscreen"),
    exitFullscreen: () => ipcRenderer.invoke("nori:window", "fullscreen-exit"),
    isFullscreen: () => ipcRenderer.invoke("nori:window", "is-fullscreen"),
    /** Meldet sich, wenn der Vollbildzustand sich ändert — auch über F11. */
    onFullscreen(listener: (value: boolean) => void) {
      const handler = (_event: unknown, value: boolean) => listener(value);
      ipcRenderer.on("nori:fullscreen", handler);
      return () => ipcRenderer.removeListener("nori:fullscreen", handler);
    },
  },

  openExternal: (url: string) => ipcRenderer.invoke("nori:open-external", url),

  versions: {
    app: process.env.npm_package_version ?? "",
    electron: process.versions.electron,
    chrome: process.versions.chrome,
    node: process.versions.node,
    platform: process.platform,
    arch: process.arch,
  },
};

contextBridge.exposeInMainWorld("nori", bridge);

export type NoriBridge = typeof bridge;
