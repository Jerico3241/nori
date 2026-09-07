// Die wenigen Stellen, an denen Nori tatsächlich webOS anspricht.
//
// Bewusst über Merkmalsprüfungen: dieselbe App muss sich im Browser bauen und
// bedienen lassen, sonst wäre jede Änderung nur auf einem Fernseher zu prüfen.

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
