import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { v as Link } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { i as kindFromProvider, o as providerFromPath, s as useProvider } from "./provider-B-pxa-h2.mjs";
import { t as cn } from "./cn-Ccejyh36.mjs";
import { m as Play } from "../_libs/lucide-react.mjs";
import { k as formatClock } from "./router-DDQw7P_P.mjs";
import { d as useCover, l as requestCover } from "./cover-prefetch-Dz9cGrY_.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/continue-row-DLFJRIsp.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function ContinueRow({ items }) {
	if (items.length === 0) return null;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
		className: "mb-12",
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
			className: "mb-4",
			children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "flex items-baseline justify-between gap-3",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
					className: "font-display text-xl tracking-tight md:text-2xl",
					children: "Weiter schauen"
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "text-xs text-subtle",
					children: "Genau da, wo du aufgehört hast"
				})]
			}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "nori-glow-bar mt-3" })]
		}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
			className: "nori-rail nori-stagger",
			children: items.map((item) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(ContinueCard, { item }, item.episodePath))
		})]
	});
}
function ContinueCard({ item }) {
	const { poster } = useCover(item.slug);
	const source = item.provider || providerFromPath(item.episodePath);
	const setProvider = useProvider((s) => s.setProvider);
	const current = useProvider((s) => s.provider);
	(0, import_react.useEffect)(() => {
		requestCover({
			slug: item.slug,
			title: item.title,
			kind: kindFromProvider(source)
		});
	}, [
		item.slug,
		item.title,
		source
	]);
	const pct = item.durationSec > 1 ? Math.min(100, Math.round(item.positionSec / item.durationSec * 100)) : 4;
	const seasonLabel = item.season && item.season !== "filme" ? `S${item.season}` : item.season === "filme" ? "Film" : "";
	const search = { ep: String(item.episode) };
	if (item.season) search.season = item.season;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Link, {
		to: "/watch/$slug",
		params: { slug: item.slug },
		search,
		className: "group relative isolate w-60 shrink-0 outline-none",
		onClick: () => {
			if (source !== current) setProvider(source);
		},
		children: [poster ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("img", {
			src: poster,
			alt: "",
			className: "nori-poster-bloom",
			"aria-hidden": true
		}) : null, /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
			className: "overflow-hidden rounded-xl bg-surface shadow-[var(--shadow-border)] transition-transform duration-200 group-hover:-translate-y-1 group-focus-visible:-translate-y-1",
			children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "relative aspect-video bg-poster-2",
				children: [
					poster ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("img", {
						src: poster,
						alt: "",
						className: "h-full w-full object-cover",
						loading: "lazy",
						decoding: "async"
					}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
						className: "absolute inset-3 font-display text-4xl tracking-display text-fg/15",
						children: item.title.slice(0, 1)
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "absolute inset-0 bg-gradient-to-t from-bg via-bg/20 to-transparent" }),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
						className: "absolute bottom-3 left-3 grid size-10 place-items-center rounded-full bg-accent text-accent-fg shadow-[0_8px_20px_rgb(var(--tone-glow)/0.35)]",
						children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Play, {
							className: "ml-0.5 size-4",
							fill: "currentColor"
						})
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "absolute inset-x-0 bottom-0 h-1 bg-fg/15",
						children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
							className: "h-full bg-accent",
							style: { width: `${pct}%` }
						})
					})
				]
			}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "p-3",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "truncate font-display text-base leading-snug tracking-tight",
					children: item.title
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
					className: cn("mt-1 truncate text-xs text-muted"),
					children: [
						seasonLabel ? `${seasonLabel} · ` : "",
						"Folge ",
						item.episode,
						item.durationSec > 1 ? ` · ${formatClock(item.positionSec)}` : ""
					]
				})]
			})]
		})]
	});
}
//#endregion
export { ContinueRow as t };
