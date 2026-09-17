// Leistungsmessung der TV-Oberfläche — dieselbe Folge von Tastendrücken,
// zweimal vergleichbar.
//
// ## Warum ein eigener Lauf neben `remote-control.test.mjs`
//
// Der Fernbedienungslauf beantwortet „stimmt es". Dieser hier beantwortet „was
// kostet es". Beides in einem Lauf wäre falsch: Messwerte brauchen eine
// gedrosselte CPU und ein leeres Bild-Cache, und beides macht den
// Richtigkeitslauf nur langsam, nicht strenger.
//
// ## Was gemessen wird
//
// Gezählt wird im Browser selbst, nicht geschätzt. Vor jedem Skript der Seite
// werden die Zugriffe ersetzt, die auf einer Fernseher-CPU wehtun:
//
//     Element.getBoundingClientRect
//     window.getComputedStyle
//     HTMLElement.offsetWidth / offsetHeight / offsetParent
//
// Jeder Aufruf erhöht einen Zähler. Ein Tastendruck ist damit nicht mehr „fühlt
// sich träge an", sondern „283 Layoutabfragen". Dazu kommen die Bildabrufe mit
// ihrer TMDB-Stufe, die Knotenzahl, die Zahl fokussierbarer Elemente und die
// Dauer des Tastenhandlers.
//
// ## Wie vergleichbar gemessen wird
//
// - CPU gedrosselt (`Emulation.setCPUThrottlingRate`), voreingestellt 6× —
//   das ist die Größenordnung zwischen einem Entwicklerrechner und der CPU
//   eines Einstiegs-LG.
// - Kaltes Bild-Cache: jeder Lauf bekommt ein frisches Profil.
// - Großer Katalog über `NORI_MOCK_TITLES`.
//
// Voraussetzungen:
//
//     npm run build
//     NORI_MOCK_TITLES=400 node test/mock-server.mjs &
//     node test/perf-bench.mjs --label vorher --out test-perf/vorher.json
//
// Vergleich zweier Läufe:
//
//     node test/perf-bench.mjs --compare test-perf/vorher.json test-perf/nachher.json

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const APP = resolve(HERE, "..");
const BASE = process.env.NORI_MOCK ?? "http://127.0.0.1:8799";

const args = process.argv.slice(2);

function flag(name, fallback = null) {
  const index = args.indexOf(`--${name}`);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
}

// ---------------------------------------------------------------------------
// Vergleich zweier abgelegter Läufe

const ROWS = [
  ["domNodes", "DOM-Knoten (Startseite)", "niedriger"],
  ["focusables", "Fokussierbare Elemente", "info"],
  ["homeReadyMs", "Startseite steht nach", "niedriger"],
  ["bootLayoutReads", "Layoutabfragen bis dahin", "niedriger"],
  ["navReadsPerKey", "Layoutabfragen je Tastendruck", "niedriger"],
  ["navStyleReadsPerKey", "getComputedStyle je Tastendruck", "niedriger"],
  ["navSearchMedianMs", "Zielsuche Median", "niedriger"],
  ["navCalcMedianMs", "Fokusrechnung Median", "niedriger"],
  ["navCalcP95Ms", "Fokusrechnung 95. Perzentil", "niedriger"],
  ["navMedianMs", "Tastenhandler Median", "niedriger"],
  ["navP95Ms", "Tastenhandler 95. Perzentil", "niedriger"],
  ["navMaxMs", "Tastenhandler Maximum", "niedriger"],
  ["longTasks", "Aufgaben über 100 ms", "niedriger"],
  ["longTaskMs", "davon Summe in ms", "niedriger"],
  ["imageRequests", "Bildabrufe gesamt", "niedriger"],
  ["imagePixels", "Bildpixel gesamt (Mio.)", "niedriger"],
  ["largestImage", "Größtes Artwork (px Breite)", "niedriger"],
  ["catalogDomNodes", "DOM-Knoten (Katalog)", "niedriger"],
  ["catalogNavReadsPerKey", "Katalog: Layoutabfragen je Druck", "niedriger"],
  ["catalogNavMedianMs", "Katalog: Tastenhandler Median", "niedriger"],
  ["detailsDomNodes", "DOM-Knoten (Detailseite)", "niedriger"],
  ["jsHeapMb", "JS-Heap nach dem Lauf (MB)", "niedriger"],
];

