import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { i as SettingsScreen } from "./settings-ui-DICpPGye.mjs";
import { t as TraktPanel } from "./trakt-panel-CC4BjmVD.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/einstellungen.trakt-swR7XJuz.js
var import_jsx_runtime = require_jsx_runtime();
function TraktPage() {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsScreen, {
		kicker: "Konto",
		title: "Trakt",
		hint: "Verlauf ohne VIP importieren. Schreiben braucht OAuth.",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
			className: "mt-8",
			children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(TraktPanel, {})
		})
	});
}
//#endregion
export { TraktPage as component };
