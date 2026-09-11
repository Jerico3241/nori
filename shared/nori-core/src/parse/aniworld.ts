// AniWorld-Parser, aus `HTML.swift` übernommen (parseCatalog, parseSeries,
// parseSeasons, parseEpisodes, parseWatch, parseAniworldCalendar).

import { all, attr, first, nilIfEmpty, parseHtml, text } from "../dom.js";
import type {
  AiringEntry, CatalogItem, Episode, HosterOption, SeasonRef, SeriesDetail, WatchInfo,
} from "../models.js";
import {
  MONTH_NAMES, berlinTime, coverPathFromCalendar, flagLabel, langLabel, normalize,
  packCalendar, slugFromHref, sourcePoster, toAniworldPath, unique,
} from "./common.js";

export function parseCatalog(html: string): CatalogItem[] {
  const doc = parseHtml(html);
  const seen = new Map<string, CatalogItem>();
  const items: CatalogItem[] = [];

  const ingest = (href: string, title: string, altRaw: string, genre: string | null) => {
    const path = toAniworldPath(href);
    const match = path.match(/^\/anime\/stream\/([^/?#]+)/);
    if (!match) return;
    const slug = match[1];
    if (!slug) return;
    const cleanTitle = normalize(title);
    if (!cleanTitle) return;
    const alts = unique(
      altRaw.split(",").map((s) => s.trim()).filter((s) => s.toLowerCase() !== cleanTitle.toLowerCase()),
    ).slice(0, 8);

    const existing = seen.get(slug);
    if (existing) {
      if (genre && !existing.genres.includes(genre)) existing.genres.push(genre);
      return;
    }
    const rec: CatalogItem = { slug, title: cleanTitle, alts, genres: genre ? [genre] : [] };
    seen.set(slug, rec);
    items.push(rec);
  };

  const genreBlocks = all(doc, ".genre");
  for (const block of genreBlocks) {
    const genre = nilIfEmpty(text(first(block, "h3")));
    for (const a of all(block, "a")) {
      ingest(attr(a, "href"), text(a), attr(a, "data-alternative-title"), genre);
    }
  }

  // Fällt der Genre-Aufbau weg, ist eine Katalogseite immer noch eine Linkliste.
  if (items.length < 20) {
    for (const a of all(doc, "a")) {
      ingest(
        attr(a, "href"),
        text(a),
        attr(a, "data-alternative-title") || attr(a, "data-alternativeTitles"),
        null,
      );
    }
  }
  return items;
}

export function parseSeasons(doc: Document): SeasonRef[] {
  const seasons: SeasonRef[] = [];
  const seen = new Set<string>();
  const nav = first(doc, ".hosterSiteDirectNav");
  const list = nav ? first(nav, "ul") : null;
  for (const a of list ? all(list, "a") : []) {
    const href = toAniworldPath(attr(a, "href"));
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
  return seasons;
}

export function parseEpisodes(doc: Document): Episode[] {
  const episodes: Episode[] = [];
  for (const tr of all(doc, "table.seasonEpisodesList tbody tr")) {
    const titleLink = first(tr, ".seasonEpisodeTitle a");
    let href = toAniworldPath(attr(titleLink, "href"));
    if (!href) href = toAniworldPath(attr(first(tr, "a[href*='episode-']"), "href"));
    if (!href) href = toAniworldPath(attr(first(tr, "a[href*='/filme/film-']"), "href"));

    const film = href.match(/\/filme\/film-(\d+)/);
    const episodeMatch = href.match(/episode-(\d+)/);
    const metaNumber = attr(first(tr, "meta[itemprop='episodeNumber']"), "content");
    const cellNumber = text(first(tr, "td"));
    let numRaw = "";
    if (film) numRaw = film[1];
    else if (episodeMatch) numRaw = episodeMatch[1];
    else if (metaNumber) numRaw = metaNumber;
    else numRaw = cellNumber;
    const digits = numRaw.replace(/\D/g, "");
    const number = digits ? Number(digits) : episodes.length + 1;

    const germanTitle = titleLink ? normalize(text(first(titleLink, "strong"))) : "";
    const englishTitle = titleLink ? normalize(text(first(titleLink, "span"))) : "";
    const hosters = unique(
      all(tr, "i.icon").map((el) => attr(el, "title").replace(/^Hoster\s+/i, "").trim()),
    );
    const languages = unique(
      all(tr, "img.flag").map((el) => flagLabel(attr(el, "title") || attr(el, "alt"))),
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
  return episodes;
}

export function parseSeries(html: string, slug: string, requestedSeason?: string | null): SeriesDetail {
  const doc = parseHtml(html);
  const titleEl = first(doc, ".series-title h1");
  const spanTitle = titleEl ? nilIfEmpty(text(first(titleEl, "span"))) : null;
  const elementTitle = nilIfEmpty(text(titleEl));
  const fallbackTitle = nilIfEmpty(text(first(doc, "h1")));
  const title = spanTitle ?? elementTitle ?? fallbackTitle ?? slug;

  const altRaw = attr(titleEl, "data-alternativeTitles") || attr(titleEl, "title");
  const alts = unique(
    altRaw.replace(/^Animes Stream:\s*/, "").split(",").map((s) => s.trim())
      .filter((s) => s && s.toLowerCase() !== title.toLowerCase()),
  ).slice(0, 8);

  const desEl = first(doc, "p.seri_des");
  const fullDescription = attr(desEl, "data-full-description");
  const shortDescription = normalize(text(desEl).replace(/mehr anzeigen/gi, ""));
  const description = nilIfEmpty(fullDescription) ?? shortDescription;

  const coverPath = sourcePoster(doc, "/public/img/cover/", ".seriesCoverBox img");

  const yearStart = nilIfEmpty(text(first(doc, "span[itemprop='startDate']")));
  const yearEnd = nilIfEmpty(text(first(doc, "span[itemprop='endDate']")));
  const fsk = nilIfEmpty(attr(first(doc, "[data-fsk]"), "data-fsk"));
  const imdb = nilIfEmpty(attr(first(doc, "a.imdb-link"), "data-imdb"));
  const genres = unique(
    all(doc, "a.genreButton").map((el) => text(el)).filter((n) => {
      const low = n.toLowerCase();
      return low && low !== "ger" && low !== "engsub" && low !== "gersub";
    }),
  );

  const seasons = parseSeasons(doc);
  const episodes = parseEpisodes(doc);

  let activeSeason = requestedSeason ?? "";
  if (!activeSeason) {
    const activeHref = toAniworldPath(attr(first(doc, ".hosterSiteDirectNav a.active"), "href"));
    const m = activeHref.match(/staffel-(\d+)/);
    if (activeHref.includes("/filme")) activeSeason = "filme";
    else if (m) activeSeason = m[1];
    else activeSeason = seasons.find((s) => s.id !== "filme")?.id ?? seasons[0]?.id ?? "1";
  }

  return {
    slug, title, alts, description, coverPath,
    yearStart, yearEnd, fsk, imdb, genres, seasons, activeSeason, episodes,
  };
}

export function parseWatch(html: string, path: string): WatchInfo {
  const doc = parseHtml(html);
  const h1 = normalize(text(first(doc, "h1")));
  const strongTitle = nilIfEmpty(text(first(doc, ".seasonEpisodeTitle strong")));
  const h2Title = nilIfEmpty(text(first(doc, "h2")));
  const germanTitle = strongTitle ?? h2Title ?? h1;
  const englishTitle = text(first(doc, ".seasonEpisodeTitle span"));

  const hosters: HosterOption[] = [];
  const seen = new Set<string>();

  const push = (redirectPath: string, langKey: string, name: string) => {
    let pathOnly = toAniworldPath(redirectPath);
    if (!pathOnly) pathOnly = redirectPath;
    if (!pathOnly.startsWith("/redirect/") && !pathOnly.startsWith("/r")) return;
    const key = `${pathOnly}|${langKey}`;
    if (seen.has(key)) return;
    seen.add(key);
    const clean = name.replace(/^Hoster\s+/i, "").trim();
    hosters.push({
      name: clean || "Hoster",
      lang: langLabel(langKey),
      langKey,
      redirectPath: pathOnly,
    });
  };

  for (const el of all(doc, "li[data-link-id]")) {
    const id = attr(el, "data-link-id");
    const target = attr(el, "data-link-target") || (id ? `/redirect/${id}` : "");
    const langKey = attr(el, "data-lang-key") || "1";
    const name = nilIfEmpty(text(first(el, "h4"))) ?? attr(first(el, "i.icon"), "title") ?? "Hoster";
    push(target, langKey, name || "Hoster");
  }

  if (hosters.length === 0) {
    for (const a of all(doc, "a[href*='redirect']")) {
      const href = attr(a, "href");
      const parent = a.parentElement;
      const langKey = attr(parent, "data-lang-key") || "1";
      const name = nilIfEmpty(text(first(a, "h4"))) ?? attr(first(a, "i.icon"), "title") ?? "Hoster";
      push(href, langKey, name || "Hoster");
    }
  }

  return { path, title: h1, germanTitle, englishTitle, hosters };
}

export function parseCalendar(html: string, now = Date.now()): AiringEntry[] {
  const doc = parseHtml(html);
  const merged = new Map<string, AiringEntry>();

  for (const section of all(doc, "section.calendarList")) {
    const heading = normalize(text(first(section, "h3")));
    const dateMatch = heading.match(/(\d{1,2})\.(\d{1,2})\.(\d{4})/);
    if (!dateMatch) continue;
    const day = Number(dateMatch[1]);
    const month = Number(dateMatch[2]);
    const year = Number(dateMatch[3]);
    const dayKey = `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
    const weekday = heading.split(",")[0]?.trim() ?? "";
    const monthName = MONTH_NAMES[month] ?? "";
    const dayLabel = `${weekday}, ${day}. ${monthName}`;

    for (const a of all(section, "a[href*='anime/stream']")) {
      const slug = slugFromHref(attr(a, "href"));
      if (!slug) continue;
      const title = normalize(text(first(a, "h3.seriesTitle") ?? first(a, ".seriesTitle") ?? first(a, "h3")) || slug);
      const small = all(a, "small").map((s) => text(s)).join(" ");
      const blob = `${small} ${text(a)}`;
      let season = "1";
      let episode = 0;
      const se = blob.match(/S(\d+)\s*E(\d+)/i);
      if (se) {
        season = String(Number(se[1]) || 1);
        episode = Number(se[2]) || 0;
      }
      let hour = 0;
      let minute = 0;
      // Ob überhaupt eine Uhrzeit dastand. Ohne das wäre eine fehlende Angabe
      // von einer Ausstrahlung um 00:00 nicht zu unterscheiden.
      let hasTime = false;
      const t = small.match(/(\d{1,2}):(\d{2})/);
      if (t) {
        hour = Number(t[1]) || 0;
        minute = Number(t[2]) || 0;
        hasTime = true;
      }
      const airingAt = berlinTime(year, month, day, hour, minute);
      const languages = unique(
        all(a, "img.flag").map((img) =>
          flagLabel(`${attr(img, "title")} ${attr(img, "alt")} ${attr(img, "src")}`),
        ),
      );
      const cover = all(a, "img")
        .filter((img) => !(img.getAttribute("class") ?? "").includes("flag"))
        .map((img) => coverPathFromCalendar(attr(img, "data-src") || attr(img, "src")))
        .find((c): c is string => Boolean(c)) ?? null;

      const key = `${slug}|${season}|${episode}|${dayKey}`;
      const existing = merged.get(key);
      if (existing) {
        existing.languages = unique([...existing.languages, ...languages]);
        if (!existing.coverPath) existing.coverPath = cover;
        // Nennt eine der zusammengeführten Zeilen eine Uhrzeit, gilt sie für
        // den Eintrag — die Sprachzeilen derselben Folge tragen sie nicht
        // immer beide.
        if (hasTime && existing.hasTime !== true) {
          existing.hasTime = true;
          existing.airingAt = airingAt;
        }
        continue;
      }
      merged.set(key, {
        airingAt, episode, season,
        title: title || slug,
        english: null,
        slug, languages, dayKey, dayLabel, coverPath: cover, hasTime,
      });
    }
  }
  void now;
  return Array.from(merged.values());
}

export function parseCalendarPayload(html: string, now = Date.now()) {
  return packCalendar(parseCalendar(html, now), now);
}
