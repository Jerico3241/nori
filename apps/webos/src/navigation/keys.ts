// Tastencodes der LG-Fernbedienung.
//
// Die Zahlen sind das, was webOS im `keydown` liefert. Daneben stehen die
// Browser-Entsprechungen, damit sich die App am Rechner mit der Tastatur
// bedienen lässt — sonst wäre jede Änderung nur auf einem Fernseher zu prüfen.

export const KEY = {
  left: 37,
  up: 38,
  right: 39,
  down: 40,
  ok: 13,
  back: 461,
  /** Manche webOS-Stände und der Magic-Remote-Zurück-Knopf senden 10009. */
  backAlt: 10009,
  play: 415,
  playAlt: 179,
  pause: 19,
  pauseAlt: 178,
  playPause: 463,
  stop: 413,
  stopAlt: 178,
  rewind: 412,
  rewindAlt: 227,
  forward: 417,
  forwardAlt: 228,
  red: 403,
  green: 404,
  yellow: 405,
  blue: 406,
} as const;

export interface RemoteEventLike {
  keyCode: number;
  key?: string;
}

export function isBack(event: RemoteEventLike): boolean {
  return event.keyCode === KEY.back
    || event.keyCode === KEY.backAlt
    || event.key === "Escape"
    || event.key === "Backspace"
    || event.key === "BrowserBack"
    || event.key === "GoBack";
}

export function isEnter(event: RemoteEventLike): boolean {
  return event.keyCode === KEY.ok || event.key === "Enter";
}

export function isPlay(event: RemoteEventLike): boolean {
  return event.keyCode === KEY.play || event.keyCode === KEY.playAlt || event.key === "MediaPlay";
}

export function isPause(event: RemoteEventLike): boolean {
  return event.keyCode === KEY.pause || event.key === "MediaPause";
}

export function isPlayPause(event: RemoteEventLike): boolean {
  return event.keyCode === KEY.playPause || event.key === "MediaPlayPause" || event.key === " ";
}

export function isStop(event: RemoteEventLike): boolean {
  return event.keyCode === KEY.stop || event.key === "MediaStop";
}

/** −1 zurückspulen, +1 vorspulen, sonst `null`. */
export function seekDirection(event: RemoteEventLike): -1 | 1 | null {
  if (event.keyCode === KEY.forward || event.keyCode === KEY.forwardAlt) return 1;
  if (event.keyCode === KEY.rewind || event.keyCode === KEY.rewindAlt) return -1;
  return null;
}

export function arrowDirection(event: RemoteEventLike): "left" | "right" | "up" | "down" | null {
  switch (event.keyCode) {
    case KEY.left: return "left";
    case KEY.right: return "right";
    case KEY.up: return "up";
    case KEY.down: return "down";
    default: return null;
  }
}
