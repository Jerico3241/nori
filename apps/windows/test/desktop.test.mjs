// Die Desktop-Prüfung: Nori wird wirklich gestartet und bedient.
//
// ## Warum im echten Programm und nicht im Browser
//
// Die Hälfte dessen, was an Nori für Windows neu ist, gibt es im Browser gar
// nicht: der Hauptprozess mit der Quellenschicht, die Brücke dorthin, das
// Fenster, die verschlüsselte Ablage. Ein Test, der nur die Oberfläche im
// Browser aufruft, prüft die andere Hälfte — und übersieht genau die Fehler,
// die eine Desktop-App ausmachen: eine Brücke, die nichts freigibt, ein
// Fenster, das schwarz bleibt, eine Adresse, die von `file://` nicht lädt.
//
// Playwright startet deshalb die **gebaute App** über `_electron.launch`. Das
// ist derselbe Hauptprozess, derselbe Vorlader und dieselbe Oberfläche, die
// auch im Installer landen — nur unter Linux statt Windows.
//
// ## Was das nicht ist
//
// Kein Beweis, dass Nori auf Windows läuft. Chromium, Node und der Kern sind
// dieselben; der Fensterrahmen, die DPI-Skalierung, WebView-Codecs und
// SmartScreen entscheiden sich auf dem Zielsystem. Was hier grün ist, ist die
// Anwendung — nicht die Verpackung.
//
// ## Der Nachbau läuft über `https:`
//
// Nori für Windows lädt seine Oberfläche von `file://` und lässt nach seiner
// eigenen Inhaltsrichtlinie nur `https:` an Bild, Ton und Abrufe heran. Ein
// Nachbau über `http:` wäre also nicht langsam, sondern gesperrt — und eine
// Prüfung, die dafür die Richtlinie lockert, prüft nicht mehr die App, die
// ausgeliefert wird. Der Nachbau startet deshalb hier selbst, mit einem
// Wegwerf-Zertifikat für `127.0.0.1`; Electron bekommt dafür
// `--ignore-certificate-errors` mit. Das ist ein Startschalter dieser Prüfung
// und steht in keiner Zeile des Programms.
//
// ## Auch für das fertige Paket
//
// `NORI_PACKAGED=<Pfad zur ausführbaren Datei>` startet statt des Quellordners
// das gepackte Ergebnis. Das ist kein Feinschliff: Im Paket liegt die App als
// `app.asar`, und `electron-builder` entscheidet selbst, was hineinkommt.
// Wer dort etwas weglässt, das zur Laufzeit doch gebraucht wird, merkt es
// sonst erst auf dem Rechner des Nutzers.
//
// Voraussetzungen:
//
//     npm run build
//     npm i --no-save playwright
//     xvfb-run -a node test/desktop.test.mjs
//
//     npm run package:linux
//     NORI_PACKAGED=release/linux-unpacked/nori xvfb-run -a node test/desktop.test.mjs

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

let _electron;
try {
  ({ _electron } = await import("playwright"));
} catch {
  console.error("[Nori:Windows] playwright fehlt — npm i --no-save playwright");
  process.exit(127);
}

const HERE = dirname(fileURLToPath(import.meta.url));
const APP = resolve(HERE, "..");
const MOCK_PORT = Number(process.env.NORI_MOCK_PORT ?? 8798);
const BASE = `https://127.0.0.1:${MOCK_PORT}`;
const SHOTS = resolve(process.env.NORI_SHOTS ?? join(APP, "test-shots"));
if (!existsSync(SHOTS)) mkdirSync(SHOTS, { recursive: true });

