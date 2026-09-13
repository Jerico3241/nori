// hls.js erst laden, wenn ein Stream es braucht.
//
// hls.js ist mit Abstand der größte Teil der App — gut die Hälfte des früheren
// Bündels. Gebraucht wird es nur für HLS-Streams auf Geräten **ohne** natives
// HLS; webOS spielt HLS in aller Regel selbst ab. Beim Start musste der
// Fernseher es trotzdem jedes Mal parsen und auswerten.
//
// Deshalb liegt es als eigene Datei im Paket (`vendor/hls.min.js`, beim Bau aus
// `node_modules` kopiert und für Chrome 79 übersetzt) und wird als
// **klassisches** Skript nachgeladen. Kein `import()`: ein ES-Modul lädt von
// `file://` nicht (siehe `vite.config.ts`). Ein klassisches Skript mit relativer
// Adresse tut es — genau so kommt auch das Hauptbündel auf den Fernseher.

import type HlsClass from "hls.js";

export type HlsConstructor = typeof HlsClass;

declare global {
  interface Window {
    Hls?: HlsConstructor;
  }
}

/** Relativ zur `index.html`, wie jede andere Datei im Paket. */
export const HLS_SCRIPT = "./vendor/hls.min.js";

let pending: Promise<HlsConstructor> | null = null;

/** Kann dieses Gerät überhaupt Media Source Extensions? Ohne sie ist hls.js nutzlos. */
export function hasMediaSource(): boolean {
  const scope = window as unknown as { MediaSource?: unknown; WebKitMediaSource?: unknown };
  return typeof scope.MediaSource === "function" || typeof scope.WebKitMediaSource === "function";
}

/**
 * hls.js bereitstellen — einmal je Programmlauf.
 *
 * Scheitert das Laden, darf ein zweiter Versuch es noch einmal probieren; ein
 * gemerkter Fehlschlag machte jeden weiteren Stream dieser Sitzung unspielbar.
 */
export function loadHls(): Promise<HlsConstructor> {
  if (window.Hls) return Promise.resolve(window.Hls);
  if (pending) return pending;
  pending = new Promise<HlsConstructor>((resolve, reject) => {
    const script = document.createElement("script");
    script.src = HLS_SCRIPT;
    script.async = true;
    script.onload = () => {
      if (window.Hls) {
        resolve(window.Hls);
        return;
      }
      pending = null;
      reject(new Error("hls.js wurde geladen, stellt aber nichts bereit"));
    };
    script.onerror = () => {
      pending = null;
      script.remove();
      reject(new Error("hls.js ließ sich nicht laden"));
    };
    document.head.appendChild(script);
  });
  return pending;
}
