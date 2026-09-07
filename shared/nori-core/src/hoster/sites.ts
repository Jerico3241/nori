// Was ein einzelner Hoster von der allgemeinen Behandlung abweichend braucht —
// Aufbau wie `HosterSites` im Swift-Kern: je Hoster ein Eintrag, ein neuer
// Hoster ist ein Eintrag mehr.

import type { PlayKind } from "../models.js";
import { isAllowedMediaURL } from "./safety.js";
import { extractVoe } from "./voe.js";

export interface MediaHit {
  kind: PlayKind;
  url: string;
}

export interface HosterSite {
  /** Anzeigename, nur für Meldungen und zum Nachschlagen. */
  readonly name: string;
  /** Erkennt den Hoster an dem Namen, den die Quelle liefert (der schwankt). */
  matches(lowercasedName: string): boolean;
  /** Schreibt die Seitenadresse auf die Einbettungsvariante um. */
  embed(url: string): string;
  /** Eigenes Verfahren; `null` heißt: die allgemeine Suche übernimmt. */
  media(html: string): MediaHit | null;
}

/** Diese drei liefern unter `/d/` und `/v/` eine Downloadseite aus; das Video steht nur unter `/e/`. */
function embedOnly(name: string, token: string): HosterSite {
  return {
    name,
    matches: (n) => n.includes(token),
    embed: (url) => url.replace("/d/", "/e/").replace("/v/", "/e/"),
    media: () => null,
  };
}

export const VOE: HosterSite = {
  name: "VOE",
  matches: (n) => n.includes("voe"),
  embed: (url) => url,
  media: (html) => {
    const voe = extractVoe(html);
    if (!voe) return null;
    // Reihenfolge wie im Swift-Kern: HLS zuerst, dann die direkte Datei,
    // dann eine als MP4 gelieferte `source`.
    if (voe.source?.includes(".m3u8") && isAllowedMediaURL(voe.source)) {
      return { kind: "hls", url: voe.source };
    }
    if (voe.direct && isAllowedMediaURL(voe.direct)) {
      return { kind: "mp4", url: voe.direct };
    }
    if (voe.source?.includes(".mp4") && isAllowedMediaURL(voe.source)) {
      return { kind: "mp4", url: voe.source };
    }
    return null;
  },
};

export const HOSTER_SITES: HosterSite[] = [
  VOE,
  embedOnly("Filemoon", "filemoon"),
  embedOnly("Vidmoly", "vidmoly"),
  embedOnly("Doodstream", "dood"),
];

export function matchingSite(hoster: string): HosterSite | null {
  const name = hoster.toLowerCase();
  return HOSTER_SITES.find((site) => site.matches(name)) ?? null;
}

export function toEmbed(url: string, hoster: string): string {
  return matchingSite(hoster)?.embed(url) ?? url;
}

/**
 * Erst das Verfahren des erkannten Hosters, dann die der übrigen.
 *
 * Die zweite Runde ist Absicht: viele Seiten sind Spiegel derselben Technik
 * unter anderem Namen. Der erkannte Hoster kommt nur zuerst dran.
 */
export function siteMedia(html: string, hoster: string): MediaHit | null {
  const matched = matchingSite(hoster);
  if (matched) {
    const hit = matched.media(html);
    if (hit) return hit;
  }
  for (const site of HOSTER_SITES) {
    if (site.name === matched?.name) continue;
    const hit = site.media(html);
    if (hit) return hit;
  }
  return null;
}

const HLS_PATTERNS = [
  /file\s*[:=]\s*["'](https:[^"']+\.m3u8[^"']*)["']/i,
  /src\s*[:=]\s*["'](https:[^"']+\.m3u8[^"']*)["']/i,
  /["'](https:[^"']+\.m3u8[^"']*)["']/i,
];

const MP4_PATTERNS = [
  /file\s*[:=]\s*["'](https:[^"']+\.mp4[^"']*)["']/i,
  /["'](https:[^"']+\.mp4[^"']*)["']/i,
];

export function firstMedia(html: string): MediaHit | null {
  for (const pattern of HLS_PATTERNS) {
    const url = html.match(pattern)?.[1];
    if (url && isAllowedMediaURL(url)) return { kind: "hls", url };
  }
  for (const pattern of MP4_PATTERNS) {
    const url = html.match(pattern)?.[1];
    if (url && isAllowedMediaURL(url) && !url.includes("test-videos.co.uk")) {
      return { kind: "mp4", url };
    }
  }
  return null;
}
