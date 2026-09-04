import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { v as Link } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime, r as useQueryClient } from "../_libs/react+tanstack__react-query.mjs";
import { i as kindFromProvider, s as useProvider } from "./provider-B-pxa-h2.mjs";
import { t as cn } from "./cn-Ccejyh36.mjs";
import { S as Heart, m as Play } from "../_libs/lucide-react.mjs";
import { F as progressForSlug, S as markPosterTransition, j as isEpisodeComplete, y as useFavoriteToggle, z as useLibrary } from "./router-DDQw7P_P.mjs";
import { d as useCover, i as fetchSeries, l as requestCover } from "./cover-prefetch-Dz9cGrY_.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/poster-card-B3lv1e6U.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
var TONES = [
	"bg-poster-0",
	"bg-poster-1",
	"bg-poster-2",
	"bg-poster-3",
	"bg-poster-4",
	"bg-poster-5"
];
function toneIndex(slug) {
	let h = 0;
	for (let i = 0; i < slug.length; i++) h = h * 33 + slug.charCodeAt(i) >>> 0;
	return h % TONES.length;
}
var PosterCard = (0, import_react.memo)(function PosterCard({ item, eager = false, compact = false, source }) {
	const favorite = useLibrary((s) => s.favorites.includes(item.slug));
	const latest = useLibrary((s) => progressForSlug(s.progress, item.slug));
	const { poster } = useCover(item.slug);
	const toggleFavorite = useFavoriteToggle();
	const qc = useQueryClient();
	const current = useProvider((s) => s.provider);
	const provider = source || current;
	const setProvider = useProvider((s) => s.setProvider);
	const tone = TONES[toneIndex(item.slug)];
	const genre = item.genres[0];
	const [broken, setBroken] = (0, import_react.useState)(false);
	const pct = latest && latest.durationSec > 1 && !isEpisodeComplete(latest) ? Math.min(100, Math.round(latest.positionSec / latest.durationSec * 100)) : 0;
	(0, import_react.useEffect)(() => {
		requestCover({
			slug: item.slug,
			title: item.title,
			alts: item.alts,
			kind: kindFromProvider(provider)
		});
	}, [
		item.slug,
		item.title,
		item.alts,
		provider
	]);
	(0, import_react.useEffect)(() => {
		setBroken(false);
	}, [poster]);
	function prefetch() {
		qc.prefetchQuery({
			queryKey: [
				"series",
				provider,
				item.slug,
				""
			],
			queryFn: () => fetchSeries({ data: {
				slug: item.slug,
				provider
			} }),
			staleTime: 6e5
		});
	}
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
		className: "group relative isolate",
		onPointerEnter: prefetch,
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Link, {
			to: "/anime/$slug",
			params: { slug: item.slug },
			preload: "intent",
			className: "block outline-none",
			onPointerDown: (e) => {
				if (provider !== current) setProvider(provider);
				const box = e.currentTarget.querySelector("[data-nori-poster]");
				markPosterTransition(item.slug, box instanceof HTMLElement ? box : void 0);
			},
			children: [
				poster && !broken ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("img", {
					src: poster,
					alt: "",
					className: "nori-poster-bloom",
					"aria-hidden": true
				}) : null,
				/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: cn("nori-poster aspect-poster", tone),
					"data-nori-poster": item.slug,
					children: [
						poster && !broken ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("img", {
							src: poster,
							alt: "",
							className: "absolute inset-0 h-full w-full object-cover",
							loading: eager ? "eager" : "lazy",
							decoding: "async",
							referrerPolicy: "no-referrer",
							onError: () => setBroken(true)
						}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "pointer-events-none absolute inset-x-3 top-3 font-display text-5xl leading-none tracking-display text-fg/15",
							children: item.title.slice(0, 1)
						}),
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "pointer-events-none absolute inset-0 bg-gradient-to-t from-black/70 via-transparent to-black/10" }),
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "nori-poster-play absolute inset-0 grid place-items-center",
							children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
								className: "grid size-11 place-items-center rounded-full bg-accent text-accent-fg shadow-lg",
								children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Play, {
									className: "ml-0.5 size-4",
									fill: "currentColor"
								})
							})
						}),
						pct > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
							className: "absolute top-2 left-2 z-10 rounded-full bg-black/70 px-2 py-0.5 text-[11px] tabular-nums text-fg backdrop-blur-sm",
							children: [
								"F",
								latest?.episode,
								" · ",
								pct,
								"%"
							]
						}) : null,
						pct > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
							className: "absolute inset-x-0 bottom-0 h-1 bg-fg/20",
							children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
								className: "h-full bg-accent",
								style: { width: `${pct}%` }
							})
						}) : null
					]
				}),
				compact ? null : /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "mt-2.5 min-w-0",
					children: [genre ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "mb-0.5 text-[11px] font-medium uppercase tracking-widest text-muted",
						children: genre
					}) : null, /* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
						className: "line-clamp-2 font-display text-[0.95rem] leading-snug tracking-tight text-fg",
						children: item.title
					})]
				})
			]
		}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
			type: "button",
			"aria-pressed": favorite,
			"aria-label": favorite ? "Von Merkliste entfernen" : "Zur Merkliste",
			onClick: (e) => {
				e.preventDefault();
				e.stopPropagation();
				toggleFavorite(item.slug, item.title);
			},
			className: cn("absolute top-2 right-2 z-20 grid size-10 place-items-center rounded-full", "bg-black/55 text-muted backdrop-blur-md transition-[color,background-color] duration-150 hover:text-fg", favorite && "text-fg"),
			children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Heart, {
				className: cn("size-4", favorite && "fill-current"),
				strokeWidth: 1.75
			})
		})]
	});
});
//#endregion
export { PosterCard as t };
