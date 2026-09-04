import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { v as Link } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime, t as useQuery } from "../_libs/react+tanstack__react-query.mjs";
import { s as useProvider, t as PROVIDER_META } from "./provider-B-pxa-h2.mjs";
import { t as cn } from "./cn-Ccejyh36.mjs";
import { S as Heart, d as Search } from "../_libs/lucide-react.mjs";
import { g as KindSwitch, z as useLibrary } from "./router-DDQw7P_P.mjs";
import { d as useCover, l as requestCover, n as fetchCalendar, t as CoverPrefetch } from "./cover-prefetch-Dz9cGrY_.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
import { t as CalendarSkeleton } from "./skeletons-BcBDVE1W.mjs";
import { r as langDisplay } from "./playback-CYrpmXej.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/kalender-B7aoj6V_.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function startOfBerlinDay(d = /* @__PURE__ */ new Date()) {
	const parts = new Intl.DateTimeFormat("en-GB", {
		timeZone: "Europe/Berlin",
		year: "numeric",
		month: "2-digit",
		day: "2-digit"
	}).formatToParts(d);
	const num = (t) => Number(parts.find((p) => p.type === t)?.value ?? 0);
	const y = num("year");
	const m = num("month");
	const day = num("day");
	const utc = Date.UTC(y, m - 1, day);
	const shown = new Intl.DateTimeFormat("en-GB", {
		timeZone: "Europe/Berlin",
		hour: "2-digit",
		hour12: false,
		hourCycle: "h23"
	}).format(new Date(utc));
	return utc - (Number(shown) || 0) * 36e5;
}
function countdown(delta) {
	if (delta < 0) return "gelaufen";
	if (delta < 36e5) return `${Math.max(1, Math.round(delta / 6e4))} Min`;
	if (delta < 864e5) return `${Math.round(delta / 36e5)} Std`;
	return `${Math.round(delta / 864e5)} Tage`;
}
function Kalender() {
	const favorites = useLibrary((s) => s.favorites);
	const [filter, setFilter] = (0, import_react.useState)("alle");
	const [q, setQ] = (0, import_react.useState)("");
	const [opened, setOpened] = (0, import_react.useState)({});
	const provider = useProvider((s) => s.provider);
	const query = useQuery({
		queryKey: ["calendar", provider],
		queryFn: () => fetchCalendar({ data: { provider } }),
		staleTime: 12e5,
		retry: 1,
		refetchOnWindowFocus: false
	});
	const now = Date.now();
	const today = startOfBerlinDay();
	const weekEnd = today + 6048e5;
	const rows = (0, import_react.useMemo)(() => {
		let list = query.data?.upcoming ?? [];
		if (filter === "merke") list = list.filter((r) => favorites.includes(r.slug));
		if (filter === "heute") list = list.filter((r) => r.airingAt >= today && r.airingAt < today + 864e5);
		if (filter === "woche") list = list.filter((r) => r.airingAt >= today && r.airingAt < weekEnd);
		const needle = q.trim().toLowerCase();
		if (needle) list = list.filter((r) => r.title.toLowerCase().includes(needle) || r.slug.includes(needle.replace(/\s+/g, "-")));
		return list;
	}, [
		query.data,
		filter,
		favorites,
		today,
		weekEnd,
		q
	]);
	const groups = (0, import_react.useMemo)(() => {
		const map = /* @__PURE__ */ new Map();
		for (const row of rows) {
			const hit = map.get(row.dayKey);
			if (hit) hit.list.push(row);
			else map.set(row.dayKey, {
				label: row.dayLabel,
				key: row.dayKey,
				list: [row]
			});
		}
		return [...map.values()];
	}, [rows]);
	const covers = (0, import_react.useMemo)(() => rows.slice(0, 24).map((r) => ({
		slug: r.slug,
		title: r.title
	})), [rows]);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("main", {
		className: "mx-auto max-w-3xl px-4 pb-20 pt-8",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)(CoverPrefetch, {
				items: covers,
				limit: 8
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "mb-3 text-xs font-medium uppercase tracking-widest text-muted",
				children: "Zeitplan"
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h1", {
				className: "font-display text-3xl tracking-display",
				children: "Kalender"
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
				className: "mt-2 text-sm text-muted",
				children: [
					"Releases von ",
					PROVIDER_META[provider].label,
					". Jede Karte öffnet die Serie."
				]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)(KindSwitch, { className: "mt-4" }),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
				className: "mt-6 flex h-11 items-center gap-2 rounded-md bg-surface px-3 shadow-[var(--shadow-border)]",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Search, {
					className: "size-4 text-muted",
					strokeWidth: 1.75
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
					value: q,
					onChange: (e) => setQ(e.target.value),
					placeholder: "Im Kalender suchen",
					className: "h-full w-full bg-transparent text-sm outline-none placeholder:text-subtle",
					autoComplete: "off"
				})]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "mt-4 mb-8 flex flex-wrap gap-2",
				children: [
					["alle", "Alle"],
					["merke", "Merkliste"],
					["heute", "Heute"],
					["woche", "Diese Woche"]
				].map(([id, label]) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
					type: "button",
					onClick: () => setFilter(id),
					className: cn("h-10 rounded-full px-4 text-sm", filter === id ? "bg-accent text-accent-fg" : "text-muted shadow-[var(--shadow-border)]"),
					children: label
				}, id))
			}),
			query.isLoading ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(CalendarSkeleton, {}) : query.isError ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "text-sm",
					children: "Kalender gerade nicht ladbar."
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
					className: "mt-4",
					variant: "outline",
					onClick: () => void query.refetch(),
					children: "Erneut laden"
				})]
			}) : groups.length === 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "text-sm text-muted",
				children: filter === "merke" ? "Nichts aus der Merkliste in den nächsten Tagen." : "Keine Einträge in diesem Filter."
			}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "space-y-6",
				children: groups.map((group) => {
					const isToday = group.key === berlinDayKey(now);
					const open = filter !== "alle" || opened[group.key] || opened[group.key] === void 0 && isToday;
					return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("button", {
						type: "button",
						className: "mb-3 flex min-h-11 w-full items-baseline gap-2 text-left",
						onClick: () => setOpened((s) => ({
							...s,
							[group.key]: !open
						})),
						children: [
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
								className: "font-display text-xl tracking-tight capitalize",
								children: group.label
							}),
							isToday ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
								className: "text-xs uppercase tracking-widest text-muted",
								children: "Heute"
							}) : null,
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
								className: "ml-auto text-xs text-subtle",
								children: group.list.length
							})
						]
					}), open ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("ul", {
						className: "space-y-2",
						children: group.list.map((row) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(CalendarRow, {
							row,
							now,
							favorite: favorites.includes(row.slug)
						}, `${row.slug}-${row.season}-${row.episode}-${row.dayKey}`))
					}) : null] }, group.key);
				})
			})
		]
	});
}
function berlinDayKey(ms) {
	const parts = new Intl.DateTimeFormat("en-GB", {
		timeZone: "Europe/Berlin",
		year: "numeric",
		month: "2-digit",
		day: "2-digit"
	}).formatToParts(new Date(ms));
	const num = (t) => parts.find((p) => p.type === t)?.value ?? "00";
	return `${num("year")}-${num("month")}-${num("day")}`;
}
function CalendarRow({ row, now, favorite }) {
	const { poster } = useCover(row.slug);
	const art = poster && poster.startsWith("http") ? poster : null;
	const time = new Date(row.airingAt).toLocaleTimeString("de-DE", {
		hour: "2-digit",
		minute: "2-digit",
		timeZone: "Europe/Berlin"
	});
	const delta = row.airingAt - now;
	const seasonLabel = row.season === "filme" ? "Film" : `S${row.season}`;
	const epLabel = row.episode ? `${seasonLabel}E${String(row.episode).padStart(2, "0")}` : seasonLabel;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("li", { children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Link, {
		to: "/anime/$slug",
		params: { slug: row.slug },
		search: {
			season: row.season,
			...row.episode ? { ep: String(row.episode) } : {}
		},
		preload: false,
		className: "flex min-h-16 gap-3 rounded-lg bg-surface p-3 shadow-[var(--shadow-border)] outline-none transition-colors duration-150 hover:bg-elevated focus-visible:outline-accent",
		onPointerEnter: () => requestCover({
			slug: row.slug,
			title: row.title
		}),
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: cn("relative h-16 w-12 shrink-0 overflow-hidden rounded-md", [
					"bg-poster-0",
					"bg-poster-1",
					"bg-poster-2",
					"bg-poster-3",
					"bg-poster-4",
					"bg-poster-5"
				][Math.abs(hashSlug(row.slug)) % 6]),
				children: art ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("img", {
					src: art,
					alt: "",
					className: "h-full w-full object-cover",
					decoding: "async"
				}) : null
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "min-w-0 flex-1",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
					className: "text-xs text-muted",
					children: [
						"~ ",
						time,
						" · ",
						epLabel,
						row.languages.length ? ` · ${row.languages.map(langDisplay).join(" / ")}` : "",
						" · ",
						countdown(delta)
					]
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "truncate font-display text-base tracking-tight",
					children: row.title
				})]
			}),
			favorite ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Heart, {
				className: "mt-1 size-4 shrink-0 fill-current text-fg",
				strokeWidth: 1.75
			}) : null
		]
	}) });
}
function hashSlug(slug) {
	let h = 0;
	for (let i = 0; i < slug.length; i++) h = h * 33 + slug.charCodeAt(i) >>> 0;
	return h;
}
//#endregion
export { Kalender as component };
