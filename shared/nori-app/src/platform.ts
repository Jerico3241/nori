// Was eine Nori-Oberfläche über ihr Gerät wissen muss — und mehr nicht.
//
// ## Warum es das gibt
//
// Der gemeinsame Kern (`@nori/core`) weiß nichts von einer Oberfläche: er
// kennt Quellen, Modelle, Regeln. Die Oberflächen dagegen — der Fernseher und
// der Desktop — teilen sich fast ihren gesamten Unterbau: TMDB, Bildindex,
// Bibliothek, Katalogansicht, Startseitenrangfolge, Einstellungen. Der
// Unterschied liegt in einer Handvoll Dinge, die das Gerät beantwortet:
//
//     Wie groß ist die Zeichenfläche wirklich?
//     Arbeitet die Eingabe gerade, sodass Hintergrundarbeit warten soll?
//     Wo liegen Einstellungen?
//     Wie öffnet man eine fremde Adresse?
//
// Statt jede dieser Fragen an `if (isWebOS())` zu hängen, beantwortet sie eine
// Plattform. Jede App meldet beim Start ihre eigene an; der geteilte Unterbau
// fragt nur noch diese Schnittstelle. Das ist der Unterschied zwischen zwei
// Apps, die sich Code teilen, und zwei Apps, die sich Code kopieren.
//
// Bewusst klein gehalten: Jede Methode hier ist eine, die mindestens zwei
// Plattformen unterschiedlich beantworten **und** die der geteilte Unterbau
// wirklich braucht. Was nur eine Plattform betrifft, gehört in ihre App.

export type PlatformKind = "webos" | "windows" | "browser";

export interface NoriPlatform {
  /** Welche App das hier ist. Nur für Protokoll und Diagnose. */
  readonly kind: PlatformKind;

  /**
   * Die Breite der Zeichenfläche in echten Bildpunkten.
   *
   * Nicht `window.innerWidth * devicePixelRatio`: Ein webOS-Paket mit
   * `"resolution": "1920x1080"` zeichnet in 1920 × 1080, auch wenn das Panel
   * 4K meldet. Daran hängt, welche TMDB-Stufe ein Bild bekommt — und damit,
   * wie viel ein Fernseher dekodieren muss.
   */
  surfaceWidth(): number;

  /**
   * Arbeitet die Eingabe gerade?
   *
   * Auf dem Fernseher: eine Pfeiltaste bewegt den Fokus, und alles andere hat
   * zu warten. Auf dem Desktop: gescrollt oder gezogen wird, und ein
   * Bildabruf darf das nicht ins Stocken bringen. Hintergrundarbeit
   * (`services/scheduler.ts`) fragt hier nach, bevor sie loslegt.
   */
  isInputBusy(): boolean;

  /** Eine Adresse außerhalb der App öffnen — Systembrowser, nie im Fenster. */
  openExternal(url: string): void;

  /** Die App verlassen. Auf dem Fernseher der Systemweg, auf dem Desktop das Fenster. */
  exit(): void;
}

/**
 * Die Voreinstellung: ein gewöhnlicher Browser.
 *
 * Sie ist nicht nur Platzhalter — der Entwicklungsstand beider Apps läuft im
 * Browser, und dort ist das echte Pixelverhältnis tatsächlich die Wahrheit.
 */
const browserPlatform: NoriPlatform = {
  kind: "browser",
  surfaceWidth: () => (window.innerWidth || 1920) * (window.devicePixelRatio || 1),
  isInputBusy: () => false,
  openExternal: (url) => {
    window.open(url, "_blank", "noopener,noreferrer");
  },
  exit: () => window.close(),
};

let current: NoriPlatform = browserPlatform;

/** Einmal beim Start, bevor irgendetwas gezeichnet wird. */
export function installPlatform(platform: NoriPlatform): void {
  current = platform;
}

export function platform(): NoriPlatform {
  return current;
}
