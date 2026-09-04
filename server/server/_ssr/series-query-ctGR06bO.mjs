import { a as otherProvider, n as asProvider } from "./provider-B-pxa-h2.mjs";
import { t as parseScrapeError } from "./errors-D28ORtyS.mjs";
import { i as fetchSeries } from "./cover-prefetch-Dz9cGrY_.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/series-query-ctGR06bO.js
async function fetchSeriesSmart(opts) {
	const first = asProvider(opts.provider);
	try {
		return {
			series: await fetchSeries({ data: {
				slug: opts.slug,
				season: opts.season,
				provider: first
			} }),
			provider: first
		};
	} catch (err) {
		if (parseScrapeError(err).code !== "notfound") throw err;
		const next = otherProvider(first);
		return {
			series: await fetchSeries({ data: {
				slug: opts.slug,
				season: opts.season,
				provider: next
			} }),
			provider: next
		};
	}
}
//#endregion
export { fetchSeriesSmart as t };
