import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { p as RefreshCw } from "../_libs/lucide-react.mjs";
import { a as APP_VERSION, i as APP_CHANNEL, l as isElectron, r as APP_BUILD } from "./router-DDQw7P_P.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
import { a as Toggle, i as SettingsScreen, r as SettingsRow } from "./settings-ui-DICpPGye.mjs";
import { n as useUpdates } from "./updates-DUQY2QP2.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/einstellungen.updates.index-BvrEDFoq.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function UpdatesPage() {
	const autoCheck = useUpdates((s) => s.autoCheck);
	const lastChecked = useUpdates((s) => s.lastChecked);
	const remote = useUpdates((s) => s.remote);
	const checking = useUpdates((s) => s.checking);
	const error = useUpdates((s) => s.error);
	const setAutoCheck = useUpdates((s) => s.setAutoCheck);
	const checkNow = useUpdates((s) => s.checkNow);
	const desktop = isElectron();
	(0, import_react.useEffect)(() => {
		if (autoCheck) checkNow();
	}, [autoCheck, checkNow]);
	const checkedLabel = lastChecked ? new Date(lastChecked).toLocaleString("de-DE", {
		dateStyle: "medium",
		timeStyle: "short"
	}) : "noch nicht";
	const upToDate = Boolean(remote && remote.version === "1.8.0");
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(SettingsScreen, {
		kicker: "Updates",
		title: "Version prüfen",
		hint: "Stand dieser Installation und Prüfung auf neue Pakete.",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
				className: "mt-8 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
						className: "font-display text-lg tracking-tight",
						children: "Diese Installation"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("dl", {
						className: "mt-4 grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm",
						children: [
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("dt", {
								className: "text-muted",
								children: "Version"
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("dd", { children: APP_VERSION }),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("dt", {
								className: "text-muted",
								children: "Kanal"
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("dd", {
								className: "capitalize",
								children: APP_CHANNEL
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("dt", {
								className: "text-muted",
								children: "Build"
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("dd", { children: APP_BUILD }),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("dt", {
								className: "text-muted",
								children: "Umgebung"
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("dd", { children: desktop ? "Windows-App" : "Web" }),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("dt", {
								className: "text-muted",
								children: "Geprüft"
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("dd", { children: checkedLabel })
						]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Button, {
						className: "mt-5",
						variant: "outline",
						disabled: checking,
						onClick: () => void checkNow(),
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(RefreshCw, { className: `size-4 ${checking ? "animate-spin" : ""}` }), checking ? "Prüfe…" : "Auf Updates prüfen"]
					}),
					error ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "mt-3 text-sm text-red-400",
						children: error
					}) : null,
					!error && upToDate ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "mt-3 text-sm text-muted",
						children: "Du bist auf dem neuesten Stand."
					}) : null
				]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("section", {
				className: "mt-4 overflow-hidden rounded-xl bg-surface shadow-[var(--shadow-border)]",
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Toggle, {
					label: "Beim Öffnen nach Updates sehen",
					on: autoCheck,
					onChange: setAutoCheck
				})
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "mt-4 overflow-hidden rounded-xl bg-surface shadow-[var(--shadow-border)]",
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
					to: "/einstellungen/updates/log",
					title: "Änderungen"
				})
			})
		]
	});
}
//#endregion
export { UpdatesPage as component };
