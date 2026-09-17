// Protokoll mit festem Präfix, damit sich Nori in den Fernseherprotokollen
// (`ares-log`, Web-Inspector) von allem anderen trennen lässt.
//
// Im gebauten Stand bleiben nur Warnungen und Fehler übrig: ein Fernseher hat
// wenig Speicher, und eine Konsole voller Navigationsmeldungen kostet ihn.
// Keine Adressen mit Zugangsdaten, keine Schlüssel — was hier landet, landet
// auch im Protokoll des Geräts.

const PREFIX = "[Nori:webOS]";
const verbose = import.meta.env.DEV || localStorage.getItem("nori.debug") === "1";

type Scope =
  | "nav" | "focus" | "playback" | "resolver" | "hls" | "hoster" | "progress"
  | "data" | "tmdb" | "app";

export function log(scope: Scope, ...parts: unknown[]): void {
  if (!verbose) return;
  console.log(`${PREFIX}[${scope}]`, ...parts);
}

export function warn(scope: Scope, ...parts: unknown[]): void {
  console.warn(`${PREFIX}[${scope}]`, ...parts);
}

export function error(scope: Scope, ...parts: unknown[]): void {
  console.error(`${PREFIX}[${scope}]`, ...parts);
}

export function isVerbose(): boolean {
  return verbose;
}
