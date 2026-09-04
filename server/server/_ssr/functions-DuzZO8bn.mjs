import { r as createServerFn } from "./ssr.mjs";
import { t as createServerRpc } from "./createServerRpc-CcvdN_gc.mjs";
import { cn as _enum, dn as boolean, gn as object, un as array, yn as string } from "../_libs/@better-auth/core+[...].mjs";
import { n as asProvider } from "./provider-B-pxa-h2.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/functions-DuzZO8bn.js
var Provider = _enum(["aniworld", "serienstream"]).default("aniworld");
var Kind = _enum(["anime", "series"]).optional();
var fetchCatalog_createServerFn_handler = createServerRpc({
	id: "20128a1510ed5c2e264aba5009f2d1690dc73121d428ff4e5b740f4afca77484",
	name: "fetchCatalog",
	filename: "src/lib/aniworld/functions.ts"
}, (opts) => fetchCatalog.__executeServer(opts));
var fetchCatalog = createServerFn({ method: "GET" }).validator(object({ provider: Provider })).handler(fetchCatalog_createServerFn_handler, async ({ data }) => {
	if (asProvider(data.provider) === "serienstream") {
		const { getCatalog } = await import("./scrape.server-CxlWdT5G.mjs");
		return getCatalog();
	}
	const { getCatalog } = await import("./scrape.server-Dx4-7B2O.mjs").then((n) => n.i).then((n) => n.i);
	return getCatalog();
});
var fetchSeries_createServerFn_handler = createServerRpc({
	id: "7f3a6168f64490135efba5181cc5fffc8b4ebc08ae66ae6bdf72b1de3e90bbdb",
	name: "fetchSeries",
	filename: "src/lib/aniworld/functions.ts"
}, (opts) => fetchSeries.__executeServer(opts));
var fetchSeries = createServerFn({ method: "GET" }).validator(object({
	slug: string().min(1).max(180),
	season: string().max(20).optional(),
	provider: Provider
})).handler(fetchSeries_createServerFn_handler, async ({ data }) => {
	if (asProvider(data.provider) === "serienstream") {
		const { getSeries } = await import("./scrape.server-CxlWdT5G.mjs");
		return getSeries(data.slug, data.season);
	}
	const { getSeries } = await import("./scrape.server-Dx4-7B2O.mjs").then((n) => n.i).then((n) => n.i);
	return getSeries(data.slug, data.season);
});
var fetchCovers_createServerFn_handler = createServerRpc({
	id: "02593d4d11ad011b4ad72aaa7668cea4fe8e361d527b81447adb07c6288428f0",
	name: "fetchCovers",
	filename: "src/lib/aniworld/functions.ts"
}, (opts) => fetchCovers.__executeServer(opts));
var fetchCovers = createServerFn({ method: "POST" }).validator(object({ items: array(object({
	slug: string().min(1).max(180),
	title: string().min(1).max(220),
	alts: array(string().max(220)).max(4).optional(),
	kind: Kind
})).max(60) })).handler(fetchCovers_createServerFn_handler, async ({ data }) => {
	const { lookupCovers } = await import("./anilist.server-BI0WYpPZ.mjs");
	return lookupCovers(data.items);
});
var fetchSeriesMeta_createServerFn_handler = createServerRpc({
	id: "961ec6c4663d8493641583b518ef45bad2057e511a8d407b51e1470ffabd5312",
	name: "fetchSeriesMeta",
	filename: "src/lib/aniworld/functions.ts"
}, (opts) => fetchSeriesMeta.__executeServer(opts));
var fetchSeriesMeta = createServerFn({ method: "POST" }).validator(object({
	slug: string().min(1).max(180),
	title: string().min(1).max(220),
	alts: array(string().max(220)).max(4).optional(),
	season: string().max(20).optional(),
	kind: Kind
})).handler(fetchSeriesMeta_createServerFn_handler, async ({ data }) => {
	const { lookupSeriesMeta } = await import("./lookup.server-CJI6oPjt.mjs");
	return lookupSeriesMeta(data);
});
var fetchWatch_createServerFn_handler = createServerRpc({
	id: "79f8e4b00f3a3f971db8db090d132ddba617406eabda264d2b38539b554bc319",
	name: "fetchWatch",
	filename: "src/lib/aniworld/functions.ts"
}, (opts) => fetchWatch.__executeServer(opts));
var fetchWatch = createServerFn({ method: "GET" }).validator(object({
	path: string().min(1).max(400),
	provider: Provider
})).handler(fetchWatch_createServerFn_handler, async ({ data }) => {
	if (asProvider(data.provider) === "serienstream" || data.path.startsWith("/serie/")) {
		const { getWatch } = await import("./watch.server-CtiQsoD0.mjs");
		return getWatch(data.path);
	}
	const { getWatch } = await import("./watch.server-Djsupa21.mjs");
	return getWatch(data.path);
});
var resolvePlay_createServerFn_handler = createServerRpc({
	id: "f4ad4313e00925612c97054eb03a6805f4db43edd778df8abb1c1dc6aac0dcf8",
	name: "resolvePlay",
	filename: "src/lib/aniworld/functions.ts"
}, (opts) => resolvePlay.__executeServer(opts));
var resolvePlay = createServerFn({ method: "POST" }).validator(object({
	redirectPath: string().min(1).max(800),
	hoster: string().min(1).max(40),
	lang: string().min(1).max(16),
	fresh: boolean().optional(),
	provider: Provider
})).handler(resolvePlay_createServerFn_handler, async ({ data }) => {
	if (asProvider(data.provider) === "serienstream" || data.redirectPath.startsWith("/r")) {
		const { resolvePlay: resolve } = await import("./watch.server-CtiQsoD0.mjs");
		return resolve(data.redirectPath, data.hoster, data.lang, data.fresh);
	}
	const { resolvePlay: resolve } = await import("./watch.server-Djsupa21.mjs");
	return resolve(data.redirectPath, data.hoster, data.lang, data.fresh);
});
var resolveBestPlay_createServerFn_handler = createServerRpc({
	id: "74bbac9d26669d7b3ec18237ac2cfbd0d44ee377dc43c4c554dbf0581b6d7871",
	name: "resolveBestPlay",
	filename: "src/lib/aniworld/functions.ts"
}, (opts) => resolveBestPlay.__executeServer(opts));
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
})).handler(resolveBestPlay_createServerFn_handler, async ({ data }) => {
	if (asProvider(data.provider) === "serienstream" || data.hosters.some((h) => h.redirectPath.startsWith("/r"))) {
		const { resolveBestPlay: resolve } = await import("./watch.server-CtiQsoD0.mjs");
		return resolve(data.hosters, data.preferred, data.fresh);
	}
	const { resolveBestPlay: resolve } = await import("./watch.server-Djsupa21.mjs");
	return resolve(data.hosters, data.preferred, data.fresh);
});
var fetchCalendar_createServerFn_handler = createServerRpc({
	id: "96b638e9664ff9289c87bd845ba1fd5202bcdc6e5eef8dea37fa448274764032",
	name: "fetchCalendar",
	filename: "src/lib/aniworld/functions.ts"
}, (opts) => fetchCalendar.__executeServer(opts));
var fetchCalendar = createServerFn({ method: "GET" }).validator(object({ provider: Provider })).handler(fetchCalendar_createServerFn_handler, async ({ data }) => {
	const { fetchCalendarFor } = await import("./calendar.server-B19rj8Tk.mjs");
	return fetchCalendarFor(asProvider(data.provider));
});
//#endregion
export { fetchCalendar_createServerFn_handler, fetchCatalog_createServerFn_handler, fetchCovers_createServerFn_handler, fetchSeriesMeta_createServerFn_handler, fetchSeries_createServerFn_handler, fetchWatch_createServerFn_handler, resolveBestPlay_createServerFn_handler, resolvePlay_createServerFn_handler };
