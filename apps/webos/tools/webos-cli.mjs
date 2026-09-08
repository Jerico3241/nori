// Hülle um das LG-SDK (`@webosose/ares-cli`).
//
// Sie tut absichtlich wenig: Gerät heraussuchen, den passenden ares-Befehl
// aufrufen, und wenn das SDK fehlt, das genau sagen statt mit „command not
// found" abzubrechen. Das Paket selbst entsteht ohne SDK (siehe
// tools/package-ipk.mjs) — installieren und starten braucht es zwingend, weil
// dabei mit dem Fernseher gesprochen wird.

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const APP = resolve(HERE, "..");
const appinfo = JSON.parse(readFileSync(join(APP, "appinfo.json"), "utf8"));

const command = process.argv[2];
const device = process.env.NORI_WEBOS_DEVICE ?? process.argv[3] ?? "";

function ares(tool, args) {
  const bin = join(APP, "node_modules", ".bin", tool);
  const useLocal = existsSync(bin);
  const result = spawnSync(useLocal ? bin : tool, args, { stdio: "inherit", shell: process.platform === "win32" });
  if (result.error && result.error.code === "ENOENT") {
    console.error(
      `[Nori:webOS] ${tool} nicht gefunden.\n`
      + "Das LG-SDK installieren:  npm i -g @webosose/ares-cli\n"
      + "Danach einmalig ein Gerät eintragen:  ares-setup-device",
    );
    process.exit(127);
  }
  process.exit(result.status ?? 1);
}

function withDevice(args) {
  return device ? ["-d", device, ...args] : args;
}

function findPackage() {
  const wanted = `${appinfo.id}_${appinfo.version}_all.ipk`;
  if (existsSync(join(APP, wanted))) return join(APP, wanted);
  const any = readdirSync(APP).filter((name) => name.endsWith(".ipk")).sort();
  if (any.length === 0) {
    console.error("[Nori:webOS] Kein .ipk gefunden — erst `npm run build && npm run webos:package`.");
    process.exit(1);
  }
  return join(APP, any[any.length - 1]);
}

switch (command) {
  case "devices":
    ares("ares-setup-device", ["--list"]);
    break;
  case "install":
    ares("ares-install", withDevice([findPackage()]));
    break;
  case "launch":
    ares("ares-launch", withDevice([appinfo.id]));
    break;
  case "inspect":
    ares("ares-inspect", withDevice(["--app", appinfo.id, "--open"]));
    break;
  case "log":
    ares("ares-log", withDevice(["-f", appinfo.id]));
    break;
  default:
    console.error(
      "[Nori:webOS] Aufruf: node tools/webos-cli.mjs <devices|install|launch|inspect|log> [Gerätename]\n"
      + "Das Gerät lässt sich auch über NORI_WEBOS_DEVICE setzen.",
    );
    process.exit(1);
}