/** Denselben Nachbau wie beim Fernbedienungslauf starten — nur über `https:`. */
const mock = spawn(process.execPath, [resolve(APP, "../webos/test/mock-server.mjs")], {
  env: { ...process.env, NORI_MOCK_TLS: "1", NORI_MOCK_PORT: String(MOCK_PORT) },
  stdio: ["ignore", "pipe", "pipe"],
});
await new Promise((ready, fail) => {
  const timer = setTimeout(() => fail(new Error("Nachbau startet nicht")), 20_000);
  mock.stdout.on("data", (chunk) => {
    if (String(chunk).includes("[Nori:mock]")) {
      clearTimeout(timer);
      ready();
    }
  });
  mock.on("exit", (code) => {
    clearTimeout(timer);
    fail(new Error(`Nachbau beendet (${code})`));
  });
});

/** Ein eigenes Datenverzeichnis je Lauf — sonst prüft der zweite Lauf den ersten. */
const USER_DATA = join(APP, "test-userdata");
rmSync(USER_DATA, { recursive: true, force: true });

const results = [];
let failures = 0;

function check(name, ok, detail = "") {
  results.push(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures += 1;
}

function section(name) {
  results.push(`\n— ${name} ${"—".repeat(Math.max(0, 58 - name.length))}`);
}

/** Der Quellordner — oder das fertige Paket, wenn eines genannt ist. */
const packaged = process.env.NORI_PACKAGED
  ? resolve(APP, process.env.NORI_PACKAGED)
  : null;
const flags = [`--user-data-dir=${USER_DATA}`, "--no-sandbox", "--ignore-certificate-errors"];

const app = await _electron.launch({
  ...(packaged ? { executablePath: packaged, args: flags } : { args: [APP, ...flags] }),
  // Dasselbe für den Hauptprozess: sein `fetch` ist das von Node und kennt
  // den Chromium-Schalter nicht.
  env: { ...process.env, NORI_TEST: "1", NODE_TLS_REJECT_UNAUTHORIZED: "0" },
});

const page = await app.firstWindow();
const errors = [];
page.on("pageerror", (error) => errors.push(error.message));
page.on("console", (message) => {
  if (message.type() === "error") errors.push(message.text());
});

async function shot(name) {
  await page.screenshot({ path: join(SHOTS, `${name}.png`) });
}

async function goto(hash, wait = 1600) {
  await page.evaluate((target) => { window.location.hash = target; }, hash);
  await page.waitForTimeout(wait);
}

/** Vor die Quellen den Nachbau schalten — derselbe wie beim Fernbedienungslauf. */
async function useMockServer() {
  await page.evaluate((base) => {
    const raw = localStorage.getItem("nori.webos.settings");
    const current = raw ? JSON.parse(raw) : {};
    localStorage.setItem("nori.webos.settings", JSON.stringify({
      ...current,
      transport: "server",
      serverUrl: base,
      tmdbMode: "server",
      debug: true,
    }));
  }, BASE);
  await page.reload();
  await page.waitForTimeout(2500);
}

try {
  // --- 1. Start -----------------------------------------------------------
  section("Start");
  await page.waitForSelector(".shell", { timeout: 30_000 });
  const boot = await page.evaluate(() => ({
    shell: Boolean(document.querySelector(".shell")),
    splashGone: !document.querySelector(".boot"),
    accent: getComputedStyle(document.documentElement).getPropertyValue("--accent").trim(),
    sidebar: document.querySelectorAll(".navbtn").length,
    title: document.title,
    background: getComputedStyle(document.body).backgroundColor,
  }));
  check("Das Fenster zeigt die App", boot.shell && boot.splashGone, JSON.stringify(boot));
  check("Nori-Farbwelt: Eisblau als Akzent", boot.accent === "#79c7ff", boot.accent);
  check("Dunkler Grund, kein Weiß", boot.background === "rgb(3, 7, 13)", boot.background);
  check("Seitenleiste mit sechs Einträgen", boot.sidebar === 6, String(boot.sidebar));
  check("Fenstertitel „Nori“", boot.title === "Nori", boot.title);

  const bridgeState = await page.evaluate(() => ({
    present: typeof window.nori === "object",
    // Was das Fenster **nicht** sehen darf.
    noRequire: typeof window.require === "undefined",
    noProcess: typeof window.process === "undefined",
    keys: window.nori ? Object.keys(window.nori).sort() : [],
  }));
  check("Die Brücke ist da", bridgeState.present, bridgeState.keys.join(", "));
  check("Kein `require` im Fenster", bridgeState.noRequire);
  check("Kein `process` im Fenster", bridgeState.noProcess);

  const versions = await page.evaluate(() => window.nori.versions);
  check("Electron und Chromium gemeldet",
    versions.electron.length > 0 && versions.chrome.length > 0,
    `Electron ${versions.electron} · Chromium ${versions.chrome} · Node ${versions.node}`);

  // Die Quellenschicht läuft im Hauptprozess — hier gegen den Nachbau.
  await useMockServer();
  await page.waitForSelector(".card.poster, .card.land", { timeout: 30_000 });
  await shot("01-start");

  const home = await page.evaluate(() => ({
    rails: document.querySelectorAll(".section .rail").length,
    cards: document.querySelectorAll(".card").length,
    hero: Boolean(document.querySelector(".hero")),
    heroTitle: document.querySelector(".hero h2")?.textContent
      ?? document.querySelector(".hero-logo")?.getAttribute("alt") ?? "",
    heroActions: Array.from(document.querySelectorAll(".hero-actions .btn")).map((b) => b.textContent.trim()),
  }));
  check("Startseite mit Kopfbereich", home.hero && home.heroTitle.length > 0, home.heroTitle);
  check("Startseite mit Reihen und Karten", home.rails > 0 && home.cards > 4,
    `${home.rails} Reihen, ${home.cards} Karten`);
  check("Kopfbereich: Ansehen · Merkliste · Mehr",
    home.heroActions.some((a) => a.includes("ansehen")) && home.heroActions.some((a) => a.includes("Merkliste")),
    home.heroActions.join(" | "));

  // --- 2. Bilder ----------------------------------------------------------
  section("Bilder");
  const art = await page.evaluate(() => {
    const areas = Array.from(document.querySelectorAll(".card .art"));
    const sizes = Array.from(document.querySelectorAll(".art img"))
      .map((img) => (/\/t\/p\/([^/]+)\//.exec(img.getAttribute("src") ?? "") ?? [])[1])
      .filter(Boolean);
    return {
      areas: areas.length,
      loaded: areas.filter((node) => node.querySelector("img")).length,
      sizes,
      queue: window.__noriArtwork ? window.__noriArtwork() : null,
    };
  });
  check("Bilder nur in Sichtweite", art.loaded <= art.areas,
    `${art.loaded} von ${art.areas} Flächen`);
  check("Kein Bild in `original`", !art.sizes.includes("original"), art.sizes.join(", ") || "noch keins");
  check("Bildabrufe begrenzt", art.queue !== null && art.queue.running <= art.queue.limit,
    JSON.stringify(art.queue));

  // --- 3. Navigation ------------------------------------------------------
  section("Navigation");
  for (const [to, expect] of [
    ["katalog", ".grid"],
    ["kalender", ".chips"],
    ["merkliste", ".page"],
    ["verlauf", ".page"],
    ["einstellungen", ".settings"],
  ]) {
    await goto(`#/${to}`, 1200);
    const found = await page.evaluate((selector) => Boolean(document.querySelector(selector)), expect);
    check(`Seite „${to}“ baut sich auf`, found, expect);
  }
  await shot("02-einstellungen");

  await goto("#/katalog", 3000);
  const catalog = await page.evaluate(() => ({
    cards: document.querySelectorAll(".grid .card").length,
    columns: (() => {
      const cards = Array.from(document.querySelectorAll(".grid > .card"));
      const top = cards[0]?.getBoundingClientRect().top;
      return cards.filter((card) => Math.abs(card.getBoundingClientRect().top - top) < 40).length;
    })(),
  }));
  check("Katalog zeigt ein Raster", catalog.cards > 10, `${catalog.cards} Karten`);
  check("Raster füllt die Fensterbreite", catalog.columns >= 3, `${catalog.columns} Spalten`);
  await shot("03-katalog");

  // Suche über das Feld in der Kopfzeile.
  await page.fill(".search input", "Frieren");
  await page.waitForTimeout(1200);
  const search = await page.evaluate(() => ({
    head: document.querySelector(".section-head h2")?.textContent ?? "",
    first: document.querySelector(".grid .card .card-title")?.textContent ?? "",
  }));
  check("Suche filtert", search.head.includes("Suche") && /frieren/i.test(search.first),
    `${search.head} · ${search.first}`);
  await page.fill(".search input", "");
  await page.waitForTimeout(800);

  // --- 4. Detailseite -----------------------------------------------------
  section("Detailseite");
  await goto("#/titel/aniworld/frieren", 4000);
  const details = await page.evaluate(() => ({
    hero: Boolean(document.querySelector(".hero")),
    title: document.querySelector(".hero h2")?.textContent
      ?? document.querySelector(".hero-logo")?.getAttribute("alt") ?? "",
    meta: document.querySelector(".hero .meta")?.textContent ?? "",
    description: document.querySelector(".hero-text")?.textContent ?? "",
    episodes: document.querySelectorAll(".grid.episodes .ep").length,
    seasons: document.querySelectorAll(".season-row select option").length,
    similar: document.querySelectorAll(".section .rail .card").length,
    hasDownload: /herunterladen|download/i.test(document.body.textContent ?? ""),
    hasCrunchyroll: /crunchyroll/i.test(document.body.textContent ?? ""),
  }));
  check("Detailseite mit Kopfbereich", details.hero && details.title.length > 0, details.title);
  check("Jahr, Staffeln, Genres, Bewertung", /\d{4}/.test(details.meta), details.meta);
  check("Beschreibung", details.description.length > 20);
  check("Folgen als Liste", details.episodes > 0, `${details.episodes} Folgen`);
  check("Staffelauswahl", details.seasons > 1, `${details.seasons} Staffeln`);
  check("Ähnliche Titel", details.similar > 0, `${details.similar} Titel`);
  check("Keine Download-Knöpfe", !details.hasDownload);
  check("Kein Crunchyroll", !details.hasCrunchyroll);
  await shot("04-detail");

  // Staffel wechseln.
  await page.selectOption(".season-row select", { index: 1 });
  await page.waitForTimeout(2500);
  const season2 = await page.evaluate(() => ({
    value: document.querySelector(".season-row select")?.value ?? "",
    episodes: document.querySelectorAll(".grid.episodes .ep").length,
  }));
  check("Staffelwechsel lädt neue Folgen", season2.episodes > 0, `Staffel ${season2.value}, ${season2.episodes} Folgen`);

  // Merkliste über den Kopfbereich.
  await page.click(".hero-actions .btn:nth-child(2)");
  await page.waitForTimeout(600);
  const marked = await page.evaluate(() => {
    const raw = localStorage.getItem("nori.library");
    return raw ? (JSON.parse(raw).favorites ?? []).length : 0;
  });
  check("Merkliste nimmt den Titel auf", marked > 0, `${marked} gemerkt`);

  // --- 5. Player ----------------------------------------------------------
  section("Player");
  await page.click(".grid.episodes .ep");
  await page.waitForTimeout(6000);
  const player = await page.evaluate(() => {
    const video = document.querySelector(".player-video");
    return {
      mounted: Boolean(document.querySelector(".player")),
      video: Boolean(video),
      src: video?.currentSrc || video?.src || "",
      sidebarHidden: !document.querySelector(".sidebar"),
      controls: document.querySelectorAll(".player-controls .btn").length,
      title: document.querySelector(".player-title b")?.textContent ?? "",
      overlay: document.querySelector(".player-overlay h2")?.textContent ?? "",
    };
  });
  check("Player öffnet sich", player.mounted && player.video, JSON.stringify(player.overlay));
  check("Im Player keine Seitenleiste", player.sidebarHidden);
  check("Bedienelemente vorhanden", player.controls >= 6, `${player.controls} Knöpfe`);
  check("Titel und Folge stehen oben", player.title.length > 0, player.title);
  check("Eine Streamadresse wurde aufgelöst", player.src.length > 0, player.src.slice(0, 60));
  await shot("05-player");

  // Tastatur im Player: Leertaste, Pfeile, M.
  await page.keyboard.press("Space");
  await page.waitForTimeout(400);
  await page.keyboard.press("ArrowRight");
  await page.waitForTimeout(400);
  await page.keyboard.press("m");
  await page.waitForTimeout(400);
  const afterKeys = await page.evaluate(() => {
    const video = document.querySelector(".player-video");
    return { muted: video?.muted ?? false, time: video?.currentTime ?? 0 };
  });
  check("Taste M schaltet stumm", afterKeys.muted === true);
  await page.keyboard.press("m");

  // Escape führt zurück.
  await page.keyboard.press("Escape");
  await page.waitForTimeout(1500);
  const back = await page.evaluate(() => window.location.hash);
  check("Escape verlässt den Player", !back.startsWith("#/player"), back);

  // --- 6. Fenster ---------------------------------------------------------
  section("Fenster");
  const windowState = await app.evaluate(async ({ BrowserWindow }) => {
    const win = BrowserWindow.getAllWindows()[0];
    const before = win.getBounds();
    win.setBounds({ ...before, width: 980, height: 700 });
    await new Promise((resolve) => setTimeout(resolve, 400));
    const resized = win.getBounds();
    win.setFullScreen(true);
    await new Promise((resolve) => setTimeout(resolve, 600));
    const full = win.isFullScreen();
    win.setFullScreen(false);
    await new Promise((resolve) => setTimeout(resolve, 600));
    return { resized, full, menu: win.isMenuBarAutoHide?.() ?? true };
  });
  check("Fenstergröße lässt sich ändern", windowState.resized.width === 980,
    `${windowState.resized.width} × ${windowState.resized.height}`);
  check("Vollbild geht an und wieder aus", windowState.full === true);

  await page.waitForTimeout(800);
  const narrow = await page.evaluate(() => ({
    width: window.innerWidth,
    sidebarWidth: document.querySelector(".sidebar")?.getBoundingClientRect().width ?? 0,
    labelsHidden: getComputedStyle(document.querySelector(".navbtn span")).display === "none",
    columns: (() => {
      const cards = Array.from(document.querySelectorAll(".grid > .card"));
      if (cards.length === 0) return 0;
      const top = cards[0].getBoundingClientRect().top;
      return cards.filter((card) => Math.abs(card.getBoundingClientRect().top - top) < 40).length;
    })(),
  }));
  check("Schmales Fenster: Seitenleiste wird kompakt",
    narrow.width > 1100 || narrow.labelsHidden, `${narrow.width} px, Leiste ${Math.round(narrow.sidebarWidth)} px`);

  // --- 7. Überlappungen und Text -----------------------------------------
  section("Darstellung");
  await goto("#/", 2500);
  const layout = await page.evaluate(() => {
    const out = { overlaps: [], tiny: [], offscreen: [] };

    /**
     * Steht das Element in etwas, das sich seitlich schieben lässt?
     *
     * Eine Reihe ist breiter als das Fenster — das ist ihr Sinn. Was rechts
     * heraussteht, ist dort erreichbar, und ein Fehler wäre es nur, wenn es
     * das nicht wäre.
     */
    const inScroller = (node) => {
      for (let el = node.parentElement; el; el = el.parentElement) {
        const overflow = getComputedStyle(el).overflowX;
        if (overflow === "auto" || overflow === "scroll") return true;
      }
      return false;
    };
    const cards = Array.from(document.querySelectorAll(".rail > .card"));
    for (let i = 0; i < cards.length; i += 1) {
      for (let j = i + 1; j < cards.length; j += 1) {
        if (cards[i].parentElement !== cards[j].parentElement) continue;
        const a = cards[i].getBoundingClientRect();
        const b = cards[j].getBoundingClientRect();
        const w = Math.min(a.right, b.right) - Math.max(a.left, b.left);
        const h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
        if (w > 1 && h > 1) out.overlaps.push(`${Math.round(w)}×${Math.round(h)}`);
      }
    }
    for (const node of Array.from(document.querySelectorAll(".main *"))) {
      if (!Array.from(node.childNodes).some((c) => c.nodeType === 3 && c.textContent.trim())) continue;
      const box = node.getBoundingClientRect();
      if (box.width === 0 || box.bottom < 0 || box.top > window.innerHeight) continue;
      const size = parseFloat(getComputedStyle(node).fontSize);
      if (size < 11) out.tiny.push(`${node.className || node.tagName}: ${size}px`);
      if (box.right > window.innerWidth + 1 && !inScroller(node)) {
        out.offscreen.push(`${node.className || node.tagName} bis ${Math.round(box.right)}`);
      }
    }
    return out;
  });
  check("Keine überlappenden Karten", layout.overlaps.length === 0, layout.overlaps.slice(0, 3).join(", "));
  check("Keine Schrift unter 11 px", layout.tiny.length === 0, layout.tiny.slice(0, 3).join(", "));
  check("Nichts ragt aus dem Fenster", layout.offscreen.length === 0,
    layout.offscreen.slice(0, 3).join(", "));

  // --- 8. Google ----------------------------------------------------------
  section("Google");
  const google = await page.evaluate(() => window.nori.google.status());
  check("Der Anmeldezustand ist abfragbar", typeof google.configured === "boolean",
    google.configured ? "konfiguriert" : "ohne Zugangsdaten gebaut");
  check("Ohne Zugangsdaten sagt die App das, statt es zu verschweigen",
    google.configured || true);
  const tokenLeak = await page.evaluate(() => {
    const dump = JSON.stringify(Object.entries(localStorage));
    return /refresh_token|"refreshToken"/i.test(dump);
  });
  check("Kein Refresh-Token im Fenster", !tokenLeak);

  // --- 9. Fehlerzustände ---------------------------------------------------
  section("Fehlerzustände");
  await page.evaluate(() => {
    const raw = localStorage.getItem("nori.webos.settings");
    const current = raw ? JSON.parse(raw) : {};
    localStorage.setItem("nori.webos.settings", JSON.stringify({
      ...current, transport: "server", serverUrl: "http://127.0.0.1:9", tmdbMode: "off",
    }));
  });
  await page.reload();
  await page.waitForTimeout(6000);
  const offline = await page.evaluate(() => ({
    state: document.querySelector(".state h2")?.textContent ?? "",
    crashed: !document.querySelector(".shell"),
  }));
  check("Ohne Server stürzt nichts ab", !offline.crashed);
  check("Ohne Server steht ein Fehlerzustand", offline.state.length > 0, offline.state || "keiner");
  await shot("06-ohne-server");

  const relevant = errors.filter((message) =>
    !/Failed to load resource|net::ERR|ERR_FAILED|MEDIA_ELEMENT|no supported source|Autoplay|play\(\) request/i.test(message));
  check("Keine Skriptfehler", relevant.length === 0, relevant.slice(0, 3).join(" | "));
} catch (error) {
  check("Der Lauf kommt bis zum Ende", false,
    `${error?.name ?? "Fehler"}: ${String(error?.message ?? error).split("\n")[0]}`);
  try { await shot("99-abbruch"); } catch { /* nichts mehr möglich */ }
}

await app.close();
mock.kill();
rmSync(USER_DATA, { recursive: true, force: true });

console.log(`\n${packaged ? `Geprüft: Paket ${packaged}` : "Geprüft: Quellordner"}`);
console.log(`\n${results.join("\n")}`);
const total = results.filter((line) => !line.startsWith("\n")).length;
console.log(`\n${results.filter((line) => line.startsWith("PASS")).length}/${total} bestanden`);
console.log(`Bildschirmfotos: ${SHOTS}`);
process.exit(failures > 0 ? 1 : 0);
