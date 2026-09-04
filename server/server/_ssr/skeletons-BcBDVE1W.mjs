import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/skeletons-BcBDVE1W.js
var import_jsx_runtime = require_jsx_runtime();
function PosterSkeleton() {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "aspect-poster animate-pulse rounded-xl bg-elevated" });
}
function CalendarSkeleton() {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
		className: "space-y-3",
		children: Array.from({ length: 5 }).map((_, i) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "h-20 animate-pulse rounded-xl bg-surface" }, i))
	});
}
//#endregion
export { PosterSkeleton as n, CalendarSkeleton as t };
