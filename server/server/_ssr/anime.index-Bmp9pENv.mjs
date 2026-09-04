import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { b as useNavigate } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { s as useProvider, t as PROVIDER_META } from "./provider-B-pxa-h2.mjs";
import { t as cn } from "./cn-Ccejyh36.mjs";
import { d as Search, t as X } from "../_libs/lucide-react.mjs";
import { d as Route$21, g as KindSwitch, x as markBootCatalog } from "./router-DDQw7P_P.mjs";
import { t as CoverPrefetch } from "./cover-prefetch-Dz9cGrY_.mjs";
import { t as PosterCard } from "./poster-card-B3lv1e6U.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
import { t as useCatalog } from "./use-catalog-DJGhQEbo.mjs";
import { n as PosterSkeleton } from "./skeletons-BcBDVE1W.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/anime.index-Bmp9pENv.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
var PAGE_SIZE = 36;
function Explore() {
	const search = Route$21.useSearch();
	const navigate = useNavigate({ from: "/anime/" });
	const [draft, setDraft] = (0, import_react.useState)(search.q ?? "");
	const [genre, setGenre] = (0, import_react.useState)(search.genre ?? "");
	const [sort, setSort] = (0, import_react.useState)(search.sort ?? "az");
	const deferred = (0, import_react.useDeferredValue)(draft.trim().toLowerCase());
	const catalogQuery = useCatalog();
	const provider = useProvider((s) => s.provider);
	const kind = PROVIDER_META[provider].kind;
	const [visible, setVisible] = (0, import_react.useState)(PAGE_SIZE);
	(0, import_react.useEffect)(() => {
		if (catalogQuery.data) markBootCatalog();
	}, [catalogQuery.data]);
	const items = catalogQuery.data?.items ?? [];
	const genres = (0, import_react.useMemo)(() => {
		const set = /* @__PURE__ */ new Set();
		for (const item of items) for (const g of item.genres) if (g) set.add(g);
		return [...set].sort((a, b) => a.localeCompare(b, "de"));
	}, [items]);
	const filtered = (0, import_react.useMemo)(() => {
		let list = items;
		if (genre) list = list.filter((i) => i.genres.includes(genre));
		if (deferred) list = list.filter((i) => {
			return `${i.title} ${i.alts.join(" ")}`.toLowerCase().includes(deferred);
		});
		const copy = [...list];
		if (sort === "za") copy.sort((a, b) => b.title.localeCompare(a.title, "de"));
		else if (sort === "neu") copy.reverse();
		else copy.sort((a, b) => a.title.localeCompare(b.title, "de"));
		return copy;
	}, [
		items,
		genre,
		deferred,
		sort
	]);
	const shown = filtered.slice(0, visible);
	const coverItems = shown.slice(0, 16).map((i) => ({
		slug: i.slug,
		title: i.title,
		alts: i.alts.slice(0, 2)
	}));
	function apply(next) {
		navigate({
			search: {
				q: next.q || void 0,
				genre: next.genre || void 0,
				sort: next.sort && next.sort !== "az" ? next.sort : void 0
			},
			replace: true
		});
	}
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(CoverPrefetch, {
		items: coverItems,
		limit: 16
	}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("main", {
		className: "mx-auto max-w-6xl px-4 pb-20 pt-8",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "mb-3 text-xs font-medium uppercase tracking-widest text-muted",
				children: "Entdecken"
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("h1", {
				className: "font-display text-3xl tracking-display",
				children: ["Alle ", kind]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)(KindSwitch, { className: "mt-4" }),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("form", {
				className: "mt-6 mb-4",
				onSubmit: (e) => {
					e.preventDefault();
					apply({
						q: draft.trim(),
						genre,
						sort
					});
				},
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
					className: "flex h-12 items-center gap-3 rounded-lg bg-surface px-4 shadow-[var(--shadow-border)]",
					children: [
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Search, { className: "size-4 text-muted" }),
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							value: draft,
							onChange: (e) => {
								setDraft(e.target.value);
								setVisible(PAGE_SIZE);
							},
							placeholder: "Titel, Romaji, Alternativtitel…",
							className: "h-full w-full bg-transparent outline-none placeholder:text-subtle",
							autoComplete: "off"
						}),
						draft ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
							type: "button",
							onClick: () => setDraft(""),
							className: "text-muted",
							"aria-label": "Leeren",
							children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(X, { className: "size-4" })
						}) : null
					]
				})
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "mb-4 flex flex-wrap gap-2",
				children: [
					"az",
					"za",
					"neu"
				].map((s) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Chip, {
					active: sort === s,
					onClick: () => setSort(s),
					children: s === "az" ? "A–Z" : s === "za" ? "Z–A" : "Zuletzt"
				}, s))
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "mb-6 flex gap-2 overflow-x-auto pb-1 scrollbar-none",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Chip, {
					active: !genre,
					onClick: () => {
						setGenre("");
						setVisible(PAGE_SIZE);
					},
					children: "Alle Genres"
				}), genres.map((g) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Chip, {
					active: genre === g,
					onClick: () => {
						setGenre(g);
						setVisible(PAGE_SIZE);
					},
					children: g
				}, g))]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
				className: "mb-4 text-xs text-subtle",
				children: [
					filtered.length,
					" Titel",
					catalogQuery.data?.source === "live" ? " · live" : ""
				]
			}),
			catalogQuery.isLoading && items.length === 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6",
				children: Array.from({ length: 12 }).map((_, i) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(PosterSkeleton, {}, i))
			}) : filtered.length === 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "py-16 text-center text-sm text-muted",
				children: "Keine Treffer."
			}) : /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6",
				children: shown.map((item, i) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(PosterCard, {
					item,
					eager: i < 8
				}, item.slug))
			}), shown.length < filtered.length ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "mt-8 flex justify-center",
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
					variant: "outline",
					onClick: () => setVisible((v) => v + PAGE_SIZE),
					children: "Mehr anzeigen"
				})
			}) : null] })
		]
	})] });
}
function Chip({ active, onClick, children }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
		type: "button",
		onClick,
		className: cn("h-10 shrink-0 rounded-full px-4 text-sm font-medium", active ? "bg-accent text-accent-fg" : "text-muted shadow-[var(--shadow-border)] hover:text-fg"),
		children
	});
}
//#endregion
export { Explore as component };
