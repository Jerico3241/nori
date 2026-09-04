import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { z as useLibrary } from "./router-DDQw7P_P.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
import { i as SettingsScreen } from "./settings-ui-DICpPGye.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/einstellungen.daten-DN4eMnSh.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function DatenPage() {
	const clearHistory = useLibrary((s) => s.clearHistory);
	const clearProgress = useLibrary((s) => s.clearProgress);
	const [confirm, setConfirm] = (0, import_react.useState)(null);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsScreen, {
		kicker: "Daten",
		title: "Verlauf & Fortschritt",
		hint: "Lokal auf diesem Gerät. Löschen geht nicht zurück.",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
			className: "mt-8 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
			children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "flex flex-wrap gap-2",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
					variant: "outline",
					onClick: () => setConfirm("history"),
					children: "Verlauf löschen"
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
					variant: "ghost",
					onClick: () => setConfirm("progress"),
					children: "Fortschritt löschen"
				})]
			}), confirm ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "mt-4",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "text-sm",
					children: confirm === "progress" ? "Gespeicherte Positionen wirklich löschen?" : "Verlauf wirklich löschen?"
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "mt-3 flex gap-2",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
						onClick: () => {
							if (confirm === "progress") clearProgress();
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
			}) : null]
		})
	});
}
//#endregion
export { DatenPage as component };
