// Auflösung eines Hoster-Links zu einer abspielbaren Adresse.
//
// Der Ablauf ist derselbe wie in `HosterResolver.swift`: Weiterleitung der
// Quelle folgen, bis sie beim Hoster landet, dessen Seite holen, den Stream
// herausziehen. Die Reihenfolge der Hoster und die Sprachwahl kommen aus
// `contract.json` und stimmen mit den Apple-Apps überein.

import { NORI_USER_AGENT, NoriError, PROVIDERS, type CatalogProvider, type HosterOption, type PlaySource } from "../models.js";
import { hosterRank, normalizeEpisodePath } from "../rules.js";
import type { HttpClient } from "../http.js";
import { isExternalOrigin, isSafeRemoteURL, looksCaptcha } from "./safety.js";
import { firstMedia, siteMedia, toEmbed } from "./sites.js";

/** Bevorzugten Hoster nach vorn, sonst nach der Rangliste aus contract.json. */
export function orderHosters(hosters: HosterOption[], preferred?: string | null): HosterOption[] {
  const want = (preferred ?? "").toLowerCase();
  return [...hosters].sort((a, b) => {
    const ra = want && a.name.toLowerCase() === want ? -1 : hosterRank(a.name);
    const rb = want && b.name.toLowerCase() === want ? -1 : hosterRank(b.name);
    return ra - rb;
  });
}

/** Erste Sprache aus [Wunsch, DE, GerSub, EN], die überhaupt vorkommt. */
export function pickLang(hosters: HosterOption[], preferred: string): HosterOption[] {
  for (const lang of [preferred, "DE", "GerSub", "EN"]) {
    const hit = hosters.filter((h) => h.lang.toLowerCase() === lang.toLowerCase());
    if (hit.length > 0) return hit;
  }
  return hosters;
}

/** Die Sprachen, die für diese Folge überhaupt angeboten werden. */
export function availableLanguages(hosters: HosterOption[]): string[] {
  const order = ["DE", "GerSub", "EN"];
  const found = new Set(hosters.map((h) => h.lang));
  const sorted = order.filter((l) => found.has(l));
  for (const lang of found) if (!sorted.includes(lang)) sorted.push(lang);
  return sorted;
}

export interface ResolveContext {
  http: HttpClient;
  provider: CatalogProvider;
  episodePath?: string;
}

