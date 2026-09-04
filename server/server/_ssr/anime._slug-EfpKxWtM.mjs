import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { b as useNavigate, v as Link } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime, t as useQuery } from "../_libs/react+tanstack__react-query.mjs";
import { i as kindFromProvider, s as useProvider, t as PROVIDER_META } from "./provider-B-pxa-h2.mjs";
import { t as parseScrapeError } from "./errors-D28ORtyS.mjs";
import { t as cn } from "./cn-Ccejyh36.mjs";
import { D as Check, S as Heart, f as RotateCw, m as Play } from "../_libs/lucide-react.mjs";
import { B as watchRatio, C as posterVtIdent, F as progressForSlug, L as seasonWatchStats, M as nextPlayTarget, N as progressForEpisode, h as readCachedCatalog, j as isEpisodeComplete, k as formatClock, m as hintProviderForSlug, p as findCachedItem, u as Route$20, y as useFavoriteToggle, z as useLibrary } from "./router-DDQw7P_P.mjs";
import { a as fetchSeriesMeta, c as ingestCovers, d as useCover, s as hasPoster, t as CoverPrefetch } from "./cover-prefetch-Dz9cGrY_.mjs";
import { t as fetchSeriesSmart } from "./series-query-ctGR06bO.mjs";
import { t as BackButton } from "./back-button-0P2iyjug.mjs";
import { t as CoverToneRoot } from "./cover-tone-C-t57wR4.mjs";
import { t as PosterCard } from "./poster-card-B3lv1e6U.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/anime._slug-EfpKxWtM.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function Badge({ className, children }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
		className: cn("inline-flex h-7 items-center rounded-full px-3 text-xs font-medium tracking-wide text-fg/90", "bg-white/8 shadow-[inset_0_0_0_1px_rgb(255_255_255/0.1)]", className),
		children
	});
}
function SeriesPage() {
	const { slug } = Route$20.useParams();
	const { season, ep } = Route$20.useSearch();
	const navigate = useNavigate({ from: "/anime/$slug" });
	const currentProvider = useProvider((s) => s.provider);
	const setProvider = useProvider((s) => s.setProvider);
	const progressMap = useLibrary((s) => s.progress);
	const latest = progressForSlug(progressMap, slug);
	const hinted = hintProviderForSlug(slug, currentProvider, latest?.episodePath);
	const catalogItem = findCachedItem(slug, hinted)?.item ?? readCachedCatalog(hinted).items.find((i) => i.slug === slug);
	const storedTitle = useLibrary((s) => s.titles[slug]);
	const remember = useLibrary((s) => s.remember);
	const favorite = useLibrary((s) => s.favorites.includes(slug));
	const toggleFavorite = useFavoriteToggle();
	const coverArt = useCover(slug);
	const seriesQuery = useQuery({
		queryKey: [
			"series-smart",
			hinted,
			slug,
			season ?? ""
		],
		queryFn: () => fetchSeriesSmart({
			slug,
			season,
			provider: hinted
		}),
		retry: 1,
		staleTime: 6e5,
		gcTime: 18e5
	});
	const series = seriesQuery.data?.series;
	const provider = seriesQuery.data?.provider ?? hinted;
	const title = series?.title || catalogItem?.title || storedTitle || slug;
	const genres = series?.genres.length ? series.genres : catalogItem?.genres ?? [];
	const episodes = series?.episodes ?? [];
	const currentIndex = ep ? episodes.findIndex((e) => String(e.number) === ep) : -1;
	const current = currentIndex >= 0 ? episodes[currentIndex] : void 0;
	const activeSeason = season || series?.activeSeason || "1";
	const meta = useQuery({
		queryKey: [
			"series-meta",
			slug,
			season ?? series?.activeSeason ?? "1",
			title,
			provider
		],
		queryFn: () => fetchSeriesMeta({ data: {
			slug,
			title,
			alts: (series?.alts?.length ? series.alts : catalogItem?.alts ?? []).slice(0, 3),
			season: season || series?.activeSeason || "1",
			kind: kindFromProvider(provider)
		} }),
		enabled: Boolean(title && title !== slug),
		staleTime: 432e5,
		gcTime: 864e5,
		retry: 0
	}).data;
	(0, import_react.useEffect)(() => {
		if (seriesQuery.data?.provider && seriesQuery.data.provider !== currentProvider) setProvider(seriesQuery.data.provider);
	}, [
		seriesQuery.data?.provider,
		currentProvider,
		setProvider
	]);
	(0, import_react.useEffect)(() => {
		remember({
			slug,
			title,
			provider
		});
	}, [
		slug,
		title,
		provider,
		remember
	]);
	(0, import_react.useEffect)(() => {
		if (!series?.coverPath || hasPoster(slug)) return;
		ingestCovers([{
			slug,
			poster: `/api/cover?path=${encodeURIComponent(series.coverPath)}`,
			banner: null
		}]);
	}, [series?.coverPath, slug]);
	(0, import_react.useEffect)(() => {
		if (!meta?.poster) return;
		ingestCovers([{
			slug,
			poster: meta.poster,
			banner: meta.banner
		}]);
	}, [
		meta?.poster,
		meta?.banner,
		slug
	]);
	function watchSearch(nextEp, nextSeason) {
		const target = nextPlayTarget(progressMap, {
			slug,
			season: nextSeason || season || series?.activeSeason || latest?.season || "1",
			episodes
		});
		return {
			season: nextSeason || season || series?.activeSeason || latest?.season || void 0,
			ep: String(nextEp || current?.number || target.episode || episodes[0]?.number || 1)
		};
	}
	const playTarget = nextPlayTarget(progressMap, {
		slug,
		season: activeSeason,
		episodes
	});
	const resumeLabel = playTarget.kind === "resume" ? `Weiter · F${playTarget.episode} ${formatClock(playTarget.resumeAt)}` : playTarget.kind === "next" ? `Weiter · Folge ${playTarget.episode}` : "Abspielen";
	const stats = seasonWatchStats(progressMap, {
		slug,
		season: activeSeason,
		episodes
	});
	const latestInSeason = latest && String(latest.season) === String(activeSeason) && !isEpisodeComplete(latest) ? latest : void 0;
	const episodePct = Math.round(watchRatio(latestInSeason) * 100);
	const banner = coverArt?.banner || meta?.banner || coverArt?.poster || meta?.poster || null;
	const toneSrc = banner;
	const description = series?.description || meta?.description || "";
	const yearLine = [series?.yearStart, series?.yearEnd].filter(Boolean).join(" – ");
	const displayAlts = (0, import_react.useMemo)(() => {
		const raw = (series?.alts?.length ? series.alts : catalogItem?.alts) ?? [];
		const nTitle = title.toLowerCase();
		return raw.filter((a) => {
			const n = a.toLowerCase().trim();
			return n && n !== nTitle && n !== slug && n !== slug.replace(/-/g, " ");
		}).slice(0, 3);
	}, [
		series?.alts,
		catalogItem?.alts,
		title,
		slug
	]);
	const similar = (0, import_react.useMemo)(() => {
		const items = readCachedCatalog(provider).items;
		if (!items.length || !genres.length) return [];
		const gset = new Set(genres);
		return items.filter((i) => i.slug !== slug).map((i) => ({
			i,
			n: i.genres.filter((g) => gset.has(g)).length
		})).filter((x) => x.n > 0).sort((a, b) => b.n - a.n).slice(0, 12).map((x) => x.i);
	}, [
		provider,
		slug,
		genres
	]);
	const prefetchItems = (0, import_react.useMemo)(() => {
		const extra = [];
		if (title && title !== slug) extra.push({
			slug,
			title
		});
		for (const item of similar.slice(0, 10)) extra.push({
			slug: item.slug,
			title: item.title,
			alts: item.alts.slice(0, 2)
		});
		return extra;
	}, [
		slug,
		title,
		similar
	]);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(CoverToneRoot, {
		src: toneSrc,
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)(CoverPrefetch, { items: prefetchItems }),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
				className: "nori-series-hero",
				children: [
					banner ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("img", {
						src: banner,
						alt: "",
						className: "nori-series-art"
					}) : null,
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "nori-series-veil" }),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "nori-series-glow" }),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "relative mx-auto flex min-h-[inherit] max-w-7xl flex-col justify-end px-4 pb-10 pt-[calc(env(safe-area-inset-top)+5.5rem)] md:pb-14",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
							className: "mb-6 flex items-center justify-between gap-3",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(BackButton, { fallback: "/" }), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("button", {
								type: "button",
								onClick: () => toggleFavorite(slug, title),
								className: cn("inline-flex h-11 items-center gap-2 rounded-full bg-white/8 px-3 text-sm backdrop-blur-md shadow-[inset_0_0_0_1px_rgb(255_255_255/0.1)]", favorite ? "text-fg" : "text-muted hover:text-fg"),
								children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Heart, {
									className: cn("size-4", favorite && "fill-current"),
									strokeWidth: 1.75
								}), favorite ? "Gemerkt" : "Merken"]
							})]
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
							className: "grid items-end gap-6 sm:grid-cols-[180px_minmax(0,1fr)] md:grid-cols-[240px_minmax(0,1fr)]",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Cover, {
								slug,
								title,
								poster: coverArt?.poster ?? meta?.poster ?? null,
								coverPath: series?.coverPath ?? null,
								percent: stats.pct,
								watched: stats.watched,
								total: stats.total,
								episodeNumber: latestInSeason?.episode,
								episodePct
							}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
								className: "min-w-0 pb-1",
								children: [
									/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
										className: "mb-2 text-xs font-medium uppercase tracking-[0.2em] text-muted",
										children: [
											yearLine || PROVIDER_META[provider].kind,
											series?.fsk ? ` · FSK ${series.fsk}` : "",
											episodes.length > 0 ? ` · ${activeSeason === "filme" ? `${episodes.length} Filme` : `${episodes.length} Folgen`}` : ""
										]
									}),
									/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h1", {
										className: "font-display text-4xl leading-[0.92] tracking-display md:text-6xl",
										children: title
									}),
									displayAlts.length ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
										className: "mt-2 text-sm text-muted",
										children: displayAlts.join(" · ")
									}) : null,
									/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
										className: "mt-4 flex flex-wrap gap-2",
										children: genres.map((g) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Badge, { children: g }, g))
									}),
									description ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
										className: "mt-4 max-w-2xl text-sm leading-relaxed text-muted line-clamp-3",
										children: description
									}) : seriesQuery.isLoading ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
										className: "mt-4 space-y-2",
										children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "h-3 w-full max-w-xl rounded-sm bg-white/10" }), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "h-3 w-4/5 max-w-lg rounded-sm bg-white/10" })]
									}) : null,
									episodes[0]?.path || latest ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
										className: "mt-6 flex flex-wrap gap-2",
										children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
											size: "lg",
											asChild: true,
											children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Link, {
												to: "/watch/$slug",
												params: { slug },
												search: watchSearch(playTarget.episode),
												children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Play, {
													className: "ml-0.5 size-4",
													fill: "currentColor"
												}), resumeLabel]
											})
										}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Button, {
											variant: "outline",
											size: "lg",
											onClick: () => toggleFavorite(slug, title),
											children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Heart, { className: cn("size-4", favorite && "fill-current") }), favorite ? "Gemerkt" : "Merkliste"]
										})]
									}) : null
								]
							})]
						})]
					})
				]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("main", {
				className: "relative mx-auto max-w-7xl px-4 pb-24",
				children: [seriesQuery.isError ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
					className: "mt-8 rounded-xl bg-surface p-6 shadow-[var(--shadow-border)]",
					children: (() => {
						const info = parseScrapeError(seriesQuery.error);
						if (info.code === "notfound") return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
								className: "font-display text-xl tracking-tight",
								children: "Serie nicht gefunden"
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
								className: "mt-2 max-w-xl text-sm text-muted",
								children: [
									"Unter diesem Slug gibt es bei ",
									PROVIDER_META[provider].label,
									" keine Serie. Such im Katalog nach dem Titel."
								]
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
								className: "mt-5",
								asChild: true,
								children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Link, {
									to: "/anime",
									children: "Zum Katalog"
								})
							})
						] });
						return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
								className: "font-display text-xl tracking-tight",
								children: "Episoden gerade nicht lesbar"
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
								className: "mt-2 max-w-xl text-sm text-muted",
								children: info.code === "blocked" ? `${PROVIDER_META[provider].label} blockiert den Zugriff gerade. Versuch es in ein paar Sekunden nochmal.` : "Die Seite hat sich geändert oder der Parser kommt nicht durch. Retry lädt neu."
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Button, {
								className: "mt-5",
								onClick: () => void seriesQuery.refetch(),
								children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(RotateCw, { className: "size-4" }), "Erneut laden"]
							})
						] });
					})()
				}) : /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [
					series && series.seasons.length > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "mt-8 mb-5 flex gap-2 overflow-x-auto pb-1 scrollbar-none",
						children: series.seasons.map((s) => {
							const active = (season || series.activeSeason) === s.id;
							return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
								type: "button",
								onClick: () => void navigate({ search: { season: s.id } }),
								className: cn("nori-chip shrink-0", active && "is-on"),
								children: s.label
							}, s.id);
						})
					}) : seriesQuery.isLoading ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "mt-8 mb-5 flex gap-2",
						children: Array.from({ length: 3 }).map((_, i) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "h-11 w-24 rounded-full bg-elevated" }, i))
					}) : null,
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "mb-4",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
							className: "flex items-baseline justify-between",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
								className: "font-display text-xl tracking-tight",
								children: series ? activeSeason === "filme" ? `${series.episodes.length} Filme` : `${series.episodes.length} Folgen` : "Episoden"
							}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
								className: "text-xs text-subtle",
								children: stats.total > 0 && stats.watched > 0 ? `${stats.watched} von ${stats.total} gesehen` : "Tippe eine Folge zum Abspielen"
							})]
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "nori-glow-bar mt-3" })]
					}),
					seriesQuery.isLoading ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(EpisodeSkeleton, {}) : series && series.episodes.length === 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "py-10 text-sm text-muted",
						children: "Keine Folgen in dieser Staffel."
					}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "grid gap-3 sm:grid-cols-2 lg:grid-cols-3",
						children: series?.episodes.map((episode) => {
							const prog = progressForEpisode(progressMap, {
								path: episode.path,
								slug,
								season: season || series.activeSeason,
								episode: episode.number
							});
							return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(EpisodeCard, {
								episode,
								meta: meta?.episodes[episode.number],
								active: String(episode.number) === ep,
								resumeAt: prog?.positionSec,
								complete: isEpisodeComplete(prog),
								ratio: watchRatio(prog),
								onPlay: () => void navigate({
									to: "/watch/$slug",
									params: { slug },
									search: {
										season: season || series?.activeSeason,
										ep: String(episode.number)
									}
								})
							}, episode.path || episode.number);
						})
					})
				] }), similar.length >= 4 ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
					className: "mt-14",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "mb-4",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
							className: "font-display text-xl tracking-tight",
							children: "Ähnliche Titel"
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "nori-glow-bar mt-3" })]
					}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "nori-rail",
						children: similar.map((item, index) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
							className: "w-36 shrink-0 sm:w-40",
							children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(PosterCard, {
								item,
								eager: index < 4,
								source: provider
							})
						}, item.slug))
					})]
				}) : null]
			})
		]
	});
}
function Cover({ slug, title, poster, coverPath, percent, watched, total, episodeNumber, episodePct }) {
	const aniworld = coverPath ? `/api/cover?path=${encodeURIComponent(coverPath)}` : null;
	const [src, setSrc] = (0, import_react.useState)(poster || aniworld);
	(0, import_react.useEffect)(() => {
		setSrc(poster || aniworld);
	}, [poster, aniworld]);
	const seasonDone = total > 0 && watched === total;
	const showOverlay = total > 0 && (watched > 0 || episodePct > 0);
	const vtName = posterVtIdent(slug);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
		className: "nori-series-poster w-36 shrink-0 sm:w-[180px] md:w-[240px]",
		children: [src ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("img", {
			src,
			alt: "",
			className: "nori-series-poster-bloom rounded-xl"
		}) : null, /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
			className: "relative overflow-hidden rounded-xl bg-poster-2 shadow-[0_24px_60px_rgb(0_0_0/0.5)] outline outline-1 -outline-offset-1 outline-white/10",
			"data-nori-cover": slug,
			style: vtName ? { viewTransitionName: vtName } : void 0,
			children: [
				src ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("img", {
					src,
					alt: "",
					className: "aspect-poster w-full object-cover",
					onError: () => {
						if (src === poster && aniworld) setSrc(aniworld);
						else setSrc(null);
					}
				}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
					className: "flex aspect-poster items-end p-4",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
						className: "font-display text-4xl leading-none tracking-display text-fg/20",
						children: title.slice(0, 1).toUpperCase()
					})
				}),
				seasonDone ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
					className: "absolute right-2 top-2 grid size-7 place-items-center rounded-full bg-accent text-accent-fg",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Check, {
						className: "size-3.5",
						strokeWidth: 2.5
					})
				}) : null,
				showOverlay ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "absolute inset-x-0 bottom-0 bg-gradient-to-t from-bg/90 to-transparent px-2.5 pb-2 pt-6",
					children: [episodePct > 0 && episodeNumber ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
						className: "text-xs font-medium tabular-nums text-fg",
						children: [
							"F",
							episodeNumber,
							" · ",
							episodePct,
							"%"
						]
					}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "text-xs font-medium tabular-nums text-fg",
						children: seasonDone ? "Staffel gesehen" : `${percent}% gesehen`
					}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
						className: "text-xs tabular-nums text-muted",
						children: [
							watched,
							"/",
							total
						]
					})]
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
					className: "absolute inset-x-0 bottom-0 h-1 bg-fg/15",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "h-full bg-accent",
						style: { width: `${episodePct > 0 && !seasonDone ? episodePct : percent}%` }
					})
				})] }) : null,
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
					className: "sr-only",
					children: slug
				})
			]
		})]
	});
}
function EpisodeCard({ episode, meta, active, resumeAt, complete, ratio, onPlay }) {
	const canPlay = Boolean(episode.path);
	const showResume = !complete && (resumeAt ?? 0) > 8;
	const heading = episode.germanTitle || meta?.title || `Folge ${episode.number}`;
	const sub = episode.englishTitle && episode.englishTitle !== heading ? episode.englishTitle : meta?.title && meta.title !== heading ? meta.title : null;
	const [stillBroken, setStillBroken] = (0, import_react.useState)(false);
	const bar = complete ? 100 : Math.round(ratio * 100);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("button", {
		type: "button",
		onClick: onPlay,
		disabled: !canPlay,
		className: cn("nori-ep w-full disabled:cursor-default disabled:opacity-60", active && "is-on"),
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
			className: "relative block aspect-video overflow-hidden bg-poster-2",
			children: [
				meta?.still && !stillBroken ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("img", {
					src: meta.still,
					alt: "",
					className: cn("h-full w-full object-cover", complete && "opacity-70"),
					loading: "lazy",
					decoding: "async",
					referrerPolicy: "no-referrer",
					onError: () => setStillBroken(true)
				}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
					className: "grid h-full w-full place-items-center font-display text-3xl tracking-display text-fg/20",
					children: String(episode.number).padStart(2, "0")
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { className: "pointer-events-none absolute inset-0 bg-gradient-to-t from-black/70 via-transparent to-black/10" }),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
					className: "nori-ep-play absolute inset-0 grid place-items-center",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
						className: "grid size-11 place-items-center rounded-full bg-accent text-accent-fg shadow-[0_10px_24px_rgb(var(--tone-glow)/0.4)]",
						children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Play, {
							className: "ml-0.5 size-4",
							fill: "currentColor"
						})
					})
				}),
				complete ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
					className: "absolute right-2 top-2 grid size-7 place-items-center rounded-full bg-accent text-accent-fg",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Check, {
						className: "size-3.5",
						strokeWidth: 2.5
					})
				}) : bar > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
					className: "absolute left-2 top-2 rounded-full bg-bg/80 px-2 py-0.5 text-[11px] tabular-nums text-fg backdrop-blur-sm",
					children: [bar, "%"]
				}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
					className: "absolute left-2 top-2 rounded-full bg-bg/70 px-2 py-0.5 text-[11px] tabular-nums text-fg backdrop-blur-sm",
					children: String(episode.number).padStart(2, "0")
				}),
				bar > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
					className: "absolute inset-x-0 bottom-0 h-1 bg-fg/20",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
						className: "block h-full bg-accent",
						style: { width: `${bar}%` }
					})
				}) : null
			]
		}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
			className: "block px-3 py-3 text-left",
			children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
					className: "block text-sm font-medium text-fg",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
						className: "mr-2 font-mono text-xs tabular-nums text-subtle",
						children: String(episode.number).padStart(2, "0")
					}), heading]
				}),
				sub ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
					className: "mt-0.5 block truncate text-xs text-muted",
					children: sub
				}) : null,
				meta?.overview ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
					className: "mt-1 line-clamp-2 text-xs leading-relaxed text-muted",
					children: meta.overview
				}) : null,
				complete ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
					className: "mt-1 block text-xs text-subtle",
					children: "Gesehen"
				}) : showResume ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
					className: "mt-1 block text-xs text-subtle",
					children: ["Fortgesetzt bei ", formatClock(resumeAt ?? 0)]
				}) : null
			]
		})]
	});
}
function EpisodeSkeleton() {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
		className: "grid gap-3 sm:grid-cols-2 lg:grid-cols-3",
		children: Array.from({ length: 6 }).map((_, i) => /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
			className: "overflow-hidden rounded-xl bg-surface shadow-[var(--shadow-border)]",
			children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "aspect-video animate-pulse bg-elevated" }), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "space-y-2 p-3",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "h-3 w-2/3 animate-pulse rounded bg-elevated" }), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "h-3 w-1/3 animate-pulse rounded bg-elevated" })]
			})]
		}, i))
	});
}
//#endregion
export { SeriesPage as component };
