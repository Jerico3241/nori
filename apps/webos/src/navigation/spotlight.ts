// Eine schmale, getypte Hülle um `@enact/spotlight`.
//
// Die mitgelieferten Typen beschreiben `focus` als „String oder Objekt" und
// `getCurrent` als React-Knoten; im Betrieb sind es DOM-Elemente. Statt an
// jeder Aufrufstelle zu casten, steht die Umdeutung hier einmal.

import SpotlightRaw from "@enact/spotlight";

interface SpotlightApi {
  focus(target?: string | HTMLElement): boolean;
  getCurrent(): HTMLElement | null;
  setPointerMode(value: boolean): void;
  pause(): void;
  resume(): void;
  set(containerIdOrConfig: string | object, config?: object): void;
}

export const Spotlight = SpotlightRaw as unknown as SpotlightApi;
