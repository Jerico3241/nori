import { app, BrowserWindow, shell, nativeImage } from "electron";
import { spawn } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const PORT = Number(process.env.NORI_PORT || 17321);
const HOST = "127.0.0.1";
const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");

let mainWindow = null;
let serverProcess = null;

app.setAppUserModelId("de.nori.app");

function portableRoot() {
  if (process.env.PORTABLE_EXECUTABLE_DIR) return process.env.PORTABLE_EXECUTABLE_DIR;
  if (app.isPackaged) return path.dirname(process.execPath);
  return ROOT;
}

function dataDir() {
  return path.join(portableRoot(), "Nori-Daten");
}

function serverEntry() {
  const packed = path.join(process.resourcesPath, "nori-server", "server", "index.mjs");
  const unpacked = path.join(ROOT, ".output", "server", "index.mjs");
  if (app.isPackaged && existsSync(packed)) return packed;
  return unpacked;
}

function iconPath() {
  const ico = path.join(ROOT, "desktop", "icon.ico");
  const png = path.join(ROOT, "desktop", "icon.png");
  if (existsSync(ico)) return ico;
  if (existsSync(png)) return png;
  return undefined;
}

function log(...parts) {
  const line = `[${new Date().toISOString()}] ${parts.join(" ")}\n`;
  try {
    mkdirSync(dataDir(), { recursive: true });
    appendFileSync(path.join(dataDir(), "nori.log"), line);
  } catch {
    /* ignore */
  }
  console.log(...parts);
}

if (app.isPackaged) {
  app.setPath("userData", dataDir());
}

function waitForServer(url, timeoutMs = 45000) {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    const tick = async () => {
      try {
        const res = await fetch(url, { signal: AbortSignal.timeout(2500) });
        const text = await res.text();
        if ((res.ok || res.status === 404) && (text.includes("/assets/index-") || text.includes("$_TSR"))) {
          resolve(res.status);
          return;
        }
      } catch {
        /* still booting */
      }
      if (Date.now() - start > timeoutMs) {
        reject(new Error("Server antwortet nicht"));
        return;
      }
      setTimeout(() => void tick(), 350);
    };
    void tick();
  });
}

function spawnServer(entry) {
  const child = spawn(process.execPath, [entry], {
    cwd: path.dirname(entry),
    env: {
      ...process.env,
      ELECTRON_RUN_AS_NODE: "1",
      NORI_PORTABLE: "1",
      PORTABLE_EXECUTABLE_DIR: portableRoot(),
      PORT: String(PORT),
      HOST,
      NITRO_PORT: String(PORT),
      NITRO_HOST: HOST,
    },
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  child.stdout?.on("data", (buf) => log("server", String(buf).trim()));
  child.stderr?.on("data", (buf) => log("server-err", String(buf).trim()));
  child.on("exit", (code) => log("server-exit", String(code)));
  serverProcess = child;
  return child;
}

function createWindow() {
  const icon = iconPath();
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 900,
    minHeight: 600,
    backgroundColor: "#05060a",
    autoHideMenuBar: true,
    title: "Nori",
    icon: icon ? nativeImage.createFromPath(icon) : undefined,
    show: true,
    webPreferences: {
      contextIsolation: true,
      sandbox: false,
      spellcheck: false,
    },
  });
  const loading = path.join(ROOT, "desktop", "loading.html");
  if (existsSync(loading)) {
    void mainWindow.loadFile(loading);
  }
  mainWindow.webContents.on("did-fail-load", (_e, code, desc, url) => {
    log("did-fail-load", String(code), desc, url);
  });
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith(`http://${HOST}:`)) return { action: "allow" };
    void shell.openExternal(url);
    return { action: "deny" };
  });
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

async function loadApp() {
  const url = `http://${HOST}:${PORT}/`;
  for (let i = 1; i <= 6; i++) {
    try {
      await mainWindow.loadURL(url);
      log("loaded", url, "try", String(i));
      return;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      log("load-fail", String(i), msg);
      if (msg.includes("(-3)") || msg.includes("ERR_ABORTED")) {
        await new Promise((r) => setTimeout(r, 500));
        continue;
      }
      throw err;
    }
  }
  throw new Error("Fenster konnte die App nicht laden");
}

function showError() {
  const file = path.join(ROOT, "desktop", "error.html");
  if (existsSync(file) && mainWindow) {
    void mainWindow.loadFile(file);
  }
}

app.whenReady().then(async () => {
  log("boot", "packaged=" + String(app.isPackaged), portableRoot());
  createWindow();
  try {
    const entry = serverEntry();
    log("entry", entry, "exists", String(existsSync(entry)));
    if (!existsSync(entry)) throw new Error("Serverdatei fehlt");
    spawnServer(entry);
    const status = await waitForServer(`http://${HOST}:${PORT}/`);
    log("ready", String(status));
    await loadApp();
  } catch (err) {
    const message = err instanceof Error ? err.stack || err.message : String(err);
    log("fatal", message);
    showError();
  }
});

app.on("window-all-closed", () => {
  if (serverProcess && !serverProcess.killed) serverProcess.kill();
  app.quit();
});

app.on("before-quit", () => {
  if (serverProcess && !serverProcess.killed) serverProcess.kill();
});