function fmt(value) {
  if (value === null || value === undefined) return "—";
  if (typeof value !== "number") return String(value);
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

function compare(beforePath, afterPath) {
  const before = JSON.parse(readFileSync(beforePath, "utf8"));
  const after = JSON.parse(readFileSync(afterPath, "utf8"));
  const width = Math.max(...ROWS.map(([, label]) => label.length));
  const lines = [
    `Leistungsvergleich — ${before.label ?? "vorher"} → ${after.label ?? "nachher"}`,
    `CPU-Drosselung ${before.throttle}×, Katalog ${before.catalogTitles} Titel je Quelle`,
    "",
    `${"Messwert".padEnd(width)}  ${"vorher".padStart(10)}  ${"nachher".padStart(10)}  Änderung`,
    "-".repeat(width + 40),
  ];
  for (const [key, label, better] of ROWS) {
    const a = before.metrics[key];
    const b = after.metrics[key];
    let change = "";
    if (typeof a === "number" && typeof b === "number" && a !== 0) {
      const factor = b / a;
      const percent = (factor - 1) * 100;
      change = better === "info"
        ? `${percent >= 0 ? "+" : ""}${percent.toFixed(0)} %`
        : `${percent >= 0 ? "+" : ""}${percent.toFixed(0)} %${factor < 0.67 ? `  (${(1 / factor).toFixed(1)}× weniger)` : ""}`;
    }
    lines.push(`${label.padEnd(width)}  ${fmt(a).padStart(10)}  ${fmt(b).padStart(10)}  ${change}`);
  }
  console.log(lines.join("\n"));
}

const comparePair = args.indexOf("--compare");
if (comparePair >= 0) {
  compare(args[comparePair + 1], args[comparePair + 2]);
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Messlauf

let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  console.error("[Nori:webOS] playwright fehlt — npm i --no-save playwright");
  process.exit(127);
}

const LABEL = flag("label", "lauf");
const OUT = flag("out", join(APP, "test-perf", `${LABEL}.json`));
const THROTTLE = Number(flag("throttle", process.env.NORI_BENCH_THROTTLE ?? "6"));
const KEYS = Number(flag("keys", "40"));

/**
 * Zähler für Layoutabfragen, Bildabrufe und lange Aufgaben.
 *
 * Läuft als allererstes Skript der Seite, vor React und vor Nori — sonst
 * entginge ihm genau der Aufbau, der am meisten kostet.
 */
const PROBE = () => {
  const counters = {
    rects: 0, styles: 0, offsets: 0, longTasks: 0, longTaskMs: 0,
    images: [], marks: {},
  };
  window.__noriBench = counters;

  const rect = Element.prototype.getBoundingClientRect;
  Element.prototype.getBoundingClientRect = function patched() {
    counters.rects += 1;
    return rect.call(this);
  };
  const rects = Element.prototype.getClientRects;
  Element.prototype.getClientRects = function patched() {
    counters.rects += 1;
    return rects.call(this);
  };
  const computed = window.getComputedStyle.bind(window);
  window.getComputedStyle = function patched(node, pseudo) {
    counters.styles += 1;
    return computed(node, pseudo);
  };
  for (const name of ["offsetWidth", "offsetHeight", "offsetTop", "offsetLeft", "offsetParent"]) {
    const descriptor = Object.getOwnPropertyDescriptor(HTMLElement.prototype, name);
    if (!descriptor || !descriptor.get) continue;
    Object.defineProperty(HTMLElement.prototype, name, {
      configurable: true,
      get() {
        counters.offsets += 1;
        return descriptor.get.call(this);
      },
    });
  }
  for (const name of ["scrollWidth", "scrollHeight"]) {
    const descriptor = Object.getOwnPropertyDescriptor(Element.prototype, name);
    if (!descriptor || !descriptor.get) continue;
    Object.defineProperty(Element.prototype, name, {
      configurable: true,
      get() {
        counters.offsets += 1;
        return descriptor.get.call(this);
      },
    });
  }

  try {
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (entry.duration < 100) continue;
        counters.longTasks += 1;
        counters.longTaskMs += entry.duration;
      }
    }).observe({ entryTypes: ["longtask"] });
  } catch {
    /* ohne Long-Task-API bleibt die Zahl null */
  }
};

function tmdbSize(url) {
  const match = /\/t\/p\/([^/]+)\//.exec(url);
  if (!match) return null;
  const segment = match[1];
  if (segment === "original") return 2000;
  const wide = /^w(\d+)/.exec(segment);
  return wide ? Number(wide[1]) : 500;
}

const browser = await chromium.launch({
  executablePath: process.env.NORI_CHROMIUM || undefined,
  args: ["--no-sandbox", "--autoplay-policy=no-user-gesture-required"],
});

