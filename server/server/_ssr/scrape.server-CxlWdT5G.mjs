import { n as scrapeFail } from "./errors-D28ORtyS.mjs";
import { n as looksDdos, t as fetchOrigin } from "./http.server-D7YcQUwF.mjs";
import { t as load } from "../_libs/cheerio+[...].mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/scrape.server-CxlWdT5G.js
function unique(list) {
	const out = [];
	for (const item of list) {
		const t = item.trim();
		if (t && !out.includes(t)) out.push(t);
	}
	return out;
}
function slugFromSerieHref(href) {
	return href.replace(/&amp;/g, "&").split("?")[0].match(/\/serie\/([^/?#]+)/)?.[1] ?? null;
}
function dropAnimeTitles(items) {
	const re = /\b(anime|ova|ona|shounen|shoujo|seinen|isekai|zeichentrick|the animation)\b/i;
	return items.filter((item) => !re.test(`${item.title} ${(item.alts || []).join(" ")} ${(item.genres || []).join(" ")}`) && !/[\u3040-\u30ff\u3400-\u9fff]/.test(item.title));
}
var DROP_GENRES = /* @__PURE__ */ new Set([
	"anime",
	"animation",
	"zeichentrick"
]);
function parseCatalog(html) {
	const $ = load(html);
	const seen = /* @__PURE__ */ new Map();
	const dropped = /* @__PURE__ */ new Set();
	let usedGenre = false;
	function ingest(a, genre, drop) {
		const href = $(a).attr("href") || "";
		if (/staffel-|episode-|\/filme/.test(href)) return;
		const slug = slugFromSerieHref(href);
		if (!slug) return;
		if (drop) {
			dropped.add(slug);
			return;
		}
		const title = $(a).text().replace(/\s+/g, " ").trim();
		if (!title) return;
		const rec = seen.get(slug);
		if (rec) {
			if (genre && !rec.genres.includes(genre)) rec.genres.push(genre);
			return;
		}
		seen.set(slug, {
			slug,
			title,
			alts: unique(($(a).closest("li").attr("data-search") || "").replace(/\s+/g, " ").split("|").flatMap((part) => part.split(",")).map((s) => s.trim()).filter((s) => s && s.toLowerCase() !== title.toLowerCase())).slice(0, 8),
			genres: genre ? [genre] : []
		});
	}
	$("h3").each((_, h) => {
		const genre = $(h).text().replace(/\s+/g, " ").trim();
		if (!genre || /^filter\./i.test(genre)) return;
		const list = $(h).parent().nextAll("ul.series-list").first();
		if (!list.length) return;
		usedGenre = true;
		const drop = DROP_GENRES.has(genre.toLowerCase());
		list.find("li.series-item a[href*='/serie/']").each((__, a) => ingest(a, genre, drop));
	});
	if (!usedGenre) {
		$("li.series-item a[href*='/serie/']").each((_, a) => ingest(a, "", false));
		return dropAnimeTitles([...seen.values()]);
	}
	return dropAnimeTitles([...seen.values()].filter((item) => !dropped.has(item.slug)));
}
function flagLang(className) {
	const n = className.toLowerCase();
	if (n.includes("ger-sub") || n.includes("gersub") || n.includes("sub") && n.includes("japan")) return "GerSub";
	if (n.includes("german") || n.includes("deutsch")) return "DE";
	if (n.includes("english") || n.includes("englisch")) return "EN";
	return null;
}
function parseSeasons($, slug) {
	const seasons = [];
	const seen = /* @__PURE__ */ new Set();
	$(`a[href*='/serie/${slug}/']`).each((_, a) => {
		const href = $(a).attr("href") || "";
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
	$(".episode-row").each((_, row) => {
		const el = $(row);
		const href = (el.attr("onclick") || "").match(/['"](\/serie\/[^'"]+)['"]/)?.[1] || el.find("a[href*='episode-'], a[href*='/filme/']").attr("href") || "";
		const film = href.match(/\/filme\/(?:film-)?(\d+)/);
		const ep = href.match(/episode-(\d+)/);
		const numRaw = film?.[1] || ep?.[1] || el.find(".episode-number-cell").text();
		const number = Number(String(numRaw).replace(/[^\d]/g, "")) || episodes.length + 1;
		const germanTitle = el.find(".episode-title-ger").text().replace(/\s+/g, " ").trim();
		const englishTitle = el.find(".episode-title-eng").text().replace(/\s+/g, " ").trim();
		const hosters = unique(el.find("img.watch-link, img[alt]").map((__, img) => $(img).attr("alt") || $(img).attr("title") || "").get().map((t) => t.replace(/^Hoster\s+/i, "").trim()).filter(Boolean));
		const languages = unique(el.find("svg.watch-language, svg[class*='flag']").map((__, svg) => flagLang($(svg).attr("class") || "") || "").get().filter(Boolean));
		if (!href && !germanTitle && !englishTitle) return;
		const fallback = film ? `Film ${number}` : `Folge ${number}`;
		episodes.push({
			number,
			germanTitle: germanTitle || englishTitle || fallback,
			englishTitle,
			path: href.split("?")[0],
			hosters,
			languages
		});
	});
	return episodes;
}
function parseSeries(html, slug, requestedSeason) {
	const $ = load(html);
	const title = $("h1").first().text().replace(/\s+/g, " ").trim() || slug;
	const description = $(".description-text").first().text().replace(/\s+/g, " ").trim() || $("meta[name=\"description\"]").attr("content") || "";
	const og = $("meta[property=\"og:image\"]").attr("content") || "";
	let coverPath = null;
	const poster = $("img[src*='/media/images/channel/desktop/']").first().attr("src") || "";
	if (poster.startsWith("/media/")) coverPath = poster.split("?")[0];
	else if (og.includes("/media/images/channel/")) try {
		coverPath = new URL(og).pathname;
	} catch {
		coverPath = og.replace(/^https?:\/\/[^/]+/, "").split("?")[0];
	}
	else if (og.includes("/media/images/")) try {
		coverPath = new URL(og).pathname;
	} catch {
		coverPath = og.replace(/^https?:\/\/[^/]+/, "").split("?")[0];
	}
	const seasons = parseSeasons($, slug);
	const episodes = parseEpisodes($);
	let activeSeason = requestedSeason || "";
	if (!activeSeason) activeSeason = ($(`a[href*='/serie/${slug}/staffel-'].active`).attr("href") || "").match(/staffel-(\d+)/)?.[1] || seasons.find((s) => s.id !== "filme")?.id || "1";
	return {
		slug,
		title,
		alts: [],
		description,
		coverPath,
		yearStart: null,
		yearEnd: null,
		fsk: null,
		imdb: null,
		genres: [],
		seasons,
		activeSeason,
		episodes
	};
}
var LANG = {
	"1": "DE",
	"2": "EN",
	"3": "GerSub"
};
function langFrom(id, label) {
	if (LANG[id]) return {
		lang: LANG[id],
		langKey: id
	};
	const n = label.toLowerCase();
	if (n.includes("sub")) return {
		lang: "GerSub",
		langKey: "3"
	};
	if (n.includes("engl")) return {
		lang: "EN",
		langKey: "2"
	};
	if (n.includes("deutsch") || n.includes("german")) return {
		lang: "DE",
		langKey: "1"
	};
	return {
		lang: label || "DE",
		langKey: id || "1"
	};
}
function parseWatch(html, path) {
	const $ = load(html);
	const h1 = $("h1").first().text().replace(/\s+/g, " ").trim();
	const germanTitle = $(".episode-title-ger").first().text().trim() || h1;
	const englishTitle = $(".episode-title-eng").first().text().trim();
	const hosters = [];
	const seen = /* @__PURE__ */ new Set();
	$("button.link-box[data-play-url]").each((_, el) => {
		const box = $(el);
		const playUrl = (box.attr("data-play-url") || "").trim();
		if (!playUrl.startsWith("/r")) return;
		const name = (box.attr("data-provider-name") || box.text() || "Hoster").replace(/\s+/g, " ").trim();
		const { lang, langKey } = langFrom(box.attr("data-language-id") || "", box.attr("data-language-label") || "");
		const key = `${playUrl}|${langKey}`;
		if (seen.has(key)) return;
		seen.add(key);
		hosters.push({
			name,
			lang,
			langKey,
			redirectPath: playUrl
		});
	});
	return {
		path,
		title: h1,
		germanTitle,
		englishTitle,
		hosters
	};
}
var ORIGIN = "https://serienstream.to";
var catalogCache = /* @__PURE__ */ new Map();
var seriesCache = /* @__PURE__ */ new Map();
var htmlCache = /* @__PURE__ */ new Map();
var htmlInflight = /* @__PURE__ */ new Map();
var seriesInflight = /* @__PURE__ */ new Map();
var catalogInflight = null;
var CATALOG_TTL = 18e5;
var SERIES_TTL = 6e5;
var HTML_TTL = 48e4;
var SS_HEADERS = {
	"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
	Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
	"Accept-Language": "de-DE,de;q=0.9,en;q=0.8"
};
function looksBlocked(html) {
	const head = html.slice(0, 800).toLowerCase();
	return html.length < 400 || looksDdos(html) || head.includes("error code: 522");
}
function htmlProxyUrls(target) {
	const encoded = encodeURIComponent(target);
	return [
		target,
		`https://translate.google.com/translate?sl=de&tl=en&u=${encoded}`,
		`https://api.allorigins.win/raw?url=${encoded}`,
		`https://api.codetabs.com/v1/proxy?quest=${encoded}`
	];
}
function combineSignals(timeoutMs, extra) {
	const timeout = AbortSignal.timeout(timeoutMs);
	return extra ? AbortSignal.any([timeout, extra]) : timeout;
}
async function fetchRaw(url, timeoutMs, extra, accept) {
	const res = await fetchOrigin(url, {
		timeout: timeoutMs,
		extra,
		referer: `${ORIGIN}/`,
		accept: accept || void 0
	});
	if (!res.ok) throw new Error(`HTTP ${res.status}`);
	const text = await res.text();
	if (url.includes("allorigins.win/get?")) try {
		const parsed = JSON.parse(text);
		if (typeof parsed.contents === "string") return parsed.contents;
	} catch {}
	return text;
}
async function fetchSerienstreamPage(path, expect = "html") {
	const key = `${expect}:${path}`;
	const hit = htmlCache.get(key);
	if (hit && hit.expires > Date.now()) return hit.value;
	const existing = htmlInflight.get(key);
	if (existing) return existing;
	const promise = (async () => {
		const urls = htmlProxyUrls(path.startsWith("http") ? path : `${ORIGIN}${path}`);
		const controller = new AbortController();
		const tryOne = async (url, timeout) => {
			const body = await fetchRaw(url, timeout, controller.signal, expect === "json" ? "application/json" : void 0);
			if (looksBlocked(body)) throw new Error("blocked");
			if (expect === "json") {
				JSON.parse(body);
				return body;
			}
			if (!body.includes("/serie/") && !body.includes("series-item") && !body.includes("episode-row") && !body.includes("link-box")) throw new Error("blocked");
			return body;
		};
		try {
			try {
				const html = await tryOne(urls[0], 8e3);
				controller.abort();
				htmlCache.set(key, {
					value: html,
					expires: Date.now() + HTML_TTL
				});
				return html;
			} catch {}
			const html = await Promise.any(urls.slice(1).map((url) => tryOne(url, 12e3)));
			controller.abort();
			htmlCache.set(key, {
				value: html,
				expires: Date.now() + HTML_TTL
			});
			return html;
		} catch {
			throw scrapeFail("blocked", "Serienstream nicht erreichbar");
		}
	})().finally(() => {
		htmlInflight.delete(key);
	});
	htmlInflight.set(key, promise);
	return promise;
}
async function fetchSerienstreamAsset(path) {
	if (!path.startsWith("/media/images/") && !path.startsWith("/storage/")) throw new Error("Ungültiger Pfad");
	let target = `${ORIGIN}${path}`;
	if (!target.includes("format=")) target += (target.includes("?") ? "&" : "?") + "format=jpg";
	const encoded = encodeURIComponent(target);
	const urls = [
		target,
		`https://api.allorigins.win/raw?url=${encoded}`,
		`https://api.codetabs.com/v1/proxy?quest=${encoded}`
	];
	const controller = new AbortController();
	const tryOne = async (url, timeout) => {
		const res = await fetch(url, {
			headers: {
				...SS_HEADERS,
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
function seriesPath(slug, season) {
	if (!season) return `/serie/${slug}`;
	if (season === "filme") return `/serie/${slug}/filme`;
	return `/serie/${slug}/staffel-${season}`;
}
async function refreshCatalog() {
	const items = parseCatalog(await fetchSerienstreamPage("/serien?by=genre"));
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
	if (!catalogInflight) catalogInflight = refreshCatalog().catch((err) => {
		if (hit) return {
			...hit.value,
			source: "cache"
		};
		throw err;
	}).finally(() => {
		catalogInflight = null;
	});
	if (hit) return {
		...hit.value,
		source: "cache"
	};
	return catalogInflight;
}
async function getSeries(slug, season) {
	const key = `${slug}::${season || "default"}`;
	const hit = seriesCache.get(key);
	if (hit && hit.expires > Date.now()) return hit.value;
	let inflight = seriesInflight.get(key);
	if (!inflight) {
		inflight = (async () => {
			const html = await fetchSerienstreamPage(seriesPath(slug, season));
			if (!html.includes("episode-row") && !html.includes("staffel-")) throw scrapeFail("notfound", "Serie nicht gefunden");
			const detail = parseSeries(html, slug, season);
			if (!detail.title) throw scrapeFail("notfound", "Serie nicht gefunden");
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
export { SS_HEADERS, fetchSerienstreamAsset, fetchSerienstreamPage, getCatalog, getSeries, parseWatch };
