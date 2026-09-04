//#region node_modules/.nitro/vite/services/ssr/assets/tmdb.server-KxAOssiY.js
var TMDB = "https://api.themoviedb.org/3";
var IMG = "https://image.tmdb.org/t/p";
var ANIMATION = 16;
function apiKey() {
	return process.env.TMDB_API_KEY?.trim() || process.env.TMDB_KEY?.trim() || "8265bd1679663a7ea12ac168da84d2e8";
}
function bearer() {
	return process.env.TMDB_READ_TOKEN?.trim() || null;
}
function tmdbImage(path, size = "w780") {
	if (!path) return null;
	if (path.startsWith("http")) return path;
	return `${IMG}/${size}${path}`;
}
var windowStart = Date.now();
var windowCount = 0;
async function gate() {
	const now = Date.now();
	if (now - windowStart >= 1e4) {
		windowStart = now;
		windowCount = 0;
	}
	if (windowCount >= 32) {
		const wait = 1e4 - (now - windowStart) + 40;
		await new Promise((r) => setTimeout(r, Math.max(40, wait)));
		windowStart = Date.now();
		windowCount = 0;
	}
	windowCount += 1;
}
async function tmdbGet(path, query = {}) {
	await gate();
	const url = new URL(`${TMDB}${path}`);
	url.searchParams.set("language", "de-DE");
	url.searchParams.set("include_adult", "false");
	for (const [k, v] of Object.entries(query)) {
		if (v === void 0 || v === "") continue;
		url.searchParams.set(k, String(v));
	}
	const token = bearer();
	const headers = { Accept: "application/json" };
	if (token) headers.Authorization = `Bearer ${token}`;
	else url.searchParams.set("api_key", apiKey());
	const res = await fetch(url.toString(), {
		headers,
		signal: AbortSignal.timeout(8e3)
	});
	if (!res.ok) throw new Error(`tmdb ${res.status}`);
	return await res.json();
}
function norm(s) {
	return s.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, " ").trim();
}
function titleVariants(title, alts = []) {
	const raw = [title, ...alts].map((s) => s.trim()).filter((s) => s.length >= 2);
	const extra = [];
	for (const s of raw) {
		const noYear = s.replace(/\s*\(\d{4}\)\s*/g, " ").replace(/\s+/g, " ").trim();
		if (noYear && noYear !== s) extra.push(noYear);
		const noDash = s.replace(/\s*[-–—:].+$/, "").trim();
		if (noDash.length >= 3 && noDash !== s) extra.push(noDash);
		const noKind = s.replace(/\s+\((?:tv|serie|series|die serie|the series|anime)\)\s*$/i, "").trim();
		if (noKind.length >= 3 && noKind !== s) extra.push(noKind);
	}
	return [...new Set([...raw, ...extra].filter((s) => s.length >= 2))].slice(0, 6);
}
function scoreTv(row, q, kind) {
	const nq = norm(q);
	const name = norm(String(row.name || row.title || ""));
	const orig = norm(String(row.original_name || row.original_title || ""));
	let s = Number(row.popularity ?? 0);
	if (name === nq || orig === nq) s += 400;
	else if (name.startsWith(nq) || orig.startsWith(nq) || nq.startsWith(name)) s += 180;
	else if (name.includes(nq) || orig.includes(nq) || nq.includes(name)) s += 80;
	const genres = Array.isArray(row.genre_ids) ? row.genre_ids : [];
	const countries = Array.isArray(row.origin_country) ? row.origin_country : [];
	if (kind === "anime") {
		if (genres.includes(ANIMATION)) s += 120;
		if (countries.includes("JP")) s += 60;
	} else {
		if (genres.includes(ANIMATION) && countries.includes("JP")) s -= 90;
		else if (countries.includes("JP")) s -= 20;
		if (countries.includes("US") || countries.includes("GB") || countries.includes("DE")) s += 40;
	}
	if (!row.poster_path) s -= 50;
	return s;
}
async function searchTmdb(names, kind = "anime") {
	const queries = titleVariants(names[0] || "", names.slice(1));
	let best = null;
	for (const q of queries.slice(0, 4)) try {
		const found = await tmdbGet("/search/tv", { query: q });
		for (const row of found.results ?? []) {
			if (!row.id) continue;
			const sc = scoreTv(row, q, kind);
			if (!best || sc > best.score) best = {
				score: sc,
				hit: {
					id: row.id,
					media: "tv",
					name: row.name || q,
					originalName: row.original_name || "",
					overview: row.overview || null,
					poster: tmdbImage(row.poster_path, "w780"),
					banner: tmdbImage(row.backdrop_path, "w1280")
				}
			};
		}
		if (best && best.score >= 400 && best.hit.poster) return best.hit;
	} catch {}
	if (best && best.score >= 45 && best.hit.poster) return best.hit;
	for (const q of queries.slice(0, 2)) try {
		const row = (await tmdbGet("/search/movie", { query: q })).results?.[0];
		if (row?.poster_path) return {
			id: row.id,
			media: "movie",
			name: row.title || q,
			originalName: row.original_title || "",
			overview: row.overview || null,
			poster: tmdbImage(row.poster_path, "w780"),
			banner: tmdbImage(row.backdrop_path, "w1280")
		};
	} catch {}
	return best?.hit?.poster ? best.hit : null;
}
async function tmdbTvDetails(id) {
	const de = await tmdbGet(`/tv/${id}`);
	let overview = de.overview || null;
	if (!overview) try {
		overview = (await tmdbGet(`/tv/${id}`, { language: "en-US" })).overview || null;
	} catch {}
	return {
		overview,
		poster: tmdbImage(de.poster_path, "w780"),
		banner: tmdbImage(de.backdrop_path, "w1280")
	};
}
async function tmdbSeasonEpisodes(id, season) {
	const data = await tmdbGet(`/tv/${id}/season/${season}`);
	const out = [];
	for (const ep of data.episodes ?? []) {
		if (!ep.episode_number) continue;
		out.push({
			number: ep.episode_number,
			title: ep.name || null,
			overview: ep.overview || null,
			still: tmdbImage(ep.still_path, "w500")
		});
	}
	if (out.some((e) => e.overview && e.overview.length > 20)) return out;
	try {
		const en = await tmdbGet(`/tv/${id}/season/${season}`, { language: "en-US" });
		const byN = new Map(out.map((e) => [e.number, e]));
		for (const ep of en.episodes ?? []) {
			if (!ep.episode_number) continue;
			const prev = byN.get(ep.episode_number);
			if (!prev) {
				byN.set(ep.episode_number, {
					number: ep.episode_number,
					title: ep.name || null,
					overview: ep.overview || null,
					still: tmdbImage(ep.still_path, "w500")
				});
				continue;
			}
			if (!prev.overview) prev.overview = ep.overview || null;
			if (!prev.still) prev.still = tmdbImage(ep.still_path, "w500");
			if (!prev.title) prev.title = ep.name || null;
		}
		return [...byN.values()].sort((a, b) => a.number - b.number);
	} catch {
		return out;
	}
}
async function mapPool(items, limit, fn) {
	const out = new Array(items.length);
	let i = 0;
	async function worker() {
		while (i < items.length) {
			const idx = i++;
			out[idx] = await fn(items[idx]);
		}
	}
	await Promise.all(Array.from({ length: Math.min(limit, items.length) }, () => worker()));
	return out;
}
//#endregion
export { tmdbTvDetails as i, searchTmdb as n, tmdbSeasonEpisodes as r, mapPool as t };
