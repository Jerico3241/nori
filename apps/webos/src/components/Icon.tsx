// Eigene Symbole als Inline-SVG.
//
// Kein Icon-Paket und keine Bilddateien: ein Fernseher lädt sonst für jedes
// Symbol eine eigene Datei, und ein fremdes Set brächte eine fremde Formsprache
// mit. Die Pfade sind schlicht gehalten — auf drei Metern Abstand zählt die
// Silhouette, nicht das Detail.

export type IconName =
  | "home" | "compass" | "calendar" | "search" | "bookmark" | "bookmarkFilled"
  | "history" | "settings" | "play" | "pause" | "back" | "forward" | "rewind"
  | "next" | "previous" | "layers" | "check" | "close" | "info" | "warning";

const PATHS: Record<IconName, string> = {
  home: "M3 11.2 12 4l9 7.2V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z",
  compass: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm3.6 6.4-2.1 5-5 2.1 2.1-5z",
  calendar: "M7 2v3M17 2v3M3 8h18M5 5h14a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z",
  search: "M11 4a7 7 0 1 1 0 14 7 7 0 0 1 0-14zm9 16-4.3-4.3",
  bookmark: "M6 3h12a1 1 0 0 1 1 1v17l-7-4-7 4V4a1 1 0 0 1 1-1z",
  bookmarkFilled: "M6 3h12a1 1 0 0 1 1 1v17l-7-4-7 4V4a1 1 0 0 1 1-1z",
  history: "M3 12a9 9 0 1 0 3-6.7M3 4v4h4M12 7v5l4 2",
  settings: "M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zm8.4 3a8.4 8.4 0 0 0-.2-1.8l2-1.5-2-3.4-2.3 1a8.5 8.5 0 0 0-3-1.7L14.5 2h-4l-.4 2.6a8.5 8.5 0 0 0-3 1.7l-2.3-1-2 3.4 2 1.5a8.4 8.4 0 0 0 0 3.6l-2 1.5 2 3.4 2.3-1a8.5 8.5 0 0 0 3 1.7l.4 2.6h4l.4-2.6a8.5 8.5 0 0 0 3-1.7l2.3 1 2-3.4-2-1.5c.13-.6.2-1.2.2-1.8z",
  play: "M7 4.5 19.5 12 7 19.5z",
  pause: "M8 4h3.2v16H8zM12.8 4H16v16h-3.2z",
  back: "M15 5 8 12l7 7",
  // Doppelter Pfeil, nicht Pfeil-plus-Balken: der Balken liest sich als
  // „zum Anfang springen", und genau das tun diese beiden nicht.
  forward: "M3 5l8 7-8 7zM12.5 5l8 7-8 7z",
  rewind: "M21 5l-8 7 8 7zM11.5 5l-8 7 8 7z",
  next: "M6 5l9 7-9 7zM17 5h2.4v14H17z",
  previous: "M18 5 9 12l9 7zM4.6 5H7v14H4.6z",
  layers: "M12 3 2 8.5 12 14l10-5.5zM2 15.5 12 21l10-5.5",
  check: "M4 12.5 9.5 18 20 6.5",
  close: "M5 5l14 14M19 5 5 19",
  info: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 4.5v1.2m0 3.3v6",
  warning: "M12 3 1.5 21h21zM12 9v6m0 3v.01",
};

const FILLED: IconName[] = ["play", "home", "bookmarkFilled", "pause", "next", "previous", "forward", "rewind"];

export function Icon({ name, className }: { name: IconName; className?: string }) {
  const filled = FILLED.includes(name);
  return (
    <svg
      className={`icon ${className ?? ""}`}
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
      fill={filled ? "currentColor" : "none"}
      stroke={filled ? "none" : "currentColor"}
      strokeWidth={filled ? 0 : 1.9}
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d={PATHS[name]} />
    </svg>
  );
}
