// Das Umschreiben von HLS-Playlisten.
//
// Eigene Datei, damit sie prüfbar ist: `server.ts` startet beim Einlesen einen
// HTTP-Dienst, und ein Test, der ihn dafür hochfährt, prüft am Ende die
// Portvergabe mit.

import { isSafeRemoteURL } from "@nori/core";

/**
 * Adressen in einer HLS-Playlist auf den eigenen Weiterreicher umbiegen.
 *
 * Sonst holt der Fernseher die Segmente direkt beim Hoster — ohne `Referer`,
 * und damit oft mit 403. Betroffen sind Zeilen ohne `#` und die
 * `URI="…"`-Angaben in Schlüssel-, Map- und Media-Zeilen.
 */
export function rewriteM3U8(text: string, baseUrl: string, referer: string | null): string {
  const wrap = (raw: string): string => {
    let absolute: string;
    try {
      absolute = new URL(raw, baseUrl).toString();
    } catch {
      return raw;
    }
    if (!isSafeRemoteURL(absolute)) return raw;
    const params = new URLSearchParams({ u: absolute });
    if (referer) params.set("r", referer);
    return `/api/stream?${params.toString()}`;
  };

  return text.split(/\r?\n/).map((line) => {
    const trimmed = line.trim();
    if (!trimmed) return line;
    if (!trimmed.startsWith("#")) return wrap(trimmed);
    return line.replace(/URI="([^"]+)"/g, (_m, uri: string) => `URI="${wrap(uri)}"`);
  }).join("\n");
}
