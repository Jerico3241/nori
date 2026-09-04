import { r as __exportAll } from "../_runtime.mjs";
import { t as __exportAll$1 } from "./rolldown-runtime-D7D4PA-g.mjs";
import { n as scrapeFail } from "./errors-D28ORtyS.mjs";
import { t as catalog_fallback_default } from "./catalog-fallback-D0Cgu-LQ.mjs";
import { n as looksDdos, t as fetchOrigin } from "./http.server-D7YcQUwF.mjs";
import { t as load } from "../_libs/cheerio+[...].mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/scrape.server-Dx4-7B2O.js
var scrape_server_Dx4_7B2O_exports = /* @__PURE__ */ __exportAll({
	a: () => toAniworldPath,
	i: () => scrape_server_exports,
	n: () => fetchAniworldPage,
	o: () => unwrapTranslateUrl,
	r: () => fetchExternalPage,
	t: () => BROWSER_HEADERS
});
var scrape_server_exports = /* @__PURE__ */ __exportAll$1({
	BROWSER_HEADERS: () => BROWSER_HEADERS,
	ORIGIN: () => ORIGIN,
	fetchAniworldAsset: () => fetchAniworldAsset,
	fetchAniworldPage: () => fetchAniworldPage,
	fetchAniworldPageUncached: () => fetchAniworldPageUncached,
	fetchExternalPage: () => fetchExternalPage,
	getCatalog: () => getCatalog,
	getSeries: () => getSeries,
	htmlProxyUrls: () => htmlProxyUrls,
	parseCatalog: () => parseCatalog,
	parseSeries: () => parseSeries,
	toAniworldPath: () => toAniworldPath,
	unwrapTranslateUrl: () => unwrapTranslateUrl
});
var ORIGIN = "https://aniworld.to";
var FALLBACK = catalog_fallback_default;
var catalogCache = /* @__PURE__ */ new Map();
var seriesCache = /* @__PURE__ */ new Map();
var htmlCache = /* @__PURE__ */ new Map();
var htmlInflight = /* @__PURE__ */ new Map();
var seriesInflight = /* @__PURE__ */ new Map();
var catalogInflight = null;
var CATALOG_TTL = 18e5;
var SERIES_TTL = 6e5;
var HTML_TTL = 48e4;
var BROWSER_HEADERS = {
	"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
	Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
	"Accept-Language": "de-DE,de;q=0.9,en;q=0.8"
};
function toAniworldPath(href) {
	if (!href) return "";
	const cleaned = href.replace(/&amp;/g, "&").trim();
	const stream = cleaned.match(/\/anime\/stream\/[^?\s#]+/);
	if (stream) return stream[0].replace(/\/+$/, "");
	const redirect = cleaned.match(/\/redirect\/\d+/);
	if (redirect) return redirect[0];
	if (cleaned.startsWith("/")) return cleaned.split("?")[0];
	return "";
}
function unwrapTranslateUrl(url) {
	try {
		const u = new URL(url.replace(/&amp;/g, "&"));
		if (u.hostname.endsWith(".translate.goog")) {
			const host = u.hostname.replace(/\.translate\.goog$/, "").replace(/-/g, ".");
			return `${u.protocol}//${host}${u.pathname}`;
		}
		return `${u.protocol}//${u.hostname}${u.pathname}`;
	} catch {
		return url;
	}
}
function htmlProxyUrls(target) {
	const encoded = encodeURIComponent(target);
	return [
		target,
		`https://translate.google.com/translate?sl=de&tl=en&u=${encoded}`,
		`https://api.allorigins.win/raw?url=${encoded}`,
		`https://api.allorigins.win/get?url=${encoded}`,
		`https://api.codetabs.com/v1/proxy?quest=${encoded}`
	];
}
function assetProxyUrls(target) {
	const encoded = encodeURIComponent(target);
	return [
		target,
		`https://api.allorigins.win/raw?url=${encoded}`,
		`https://api.codetabs.com/v1/proxy?quest=${encoded}`
	];
}
function looksBlocked(html) {
	const head = html.slice(0, 800).toLowerCase();
	return html.length < 1500 || looksDdos(html) || head.includes("error code: 522") || head.includes("oops... request timeout") || head.includes("allorigins.win | 522") || head.includes("connection timed out");
}
function looksLikeAniworld(html) {
	return html.includes("/anime/stream/") || html.includes("seasonEpisodesList") || html.includes("series-title") || html.includes("data-link-id") || html.includes("class=\"genre\"");
}
function combineSignals(timeoutMs, extra) {
	const timeout = AbortSignal.timeout(timeoutMs);
	return extra ? AbortSignal.any([timeout, extra]) : timeout;
}
async function fetchRaw(url, timeoutMs, extra) {
	const res = await fetchOrigin(url, {
		timeout: timeoutMs,
		extra,
		referer: `${ORIGIN}/`
	});
	if (!res.ok) throw new Error(`HTTP ${res.status}`);
	const text = await res.text();
	if (url.includes("allorigins.win/get?")) try {
		const parsed = JSON.parse(text);
		if (typeof parsed.contents === "string") return parsed.contents;
	} catch {}
	return text;
}
async function fetchAniworldPageUncached(path) {
	const urls = htmlProxyUrls(path.startsWith("http") ? path : `${ORIGIN}${path}`);
	const controller = new AbortController();
	const tryOne = async (url, timeout) => {
		const html = await fetchRaw(url, timeout, controller.signal);
		if (looksBlocked(html) || !looksLikeAniworld(html)) throw new Error("blocked");
		return html;
	};
	try {
		try {
			const html = await tryOne(urls[0], 3200);
			controller.abort();
			return html;
		} catch {}
		const html = await Promise.any(urls.slice(1).map((url) => tryOne(url, 6e3)));
		controller.abort();
		return html;
	} catch {
		throw scrapeFail("blocked", "AniWorld nicht erreichbar");
	}
}
async function fetchAniworldPage(path) {
	const key = path;
	const hit = htmlCache.get(key);
	if (hit && hit.expires > Date.now()) return hit.value;
	const existing = htmlInflight.get(key);
	if (existing) return existing;
	const promise = fetchAniworldPageUncached(path).then((html) => {
		htmlCache.set(key, {
			value: html,
			expires: Date.now() + HTML_TTL
		});
		return html;
	}).finally(() => {
		htmlInflight.delete(key);
	});
	htmlInflight.set(key, promise);
	return promise;
}
async function fetchExternalPage(url, referer) {
	const res = await fetch(url, {
		headers: {
			...BROWSER_HEADERS,
			Referer: referer || "https://voe.sx/"
		},
		redirect: "follow",
		signal: AbortSignal.timeout(2e4)
	});
	if (!res.ok) throw new Error(`HTTP ${res.status}`);
	return res.text();
}
async function fetchAniworldAsset(path) {
	if (!path.startsWith("/public/")) throw new Error("Ungültiger Pfad");
	const urls = assetProxyUrls(`${ORIGIN}${path}`);
	const controller = new AbortController();
	const tryOne = async (url, timeout) => {
		const res = await fetch(url, {
			headers: {
				...BROWSER_HEADERS,
				Accept: "image/*,*/*;q=0.8"
			},
			redirect: "follow",
			signal: combineSignals(timeout, controller.signal)
		});
		if (!res.ok) throw new Error("http");
		const contentType = res.headers.get("content-type") || "image/jpeg";
		if (contentType.includes("text/html")) throw new Error("html");
		const buf = new Uint8Array(await res.arrayBuffer());
		if (buf.byteLength < 400) throw new Error("tiny");
		return {
			bytes: buf,
			contentType
		};
	};
	try {
		const result = await Promise.any(urls.map((url, i) => tryOne(url, i === 0 ? 4e3 : 7e3)));
		controller.abort();
		return result;
	} catch {
		throw new Error("Cover nicht ladbar");
	}
}
function unique(list) {
	const out = [];
	for (const item of list) {
		const t = item.trim();
		if (t && !out.includes(t)) out.push(t);
	}
	return out;
}
function parseCatalog(html) {
	const $ = load(html);
	const seen = /* @__PURE__ */ new Map();
	const items = [];
	const ingestAnchor = (href, title, altRaw, genre) => {
		const match = toAniworldPath(href).match(/^\/anime\/stream\/([^/?#]+)/);
		if (!match) return;
		const slug = match[1];
		const cleanTitle = title.replace(/\s+/g, " ").trim();
		if (!cleanTitle) return;
		const alts = unique(altRaw.split(",").map((s) => s.trim()).filter((s) => s.toLowerCase() !== cleanTitle.toLowerCase())).slice(0, 8);
		const existing = seen.get(slug);
		if (existing) {
			if (genre && !existing.genres.includes(genre)) existing.genres.push(genre);
			return;
		}
		const rec = {
			slug,
			title: cleanTitle,
			alts,
			genres: genre ? [genre] : []
		};
		seen.set(slug, rec);
		items.push(rec);
	};
	const genreBlocks = $(".genre");
	if (genreBlocks.length > 0) genreBlocks.each((_, block) => {
		const genre = $(block).find("h3").first().text().trim() || null;
		$(block).find("a").each((__, a) => {
			ingestAnchor($(a).attr("href") || "", $(a).text(), $(a).attr("data-alternative-title") || "", genre);
		});
	});
	if (items.length < 20) $("a").each((_, a) => {
		ingestAnchor($(a).attr("href") || "", $(a).text(), $(a).attr("data-alternative-title") || $(a).attr("data-alternativeTitles") || "", null);
	});
	return items;
}
function flagLabel(title) {
	const t = title.toLowerCase();
	if (t.includes("untertitel") || t.includes("gersub") || t.includes("japanese-german")) return "GerSub";
	if (t.includes("english") || t.includes("englisch")) return "EN";
	if (t.includes("deutsch") || t.includes("german")) return "DE";
	if (t.includes("japan")) return "JP";
	return title.trim() ? title.trim() : null;
}
function parseSeasons($) {
	const seasons = [];
	const seen = /* @__PURE__ */ new Set();
	$(".hosterSiteDirectNav").first().find("ul").first().find("a").each((_, a) => {
		const href = toAniworldPath($(a).attr("href") || "");
		if (href.includes("/filme")) {
			if (!seen.has("filme")) {
				seen.add("filme");
				seasons.push({
					id: "filme",
					label: "Filme"
				});
			}
			return;
		}
		const m = href.match(/staffel-(\d+)/);
		if (m && !seen.has(m[1])) {
			seen.add(m[1]);
			seasons.push({
				id: m[1],
				label: `Staffel ${m[1]}`
			});
		}
	});
	seasons.sort((a, b) => {
		if (a.id === "filme") return 1;
		if (b.id === "filme") return -1;
		return Number(a.id) - Number(b.id);
	});
	if (seasons.length === 0) seasons.push({
		id: "1",
		label: "Staffel 1"
	});
	return seasons;
}
function parseEpisodes($) {
	const episodes = [];
	$("table.seasonEpisodesList tbody tr").each((_, tr) => {
		const row = $(tr);
		const titleLink = row.find(".seasonEpisodeTitle a").first();
		const href = toAniworldPath(titleLink.attr("href") || "") || toAniworldPath(row.find("a[href*='episode-']").attr("href") || "") || toAniworldPath(row.find("a[href*='/filme/film-']").attr("href") || "");
		const film = href.match(/\/filme\/film-(\d+)/);
		const ep = href.match(/episode-(\d+)/);
		const numRaw = film?.[1] || ep?.[1] || row.find("meta[itemprop=\"episodeNumber\"]").attr("content") || row.find("td").first().text();
		const number = Number(String(numRaw).replace(/[^\d]/g, "")) || episodes.length + 1;
		const germanTitle = titleLink.find("strong").text().replace(/\s+/g, " ").trim();
		const englishTitle = titleLink.find("span").text().replace(/\s+/g, " ").trim();
		const hosters = unique(row.find("i.icon").map((__, el) => $(el).attr("title") || "").get().map((t) => t.replace(/^Hoster\s+/i, "").trim()));
		const languages = unique(row.find("img.flag").map((__, el) => flagLabel($(el).attr("title") || $(el).attr("alt") || "") || "").get().filter(Boolean));
		if (!href && !germanTitle && !englishTitle) return;
		const fallback = film ? `Film ${number}` : `Folge ${number}`;
		episodes.push({
			number,
			germanTitle: germanTitle || englishTitle || fallback,
			englishTitle,
			path: href,
			hosters,
			languages
		});
	});
	return episodes;
}
function parseSeries(html, slug, requestedSeason) {
	const $ = load(html);
	const titleEl = $(".series-title h1").first();
	const title = titleEl.find("span").first().text().trim() || titleEl.text().trim() || $("h1").first().text().trim() || slug;
	const alts = unique((titleEl.attr("data-alternativeTitles") || titleEl.attr("title") || "").replace(/^Animes Stream:\s*/i, "").split(",").map((s) => s.trim()).filter((s) => s && s.toLowerCase() !== title.toLowerCase())).slice(0, 8);
	const description = $("p.seri_des").attr("data-full-description") || $("p.seri_des").text().replace(/mehr anzeigen/gi, "").replace(/\s+/g, " ").trim() || "";
	const coverSrc = $(".seriesCoverBox img").attr("data-src") || $(".seriesCoverBox img").attr("src") || null;
	let coverPath = null;
	if (coverSrc && coverSrc.startsWith("/public/") && !coverSrc.startsWith("data:")) coverPath = coverSrc;
	else if (coverSrc && coverSrc.includes("/public/img/cover/")) coverPath = coverSrc.replace(/^https?:\/\/[^/]+/, "");
	const yearStart = $("span[itemprop=\"startDate\"]").text().trim() || null;
	const yearEnd = $("span[itemprop=\"endDate\"]").text().trim() || null;
	const fsk = $("[data-fsk]").attr("data-fsk") || null;
	const imdb = $("a.imdb-link").attr("data-imdb") || null;
	const genres = unique($("a.genreButton").map((_, el) => $(el).text().trim()).get().filter((g) => {
		const n = g.toLowerCase();
		return n && n !== "ger" && n !== "engsub" && n !== "gersub";
	}));
	const seasons = parseSeasons($);
	const episodes = parseEpisodes($);
	let activeSeason = requestedSeason || "";
	if (!activeSeason) {
		const activeHref = toAniworldPath($(".hosterSiteDirectNav a.active").attr("href") || "");
		if (activeHref.includes("/filme")) activeSeason = "filme";
		else activeSeason = activeHref.match(/staffel-(\d+)/)?.[1] || seasons.find((s) => s.id !== "filme")?.id || seasons[0]?.id || "1";
	}
	return {
		slug,
		title,
		alts,
		description,
		coverPath,
		yearStart,
		yearEnd,
		fsk,
		imdb,
		genres,
		seasons,
		activeSeason,
		episodes
	};
}
function seriesPath(slug, season) {
	if (!season) return `/anime/stream/${slug}`;
	if (season === "filme") return `/anime/stream/${slug}/filme`;
	return `/anime/stream/${slug}/staffel-${season}`;
}
async function refreshCatalog() {
	const items = parseCatalog(await fetchAniworldPage("/animes"));
	if (items.length < 50) throw new Error("Katalog unvollständig");
	const result = {
		items,
		source: "live",
		fetchedAt: Date.now()
	};
	catalogCache.set("catalog", {
		value: result,
		expires: Date.now() + CATALOG_TTL
	});
	return result;
}
async function getCatalog() {
	const hit = catalogCache.get("catalog");
	if (hit && hit.expires > Date.now()) return hit.value;
	if (!catalogInflight) catalogInflight = refreshCatalog().catch(() => {
		const stale = catalogCache.get("catalog");
		if (stale) return {
			...stale.value,
			source: "cache"
		};
		return {
			items: FALLBACK,
			source: "fallback",
			fetchedAt: 0
		};
	}).finally(() => {
		catalogInflight = null;
	});
	if (hit) return {
		...hit.value,
		source: "cache"
	};
	return {
		items: FALLBACK,
		source: "fallback",
		fetchedAt: 0
	};
}
async function getSeries(slug, season) {
	const key = `${slug}::${season || "default"}`;
	const hit = seriesCache.get(key);
	if (hit && hit.expires > Date.now()) return hit.value;
	let inflight = seriesInflight.get(key);
	if (!inflight) {
		inflight = (async () => {
			const html = await fetchAniworldPage(seriesPath(slug, season));
			const hasSeries = html.includes("series-title") || html.includes("seasonEpisodesList");
			const looksCatalog = html.includes("class=\"genre\"") && html.includes("/animes");
			if (!hasSeries || looksCatalog && !html.includes("series-title")) throw scrapeFail("notfound", "Serie nicht gefunden");
			const detail = parseSeries(html, slug, season);
			if (!detail.title || detail.title.toLowerCase() === "alle animes") throw scrapeFail("notfound", "Serie nicht gefunden");
			seriesCache.set(key, {
				value: detail,
				expires: Date.now() + SERIES_TTL
			});
			return detail;
		})().finally(() => {
			seriesInflight.delete(key);
		});
		seriesInflight.set(key, inflight);
	}
	if (hit) return hit.value;
	return inflight;
}
//#endregion
export { toAniworldPath as a, scrape_server_Dx4_7B2O_exports as i, fetchAniworldPage as n, unwrapTranslateUrl as o, fetchExternalPage as r, BROWSER_HEADERS as t };
