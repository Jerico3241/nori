import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { v as Link } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { s as useProvider, t as PROVIDER_META } from "./provider-B-pxa-h2.mjs";
import { d as Search } from "../_libs/lucide-react.mjs";
import { f as Route$25 } from "./router-DDQw7P_P.mjs";
import { t as CoverPrefetch } from "./cover-prefetch-Dz9cGrY_.mjs";
import { t as PosterCard } from "./poster-card-B3lv1e6U.mjs";
import { t as useCatalog } from "./use-catalog-DJGhQEbo.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/search-DsQN0gSn.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function SearchPage() {
	const initial = Route$25.useSearch().q ?? "";
	const [draft, setDraft] = (0, import_react.useState)(initial);
	const deferred = (0, import_react.useDeferredValue)(draft.trim().toLowerCase());
	const catalogQuery = useCatalog();
	const provider = useProvider((s) => s.provider);
	const kind = PROVIDER_META[provider].kind;
	const items = catalogQuery.data?.items ?? [];
	const hits = (0, import_react.useMemo)(() => {
		if (!deferred) return [];
		return items.filter((i) => `${i.title} ${i.alts.join(" ")}`.toLowerCase().includes(deferred)).slice(0, 60);
	}, [items, deferred]);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(CoverPrefetch, { items: hits.slice(0, 12) }), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("main", {
		className: "mx-auto max-w-6xl px-4 pb-20 pt-8",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "mb-3 text-xs font-medium uppercase tracking-widest text-muted",
				children: "Suche"
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("h1", {
				className: "font-display text-3xl tracking-display",
				children: [kind, " finden"]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
				className: "mt-6 mb-6 flex h-12 items-center gap-3 rounded-lg bg-surface px-4",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Search, { className: "size-4 text-muted" }), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
					value: draft,
					onChange: (e) => setDraft(e.target.value),
					placeholder: "Deutsch, Englisch, Romaji…",
					className: "h-full w-full bg-transparent outline-none",
					autoFocus: true,
					autoComplete: "off"
				})]
			}),
			!deferred ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "text-sm text-muted",
				children: "Tippe einen Titel — Treffer erscheinen sofort."
			}) : hits.length === 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "py-16 text-center text-sm text-muted",
				children: "Keine Treffer."
			}) : /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
				className: "mb-4 text-xs text-subtle",
				children: [hits.length, " Treffer"]
			}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6",
				children: hits.map((item, i) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(PosterCard, {
					item,
					eager: i < 8
				}, item.slug))
			})] }),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "mt-10 text-center",
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Link, {
					to: "/anime",
					className: "text-sm text-muted hover:text-fg",
					children: "Zum Katalog"
				})
			})
		]
	})] });
}
//#endregion
export { SearchPage as component };
