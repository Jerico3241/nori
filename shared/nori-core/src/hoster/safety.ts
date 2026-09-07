// Adressprüfungen aus `HosterResolver.swift`.
//
// Diese Datei ist eine Sicherheitsgrenze, keine Formsache: der Resolver folgt
// fremden Weiterleitungen, und ohne diese Prüfungen wäre das ein offener
// Zugang zu allem, was vom Gerät aus erreichbar ist — Router-Oberflächen,
// Metadatendienste, Dienste im Heimnetz. Nicht aufweichen (siehe CLAUDE.md).

export function isSafeRemoteURL(input: URL | string): boolean {
  let url: URL;
  try {
    url = typeof input === "string" ? new URL(input) : input;
  } catch {
    return false;
  }
  if (url.protocol.toLowerCase() !== "https:") return false;
  if (url.username || url.password) return false;
  const host = url.hostname.toLowerCase();
  if (!host) return false;

  if (host === "localhost" || host.endsWith(".localhost") || host.endsWith(".local")) return false;
  if (host === "::1" || host === "[::1]" || host === "0.0.0.0") return false;

  const octets = host.split(".").map((p) => (/^\d+$/.test(p) ? Number(p) : NaN));
  if (octets.length === 4 && octets.every((n) => Number.isFinite(n) && n >= 0 && n <= 255)) {
    const [a, b] = octets;
    if (a === 10 || a === 127 || a === 0) return false;
    if (a === 169 && b === 254) return false;
    if (a === 172 && b >= 16 && b <= 31) return false;
    if (a === 192 && b === 168) return false;
    if (a === 100 && b >= 64 && b <= 127) return false;
    if (a >= 224) return false;
  }

  const bare = host.replace(/^\[|\]$/g, "");
  if (bare.startsWith("fc") || bare.startsWith("fd") || bare.startsWith("fe80:")) return false;
  return true;
}

/** Sieht die Adresse nach Medien aus? Wie im Swift-Kern über Pfad und Query. */
export function isAllowedMediaURL(raw: string): boolean {
  if (!isSafeRemoteURL(raw)) return false;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return false;
  }
  const path = (url.pathname + url.search).toLowerCase();
  return path.includes(".m3u8") || path.includes(".mp4") || path.includes(".m4s")
    || path.includes(".ts") || path.includes("urlset") || path.includes("/hls")
    || path.includes("playlist");
}

/** Zielt die Adresse auf einen Hoster und nicht zurück auf die Quelle? */
export function isExternalOrigin(input: URL | string): boolean {
  let url: URL;
  try {
    url = typeof input === "string" ? new URL(input) : input;
  } catch {
    return false;
  }
  const host = url.hostname.toLowerCase();
  if (!host) return false;
  return !host.includes("aniworld") && !host.includes("serienstream");
}

export function looksCaptcha(html: string): boolean {
  const h = html.slice(0, 4000).toLowerCase();
  return h.includes("cf-turnstile") || h.includes("g-recaptcha") || h.includes("hcaptcha")
    || h.includes("just a moment") || h.includes("ddos-guard");
}

export function looksBlocked(html: string): boolean {
  const head = html.slice(0, 800).toLowerCase();
  return html.length < 800
    || head.includes("ddos-guard")
    || head.includes("just a moment")
    || head.includes("cf-turnstile");
}
