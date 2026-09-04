import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { v as Link } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime, t as useQuery } from "../_libs/react+tanstack__react-query.mjs";
import { t as cn } from "./cn-Ccejyh36.mjs";
import { O as continueWatching, z as useLibrary } from "./router-DDQw7P_P.mjs";
import { r as fetchCatalog, t as CoverPrefetch } from "./cover-prefetch-Dz9cGrY_.mjs";
import { t as PosterCard } from "./poster-card-B3lv1e6U.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
import { t as useCatalog } from "./use-catalog-DJGhQEbo.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/merkliste-D0yfFDA2.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function Merkliste() {
	const catalog = useCatalog();
	const favorites = useLibrary((s) => s.favorites);
	const titles = useLibrary((s) => s.titles);
	const progress = useLibrary((s) => s.progress);
	const recents = useLibrary((s) => s.recents);
	const continues = (0, import_react.useMemo)(() => continueWatching(progress), [progress]);
	const [sort, setSort] = (0, import_react.useState)("neu");
	const animeCatalog = useQuery({
		queryKey: ["catalog", "aniworld"],
		queryFn: () => fetchCatalog({ data: { provider: "aniworld" } }),
		staleTime: 6e5,
		retry: 0
	});
	const seriesCatalog = useQuery({
		queryKey: ["catalog", "serienstream"],
		queryFn: () => fetchCatalog({ data: { provider: "serienstream" } }),
		staleTime: 6e5,
		retry: 0
	});
	const bySlug = (0, import_react.useMemo)(() => new Map((catalog.data?.items ?? []).map((i) => [i.slug, i])), [catalog.data]);
	const animeSlugs = (0, import_react.useMemo)(() => new Set((animeCatalog.data?.items ?? []).map((i) => i.slug)), [animeCatalog.data]);
	const seriesSlugs = (0, import_react.useMemo)(() => new Set((seriesCatalog.data?.items ?? []).map((i) => i.slug)), [seriesCatalog.data]);
	const items = (0, import_react.useMemo)(() => {
		const rows = favorites.map((slug) => {
			return bySlug.get(slug) ?? animeCatalog.data?.items.find((i) => i.slug === slug) ?? seriesCatalog.data?.items.find((i) => i.slug === slug) ?? {
				slug,
				title: titles[slug] || recents.find((r) => r.slug === slug)?.title || slug,
				alts: [],
				genres: []
			};
		});
		if (sort === "az") return [...rows].sort((a, b) => a.title.localeCompare(b.title, "de"));
		if (sort === "gesehen") {
			const order = new Map(continues.map((c, i) => [c.slug, i]));
			return [...rows].sort((a, b) => (order.get(a.slug) ?? 99) - (order.get(b.slug) ?? 99));
		}
		return rows;
	}, [
		favorites,
		bySlug,
		titles,
		recents,
		sort,
		continues,
		animeCatalog.data,
		seriesCatalog.data
	]);
	const animeItems = items.filter((i) => animeSlugs.has(i.slug) || !seriesSlugs.has(i.slug) && !animeSlugs.size);
	const seriesItems = items.filter((i) => seriesSlugs.has(i.slug) && !animeSlugs.has(i.slug));
	const leftover = items.filter((i) => !animeItems.includes(i) && !seriesItems.includes(i));
	const animeList = leftover.length ? [...animeItems, ...leftover] : animeItems;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(CoverPrefetch, { items: items.slice(0, 16) }), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("main", {
		className: "mx-auto max-w-7xl px-4 pb-20 pt-8",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "mb-3 text-xs font-medium uppercase tracking-widest text-muted",
				children: "Bibliothek"
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h1", {
				className: "font-display text-4xl tracking-display",
				children: "Merkliste"
			}),
			items.length === 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "mt-10 max-w-md",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "text-sm text-muted",
					children: "Deine Merkliste ist noch leer. Entdecke Titel und merke sie mit dem Herz."
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
					asChild: true,
					className: "mt-6",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Link, {
						to: "/anime",
						children: "Katalog öffnen"
					})
				})]
			}) : /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
					className: "mt-6 mb-8 flex gap-2",
					children: [
						"neu",
						"gesehen",
						"az"
					].map((s) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
						type: "button",
						onClick: () => setSort(s),
						className: cn("nori-chip", sort === s && "is-on"),
						children: s === "neu" ? "Zuletzt" : s === "gesehen" ? "Angesehen" : "A–Z"
					}, s))
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Section, {
					title: "Anime",
					items: animeList,
					source: "aniworld"
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Section, {
					title: "Serien",
					items: seriesItems,
					source: "serienstream"
				})
			] })
		]
	})] });
}
function Section({ title, items, source }) {
	if (items.length === 0) return null;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
		className: "mb-12",
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
			className: "mb-4 font-display text-xl tracking-tight",
			children: title
		}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
			className: "grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6",
			children: items.map((item, i) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(PosterCard, {
				item,
				eager: i < 8,
				source
			}, item.slug))
		})]
	});
}
//#endregion
export { Merkliste as component };
