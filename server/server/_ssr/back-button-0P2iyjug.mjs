import { x as useRouter } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { k as ArrowLeft } from "../_libs/lucide-react.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/back-button-0P2iyjug.js
var import_jsx_runtime = require_jsx_runtime();
function BackButton({ fallback = "/", label = "Zurück" }) {
	const router = useRouter();
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("button", {
		type: "button",
		onClick: () => {
			if (router.history.canGoBack()) router.history.back();
			else router.history.replace(fallback);
		},
		className: "inline-flex h-11 items-center gap-2 text-sm text-muted transition-colors duration-150 hover:text-fg",
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(ArrowLeft, {
			className: "size-4",
			strokeWidth: 1.75
		}), label]
	});
}
//#endregion
export { BackButton as t };
