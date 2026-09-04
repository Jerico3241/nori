import { r as __exportAll } from "../_runtime.mjs";
import { t as __exportAll$1 } from "./rolldown-runtime-D7D4PA-g.mjs";
import { n as create, t as persist } from "../_libs/zustand.mjs";
import { A as guessEpisodePath, z as useLibrary } from "./router-DDQw7P_P.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/trakt-wm9BT4pC.js
var trakt_wm9BT4pC_exports = /* @__PURE__ */ __exportAll({
	a: () => pullTraktWatched,
	c: () => trakt_exports,
	i: () => pullPublicWatched,
	l: () => useTrakt,
	n: () => isTraktConnected,
	o: () => startDeviceAuth,
	r: () => pollDeviceToken,
	s: () => traktServerCaps,
	t: () => ingestTraktExport
});
var trakt_exports = /* @__PURE__ */ __exportAll$1({
	ensureTraktToken: () => ensureTraktToken,
	ingestTraktExport: () => ingestTraktExport,
	isTraktConnected: () => isTraktConnected,
	pollDeviceToken: () => pollDeviceToken,
	pullPublicWatched: () => pullPublicWatched,
	pullTraktWatched: () => pullTraktWatched,
	pushWatchedEpisode: () => pushWatchedEpisode,
	scrobbleProgress: () => scrobbleProgress,
	startDeviceAuth: () => startDeviceAuth,
	traktServerCaps: () => traktServerCaps,
	useTrakt: () => useTrakt
});
function asRecord(value) {
	return value && typeof value === "object" && !Array.isArray(value) ? value : null;
}
function str(value) {
	return typeof value === "string" ? value.trim() : typeof value === "number" ? String(value) : "";
}
function num(value) {
	if (typeof value === "number" && Number.isFinite(value)) return value;
	if (typeof value === "string" && value.trim()) {
		const n = Number.parseInt(value, 10);
		return Number.isFinite(n) ? n : 0;
	}
	return 0;
}
function idsOf(raw) {
	const o = asRecord(raw);
	if (!o) return void 0;
	const ids = {};
	if (typeof o.trakt === "number") ids.trakt = o.trakt;
	else if (typeof o.trakt === "string" && o.trakt) ids.trakt = Number.parseInt(o.trakt, 10) || void 0;
	if (typeof o.slug === "string" && o.slug) ids.slug = o.slug;
	if (typeof o.imdb === "string" && o.imdb) ids.imdb = o.imdb;
	if (typeof o.tmdb === "number") ids.tmdb = o.tmdb;
	return Object.keys(ids).length ? ids : void 0;
}
function showKey(title, ids) {
	if (ids?.trakt) return `t:${ids.trakt}`;
	if (ids?.slug) return `s:${ids.slug}`;
	return `n:${title.toLowerCase()}`;
}
function addEpisode(bag, show, season, episode, watchedAt) {
	if (!show.title || !episode) return;
	const key = showKey(show.title, show.ids);
	let row = bag.get(key);
	if (!row) {
		row = {
			title: show.title,
			year: show.year,
			ids: show.ids,
			seasons: []
		};
		bag.set(key, row);
	}
	let seasonRow = row.seasons.find((s) => s.number === season);
	if (!seasonRow) {
		seasonRow = {
			number: season,
			episodes: []
		};
		row.seasons.push(seasonRow);
	}
	const existing = seasonRow.episodes.find((e) => e.number === episode);
	if (existing) {
		if (watchedAt && (!existing.last_watched_at || watchedAt > existing.last_watched_at)) existing.last_watched_at = watchedAt;
		return;
	}
	seasonRow.episodes.push({
		number: episode,
		last_watched_at: watchedAt
	});
}
function showFrom(raw) {
	const o = asRecord(raw);
	if (!o) return null;
	const nested = asRecord(o.show);
	const title = str(nested?.title) || str(o.title);
	if (!title) return null;
	return {
		title,
		year: num(nested?.year ?? o.year) || void 0,
		ids: idsOf(nested?.ids) || idsOf(o.ids)
	};
}
function fromWatchedShows(rows) {
	const out = [];
	for (const row of rows) {
		const o = asRecord(row);
		if (!o) continue;
		const show = showFrom(o.show ?? o);
		if (!show) continue;
		const seasons = [];
		const seasonRows = Array.isArray(o.seasons) ? o.seasons : [];
		for (const season of seasonRows) {
			const s = asRecord(season);
			if (!s) continue;
			const number = num(s.number);
			const episodes = [];
			for (const ep of Array.isArray(s.episodes) ? s.episodes : []) {
				const e = asRecord(ep);
				if (!e) continue;
				const epNumber = num(e.number);
				if (!epNumber) continue;
				episodes.push({
					number: epNumber,
					last_watched_at: str(e.last_watched_at) || void 0
				});
			}
			if (episodes.length) seasons.push({
				number,
				episodes
			});
		}
		if (seasons.length) out.push({
			...show,
			seasons
		});
	}
	return out;
}
function fromHistory(rows) {
	const bag = /* @__PURE__ */ new Map();
	for (const row of rows) {
		const o = asRecord(row);
		if (!o) continue;
		const type = str(o.type).toLowerCase();
		if (type && type !== "episode") continue;
		const episode = asRecord(o.episode);
		const show = showFrom(o.show) || showFrom(o);
		if (!show) continue;
		const season = num(episode?.season ?? o.season ?? o.episode_season);
		const number = num(episode?.number ?? o.number ?? o.episode ?? o.episode_number);
		if (!number) continue;
		addEpisode(bag, show, season, number, str(o.watched_at || o.last_watched_at || episode?.last_watched_at) || void 0);
	}
	return [...bag.values()];
}
function splitCsvLine(line) {
	const out = [];
	let cur = "";
	let quoted = false;
	for (let i = 0; i < line.length; i++) {
		const ch = line[i];
		if (quoted) {
			if (ch === "\"" && line[i + 1] === "\"") {
				cur += "\"";
				i += 1;
			} else if (ch === "\"") quoted = false;
			else cur += ch;
		} else if (ch === "\"") quoted = true;
		else if (ch === ",") {
			out.push(cur.trim());
			cur = "";
		} else cur += ch;
	}
	out.push(cur.trim());
	return out;
}
function parseCsv(text) {
	const lines = text.replace(/^\uFEFF/, "").split(/\r?\n/).filter((l) => l.trim());
	if (lines.length < 2) return [];
	const headers = splitCsvLine(lines[0]).map((h) => h.toLowerCase().replace(/[^\w]+/g, "_"));
	const idx = (names) => {
		for (const name of names) {
			const i = headers.indexOf(name);
			if (i >= 0) return i;
		}
		return -1;
	};
	const col = (cells, i) => i >= 0 ? cells[i] ?? "" : "";
	const typeI = idx(["type"]);
	const titleI = idx([
		"show_title",
		"show",
		"title"
	]);
	const seasonI = idx(["season", "episode_season"]);
	const episodeI = idx([
		"episode",
		"episode_number",
		"number"
	]);
	const watchedI = idx([
		"watched_at",
		"last_watched_at",
		"watched"
	]);
	const slugI = idx([
		"show_slug",
		"trakt_slug",
		"slug"
	]);
	const traktI = idx([
		"show_trakt_id",
		"trakt_id",
		"trakt"
	]);
	const bag = /* @__PURE__ */ new Map();
	for (const line of lines.slice(1)) {
		const cells = splitCsvLine(line);
		const type = col(cells, typeI).toLowerCase();
		if (type && type !== "episode") continue;
		const title = col(cells, titleI);
		const episode = num(col(cells, episodeI));
		if (!title || !episode) continue;
		const ids = {};
		const slug = col(cells, slugI);
		const trakt = num(col(cells, traktI));
		if (slug) ids.slug = slug;
		if (trakt) ids.trakt = trakt;
		addEpisode(bag, {
			title,
			ids: Object.keys(ids).length ? ids : void 0
		}, num(col(cells, seasonI)), episode, col(cells, watchedI) || void 0);
	}
	return [...bag.values()];
}
function parseTraktExport(input) {
	if (typeof input === "string") {
		const trimmed = input.trim();
		if (!trimmed) return [];
		if (trimmed.startsWith("{") || trimmed.startsWith("[")) try {
			return parseTraktExport(JSON.parse(trimmed));
		} catch {
			return [];
		}
		return parseCsv(trimmed);
	}
	if (Array.isArray(input)) {
		if (input.length === 0) return [];
		const first = asRecord(input[0]);
		if (!first) return [];
		if (first.type || first.episode || first.action || first.watched_at) return fromHistory(input);
		if (first.show || first.seasons) return fromWatchedShows(input);
		return [];
	}
	const obj = asRecord(input);
	if (!obj) return [];
	const watched = asRecord(obj.watched);
	if (watched && Array.isArray(watched.shows)) return fromWatchedShows(watched.shows);
	if (Array.isArray(obj.shows)) return fromWatchedShows(obj.shows);
	if (Array.isArray(obj.history)) return fromHistory(obj.history);
	if (Array.isArray(obj.watched)) return fromWatchedShows(obj.watched);
	return [];
}
function isTraktUsername(value) {
	return /^[A-Za-z0-9_-]{2,32}$/.test(value.trim());
}
function normalizeTitle(raw) {
	return raw.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/&/g, " and ").replace(/[^a-z0-9]+/g, " ").replace(/\b(the|der|die|das|a|an|tv|season|staffel)\b/g, " ").replace(/\s+/g, " ").trim();
}
function buildMatchIndex(items) {
	const bySlug = /* @__PURE__ */ new Map();
	const byTitle = /* @__PURE__ */ new Map();
	for (const item of items) {
		bySlug.set(item.slug, item);
		const titleKey = normalizeTitle(item.title);
		if (titleKey && !byTitle.has(titleKey)) byTitle.set(titleKey, item);
		for (const alt of item.alts) {
			const key = normalizeTitle(alt);
			if (key && !byTitle.has(key)) byTitle.set(key, item);
		}
	}
	return {
		bySlug,
		byTitle,
		items
	};
}
function matchCatalogItem(show, items) {
	const index = Array.isArray(items) ? buildMatchIndex(items) : items;
	const traktSlug = show.ids?.slug || "";
	if (traktSlug) {
		const bySlug = index.bySlug.get(traktSlug);
		if (bySlug) return bySlug;
	}
	const want = normalizeTitle(show.title);
	if (!want) return void 0;
	const exact = index.byTitle.get(want);
	if (exact) return exact;
	for (const item of index.items) {
		const have = normalizeTitle(item.title);
		if (have && (have.includes(want) || want.includes(have)) && Math.abs(have.length - want.length) <= 8) return item;
	}
}
var useTrakt = create()(persist((set) => ({
	clientId: "",
	clientSecret: "",
	accessToken: "",
	refreshToken: "",
	tokenExpiresAt: 0,
	username: "",
	lastSyncAt: 0,
	maps: {},
	setCredentials: (clientId, clientSecret) => set({
		clientId: clientId.trim(),
		clientSecret: clientSecret.trim()
	}),
	setUsername: (username) => set({ username: username.trim() }),
	setTokens: ({ accessToken, refreshToken, expiresIn, username }) => set({
		accessToken,
		refreshToken,
		tokenExpiresAt: Date.now() + Math.max(60, expiresIn - 120) * 1e3,
		username: username ?? ""
	}),
	rememberShow: (slug, show) => set((s) => ({ maps: {
		...s.maps,
		[slug]: show
	} })),
	disconnect: () => set({
		accessToken: "",
		refreshToken: "",
		tokenExpiresAt: 0,
		username: "",
		lastSyncAt: 0
	}),
	markSynced: () => set({ lastSyncAt: Date.now() })
}), {
	name: "nori-trakt",
	version: 1
}));
function isTraktConnected() {
	return Boolean(useTrakt.getState().accessToken);
}
function storageCatalog() {
	if (typeof window === "undefined") return [];
	const items = [];
	const seen = /* @__PURE__ */ new Set();
	try {
		const raw = window.sessionStorage.getItem("nori-catalog-v1") || window.localStorage.getItem("nori-catalog-v1");
		if (!raw) return items;
		const parsed = JSON.parse(raw);
		for (const item of parsed.items ?? []) {
			if (!item?.slug || !item?.title || seen.has(item.slug)) continue;
			items.push({
				slug: item.slug,
				title: item.title,
				alts: Array.isArray(item.alts) ? item.alts : []
			});
			seen.add(item.slug);
		}
	} catch {}
	return items;
}
async function catalogForMatch() {
	const items = storageCatalog();
	const seen = new Set(items.map((i) => i.slug));
	const titles = useLibrary.getState().titles;
	for (const [slug, title] of Object.entries(titles)) {
		if (!slug || !title || seen.has(slug)) continue;
		items.push({
			slug,
			title,
			alts: []
		});
		seen.add(slug);
	}
	if (items.length < 40) try {
		const { fallbackCatalog } = await import("./client-fallback-BxiYvHD-.mjs");
		for (const item of fallbackCatalog().items) {
			if (!item?.slug || seen.has(item.slug)) continue;
			items.push({
				slug: item.slug,
				title: item.title,
				alts: item.alts ?? []
			});
			seen.add(item.slug);
		}
	} catch {}
	return items;
}
async function traktPost(payload) {
	const res = await fetch("/api/trakt", {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify(payload)
	});
	const json = await res.json().catch(() => ({}));
	if (!res.ok && json.ok !== false) return {
		ok: false,
		status: res.status,
		error: json.error || `HTTP ${res.status}`
	};
	return {
		...json,
		ok: json.ok !== false && res.ok,
		status: json.status ?? res.status
	};
}
async function traktServerCaps() {
	try {
		const json = await (await fetch("/api/trakt")).json();
		return {
			serverApp: Boolean(json.serverApp),
			hasClientId: Boolean(json.hasClientId || json.serverApp)
		};
	} catch {
		return {
			serverApp: false,
			hasClientId: false
		};
	}
}
function creds() {
	const s = useTrakt.getState();
	return {
		clientId: s.clientId,
		clientSecret: s.clientSecret
	};
}
async function startDeviceAuth() {
	const { clientId, clientSecret } = creds();
	const result = await traktPost({
		action: "device-code",
		clientId,
		clientSecret
	});
	if (!result.ok) throw new Error(result.error || "Trakt-Code konnte nicht erzeugt werden.");
	const data = result.data;
	if (!data?.device_code || !data?.user_code) throw new Error("Ungültige Antwort von Trakt.");
	return {
		deviceCode: data.device_code,
		userCode: data.user_code,
		verificationUrl: data.verification_url || "https://trakt.tv/activate",
		expiresIn: data.expires_in || 600,
		interval: Math.max(5, data.interval || 5)
	};
}
async function pollDeviceToken(deviceCode) {
	const { clientId, clientSecret } = creds();
	const result = await traktPost({
		action: "device-token",
		clientId,
		clientSecret,
		deviceCode
	});
	if (result.pending) return "pending";
	if (result.status === 429) return "slow";
	if (result.status === 410) return "expired";
	if (result.status === 418 || result.status === 409) return "denied";
	if (!result.ok) throw new Error(result.error || "Trakt hat abgelehnt.");
	const data = result.data;
	if (!data?.access_token) throw new Error("Kein Token erhalten.");
	useTrakt.getState().setTokens({
		accessToken: data.access_token,
		refreshToken: data.refresh_token,
		expiresIn: data.expires_in || 604800
	});
	try {
		const user = await traktProxy("/users/me");
		if (user?.username) useTrakt.getState().setTokens({
			accessToken: data.access_token,
			refreshToken: data.refresh_token,
			expiresIn: data.expires_in || 604800,
			username: user.username
		});
	} catch {}
	return "done";
}
async function refreshTokens() {
	const s = useTrakt.getState();
	if (!s.refreshToken) return false;
	const result = await traktPost({
		action: "refresh",
		clientId: s.clientId,
		clientSecret: s.clientSecret,
		refreshToken: s.refreshToken
	});
	if (!result.ok) return false;
	const data = result.data;
	if (!data?.access_token) return false;
	s.setTokens({
		accessToken: data.access_token,
		refreshToken: data.refresh_token || s.refreshToken,
		expiresIn: data.expires_in || 604800,
		username: s.username
	});
	return true;
}
async function ensureTraktToken() {
	const s = useTrakt.getState();
	if (!s.accessToken) return null;
	if (s.tokenExpiresAt && Date.now() > s.tokenExpiresAt - 1e4) {
		if (!await refreshTokens()) return s.accessToken;
	}
	return useTrakt.getState().accessToken;
}
async function traktProxy(path, init) {
	const accessToken = await ensureTraktToken();
	if (!accessToken) throw new Error("Nicht mit Trakt verbunden.");
	const s = useTrakt.getState();
	let result = await traktPost({
		action: "proxy",
		path,
		method: init?.method || "GET",
		query: init?.query,
		body: init?.body,
		accessToken,
		clientId: s.clientId,
		clientSecret: s.clientSecret
	});
	if (result.status === 401) {
		if (await refreshTokens()) result = await traktPost({
			action: "proxy",
			path,
			method: init?.method || "GET",
			query: init?.query,
			body: init?.body,
			accessToken: useTrakt.getState().accessToken,
			clientId: s.clientId,
			clientSecret: s.clientSecret
		});
	}
	if (!result.ok) throw new Error(result.error || `Trakt ${result.status}`);
	return result.data;
}
function asWatchedShows(rows) {
	return rows.map((row) => ({
		show: {
			title: row.title,
			year: row.year,
			ids: row.ids
		},
		seasons: row.seasons.map((season) => ({
			number: season.number,
			episodes: season.episodes.map((ep) => ({
				number: ep.number,
				last_watched_at: ep.last_watched_at
			}))
		}))
	}));
}
async function ingestWatchedShows(watched, playback = []) {
	const index = buildMatchIndex(await catalogForMatch());
	const incoming = [];
	const maps = useTrakt.getState().maps;
	let shows = 0;
	let unmatched = 0;
	for (const row of watched) {
		const title = row.show?.title;
		if (!title) continue;
		const hit = matchCatalogItem({
			title,
			ids: row.show?.ids
		}, index);
		if (!hit) {
			unmatched += 1;
			continue;
		}
		shows += 1;
		if (row.show?.ids?.trakt) useTrakt.getState().rememberShow(hit.slug, {
			trakt: row.show.ids.trakt,
			slug: row.show.ids.slug,
			title
		});
		for (const season of row.seasons ?? []) {
			const seasonId = season.number === 0 ? "filme" : String(season.number ?? 1);
			for (const ep of season.episodes ?? []) {
				if (!ep.number) continue;
				const watchedAt = Date.parse(ep.last_watched_at || row.last_watched_at || "") || Date.now();
				incoming.push({
					slug: hit.slug,
					title: hit.title,
					season: seasonId,
					episode: ep.number,
					episodePath: guessEpisodePath(hit.slug, seasonId, ep.number),
					germanTitle: "",
					englishTitle: "",
					positionSec: 1,
					durationSec: 1,
					updatedAt: watchedAt,
					completed: true
				});
			}
		}
	}
	for (const row of playback) {
		const title = row.show?.title;
		if (!title || !row.episode?.number) continue;
		const hit = matchCatalogItem({
			title,
			ids: row.show?.ids
		}, index) || (row.show?.ids?.trakt ? Object.entries(maps).find(([, m]) => m.trakt === row.show?.ids?.trakt)?.[0] : void 0);
		const slug = typeof hit === "string" ? hit : hit?.slug;
		const seriesTitle = typeof hit === "string" ? title : hit?.title || title;
		if (!slug) continue;
		const seasonId = row.episode.season === 0 ? "filme" : String(row.episode.season ?? 1);
		const ratio = Math.max(0, Math.min(.89, (row.progress || 0) / 100));
		incoming.push({
			slug,
			title: seriesTitle,
			season: seasonId,
			episode: row.episode.number,
			episodePath: guessEpisodePath(slug, seasonId, row.episode.number),
			germanTitle: row.episode.title || "",
			englishTitle: "",
			positionSec: Math.round(ratio * 1400),
			durationSec: 1400,
			updatedAt: Date.parse(row.paused_at || "") || Date.now(),
			completed: false
		});
	}
	const episodes = useLibrary.getState().importWatched(incoming);
	useTrakt.getState().markSynced();
	return {
		shows,
		episodes,
		unmatched
	};
}
async function ingestTraktExport(raw) {
	const parsed = typeof raw === "string" || raw == null ? parseTraktExport(raw ?? "") : parseTraktExport(raw);
	if (!parsed.length) throw new Error("Keine gesehenen Folgen in der Datei gefunden.");
	return ingestWatchedShows(asWatchedShows(parsed));
}
async function pullPublicWatched(username) {
	const name = username.trim();
	if (!isTraktUsername(name)) throw new Error("Ungültiger Trakt-Benutzername.");
	useTrakt.getState().setUsername(name);
	const result = await traktPost({
		action: "public-watched",
		username: name,
		clientId: useTrakt.getState().clientId
	});
	if (!result.ok) {
		if (result.status === 404) throw new Error("Profil nicht gefunden oder nicht öffentlich.");
		if (result.status === 403 || result.status === 401) throw new Error("Trakt blockt ohne API-Key. Export unter trakt.tv/settings/data nutzen.");
		throw new Error(result.error || "Öffentlicher Verlauf nicht lesbar.");
	}
	const rows = Array.isArray(result.data) ? result.data : [];
	if (!rows.length) throw new Error("Keine gesehenen Serien auf dem öffentlichen Profil.");
	return ingestWatchedShows(rows);
}
async function pullTraktWatched() {
	if (!isTraktConnected()) {
		const name = useTrakt.getState().username;
		if (name) return pullPublicWatched(name);
		throw new Error("Kein Trakt-Verlauf hinterlegt. Export importieren oder Benutzername setzen.");
	}
	const watched = await traktProxy("/sync/watched/shows");
	const playback = await traktProxy("/sync/playback/episodes").catch(() => []);
	return ingestWatchedShows(Array.isArray(watched) ? watched : [], Array.isArray(playback) ? playback : []);
}
async function resolveShow(item) {
	const mapped = useTrakt.getState().maps[item.slug];
	if (mapped?.trakt) return {
		title: mapped.title || item.title,
		ids: {
			trakt: mapped.trakt,
			slug: mapped.slug
		}
	};
	const local = (await catalogForMatch()).find((i) => i.slug === item.slug) ?? {
		slug: item.slug,
		title: item.title,
		alts: []
	};
	const queries = [item.title, ...local.alts ?? []].filter(Boolean).slice(0, 3);
	for (const q of queries) {
		const rows = await traktProxy("/search/show", { query: { query: q } }).catch(() => []);
		const list = Array.isArray(rows) ? rows : [];
		for (const row of list) {
			if (!row.show) continue;
			if (matchCatalogItem(row.show, [local]) || normalizeTitle(row.show.title) === normalizeTitle(item.title)) {
				if (row.show.ids.trakt) useTrakt.getState().rememberShow(item.slug, {
					trakt: row.show.ids.trakt,
					slug: row.show.ids.slug,
					title: row.show.title
				});
				return row.show;
			}
		}
		if (list[0]?.show?.ids?.trakt && normalizeTitle(list[0].show.title).includes(normalizeTitle(item.title).slice(0, 12))) {
			const show = list[0].show;
			useTrakt.getState().rememberShow(item.slug, {
				trakt: show.ids.trakt,
				slug: show.ids.slug,
				title: show.title
			});
			return show;
		}
	}
	return null;
}
async function pushWatchedEpisode(item) {
	if (!isTraktConnected()) return;
	const show = await resolveShow(item);
	const seasonNumber = item.season === "filme" ? 0 : Number(item.season) || 1;
	await traktProxy("/sync/history", {
		method: "POST",
		body: show?.ids?.trakt ? { shows: [{
			ids: { trakt: show.ids.trakt },
			seasons: [{
				number: seasonNumber,
				episodes: [{ number: item.episode }]
			}]
		}] } : { shows: [{
			title: item.title,
			seasons: [{
				number: seasonNumber,
				episodes: [{ number: item.episode }]
			}]
		}] }
	});
}
var scrobbleAt = 0;
async function scrobbleProgress(item, action) {
	if (!isTraktConnected()) return;
	const now = Date.now();
	if (action !== "stop" && now - scrobbleAt < 2e4) return;
	scrobbleAt = now;
	const show = await resolveShow(item);
	if (!show?.ids?.trakt) return;
	const duration = item.durationSec > 8 ? item.durationSec : 0;
	const progress = duration > 0 ? Math.max(1, Math.min(99, item.positionSec / duration * 100)) : 1;
	const seasonNumber = item.season === "filme" ? 0 : Number(item.season) || 1;
	await traktProxy(`/scrobble/${action}`, {
		method: "POST",
		body: {
			show: { ids: { trakt: show.ids.trakt } },
			episode: {
				season: seasonNumber,
				number: item.episode
			},
			progress
		}
	}).catch(() => void 0);
}
//#endregion
export { pullTraktWatched as a, trakt_wm9BT4pC_exports as c, pullPublicWatched as i, useTrakt as l, isTraktConnected as n, startDeviceAuth as o, pollDeviceToken as r, traktServerCaps as s, ingestTraktExport as t };
