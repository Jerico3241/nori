// Die wenigen Stellen, an denen Nori tatsächlich webOS anspricht.
//
// Bewusst über Merkmalsprüfungen: dieselbe App muss sich im Browser bauen und
// bedienen lassen, sonst wäre jede Änderung nur auf einem Fernseher zu prüfen.
//
// Am Ende der Datei steht die Plattform, die die gemeinsame
// Anwendungsschicht (`@nori/app`) beim Start bekommt. Sie ist der einzige Weg,
// auf dem geteilter Code etwas über diesen Fernseher erfährt.

import type { DeviceSettings, NoriPlatform } from "@nori/app";

import { navigating } from "../navigation/engine";

interface WebOSSystem {
  close?: () => void;
  platformBack?: () => void;
  deviceInfo?: (callback: (info: unknown) => void) => void;
}

function webOSSystem(): WebOSSystem | null {
  const w = window as unknown as { webOSSystem?: WebOSSystem; PalmSystem?: WebOSSystem };
  return w.webOSSystem ?? w.PalmSystem ?? null;
}

export function isWebOS(): boolean {
  return webOSSystem() !== null || /web0s|webos/i.test(navigator.userAgent);
}

/**
 * Die App verlassen.
 *
 * Auf webOS ist das `platformBack` — der Systemweg, der die App in den
 * Hintergrund nimmt statt sie hart zu beenden. Im Browser bleibt `window.close`,
 * das je nach Kontext nichts tut; deshalb der Rückfall auf die Startseite,
 * damit man nicht in einem Zustand ohne Ausweg endet.
 */
export function exitApp(): void {
  const system = webOSSystem();
  if (system?.platformBack) {
    system.platformBack();
    return;
  }
  if (system?.close) {
    system.close();
    return;
  }
  window.close();
}

/** Bildschirmschoner unterdrücken, solange etwas läuft. */
export function keepAwake(active: boolean): () => void {
  const nav = navigator as Navigator & {
    wakeLock?: { request(type: "screen"): Promise<{ release(): Promise<void> }> };
  };
  if (!active || !nav.wakeLock) return () => undefined;
  let released = false;
  let handle: { release(): Promise<void> } | null = null;
  nav.wakeLock.request("screen").then(
    (lock) => {
      if (released) void lock.release();
      else handle = lock;
    },
    () => undefined,
  );
  return () => {
    released = true;
    void handle?.release().catch(() => undefined);
  };
}

/**
 * Kennt dieser Browser `gap` in einem Flex-Container?
 *
 * ## Warum das geprüft werden muss
 *
 * webOS 6 fährt Chrome 79. Dort gibt es `gap` **nur im Raster**, nicht im
 * Flex-Layout — das kam erst mit Chrome 84. Noris Oberfläche benutzt es an gut
 * vierzig Stellen: Reihen, Knopfzeilen, Chips, die Bedienung im Player. Ohne
 * Abstand klebt dort alles aneinander, und zwar genau auf dem ältesten Gerät,
 * das Nori unterstützen soll.
 *
 * Das lässt sich nicht übersetzen und nicht über `@supports` erfragen:
 * `@supports (gap: 1px)` ist in Chrome 79 **wahr**, weil es Rasterabstände
 * kennt. Ein Feature-Query würde also das Falsche sagen.
 *
 * Deshalb wird gemessen: zwei Kästen in einem Flex-Container übereinander,
 * dazwischen ein Pixel Abstand. Kommt die Höhe 1 zurück, wirkt `row-gap`.
 *
 * Das Ergebnis landet als `data-flex-gap` am Wurzelelement; das Stylesheet
 * hängt daran seinen Rückfall über Ränder. Dieselbe Stelle trägt schon
 * `data-effects` und `data-nav`.
 */
export function supportsFlexGap(): boolean {
  const probe = document.createElement("div");
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  probe.style.display = "flex";
  probe.style.flexDirection = "column";
  probe.style.rowGap = "1px";
  probe.appendChild(document.createElement("div"));
  probe.appendChild(document.createElement("div"));
  document.body.appendChild(probe);
  const height = probe.scrollHeight;
  probe.parentNode?.removeChild(probe);
  return height === 1;
}

/** Das Messergebnis am Dokument anschreiben. Einmal beim Start. */
export function markFlexGapSupport(): boolean {
  let supported = true;
  try {
    supported = supportsFlexGap();
  } catch {
    // Im Zweifel annehmen, dass es geht: der Rückfall über Ränder ist auf
    // einem modernen Panel sonst ein doppelter Abstand.
    supported = true;
  }
  document.documentElement.dataset.flexGap = supported ? "yes" : "no";
  return supported;
}

/**
 * Die Zeichenfläche dieses Geräts in Bildpunkten.
 *
 * Auf webOS die Auflösung aus `appinfo.json` — ein Paket mit
 * `"resolution": "1920x1080"` zeichnet in 1920 × 1080, auch wenn das Panel 4K
 * meldet und `devicePixelRatio` 2 sagt. Nur im Browser, wo es kein
 * `appinfo.json` gibt, entscheidet das echte Pixelverhältnis; dort ist es die
 * Wahrheit.
 */
function surfaceWidth(): number {
  if (isWebOS()) {
    const match = /^(\d+)\s*x\s*(\d+)$/i.exec(__NORI_WEBOS_RESOLUTION__ ?? "");
    const width = match ? Number(match[1]) : NaN;
    if (Number.isFinite(width) && width > 0) return width;
  }
  return (window.innerWidth || 1920) * (window.devicePixelRatio || 1);
}

/**
 * Womit dieser Fernseher startet, wenn noch nichts eingestellt ist.
 *
 * Der Weg über den Nori-Server ist auf einem Fernseher die Voreinstellung und
 * nicht nur eine Möglichkeit: ein Fernseher darf `Referer` nicht setzen, und
 * viele Hoster liefern ohne diese Kopfzeile nichts aus. Der Desktop macht es
 * andersherum — dort läuft die Quellenschicht im Hauptprozess und darf alles,
 * was ein Programm darf.
 */
export const WEBOS_DEFAULTS: Partial<DeviceSettings> = { transport: "server", tmdbMode: "server" };

/** Was der geteilte Unterbau über diesen Fernseher wissen darf. */
export const webOSPlatform: NoriPlatform = {
  kind: "webos",
  surfaceWidth,
  // Auf dem Fernseher heißt „die Eingabe arbeitet": der Fokus bewegt sich
  // gerade. Hintergrundarbeit hat dann zu warten.
  isInputBusy: navigating,
  openExternal(url) {
    // Ein Fernseher hat keinen zweiten Browser, in den sich etwas öffnen
    // ließe. Nori zeigt Adressen deshalb als QR-Code; hierher kommt nichts.
    warnUnsupported(url);
  },
  exit: exitApp,
};

function warnUnsupported(url: string): void {
  // Absichtlich ohne die Adresse im Protokoll: sie kann einen Gerätecode
  // tragen, und der gehört in kein Protokoll.
  console.warn("[Nori:webOS][app] Adresse extern öffnen wird auf dem Fernseher nicht unterstützt", url.split("?")[0]);
}
