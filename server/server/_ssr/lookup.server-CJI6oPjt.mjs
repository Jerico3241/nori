import { i as tmdbTvDetails, n as searchTmdb, r as tmdbSeasonEpisodes } from "./tmdb.server-KxAOssiY.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/lookup.server-CJI6oPjt.js
var cache = /* @__PURE__ */ new Map();
var TTL = 432e5;
function cacheKey(slug, season) {
	return `${slug}::${season || "1"}`;
}
function stripHtml(raw) {
	if (!raw) return null;
	return raw.replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, " ").replace(/&/gi, "&").replace(/"/gi, "\"").replace(/&#39;/g, "'").replace(/\s+/g, " ").trim() || null;
}
function seasonNumber(season) {
	if (!season || season === "filme") return 1;
	const n = Number.parseInt(season, 10);
	return Number.isFinite(n) && n > 0 ? n : 1;
}
function put(bag, number, patch) {
	const prev = bag[number] ?? {
		number,
		title: null,
		overview: null,
		still: null
	};
	bag[number] = {
		number,
		title: prev.title || patch.title || null,
		overview: prev.overview || patch.overview || null,
		still: prev.still || patch.still || null
	};
}
function richness(bag) {
	let score = 0;
	for (const ep of Object.values(bag)) {
		if (ep.still) score += 2;
		if (ep.overview && ep.overview.length > 40) score += 3;
		else if (ep.overview) score += 1;
		if (ep.title) score += 1;
	}
	return score;
}
async function fetchJson(url) {
	const res = await fetch(url, {
		signal: AbortSignal.timeout(8e3),
		headers: {
			Accept: "application/json",
			"User-Agent": "Nori/1.0"
		}
	});
	if (!res.ok) throw new Error(`${res.status}`);
	return res.json();
}
async function fromTvMaze(names, season) {
	const bag = {};
	for (const title of names.slice(0, 2)) try {
		const show = await fetchJson(`https://api.tvmaze.com/singlesearch/shows?q=${encodeURIComponent(title)}&embed=episodes`);
		for (const ep of show._embedded?.episodes ?? []) {
			if (ep.season !== season || !ep.number) continue;
			put(bag, ep.number, {
				title: ep.name || null,
				overview: stripHtml(ep.summary),
				still: ep.image?.original || ep.image?.medium || null
			});
		}
		if (richness(bag) > 0) return bag;
	} catch {
		continue;
	}
	return bag;
}
async function lookupSeriesMeta(input) {
	const season = input.season || "1";
	const key = cacheKey(input.slug, season);
	const hit = cache.get(key);
	if (hit && Date.now() - hit.at < TTL) return hit.value;
	const sNum = seasonNumber(season);
	const names = Array.from(new Set([input.title, ...input.alts ?? []].filter(Boolean))).slice(0, 4);
	const kind = input.kind === "series" ? "series" : "anime";
	const tmdb = await searchTmdb(names, kind).catch(() => null);
	let description = tmdb?.overview ?? null;
	let poster = tmdb?.poster ?? null;
	let banner = tmdb?.banner ?? null;
	const episodes = {};
	if (tmdb?.media === "tv") {
		const [details, seasonEps] = await Promise.all([tmdbTvDetails(tmdb.id).catch(() => null), tmdbSeasonEpisodes(tmdb.id, sNum).catch(() => [])]);
		if (details?.overview) description = details.overview;
		if (details?.poster) poster = details.poster;
		if (details?.banner) banner = details.banner;
		for (const ep of seasonEps) put(episodes, ep.number, {
			title: ep.title,
			overview: ep.overview,
			still: ep.still
		});
	}
	if (richness(episodes) < 3) {
		const maze = await fromTvMaze(tmdb ? [
			tmdb.name,
			tmdb.originalName,
			...names
		] : names, sNum);
		for (const ep of Object.values(maze)) put(episodes, ep.number, ep);
	}
	const value = {
		slug: input.slug,
		season,
		description: stripHtml(description),
		poster,
		banner,
		episodes
	};
	cache.set(key, {
		at: Date.now(),
		value
	});
	return value;
}
//#endregion
export { lookupSeriesMeta };