const REDIRECT_PATTERNS = [
  /<meta[^>]+http-equiv\s*=\s*["']refresh["'][^>]+content\s*=\s*["'][^"']*url\s*=\s*([^"'>\s]+)/i,
  /window\.location\.(?:href|replace)\s*[=(]\s*["'](https?:\/\/[^"']+)["']/i,
  /location\.href\s*=\s*["'](https?:\/\/[^"']+)["']/i,
  /<iframe[^>]+src\s*=\s*["'](https?:\/\/[^"']+)["']/i,
];

export function htmlRedirectTarget(html: string): string | null {
  for (const pattern of REDIRECT_PATTERNS) {
    const raw = html.match(pattern)?.[1];
    if (raw) return raw;
  }
  return null;
}

const BOUNCE_PATTERNS = [
  /window\.location\.href\s*=\s*['"](https?:\/\/[^'"]+\/e\/[A-Za-z0-9]+)['"]/i,
  /location\.href\s*=\s*['"](https?:\/\/[^'"]+\/e\/[A-Za-z0-9]+)['"]/i,
  /window\.location\.href\s*=\s*['"](https?:\/\/[^'"]+)['"]/i,
];

export function extractBounce(html: string): string | null {
  for (const pattern of BOUNCE_PATTERNS) {
    const url = html.match(pattern)?.[1];
    if (!url) continue;
    if (url.includes("translate") || url.includes("voe.sx/api")) continue;
    return url;
  }
  return null;
}

/**
 * Der Weiterleitung der Quelle folgen, bis sie den eigenen Hosts entkommt.
 *
 * Wo die Laufzeit `Location` lesen kann (Node), wird Sprung für Sprung
 * gegangen — genau wie der `RedirectTap` im Swift-Kern, der bei der ersten
 * fremden Adresse abbricht. Im Browser geht das nicht; dort bleibt die
 * Endadresse der gefolgten Kette, die in der Praxis dieselbe ist.
 */
export async function followRedirect(
  redirectPath: string,
  ctx: ResolveContext,
): Promise<string> {
  let start: string;
  if (redirectPath.startsWith("http")) {
    start = redirectPath;
  } else {
    if (!redirectPath.startsWith("/")) throw NoriError.hoster("Ungültiger Hoster");
    start = PROVIDERS[ctx.provider].origin + redirectPath;
  }

  const origin = PROVIDERS[ctx.provider].origin;
  const referer = ctx.episodePath
    ? origin + normalizeEpisodePath(ctx.episodePath)
    : origin + "/";
  const headers: Record<string, string> = {
    "User-Agent": NORI_USER_AGENT,
    "Accept-Language": "de-DE,de;q=0.9",
    Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    // Die Weiterleitung wird aus der Episodenseite heraus aufgerufen. Mit dem
    // blanken Origin als Referer weist sich der Abruf als nicht von dort
    // kommend aus, was manche Quellen abweisen.
    Referer: referer,
  };

  if (ctx.http.canReadRedirects) {
    let current = start;
    for (let hop = 0; hop < 8; hop += 1) {
      const res = await ctx.http.request(current, { headers, redirect: "manual" });
      if (res.status >= 300 && res.status < 400) {
        const location = res.headers.get("location");
        if (!location) break;
        const next = new URL(location, current).toString();
        if (isExternalOrigin(next)) return next;
        current = next;
        continue;
      }
      if (res.status >= 400) {
        throw NoriError.hoster(`Weiterleitung endete nicht beim Hoster (HTTP ${res.status})`);
      }
      const html = await res.text();
      const target = htmlRedirectTarget(html);
      if (target) {
        const absolute = new URL(target, current).toString();
        if (isExternalOrigin(absolute)) return absolute;
      }
      throw NoriError.hoster(redirectDiagnosis(res.status, current, html));
    }
    throw NoriError.hoster("Weiterleitung endete nicht beim Hoster (zu viele Sprünge)");
  }

  const res = await ctx.http.request(start, { headers, redirect: "follow" });
  if (res.url && isExternalOrigin(res.url)) return res.url;
  const html = await res.text();
  const target = htmlRedirectTarget(html);
  if (target) {
    const absolute = new URL(target, res.url || start).toString();
    if (isExternalOrigin(absolute)) return absolute;
  }
  throw NoriError.hoster(redirectDiagnosis(res.status, res.url || start, html));
}

/**
 * Ohne Zugriff auf die Quelle ist die Fehlermeldung das einzige
 * Diagnosewerkzeug. Sie soll unterscheiden, ob die Anfrage abgewiesen wurde,
 * eine Schutzseite kam oder nur die Weiterleitung fehlt.
 */
function redirectDiagnosis(status: number, url: string, html: string): string {
  const parts = [`HTTP ${status}`];
  try {
    parts.push(new URL(url).hostname);
  } catch {
    /* ohne Host */
  }
  parts.push(looksCaptcha(html) ? "Schutzseite/Captcha" : `${html.length} Bytes ohne Weiterleitung`);
  return `Weiterleitung endete nicht beim Hoster (${parts.join(", ")})`;
}

async function extract(
  embedUrl: string,
  hoster: string,
  lang: string,
  http: HttpClient,
): Promise<PlaySource> {
  if (!isSafeRemoteURL(embedUrl)) throw NoriError.hoster(`${hoster}: unsichere Ziel-URL`);
  let page = toEmbed(embedUrl, hoster);
  if (!isSafeRemoteURL(page)) throw NoriError.hoster(`${hoster}: unsichere Embed-URL`);

  const load = async (url: string, referer: string) => {
    const res = await http.request(url, {
      headers: { "User-Agent": NORI_USER_AGENT, Referer: referer },
    });
    if (res.status >= 400) throw NoriError.network(`HTTP ${res.status}`);
    return res.text();
  };

  let html = await load(page, page);
  if (looksCaptcha(html)) throw NoriError.hoster(`${hoster}: Captcha`);

  const bounce = extractBounce(html);
  if (bounce && bounce !== page) {
    if (!isSafeRemoteURL(bounce)) throw NoriError.hoster(`${hoster}: unsichere Weiterleitung`);
    html = await load(bounce, page);
    page = bounce;
    if (looksCaptcha(html)) throw NoriError.hoster(`${hoster}: Captcha`);
  }

  const hit = siteMedia(html, hoster) ?? firstMedia(html);
  if (!hit) throw NoriError.hoster(`${hoster} liefert keinen Stream`);
  return { kind: hit.kind, url: hit.url, hoster, lang, referer: page };
}

export async function resolveHoster(
  option: HosterOption,
  ctx: ResolveContext,
): Promise<PlaySource> {
  const embed = await followRedirect(option.redirectPath, ctx);
  return extract(embed, option.name, option.lang, ctx.http);
}

export interface ResolveBestOptions extends ResolveContext {
  preferredHoster?: string;
  preferredLang?: string;
  /** Vorab bereits gescheiterte Hoster, etwa nach einem Streamfehler im Player. */
  skip?: string[];
  onAttempt?: (option: HosterOption) => void;
}

export async function resolveBest(
  hosters: HosterOption[],
  options: ResolveBestOptions,
): Promise<PlaySource> {
  const langMatched = pickLang(hosters, options.preferredLang ?? "DE");
  const skip = new Set((options.skip ?? []).map((s) => s.toLowerCase()));
  const ranked = orderHosters(langMatched, options.preferredHoster)
    .filter((h) => !skip.has(`${h.name}|${h.lang}`.toLowerCase()));
  if (ranked.length === 0) {
    throw NoriError.hoster("Für diese Folge ist kein Hoster eingetragen.");
  }
  // Jeden Fehlschlag mit Hoster und Grund festhalten: sonst bleibt nur die
  // Meldung des zuletzt versuchten Hosters, und daran ist nicht zu erkennen,
  // ob ein einzelner Hoster klemmt oder alle.
  const failures: string[] = [];
  for (const option of ranked) {
    try {
      options.onAttempt?.(option);
      return await resolveHoster(option, options);
    } catch (error) {
      let reason = (error as Error)?.message ?? "unbekannter Fehler";
      const prefix = `${option.name}: `;
      if (reason.startsWith(prefix)) reason = reason.slice(prefix.length);
      failures.push(`${option.name} (${option.lang}): ${reason}`);
    }
  }
  throw NoriError.hoster(`Kein Hoster lieferte einen Stream.\n${failures.join("\n")}`);
}
