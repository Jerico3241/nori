import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { s as useProvider, t as PROVIDER_META } from "./provider-B-pxa-h2.mjs";
import { g as KindSwitch } from "./router-DDQw7P_P.mjs";
import { i as SettingsScreen } from "./settings-ui-DICpPGye.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/einstellungen.quelle-C9wgo9Mq.js
var import_jsx_runtime = require_jsx_runtime();
function QuellePage() {
	const provider = useProvider((s) => s.provider);
	const current = PROVIDER_META[provider];
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SettingsScreen, {
		kicker: "Quelle",
		title: "Katalog",
		hint: "AniWorld für Anime, Serienstream für Serien. Merkliste und Verlauf bleiben auf dem Gerät.",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
			className: "mt-8 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
			children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
					className: "text-sm text-muted",
					children: ["Aktiv: ", current.label]
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(KindSwitch, { className: "mt-4" }),
				/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("ul", {
					className: "mt-5 space-y-2 text-sm text-muted",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("li", { children: "AniWorld — aniworld.to, Anime-Katalog und Anime-Kalender." }), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("li", { children: "Serienstream — serienstream.to, Serien-Katalog und Serien-Kalender." })]
				})
			]
		})
	});
}
//#endregion
export { QuellePage as component };