const context = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
await context.addInitScript(PROBE);
await context.addInitScript(([base, perfMode]) => {
  localStorage.setItem("nori.webos.settings", JSON.stringify({
    transport: "server", serverUrl: base, controlsTimeout: 4, seekStep: 10,
    autoplayCountdown: 3, tmdbMode: "server", tmdbKey: "", reduceEffects: false,
    performance: perfMode, debug: false,
  }));

  /*
   * Eine Bibliothek, wie sie nach ein paar Wochen aussieht.
   *
   * Ohne sie gäbe es weder „Weiterschauen" noch „Merkliste" noch „Für dich" —
   * und damit genau die drei Reihen nicht, die die Startseite groß machen.
   */
  const now = Date.now();
  const titles = [
    "frieren", "one-piece", "vinland-saga", "jujutsu-kaisen", "dandadan",
    "detektiv-conan", "pluto", "monster", "dark", "breaking-bad",
    "bocchi-the-rock", "steins-gate", "mushishi", "dexter", "fringe",
    "the-wire", "chainsaw-man", "ranking-of-kings", "odd-taxi", "kaiji",
  ];
  const progress = {};
  titles.slice(0, 12).forEach((slug, index) => {
    const path = `/anime/stream/${slug}/staffel-1/episode-${index + 1}`;
    progress[`aniworld|${path}`] = {
      slug,
      title: slug.replace(/-/g, " "),
      season: "1",
      episode: index + 1,
      episodePath: path,
      germanTitle: "Der Anfang",
      englishTitle: "The Beginning",
      positionSec: 400 + index * 37,
      durationSec: 1440,
      updatedAt: now - index * 3_600_000,
      provider: "aniworld",
    };
  });
  localStorage.setItem("nori.library", JSON.stringify({
    version: 6,
    modifiedAt: now,
    favorites: titles,
    recents: [],
    titles: Object.fromEntries(titles.map((slug) => [slug, slug.replace(/-/g, " ")])),
    progress,
    resumeEnabled: true,
    autoplayNext: true,
    scope: "all",
  }));
}, [BASE, flag("perf", "normal")]);

const page = await context.newPage();

const images = [];
const placeholder = readFileSync(join(APP, "public", "icon-400.png"));
await page.route("https://image.tmdb.org/**", async (route) => {
  const url = route.request().url();
  images.push({ url, width: tmdbSize(url) });
  await route.fulfill({ status: 200, contentType: "image/png", body: placeholder });
});

const cdp = await context.newCDPSession(page);
await cdp.send("Emulation.setCPUThrottlingRate", { rate: THROTTLE });

const KEY = { left: 37, up: 38, right: 39, down: 40, ok: 13 };

/** Eine Taste drücken und messen, was ihr Handler kostet. */
async function press(name, wait = 90) {
  const sample = await page.evaluate(([code, key]) => {
    const bench = window.__noriBench;
    const before = { rects: bench.rects, styles: bench.styles, offsets: bench.offsets };
    const target = document.activeElement ?? document.body;
    const event = new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true });
    Object.defineProperty(event, "keyCode", { get: () => code });
    Object.defineProperty(event, "which", { get: () => code });
    const start = performance.now();
    target.dispatchEvent(event);
    const duration = performance.now() - start;
    return {
      ms: duration,
      navMs: window.__noriNav ? window.__noriNav.lastMs : null,
      searchMs: window.__noriNav ? window.__noriNav.searchMs : null,
      rects: bench.rects - before.rects,
      styles: bench.styles - before.styles,
      offsets: bench.offsets - before.offsets,
    };
  }, [KEY[name], name === "ok" ? "Enter" : `Arrow${name[0].toUpperCase()}${name.slice(1)}`]);
  if (wait > 0) await page.waitForTimeout(wait);
  return sample;
}

function stats(list) {
  if (list.length === 0) return { median: 0, p95: 0, max: 0, mean: 0 };
  const sorted = [...list].sort((a, b) => a - b);
  return {
    median: sorted[Math.floor(sorted.length / 2)],
    p95: sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.95))],
    max: sorted[sorted.length - 1],
    mean: sorted.reduce((sum, value) => sum + value, 0) / sorted.length,
  };
}

async function snapshot() {
  return page.evaluate(() => ({
    nodes: document.getElementsByTagName("*").length,
    focusables: document.querySelectorAll(".spottable").length,
    imgs: document.querySelectorAll(".art img").length,
    rails: document.querySelectorAll(".rail-section").length,
    bench: {
      rects: window.__noriBench.rects,
      styles: window.__noriBench.styles,
      offsets: window.__noriBench.offsets,
      longTasks: window.__noriBench.longTasks,
      longTaskMs: window.__noriBench.longTaskMs,
    },
    nav: window.__noriNav ? { ...window.__noriNav } : null,
  }));
}

const started = Date.now();
await page.goto(BASE, { waitUntil: "domcontentloaded" });

// „Startseite steht": die erste Reihe mit echten Karten ist gezeichnet.
await page.waitForFunction(() => document.querySelectorAll(".rail-section .poster-card, .rail-section .land-card").length > 0, null, { timeout: 60_000 });
const homeReadyMs = Date.now() - started;
// Danach noch die TMDB-Nachträge abwarten, damit jeder Lauf denselben Stand misst.
await page.waitForTimeout(6000);

