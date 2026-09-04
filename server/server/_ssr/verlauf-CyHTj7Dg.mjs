import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { v as Link } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { s as useProvider } from "./provider-B-pxa-h2.mjs";
import { O as continueWatching, p as findCachedItem, z as useLibrary } from "./router-DDQw7P_P.mjs";
import { t as CoverPrefetch } from "./cover-prefetch-Dz9cGrY_.mjs";
import { t as PosterCard } from "./poster-card-B3lv1e6U.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
import { t as useCatalog } from "./use-catalog-DJGhQEbo.mjs";
import { t as ContinueRow } from "./continue-row-DLFJRIsp.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/verlauf-CyHTj7Dg.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function Verlauf() {
	const catalog = useCatalog();
	const provider = useProvider((s) => s.provider);
	const recents = useLibrary((s) => s.recents);
	const progress = useLibrary((s) => s.progress);
	const titles = useLibrary((s) => s.titles);
	const clearHistory = useLibrary((s) => s.clearHistory);
	const clearProgress = useLibrary((s) => s.clearProgress);
	const [confirm, setConfirm] = (0, import_react.useState)(null);
	const continues = (0, import_react.useMemo)(() => continueWatching(progress), [progress]);
	const bySlug = (0, import_react.useMemo)(() => new Map((catalog.data?.items ?? []).map((i) => [i.slug, i])), [catalog.data]);
	const recentItems = recents.map((r) => {
		return findCachedItem(r.slug, r.provider || provider)?.item ?? bySlug.get(r.slug) ?? {
			slug: r.slug,
			title: r.title || titles[r.slug] || r.slug,
			alts: [],
			genres: []
		};
	});
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(CoverPrefetch, { items: recentItems.slice(0, 12) }), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("main", {
		className: "mx-auto max-w-6xl px-4 pb-20 pt-8",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "mb-3 text-xs font-medium uppercase tracking-widest text-muted",
				children: "Bibliothek"
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h1", {
				className: "font-display text-3xl tracking-display",
				children: "Verlauf"
			}),
			continues.length > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "mt-8",
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(ContinueRow, { items: continues })
			}) : null,
			recentItems.length === 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "mt-10 max-w-md",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "text-sm text-muted",
					children: "Noch nichts angesehen."
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
					asChild: true,
					className: "mt-6",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Link, {
						to: "/anime",
						children: "Katalog öffnen"
					})
				})]
			}) : /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "mb-5 mt-2 flex flex-wrap gap-2",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
						variant: "outline",
						onClick: () => setConfirm("history"),
						children: "Verlauf löschen"
					}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
						variant: "ghost",
						onClick: () => setConfirm("all"),
						children: "Alles inklusive Fortschritt"
					})]
				}),
				confirm ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "mb-6 rounded-lg bg-surface p-4",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "text-sm",
						children: confirm === "all" ? "Fortschritt und Verlauf wirklich löschen?" : "Verlauf wirklich löschen? Fortschritt bleibt erhalten."
					}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "mt-3 flex gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
							variant: "primary",
							onClick: () => {
								if (confirm === "all") clearProgress();
								else clearHistory();
								setConfirm(null);
							},
							children: "Löschen"
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
							variant: "ghost",
							onClick: () => setConfirm(null),
							children: "Abbrechen"
						})]
					})]
				}) : null,
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
					className: "grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6",
					children: recentItems.map((item, i) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(PosterCard, {
						item,
						eager: i < 8,
						source: findCachedItem(item.slug, provider)?.provider
					}, item.slug))
				})
			] })
		]
	})] });
}
//#endregion
export { Verlauf as component };
