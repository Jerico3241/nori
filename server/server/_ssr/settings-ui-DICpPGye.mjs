import { v as Link } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { t as cn } from "./cn-Ccejyh36.mjs";
import { T as ChevronRight } from "../_libs/lucide-react.mjs";
import { t as BackButton } from "./back-button-0P2iyjug.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/settings-ui-DICpPGye.js
var import_jsx_runtime = require_jsx_runtime();
function SettingsScreen({ kicker, title, hint, fallback = "/einstellungen", children }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("main", {
		className: "mx-auto max-w-lg px-4 pb-24 pt-6",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)(BackButton, { fallback }),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "mt-4 text-xs font-medium uppercase tracking-widest text-muted",
				children: kicker
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h1", {
				className: "mt-2 font-display text-3xl tracking-display",
				children: title
			}),
			hint ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "mt-2 text-sm text-muted",
				children: hint
			}) : null,
			children
		]
	});
}
function SettingsGroup({ label, children }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
		className: "mt-8",
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
			className: "mb-2 px-1 text-xs font-medium uppercase tracking-widest text-muted",
			children: label
		}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
			className: "divide-y divide-fg/10 overflow-hidden rounded-xl bg-surface shadow-[var(--shadow-border)]",
			children
		})]
	});
}
function SettingsRow({ to, title, hint }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Link, {
		to,
		className: "flex min-h-14 items-center gap-3 px-4 py-3 text-left transition-colors duration-150 hover:bg-elevated",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
				className: "min-w-0 flex-1 text-sm",
				children: title
			}),
			hint ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
				className: "max-w-[45%] truncate text-sm text-muted",
				children: hint
			}) : null,
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)(ChevronRight, {
				className: "size-4 shrink-0 text-subtle",
				strokeWidth: 1.75
			})
		]
	});
}
function Chip({ active, onClick, children }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
		type: "button",
		onClick,
		className: cn("nori-chip", active && "is-on"),
		children
	});
}
function Toggle({ label, on, onChange }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("button", {
		type: "button",
		onClick: () => onChange(!on),
		className: "flex min-h-14 w-full items-center justify-between gap-3 px-4 py-3 text-left",
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
			className: "text-sm",
			children: label
		}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
			className: cn("h-6 w-10 shrink-0 rounded-full p-0.5 transition-colors duration-150", on ? "bg-accent" : "bg-elevated"),
			children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { className: cn("block size-5 rounded-full bg-fg transition-transform duration-150", on ? "translate-x-4" : "translate-x-0") })
		})]
	});
}
//#endregion
export { Toggle as a, SettingsScreen as i, SettingsGroup as n, SettingsRow as r, Chip as t };
