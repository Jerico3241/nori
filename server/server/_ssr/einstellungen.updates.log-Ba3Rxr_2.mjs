import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { o as CHANGELOG } from "./router-DDQw7P_P.mjs";
import { i as SettingsScreen } from "./settings-ui-DICpPGye.mjs";
import { n as useUpdates } from "./updates-DUQY2QP2.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/einstellungen.updates.log-Ba3Rxr_2.js
var import_jsx_runtime = require_jsx_runtime();
function ChangelogPage() {
	const changelog = useUpdates((s) => s.remote)?.changelog ?? CHANGELOG;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsScreen, {
		kicker: "Updates",
		title: "Änderungen",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("section", {
			className: "mt-8 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
			children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "space-y-5",
				children: changelog.map((entry) => /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
					className: "text-sm",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
						className: "font-medium",
						children: entry.version
					}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
						className: "text-muted",
						children: [" · ", entry.date]
					})]
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("ul", {
					className: "mt-2 list-disc space-y-1 pl-5 text-sm text-muted",
					children: entry.items.map((item) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("li", { children: item }, item))
				})] }, entry.version))
			})
		})
	});
}
//#endregion
export { ChangelogPage as component };
