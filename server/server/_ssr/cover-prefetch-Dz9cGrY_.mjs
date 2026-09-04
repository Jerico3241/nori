import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { r as createServerFn } from "./ssr.mjs";
import { cn as _enum, dn as boolean, gn as object, un as array, yn as string } from "../_libs/@better-auth/core+[...].mjs";
import { b as createSsrRpc, z as useLibrary } from "./router-DDQw7P_P.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/cover-prefetch-Dz9cGrY_.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var Provider = _enum(["aniworld", "serienstream"]).default("aniworld");
var Kind = _enum(["anime", "series"]).optional();
var fetchCatalog = createServerFn({ method: "GET" }).validator(object({ provider: Provider })).handler(createSsrRpc("20128a1510ed5c2e264aba5009f2d1690dc73121d428ff4e5b740f4afca77484"));
var fetchSeries = createServerFn({ method: "GET" }).validator(object({
	slug: string().min(1).max(180),
	season: string().max(20).optional(),
	provider: Provider
})).handler(createSsrRpc("7f3a6168f64490135efba5181cc5fffc8b4ebc08ae66ae6bdf72b1de3e90bbdb"));
var fetchCovers = createServerFn({ method: "POST" }).validator(object({ items: array(object({
	slug: string().min(1).max(180),
	title: string().min(1).max(220),
	alts: array(string().max(220)).max(4).optional(),
	kind: Kind
})).max(60) })).handler(createSsrRpc("02593d4d11ad011b4ad72aaa7668cea4fe8e361d527b81447adb07c6288428f0"));
var fetchSeriesMeta = createServerFn({ method: "POST" }).validator(object({
	slug: string().min(1).max(180),
	title: string().min(1).max(220),
	alts: array(string().max(220)).max(4).optional(),
	season: string().max(20).optional(),
	kind: Kind
})).handler(createSsrRpc("961ec6c4663d8493641583b518ef45bad2057e511a8d407b51e1470ffabd5312"));
var fetchWatch = createServerFn({ method: "GET" }).validator(object({
	path: string().min(1).max(400),
	provider: Provider
})).handler(createSsrRpc("79f8e4b00f3a3f971db8db090d132ddba617406eabda264d2b38539b554bc319"));
createServerFn({ method: "POST" }).validator(object({
	redirectPath: string().min(1).max(800),
	hoster: string().min(1).max(40),
	lang: string().min(1).max(16),
	fresh: boolean().optional(),
	provider: Provider
})).handler(createSsrRpc("f4ad4313e00925612c97054eb03a6805f4db43edd778df8abb1c1dc6aac0dcf8"));
var resolveBestPlay = createServerFn({ method: "POST" }).validator(object({
	preferred: string().max(40).optional(),
	fresh: boolean().optional(),
	provider: Provider,
	hosters: array(object({
		name: string().min(1).max(40),
		lang: string().min(1).max(16),
		langKey: string().max(8),
		redirectPath: string().min(1).max(800)
	})).min(1).max(20)
})).handler(createSsrRpc("74bbac9d26669d7b3ec18237ac2cfbd0d44ee377dc43c4c554dbf0581b6d7871"));
var fetchCalendar = createServerFn({ method: "GET" }).validator(object({ provider: Provider })).handler(createSsrRpc("96b638e9664ff9289c87bd845ba1fd5202bcdc6e5eef8dea37fa448274764032"));
var posters = /* @__PURE__ */ new Map();
var banners = /* @__PURE__ */ new Map();
var snaps = /* @__PURE__ */ new Map();
var listeners = /* @__PURE__ */ new Set();
var EMPTY = {
	poster: null,
	banner: null
};
var STORAGE_KEY = "nori-covers-tmdb";
var LEGACY_KEY = "nori-covers";
var pending = /* @__PURE__ */ new Set();
var queue = /* @__PURE__ */ new Map();
var flushTimer = 0;
function emit() {
	for (const listener of listeners) listener();
}
function isUsablePoster(url) {
	if (!url.startsWith("http") && !url.startsWith("/api/cover")) return false;
	if (url.includes("anilist.co") || url.includes("anilistcdn")) return false;
	return true;
}
function snapshot(slug) {
	const poster = posters.get(slug);
	if (!poster) {
		const prev = snaps.get(slug);
		if (prev && !prev.poster) return prev;
		snaps.set(slug, EMPTY);
		return EMPTY;
	}
	const banner = banners.get(slug) ?? null;
	const prev = snaps.get(slug);
	if (prev && prev.poster === poster && prev.banner === banner) return prev;
	const next = {
		poster,
		banner
	};
	snaps.set(slug, next);
	return next;
}
function readStorage() {
	if (typeof window === "undefined") return;
	try {
		window.localStorage.removeItem(LEGACY_KEY);
		const raw = window.localStorage.getItem(STORAGE_KEY);
		if (!raw) return;
		const parsed = JSON.parse(raw);
		for (const [slug, poster] of Object.entries(parsed)) if (typeof poster === "string" && isUsablePoster(poster)) posters.set(slug, poster);
	} catch {}
}
if (typeof window !== "undefined") readStorage();
var persistTimer = 0;
function persist() {
	if (typeof window === "undefined") return;
	window.clearTimeout(persistTimer);
	persistTimer = window.setTimeout(() => {
		const obj = {};
		let n = 0;
		for (const [slug, poster] of posters) {
			if (!isUsablePoster(poster)) continue;
			obj[slug] = poster;
			if (++n >= 2500) break;
		}
		try {
			window.localStorage.setItem(STORAGE_KEY, JSON.stringify(obj));
		} catch {}
	}, 400);
}
function hasPoster(slug) {
	const poster = posters.get(slug);
	return Boolean(poster && isUsablePoster(poster));
}
function ingestCovers(arts) {
	let changed = false;
	for (const art of arts) {
		if (!art?.slug || !art.poster || !isUsablePoster(art.poster)) continue;
		if (posters.get(art.slug) !== art.poster) {
			posters.set(art.slug, art.poster);
			snaps.delete(art.slug);
			changed = true;
		}
		if (art.banner !== void 0 && banners.get(art.slug) !== art.banner) {
			banners.set(art.slug, art.banner);
			snaps.delete(art.slug);
			changed = true;
		}
	}
	if (!changed) return;
	persist();
	emit();
}
async function flushQueue() {
	flushTimer = 0;
	const items = [...queue.values()].slice(0, 24);
	for (const item of items) queue.delete(item.slug);
	if (items.length === 0) return;
	try {
		const arts = await fetchCovers({ data: { items } });
		ingestCovers(arts);
		useLibrary.getState().mergeCovers(arts);
		for (const item of items) if (!hasPoster(item.slug)) pending.delete(item.slug);
	} catch {
		for (const item of items) pending.delete(item.slug);
	}
	if (queue.size > 0) flushTimer = window.setTimeout(() => void flushQueue(), 80);
}
function requestCover(item) {
	if (typeof window === "undefined") return;
	if (!item.slug || !item.title || item.title === item.slug) return;
	if (hasPoster(item.slug) || pending.has(item.slug)) return;
	pending.add(item.slug);
	queue.set(item.slug, {
		slug: item.slug,
		title: item.title,
		alts: item.alts?.slice(0, 3),
		kind: item.kind
	});
	if (!flushTimer) flushTimer = window.setTimeout(() => void flushQueue(), 280);
}
function useCover(slug) {
	const subscribe = (0, import_react.useCallback)((listener) => {
		listeners.add(listener);
		return () => {
			listeners.delete(listener);
		};
	}, []);
	const get = (0, import_react.useCallback)(() => snapshot(slug), [slug]);
	return (0, import_react.useSyncExternalStore)(subscribe, get, () => EMPTY);
}
function CoverPrefetch({ items, limit = 16, kind }) {
	const key = items.slice(0, limit).map((i) => i.slug).join(",");
	(0, import_react.useEffect)(() => {
		for (const item of items.slice(0, limit)) requestCover({
			...item,
			kind: item.kind || kind
		});
	}, [
		key,
		limit,
		kind
	]);
	return null;
}
//#endregion
export { fetchSeriesMeta as a, ingestCovers as c, useCover as d, fetchSeries as i, requestCover as l, fetchCalendar as n, fetchWatch as o, fetchCatalog as r, hasPoster as s, CoverPrefetch as t, resolveBestPlay as u };
