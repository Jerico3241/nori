import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { l as isElectron } from "./router-DDQw7P_P.mjs";
import { i as SettingsScreen, n as SettingsGroup, r as SettingsRow } from "./settings-ui-DICpPGye.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/einstellungen.apps.index-BVbL_ZhM.js
var import_jsx_runtime = require_jsx_runtime();
function AppsPage() {
	const desktop = isElectron();
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsScreen, {
		kicker: "Apps",
		title: "Apps",
		hint: "Jedes Paket hat eine eigene Seite.",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(SettingsGroup, {
			label: "Geräte",
			children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
				to: "/einstellungen/apps/windows",
				title: "Windows",
				hint: desktop ? "Aktiv" : "Portable EXE"
			}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
				to: "/einstellungen/apps/ios",
				title: "iPhone",
				hint: "SwiftUI"
			})]
		})
	});
}
//#endregion
export { AppsPage as component };
