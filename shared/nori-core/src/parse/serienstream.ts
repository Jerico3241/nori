// Serienstream-Parser, aus `HTML.swift` übernommen (parseCatalogSerienstream,
// parseSeriesSerienstream, parseWatchSerienstream, parseSerienstreamCalendar).

import { all, attr, first, nilIfEmpty, parseHtml, text } from "../dom.js";
import type {
  AiringEntry, CatalogItem, Episode, HosterOption, SeasonRef, SeriesDetail, WatchInfo,
} from "../models.js";
import {
  MONTH_NAMES, berlinTime, berlinWeekday, coverPathFromCalendar, dropAnimeTitles, flagLabel,
  langLabel, normalize, packCalendar, slugFromHref, slugFromPoster, sourcePoster, unique,
} from "./common.js";

const DROP_GENRES = new Set(["anime", "animation", "zeichentrick"]);

export function parseCatalog(html: string): CatalogItem[] {
  const doc = parseHtml(html);
  const seen = new Map<string, CatalogItem>();
  const dropped = new Set<string>();
  let usedGenre = false;

  const ingest = (a: Element, genre: string | null, drop: boolean) => {
    const href = attr(a, "href");
    if (href.includes("staffel-") || href.includes("episode-") || href.includes("/filme")) return;
    const slug = slugFromHref(href);
    if (!slug) return;
    if (drop) {
      dropped.add(slug);
      return;
    }
    const title = normalize(text(a));
    if (!title) return;
    const existing = seen.get(slug);
    if (existing) {
      if (genre && !existing.genres.includes(genre)) existing.genres.push(genre);
      return;
    }
    const search = normalize(attr(a.parentElement, "data-search"));
    const alts = unique(
      search.split(/[|,]/).map((s) => s.trim()).filter((s) => s && s.toLowerCase() !== title.toLowerCase()),
    ).slice(0, 8);
    seen.set(slug, { slug, title, alts, genres: genre ? [genre] : [] });
  };

  for (const h3 of all(doc, "h3")) {
    const genre = normalize(text(h3));
    if (!genre || genre.toLowerCase().startsWith("filter.")) continue;
    const parent = h3.parentElement;
    if (!parent) continue;
    let list: Element | null = null;
    let sibling = parent.nextElementSibling;
    while (sibling) {
      if (sibling.tagName.toLowerCase() === "ul" && (sibling.getAttribute("class") ?? "").includes("series-list")) {
        list = sibling;
        break;
      }
      sibling = sibling.nextElementSibling;
    }
    if (!list) continue;
    usedGenre = true;
    const drop = DROP_GENRES.has(genre.toLowerCase());
    for (const a of all(list, "li.series-item a[href*='/serie/']")) ingest(a, genre, drop);
  }

  if (!usedGenre) {
    for (const a of all(doc, "li.series-item a[href*='/serie/']")) ingest(a, null, false);
    return dropAnimeTitles(Array.from(seen.values()));
  }
  return dropAnimeTitles(Array.from(seen.values()).filter((item) => !dropped.has(item.slug)));
}

export function parseSeries(html: string, slug: string, requestedSeason?: string | null): SeriesDetail {
  const doc = parseHtml(html);
  const title = normalize(text(first(doc, "h1"))) || slug;

  const visibleDescription = normalize(text(first(doc, ".description-text")));
  const metaDescription = attr(first(doc, "meta[name='description']"), "content");
  const description = nilIfEmpty(visibleDescription) ?? metaDescription;

  const coverPath = sourcePoster(doc, "/media/images/channel/", "img");

  const seasons: SeasonRef[] = [];
  const seen = new Set<string>();
  for (const a of all(doc, `a[href*='/serie/${cssEscape(slug)}/']`)) {
    const href = attr(a, "href");
    if (href.includes("/filme")) {
      if (!seen.has("filme")) {
        seen.add("filme");
        seasons.push({ id: "filme", label: "Filme" });
      }
      continue;
    }
    const m = href.match(/staffel-(\d+)/);
    if (m && !seen.has(m[1])) {
      seen.add(m[1]);
      seasons.push({ id: m[1], label: `Staffel ${m[1]}` });
    }
  }
  seasons.sort((a, b) => {
    if (a.id === "filme") return 1;
    if (b.id === "filme") return -1;
    return (Number(a.id) || 0) - (Number(b.id) || 0);
  });
  if (seasons.length === 0) seasons.push({ id: "1", label: "Staffel 1" });

  const episodes: Episode[] = [];
  for (const row of all(doc, ".episode-row")) {
    const onclick = attr(row, "onclick");
    let href = "";
    const m = onclick.match(/['"](\/serie\/[^'"]+)['"]/);
    if (m) href = m[1];
    if (!href) href = attr(first(row, "a[href*='episode-']"), "href");
    if (!href) href = attr(first(row, "a[href*='/filme/']"), "href");
    href = href.split("?")[0];

    const film = href.match(/\/filme\/(?:film-)?(\d+)/);
    const episodeMatch = href.match(/episode-(\d+)/);
    const rowNumber = text(first(row, ".episode-number-cell"));
    let numRaw = "";
    if (film) numRaw = film[1];
    else if (episodeMatch) numRaw = episodeMatch[1];
    else numRaw = rowNumber;
    const digits = numRaw.replace(/\D/g, "");
    const number = digits ? Number(digits) : episodes.length + 1;

    const germanTitle = normalize(text(first(row, ".episode-title-ger")));
    const englishTitle = normalize(text(first(row, ".episode-title-eng")));
    const hosters = unique(
      all(row, "img.watch-link, img[alt]").map((img) =>
        (attr(img, "alt") || attr(img, "title")).replace(/^Hoster\s+/i, "").trim(),
      ),
    );
    const languages = unique(
      all(row, "svg.watch-language, svg[class*='flag']").map((svg) => flagLabel(svgClass(svg))),
    );
    if (!href && !germanTitle && !englishTitle) continue;
    const fallback = film ? `Film ${number}` : `Folge ${number}`;
    episodes.push({
      number,
      germanTitle: germanTitle || englishTitle || fallback,
      englishTitle,
      path: href,
      hosters,
      languages,
    });
  }

  let activeSeason = requestedSeason ?? "";
  if (!activeSeason) {
    const href = attr(first(doc, `a[href*='/serie/${cssEscape(slug)}/staffel-'].active`), "href");
    const m = href.match(/staffel-(\d+)/);
    activeSeason = m ? m[1] : (seasons.find((s) => s.id !== "filme")?.id ?? "1");
  }

  return {
    slug, title, alts: [], description, coverPath,
    yearStart: null, yearEnd: null, fsk: null, imdb: null,
    genres: [], seasons, activeSeason, episodes,
  };
}