const home = await snapshot();

// --- Fernbedienung auf der Startseite ---------------------------------------
await page.evaluate(() => document.querySelector('[data-focus-key="hero-play"]')?.focus());
await page.waitForTimeout(400);

const sequence = [
  ...Array.from({ length: 6 }, () => "down"),
  ...Array.from({ length: 20 }, () => "right"),
  ...Array.from({ length: 6 }, () => "up"),
  ...Array.from({ length: 8 }, () => "left"),
].slice(0, KEYS);

const navSamples = [];
for (const step of sequence) navSamples.push(await press(step));
const navMs = stats(navSamples.map((sample) => sample.ms));
const navCalc = stats(navSamples.map((sample) => sample.navMs).filter((value) => typeof value === "number"));
const navSearch = stats(navSamples.map((sample) => sample.searchMs).filter((value) => typeof value === "number"));
const navReads = navSamples.reduce((sum, s) => sum + s.rects + s.offsets, 0) / navSamples.length;
const navStyles = navSamples.reduce((sum, s) => sum + s.styles, 0) / navSamples.length;

// --- Katalog ----------------------------------------------------------------
await page.evaluate(() => { window.location.hash = "#/katalog"; });
await page.waitForTimeout(7000);
const catalog = await snapshot();
const catalogSamples = [];
for (const step of [
  ...Array.from({ length: 8 }, () => "right"),
  ...Array.from({ length: 4 }, () => "down"),
  ...Array.from({ length: 8 }, () => "left"),
  ...Array.from({ length: 4 }, () => "up"),
]) catalogSamples.push(await press(step));
const catalogMs = stats(catalogSamples.map((sample) => sample.ms));
const catalogReads = catalogSamples.reduce((sum, s) => sum + s.rects + s.offsets, 0) / catalogSamples.length;

// --- Detailseite ------------------------------------------------------------
await page.evaluate(() => {
  const card = document.querySelector(".catalog-grid .spottable");
  if (card) card.click();
});
await page.waitForTimeout(6000);
const details = await snapshot();

const heap = await page.evaluate(() => (performance.memory ? performance.memory.usedJSHeapSize : null));

const metrics = {
  domNodes: home.nodes,
  focusables: home.focusables,
  rails: home.rails,
  homeReadyMs,
  bootLayoutReads: home.bench.rects + home.bench.offsets,
  bootStyleReads: home.bench.styles,
  navReadsPerKey: Math.round(navReads),
  navSearchMedianMs: navSearch.median,
  navSearchP95Ms: navSearch.p95,
  navCalcMedianMs: navCalc.median,
  navCalcP95Ms: navCalc.p95,
  navStyleReadsPerKey: Math.round(navStyles),
  navMedianMs: navMs.median,
  navP95Ms: navMs.p95,
  navMaxMs: navMs.max,
  navMeanMs: navMs.mean,
  longTasks: details.bench.longTasks,
  longTaskMs: Math.round(details.bench.longTaskMs),
  imageRequests: images.length,
  imagePixels: Number((images.reduce((sum, img) => sum + (img.width ?? 0) * (img.width ?? 0) * 0.5, 0) / 1e6).toFixed(1)),
  largestImage: images.reduce((max, img) => Math.max(max, img.width ?? 0), 0),
  catalogDomNodes: catalog.nodes,
  catalogFocusables: catalog.focusables,
  catalogNavReadsPerKey: Math.round(catalogReads),
  catalogNavMedianMs: catalogMs.median,
  catalogNavP95Ms: catalogMs.p95,
  detailsDomNodes: details.nodes,
  jsHeapMb: heap === null ? null : Number((heap / 1e6).toFixed(1)),
  navCounters: details.nav,
};

const payload = {
  label: LABEL,
  at: new Date().toISOString(),
  throttle: THROTTLE,
  catalogTitles: Number(process.env.NORI_MOCK_TITLES ?? 40),
  keys: sequence.length,
  metrics,
};

mkdirSync(dirname(resolve(OUT)), { recursive: true });
writeFileSync(resolve(OUT), `${JSON.stringify(payload, null, 2)}\n`, "utf8");

const width = Math.max(...ROWS.map(([, label]) => label.length));
console.log(`\nLeistungsmessung „${LABEL}" — CPU ${THROTTLE}×, Katalog ${payload.catalogTitles} Titel je Quelle\n`);
for (const [key, label] of ROWS) {
  console.log(`${label.padEnd(width)}  ${fmt(metrics[key]).padStart(10)}`);
}
if (metrics.navCounters) console.log(`\nZähler der Navigation: ${JSON.stringify(metrics.navCounters)}`);
console.log(`\nAbgelegt: ${resolve(OUT)}`);

await browser.close();
