import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { l as Share, o as Smartphone, w as Download } from "../_libs/lucide-react.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
import { i as SettingsScreen } from "./settings-ui-DICpPGye.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/einstellungen.apps.ios-DWMbhATQ.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function isIOS() {
	if (typeof navigator === "undefined") return false;
	return /iPad|iPhone|iPod/.test(navigator.userAgent) || navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1;
}
function isStandalone() {
	if (typeof window === "undefined") return false;
	if (window.navigator.standalone) return true;
	return window.matchMedia("(display-mode: standalone)").matches;
}
var emptySubscribe = () => () => {};
function IosAppPage() {
	const ios = (0, import_react.useSyncExternalStore)(emptySubscribe, isIOS, () => false);
	const standalone = (0, import_react.useSyncExternalStore)(emptySubscribe, isStandalone, () => false);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(SettingsScreen, {
		kicker: "Apps",
		title: "iPhone",
		hint: "Native SwiftUI-App. Kein Safari, kein Server.",
		fallback: "/einstellungen/apps",
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
			className: "mt-8 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
			children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
					className: "font-display text-lg tracking-tight",
					children: "Xcode-Projekt"
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "mt-2 text-sm text-muted",
					children: "Auf dem Mac zur IPA bauen, Signatur auf dem iPhone. Katalog, Player und Fortschritt laufen lokal."
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
					asChild: true,
					className: "mt-4",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("a", {
						href: "/api/nori-ios",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Download, { className: "size-4" }), "Nori-iOS.zip laden"]
					})
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("ol", {
					className: "mt-5 space-y-3 text-sm",
					children: [
						/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("li", {
							className: "flex gap-3",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
								className: "grid size-7 shrink-0 place-items-center rounded-full bg-elevated text-xs",
								children: "1"
							}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { children: "ZIP auf den Mac legen und entpacken." })]
						}),
						/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("li", {
							className: "flex gap-3",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
								className: "grid size-7 shrink-0 place-items-center rounded-full bg-elevated text-xs",
								children: "2"
							}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("strong", { children: "IPA-bauen.command" }), " doppelklicken (Xcode muss installiert sein)."] })]
						}),
						/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("li", {
							className: "flex gap-3",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
								className: "grid size-7 shrink-0 place-items-center rounded-full bg-elevated text-xs",
								children: "3"
							}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", { children: [
								"Es entsteht ",
								/* @__PURE__ */ (0, import_jsx_runtime.jsx)("strong", { children: "Nori.ipa" }),
								" — unsigniert, zum Signieren auf dem iPhone."
							] })]
						}),
						/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("li", {
							className: "flex gap-3",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
								className: "grid size-7 shrink-0 place-items-center rounded-full bg-elevated text-xs",
								children: "4"
							}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { children: "IPA aufs iPhone, mit Feather, ESign oder SideStore signieren und installieren." })]
						})
					]
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "mt-4 text-xs text-subtle",
					children: "Die IPA entsteht auf dem Mac. Signieren bleibt bei dir auf dem Gerät."
				})
			]
		}), standalone ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
			className: "mt-4 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
			children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Smartphone, { className: "size-6 text-accent" }),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
					className: "mt-3 font-display text-lg tracking-tight",
					children: "Web-Variante aktiv"
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "mt-2 text-sm text-muted",
					children: "Das hier ist Safari im Home-Bildschirm-Modus — Notlösung, nicht die native App."
				})
			]
		}) : /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
			className: "mt-4 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
			children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
					className: "font-display text-lg tracking-tight",
					children: "Notlösung: Home-Bildschirm"
				}),
				!ios ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "mt-2 text-sm text-muted",
					children: "Nur falls Xcode gerade nicht geht. In Safari, nicht in Chrome."
				}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "mt-2 text-sm text-muted",
					children: "Bleibt eine Website. Für den Alltag die native App nehmen."
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("ol", {
					className: "mt-5 space-y-3 text-sm text-muted",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("li", {
						className: "flex gap-3",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "grid size-7 shrink-0 place-items-center rounded-full bg-elevated text-xs",
							children: "1"
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { children: "In Safari öffnen." })]
					}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("li", {
						className: "flex gap-3",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "grid size-7 shrink-0 place-items-center rounded-full bg-elevated text-xs",
							children: "2"
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
							className: "flex items-center gap-2",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Share, { className: "inline size-4" }), " Teilen, dann zum Home-Bildschirm."]
						})]
					})]
				})
			]
		})]
	});
}
//#endregion
export { IosAppPage as component };
