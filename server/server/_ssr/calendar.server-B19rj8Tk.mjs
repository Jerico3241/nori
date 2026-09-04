import { t as load } from "../_libs/cheerio+[...].mjs";
import { n as fetchAniworldPage } from "./scrape.server-Dx4-7B2O.mjs";
import { fetchSerienstreamPage, getCatalog } from "./scrape.server-CxlWdT5G.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/calendar.server-B19rj8Tk.js
var CALENDAR_TTL = 12e5;
var cachedBy = /* @__PURE__ */ new Map();
var inflightBy = /* @__PURE__ */ new Map();
function slugFromHref(href) {
	const cleaned = href.replace(/&amp;/g, "&");
	const anime = cleaned.match(/\/anime\/stream\/([^/?#]+)/);
	if (anime) return anime[1];
	return cleaned.match(/\/serie\/([^/?#]+)/)?.[1] ?? null;
}
function pad(n) {
	return String(n).padStart(2, "0");
}
function unique(list) {
	const out = [];
	for (const item of list) {
		const t = item.trim();
		if (t && !out.includes(t)) out.push(t);
	}
	return out;
}
function berlinMs(year, month, day, hour, minute) {
	const utc = Date.UTC(year, month - 1, day, hour, minute);
	const parts = new Intl.DateTimeFormat("en-GB", {
		timeZone: "Europe/Berlin",
		year: "numeric",
		month: "2-digit",
		day: "2-digit",
		hour: "2-digit",
		minute: "2-digit",
		hour12: false,
		hourCycle: "h23"
	}).formatToParts(new Date(utc));
	const num = (type) => Number(parts.find((p) => p.type === type)?.value ?? 0);
	let h = num("hour");
	if (h === 24) h = 0;
	return utc - (Date.UTC(num("year"), num("month") - 1, num("day"), h, num("minute")) - utc);
}
function flagLang(src, title, alt) {
	const blob = `${src} ${title} ${alt}`.toLowerCase();
	if (blob.includes("japanese-german") || blob.includes("gersub") || blob.includes("untertitel") || blob.includes("ger-sub")) return "GerSub";
	if (blob.includes("japanese-english") || blob.includes("englisch") || blob.includes("english")) return "EN";
	if (blob.includes("german") || blob.includes("deutsch")) return "DE";
	return null;
}
function ssLang(raw, id) {
	if (id === 1) return "DE";
	if (id === 2) return "EN";
	if (id === 3) return "GerSub";
	return flagLang("", raw, "");
}
function coverUrl(path) {
	if (!path) return null;
	if (path.startsWith("http") || path.startsWith("/api/cover")) return path;
	if (path.startsWith("/public/") || path.startsWith("/media/")) return `/api/cover?path=${encodeURIComponent(path)}`;
	return null;
}
function weekdayLabel(year, month, day) {
	return `${new Date(year, month - 1, day).toLocaleDateString("de-DE", { weekday: "long" })}, ${day}. ${new Date(year, month - 1, day).toLocaleDateString("de-DE", { month: "long" })}`;
}
function parseAniworldCalendar(html, now = Date.now()) {
	const $ = load(html);
	const merged = /* @__PURE__ */ new Map();
	$("section.calendarList").each((_, section) => {
		const heading = $(section).find("h3").first().text().replace(/\s+/g, " ").trim();
		const dateMatch = heading.match(/(\d{1,2})\.(\d{1,2})\.(\d{4})/);
		if (!dateMatch) return;
		const day = Number(dateMatch[1]);
		const month = Number(dateMatch[2]);
		const year = Number(dateMatch[3]);
		const dayKey = `${year}-${pad(month)}-${pad(day)}`;
		const dayLabel = `${heading.split(",")[0]?.trim() || ""}, ${day}. ${new Date(year, month - 1, day).toLocaleDateString("de-DE", { month: "long" })}`;
		$(section).find("a[href*='anime/stream']").each((__, anchor) => {
			const a = $(anchor);
			const slug = slugFromHref(a.attr("href") || "");
			if (!slug) return;
			const title = a.find("h3.seriesTitle, .seriesTitle, h3").first().text().replace(/\s+/g, " ").trim() || slug;
			const small = a.find("small").map((___, s) => $(s).text()).get().join(" ");
			const epMatch = small.match(/S(\d+)\s*E(\d+)/i) || a.text().match(/S(\d+)\s*E(\d+)/i);
			const season = String(Number(epMatch?.[1] || "1"));
			const episode = Number(epMatch?.[2] || "0") || 0;
			const timeMatch = small.match(/(\d{1,2}):(\d{2})/);
			const hour = timeMatch ? Number(timeMatch[1]) : 0;
			const minute = timeMatch ? Number(timeMatch[2]) : 0;
			const airingAt = berlinMs(year, month, day, hour, minute);
			const coverPath = a.find("img").attr("data-src") || a.find("img").attr("src") || null;
			const languages = unique(a.find("img.flag").map((___, img) => flagLang($(img).attr("data-src") || $(img).attr("src") || "", $(img).attr("title") || "", $(img).attr("alt") || "") || "").get().filter(Boolean));
			const key = `${slug}|${season}|${episode}|${dayKey}`;
			const existing = merged.get(key);
			if (existing) {
				existing.languages = unique([...existing.languages, ...languages]);
				return;
			}
			merged.set(key, {
				airingAt,
				episode,
				season,
				title,
				english: null,
				romaji: null,
				poster: coverUrl(coverPath),
				coverPath,
				anilistId: 0,
				status: null,
				slug,
				languages,
				dayKey,
				dayLabel
			});
		});
	});
	return packEntries([...merged.values()], now);
}
function parseSerienstreamCalendar(raw, now = Date.now()) {
	const data = raw;
	const merged = /* @__PURE__ */ new Map();
	if (!data || typeof data !== "object") return {
		upcoming: [],
		recent: [],
		fetchedAt: now
	};
	for (const [dayKey, rows] of Object.entries(data)) {
		if (!Array.isArray(rows)) continue;
		const dm = dayKey.match(/^(\d{4})-(\d{2})-(\d{2})$/);
		if (!dm) continue;
		const year = Number(dm[1]);
		const month = Number(dm[2]);
		const day = Number(dm[3]);
		const dayLabel = weekdayLabel(year, month, day);
		for (const row of rows) {
			const slug = slugFromHref(row.url || "") || (row.poster || "").split("-")[0] || "";
			if (!slug) continue;
			const [hh, mm] = (row.time || "00:00").split(":");
			const airingAt = berlinMs(year, month, day, Number(hh) || 0, Number(mm) || 0);
			const lang = ssLang(row.language || "", row.language_id);
			const key = `${slug}|${row.season || 1}|${row.episode || 0}|${dayKey}|${lang || ""}`;
			const existing = merged.get(key);
			if (existing) {
				if (lang && !existing.languages.includes(lang)) existing.languages.push(lang);
				continue;
			}
			const coverPath = row.cover_url || null;
			merged.set(key, {
				airingAt,
				episode: Number(row.episode) || 0,
				season: String(row.season || 1),
				title: row.title || slug,
				english: null,
				romaji: null,
				poster: coverUrl(coverPath),
				coverPath,
				anilistId: 0,
				status: row.language || null,
				slug,
				languages: lang ? [lang] : [],
				dayKey,
				dayLabel
			});
		}
	}
	return packEntries([...merged.values()], now);
}
function packEntries(allIn, now) {
	const all = allIn.sort((a, b) => a.airingAt - b.airingAt || a.title.localeCompare(b.title, "de"));
	const berlinNowParts = new Intl.DateTimeFormat("en-GB", {
		timeZone: "Europe/Berlin",
		year: "numeric",
		month: "2-digit",
		day: "2-digit"
	}).formatToParts(new Date(now));
	const bNum = (t) => Number(berlinNowParts.find((p) => p.type === t)?.value ?? 0);
	const startToday = berlinMs(bNum("year"), bNum("month"), bNum("day"), 0, 0);
	return {
		upcoming: all.filter((row) => row.airingAt >= now - 108e5),
		recent: all.filter((row) => row.airingAt < now && row.airingAt >= startToday - 1728e5),
		fetchedAt: now
	};
}
async function loadAniworldCalendar() {
	const html = await fetchAniworldPage("/animekalender");
	if (!html.includes("calendarList") && !html.includes("seriesListContainer")) throw new Error("Kalender unvollständig");
	const value = parseAniworldCalendar(html);
	if (value.upcoming.length + value.recent.length < 3) throw new Error("Kalender unvollständig");
	return value;
}
async function loadSerienstreamCalendar() {
	const body = await fetchSerienstreamPage("/api/calendar", "json");
	const value = parseSerienstreamCalendar(JSON.parse(body));
	try {
		const catalog = await getCatalog();
		const allow = new Set((catalog.items || []).map((item) => item.slug));
		value.upcoming = value.upcoming.filter((row) => allow.has(row.slug));
		value.recent = value.recent.filter((row) => allow.has(row.slug));
	} catch {}
	if (value.upcoming.length + value.recent.length < 3) throw new Error("Kalender unvollständig");
	return value;
}
async function fetchCalendarFor(provider = "aniworld") {
	const hit = cachedBy.get(provider);
	if (hit && hit.expires > Date.now()) return hit.value;
	let inflight = inflightBy.get(provider);
	if (!inflight) {
		inflight = (async () => {
			const value = provider === "serienstream" ? await loadSerienstreamCalendar() : await loadAniworldCalendar();
			cachedBy.set(provider, {
				value,
				expires: Date.now() + CALENDAR_TTL
			});
			return value;
		})().finally(() => {
			inflightBy.delete(provider);
		});
		inflightBy.set(provider, inflight);
	}
	if (hit) return hit.value;
	return inflight;
}
//#endregion
export { fetchCalendarFor };
