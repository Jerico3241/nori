import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { w as Download } from "../_libs/lucide-react.mjs";
import { c as formatBytes } from "./router-DDQw7P_P.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
import { i as SettingsScreen } from "./settings-ui-DICpPGye.mjs";
import { n as useUpdates, t as portableIsNewer } from "./updates-DUQY2QP2.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/einstellungen.apps.windows-C_Z4_kh8.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function WindowsAppPage() {
	const downloadedVersion = useUpdates((s) => s.downloadedVersion);
	const remote = useUpdates((s) => s.remote);
	const checking = useUpdates((s) => s.checking);
	const error = useUpdates((s) => s.error);
	const markDownloaded = useUpdates((s) => s.markDownloaded);
	const checkNow = useUpdates((s) => s.checkNow);
	(0, import_react.useEffect)(() => {
		checkNow();
	}, [checkNow]);
	const portable = remote?.portable;
	const latestPortable = portable?.version ?? remote?.version ?? "1.8.0";
	const needsPortable = portableIsNewer(remote, downloadedVersion);
	const ready = portable?.available !== false;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsScreen, {
		kicker: "Apps",
		title: "Windows",
		hint: "Portable EXE, ohne Installer. Daten liegen im Ordner Nori-Daten.",
		fallback: "/einstellungen/apps",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
			className: "mt-8 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
			children: [ready ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
					className: "text-sm text-muted",
					children: [
						"Portable 64-bit",
						portable?.bytes ? `, ${formatBytes(portable.bytes)}` : "",
						portable?.version ? ` · Paket ${portable.version}` : checking ? " · wird geprüft…" : "",
						needsPortable ? " · neuere Version bereit" : ""
					]
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
					asChild: true,
					className: "mt-4 w-full",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("a", {
						href: "/api/nori-portable",
						download: "Nori-Portable-x64.zip",
						onClick: () => markDownloaded(latestPortable),
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Download, { className: "size-4" }), needsPortable ? `Version ${latestPortable} laden` : "ZIP herunterladen"]
					})
				}),
				error ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "mt-3 text-sm text-red-400",
					children: error
				}) : null
			] }) : /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "text-sm text-muted",
				children: "Das Windows-Paket liegt gerade nicht bereit."
			}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
				className: "mt-4 w-full",
				variant: "outline",
				disabled: checking,
				onClick: () => void checkNow(),
				children: checking ? "Prüfe…" : "Erneut prüfen"
			})] }), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("ol", {
				className: "mt-5 space-y-3 text-sm",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("li", {
						className: "flex gap-3",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "grid size-7 shrink-0 place-items-center rounded-full bg-elevated text-xs",
							children: "1"
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { children: "ZIP entpacken. Nori.exe starten oder Installieren.cmd." })]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("li", {
						className: "flex gap-3",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "grid size-7 shrink-0 place-items-center rounded-full bg-elevated text-xs",
							children: "2"
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { children: "Ordner Nori-Daten nicht löschen — dort liegen Merkliste und Verlauf." })]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("li", {
						className: "flex gap-3",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "grid size-7 shrink-0 place-items-center rounded-full bg-elevated text-xs",
							children: "3"
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { children: "SmartScreen: Weitere Informationen, dann Trotzdem ausführen." })]
					})
				]
			})]
		})
	});
}
//#endregion
export { WindowsAppPage as component };
