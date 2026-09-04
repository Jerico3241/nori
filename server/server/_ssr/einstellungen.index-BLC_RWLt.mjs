import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { s as useProvider, t as PROVIDER_META } from "./provider-B-pxa-h2.mjs";
import { a as APP_VERSION, l as isElectron } from "./router-DDQw7P_P.mjs";
import { i as SettingsScreen, n as SettingsGroup, r as SettingsRow } from "./settings-ui-DICpPGye.mjs";
import { o as usePlayback, r as langDisplay } from "./playback-CYrpmXej.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/einstellungen.index-BLC_RWLt.js
var import_jsx_runtime = require_jsx_runtime();
function Einstellungen() {
	const langPref = usePlayback((s) => s.langPref);
	const hosterPref = usePlayback((s) => s.hosterPref);
	const desktop = isElectron();
	const provider = useProvider((s) => s.provider);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(SettingsScreen, {
		kicker: "Gerät",
		title: "Einstellungen",
		hint: "Kategorien, jede Sache auf einer eigenen Seite.",
		fallback: "/",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsGroup, {
				label: "Quelle",
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
					to: "/einstellungen/quelle",
					title: "Katalog",
					hint: PROVIDER_META[provider].label
				})
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)(SettingsGroup, {
				label: "Updates",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
					to: "/einstellungen/updates",
					title: "Version prüfen",
					hint: APP_VERSION
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
					to: "/einstellungen/updates/log",
					title: "Änderungen"
				})]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)(SettingsGroup, {
				label: "Apps",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
						to: "/einstellungen/apps",
						title: "Alle Apps"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
						to: "/einstellungen/apps/windows",
						title: "Windows",
						hint: desktop ? "Aktiv" : "Portable EXE"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
						to: "/einstellungen/apps/ios",
						title: "iPhone",
						hint: "SwiftUI"
					})
				]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsGroup, {
				label: "Wiedergabe",
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
					to: "/einstellungen/wiedergabe",
					title: "Sprache & Player",
					hint: `${langDisplay(langPref)} · ${hosterPref}`
				})
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)(SettingsGroup, {
				label: "Konto",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
					to: "/konto",
					title: "Profil"
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
					to: "/einstellungen/trakt",
					title: "Trakt",
					hint: "Verlauf importieren"
				})]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsGroup, {
				label: "Daten",
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsRow, {
					to: "/einstellungen/daten",
					title: "Verlauf & Fortschritt"
				})
			})
		]
	});
}
//#endregion
export { Einstellungen as component };
