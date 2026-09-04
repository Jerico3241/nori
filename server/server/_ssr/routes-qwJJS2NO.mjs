import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { b as useNavigate, v as Link } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime, t as useQuery } from "../_libs/react+tanstack__react-query.mjs";
import { i as kindFromProvider, o as providerFromPath, s as useProvider, t as PROVIDER_META } from "./provider-B-pxa-h2.mjs";
import { t as cn } from "./cn-Ccejyh36.mjs";
import { S as Heart, d as Search, m as Play } from "../_libs/lucide-react.mjs";
import { O as continueWatching, S as markPosterTransition, g as KindSwitch, p as findCachedItem, x as markBootCatalog, y as useFavoriteToggle, z as useLibrary } from "./router-DDQw7P_P.mjs";
import { d as useCover, l as requestCover, n as fetchCalendar, t as CoverPrefetch } from "./cover-prefetch-Dz9cGrY_.mjs";
import { t as CoverToneRoot } from "./cover-tone-C-t57wR4.mjs";
import { t as PosterCard } from "./poster-card-B3lv1e6U.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
import { t as useCatalog } from "./use-catalog-DJGhQEbo.mjs";
import { t as ContinueRow } from "./continue-row-DLFJRIsp.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/routes-qwJJS2NO.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function HeroCarousel({ items }) {
	const slides = items.slice(0, 6);
	const [index, setIndex] = (0, import_react.useState)(0);
	const slideKey = slides.map((s) => s.slug).join(",");
	const kind = kindFromProvider(useProvider((s) => s.provider));
	(0, import_react.useEffect)(() => {
		for (const slide of slides) requestCover({
			slug: slide.slug,
			title: slide.title,
			alts: slide.alts,
			kind
		});
	}, [slideKey, kind]);
	(0, import_react.useEffect)(() => {
		if (slides.length < 2) return;
		const t = window.setInterval(() => setIndex((i) => (i + 1) % slides.length), 8e3);
		return () => window.clearInterval(t);
	}, [slides.length]);
	const item = slides[index];
	if (!item) return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "nori-hero animate-pulse bg-surface" });
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(HeroSlide, {
		item,
		index,
		count: slides.length,
		onPick: setIndex
	});
}
function HeroSlide({ item, index, count, onPick }) {
	const art = useCover(item.slug);
	const favorite = useLibrary((s) => s.favorites.includes(item.slug));
	const toggle = useFavoriteToggle();
	const src = art?.banner || art?.poster || null;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(CoverToneRoot, {
		src,
		className: "nori-hero",
		children: [
			src ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("img", {
				src,
				alt: "",
				className: "nori-hero-art"
			}) : null,
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "nori-hero-veil" }),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "nori-hero-glow" }),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "relative mx-auto flex min-h-[inherit] max-w-7xl flex-col justify-end px-4 pb-12 pt-[calc(env(safe-area-inset-top)+6.5rem)] md:pb-20",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
						className: "text-xs font-medium uppercase tracking-[0.22em] text-muted",
						children: ["Featured", item.genres[0] ? ` · ${item.genres[0]}` : ""]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h1", {
						className: "mt-3 max-w-3xl font-display text-4xl leading-[0.92] tracking-display sm:text-5xl md:text-7xl",
						children: item.title
					}),
					item.alts[0] ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "mt-3 max-w-xl text-sm text-muted md:text-base",
						children: item.alts[0]
					}) : null,
					item.genres.length > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "mt-4 flex flex-wrap gap-2",
						children: item.genres.slice(0, 4).map((g) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "inline-flex h-7 items-center rounded-full bg-white/8 px-3 text-xs font-medium text-fg/90 shadow-[inset_0_0_0_1px_rgb(255_255_255/0.08)]",
							children: g
						}, g))
					}) : null,
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "mt-8 flex flex-wrap items-center gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
							asChild: true,
							size: "lg",
							children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Link, {
								to: "/anime/$slug",
								params: { slug: item.slug },
								onPointerDown: () => markPosterTransition(item.slug),
								children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Play, {
									className: "ml-0.5 size-4",
									fill: "currentColor"
								}), "Zur Serie"]
							})
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Button, {
							variant: "outline",
							size: "lg",
							onClick: () => toggle(item.slug, item.title),
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Heart, { className: cn("size-4", favorite && "fill-current") }), favorite ? "Gemerkt" : "Merken"]
						})]
					}),
					count > 1 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "mt-8 flex gap-1.5",
						children: Array.from({ length: count }).map((_, i) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
							type: "button",
							"aria-label": `Slide ${i + 1}`,
							onClick: () => onPick(i),
							className: cn("h-1.5 rounded-full transition-[width,background-color] duration-300", i === index ? "w-8 bg-accent" : "w-2 bg-fg/25 hover:bg-fg/40")
						}, i))
					}) : null
				]
			})
		]
	});
}
var FALLBACK_GENRES = [
	"Action",
	"Fantasy",
	"Abenteuer",
	"Comedy",
	"Drama",
	"Romance"
];
var FEATURED_ANIME = [
	"solo-leveling",
	"frieren-beyond-journeys-end",
	"jujutsu-kaisen-anime",
	"demon-slayer-kimetsu-no-yaiba",
	"attack-on-titan",
	"chainsaw-man",
	"spy-x-family",
	"kaiju-no-8"
];
var FEATURED_SERIES = [
	"reacher",
	"silo",
	"game-of-thrones",
	"the-walking-dead",
	"the-last-of-us",
	"breaking-bad",
	"stranger-things",
	"the-rookie"
];
function homeRails(catalog, opts) {
	const bySlug = new Map(catalog.map((i) => [i.slug, i]));
	const continues = continueWatching(opts.progress);
	const seen = /* @__PURE__ */ new Set([
		...continues.map((p) => p.slug),
		...opts.favorites,
		...opts.recents.map((r) => r.slug)
	]);
	const genreScore = /* @__PURE__ */ new Map();
	function addGenres(slug, weight) {
		const item = bySlug.get(slug);
		if (!item) return;
		for (const g of item.genres) genreScore.set(g, (genreScore.get(g) ?? 0) + weight);
	}
	for (const [i, p] of continues.entries()) addGenres(p.slug, 8 - Math.min(i, 7));
	for (const slug of opts.favorites) addGenres(slug, 4);
	for (const [i, r] of opts.recents.entries()) addGenres(r.slug, 3 - Math.min(i, 2));
	const rankedGenres = [...genreScore.entries()].sort((a, b) => b[1] - a[1]).map(([g]) => g);
	const rails = [];
	const used = new Set(seen);
	function pick(genre, n) {
		const out = [];
		for (const item of catalog) {
			if (out.length >= n) break;
			if (used.has(item.slug)) continue;
			if (!item.genres.includes(genre)) continue;
			used.add(item.slug);
			out.push(item);
		}
		return out;
	}
	const last = continues[0];
	if (last) {
		const genre = bySlug.get(last.slug)?.genres[0];
		if (genre) {
			const items = pick(genre, 10);
			if (items.length >= 4) rails.push({
				id: `like-${last.slug}`,
				title: `Ähnlich wie ${last.title}`,
				items
			});
		}
	}
	for (const genre of rankedGenres.slice(0, 3)) {
		const items = pick(genre, 10);
		if (items.length < 4) continue;
		rails.push({
			id: `genre-${genre}`,
			title: `Weil du ${genre} magst`,
			items
		});
	}
	if (rails.length === 0) for (const genre of FALLBACK_GENRES) {
		const items = pick(genre, 10);
		if (items.length < 4) continue;
		rails.push({
			id: `discover-${genre}`,
			title: genre,
			items
		});
		if (rails.length >= 4) break;
	}
	const leftover = catalog.filter((i) => !used.has(i.slug)).slice(0, 10);
	if (leftover.length >= 4) rails.push({
		id: "more",
		title: "Zum Entdecken",
		items: leftover
	});
	return rails.slice(0, 5);
}
function Home() {
	const navigate = useNavigate();
	const [draft, setDraft] = (0, import_react.useState)("");
	const favorites = useLibrary((s) => s.favorites);
	const recents = useLibrary((s) => s.recents);
	const titles = useLibrary((s) => s.titles);
	const progress = useLibrary((s) => s.progress);
	const continues = (0, import_react.useMemo)(() => continueWatching(progress), [progress]);
	const catalogQuery = useCatalog();
	const provider = useProvider((s) => s.provider);
	const meta = PROVIDER_META[provider];
	(0, import_react.useEffect)(() => {
		if (catalogQuery.data) markBootCatalog();
	}, [catalogQuery.data]);
	const calendarQuery = useQuery({
		queryKey: ["calendar", provider],
		queryFn: () => fetchCalendar({ data: { provider } }),
		staleTime: 12e5,
		retry: 0
	});
	const items = catalogQuery.data?.items ?? [];
	const bySlug = (0, import_react.useMemo)(() => new Map(items.map((i) => [i.slug, i])), [items]);
	const featuredItems = (0, import_react.useMemo)(() => {
		const picked = [];
		for (const slug of provider === "serienstream" ? FEATURED_SERIES : FEATURED_ANIME) {
			const hit = bySlug.get(slug);
			if (hit) picked.push(hit);
		}
		if (picked.length < 3) for (const item of items) {
			if (picked.some((p) => p.slug === item.slug)) continue;
			picked.push(item);
			if (picked.length >= 6) break;
		}
		return picked.slice(0, 6);
	}, [
		bySlug,
		items,
		provider
	]);
	const rails = (0, import_react.useMemo)(() => homeRails(items, {
		progress,
		favorites,
		recents
	}), [
		items,
		progress,
		favorites,
		recents
	]);
	const merkeItems = (0, import_react.useMemo)(() => favorites.map((slug) => {
		return findCachedItem(slug, provider)?.item ?? bySlug.get(slug) ?? {
			slug,
			title: titles[slug] || recents.find((r) => r.slug === slug)?.title || slug,
			alts: [],
			genres: []
		};
	}).slice(0, 12), [
		favorites,
		bySlug,
		titles,
		recents,
		provider
	]);
	const recentItems = (0, import_react.useMemo)(() => recents.map((r) => {
		return findCachedItem(r.slug, r.provider || provider)?.item ?? bySlug.get(r.slug) ?? {
			slug: r.slug,
			title: r.title || titles[r.slug] || r.slug,
			alts: [],
			genres: []
		};
	}).slice(0, 12), [
		recents,
		bySlug,
		titles,
		provider
	]);
	const popular = (0, import_react.useMemo)(() => {
		const action = items.filter((i) => i.genres.includes("Action")).slice(0, 12);
		if (action.length >= 6) return action;
		return items.slice(0, 12);
	}, [items]);
	const newEps = (0, import_react.useMemo)(() => {
		const recent = calendarQuery.data?.recent ?? [];
		const out = [];
		for (const row of recent) {
			if (!row.slug) continue;
			const hit = bySlug.get(row.slug);
			if (hit && !out.some((x) => x.slug === hit.slug)) out.push(hit);
			if (out.length >= 10) break;
		}
		return out;
	}, [calendarQuery.data, bySlug]);
	const upcoming = (0, import_react.useMemo)(() => {
		const rows = calendarQuery.data?.upcoming ?? [];
		const out = [];
		for (const row of rows) {
			if (!row.slug) continue;
			const hit = bySlug.get(row.slug);
			if (hit && !out.some((x) => x.slug === hit.slug)) out.push(hit);
			if (out.length >= 10) break;
		}
		return out;
	}, [calendarQuery.data, bySlug]);
	const coverTargets = (0, import_react.useMemo)(() => {
		const extra = [];
		const kindOf = (slug, fallback) => fallback || kindFromProvider(findCachedItem(slug, provider)?.provider || provider);
		for (const item of featuredItems) extra.push({
			slug: item.slug,
			title: item.title,
			alts: item.alts.slice(0, 2),
			kind: kindFromProvider(provider)
		});
		for (const p of continues.slice(0, 8)) extra.push({
			slug: p.slug,
			title: p.title,
			kind: kindFromProvider(p.provider || providerFromPath(p.episodePath))
		});
		for (const item of merkeItems.slice(0, 8)) extra.push({
			slug: item.slug,
			title: item.title,
			alts: item.alts.slice(0, 2),
			kind: kindOf(item.slug)
		});
		for (const item of recentItems.slice(0, 8)) extra.push({
			slug: item.slug,
			title: item.title,
			alts: item.alts.slice(0, 2),
			kind: kindOf(item.slug)
		});
		for (const item of popular.slice(0, 12)) extra.push({
			slug: item.slug,
			title: item.title,
			alts: item.alts.slice(0, 2),
			kind: kindFromProvider(provider)
		});
		for (const item of newEps) extra.push({
			slug: item.slug,
			title: item.title,
			alts: item.alts.slice(0, 2),
			kind: kindFromProvider(provider)
		});
		for (const item of upcoming) extra.push({
			slug: item.slug,
			title: item.title,
			alts: item.alts.slice(0, 2),
			kind: kindFromProvider(provider)
		});
		for (const rail of rails) for (const item of rail.items.slice(0, 10)) extra.push({
			slug: item.slug,
			title: item.title,
			alts: item.alts.slice(0, 2),
			kind: kindFromProvider(provider)
		});
		const seen = /* @__PURE__ */ new Set();
		return extra.filter((i) => {
			if (seen.has(i.slug)) return false;
			seen.add(i.slug);
			return true;
		});
	}, [
		featuredItems,
		continues,
		merkeItems,
		recentItems,
		popular,
		newEps,
		upcoming,
		rails,
		provider
	]);
	const hasHistory = continues.length > 0 || favorites.length > 0 || recents.length > 0;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [
		/* @__PURE__ */ (0, import_jsx_runtime.jsx)(CoverPrefetch, {
			items: coverTargets,
			limit: 16,
			kind: kindFromProvider(provider)
		}),
		/* @__PURE__ */ (0, import_jsx_runtime.jsx)(HeroCarousel, { items: featuredItems }),
		/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("main", {
			className: "mx-auto max-w-7xl px-4 pb-20 pt-8",
			children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("form", {
					className: "mb-8 md:hidden",
					onSubmit: (e) => {
						e.preventDefault();
						const q = draft.trim();
						navigate({
							to: "/search",
							search: q ? { q } : {}
						});
					},
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
						className: "flex h-12 items-center gap-3 rounded-full bg-surface px-4 shadow-[var(--shadow-border)]",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Search, {
							className: "size-4 shrink-0 text-muted",
							strokeWidth: 1.75
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							value: draft,
							onChange: (e) => setDraft(e.target.value),
							placeholder: `${meta.kind} suchen…`,
							className: "h-full w-full bg-transparent text-base text-fg outline-none placeholder:text-subtle",
							autoComplete: "off",
							autoCorrect: "off",
							spellCheck: false
						})]
					})
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "mb-8 flex items-center justify-between gap-3 sm:hidden",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "text-xs font-medium uppercase tracking-widest text-muted",
						children: meta.kind
					}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(KindSwitch, {})]
				}),
				continues.length > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(ContinueRow, { items: continues }) : null,
				merkeItems.length > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Rail, {
					title: "Merkliste",
					href: "/merkliste",
					items: merkeItems.slice(0, 8)
				}) : null,
				recentItems.length > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Rail, {
					title: "Zuletzt angesehen",
					href: "/verlauf",
					items: recentItems
				}) : null,
				popular.length > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Rail, {
					title: `Beliebte ${meta.kind}`,
					href: "/anime",
					items: popular
				}) : null,
				newEps.length > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Rail, {
					title: "Neue Episoden",
					href: "/kalender",
					items: newEps
				}) : null,
				upcoming.length > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Rail, {
					title: "Demnächst",
					href: "/kalender",
					items: upcoming
				}) : null,
				rails.map((rail) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Rail, {
					title: rail.title,
					href: "/anime",
					items: rail.items
				}, rail.id)),
				!hasHistory ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "max-w-xl text-sm text-muted",
					children: "Schau ein paar Folgen — dann werden die Reihen hier aus deinem Verlauf zusammengestellt."
				}) : null
			]
		})
	] });
}
function Rail({ title, href, items }) {
	const provider = useProvider((s) => s.provider);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
		className: "mb-12",
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
			className: "mb-4",
			children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "flex items-baseline justify-between gap-3",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
					className: "font-display text-xl tracking-tight md:text-2xl",
					children: title
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Link, {
					to: href,
					className: "text-xs text-muted transition-colors hover:text-fg",
					children: "Alle"
				})]
			}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "nori-glow-bar mt-3" })]
		}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
			className: "nori-rail nori-stagger",
			children: items.map((item, index) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "w-36 shrink-0 sm:w-40",
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(PosterCard, {
					item,
					eager: index < 4,
					source: findCachedItem(item.slug, provider)?.provider
				})
			}, item.slug))
		})]
	});
}
//#endregion
export { Home as component };
