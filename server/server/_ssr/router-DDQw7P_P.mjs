import { o as __toESM } from "../_runtime.mjs";
import { t as __exportAll } from "./rolldown-runtime-D7D4PA-g.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { M as parseSearchWith, N as stringifySearchWith, V as redirect, _ as createRootRoute, b as useNavigate, d as useRouterState, g as createFileRoute, h as lazyRouteComponent, l as Scripts, m as Outlet, p as createRouter, u as HeadContent, v as Link, x as useRouter } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime, n as QueryClientProvider, r as useQueryClient } from "../_libs/react+tanstack__react-query.mjs";
import { a as getServerFnById, i as TSS_SERVER_FUNCTION, r as createServerFn } from "./ssr.mjs";
import { t as authMiddleware } from "./middleware-Bflz3Va7.mjs";
import { bn as union, gn as object, hn as number, pn as literal, un as array, vn as record, yn as string } from "../_libs/@better-auth/core+[...].mjs";
import { n as create, t as persist } from "../_libs/zustand.mjs";
import { a as otherProvider, n as asProvider, o as providerFromPath, r as isCatalogProvider, s as useProvider } from "./provider-B-pxa-h2.mjs";
import { t as cn } from "./cn-Ccejyh36.mjs";
import { t as auth } from "./server-DR24G2td.mjs";
import "./client-C_SNNFs7.mjs";
import { O as CalendarDays, S as Heart, a as TriangleAlert, b as LayoutGrid, d as Search, i as UserRound, u as Settings2, x as House } from "../_libs/lucide-react.mjs";
import { t as QueryClient } from "../_libs/tanstack__query-core.mjs";
import { Readable } from "node:stream";
import { createReadStream, existsSync, readFileSync, statSync } from "node:fs";
//#region node_modules/.nitro/vite/services/ssr/assets/library-Ce5X_-2F.js
function progressKey(path, lang) {
	return lang ? `${path}::${lang}` : path;
}
function guessEpisodePath(slug, season, episode, provider) {
	const prefix = asProvider(provider) === "serienstream" ? "/serie" : "/anime/stream";
	if (season === "filme") return `${prefix}/${slug}/filme/film-${episode}`;
	return `${prefix}/${slug}/staffel-${season || "1"}/episode-${episode}`;
}
function normalizeEpisodePath(path) {
	if (!path) return "";
	try {
		if (path.startsWith("http")) path = new URL(path).pathname;
	} catch {}
	return path.replace(/\/+$/, "");
}
function progressForPath(progress, path, lang) {
	const clean = normalizeEpisodePath(path);
	if (lang) {
		const keyed = progress[progressKey(clean, lang)] ?? progress[progressKey(path, lang)];
		if (keyed) return keyed;
	}
	let best = progress[clean] ?? progress[path];
	const prefixes = [`${clean}::`, `${path}::`];
	for (const [key, item] of Object.entries(progress)) if (key === clean || key === path || prefixes.some((p) => key.startsWith(p))) {
		if (!best || item.updatedAt > best.updatedAt) best = item;
	}
	return best;
}
function progressForEpisode(progress, opts) {
	if (opts.path) {
		const byPath = progressForPath(progress, opts.path, opts.lang);
		if (byPath) return byPath;
	}
	let best;
	for (const item of Object.values(progress)) {
		if (item.slug !== opts.slug) continue;
		if (String(item.season) !== String(opts.season)) continue;
		if (Number(item.episode) !== Number(opts.episode)) continue;
		if (!best || item.updatedAt > best.updatedAt) best = item;
	}
	return best;
}
function isEpisodeComplete(item) {
	if (!item) return false;
	if (item.completed) return true;
	if (item.durationSec >= 20 && item.positionSec >= item.durationSec * .9) return true;
	return false;
}
function watchRatio(item) {
	if (!item) return 0;
	if (isEpisodeComplete(item)) return 1;
	if (item.durationSec < 8) return 0;
	return Math.max(0, Math.min(1, item.positionSec / item.durationSec));
}
function resumePosition(item) {
	if (!item || isEpisodeComplete(item)) return 0;
	const pos = item.positionSec || 0;
	if (pos < 8) return 0;
	return pos;
}
function seasonWatchStats(progress, opts) {
	let watched = 0;
	for (const episode of opts.episodes) if (isEpisodeComplete(progressForEpisode(progress, {
		path: episode.path,
		slug: opts.slug,
		season: opts.season,
		episode: episode.number
	}))) watched += 1;
	const total = opts.episodes.length;
	return {
		watched,
		total,
		pct: total ? Math.round(watched / total * 100) : 0
	};
}
function continueWatching(progress) {
	const latest = /* @__PURE__ */ new Map();
	for (const item of Object.values(progress)) {
		const prev = latest.get(item.slug);
		if (!prev || item.updatedAt > prev.updatedAt) latest.set(item.slug, item);
	}
	return [...latest.values()].filter((item) => !isEpisodeComplete(item) && (item.positionSec < item.durationSec * .96 || item.durationSec < 20)).sort((a, b) => b.updatedAt - a.updatedAt).slice(0, 16);
}
function progressForSlug(progress, slug) {
	let best;
	for (const item of Object.values(progress)) {
		if (item.slug !== slug) continue;
		if (!best || item.updatedAt > best.updatedAt) best = item;
	}
	return best;
}
function shouldPersistProgress(opts) {
	if (!Number.isFinite(opts.current) || opts.current < 2) return false;
	if (opts.userSeek || opts.landed) return true;
	if (opts.resumeTarget >= 8) return false;
	return true;
}
function nextPlayTarget(progress, opts) {
	const eps = opts.episodes;
	if (eps.length === 0) return {
		episode: 1,
		resumeAt: 0,
		kind: "play"
	};
	const latest = progressForSlug(progress, opts.slug);
	if (latest && String(latest.season) === String(opts.season) && !isEpisodeComplete(latest)) {
		if (eps.some((e) => e.number === latest.episode)) {
			const at = resumePosition(latest);
			return {
				episode: latest.episode,
				resumeAt: at,
				kind: at >= 8 ? "resume" : "play"
			};
		}
	}
	for (const ep of eps) {
		const item = progressForEpisode(progress, {
			path: ep.path,
			slug: opts.slug,
			season: opts.season,
			episode: ep.number
		});
		if (!isEpisodeComplete(item)) {
			const at = resumePosition(item);
			return {
				episode: ep.number,
				resumeAt: at,
				kind: at >= 8 ? "resume" : "next"
			};
		}
	}
	return {
		episode: eps[0].number,
		resumeAt: 0,
		kind: "play"
	};
}
function formatClock(sec) {
	const s = Math.max(0, Math.floor(sec));
	const h = Math.floor(s / 3600);
	const m = Math.floor(s % 3600 / 60);
	const r = s % 60;
	if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}`;
	return `${m}:${String(r).padStart(2, "0")}`;
}
function writeProgress(bag, item) {
	const path = normalizeEpisodePath(item.episodePath) || item.episodePath;
	const next = {
		...item,
		episodePath: path
	};
	bag[progressKey(path, next.lang)] = next;
	bag[path] = next;
	return bag;
}
function mergeIncoming(prev, item) {
	const durationSec = Number.isFinite(item.durationSec) && item.durationSec >= 8 ? item.durationSec : prev?.durationSec && prev.durationSec >= 8 ? prev.durationSec : Number.isFinite(item.durationSec) ? item.durationSec : 0;
	const positionSec = Number.isFinite(item.positionSec) ? item.positionSec : prev?.positionSec || 0;
	const completed = item.completed || prev?.completed && positionSec >= durationSec * .9 || durationSec >= 20 && positionSec >= durationSec * .9;
	return {
		...prev,
		...item,
		episodePath: normalizeEpisodePath(item.episodePath) || item.episodePath,
		durationSec,
		positionSec,
		completed,
		provider: item.provider || prev?.provider || providerFromPath(item.episodePath || prev?.episodePath)
	};
}
var useLibrary = create()(persist((set, get) => ({
	ownerId: null,
	favorites: [],
	recents: [],
	covers: {},
	titles: {},
	progress: {},
	toggleFavorite: (slug, title) => set((state) => {
		const on = state.favorites.includes(slug);
		const titles = title && !on ? {
			...state.titles,
			[slug]: title
		} : state.titles;
		return {
			favorites: on ? state.favorites.filter((s) => s !== slug) : [slug, ...state.favorites],
			titles
		};
	}),
	isFavorite: (slug) => get().favorites.includes(slug),
	remember: ({ slug, title, provider }) => set((state) => ({
		recents: [{
			slug,
			title,
			viewedAt: Date.now(),
			provider
		}, ...state.recents.filter((r) => r.slug !== slug)].slice(0, 24),
		titles: {
			...state.titles,
			[slug]: title
		}
	})),
	mergeCovers: (arts) => set((state) => {
		if (arts.length === 0) return state;
		let changed = false;
		const merged = { ...state.covers };
		for (const art of arts) {
			const prev = merged[art.slug];
			if (prev && prev.poster === art.poster && prev.banner === art.banner) continue;
			merged[art.slug] = art;
			changed = true;
		}
		return changed ? { covers: merged } : state;
	}),
	upsertProgress: (item) => set((state) => {
		const prev = state.progress[progressKey(normalizeEpisodePath(item.episodePath), item.lang)] ?? state.progress[normalizeEpisodePath(item.episodePath)] ?? state.progress[item.episodePath];
		const next = mergeIncoming(prev, item);
		if (prev && Math.abs((prev.positionSec || 0) - next.positionSec) < 1.25 && Boolean(prev.completed) === Boolean(next.completed) && Math.abs((prev.durationSec || 0) - next.durationSec) < 1 && prev.lang === next.lang) return state;
		return {
			progress: writeProgress({ ...state.progress }, next),
			titles: {
				...state.titles,
				[next.slug]: next.title
			},
			recents: [{
				slug: next.slug,
				title: next.title,
				viewedAt: next.updatedAt,
				provider: next.provider || providerFromPath(next.episodePath)
			}, ...state.recents.filter((r) => r.slug !== next.slug)].slice(0, 24)
		};
	}),
	importWatched: (items) => {
		if (items.length === 0) return 0;
		let added = 0;
		set((state) => {
			const progress = { ...state.progress };
			const titles = { ...state.titles };
			const recents = [...state.recents];
			for (const raw of items) {
				if (!raw?.slug) continue;
				const path = normalizeEpisodePath(raw.episodePath) || guessEpisodePath(raw.slug, raw.season, raw.episode);
				const prev = progressForEpisode(progress, {
					path,
					slug: raw.slug,
					season: raw.season,
					episode: raw.episode
				});
				if (prev && prev.updatedAt > raw.updatedAt && isEpisodeComplete(prev)) continue;
				if (prev && !raw.completed && isEpisodeComplete(prev)) continue;
				if (prev && !raw.completed && (prev.positionSec || 0) >= (raw.positionSec || 0) && prev.updatedAt >= raw.updatedAt) continue;
				const next = mergeIncoming(prev, {
					...raw,
					episodePath: path
				});
				writeProgress(progress, next);
				titles[next.slug] = next.title || titles[next.slug] || next.slug;
				if (!recents.some((r) => r.slug === next.slug)) recents.unshift({
					slug: next.slug,
					title: next.title,
					viewedAt: next.updatedAt
				});
				added += 1;
			}
			return {
				progress,
				titles,
				recents: recents.slice(0, 24)
			};
		});
		return added;
	},
	clearHistory: () => set({ recents: [] }),
	clearProgress: () => set({
		progress: {},
		recents: []
	}),
	hydrateRemote: ({ ownerId, favorites, titles, progress, recents }) => set((state) => {
		const merged = { ...state.progress };
		for (const item of progress) {
			const path = normalizeEpisodePath(item.episodePath) || item.episodePath;
			const prev = merged[progressKey(path, item.lang)] ?? merged[path];
			if (!prev || item.updatedAt >= prev.updatedAt) writeProgress(merged, mergeIncoming(prev, {
				...item,
				episodePath: path
			}));
		}
		const recentMerged = recents?.length ? [...recents, ...state.recents.filter((r) => !recents.some((x) => x.slug === r.slug))].slice(0, 24) : state.recents;
		return {
			ownerId,
			favorites,
			titles: {
				...state.titles,
				...titles
			},
			progress: merged,
			recents: recentMerged
		};
	}),
	setOwner: (ownerId) => set({ ownerId })
}), {
	name: "nori-library",
	version: 5,
	skipHydration: true,
	partialize: (state) => ({
		ownerId: state.ownerId,
		favorites: state.favorites,
		recents: state.recents,
		titles: state.titles,
		progress: state.progress
	}),
	merge: (persisted, current) => ({
		...current,
		...persisted,
		covers: current.covers
	}),
	migrate: (persisted) => {
		const p = persisted ?? {};
		const recents = Array.isArray(p.recents) ? p.recents : [];
		const titles = { ...p.titles && typeof p.titles === "object" ? p.titles : {} };
		for (const r of recents) if (r?.slug && r.title && !titles[r.slug]) titles[r.slug] = r.title;
		const progress = p.progress && typeof p.progress === "object" ? { ...p.progress } : {};
		for (const [key, item] of Object.entries(progress)) {
			if (!item) continue;
			const path = normalizeEpisodePath(item.episodePath) || item.episodePath;
			const completed = item.completed || item.durationSec >= 20 && item.positionSec >= item.durationSec * .9;
			progress[key] = {
				...item,
				episodePath: path,
				completed
			};
		}
		return {
			ownerId: p.ownerId ?? null,
			favorites: Array.isArray(p.favorites) ? p.favorites : [],
			recents,
			titles,
			progress
		};
	}
}));
//#endregion
//#region node_modules/.nitro/vite/services/ssr/assets/use-current-user-D-a3c__c.js
function looksFakeName(value) {
	const name = (value || "").trim().toLowerCase();
	return !name || name === "user" || name === "dev user" || name === "guest";
}
function looksFakeEmail(value) {
	const email = (value || "").trim().toLowerCase();
	return !email || email.endsWith("@example.com") || email.endsWith(".local");
}
function accountLabel(user) {
	if (!looksFakeName(user.displayName)) return user.displayName.trim();
	if (!looksFakeEmail(user.primaryEmail)) return user.primaryEmail;
	return "Konto";
}
function accountEmail(user) {
	if (looksFakeEmail(user.primaryEmail)) return null;
	return user.primaryEmail;
}
function isPlaceholderAccount(user) {
	if (!user) return true;
	return looksFakeName(user.displayName) && looksFakeEmail(user.primaryEmail);
}
/**
* Stable fallback user, used ONLY when auth is disabled
* (`VITE_AUTH_ENABLED=false`, the shipped default). With auth on, the sandbox
* live preview does real sign-in via the baked preview client. Its id is
* `"dev-user"` — the SAME id `verify.server.ts` returns server-side — so per-user
* rows written in that mode belong to one consistent owner.
*/
var DEV_USER = {
	id: "dev-user",
	displayName: "Dev User",
	primaryEmail: "dev@example.com",
	profileImageUrl: null,
	isDevFallback: true
};
/**
* Current user + loading state. Same behavior in live preview and when deployed:
*   - Auth enabled -> the real signed-in user; `user` is `null` while
*                            the session resolves (`isPending: true`) and when
*                            signed out (`isPending: false`). Session comes from
*                            Better Auth `useSession()` → `/api/auth/get-session`
*                            (cookie when deployed; bearer in live preview).
*   - Auth disabled (`VITE_AUTH_ENABLED=false`) -> `DEV_USER`, never pending.
*
* Protect a route by waiting out `isPending` before acting on `user` —
* redirecting on `user: null` alone bounces signed-in visitors to sign-in on
* every hard reload:
*
*   import { RedirectToSignIn } from "@/lib/auth/gates";
*   const { user, isPending } = useCurrentUserState();
*   if (isPending) return null;              // still resolving — don't redirect yet
*   if (!user) return <RedirectToSignIn />;  // definitely signed out
*
* `authEnabled` is a module-level constant fixed at load, so the guarded hook
* call keeps a stable hook order across every render of a given component.
*/
function useCurrentUserState() {
	return {
		user: DEV_USER,
		isPending: false
	};
}
//#endregion
//#region node_modules/.nitro/vite/services/ssr/assets/search-params-BAdF11kn.js
function asSearchString(value) {
	if (typeof value === "number" && Number.isFinite(value)) return String(value);
	if (typeof value !== "string") return void 0;
	return value.replace(/^"+|"+$/g, "").trim() || void 0;
}
//#endregion
//#region node_modules/.nitro/vite/services/ssr/assets/router-DDQw7P_P.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function AppErrorComponent({ error }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("main", {
		className: "flex min-h-screen flex-col items-center justify-center gap-3 px-6 text-center bg-zinc-50 text-zinc-900 dark:bg-zinc-950 dark:text-zinc-50",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
				className: "text-red-500",
				"aria-hidden": "true",
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(TriangleAlert, {
					className: "size-10",
					strokeWidth: 2
				})
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h1", {
				className: "text-lg font-semibold",
				children: "Something went wrong"
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "max-w-md text-sm break-words text-zinc-500 dark:text-zinc-400",
				children: error.message || "An unexpected error occurred. Try reloading the page."
			})
		]
	});
}
function posterVtIdent(slug) {
	const clean = slug.replace(/[^a-zA-Z0-9_-]+/g, "");
	return clean ? `nori-p-${clean}` : "";
}
function markPosterTransition(slug, el) {
	if (typeof document === "undefined") return;
	const ident = posterVtIdent(slug);
	for (const node of document.querySelectorAll("[data-nori-poster]")) if (node instanceof HTMLElement) node.style.viewTransitionName = "";
	const target = el ?? document.querySelector(`[data-nori-poster="${CSS.escape(slug)}"]`);
	if (target instanceof HTMLElement && ident) target.style.viewTransitionName = ident;
}
function viewTransitionTypes(info) {
	if (typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return false;
	if (!info.pathChanged) return false;
	const from = info.fromLocation?.pathname ?? "";
	const to = info.toLocation.pathname;
	const isSeries = (path) => /^\/anime\/[^/]+$/.test(path);
	const isWatch = (path) => path.startsWith("/watch/");
	if (isWatch(to) || isWatch(from)) return ["nori-nav", "nori-watch"];
	if (isSeries(to) && !isSeries(from)) return ["nori-nav", "nori-open"];
	if (isSeries(from) && !isSeries(to)) return ["nori-nav", "nori-back"];
	return ["nori-nav"];
}
/**
* App-wide client provider mounted once near the root (in `src/routes/__root.tsx`):
*
*   <AuthProvider><Outlet /></AuthProvider>
*
* Better Auth's React client (`@/lib/auth/client`) needs NO context provider —
* its `useSession()` works standalone — so this is a passthrough today. It's
* kept as the single, stable mount point for any future client-side providers
* (e.g. a toast or theme provider) without churning the root shell.
*/
function AuthProvider({ children }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_jsx_runtime.Fragment, { children });
}
function isGrokEmbedderOrigin(origin) {
	try {
		const url = new URL(origin);
		if (url.protocol !== "https:" && url.protocol !== "http:") return false;
		const host = url.hostname.toLowerCase();
		if (host === "grok.com" || host.endsWith(".grok.com")) return true;
		if (host === "localhost" || host === "127.0.0.1" || host === "[::1]") return true;
		return false;
	} catch {
		return false;
	}
}
function isSandboxPreviewGuestHost(hostname) {
	const host = hostname.toLowerCase();
	return host === "grok-sandbox.com" || host.endsWith(".grok-sandbox.com");
}
function isRemintPreviewPair(guestHost, parentHost) {
	const guest = guestHost.toLowerCase();
	const parent = parentHost.toLowerCase();
	const i = guest.indexOf(".preview.");
	if (i <= 0) return false;
	const label = guest.slice(0, i);
	const rest = guest.slice(i + 9);
	if (label.includes(".") || !rest.includes(".")) return false;
	return parent === rest || parent === `grok.${rest}`;
}
function resolveParentEmbedderOrigin(parentIsSelf, referrer, ancestorOrigin, guestHostname = "") {
	if (parentIsSelf) return null;
	for (const candidate of [referrer, ancestorOrigin ?? ""].filter(Boolean)) try {
		const url = new URL(candidate.includes("://") ? candidate : `https://${candidate}`);
		if (url.protocol !== "https:" && url.protocol !== "http:") continue;
		if (isGrokEmbedderOrigin(url.origin)) return url.origin;
		if (isSandboxPreviewGuestHost(guestHostname) || isRemintPreviewPair(guestHostname, url.hostname)) return url.origin;
	} catch {}
	return null;
}
/**
* Guest side of the grok-web ↔ sandbox preview postMessage bridge.
*
* Activates only when this page is framed by an allowlisted Grok embedder.
* Top-level runs (download/export, local `npm run dev`, deployed sites) noop.
*/
var PREVIEW_BRIDGE_CHANNEL = "grok-preview-bridge";
var EnvelopeSchema = object({
	channel: literal(PREVIEW_BRIDGE_CHANNEL),
	version: number().int().positive(),
	type: string().min(1)
});
var HelloSchema = EnvelopeSchema.extend({ type: literal("hello") });
var NavigateSchema = EnvelopeSchema.extend({
	type: literal("navigate"),
	path: string().min(1)
});
var HistorySchema = EnvelopeSchema.extend({
	type: literal("history"),
	delta: union([literal(-1), literal(1)])
});
function isSafeBridgePath(path) {
	if (!path.startsWith("/") || path.startsWith("//") || path.includes("\\")) return false;
	try {
		return new URL(path, "https://preview.invalid").origin === "https://preview.invalid";
	} catch {
		return false;
	}
}
/**
* Install host↔guest messaging. Returns a dispose function.
* Noops (returns a no-op dispose) when not embedded under a Grok parent.
*/
function installPreviewHostBridge(options = {}) {
	if (typeof window === "undefined") return () => {};
	const ancestorOrigin = typeof location.ancestorOrigins !== "undefined" && location.ancestorOrigins.length > 0 ? location.ancestorOrigins[0] : null;
	const parentOrigin = resolveParentEmbedderOrigin(window.parent === window, document.referrer, ancestorOrigin, window.location.hostname);
	if (parentOrigin === null) return () => {};
	const ROOT_STATE_KEY = "__grokPreviewBridgeRoot";
	const originalPushState = window.history.pushState.bind(window.history);
	const originalReplaceState = window.history.replaceState.bind(window.history);
	const isAtHistoryRoot = () => {
		const state = window.history.state;
		return Boolean(state && typeof state === "object" && state[ROOT_STATE_KEY] === true);
	};
	try {
		const current = window.history.state;
		if (!(current !== null && typeof current === "object" && Object.prototype.hasOwnProperty.call(current, ROOT_STATE_KEY))) {
			const isRoot = window.history.length <= 1;
			originalReplaceState(current && typeof current === "object" ? {
				...current,
				[ROOT_STATE_KEY]: isRoot
			} : { [ROOT_STATE_KEY]: isRoot }, "", window.location.href);
		}
	} catch {}
	const post = (message) => {
		window.parent.postMessage(message, parentOrigin);
	};
	const reportLocation = () => {
		post({
			channel: PREVIEW_BRIDGE_CHANNEL,
			version: 1,
			type: "location",
			path: window.location.pathname || "/",
			search: window.location.search,
			hash: window.location.hash
		});
	};
	const reportRoutes = () => {
		const paths = options.getRoutePaths?.() ?? [];
		post({
			channel: PREVIEW_BRIDGE_CHANNEL,
			version: 1,
			type: "routes",
			paths
		});
	};
	const defaultNavigate = (path) => {
		if (!isSafeBridgePath(path)) return;
		try {
			const url = new URL(path, window.location.origin);
			if (url.origin !== window.location.origin) return;
			const next = `${url.pathname}${url.search}${url.hash}`;
			window.history.pushState(window.history.state, "", next);
			window.dispatchEvent(new PopStateEvent("popstate", { state: window.history.state }));
		} catch {}
	};
	const navigate = (path) => {
		if (!isSafeBridgePath(path)) return;
		if (options.navigate) {
			options.navigate(path);
			return;
		}
		defaultNavigate(path);
	};
	const announce = () => {
		reportLocation();
		reportRoutes();
		post({
			channel: PREVIEW_BRIDGE_CHANNEL,
			version: 1,
			type: "ready"
		});
	};
	const onMessage = (event) => {
		if (event.source !== window.parent) return;
		if (event.origin !== parentOrigin) return;
		const envelope = EnvelopeSchema.safeParse(event.data);
		if (!envelope.success || envelope.data.version !== 1) return;
		if (envelope.data.type === "hello") {
			if (!HelloSchema.safeParse(event.data).success) return;
			announce();
			return;
		}
		if (envelope.data.type === "navigate") {
			const parsed = NavigateSchema.safeParse(event.data);
			if (!parsed.success) return;
			navigate(parsed.data.path);
			queueMicrotask(reportLocation);
			return;
		}
		if (envelope.data.type === "history") {
			const parsed = HistorySchema.safeParse(event.data);
			if (!parsed.success) return;
			if (parsed.data.delta === -1 && isAtHistoryRoot()) return;
			window.history.go(parsed.data.delta);
		}
	};
	const onPopState = () => {
		reportLocation();
	};
	const onHashChange = () => {
		reportLocation();
	};
	window.history.pushState = (data, unused, url) => {
		const next = data && typeof data === "object" ? {
			...data,
			[ROOT_STATE_KEY]: false
		} : data;
		originalPushState(next, unused, url);
		reportLocation();
	};
	window.history.replaceState = (data, unused, url) => {
		const next = isAtHistoryRoot() ? {
			...data && typeof data === "object" ? data : {},
			[ROOT_STATE_KEY]: true
		} : data;
		originalReplaceState(next, unused, url);
		reportLocation();
	};
	window.addEventListener("message", onMessage);
	window.addEventListener("popstate", onPopState);
	window.addEventListener("hashchange", onHashChange);
	announce();
	return () => {
		window.removeEventListener("message", onMessage);
		window.removeEventListener("popstate", onPopState);
		window.removeEventListener("hashchange", onHashChange);
		window.history.pushState = originalPushState;
		window.history.replaceState = originalReplaceState;
	};
}
/** Collect static path patterns from a TanStack route tree (best-effort). */
function collectRoutePathsFromTree(routeTree) {
	const paths = /* @__PURE__ */ new Set();
	const walk = (node) => {
		if (!node || typeof node !== "object") return;
		const record = node;
		const full = typeof record.fullPath === "string" ? record.fullPath : typeof record.path === "string" ? record.path : null;
		if (full !== null && full !== "") paths.add(full.startsWith("/") ? full : `/${full}`);
		else if (full === "") paths.add("/");
		const children = record.children;
		if (Array.isArray(children)) for (const child of children) walk(child);
		else if (children && typeof children === "object") for (const child of Object.values(children)) walk(child);
	};
	walk(routeTree);
	return [...paths];
}
/**
* Mount once in `__root.tsx` so the Grok preview chrome can drive navigation
* (and later receive registered routes). Noops when the app is not embedded.
*/
function PreviewHostBridge() {
	const router = useRouter();
	(0, import_react.useEffect)(() => {
		return installPreviewHostBridge({
			navigate: (path) => {
				router.history.push(path);
			},
			getRoutePaths: () => collectRoutePathsFromTree(router.routeTree)
		});
	}, [router]);
	return null;
}
var listeners$1 = /* @__PURE__ */ new Set();
var state = {
	progress: 22,
	label: "Nori wird geladen",
	done: false
};
function emit() {
	for (const l of listeners$1) l();
}
function set(partial) {
	state = {
		...state,
		...partial
	};
	emit();
}
function getBoot() {
	return state;
}
function subscribeBoot(fn) {
	listeners$1.add(fn);
	return () => listeners$1.delete(fn);
}
function markBootCatalog() {
	if (state.done) return;
	set({
		progress: Math.max(state.progress, 72),
		label: "Katalog"
	});
	maybeFinish();
}
function markBootAccount() {
	if (state.done) return;
	set({
		progress: Math.max(state.progress, 88),
		label: "Konto"
	});
	maybeFinish();
}
function finish() {
	if (state.done) return;
	set({
		progress: 100,
		label: "Bereit",
		done: true
	});
}
function maybeFinish() {
	if (state.progress >= 70) window.setTimeout(finish, 280);
}
function startBoot() {
	if (typeof window === "undefined" || state.done) return;
	window.setTimeout(() => {
		if (!state.done) set({
			progress: Math.max(state.progress, 48),
			label: "Katalog"
		});
	}, 90);
	window.setTimeout(() => {
		if (!state.done) finish();
	}, 900);
}
var createSsrRpc = (functionId) => {
	const url = "/_serverFn/" + functionId;
	const serverFnMeta = { id: functionId };
	const fn = async (...args) => {
		return (await getServerFnById(functionId, { origin: "server" }))(...args);
	};
	return Object.assign(fn, {
		url,
		serverFnMeta,
		[TSS_SERVER_FUNCTION]: true
	});
};
var progressSchema = object({
	slug: string(),
	title: string().optional().default(""),
	season: string().optional().default(""),
	episode: number().optional().default(0),
	episodePath: string().optional().default(""),
	germanTitle: string().optional().default(""),
	englishTitle: string().optional().default(""),
	positionSec: number().optional().default(0),
	durationSec: number().optional().default(0),
	updatedAt: number().optional().default(0),
	lang: string().optional()
});
var snapshotSchema = object({
	favorites: array(object({
		slug: string().min(1).max(180),
		title: string().max(220)
	})).max(400),
	progress: array(progressSchema).max(400),
	recents: array(object({
		slug: string(),
		title: string().optional().default(""),
		viewedAt: number().optional().default(0)
	})).max(40),
	titles: record(string(), string()).optional()
});
var pullAccountLibrary = createServerFn({ method: "POST" }).middleware([authMiddleware]).handler(createSsrRpc("26be109a86abb080397abe35b4a110fd21047f8d4f378a83e7c2ebe5ff270b74"));
var pushAccountLibrary = createServerFn({ method: "POST" }).middleware([authMiddleware]).validator(snapshotSchema).handler(createSsrRpc("9b362db42ffdd0e3ea4af055f9345246a720cdd1b8891dcbac410615d956775e"));
function authFail(message) {
	return /unauthor|401|forbidden|not authenticated|session/i.test(message);
}
function driveMessage(result) {
	if (result.ok && result.action === "load") {
		const n = result.library?.favorites.length ?? 0;
		const p = result.library?.progress.length ?? 0;
		if (!result.fileFound && n === 0 && p === 0) return "Automatischer Sync aktiv. Lokal bleibt die Quelle, bis die Cloud Daten hat.";
		return `Aktuell: ${n} gemerkt, ${p} Fortschritte — wird automatisch abgeglichen.`;
	}
	if (result.ok) return "Automatisch synchronisiert. Andere Geräte holen das in wenigen Sekunden.";
	if (result.errorKind === "login" || authFail(result.errorMessage ?? "")) return "Bitte mit Google oder E-Mail anmelden — dann synct Nori von allein.";
	if (result.detail) return `Sync fehlgeschlagen: ${result.detail.slice(0, 160)}`;
	return "Cloud gerade nicht erreichbar. Lokal ist alles gespeichert.";
}
function snapshot() {
	const s = useLibrary.getState();
	const titles = {};
	for (const [k, v] of Object.entries(s.titles)) if (k && typeof v === "string") titles[k] = v.slice(0, 220);
	return {
		favorites: s.favorites.filter((slug) => typeof slug === "string" && slug).map((slug) => ({
			slug,
			title: (titles[slug] || slug).slice(0, 220)
		})),
		progress: Object.values(s.progress).filter((p) => p?.slug && p?.episodePath).map((p) => ({
			slug: p.slug,
			title: p.title || "",
			season: p.season || "",
			episode: Number(p.episode) || 0,
			episodePath: p.episodePath,
			germanTitle: p.germanTitle || "",
			englishTitle: p.englishTitle || "",
			positionSec: Number(p.positionSec) || 0,
			durationSec: Number(p.durationSec) || 0,
			updatedAt: Number(p.updatedAt) || Date.now(),
			completed: Boolean(p.completed) || Number(p.durationSec) >= 20 && Number(p.positionSec) >= Number(p.durationSec) * .9,
			lang: p.lang
		})),
		recents: s.recents.filter((r) => r?.slug).map((r) => ({
			slug: r.slug,
			title: r.title || r.slug,
			viewedAt: Number(r.viewedAt) || Date.now()
		})),
		titles
	};
}
var saveTimer = 0;
var saveInFlight = false;
var applyingRemote = false;
var lastPushAt = 0;
var subscribed = false;
var lastDrive = null;
var listeners = /* @__PURE__ */ new Set();
function setLast(result) {
	lastDrive = result;
	for (const l of listeners) l();
}
function failFrom(e) {
	const message = e instanceof Error ? e.message : String(e);
	return {
		ok: false,
		action: "save",
		errorKind: authFail(message) ? "login" : "error",
		errorMessage: message,
		detail: message
	};
}
function scheduleDriveSave() {
	window.clearTimeout(saveTimer);
	saveTimer = window.setTimeout(() => {
		flushDriveSave();
	}, 900);
}
function applyPayload(library) {
	applyingRemote = true;
	try {
		const local = useLibrary.getState();
		const titles = { ...library.titles };
		for (const f of library.favorites) titles[f.slug] = f.title;
		for (const p of library.progress) titles[p.slug] = p.title;
		const replaceFavs = lastPushAt > 0 && library.updatedAt > lastPushAt;
		local.hydrateRemote({
			ownerId: "account",
			favorites: replaceFavs ? Array.from(new Set(library.favorites.map((f) => f.slug))) : Array.from(/* @__PURE__ */ new Set([...library.favorites.map((f) => f.slug), ...local.favorites])),
			titles: {
				...local.titles,
				...titles
			},
			progress: library.progress,
			recents: library.recents
		});
	} finally {
		window.setTimeout(() => {
			applyingRemote = false;
		}, 50);
	}
}
function ensureAutoPush() {
	if (subscribed) return;
	subscribed = true;
	useLibrary.subscribe((state, prev) => {
		if (applyingRemote) return;
		if (state.favorites === prev.favorites && state.progress === prev.progress && state.recents === prev.recents) return;
		scheduleDriveSave();
	});
}
async function pullCloud() {
	try {
		const account = await pullAccountLibrary();
		if (!account.ok) return failFrom(new Error(account.error));
		if (account.library.updatedAt > 0) applyPayload(account.library);
		const result = {
			ok: true,
			action: "load",
			fileFound: account.library.updatedAt > 0,
			library: account.library
		};
		setLast(result);
		markBootAccount();
		return result;
	} catch (e) {
		const result = failFrom(e);
		result.action = "load";
		setLast(result);
		markBootAccount();
		return result;
	}
}
async function flushDriveSave() {
	if (saveInFlight || applyingRemote) return lastDrive ?? {
		ok: false,
		errorKind: "error",
		errorMessage: "busy"
	};
	saveInFlight = true;
	try {
		const pushed = await pushAccountLibrary({ data: snapshot() });
		if (!pushed.ok) {
			const result = failFrom(new Error(pushed.error));
			setLast(result);
			return result;
		}
		lastPushAt = pushed.library.updatedAt;
		const result = {
			ok: true,
			action: "save",
			fileFound: true,
			library: pushed.library
		};
		setLast(result);
		return result;
	} catch (e) {
		const result = failFrom(e);
		setLast(result);
		return result;
	} finally {
		saveInFlight = false;
	}
}
function useFavoriteToggle() {
	const toggle = useLibrary((s) => s.toggleFavorite);
	return (slug, title) => {
		toggle(slug, title);
	};
}
function recordProgress(item, _signedIn) {
	const wasComplete = isEpisodeComplete(progressForPath(useLibrary.getState().progress, item.episodePath, item.lang));
	useLibrary.getState().upsertProgress(item);
	const next = progressForPath(useLibrary.getState().progress, item.episodePath, item.lang);
	import("./trakt-wm9BT4pC.mjs").then((n) => n.c).then((n) => n.c).then((trakt) => {
		if (!trakt.isTraktConnected()) return;
		if (isEpisodeComplete(next) && !wasComplete && next) {
			trakt.pushWatchedEpisode(next).catch(() => void 0);
			trakt.scrobbleProgress(next, "stop").catch(() => void 0);
		} else if (!isEpisodeComplete(next) && (item.positionSec || 0) > 15) trakt.scrobbleProgress(item, "pause").catch(() => void 0);
	}).catch(() => void 0);
}
function useLibrarySync(enabled = true) {
	const { user, isPending } = useCurrentUserState();
	const real = Boolean(user && !isPlaceholderAccount(user));
	(0, import_react.useEffect)(() => {
		ensureAutoPush();
	}, []);
	(0, import_react.useEffect)(() => {
		if (!enabled || isPending) {
			if (!isPending && !real) markBootAccount();
			return;
		}
		if (!real) {
			markBootAccount();
			return;
		}
		const start = window.setTimeout(() => {
			pullCloud().then((loaded) => {
				if (loaded.ok) flushDriveSave();
			});
		}, 2500);
		const tick = () => {
			if (document.visibilityState !== "visible" || saveInFlight) return;
			pullCloud();
		};
		const interval = window.setInterval(tick, 3e4);
		window.addEventListener("focus", tick);
		document.addEventListener("visibilitychange", tick);
		return () => {
			window.clearTimeout(start);
			window.clearInterval(interval);
			window.removeEventListener("focus", tick);
			document.removeEventListener("visibilitychange", tick);
		};
	}, [
		enabled,
		isPending,
		real,
		user?.id
	]);
}
function useDriveStatus() {
	const { user, isPending } = useCurrentUserState();
	const real = Boolean(user && !isPlaceholderAccount(user));
	const [status, setStatus] = (0, import_react.useState)(() => lastDrive ? driveMessage(lastDrive) : "Lokal gespeichert. Angemeldet synct Nori von allein.");
	const [syncing, setSyncing] = (0, import_react.useState)(false);
	(0, import_react.useEffect)(() => {
		const onChange = () => {
			if (lastDrive) setStatus(driveMessage(lastDrive));
		};
		listeners.add(onChange);
		onChange();
		return () => {
			listeners.delete(onChange);
		};
	}, []);
	async function syncNow() {
		if (isPending) {
			setStatus("Anmeldung wird geprüft…");
			return;
		}
		if (!real) {
			setStatus("Bitte zuerst mit Google oder E-Mail anmelden.");
			return;
		}
		setSyncing(true);
		try {
			const loaded = await pullCloud();
			if (!loaded.ok && loaded.errorKind === "login") {
				setStatus(driveMessage(loaded));
				return;
			}
			const saved = await flushDriveSave();
			setStatus(driveMessage(saved));
		} catch (e) {
			setStatus(driveMessage(failFrom(e)));
		} finally {
			setSyncing(false);
		}
	}
	return {
		status,
		syncing,
		syncNow,
		last: lastDrive
	};
}
function useBoot() {
	return (0, import_react.useSyncExternalStore)(subscribeBoot, getBoot, getBoot);
}
var THRESHOLD = 8;
function KindSwitch({ className }) {
	const provider = useProvider((s) => s.provider);
	const setProvider = useProvider((s) => s.setProvider);
	const qc = useQueryClient();
	const serien = provider === "serienstream";
	const trackRef = (0, import_react.useRef)(null);
	const gesture = (0, import_react.useRef)({
		armed: false,
		dragging: false,
		startX: 0
	});
	const [dragPct, setDragPct] = (0, import_react.useState)(null);
	function pick(next) {
		if (next === provider) return;
		setProvider(next);
		window.setTimeout(() => {
			qc.invalidateQueries({ queryKey: ["catalog"] });
			qc.invalidateQueries({ queryKey: ["calendar"] });
			qc.invalidateQueries({ queryKey: ["series"] });
		}, 180);
	}
	function pctFromX(clientX) {
		const el = trackRef.current;
		if (!el) return serien ? 100 : 0;
		const r = el.getBoundingClientRect();
		const travel = Math.max(1, r.width / 2);
		return Math.min(100, Math.max(0, (clientX - r.left - 2) / travel * 100));
	}
	function providerAt(clientX) {
		const el = trackRef.current;
		if (!el) return provider;
		const r = el.getBoundingClientRect();
		return clientX < r.left + r.width / 2 ? "aniworld" : "serienstream";
	}
	const dragging = dragPct != null;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
		ref: trackRef,
		className: cn("nori-kind", className),
		"data-kind": serien ? "serien" : "anime",
		"data-dragging": dragging ? "true" : void 0,
		role: "radiogroup",
		"aria-label": "Anime oder Serien",
		style: dragging ? { ["--nori-x"]: `${dragPct}%` } : void 0,
		onPointerDown: (e) => {
			e.currentTarget.setPointerCapture(e.pointerId);
			gesture.current = {
				armed: true,
				dragging: false,
				startX: e.clientX
			};
		},
		onPointerMove: (e) => {
			const g = gesture.current;
			if (!g.armed) return;
			if (!g.dragging && Math.abs(e.clientX - g.startX) < THRESHOLD) return;
			g.dragging = true;
			setDragPct(pctFromX(e.clientX));
		},
		onPointerUp: (e) => {
			const next = providerAt(e.clientX);
			gesture.current = {
				armed: false,
				dragging: false,
				startX: 0
			};
			setDragPct(null);
			pick(next);
		},
		onPointerCancel: () => {
			gesture.current = {
				armed: false,
				dragging: false,
				startX: 0
			};
			setDragPct(null);
		},
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
				"aria-hidden": true,
				className: "nori-kind-thumb",
				style: dragging ? { transform: `translateX(${dragPct}%)` } : void 0
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
				type: "button",
				role: "radio",
				"aria-checked": !serien,
				tabIndex: 0,
				onClick: (e) => {
					e.stopPropagation();
					pick("aniworld");
				},
				className: cn("nori-kind-label", !serien && "is-on"),
				children: "Anime"
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
				type: "button",
				role: "radio",
				"aria-checked": serien,
				tabIndex: 0,
				onClick: (e) => {
					e.stopPropagation();
					pick("serienstream");
				},
				className: cn("nori-kind-label", serien && "is-on"),
				children: "Serien"
			})
		]
	});
}
function isCinematic(pathname) {
	return pathname === "/" || /^\/anime\/[^/]+$/.test(pathname);
}
function AppShell({ children, sync = true }) {
	const pathname = useRouterState({ select: (s) => s.location.pathname });
	useLibrarySync(sync);
	const cinematic = isCinematic(pathname);
	const [scrolled, setScrolled] = (0, import_react.useState)(false);
	(0, import_react.useEffect)(() => {
		const onScroll = () => setScrolled(window.scrollY > 18);
		onScroll();
		window.addEventListener("scroll", onScroll, { passive: true });
		return () => window.removeEventListener("scroll", onScroll);
	}, [pathname]);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
		className: "min-h-dvh bg-bg text-fg",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("header", {
				className: cn("nori-header", cinematic && "is-hero", cinematic && scrolled && "is-scrolled"),
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "mx-auto flex h-16 max-w-7xl items-center justify-between gap-3 px-4",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "flex min-w-0 items-center gap-6",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Link, {
							to: "/",
							className: "flex items-center gap-2.5",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
								className: "nori-mark",
								"aria-hidden": true,
								children: "N"
							}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
								className: "font-display text-xl tracking-display",
								children: "Nori"
							})]
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("nav", {
							className: "nori-desk-nav items-center gap-1",
							children: [
								/* @__PURE__ */ (0, import_jsx_runtime.jsx)(NavLink, {
									to: "/",
									active: pathname === "/",
									children: "Start"
								}),
								/* @__PURE__ */ (0, import_jsx_runtime.jsx)(NavLink, {
									to: "/anime",
									active: pathname.startsWith("/anime") && !pathname.includes("/watch"),
									children: "Entdecken"
								}),
								/* @__PURE__ */ (0, import_jsx_runtime.jsx)(NavLink, {
									to: "/kalender",
									active: pathname.startsWith("/kalender"),
									children: "Kalender"
								}),
								/* @__PURE__ */ (0, import_jsx_runtime.jsx)(NavLink, {
									to: "/merkliste",
									active: pathname.startsWith("/merkliste"),
									children: "Merkliste"
								}),
								/* @__PURE__ */ (0, import_jsx_runtime.jsx)(NavLink, {
									to: "/verlauf",
									active: pathname.startsWith("/verlauf"),
									children: "Verlauf"
								})
							]
						})]
					}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "flex items-center gap-2",
						children: [
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)(HeaderSearch, {}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)(KindSwitch, { className: "hidden sm:grid" }),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Link, {
								to: "/einstellungen",
								className: cn("grid size-11 place-items-center rounded-md transition-colors duration-150", pathname.startsWith("/einstellungen") ? "text-fg" : "text-muted hover:text-fg"),
								"aria-label": "Einstellungen",
								children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Settings2, {
									className: "size-5",
									strokeWidth: 1.75
								})
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)(AuthSlot, {})
						]
					})]
				})
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "pb-[calc(5.5rem+env(safe-area-inset-bottom))] md:pb-0",
				children
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)(MobileDock, { pathname })
		]
	});
}
function HeaderSearch() {
	const navigate = useNavigate();
	const [q, setQ] = (0, import_react.useState)("");
	function submit(e) {
		e.preventDefault();
		const query = q.trim();
		navigate({
			to: "/search",
			search: query ? { q: query } : {}
		});
	}
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("form", {
		onSubmit: submit,
		className: "hidden md:block",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
			className: "flex h-10 w-44 items-center gap-2 rounded-full bg-white/6 px-3 shadow-[inset_0_0_0_1px_rgb(255_255_255/0.08)] transition-[width,background-color] duration-200 ease-out focus-within:w-72 focus-within:bg-white/10 lg:w-56 lg:focus-within:w-80",
			children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Search, {
				className: "size-4 text-muted",
				strokeWidth: 1.75
			}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
				value: q,
				onChange: (e) => setQ(e.target.value),
				placeholder: "Suchen",
				className: "h-full w-full bg-transparent text-sm outline-none placeholder:text-subtle",
				autoComplete: "off",
				suppressHydrationWarning: true
			})]
		})
	});
}
function NavLink({ to, active, children }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Link, {
		to,
		preload: "intent",
		className: cn("relative inline-flex h-11 items-center rounded-full px-3 text-sm transition-[color,background-color] duration-150", active ? "bg-white/8 text-fg" : "text-muted hover:text-fg"),
		children
	});
}
function MobileDock({ pathname }) {
	const merkeCount = useLibrary((s) => s.favorites.length);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("nav", {
		className: "nori-dock fixed inset-x-0 bottom-0 z-30 border-t border-fg/10 bg-bg/90 backdrop-blur-xl",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
			className: "mx-auto grid h-16 max-w-lg grid-cols-5 items-center px-1",
			children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(DockLink, {
					to: "/",
					active: pathname === "/",
					label: "Start",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(House, {
						className: "size-5",
						strokeWidth: 1.75
					})
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(DockLink, {
					to: "/anime",
					active: pathname.startsWith("/anime") || pathname.startsWith("/search"),
					label: "Entdecken",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(LayoutGrid, {
						className: "size-5",
						strokeWidth: 1.75
					})
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(DockLink, {
					to: "/kalender",
					active: pathname.startsWith("/kalender"),
					label: "Kalender",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(CalendarDays, {
						className: "size-5",
						strokeWidth: 1.75
					})
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(DockLink, {
					to: "/merkliste",
					active: pathname.startsWith("/merkliste"),
					label: "Merkliste",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
						className: "relative",
						children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Heart, {
							className: cn("size-5", merkeCount > 0 && "fill-current"),
							strokeWidth: 1.75
						})
					})
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(DockLink, {
					to: "/konto",
					active: pathname.startsWith("/konto") || pathname.startsWith("/login"),
					label: "Profil",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(UserRound, {
						className: "size-5",
						strokeWidth: 1.75
					})
				})
			]
		})
	});
}
function DockLink({ to, active, label, children }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Link, {
		to,
		preload: "intent",
		className: cn("flex h-11 flex-col items-center justify-center gap-0.5 rounded-md text-[11px] transition-colors duration-150", active ? "text-fg" : "text-muted"),
		children: [children, label]
	});
}
function BootScreen() {
	const boot = useBoot();
	const [hide, setHide] = (0, import_react.useState)(boot.done);
	(0, import_react.useEffect)(() => {
		startBoot();
	}, []);
	(0, import_react.useEffect)(() => {
		if (!boot.done || hide) return;
		const t = window.setTimeout(() => setHide(true), 280);
		return () => window.clearTimeout(t);
	}, [boot.done, hide]);
	if (hide) return null;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
		className: cn("fixed inset-0 z-50 grid place-items-center bg-bg transition-opacity duration-300 ease-out", boot.done ? "pointer-events-none opacity-0" : "opacity-100"),
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
			className: "w-56 px-4",
			children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "font-display text-4xl tracking-display",
					children: "Nori"
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
					className: "mt-6 h-1 overflow-hidden rounded-full bg-elevated",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "h-full origin-left rounded-full bg-accent transition-transform duration-200 ease-out",
						style: { transform: `scaleX(${Math.min(1, boot.progress / 100)})` }
					})
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "mt-3 text-xs font-medium uppercase tracking-widest text-muted",
					children: boot.label
				})
			]
		})
	});
}
function AuthSlot() {
	const { user, isPending } = useCurrentUserState();
	const [ready, setReady] = (0, import_react.useState)(false);
	(0, import_react.useEffect)(() => setReady(true), []);
	if (!ready || isPending) return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
		className: "size-8 animate-pulse rounded-full bg-elevated",
		"aria-hidden": true
	});
	if (user && !isPlaceholderAccount(user)) {
		const label = accountLabel(user);
		return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Link, {
			to: "/konto",
			className: "inline-flex h-11 items-center gap-2 rounded-md px-1 text-sm text-fg",
			"aria-label": "Konto",
			children: [user.profileImageUrl ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("img", {
				src: user.profileImageUrl,
				alt: "",
				className: "size-8 rounded-full object-cover"
			}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
				className: "grid size-8 place-items-center rounded-full bg-elevated text-xs font-medium",
				children: label.slice(0, 1).toUpperCase()
			}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
				className: "hidden max-w-[9rem] truncate sm:inline",
				children: label
			})]
		});
	}
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Link, {
		to: "/login",
		className: "inline-flex h-11 items-center rounded-md px-3 text-sm text-muted transition-colors duration-150 hover:text-fg",
		children: "Anmelden"
	});
}
var EMPTY = {
	items: [],
	source: "cache",
	fetchedAt: 0
};
function keyFor(provider = "aniworld") {
	return provider === "serienstream" ? "nori-catalog-ss-v2" : "nori-catalog-v1";
}
function readCachedCatalog(provider = "aniworld") {
	if (typeof window === "undefined") return EMPTY;
	try {
		const key = keyFor(provider);
		const raw = window.sessionStorage.getItem(key) || window.localStorage.getItem(key);
		if (!raw) return EMPTY;
		const parsed = JSON.parse(raw);
		if (!parsed || !Array.isArray(parsed.items) || parsed.items.length < 20) return EMPTY;
		return parsed;
	} catch {
		return EMPTY;
	}
}
function writeCachedCatalog(data, provider = "aniworld") {
	if (typeof window === "undefined" || !data?.items?.length) return;
	try {
		const json = JSON.stringify(data);
		const key = keyFor(provider);
		window.sessionStorage.setItem(key, json);
		if (data.source === "live" || data.source === "cache" || data.source === "fallback") window.localStorage.setItem(key, json);
	} catch {}
}
function catalogProviderFromKey(key) {
	return typeof key === "string" && isCatalogProvider(key) ? key : "aniworld";
}
function catalogHasSlug(provider, slug) {
	return readCachedCatalog(provider).items.some((i) => i.slug === slug);
}
function findCachedItem(slug, preferred = "aniworld") {
	const first = readCachedCatalog(preferred).items.find((i) => i.slug === slug);
	if (first) return {
		item: first,
		provider: preferred
	};
	const other = otherProvider(preferred);
	const second = readCachedCatalog(other).items.find((i) => i.slug === slug);
	if (second) return {
		item: second,
		provider: other
	};
	return null;
}
function hintProviderForSlug(slug, current, path) {
	if (path) return providerFromPath(path);
	const here = catalogHasSlug(current, slug);
	if (catalogHasSlug(otherProvider(current), slug) && !here) return otherProvider(current);
	return current;
}
function QueryProvider({ children }) {
	const [client] = (0, import_react.useState)(() => {
		const qc = new QueryClient({ defaultOptions: { queries: {
			staleTime: 6e5,
			gcTime: 36e5,
			retry: 1,
			refetchOnWindowFocus: false,
			refetchOnReconnect: false
		} } });
		qc.getQueryCache().subscribe((event) => {
			if (event.type !== "updated") return;
			const key = event.query.queryKey;
			if (key[0] !== "catalog") return;
			const provider = catalogProviderFromKey(key[1]);
			const data = event.query.state.data;
			if (data && isCatalogProvider(provider)) writeCachedCatalog(data, provider);
		});
		return qc;
	});
	(0, import_react.useEffect)(() => {
		useLibrary.persist.rehydrate();
		useProvider.persist.rehydrate();
		for (const provider of ["aniworld", "serienstream"]) {
			const cached = readCachedCatalog(provider);
			if (cached.items.length && !client.getQueryData(["catalog", provider])) client.setQueryData(["catalog", provider], cached);
		}
	}, [client]);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(QueryClientProvider, {
		client,
		children
	});
}
var styles_default = "/assets/styles-cWaDT5Q4.css";
var APP_NAME = "Nori";
var Route$34 = createRootRoute({
	head: () => ({
		meta: [
			{ charSet: "utf-8" },
			{
				name: "viewport",
				content: "width=device-width, initial-scale=1, viewport-fit=cover"
			},
			{ title: APP_NAME },
			{
				name: "description",
				content: "Nori — Anime und Serien entdecken, weiterschauen, Fortschritt behalten."
			},
			{
				name: "theme-color",
				content: "#05060a"
			},
			{
				name: "apple-mobile-web-app-capable",
				content: "yes"
			},
			{
				name: "mobile-web-app-capable",
				content: "yes"
			},
			{
				name: "apple-mobile-web-app-status-bar-style",
				content: "black-translucent"
			}
		],
		links: [
			{
				rel: "icon",
				type: "image/svg+xml",
				href: "/favicon.svg"
			},
			{
				rel: "stylesheet",
				href: styles_default
			},
			{
				rel: "manifest",
				href: "/__grok/manifest.webmanifest"
			},
			{
				rel: "apple-touch-icon",
				href: "/__grok/icon-180.png"
			},
			{
				rel: "preconnect",
				href: "https://fonts.googleapis.com"
			},
			{
				rel: "preconnect",
				href: "https://fonts.gstatic.com",
				crossOrigin: "anonymous"
			},
			{
				rel: "stylesheet",
				href: "https://fonts.googleapis.com/css2?family=Figtree:ital,wght@0,400;0,500;0,600;1,400&family=Outfit:wght@500;600;700&display=swap"
			}
		]
	}),
	component: () => /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("html", {
		lang: "de",
		className: "antialiased",
		suppressHydrationWarning: true,
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("head", { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(HeadContent, {}) }), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("body", {
			className: "bg-bg text-fg",
			children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(PreviewHostBridge, {}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(AuthProvider, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(QueryProvider, { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(BootScreen, {}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(AppShell, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Outlet, {}) })] }) }),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Scripts, {})
			]
		})]
	})
});
var $$splitComponentImporter$22 = () => import("./routes-qwJJS2NO.mjs");
var Route$33 = createFileRoute("/")({ component: lazyRouteComponent($$splitComponentImporter$22, "component") });
var $$splitComponentImporter$21 = () => import("./einstellungen-CPrx2LuK.mjs");
var Route$32 = createFileRoute("/einstellungen")({ component: lazyRouteComponent($$splitComponentImporter$21, "component") });
var Route$31 = createFileRoute("/ios")({ beforeLoad: () => {
	throw redirect({ to: "/einstellungen/apps/ios" });
} });
var $$splitComponentImporter$20 = () => import("./kalender-B7aoj6V_.mjs");
var Route$30 = createFileRoute("/kalender")({ component: lazyRouteComponent($$splitComponentImporter$20, "component") });
var Route$29 = createFileRoute("/katalog")({
	validateSearch: (raw) => {
		const next = {};
		const q = asSearchString(raw.q);
		const genre = asSearchString(raw.genre);
		const tab = asSearchString(raw.tab);
		if (q) next.q = q;
		if (genre) next.genre = genre;
		if (tab) next.tab = tab;
		return next;
	},
	beforeLoad: ({ search }) => {
		if (search.tab === "merke") throw redirect({ to: "/merkliste" });
		if (search.tab === "zuletzt") throw redirect({ to: "/verlauf" });
		throw redirect({
			to: "/anime",
			search: {
				q: search.q,
				genre: search.genre
			}
		});
	}
});
var $$splitComponentImporter$19 = () => import("./konto-Dy6tq_NE.mjs");
/**
* Auth state components — plain wrappers around `useCurrentUserState()`.
*
* With auth on, visitors are signed out until they authenticate — in the sandbox
* live preview too, which does real sign-in. The shared dev user appears only
* when auth is disabled (`VITE_AUTH_ENABLED=false`, the shipped default).
* While the session is still resolving, gates that care about signed-out state
* render nothing so there's no signed-out flash on hard reload.
*/
/** Where `RedirectToSignIn` sends signed-out visitors. Create this route. */
/**
* Client-side redirect to the sign-in route (TanStack `<Navigate>` — NOT a full
* `window.location` reload). A hard navigation re-bootstraps the SPA and re-runs
* session loading, which feels like a second "Loading…" on /login.
*
* Guard routes by waiting out `isPending` first (see `use-current-user`), then
* render this.
*/
var Route$28 = createFileRoute("/konto")({ component: lazyRouteComponent($$splitComponentImporter$19, "component") });
var $$splitComponentImporter$18 = () => import("./login-sroey2Lr.mjs");
var Route$27 = createFileRoute("/login")({ component: lazyRouteComponent($$splitComponentImporter$18, "component") });
var $$splitComponentImporter$17 = () => import("./merkliste-D0yfFDA2.mjs");
var Route$26 = createFileRoute("/merkliste")({ component: lazyRouteComponent($$splitComponentImporter$17, "component") });
var $$splitComponentImporter$16 = () => import("./search-DsQN0gSn.mjs");
var Route$25 = createFileRoute("/search")({
	validateSearch: (raw) => {
		const q = asSearchString(raw.q);
		return q ? { q } : {};
	},
	component: lazyRouteComponent($$splitComponentImporter$16, "component")
});
var Route$24 = createFileRoute("/updates")({ beforeLoad: () => {
	throw redirect({ to: "/einstellungen/updates" });
} });
var $$splitComponentImporter$15 = () => import("./verlauf-CyHTj7Dg.mjs");
var Route$23 = createFileRoute("/verlauf")({ component: lazyRouteComponent($$splitComponentImporter$15, "component") });
var Route$22 = createFileRoute("/windows")({ beforeLoad: () => {
	throw redirect({ to: "/einstellungen/apps/windows" });
} });
var $$splitComponentImporter$14 = () => import("./anime.index-Bmp9pENv.mjs");
var Route$21 = createFileRoute("/anime/")({
	validateSearch: (raw) => {
		const next = {};
		const q = asSearchString(raw.q);
		const genre = asSearchString(raw.genre);
		if (q) next.q = q;
		if (genre) next.genre = genre;
		if (raw.sort === "za" || raw.sort === "neu") next.sort = raw.sort;
		return next;
	},
	component: lazyRouteComponent($$splitComponentImporter$14, "component")
});
var $$splitComponentImporter$13 = () => import("./anime._slug-EfpKxWtM.mjs");
var Route$20 = createFileRoute("/anime/$slug")({
	validateSearch: (raw) => {
		const next = {};
		const season = asSearchString(raw.season);
		const ep = asSearchString(raw.ep);
		if (season) next.season = season;
		if (ep) next.ep = ep;
		return next;
	},
	component: lazyRouteComponent($$splitComponentImporter$13, "component")
});
var ALLOWED_HOSTS = /* @__PURE__ */ new Set(["image.tmdb.org"]);
var Route$19 = createFileRoute("/api/cover")({ server: { handlers: { GET: async ({ request }) => {
	const url = new URL(request.url);
	const src = url.searchParams.get("src") || "";
	if (src) try {
		const remote = new URL(src);
		if (remote.protocol !== "https:" || !ALLOWED_HOSTS.has(remote.hostname)) return new Response("Bad source", { status: 400 });
		const res = await fetch(remote.toString(), {
			headers: { Accept: "image/*" },
			signal: AbortSignal.timeout(8e3)
		});
		if (!res.ok) return new Response("Cover missing", { status: 404 });
		const bytes = await res.arrayBuffer();
		return new Response(bytes, { headers: {
			"Content-Type": res.headers.get("content-type") || "image/jpeg",
			"Cache-Control": "public, max-age=86400"
		} });
	} catch {
		return new Response("Cover missing", { status: 404 });
	}
	const path = url.searchParams.get("path") || "";
	const aniworld = path.startsWith("/public/img/");
	const serien = path.startsWith("/media/images/") || path.startsWith("/storage/");
	if (!aniworld && !serien) return new Response("Bad path", { status: 400 });
	try {
		if (serien) {
			const { fetchSerienstreamAsset } = await import("./scrape.server-CxlWdT5G.mjs");
			const { bytes, contentType } = await fetchSerienstreamAsset(path);
			return new Response(Buffer.from(bytes), { headers: {
				"Content-Type": contentType,
				"Cache-Control": "public, max-age=86400"
			} });
		}
		const { fetchAniworldAsset } = await import("./scrape.server-Dx4-7B2O.mjs").then((n) => n.i).then((n) => n.i);
		const { bytes, contentType } = await fetchAniworldAsset(path);
		return new Response(Buffer.from(bytes), { headers: {
			"Content-Type": contentType,
			"Cache-Control": "public, max-age=86400"
		} });
	} catch {
		return new Response("Cover missing", { status: 404 });
	}
} } } });
var Route$18 = createFileRoute("/api/hls")({ server: { handlers: { GET: async ({ request }) => {
	const token = new URL(request.url).searchParams.get("t") || "";
	const { readStreamToken, mintStreamToken } = await import("./watch.server-Djsupa21.mjs");
	const target = readStreamToken(token);
	if (!target) return new Response("Expired", { status: 410 });
	let parsed;
	try {
		parsed = new URL(target);
	} catch {
		return new Response("Bad url", { status: 400 });
	}
	if (parsed.protocol !== "https:" && parsed.protocol !== "http:") return new Response("Bad protocol", { status: 400 });
	try {
		const res = await fetch(target, {
			headers: {
				"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
				Referer: parsed.origin + "/"
			},
			redirect: "follow",
			signal: AbortSignal.timeout(2e4)
		});
		if (!res.ok) return new Response("Upstream error", { status: 502 });
		const contentType = res.headers.get("content-type") || "application/octet-stream";
		if (contentType.includes("mpegurl") || target.includes(".m3u8")) {
			const rewritten = (await res.text()).split("\n").map((line) => {
				const trimmed = line.trim();
				if (!trimmed || trimmed.startsWith("#")) return line;
				const abs = new URL(trimmed, target).toString();
				return `/api/hls?t=${mintStreamToken(abs)}`;
			}).join("\n");
			return new Response(rewritten, { headers: {
				"Content-Type": "application/vnd.apple.mpegurl",
				"Cache-Control": "no-store"
			} });
		}
		const buf = Buffer.from(await res.arrayBuffer());
		return new Response(buf, { headers: {
			"Content-Type": contentType,
			"Cache-Control": "public, max-age=120"
		} });
	} catch {
		return new Response("Proxy failed", { status: 502 });
	}
} } } });
var FILES$1 = ["/workspace/artifacts/Nori-iOS.zip", "/workspace/release/Nori-iOS.zip"];
var Route$17 = createFileRoute("/api/nori-ios")({ server: { handlers: { GET: async () => {
	const file = FILES$1.find((p) => existsSync(p));
	if (!file) return new Response("Das iOS-Projekt ist auf diesem Server nicht vorhanden.", { status: 404 });
	const stat = statSync(file);
	const body = Readable.toWeb(createReadStream(file));
	return new Response(body, { headers: {
		"Content-Type": "application/zip",
		"Content-Length": String(stat.size),
		"Content-Disposition": "attachment; filename=\"Nori-iOS.zip\"",
		"Cache-Control": "no-store"
	} });
} } } });
var FILES = ["/workspace/artifacts/Nori-Portable-x64.zip", "/workspace/release/Nori-Portable-x64.zip"];
var Route$16 = createFileRoute("/api/nori-portable")({ server: { handlers: { GET: async () => {
	const file = FILES.find((p) => existsSync(p));
	if (!file) return new Response("Die Windows-ZIP ist auf diesem Server nicht vorhanden.", { status: 404 });
	const stat = statSync(file);
	const body = Readable.toWeb(createReadStream(file));
	return new Response(body, { headers: {
		"Content-Type": "application/zip",
		"Content-Length": String(stat.size),
		"Content-Disposition": "attachment; filename=\"Nori-Portable-x64.zip\"",
		"Cache-Control": "no-store"
	} });
} } } });
var APP_VERSION = "1.8.0";
var APP_CHANNEL = "stable";
var APP_BUILD = "2026.09.04";
var CHANGELOG = [
	{
		version: "1.8.0",
		date: "2026-09-04",
		items: [
			"Zuletzt angesehen öffnet die richtige Quelle — auch wenn du gerade auf Anime bist",
			"Serien-Cover kommen zuverlässiger von TMDB, fehlende Poster fallen auf das Serien-Cover zurück",
			"Streams folgen dem Hoster mit Cookies und Referer, iPhone teilt die Sitzung mit dem Katalog"
		]
	},
	{
		version: "1.7.0",
		date: "2026-09-04",
		items: [
			"Seiten gleiten weich ineinander — Poster wächst zur Serie, Cover-Farbe zieht mit",
			"iPhone: Cover zoomt in die Serienseite, Tastendruck federt",
			"Windows: Grafikkarte an, Startbildschirm ohne Ruckler"
		]
	},
	{
		version: "1.6.0",
		date: "2026-09-04",
		items: [
			"Serien- und Anime-Seiten färben sich nach dem Cover — Buttons, Glow, Header",
			"Cineastischer Banner, Episoden-Raster und ähnliche Titel",
			"Startseite und Poster mit Cover-Bloom, Glas-Header über dem Hero"
		]
	},
	{
		version: "1.5.0",
		date: "2026-09-04",
		items: [
			"Neues 2026-Design: cineastischer Hero, Glas-Header, Poster mit Hover-Play",
			"Serien- und Anime-Seiten färben sich nach dem Cover",
			"Outfit + Figtree, Mondlicht-Palette, Schalter Anime/Serien oben rechts"
		]
	},
	{
		version: "1.4.0",
		date: "2026-09-04",
		items: ["Quelle umschaltbar: AniWorld (Anime) oder Serienstream (Serien)", "Katalog, Kalender und Serienseiten folgen der gewählten Quelle"]
	},
	{
		version: "1.3.2",
		date: "2026-09-04",
		items: ["Einstellungen in Kategorien: Updates, Apps, Wiedergabe, Konto, Daten", "Jede Einstellung auf einer eigenen Seite, Zurück geht zur letzten Seite"]
	},
	{
		version: "1.3.1",
		date: "2026-09-04",
		items: ["Kalender kommt direkt von AniWorld, jeder Eintrag öffnet die Serie"]
	},
	{
		version: "1.3.0",
		date: "2026-09-04",
		items: [
			"Gemeinsamer Datenvertrag für Web und SwiftUI",
			"Xcode-Projekt: native iPhone-App ohne Browser und ohne Server",
			"IPA entsteht auf dem Mac (IPA-bauen.command), Signatur auf dem iPhone",
			"Entwicklung bleibt hier, Speicher und Laufzeit auf deinem Gerät"
		]
	},
	{
		version: "1.2.2",
		date: "2026-09-04",
		items: [
			"Ladebildschirm ist wieder da",
			"Trakt ohne VIP: Verlauf als JSON/CSV importieren oder öffentliches Profil",
			"Start ohne den großen Katalog im Hintergrund, Cover laden später"
		]
	},
	{
		version: "1.2.1",
		date: "2026-09-04",
		items: [
			"Resume überschreibt den Fortschritt nicht mehr, solange der Player noch springt",
			"Player-Leiste bleibt auf dem Handy vollständig bedienbar",
			"Nach einer fertigen Folge startet Weiter bei der nächsten ungesehenen"
		]
	},
	{
		version: "1.2.0",
		date: "2026-09-04",
		items: [
			"Player setzt wirklich an der letzten Stelle fort",
			"Vollbild, Tempo und Sprungtasten funktionieren",
			"Gesehen-Haken und Fortschritt auf jeder Folge",
			"Trakt: verbinden, Verlauf ziehen, fertig geschaute Folgen zurückspielen"
		]
	},
	{
		version: "1.1.0",
		date: "2026-09-04",
		items: ["Portable Windows-App (Ordner, ohne Installation)", "Update-Verwaltung mit Version, Changelog und Download"]
	},
	{
		version: "1.0.0",
		date: "2026-09-03",
		items: [
			"Startseite, Katalog, Suche und Kalender",
			"Player mit Resume, GerDub-Standard und Hoster-Fallback",
			"Merkliste, Verlauf und Konto-Sync"
		]
	}
];
function compareVersions(a, b) {
	const pa = a.split(".").map((n) => Number.parseInt(n, 10) || 0);
	const pb = b.split(".").map((n) => Number.parseInt(n, 10) || 0);
	const len = Math.max(pa.length, pb.length);
	for (let i = 0; i < len; i++) {
		const da = pa[i] ?? 0;
		const db = pb[i] ?? 0;
		if (da > db) return 1;
		if (da < db) return -1;
	}
	return 0;
}
function isElectron() {
	if (typeof navigator === "undefined") return false;
	return /electron/i.test(navigator.userAgent);
}
function formatBytes(bytes) {
	if (bytes < 1024) return `${bytes} B`;
	const mb = bytes / 1048576;
	if (mb < 10) return `${mb.toFixed(1).replace(".", ",")} MB`;
	return `${Math.round(mb)} MB`;
}
var ZIP_FILES = ["/workspace/artifacts/Nori-Portable-x64.zip", "/workspace/release/Nori-Portable-x64.zip"];
var META_FILES = ["/workspace/artifacts/nori-portable-meta.json", "/workspace/release/nori-portable-meta.json"];
var Route$15 = createFileRoute("/api/nori-update")({ server: { handlers: { GET: async () => {
	const zip = ZIP_FILES.find((p) => existsSync(p));
	const metaFile = META_FILES.find((p) => existsSync(p));
	let meta = {};
	if (metaFile) try {
		meta = JSON.parse(readFileSync(metaFile, "utf8"));
	} catch {
		meta = {};
	}
	const bytes = zip ? statSync(zip).size : meta.bytes ?? 0;
	return Response.json({
		version: APP_VERSION,
		channel: APP_CHANNEL,
		build: APP_BUILD,
		changelog: CHANGELOG,
		portable: {
			available: Boolean(zip),
			version: meta.version ?? (zip ? "1.8.0" : null),
			bytes,
			builtAt: meta.builtAt ?? null,
			url: "/api/nori-portable"
		}
	});
} } } });
var TRAKT = "https://api.trakt.tv";
var UA = "Nori/1.2.2";
var ALLOW = [
	/^\/oauth\/device\/code$/,
	/^\/oauth\/device\/token$/,
	/^\/oauth\/token$/,
	/^\/sync\/watched\/(shows|movies)$/,
	/^\/sync\/playback(\/episodes)?$/,
	/^\/sync\/history$/,
	/^\/scrobble\/(start|pause|stop)$/,
	/^\/search\/(show|movie)$/,
	/^\/users\/me$/,
	/^\/users\/[A-Za-z0-9_-]{2,32}\/watched\/shows$/
];
function envCreds() {
	return {
		clientId: (process.env.TRAKT_CLIENT_ID || process.env.VITE_TRAKT_CLIENT_ID || "").trim(),
		clientSecret: (process.env.TRAKT_CLIENT_SECRET || "").trim()
	};
}
function pickCreds(body) {
	const env = envCreds();
	return {
		clientId: (body.clientId || env.clientId).trim(),
		clientSecret: (body.clientSecret || env.clientSecret).trim()
	};
}
function headers(clientId, accessToken) {
	const h = {
		"Content-Type": "application/json",
		"trakt-api-version": "2",
		"trakt-api-key": clientId,
		"User-Agent": UA
	};
	if (accessToken) h.Authorization = `Bearer ${accessToken}`;
	return h;
}
function allowed(path) {
	return ALLOW.some((re) => re.test(path));
}
async function readJson(res) {
	const text = await res.text();
	if (!text) return null;
	try {
		return JSON.parse(text);
	} catch {
		return { error: text.slice(0, 200) };
	}
}
function messageOf(data) {
	if (!data || typeof data !== "object") return "Trakt-Fehler";
	const o = data;
	if (typeof o.error_description === "string") return o.error_description;
	if (typeof o.error === "string") return o.error;
	if (typeof o.message === "string") return o.message;
	return "Trakt-Fehler";
}
var Route$14 = createFileRoute("/api/trakt")({ server: { handlers: {
	GET: async () => {
		const { clientId, clientSecret } = envCreds();
		return Response.json({
			serverApp: Boolean(clientId && clientSecret),
			hasClientId: Boolean(clientId)
		});
	},
	POST: async ({ request }) => {
		let body;
		try {
			body = await request.json();
		} catch {
			return Response.json({
				ok: false,
				status: 400,
				error: "Ungültiger Request"
			}, { status: 400 });
		}
		const action = String(body.action || "");
		const creds = pickCreds({
			clientId: typeof body.clientId === "string" ? body.clientId : "",
			clientSecret: typeof body.clientSecret === "string" ? body.clientSecret : ""
		});
		if (action === "public-watched" && !creds.clientId) return Response.json({
			ok: false,
			status: 400,
			error: "Ohne Trakt-API-Key geht der Profil-Abruf nicht. JSON-Export unter trakt.tv/settings/data nutzen."
		}, { status: 400 });
		if (action !== "public-watched" && !creds.clientId) return Response.json({
			ok: false,
			status: 400,
			error: "Trakt Client-ID fehlt. Unter Konto eine App eintragen."
		}, { status: 400 });
		try {
			if (action === "public-watched") {
				const username = String(body.username || "").trim();
				if (!/^[A-Za-z0-9_-]{2,32}$/.test(username)) return Response.json({
					ok: false,
					status: 400,
					error: "Ungültiger Benutzername."
				}, { status: 400 });
				const res = await fetch(`${TRAKT}/users/${encodeURIComponent(username)}/watched/shows`, {
					headers: headers(creds.clientId),
					signal: AbortSignal.timeout(2e4)
				});
				const data = await readJson(res);
				return Response.json({
					ok: res.ok,
					status: res.status,
					data,
					error: res.ok ? void 0 : messageOf(data)
				});
			}
			if (action === "device-code") {
				const res = await fetch(`${TRAKT}/oauth/device/code`, {
					method: "POST",
					headers: headers(creds.clientId),
					body: JSON.stringify({ client_id: creds.clientId }),
					signal: AbortSignal.timeout(12e3)
				});
				const data = await readJson(res);
				return Response.json({
					ok: res.ok,
					status: res.status,
					data,
					error: res.ok ? void 0 : messageOf(data)
				});
			}
			if (action === "device-token") {
				if (!creds.clientSecret) return Response.json({
					ok: false,
					status: 400,
					error: "Trakt Client-Secret fehlt."
				}, { status: 400 });
				const res = await fetch(`${TRAKT}/oauth/device/token`, {
					method: "POST",
					headers: headers(creds.clientId),
					body: JSON.stringify({
						code: String(body.deviceCode || ""),
						client_id: creds.clientId,
						client_secret: creds.clientSecret
					}),
					signal: AbortSignal.timeout(12e3)
				});
				const data = await readJson(res);
				if (res.status === 400) return Response.json({
					ok: false,
					status: 400,
					pending: true,
					data
				});
				return Response.json({
					ok: res.ok,
					status: res.status,
					data,
					error: res.ok ? void 0 : messageOf(data)
				});
			}
			if (action === "refresh") {
				if (!creds.clientSecret) return Response.json({
					ok: false,
					status: 400,
					error: "Client-Secret fehlt."
				}, { status: 400 });
				const res = await fetch(`${TRAKT}/oauth/token`, {
					method: "POST",
					headers: headers(creds.clientId),
					body: JSON.stringify({
						refresh_token: String(body.refreshToken || ""),
						client_id: creds.clientId,
						client_secret: creds.clientSecret,
						redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
						grant_type: "refresh_token"
					}),
					signal: AbortSignal.timeout(12e3)
				});
				const data = await readJson(res);
				return Response.json({
					ok: res.ok,
					status: res.status,
					data,
					error: res.ok ? void 0 : messageOf(data)
				});
			}
			if (action === "proxy") {
				const path = String(body.path || "");
				if (!path.startsWith("/") || path.includes("..") || !allowed(path)) return Response.json({
					ok: false,
					status: 400,
					error: "Pfad nicht erlaubt"
				}, { status: 400 });
				const method = String(body.method || "GET").toUpperCase();
				const query = body.query && typeof body.query === "object" ? body.query : {};
				const url = new URL(`${TRAKT}${path}`);
				for (const [k, v] of Object.entries(query)) if (v != null) url.searchParams.set(k, String(v));
				const accessToken = typeof body.accessToken === "string" ? body.accessToken : "";
				const res = await fetch(url.toString(), {
					method,
					headers: headers(creds.clientId, accessToken),
					body: method === "GET" || method === "HEAD" ? void 0 : JSON.stringify(body.body ?? {}),
					signal: AbortSignal.timeout(2e4)
				});
				const data = await readJson(res);
				return Response.json({
					ok: res.ok,
					status: res.status,
					data,
					error: res.ok ? void 0 : messageOf(data)
				});
			}
			return Response.json({
				ok: false,
				status: 400,
				error: "Unbekannte Aktion"
			}, { status: 400 });
		} catch (e) {
			const message = e instanceof Error ? e.message : "Trakt nicht erreichbar";
			return Response.json({
				ok: false,
				status: 502,
				error: message
			}, { status: 502 });
		}
	}
} } });
var $$splitComponentImporter$12 = () => import("./einstellungen.index-BLC_RWLt.mjs");
var Route$13 = createFileRoute("/einstellungen/")({ component: lazyRouteComponent($$splitComponentImporter$12, "component") });
var $$splitComponentImporter$11 = () => import("./einstellungen.apps-IxBLjnbQ.mjs");
var Route$12 = createFileRoute("/einstellungen/apps")({ component: lazyRouteComponent($$splitComponentImporter$11, "component") });
var $$splitComponentImporter$10 = () => import("./einstellungen.daten-DN4eMnSh.mjs");
var Route$11 = createFileRoute("/einstellungen/daten")({ component: lazyRouteComponent($$splitComponentImporter$10, "component") });
var $$splitComponentImporter$9 = () => import("./einstellungen.quelle-C9wgo9Mq.mjs");
var Route$10 = createFileRoute("/einstellungen/quelle")({ component: lazyRouteComponent($$splitComponentImporter$9, "component") });
var $$splitComponentImporter$8 = () => import("./einstellungen.trakt-swR7XJuz.mjs");
var Route$9 = createFileRoute("/einstellungen/trakt")({ component: lazyRouteComponent($$splitComponentImporter$8, "component") });
var $$splitComponentImporter$7 = () => import("./einstellungen.updates-DIDLi4fv.mjs");
var Route$8 = createFileRoute("/einstellungen/updates")({ component: lazyRouteComponent($$splitComponentImporter$7, "component") });
var $$splitComponentImporter$6 = () => import("./einstellungen.wiedergabe-B0VgPhWk.mjs");
var Route$7 = createFileRoute("/einstellungen/wiedergabe")({ component: lazyRouteComponent($$splitComponentImporter$6, "component") });
var $$splitComponentImporter$5 = () => import("./watch._slug-DK9J0JWY.mjs");
var Route$6 = createFileRoute("/watch/$slug")({
	validateSearch: (raw) => {
		const next = {};
		const season = asSearchString(raw.season);
		const ep = asSearchString(raw.ep);
		if (season) next.season = season;
		if (ep) next.ep = ep;
		return next;
	},
	component: lazyRouteComponent($$splitComponentImporter$5, "component")
});
var Route$5 = createFileRoute("/api/auth/$")({ server: { handlers: {
	GET: ({ request }) => auth.handler(request),
	POST: ({ request }) => auth.handler(request)
} } });
var $$splitComponentImporter$4 = () => import("./einstellungen.apps.index-BVbL_ZhM.mjs");
var Route$4 = createFileRoute("/einstellungen/apps/")({ component: lazyRouteComponent($$splitComponentImporter$4, "component") });
var $$splitComponentImporter$3 = () => import("./einstellungen.apps.ios-DWMbhATQ.mjs");
var Route$3 = createFileRoute("/einstellungen/apps/ios")({ component: lazyRouteComponent($$splitComponentImporter$3, "component") });
var $$splitComponentImporter$2 = () => import("./einstellungen.apps.windows-C_Z4_kh8.mjs");
var Route$2 = createFileRoute("/einstellungen/apps/windows")({ component: lazyRouteComponent($$splitComponentImporter$2, "component") });
var $$splitComponentImporter$1 = () => import("./einstellungen.updates.index-BvrEDFoq.mjs");
var Route$1 = createFileRoute("/einstellungen/updates/")({ component: lazyRouteComponent($$splitComponentImporter$1, "component") });
var $$splitComponentImporter = () => import("./einstellungen.updates.log-Ba3Rxr_2.mjs");
var Route = createFileRoute("/einstellungen/updates/log")({ component: lazyRouteComponent($$splitComponentImporter, "component") });
var IndexRoute = Route$33.update({
	id: "/",
	path: "/",
	getParentRoute: () => Route$34
});
var EinstellungenRoute = Route$32.update({
	id: "/einstellungen",
	path: "/einstellungen",
	getParentRoute: () => Route$34
});
var IosRoute = Route$31.update({
	id: "/ios",
	path: "/ios",
	getParentRoute: () => Route$34
});
var KalenderRoute = Route$30.update({
	id: "/kalender",
	path: "/kalender",
	getParentRoute: () => Route$34
});
var KatalogRoute = Route$29.update({
	id: "/katalog",
	path: "/katalog",
	getParentRoute: () => Route$34
});
var KontoRoute = Route$28.update({
	id: "/konto",
	path: "/konto",
	getParentRoute: () => Route$34
});
var LoginRoute = Route$27.update({
	id: "/login",
	path: "/login",
	getParentRoute: () => Route$34
});
var MerklisteRoute = Route$26.update({
	id: "/merkliste",
	path: "/merkliste",
	getParentRoute: () => Route$34
});
var SearchRoute = Route$25.update({
	id: "/search",
	path: "/search",
	getParentRoute: () => Route$34
});
var UpdatesRoute = Route$24.update({
	id: "/updates",
	path: "/updates",
	getParentRoute: () => Route$34
});
var VerlaufRoute = Route$23.update({
	id: "/verlauf",
	path: "/verlauf",
	getParentRoute: () => Route$34
});
var WindowsRoute = Route$22.update({
	id: "/windows",
	path: "/windows",
	getParentRoute: () => Route$34
});
var AnimeIndexRoute = Route$21.update({
	id: "/anime/",
	path: "/anime/",
	getParentRoute: () => Route$34
});
var AnimeSlugRoute = Route$20.update({
	id: "/anime/$slug",
	path: "/anime/$slug",
	getParentRoute: () => Route$34
});
var ApiCoverRoute = Route$19.update({
	id: "/api/cover",
	path: "/api/cover",
	getParentRoute: () => Route$34
});
var ApiHlsRoute = Route$18.update({
	id: "/api/hls",
	path: "/api/hls",
	getParentRoute: () => Route$34
});
var ApiNoriIosRoute = Route$17.update({
	id: "/api/nori-ios",
	path: "/api/nori-ios",
	getParentRoute: () => Route$34
});
var ApiNoriPortableRoute = Route$16.update({
	id: "/api/nori-portable",
	path: "/api/nori-portable",
	getParentRoute: () => Route$34
});
var ApiNoriUpdateRoute = Route$15.update({
	id: "/api/nori-update",
	path: "/api/nori-update",
	getParentRoute: () => Route$34
});
var ApiTraktRoute = Route$14.update({
	id: "/api/trakt",
	path: "/api/trakt",
	getParentRoute: () => Route$34
});
var EinstellungenIndexRoute = Route$13.update({
	id: "/",
	path: "/",
	getParentRoute: () => EinstellungenRoute
});
var EinstellungenAppsRoute = Route$12.update({
	id: "/apps",
	path: "/apps",
	getParentRoute: () => EinstellungenRoute
});
var EinstellungenDatenRoute = Route$11.update({
	id: "/daten",
	path: "/daten",
	getParentRoute: () => EinstellungenRoute
});
var EinstellungenQuelleRoute = Route$10.update({
	id: "/quelle",
	path: "/quelle",
	getParentRoute: () => EinstellungenRoute
});
var EinstellungenTraktRoute = Route$9.update({
	id: "/trakt",
	path: "/trakt",
	getParentRoute: () => EinstellungenRoute
});
var EinstellungenUpdatesRoute = Route$8.update({
	id: "/updates",
	path: "/updates",
	getParentRoute: () => EinstellungenRoute
});
var EinstellungenWiedergabeRoute = Route$7.update({
	id: "/wiedergabe",
	path: "/wiedergabe",
	getParentRoute: () => EinstellungenRoute
});
var WatchSlugRoute = Route$6.update({
	id: "/watch/$slug",
	path: "/watch/$slug",
	getParentRoute: () => Route$34
});
var ApiAuthSplatRoute = Route$5.update({
	id: "/api/auth/$",
	path: "/api/auth/$",
	getParentRoute: () => Route$34
});
var EinstellungenAppsIndexRoute = Route$4.update({
	id: "/",
	path: "/",
	getParentRoute: () => EinstellungenAppsRoute
});
var EinstellungenAppsIosRoute = Route$3.update({
	id: "/ios",
	path: "/ios",
	getParentRoute: () => EinstellungenAppsRoute
});
var EinstellungenAppsWindowsRoute = Route$2.update({
	id: "/windows",
	path: "/windows",
	getParentRoute: () => EinstellungenAppsRoute
});
var EinstellungenUpdatesIndexRoute = Route$1.update({
	id: "/",
	path: "/",
	getParentRoute: () => EinstellungenUpdatesRoute
});
var EinstellungenUpdatesLogRoute = Route.update({
	id: "/log",
	path: "/log",
	getParentRoute: () => EinstellungenUpdatesRoute
});
var EinstellungenAppsRouteChildren = {
	EinstellungenAppsIosRoute,
	EinstellungenAppsWindowsRoute,
	EinstellungenAppsIndexRoute
};
var EinstellungenAppsRouteWithChildren = EinstellungenAppsRoute._addFileChildren(EinstellungenAppsRouteChildren);
var EinstellungenUpdatesRouteChildren = {
	EinstellungenUpdatesLogRoute,
	EinstellungenUpdatesIndexRoute
};
var EinstellungenRouteChildren = {
	EinstellungenAppsRoute: EinstellungenAppsRouteWithChildren,
	EinstellungenDatenRoute,
	EinstellungenQuelleRoute,
	EinstellungenTraktRoute,
	EinstellungenUpdatesRoute: EinstellungenUpdatesRoute._addFileChildren(EinstellungenUpdatesRouteChildren),
	EinstellungenWiedergabeRoute,
	EinstellungenIndexRoute
};
var rootRouteChildren = {
	IndexRoute,
	EinstellungenRoute: EinstellungenRoute._addFileChildren(EinstellungenRouteChildren),
	IosRoute,
	KalenderRoute,
	KatalogRoute,
	KontoRoute,
	LoginRoute,
	MerklisteRoute,
	SearchRoute,
	UpdatesRoute,
	VerlaufRoute,
	WindowsRoute,
	AnimeSlugRoute,
	ApiCoverRoute,
	ApiHlsRoute,
	ApiNoriIosRoute,
	ApiNoriPortableRoute,
	ApiNoriUpdateRoute,
	ApiTraktRoute,
	WatchSlugRoute,
	AnimeIndexRoute,
	ApiAuthSplatRoute
};
var routeTree = Route$34._addFileChildren(rootRouteChildren)._addFileTypes();
var router_exports = /* @__PURE__ */ __exportAll({ getRouter: () => getRouter });
function getRouter() {
	return createRouter({
		routeTree,
		defaultErrorComponent: AppErrorComponent,
		defaultPreload: "intent",
		defaultPreloadStaleTime: 3e4,
		defaultPendingMs: 0,
		defaultPendingMinMs: 0,
		defaultViewTransition: { types: viewTransitionTypes },
		scrollRestoration: true,
		stringifySearch: stringifySearchWith(JSON.stringify),
		parseSearch: parseSearchWith((value) => value)
	});
}
//#endregion
export { guessEpisodePath as A, watchRatio as B, posterVtIdent as C, useCurrentUserState as D, isPlaceholderAccount as E, progressForSlug as F, resumePosition as I, seasonWatchStats as L, nextPlayTarget as M, progressForEpisode as N, continueWatching as O, progressForPath as P, shouldPersistProgress as R, markPosterTransition as S, accountLabel as T, recordProgress as _, APP_VERSION as a, createSsrRpc as b, formatBytes as c, Route$21 as d, Route$25 as f, KindSwitch as g, readCachedCatalog as h, APP_CHANNEL as i, isEpisodeComplete as j, formatClock as k, isElectron as l, hintProviderForSlug as m, Route$6 as n, CHANGELOG as o, findCachedItem as p, APP_BUILD as r, compareVersions as s, router_exports as t, Route$20 as u, useDriveStatus as v, accountEmail as w, markBootCatalog as x, useFavoriteToggle as y, useLibrary as z };