export function parseWatch(html: string, path: string): WatchInfo {
  const doc = parseHtml(html);
  const h1 = normalize(text(first(doc, "h1")));
  const germanTitle = nilIfEmpty(text(first(doc, ".episode-title-ger"))) ?? h1;
  const englishTitle = text(first(doc, ".episode-title-eng"));
  const hosters: HosterOption[] = [];
  const seen = new Set<string>();

  for (const el of all(doc, "button.link-box[data-play-url]")) {
    const playUrl = attr(el, "data-play-url");
    if (!playUrl.startsWith("/r")) continue;
    const name = normalize(attr(el, "data-provider-name") || text(el) || "Hoster");
    const langKey = attr(el, "data-language-id") || "1";
    const key = `${playUrl}|${langKey}`;
    if (seen.has(key)) continue;
    seen.add(key);
    hosters.push({ name: name || "Hoster", lang: langLabel(langKey), langKey, redirectPath: playUrl });
  }

  return { path, title: h1, germanTitle, englishTitle, hosters };
}

interface CalendarRow {
  url?: string;
  poster?: string;
  time?: string;
  language_id?: number;
  language?: string;
  season?: number;
  episode?: number;
  title?: string;
}

export function parseCalendar(raw: unknown): AiringEntry[] {
  const obj = (raw ?? {}) as Record<string, CalendarRow[]>;
  const merged = new Map<string, AiringEntry>();

  for (const [dayKey, rows] of Object.entries(obj)) {
    const parts = dayKey.split("-").map((p) => Number(p));
    if (parts.length !== 3 || parts.some((n) => !Number.isFinite(n))) continue;
    if (!Array.isArray(rows)) continue;
    const [year, month, day] = parts;
    const dayLabel = `${berlinWeekday(year, month, day)}, ${day}. ${MONTH_NAMES[month] ?? ""}`;

    for (const row of rows) {
      const url = row.url ?? "";
      const poster = row.poster ?? "";
      const slug = slugFromHref(url) ?? slugFromPoster(poster) ?? "";
      if (!slug) continue;
      const [hourRaw, minuteRaw] = (row.time ?? "00:00").split(":");
      const airingAt = berlinTime(year, month, day, Number(hourRaw) || 0, Number(minuteRaw) || 0);
      const langId = row.language_id;
      let lang: string | null;
      if (langId === 1) lang = "DE";
      else if (langId === 2) lang = "EN";
      else if (langId === 3) lang = "GerSub";
      else lang = flagLabel(row.language ?? "");
      const season = String(row.season ?? 1);
      const episode = row.episode ?? 0;
      const key = `${slug}|${season}|${episode}|${dayKey}|${lang ?? ""}`;
      const existing = merged.get(key);
      if (existing) {
        if (lang && !existing.languages.includes(lang)) existing.languages.push(lang);
        continue;
      }
      merged.set(key, {
        airingAt, episode, season,
        title: row.title ?? slug,
        english: null,
        slug,
        languages: lang ? [lang] : [],
        dayKey, dayLabel,
        coverPath: coverPathFromCalendar(poster),
      });
    }
  }
  return Array.from(merged.values());
}

export function parseCalendarPayload(raw: unknown, now = Date.now()) {
  return packCalendar(parseCalendar(raw), now);
}

/** Slugs stehen in Selektoren; Sonderzeichen dürfen den Selektor nicht sprengen. */
function cssEscape(value: string): string {
  return value.replace(/['\\]/g, "\\$&");
}

function svgClass(svg: Element): string {
  const raw = svg.getAttribute("class");
  if (raw) return raw;
  // In manchen DOM-Umsetzungen ist `class` bei SVG nur über `className.baseVal`
  // zu haben; `getAttribute` liefert dort null.
  const cn = (svg as unknown as { className?: { baseVal?: string } }).className;
  return cn?.baseVal ?? "";
}
