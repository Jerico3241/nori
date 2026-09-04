import { n as searchTmdb, t as mapPool } from "./tmdb.server-KxAOssiY.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/anilist.server-BI0WYpPZ.js
var cache = /* @__PURE__ */ new Map();
var miss = /* @__PURE__ */ new Map();
var cachedAt = /* @__PURE__ */ new Map();
var TTL = 12096e5;
var MISS_TTL = 6e5;
function stillFresh(slug) {
	const art = cache.get(slug);
	const at = cachedAt.get(slug);
	if (!art?.poster || !at) return null;
	if (Date.now() - at > TTL) return null;
	return art;
}
function recentlyMissed(slug) {
	const at = miss.get(slug);
	return Boolean(at && Date.now() - at < MISS_TTL);
}
function remember(art) {
	cache.set(art.slug, art);
	cachedAt.set(art.slug, Date.now());
	miss.delete(art.slug);
}
async function lookupCovers(items) {
	const out = [];
	const missing = [];
	for (const item of items) {
		if (!item?.slug || !item.title) continue;
		const hit = stillFresh(item.slug);
		if (hit) out.push(hit);
		else if (!recentlyMissed(item.slug)) missing.push(item);
	}
	const found = await mapPool(missing, 4, async (item) => {
		try {
			const names = [item.title, ...item.alts ?? []].filter(Boolean);
			const hit = await searchTmdb(names, item.kind === "series" ? "series" : "anime");
			if (hit?.poster) {
				const art = {
					slug: item.slug,
					poster: hit.poster,
					banner: hit.banner
				};
				remember(art);
				return art;
			}
			miss.set(item.slug, Date.now());
			return null;
		} catch {
			return null;
		}
	});
	for (const art of found) if (art) out.push(art);
	return out;
}
//#endregion
export { lookupCovers };
