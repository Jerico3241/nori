// Fernbedienungsprüfung im echten Browser.
//
// Warum mit Tastencodes statt mit Mausklicks: was auf dem Fernseher passiert,
// entscheidet die Fernbedienung. Ein Test, der klickt, prüft einen Weg, den es
// dort nicht gibt — und übersieht genau die Fehler, die auf einem Fernseher
// wehtun: ein Element ohne Fokus, ein Fokus, der halb über dem Bildrand hängt,
// eine Zurück-Taste, die zu weit springt. Geklickt wird hier nur, um einen
// Zustand herzustellen, nie, um eine Bedienung zu prüfen.
//
// Was der Lauf **nicht** ist: ein Beweis, dass Nori auf einem LG-Fernseher
// läuft. Er prüft dieselbe gebaute Datei in Chromium mit echten
// LG-Tastencodes, bei 1920 × 1080 und getrennt bei 3840 × 2160. Die Wiedergabe
// eines echten HLS-Streams, der Systemplayer von webOS und die Magic Remote
// entscheiden sich erst auf dem Gerät.
//
// Voraussetzungen:
//
//     npm run build
//     node test/mock-server.mjs &
//     npm i --no-save playwright && npx playwright install chromium
//     node test/remote-control.test.mjs
//
// NORI_CHROMIUM setzt den Browser, NORI_SHOTS den Ordner der Bildschirmfotos.

import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  console.error(
    "[Nori:webOS] playwright fehlt.\n"
    + "  npm i --no-save playwright && npx playwright install chromium\n"
    + "Ein bereits vorhandener Chromium lässt sich über NORI_CHROMIUM angeben.",
  );
  process.exit(127);
}

const HERE = dirname(fileURLToPath(import.meta.url));
const APP = resolve(HERE, "..");
const BASE = process.env.NORI_MOCK ?? "http://127.0.0.1:8799";
const SHOTS = resolve(process.env.NORI_SHOTS ?? join(APP, "test-shots"));
if (!existsSync(SHOTS)) mkdirSync(SHOTS, { recursive: true });

/** Aus dem Kern, nicht abgeschrieben — sonst läuft die Zahl auseinander. */
const { LIBRARY_SCHEMA_VERSION } = await import("@nori/core");
const APP_VERSION = JSON.parse(readFileSync(join(APP, "appinfo.json"), "utf8")).version;

const results = [];
let failures = 0;

function check(name, ok, detail = "") {
  results.push(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures += 1;
}

function section(name) {
  results.push(`\n— ${name} ${"—".repeat(Math.max(0, 62 - name.length))}`);
}

const KEY = {
  left: [37, "ArrowLeft"], up: [38, "ArrowUp"], right: [39, "ArrowRight"],
  down: [40, "ArrowDown"], ok: [13, "Enter"], back: [461, "GoBack"],
  backAlt: [10009, "GoBack"],
  play: [415, "MediaPlay"], pause: [19, "MediaPause"], stop: [413, "MediaStop"],
  rewind: [412, "MediaRewind"], forward: [417, "MediaFastForward"],
};

/** Eine Taste der Fernbedienung. `wait` in Millisekunden danach. */
async function remote(page, name, wait = 280) {
  const [code, key] = KEY[name];
  await page.evaluate(([c, k]) => {
    const target = document.activeElement ?? document.body;
    for (const type of ["keydown", "keyup"]) {
      const event = new KeyboardEvent(type, { key: k, bubbles: true, cancelable: true });
      Object.defineProperty(event, "keyCode", { get: () => c });
      Object.defineProperty(event, "which", { get: () => c });
      target.dispatchEvent(event);
    }
  }, [code, key]);
  if (wait > 0) await page.waitForTimeout(wait);
}

async function focused(page) {
  return page.evaluate(() => {
    const el = document.activeElement;
    if (!el || el === document.body) return null;
    return {
      key: el.getAttribute("data-focus-key"),
      cls: String(el.className),
      text: (el.textContent ?? "").trim().slice(0, 40),
    };
  });
}

async function focusKey(page, key) {
  await page.evaluate((k) => document.querySelector(`[data-focus-key="${k}"]`)?.focus(), key);
  await page.waitForTimeout(320);
}

async function goto(page, hash, wait = 1800) {
  await page.evaluate((target) => { window.location.hash = target; }, hash);
  await page.waitForTimeout(wait);
}

async function shot(page, name) {
  await page.screenshot({ path: join(SHOTS, `${name}.png`) });
}

/**
 * Ist das fokussierte Element vollständig sichtbar — samt Wachstum und Ring?
 *
 * Geprüft gegen den Bildschirm, gegen jeden Vorfahren, der abschneidet
 * (Reihen, Scrollbereiche, Dialoge), und gegen die Seitenleiste.
 */
async function focusVisibility(page) {
  return page.evaluate(() => {
    const el = document.activeElement;
    if (!el || el === document.body) return { ok: false, reason: "kein Fokus" };
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) return { ok: false, reason: "Fokus auf unsichtbarem Element" };
    const ring = parseFloat(getComputedStyle(document.documentElement).fontSize) * 0.625;
    const box = { left: r.left - ring, top: r.top - ring, right: r.right + ring, bottom: r.bottom + ring };
    const W = window.innerWidth;
    const H = window.innerHeight;
    if (box.left < -1 || box.top < -1 || box.right > W + 1 || box.bottom > H + 1) {
      return { ok: false, reason: `außerhalb des Bildes ${Math.round(box.left)},${Math.round(box.top)},${Math.round(box.right)},${Math.round(box.bottom)}` };
    }
    for (let parent = el.parentElement; parent && parent !== document.body; parent = parent.parentElement) {
      const style = getComputedStyle(parent);
      if (style.overflowX === "visible" && style.overflowY === "visible") continue;
      const p = parent.getBoundingClientRect();
      const tolerance = 1.5;
      if (box.left < p.left - tolerance || box.right > p.right + tolerance
        || box.top < p.top - tolerance || box.bottom > p.bottom + tolerance) {
        // Der Ring darf den Rand eines Scrollbereichs berühren, das Element selbst nicht.
        const hard = r.left < p.left - tolerance || r.right > p.right + tolerance
          || r.top < p.top - tolerance || r.bottom > p.bottom + tolerance;
        return { ok: false, reason: `${hard ? "abgeschnitten" : "Ring abgeschnitten"} von .${String(parent.className).split(" ")[0]} (${Math.round(r.top)}–${Math.round(r.bottom)} in ${Math.round(p.top)}–${Math.round(p.bottom)})` };
      }
    }
    const sidebar = document.querySelector(".sidebar");
    if (sidebar && !sidebar.contains(el)) {
      const s = sidebar.getBoundingClientRect();
      if (r.left < s.right - 1) return { ok: false, reason: "unter der Seitenleiste" };
    }
    const trap = Array.from(document.querySelectorAll("[data-focus-trap]")).pop();
    if (trap && !trap.contains(el)) return { ok: false, reason: "Fokus hinter einem offenen Overlay" };
    // Lesbarkeit im Fokus: Schrift gegen eine deckende Fläche.
    const style = getComputedStyle(el);
    const parse = (v) => (/rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?/.exec(v) ?? []).slice(1).map(Number);
    const [br, bg, bb, ba = 1] = parse(style.backgroundColor);
    if (ba >= 0.99 && !Number.isNaN(br)) {
      const lum = (r, g, b) => [r, g, b].map((v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; })
        .reduce((sum, c, i) => sum + c * [0.2126, 0.7152, 0.0722][i], 0);
      const [cr, cg, cb] = parse(style.color);
      const a = lum(br, bg, bb);
      const b = lum(cr, cg, cb);
      const ratio = (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
      if (ratio < 4.5) return { ok: false, reason: `Kontrast im Fokus ${ratio.toFixed(1)}:1 (${style.color} auf ${style.backgroundColor})` };
    }
    return { ok: true, reason: "" };
  });
}

/** Eine Tastenfolge, nach jedem Druck Fokus und Sichtbarkeit prüfen. */
async function stress(page, label, sequence, wait = 280) {
  const problems = [];
  for (const [index, step] of sequence.entries()) {
    await remote(page, step, wait);
    const state = await focusVisibility(page);
    if (!state.ok) {
      const f = await focused(page);
      problems.push(`#${index + 1} ${step}: ${state.reason} [${f?.key ?? "-"}]`);
    }
  }
  check(`${label}: Fokus nach jedem Druck vollständig sichtbar`, problems.length === 0,
    problems.length ? problems.slice(0, 3).join(" | ") : `${sequence.length} Drücke`);
}

const repeat = (step, count) => Array.from({ length: count }, () => step);
const MATRIX = [...repeat("right", 10), ...repeat("left", 10), ...repeat("down", 10), ...repeat("up", 10),
  "right", "right", "down", "right", "down", "left", "up"];

/** Überlappungen, Flex-`gap`, Textgrößen und abgeschnittene Titel einer Ansicht. */
async function layoutAudit(page, label, minFontPx) {
  const audit = await page.evaluate(() => {
    const out = { flexGap: [], overlaps: [], small: [], truncated: 0, sidebarOverlap: false };
    const shell = document.querySelector(".app-shell") ?? document.body;
    const nodes = Array.from(shell.querySelectorAll("*")).slice(0, 6000);
    for (const node of nodes) {
      const style = getComputedStyle(node);
      if ((style.display === "flex" || style.display === "inline-flex")
        && ((style.columnGap !== "normal" && style.columnGap !== "0px") || (style.rowGap !== "normal" && style.rowGap !== "0px"))) {
        out.flexGap.push(String(node.className).split(" ")[0] || node.tagName);
      }
    }
    const sidebar = document.querySelector(".sidebar")?.getBoundingClientRect();
    const screen = document.querySelector(".screen")?.getBoundingClientRect();
    if (sidebar && screen && sidebar.right > screen.left + 1) out.sidebarOverlap = true;

    const focusedEl = document.activeElement;
    const boxes = (selector) => Array.from(document.querySelectorAll(selector))
      .filter((el) => el !== focusedEl && !el.contains(focusedEl))
      .map((el) => ({ el, r: el.getBoundingClientRect() }))
      .filter(({ r }) => r.width > 0 && r.height > 0);

    // Karten in einer Reihe und im Raster überdecken sich nicht.
    for (const selector of [".rail-inner > .poster-card, .rail-inner > .land-card", ".catalog-grid > .poster-card", ".episode-grid .ep-card", ".release-list > .release", ".weekstrip > .day"]) {
      const list = boxes(selector);
      for (let i = 0; i < list.length; i += 1) {
        for (let j = i + 1; j < list.length; j += 1) {
          const a = list[i].r;
          const b = list[j].r;
          const w = Math.min(a.right, b.right) - Math.max(a.left, b.left);
          const h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
          if (w > 1 && h > 1 && list[i].el.parentElement === list[j].el.parentElement) {
            out.overlaps.push(`${selector.split(" ")[0]} ${Math.round(w)}×${Math.round(h)}`);
          }
        }
      }
    }
    // Hero vor der ersten Reihe, jede Reihe vor der nächsten Überschrift.
    const hero = document.querySelector(".hero");
    const heads = Array.from(document.querySelectorAll(".screen .section-head"));
    if (hero && heads[0] && heads[0].getBoundingClientRect().top < hero.getBoundingClientRect().bottom - 1) {
      out.overlaps.push("Hero über der ersten Überschrift");
    }
    const rails = Array.from(document.querySelectorAll(".rail-section"));
    for (let i = 0; i + 1 < rails.length; i += 1) {
      const cards = Array.from(rails[i].querySelectorAll(".card-sub, .card-title")).filter((c) => !c.closest(":focus"));
      const bottom = Math.max(0, ...cards.map((c) => c.getBoundingClientRect().bottom));
      const nextHead = rails[i + 1].querySelector(".section-head");
      if (nextHead && bottom > nextHead.getBoundingClientRect().top + 1) out.overlaps.push(`Reihe ${i + 1} über Überschrift ${i + 2}`);
    }
    // Kleinste sichtbare Schrift im Inhalt.
    for (const node of Array.from(document.querySelectorAll(".screen *, .sidebar .navbtn, .sidebar .brand"))) {
      if (!node.childNodes.length || !Array.from(node.childNodes).some((c) => c.nodeType === 3 && c.textContent.trim())) continue;
      const r = node.getBoundingClientRect();
      if (r.width === 0 || r.bottom < 0 || r.top > window.innerHeight) continue;
      const size = parseFloat(getComputedStyle(node).fontSize);
      out.small.push(size);
    }
    for (const title of Array.from(document.querySelectorAll(".card-title, .ep-title, .rel-title"))) {
      if (title.scrollHeight > title.clientHeight + 2 || title.scrollWidth > title.clientWidth + 2) out.truncated += 1;
    }
    return { ...out, minFont: out.small.length ? Math.min(...out.small) : null };
  });
  check(`${label}: kein Flex-Container mit gap (webOS 6)`, audit.flexGap.length === 0, audit.flexGap.slice(0, 4).join(", "));
  check(`${label}: Seitenleiste überdeckt keinen Inhalt`, !audit.sidebarOverlap);
  check(`${label}: keine Überlappungen`, audit.overlaps.length === 0, audit.overlaps.slice(0, 4).join(" | "));
  check(`${label}: kleinste Schrift ≥ ${minFontPx} px`, audit.minFont === null || audit.minFont >= minFontPx - 0.01, `${audit.minFont} px`);
  check(`${label}: keine abgeschnittenen Titel`, audit.truncated === 0, `${audit.truncated} Titel`);
}

function luminance([r, g, b]) {
  const c = [r, g, b].map((v) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

function rgb(value) {
  const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(value ?? "");
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : [0, 0, 0];
}

function contrast(a, b) {
  const la = luminance(rgb(a));
  const lb = luminance(rgb(b));
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

async function newTvPage(browser, width, height, { settings = true } = {}) {
  const page = await browser.newPage({ viewport: { width, height } });
  const placeholder = readFileSync(join(APP, "public", "icon-400.png"));
  await page.route("https://image.tmdb.org/**", (route) =>
    route.fulfill({ status: 200, contentType: "image/png", body: placeholder }));
  if (settings) {
    await page.addInitScript((base) => {
      if (!localStorage.getItem("nori.webos.settings")) {
        localStorage.setItem("nori.webos.settings", JSON.stringify({
          transport: "server", serverUrl: base, controlsTimeout: 4, seekStep: 10,
          autoplayCountdown: 3, tmdbMode: "server", tmdbKey: "", reduceEffects: false, debug: true,
        }));
      }
    }, BASE);
  }
  return page;
}

let crashed = null;
const browser = await chromium.launch({
  executablePath: process.env.NORI_CHROMIUM || undefined,
  args: ["--no-sandbox", "--autoplay-policy=no-user-gesture-required"],
});
const page = await newTvPage(browser, 1920, 1080);
const consoleErrors = [];
page.on("console", (msg) => { if (msg.type() === "error") consoleErrors.push(msg.text()); });
page.on("pageerror", (err) => consoleErrors.push(`pageerror: ${err.message}`));

try {
  await page.goto(BASE, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(5500);

  // --- 1. Startseite --------------------------------------------------------
  section("Startseite · 1920 × 1080");

  const hero = await page.evaluate(() => {
    const node = document.querySelector(".hero-home");
    return node ? {
      title: node.querySelector(".hero-logo")?.getAttribute("alt") ?? node.querySelector(".hero-title")?.textContent ?? "",
      height: Math.round(node.getBoundingClientRect().height),
      meta: node.querySelector(".meta")?.textContent ?? "",
      text: node.querySelector(".hero-text")?.textContent ?? "",
      actions: Array.from(node.querySelectorAll(".hero-actions button")).map((b) => b.textContent.trim()),
    } : null;
  });
  check("Hero mit echtem Katalogtitel", Boolean(hero?.title), hero?.title ?? "kein Hero");
  check("Hero ohne Demo-Titel aus der Vorlage", !/Yoruka|Crimson Veil|Azure Signal|Moonlit|Falling Ember|Night Protocol|Verdant/.test(JSON.stringify(hero)));
  check("Hero groß (≥ 480 px)", (hero?.height ?? 0) >= 480, `${hero?.height} px`);
  check("Hero: Jahr, Genres, Bewertung", /\d{4}/.test(hero?.meta ?? "") && (hero?.meta ?? "").includes("★"), hero?.meta ?? "-");
  check("Hero: Beschreibung", (hero?.text.length ?? 0) > 20);
  check("Hero: Jetzt ansehen · Merkliste · Mehr",
    hero?.actions.some((a) => a.includes("ansehen")) && hero?.actions.some((a) => a.includes("Merkliste") || a.includes("Gemerkt")) && hero?.actions.some((a) => a.includes("Mehr")),
    hero?.actions.join(" | "));

  const start = await focused(page);
  check("Startfokus auf „Jetzt ansehen“", start?.key === "hero-play", start?.key ?? "-");

  const ALLOWED_RAILS = ["Weiterschauen", "Neu & beliebt", "Neu im Katalog", "Neue Episoden", "Für dich", "Entdecke etwas Neues", "Merkliste"];
  const railTitles = await page.$$eval("[data-rail] .section-head h2", (els) => els.map((e) => e.textContent?.trim()));
  check("Reihen mit vorgesehenen Namen", railTitles.length >= 2 && railTitles.every((t) => ALLOWED_RAILS.includes(t ?? "")), railTitles.join(", "));
  check("„Neu & beliebt“ aus TMDB-Signalen", railTitles.includes("Neu & beliebt"), railTitles.join(", "));

  // Sidebar und Marke.
  const sidebar = await page.evaluate(() => {
    const aside = document.querySelector(".sidebar");
    const brand = aside?.querySelector(".brand");
    const links = Array.from(aside?.querySelectorAll(".navbtn") ?? []);
    const top = links[0]?.getBoundingClientRect().top ?? 0;
    const bottom = links[links.length - 1]?.getBoundingClientRect().bottom ?? 0;
    return {
      brandText: brand?.textContent?.trim(),
      brandImages: brand?.querySelectorAll("img, svg").length ?? -1,
      brandLeft: brand?.getBoundingClientRect().left ?? -1,
      brandTop: brand?.getBoundingClientRect().top ?? -1,
      labels: links.map((l) => l.textContent.trim()),
      center: (top + bottom) / 2,
      width: aside?.getBoundingClientRect().width ?? 0,
    };
  });
  check("Oben links steht nur „Nori“", sidebar.brandText === "Nori" && sidebar.brandImages === 0, `${sidebar.brandText}, ${sidebar.brandImages} Bilder`);
  check("Marke oben links in der Safe Area", sidebar.brandLeft >= 24 && sidebar.brandTop >= 40 && sidebar.brandTop < 120, `${Math.round(sidebar.brandLeft)}/${Math.round(sidebar.brandTop)}`);
  check("Navigation: Start · Katalog · Kalender · Merkliste · Mehr", sidebar.labels.join("|") === "Start|Katalog|Kalender|Merkliste|Mehr", sidebar.labels.join("|"));
  check("Navigation vertikal zentriert", Math.abs(sidebar.center - 540) < 8, `Mitte ${Math.round(sidebar.center)}`);
  check("Seitenleiste schmal (≤ 260 px)", sidebar.width <= 260, `${Math.round(sidebar.width)} px`);

  const palette = await page.evaluate(() => {
    const style = getComputedStyle(document.documentElement);
    return { bg: style.getPropertyValue("--bg").trim(), accent: style.getPropertyValue("--accent").trim(), focus: style.getPropertyValue("--focus").trim() };
  });
  check("Farben aus V4", palette.bg === "#03070d" && palette.accent === "#79c7ff" && palette.focus === "#eef8ff", JSON.stringify(palette));

  const orange = await page.evaluate(() => {
    const isOrange = (value) => {
      const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(value ?? "");
      if (!m) return false;
      const [r, g, b] = [Number(m[1]), Number(m[2]), Number(m[3])];
      return r > 170 && b < 110 && g > 60 && g < 190 && r - b > 90;
    };
    const out = [];
    for (const node of Array.from(document.querySelectorAll(".app-shell *")).slice(0, 3000)) {
      if (node.tagName === "IMG") continue;
      const s = getComputedStyle(node);
      for (const p of ["color", "backgroundColor", "borderTopColor"]) if (isOrange(s[p])) out.push(`${node.className}.${p}`);
    }
    return out.slice(0, 5);
  });
  check("Kein oranges Branding", orange.length === 0, orange.join(" | "));

  // Kontrast des Merkliste-Knopfs — normal und im Fokus.
  const favNormal = await page.evaluate(() => {
    const b = document.querySelector('[data-focus-key="hero-favorite"]');
    const s = getComputedStyle(b);
    return { color: s.color, bg: s.backgroundColor };
  });
  await remote(page, "right");
  const favFocus = await page.evaluate(() => {
    const b = document.activeElement;
    const s = getComputedStyle(b);
    return { key: b.getAttribute("data-focus-key"), color: s.color, bg: s.backgroundColor };
  });
  check("Merkliste-Knopf normal: helle Schrift auf dunklem Grund",
    luminance(rgb(favNormal.color)) > 0.8 && luminance(rgb(favNormal.bg)) < 0.1 && contrast(favNormal.color, favNormal.bg) >= 7,
    `${favNormal.color} auf ${favNormal.bg}, ${contrast(favNormal.color, favNormal.bg).toFixed(1)}:1`);
  check("Merkliste-Knopf im Fokus: dunkle Schrift auf hellem Grund",
    favFocus.key === "hero-favorite" && luminance(rgb(favFocus.bg)) > 0.8 && luminance(rgb(favFocus.color)) < 0.05 && contrast(favFocus.color, favFocus.bg) >= 7,
    `${favFocus.color} auf ${favFocus.bg}, ${contrast(favFocus.color, favFocus.bg).toFixed(1)}:1`);
  await shot(page, "01-start-hero");

  const focusStyle = await page.evaluate(() => {
    const s = getComputedStyle(document.activeElement);
    return { transform: s.transform, shadow: s.boxShadow };
  });
  check("Fokus: Vergrößerung und Ring", focusStyle.transform !== "none" && focusStyle.shadow !== "none", `${focusStyle.transform} / ${focusStyle.shadow.slice(0, 40)}`);

  await remote(page, "left");
  await layoutAudit(page, "Startseite", 13);

  // Hero → erste Reihe: Überschrift sichtbar, Karte ganz.
  await remote(page, "down");
  const firstRail = await page.evaluate(() => {
    const el = document.activeElement;
    const head = el.closest("[data-rail]")?.querySelector(".section-head h2");
    return { key: el.getAttribute("data-focus-key"), rail: el.closest("[data-rail]")?.getAttribute("data-rail"), headTop: head?.getBoundingClientRect().top ?? -1 };
  });
  check("Hero ↓ erste Reihe", Boolean(firstRail.rail), `${firstRail.rail} / ${firstRail.key}`);
  check("Hero ↓: Überschrift der Reihe sichtbar", firstRail.headTop >= 0, `${Math.round(firstRail.headTop)} px`);
  const vis1 = await focusVisibility(page);
  check("Hero ↓: Karte vollständig sichtbar", vis1.ok, vis1.reason);
  await shot(page, "02-start-neu-beliebt-erste");

  // Erste Karte + links → Seitenleiste auf dem aktiven Eintrag.
  await remote(page, "left");
  const intoNav = await focused(page);
  check("Erste Karte ← führt in die Seitenleiste (aktiver Eintrag)", intoNav?.key === "nav-start", intoNav?.key ?? "-");
  await remote(page, "right");
  const backFromNav = await focused(page);
  check("Seitenleiste → zurück auf dieselbe Karte", backFromNav?.key === firstRail.key, `${backFromNav?.key}`);

  // Reihe entlang: Spur scrollt mit, Karte bleibt ganz.
  for (let i = 0; i < 6; i += 1) await remote(page, "right");
  const railScroll = await page.evaluate(() => {
    const el = document.activeElement;
    const track = el.closest("[data-scroll-x]");
    const r = el.getBoundingClientRect();
    const t = track.getBoundingClientRect();
    return { key: el.getAttribute("data-focus-key"), scrollLeft: track.scrollLeft, inside: r.left >= t.left && r.right <= t.right };
  });
  check("Reihe → → →: Spur scrollt mit", railScroll.scrollLeft > 0, `scrollLeft ${Math.round(railScroll.scrollLeft)}`);
  check("Reihe: siebte Karte ganz innerhalb der Spur", railScroll.inside, railScroll.key);
  await shot(page, "03-start-weit-rechts");
  const seventh = railScroll.key;

  // Letzte Karte + rechts bleibt stehen.
  for (let i = 0; i < 25; i += 1) await remote(page, "right", 60);
  await page.waitForTimeout(400);
  const last = await focused(page);
  await remote(page, "right");
  const stillLast = await focused(page);
  check("Letzte Karte → bleibt auf der letzten Karte", last?.key === stillLast?.key, `${last?.key}`);
  const lastVis = await focusVisibility(page);
  check("Letzte Karte vollständig sichtbar", lastVis.ok, lastVis.reason);

  // Schnell hintereinander, ohne Pause: am Anfang der Reihe führt „links" in
  // die Seitenleiste, und dort bleibt der Fokus stehen, egal wie oft.
  for (let i = 0; i < 25; i += 1) await remote(page, "left", 0);
  await page.waitForTimeout(500);
  const railStart = await focused(page);
  check("Schnelle Eingabe: 25× ← ohne Pause endet in der Seitenleiste auf „Start“", railStart?.key === "nav-start", railStart?.key ?? "-");
  await remote(page, "right", 400);
  const firstAgain = await page.evaluate(() => Array.from(document.activeElement.closest(".rail-inner")?.children ?? []).indexOf(document.activeElement));
  check("→ aus der Seitenleiste: zurück auf die erste Karte", firstAgain === 0, `Index ${firstAgain}`);
  for (let i = 0; i < 5; i += 1) await remote(page, "right", 25);
  await page.waitForTimeout(600);
  const fastTarget = await page.evaluate(() => {
    const el = document.activeElement;
    const cards = Array.from(el.closest(".rail-inner").children);
    return { index: cards.indexOf(el), key: el.getAttribute("data-focus-key") };
  });
  check("Schnelle Eingabe: 5× → im 25-ms-Takt landet genau fünf Karten weiter", fastTarget.index === 5, `Index ${fastTarget.index}`);
  const fastVis = await focusVisibility(page);
  check("Schnelle Eingabe: Karte vollständig sichtbar", fastVis.ok, fastVis.reason);

  await stress(page, "Startseite Matrix →×10 ←×10 ↓×10 ↑×10 + Kombination", MATRIX);

  // Das alte Problem: beim Weiter-nach-unten wurde die gewählte Karte über den
  // oberen Rand gezogen. Jetzt nach jedem Schritt: Karte ganz, Überschrift da.
  await focusKey(page, "hero-play");
  const downProblems = [];
  for (let i = 0; i < 8; i += 1) {
    await remote(page, "down");
    const s = await page.evaluate(() => {
      const el = document.activeElement;
      const r = el.getBoundingClientRect();
      const head = el.closest("[data-rail]")?.querySelector(".section-head h2")?.getBoundingClientRect();
      return { key: el.getAttribute("data-focus-key"), top: r.top, headTop: head ? head.top : null };
    });
    if (s.top < 40) downProblems.push(`${s.key} oben bei ${Math.round(s.top)} px`);
    if (s.headTop !== null && s.headTop < 0) downProblems.push(`Überschrift von ${s.key} über dem Rand`);
  }
  for (let i = 0; i < 8; i += 1) {
    await remote(page, "up");
    const s = await page.evaluate(() => document.activeElement.getBoundingClientRect().top);
    if (s < 40) downProblems.push(`↑ oben bei ${Math.round(s)} px`);
  }
  check("Altes Startseiten-Clipping nicht reproduzierbar (↓×8, ↑×8)", downProblems.length === 0, downProblems.slice(0, 3).join(" | "));
  // Achtmal hoch bei zwei Reihen: über den Hero hinaus bis in den Seitenkopf,
  // und dort bleibt er — die Seite steht ganz oben.
  const backAtHero = await page.evaluate(() => ({ key: document.activeElement.getAttribute("data-focus-key"), top: document.querySelector("[data-scroll-y]").scrollTop }));
  check("↑ bis oben: Seitenkopf erreicht, Seite ganz oben", backAtHero.key === "top-search" && backAtHero.top === 0, `${backAtHero.key}, scrollTop ${backAtHero.top}`);
  await remote(page, "down");
  check("Seitenkopf ↓ Hero", (await focused(page))?.key?.startsWith("hero-"), (await focused(page))?.key ?? "-");

  // Poster 7 öffnen, Zurück, derselbe Poster.
  await focusKey(page, seventh);
  const scrollBefore = await page.evaluate(() => document.querySelector("[data-scroll-y]").scrollTop);
  await remote(page, "ok", 1800);
  check("OK öffnet die Detailseite", page.url().includes("#/titel/"), page.url());
  await remote(page, "back", 1800);
  const restored = await focused(page);
  const scrollAfter = await page.evaluate(() => document.querySelector("[data-scroll-y]").scrollTop);
  check("Zurück: wieder auf der Startseite", !page.url().includes("#/titel/"), page.url());
  check("Zurück: Fokus auf demselben Poster", restored?.key === seventh, `erwartet ${seventh}, ist ${restored?.key}`);
  check("Zurück: Scrollposition wiederhergestellt", Math.abs(scrollAfter - scrollBefore) < 40, `${Math.round(scrollBefore)} → ${Math.round(scrollAfter)}`);
  const restoredVis = await focusVisibility(page);
  check("Zurück: Poster vollständig sichtbar", restoredVis.ok, restoredVis.reason);

  await remote(page, "right");
  const beforeAlt = await focused(page);
  await remote(page, "ok", 1600);
  await remote(page, "backAlt", 1800);
  check("Zurück über Tastencode 10009 wirkt genauso", !page.url().includes("#/titel/") && (await focused(page))?.key === beforeAlt?.key, page.url());

  const images = await page.evaluate(() => ({
    poster: document.querySelector(".poster-card .art img")?.getAttribute("src") ?? "",
    hero: document.querySelector(".hero-media .art img")?.getAttribute("src") ?? "",
  }));
  check("Poster in Kachelgröße (w342), nicht original", images.poster.includes("/w342/"), images.poster.split("/t/p/")[1] ?? images.poster);
  check("Hero-Breitbild in w1280", images.hero.includes("/w1280/"), images.hero.split("/t/p/")[1] ?? images.hero);

  // --- 2. Katalog ------------------------------------------------------------
  section("Katalog");
  // So oft „links", bis die Seitenleiste erreicht ist — wie auf der Couch.
  for (let i = 0; i < 12; i += 1) {
    if (await page.evaluate(() => Boolean(document.activeElement?.closest(".sidebar")))) break;
    await remote(page, "left", 160);
  }
  check("← erreicht von jeder Karte die Seitenleiste", (await focused(page))?.key === "nav-start", (await focused(page))?.key ?? "-");
  await remote(page, "down");
  const navCatalog = await focused(page);
  check("Seitenleiste ↓ Katalog", navCatalog?.key === "nav-katalog", navCatalog?.key ?? "-");
  await remote(page, "ok", 2200);
  check("OK öffnet den Katalog", page.url().includes("#/katalog"), page.url());
  const catStart = await focused(page);
  check("Katalog: Startfokus auf der ersten Karte", catStart?.key?.startsWith("grid-"), catStart?.key ?? "-");
  const columns = await page.evaluate(() => {
    const cards = Array.from(document.querySelectorAll(".catalog-grid > .poster-card"));
    const top = cards[0]?.getBoundingClientRect().top;
    return cards.filter((c) => Math.abs(c.getBoundingClientRect().top - top) < 30).length;
  });
  check("Raster: fünf Poster je Zeile bei 1080p", columns === 5, `${columns} Spalten`);
  const dupes = await page.$$eval('[data-focus-key$="-frieren"]', (els) => els.filter((e) => e.closest(".catalog-grid")).length);
  check("Keine Dubletten: Frieren aus beiden Quellen einmal", dupes === 1, `${dupes}×`);
  await shot(page, "04-katalog-erste-reihe");
  await layoutAudit(page, "Katalog", 13);

  await remote(page, "down");
  await remote(page, "down");
  await shot(page, "05-katalog-mittlere-reihe");
  await stress(page, "Katalog Matrix", MATRIX);
  for (let i = 0; i < 12; i += 1) await remote(page, "down", 120);
  await page.waitForTimeout(400);
  const catBottom = await focusVisibility(page);
  check("Katalog: unterste Reihe vollständig sichtbar", catBottom.ok, catBottom.reason);
  await shot(page, "06-katalog-letzte-reihe");

  // Detail aus Reihe 2 und zurück: hoch bis zu den Schnellfiltern, dann
  // zwei Reihen hinunter und eine Karte nach rechts.
  for (let i = 0; i < 20; i += 1) {
    if ((await focused(page))?.key?.startsWith("chips-")) break;
    await remote(page, "up", 140);
  }
  await remote(page, "down");
  await remote(page, "down");
  await remote(page, "right");
  const gridPick = await focused(page);
  check("Raster Reihe 2, Karte 2 erreicht", gridPick?.key?.startsWith("grid-"), gridPick?.key ?? "-");
  await remote(page, "ok", 1800);
  await remote(page, "back", 2000);
  const gridBack = await focused(page);
  check("Katalog → Detail → Zurück: Fokus auf derselben Karte", gridBack?.key === gridPick?.key, `erwartet ${gridPick?.key}, ist ${gridBack?.key}`);

  // Schnellfilter.
  // Reihe 2 → Reihe 1 → Schnellfilter; ein dritter Druck ginge ins Suchfeld.
  await remote(page, "up");
  await remote(page, "up");
  const chipFocus = await focused(page);
  check("↑ aus dem Raster erreicht die Schnellfilter", chipFocus?.key?.startsWith("chips-"), chipFocus?.key ?? "-");
  await remote(page, "up");
  check("Schnellfilter ↑ Suchfeld", (await focused(page))?.key === "catalog-search", (await focused(page))?.key ?? "-");
  await focusKey(page, "chips-top");
  await remote(page, "ok", 900);
  const topCount = await page.$$eval(".catalog-grid > .poster-card", (e) => e.length);
  const topHead = await page.textContent(".catalog .section-head span");
  check("„Top bewertet“ filtert nach TMDB-Bewertung", topCount > 0 && topCount < 39 && (topHead ?? "").includes("Bewertung"), `${topCount} Titel, ${topHead}`);
  await focusKey(page, "chips-all");
  await remote(page, "ok", 900);

  // Filterdialog: öffnen, Fokusfalle, Zurück schließt.
  await focusKey(page, "filter-open");
  await remote(page, "ok", 900);
  const dialog = await page.evaluate(() => ({ open: Boolean(document.querySelector(".dialog[data-focus-trap]")), inside: Boolean(document.activeElement?.closest("[data-focus-trap]")) }));
  check("Filter öffnet einen Dialog mit Fokus darin", dialog.open && dialog.inside);
  await shot(page, "07-katalog-filter");
  await stress(page, "Filterdialog: Fokus bleibt eingesperrt", ["left", "left", "up", "up", "down", "down", "down", "right", "right", "down", "down", "down"]);
  await remote(page, "back", 600);
  const closed = await page.evaluate(() => ({ open: Boolean(document.querySelector("[data-focus-trap]")), key: document.activeElement?.getAttribute("data-focus-key") }));
  check("Dialog + Zurück: Dialog zu, Katalog bleibt", !closed.open && page.url().includes("#/katalog"), page.url());
  check("Dialog + Zurück: Fokus zurück auf „Filter“", closed.key === "filter-open", closed.key ?? "-");

  // Suche mit Tippfehler.
  await page.fill('[data-focus-key="catalog-search"]', "frieen");
  await page.waitForTimeout(900);
  const fuzzy = await page.$$eval(".catalog-grid .card-title", (els) => els.map((e) => e.textContent));
  check("Suche verzeiht Tippfehler („frieen“ → Frieren)", fuzzy.some((t) => /Frieren/.test(t)), fuzzy.slice(0, 3).join(", "));
  await page.fill('[data-focus-key="catalog-search"]', "zzzzzz");
  await page.waitForTimeout(900);
  check("Keine Treffer: benannter Zustand", (await page.textContent(".state-panel h2").catch(() => "")) === "Keine Titel gefunden");
  for (const query of ["ノリ", "a+b/c", "進撃の巨人", "Dämonenjäger"]) {
    await page.fill('[data-focus-key="catalog-search"]', query);
    await page.waitForTimeout(400);
  }
  await page.fill('[data-focus-key="catalog-search"]', "");
  await page.waitForTimeout(800);
  check("Sonderzeichen und japanische Titel werfen nichts", Boolean(await page.$(".catalog")));

  // --- 3. Detailseite -----------------------------------------------------------
  section("Detailseite");
  await goto(page, "#/titel/aniworld/frieren", 3000);
  const detail = await page.evaluate(() => {
    const node = document.querySelector(".hero-detail");
    return {
      title: node?.querySelector(".hero-logo")?.getAttribute("alt") ?? node?.querySelector(".hero-title")?.textContent ?? "",
      meta: node?.querySelector(".meta")?.textContent ?? "",
      text: node?.querySelector(".hero-text")?.textContent ?? "",
      height: Math.round(node?.getBoundingClientRect().height ?? 0),
      backdrop: node?.querySelector(".hero-media img")?.getAttribute("src") ?? "",
      logo: node?.querySelector(".hero-logo")?.getAttribute("src") ?? "",
    };
  });
  check("Detail: Hero mit Titel oder Logo", Boolean(detail.title), detail.title);
  check("Detail: großer Backdrop", detail.height >= 560 && detail.backdrop.includes("backdrop"), `${detail.height} px, ${detail.backdrop.split("/").pop()}`);
  check("Detail: Logo von TMDB (PNG, kein SVG)", detail.logo.includes("logo") && !detail.logo.endsWith(".svg"), detail.logo.split("/").pop() ?? "-");
  check("Detail: Jahr · Genres · Staffeln · Bewertung", /\d{4}/.test(detail.meta) && detail.meta.includes("Staffeln") && detail.meta.includes("★"), detail.meta);
  check("Detail: Beschreibung", detail.text.length > 20);
  const detailStart = await focused(page);
  check("Detail: Startfokus „Jetzt ansehen“", detailStart?.key === "play", detailStart?.key ?? "-");
  await shot(page, "08-detail-hero");
  await layoutAudit(page, "Detailseite", 13);

  await remote(page, "down");
  const seasonFocus = await focused(page);
  check("Hero ↓ Staffelwahl", seasonFocus?.key === "season-open", seasonFocus?.key ?? "-");
  await remote(page, "ok", 900);
  const menu = await page.evaluate(() => ({ open: Boolean(document.querySelector(".dialog.menu")), key: document.activeElement?.getAttribute("data-focus-key"), items: document.querySelectorAll(".menu-item").length }));
  check("Staffelmenü öffnet mit Fokus auf der gewählten Staffel", menu.open && menu.key === "season-1", `${menu.key}, ${menu.items} Einträge`);
  await shot(page, "09-detail-staffelmenue");
  await stress(page, "Staffelmenü: Fokus bleibt im Menü", ["left", "right", "down", "down", "down", "down", "up", "up", "up", "up", "up"]);
  await remote(page, "back", 600);
  check("Staffelmenü + Zurück: Menü zu, Detailseite bleibt", !(await page.$(".dialog.menu")) && page.url().includes("#/titel/"));
  check("Staffelmenü zu: Fokus zurück auf der Staffelwahl", (await focused(page))?.key === "season-open");

  await remote(page, "down");
  const ep1 = await focused(page);
  check("Staffelwahl ↓ erste Folge", ep1?.key === "episode-1", ep1?.key ?? "-");
  const seasonVisible = await page.evaluate(() => document.querySelector('[data-focus-key="season-open"]').getBoundingClientRect().top >= 0);
  check("Erste Folge: Staffelzeile bleibt sichtbar", seasonVisible);
  await shot(page, "10-detail-erste-folge");
  const epColumns = await page.evaluate(() => {
    const cards = Array.from(document.querySelectorAll(".episode-grid .ep-card"));
    const top = cards[1]?.getBoundingClientRect().top;
    return cards.filter((c) => Math.abs(c.getBoundingClientRect().top - top) < 30).length;
  });
  check("Folgen: drei Karten je Reihe", epColumns === 3, `${epColumns}`);
  const epInfo = await page.evaluate(() => {
    const card = document.querySelector('[data-focus-key="episode-1"]');
    return {
      title: card.querySelector(".ep-title")?.textContent ?? "",
      meta: card.querySelector(".ep-meta")?.textContent ?? "",
      still: card.querySelector(".ep-thumb img")?.getAttribute("src") ?? "",
    };
  });
  check("Folgenkarte: Nummer und Titel", /^1\. .{3,}/.test(epInfo.title), epInfo.title);
  check("Folgenkarte: Laufzeit und Sprache", /\d+ Min\./.test(epInfo.meta) && /DE/.test(epInfo.meta), epInfo.meta);
  check("Folgenkarte: TMDB-Standbild", epInfo.still.includes("still-1-1"), epInfo.still.split("/").pop() ?? "-");

  const epPath = [];
  for (const step of ["right", "right", "down", "down", "left", "up", "down", "down", "down", "down", "down"]) {
    await remote(page, step);
    const s = await focusVisibility(page);
    const f = await focused(page);
    epPath.push(`${step}:${f?.key}${s.ok ? "" : ` ✗ ${s.reason}`}`);
    if (step === "down" && f?.key === "episode-6") await shot(page, "11-detail-mittlere-folge");
  }
  check("Folgen: 1→2→3, Reihen ↓↑, keine Karte abgeschnitten", !epPath.some((p) => p.includes("✗")) && epPath[1].includes("episode-3") && epPath[2].includes("episode-6"), epPath.join(" "));
  await shot(page, "12-detail-unterste-folge");
  await stress(page, "Detailseite Matrix", MATRIX);

  await focusKey(page, "favorite");
  await remote(page, "ok", 500);
  check("Merkliste auf der Detailseite", ((await page.textContent('[data-focus-key="favorite"]')) ?? "").includes("Gemerkt"));
  check("Ähnliche Titel nur aus Noris Bestand", (await page.$$eval("[data-rail^='similar'] .poster-card", (e) => e.length)) > 0);

  await goto(page, "#/titel/aniworld/vinland-saga", 3000);
  const offset = await page.$$eval(".ep-card", (els) => els.slice(0, 2).map((el) => ({
    title: el.querySelector(".ep-title")?.textContent ?? "",
    still: el.querySelector(".ep-thumb img")?.getAttribute("src") ?? "",
  })));
  check("Versetzte Zählung: Folge 1 mit Standbild von TMDB-Folge 17", offset[0]?.still.includes("still-1-17"), offset.map((c) => c.still.split("/").pop()).join(", "));
  check("Versetzte Zählung: Titel der Quelle bleibt", offset[0]?.title.includes("Das Ende der Reise"), offset[0]?.title ?? "-");

  await goto(page, "#/titel/aniworld/barakamon", 2600);
  const noTmdb = await page.evaluate(() => ({ episodes: document.querySelectorAll(".ep-card").length, error: Boolean(document.querySelector(".state-panel[role=alert]")) }));
  check("Titel ohne TMDB-Eintrag: Folgen stehen, kein Fehler", noTmdb.episodes >= 10 && !noTmdb.error, `${noTmdb.episodes} Folgen`);

  await goto(page, "#/titel/aniworld/detektiv-conan", 2600);
  await focusKey(page, "season-open");
  await remote(page, "ok", 900);
  for (let i = 0; i < 6; i += 1) await remote(page, "down", 120);
  await page.waitForTimeout(300);
  const menuScroll = await focusVisibility(page);
  check("Dreißig Staffeln: Menü scrollt mit, Eintrag sichtbar", menuScroll.ok, menuScroll.reason);
  await remote(page, "ok", 2200);
  const seasonLabel = await page.textContent('[data-focus-key="season-open"]');
  check("Staffelwechsel über das Menü greift", (seasonLabel ?? "").includes("Staffel 7"), seasonLabel ?? "-");
  check("Folgen der neuen Staffel geladen", (await page.$$eval(".ep-card", (e) => e.length)) >= 10);

  // --- 4. Player ---------------------------------------------------------------
  section("Player");
  await goto(page, "#/titel/aniworld/frieren", 2600);
  await focusKey(page, "play");
  await remote(page, "down");
  await remote(page, "down");
  await remote(page, "right");
  await remote(page, "right");
  check("Folge 3 per Fernbedienung erreicht", (await focused(page))?.key === "episode-3");
  await remote(page, "ok", 2800);
  check("OK auf einer Folge startet den Player", page.url().includes("#/player/"), page.url());
  check("Videoelement vorhanden", Boolean(await page.$("video.player-video")));
  check("Bedienung anfangs sichtbar", await page.evaluate(() => document.querySelector(".player-chrome")?.classList.contains("visible")));
  check("Hoster aufgelöst", ((await page.textContent(".player-actions button small").catch(() => "")) ?? "").includes("VOE"));
  await shot(page, "13-player");

  await remote(page, "play", 900);
  check("Play startet die Wiedergabe", await page.evaluate(() => { const v = document.querySelector("video.player-video"); return v ? !v.paused && v.currentTime > 0 : false; }));
  await remote(page, "pause", 400);
  check("Pause hält sie an", await page.evaluate(() => document.querySelector("video.player-video")?.paused === true));
  await remote(page, "play", 700);
  const before = await page.evaluate(() => document.querySelector("video.player-video")?.currentTime ?? 0);
  await remote(page, "forward", 900);
  const after = await page.evaluate(() => document.querySelector("video.player-video")?.currentTime ?? 0);
  check("Vorspulen", after > before + 5, `${before.toFixed(1)} → ${after.toFixed(1)}`);
  await remote(page, "rewind", 900);
  check("Zurückspulen", (await page.evaluate(() => document.querySelector("video.player-video")?.currentTime ?? 0)) < after);
  for (let i = 0; i < 8; i += 1) await remote(page, "forward", 150);
  await page.waitForTimeout(1200);
  check("Mehrfaches Spulen summiert sich", (await page.evaluate(() => document.querySelector("video.player-video")?.currentTime ?? 0)) > 60);
  await page.waitForTimeout(5500);

  await remote(page, "up", 700);
  check("Drawer über ↑", Boolean(await page.$(".player-panel")));
  check("Fokus liegt im Drawer", await page.evaluate(() => Boolean(document.activeElement?.closest(".player-panel"))));
  await shot(page, "14-player-drawer");
  await stress(page, "Player-Drawer: Fokus bleibt eingesperrt", ["left", "left", "left", "down", "down", "up"]);
  await page.click('[data-focus-key="hoster-Vidmoly"]');
  await page.waitForTimeout(1800);
  check("Hosterwechsel", ((await page.textContent(".player-actions button small").catch(() => "")) ?? "").includes("Vidmoly"));
  await remote(page, "up", 600);
  await page.click('[data-focus-key="lang-GerSub"]').catch(() => undefined);
  await page.waitForTimeout(1800);
  check("Sprachwechsel", ((await page.textContent(".player-actions button small").catch(() => "")) ?? "").includes("GerSub"));
  await stress(page, "Player-Bedienung ←→", ["left", "right", "right", "left"], 200);

  await remote(page, "up", 600);
  await remote(page, "back", 500);
  check("Zurück schließt zuerst den Drawer", !(await page.$(".player-panel")) && page.url().includes("#/player/"));
  await remote(page, "back", 500);
  check("Zurück schließt dann die Bedienung", await page.evaluate(() => !document.querySelector(".player-chrome")?.classList.contains("visible")) && page.url().includes("#/player/"));
  await remote(page, "back", 2200);
  check("Zurück verlässt erst danach den Player", !page.url().includes("#/player/"), page.url());
  check("Nach dem Player: Fokus auf Folge 3", (await focused(page))?.key === "episode-3", (await focused(page))?.key ?? "-");
  check("Kein Video läuft weiter", (await page.evaluate(() => Array.from(document.querySelectorAll("video")).filter((v) => !v.paused && v.currentSrc).length)) === 0);

  const stored = await page.evaluate(() => JSON.parse(localStorage.getItem("nori.library") ?? "{}"));
  check(`Bibliothek: Schema v${LIBRARY_SCHEMA_VERSION}`, stored.version === LIBRARY_SCHEMA_VERSION, `version ${stored.version}`);
  const progressKeys = Object.keys(stored.progress ?? {});
  check("Fortschritt mit provider|Pfad gespeichert", progressKeys.length > 0 && progressKeys.every((k) => /^(aniworld|serienstream)\|/.test(k)), progressKeys[0] ?? "-");

  // --- 5. Weiterschauen ----------------------------------------------------------
  section("Weiterschauen");
  // Fünf weitere Titel mit Fortschritt, damit die Reihe eine erste und eine letzte Karte hat.
  await page.evaluate(() => {
    const bag = JSON.parse(localStorage.getItem("nori.library"));
    const [key, item] = Object.entries(bag.progress)[0];
    const slugs = ["one-piece", "vinland-saga", "jujutsu-kaisen", "dandadan", "monster", "dark"];
    slugs.forEach((slug, i) => {
      const path = `/anime/stream/${slug}/staffel-1/episode-${i + 2}`;
      bag.progress[`aniworld|${path}`] = { ...item, slug, title: slug.replace(/-/g, " "), episode: i + 2, episodePath: path, updatedAt: item.updatedAt - (i + 1) * 60_000 };
    });
    localStorage.setItem("nori.library", JSON.stringify(bag));
    void key;
  });
  await page.reload({ waitUntil: "domcontentloaded" });
  await page.waitForTimeout(5000);
  await goto(page, "#/", 2500);
  const cont = await page.$$eval('[data-rail="continue"] .land-card', (els) => els.map((e) => ({ key: e.getAttribute("data-focus-key"), sub: e.querySelector(".card-sub")?.textContent ?? "", bar: Boolean(e.querySelector(".card-progress")) })));
  check("„Weiterschauen“ aus echtem Fortschritt", cont.length >= 5, `${cont.length} Karten`);
  check("Weiterschauen: 16:9, Staffel · Folge · Restzeit, Balken", cont[0]?.sub.includes("S1 · F3") && /noch \d+ Min\./.test(cont[0]?.sub ?? "") && cont[0]?.bar, cont[0]?.sub ?? "-");
  await focusKey(page, "hero-play");
  await remote(page, "down");
  check("Hero ↓ Weiterschauen", (await focused(page))?.key === cont[0]?.key, (await focused(page))?.key ?? "-");
  await shot(page, "15-start-weiterschauen-erste");
  for (let i = 0; i < 10; i += 1) await remote(page, "right", 120);
  await page.waitForTimeout(400);
  const lastCont = await focusVisibility(page);
  check("Weiterschauen: letzte Karte vollständig sichtbar", lastCont.ok, lastCont.reason);
  await shot(page, "16-start-weiterschauen-letzte");

  await focusKey(page, cont[0].key);
  await remote(page, "ok", 3500);
  const resume = await page.evaluate(() => ({ at: document.querySelector("video.player-video")?.currentTime ?? 0, hash: location.hash, overlay: Boolean(document.querySelector(".player-overlay")) }));
  check("Weiterschauen: Player an der gespeicherten Stelle", resume.hash.includes("episode=3") && (resume.overlay || resume.at > 8), `${resume.at.toFixed(1)} s`);
  await remote(page, "back");
  await remote(page, "back");
  await remote(page, "back", 1600);

  await goto(page, "#/player/aniworld/frieren?season=1&episode=1&path=%2Fanime%2Fstream%2Fkaputt%2Fstaffel-1%2Fepisode-1", 3000);
  const err = await page.evaluate(() => {
    const panel = document.querySelector(".player-error");
    return panel ? { heading: panel.querySelector("h2")?.textContent ?? "", buttons: panel.querySelectorAll("button").length, inside: Boolean(document.activeElement?.closest(".player-error")) } : null;
  });
  check("Hosterfehler: benannter Fehlerzustand mit Fokus darin", Boolean(err) && err.buttons >= 2 && err.inside, err?.heading ?? "schwarze Fläche");
  await shot(page, "17-player-fehler");
  await focusKey(page, "error-exit");
  await remote(page, "ok", 1400);
  check("Aus dem Fehlerzustand führt ein Weg heraus", !page.url().includes("#/player/"));

  // --- 6. Kalender ---------------------------------------------------------------
  section("Kalender");
  await goto(page, "#/kalender", 2600);
  const calStart = await focused(page);
  check("Kalender: Startfokus auf dem heutigen Tag", calStart?.cls.includes("today"), calStart?.key ?? "-");
  const noTime = await page.$$eval(".release .timepill", (els) => els.map((e) => e.textContent));
  check("Keine erfundenen Uhrzeiten (Quelle ohne Uhrzeit)", noTime.length === 0, noTime.join(", "));
  const releases = await page.$$eval(".release", (els) => els.map((e) => e.querySelector(".rel-meta")?.textContent ?? ""));
  check("Einträge mit Staffel · Folge · Sprache", releases.length > 0 && releases.every((m) => /Staffel \d+ · Folge \d+ · DE/.test(m)), releases[0] ?? "-");
  await shot(page, "18-kalender-heute");
  await layoutAudit(page, "Kalender", 13);
  await remote(page, "down");
  check("Tag ↓ erster Eintrag", (await focused(page))?.cls.includes("release"));
  await shot(page, "19-kalender-erster-eintrag");
  for (let i = 0; i < 12; i += 1) await remote(page, "down", 150);
  await page.waitForTimeout(400);
  const calBottom = await focusVisibility(page);
  check("Kalender: unterster Eintrag vollständig sichtbar", calBottom.ok, calBottom.reason);
  await shot(page, "20-kalender-unterster-eintrag");
  const relKey = (await focused(page))?.key;
  await remote(page, "ok", 2000);
  check("Eintrag öffnet die Detailseite", page.url().includes("#/titel/"));
  await remote(page, "back", 2200);
  check("Zurück: Fokus auf demselben Eintrag", (await focused(page))?.key === relKey, `${relKey} / ${(await focused(page))?.key}`);
  await stress(page, "Kalender Matrix", MATRIX);

  await focusKey(page, "modes-week");
  await remote(page, "ok", 800);
  check("Woche: Tagesgruppen", (await page.$$eval("[data-day-group]", (e) => e.length)) >= 1);
  await focusKey(page, "modes-month");
  await remote(page, "ok", 800);
  const month = await page.$$eval(".month-grid .day", (e) => e.length);
  check("Monat: Raster mit 42 Tagen", month === 42, `${month}`);
  await shot(page, "21-kalender-monat");
  await stress(page, "Monatsansicht Matrix", MATRIX.slice(0, 30));
  await focusKey(page, "modes-today");
  await remote(page, "ok", 800);

  // --- 7. Merkliste ---------------------------------------------------------------
  section("Merkliste");
  await goto(page, "#/merkliste", 2000);
  const wl = await page.evaluate(() => ({
    chips: Array.from(document.querySelectorAll(".chips .chip")).map((c) => c.textContent.trim()),
    cards: document.querySelectorAll(".catalog-grid .poster-card").length,
    badges: document.querySelectorAll(".catalog-grid .poster-card").length ? Array.from(document.querySelectorAll(".catalog-grid .card-art")).filter((a) => /ANIME|SERIE/i.test(a.textContent)).length : 0,
    scopeTabs: Array.from(document.querySelectorAll(".watchlist button")).filter((b) => /^(Anime|Serien)$/.test(b.textContent.trim())).length,
    stats: document.querySelector(".stats")?.textContent ?? "",
    sub: document.querySelector(".catalog-grid .card-sub")?.textContent ?? "",
  }));
  check("Schnellfilter Alle · Ungesehen · Angefangen · Gesehen", wl.chips.join("|") === "Alle|Ungesehen|Angefangen|Gesehen", wl.chips.join("|"));
  check("Keine Anime/Serien-Reiter und keine Schilder", wl.scopeTabs === 0 && wl.badges === 0);
  check("Merkliste aus der Bibliothek", wl.cards === 1, `${wl.cards} Karten`);
  check("Angefangen: „S1 · F3 · x %“", /^S1 · F3 · \d+ %$/.test(wl.sub), wl.sub);
  await shot(page, "22-merkliste-erste");
  await focusKey(page, "chips-unseen");
  await remote(page, "ok", 500);
  check("Filter Ungesehen blendet angefangene aus", (await page.$$eval(".catalog-grid .poster-card", (e) => e.length)) === 0);
  await focusKey(page, "chips-started");
  await remote(page, "ok", 500);
  check("Filter Angefangen zeigt ihn", (await page.$$eval(".catalog-grid .poster-card", (e) => e.length)) === 1);
  await stress(page, "Merkliste Matrix", MATRIX.slice(0, 24));
  await shot(page, "23-merkliste-untere");
  await focusKey(page, "edit");
  await remote(page, "ok", 400);
  await focusKey(page, "fav-frieren");
  await remote(page, "ok", 700);
  check("Bearbeiten + OK entfernt den Titel", (await page.$$eval(".catalog-grid .poster-card", (e) => e.length)) === 0);
  check("Nach dem Entfernen bleibt der Fokus erhalten", Boolean(await focused(page)), (await focused(page))?.key ?? "-");

  // --- 8. Mehr ---------------------------------------------------------------------
  section("Mehr");
  await goto(page, "#/mehr", 1800);
  const cards = await page.$$eval(".setting-card h3", (e) => e.map((n) => n.textContent));
  check("Karten Wiedergabe · Darstellung · Synchronisierung · Nori", cards.join("|") === "Wiedergabe|Darstellung|Synchronisierung|Nori", cards.join("|"));
  check("Startfokus auf der ersten Einstellung", (await focused(page))?.key === "set-autoplay");
  await shot(page, "24-mehr-erste");
  await layoutAudit(page, "Mehr", 13);
  const autoplayBefore = await page.evaluate(() => JSON.parse(localStorage.getItem("nori.library")).autoplayNext);
  await remote(page, "ok", 700);
  const autoplayAfter = await page.evaluate(() => JSON.parse(localStorage.getItem("nori.library")).autoplayNext);
  check("Autoplay per OK umgeschaltet und gespeichert", autoplayBefore !== autoplayAfter, `${autoplayBefore} → ${autoplayAfter}`);
  await remote(page, "ok", 500);
  await remote(page, "down");
  await remote(page, "down");
  check("↓ erreicht die Sprache", (await focused(page))?.key === "set-lang");
  const langBefore = await page.evaluate(() => JSON.parse(localStorage.getItem("nori.library")).langPref);
  await remote(page, "ok", 700);
  const langMenu = await page.evaluate(() => ({ open: Boolean(document.querySelector(".dialog.menu")), key: document.activeElement?.getAttribute("data-focus-key") }));
  check("Sprache öffnet ein Menü mit Fokus auf der aktuellen", langMenu.open && langMenu.key === `menu-lang-${langBefore}`, `${langMenu.key}`);
  await remote(page, langBefore === "EN" ? "up" : "down");
  await remote(page, "ok", 700);
  const lang = await page.evaluate(() => JSON.parse(localStorage.getItem("nori.library")).langPref);
  check("Sprachwahl gespeichert, Menü zu, Fokus zurück", lang !== langBefore && !(await page.$(".dialog.menu")) && (await focused(page))?.key === "set-lang", `${langBefore} → ${lang}`);
  const tmdbPill = await page.evaluate(() => Array.from(document.querySelectorAll(".setting-row.info")).find((r) => r.textContent.includes("TMDB"))?.querySelector(".status-pill")?.textContent);
  check("TMDB-Zustand benannt", ["Verbunden", "Nicht verfügbar", "Fehler", "Bereit"].includes(tmdbPill ?? ""), tmdbPill ?? "-");
  const version = await page.evaluate(() => Array.from(document.querySelectorAll(".setting-row.info")).find((r) => r.textContent.includes("Version"))?.textContent ?? "");
  check(`Version ${APP_VERSION} angezeigt`, version.includes(APP_VERSION), version);
  await stress(page, "Mehr Matrix", MATRIX);
  for (let i = 0; i < 12; i += 1) await remote(page, "down", 120);
  await page.waitForTimeout(400);
  await shot(page, "25-mehr-untere");

  await focusKey(page, "set-diagnose");
  await remote(page, "ok", 4500);
  const diag = await page.$$eval(".setting-row.info b", (e) => e.map((n) => n.textContent));
  check("Diagnose: AniWorld · Serienstream · TMDB · Player · Persistenz · Google Drive",
    ["AniWorld", "Serienstream", "TMDB", "Player", "Persistenz", "Google Drive"].every((n) => diag.includes(n)), diag.join(", "));
  const diagText = await page.textContent(".screen");
  check("Diagnose zeigt keine Schlüssel", !/[0-9a-f]{32}/.test(diagText ?? "") && !/GOCSPX/.test(diagText ?? ""));
  await shot(page, "26-diagnose");
  await remote(page, "back", 1500);
  check("Unterseite + Zurück → Mehr, Fokus auf „Diagnose“", page.url().endsWith("#/mehr") && (await focused(page))?.key === "set-diagnose", `${page.url()} / ${(await focused(page))?.key}`);

  await goto(page, "#/mehr/verbindung", 2000);
  const connection = await page.evaluate(() => Array.from(document.querySelectorAll(".card-note")).map((n) => n.textContent ?? "").find((t) => t.includes("Titel zugeordnet")) ?? "");
  const matched = /(\d+) Titel zugeordnet/.exec(connection);
  check("TMDB: Titel zugeordnet", Boolean(matched) && Number(matched[1]) > 0, connection.slice(0, 120));
  check("TMDB: Treffer über Alternativtitel ausgewiesen", connection.includes("über Alternativtitel"), connection.slice(0, 120));
  check("TMDB: Weg Nori-Server", connection.includes("Nori-Server"));

  // Ohne Google-Zugang im Build: ein Satz, kein Eingabefeld.
  await goto(page, "#/mehr/abgleich", 1800);
  const syncState = await page.evaluate(() => ({
    status: Array.from(document.querySelectorAll(".status-pill")).map((n) => n.textContent),
    fields: document.querySelectorAll(".screen input").length,
    text: document.querySelector(".screen")?.textContent ?? "",
  }));
  check("Abgleich ohne Google-Zugang im Build: „nicht verfügbar“", syncState.status.includes("nicht verfügbar"), syncState.status.join(", "));
  check("Abgleich: kein Eingabefeld für Client-ID oder Secret", syncState.fields === 0, `${syncState.fields} Felder`);
  check("Abgleich: kein Knopf, der Zugangsdaten annimmt", !/Zugangsdaten sichern|client_secret|GOCSPX/.test(syncState.text));
  check("Abgleich: Nori läuft ohne Netz vollständig weiter", syncState.text.includes("Ohne Netz funktioniert Nori vollständig weiter"));

  await goto(page, "#/mehr/daten", 1400);
  check(`Daten: Schema v${LIBRARY_SCHEMA_VERSION}`, ((await page.textContent(".screen")) ?? "").includes(`v${LIBRARY_SCHEMA_VERSION}`));

  // --- 9. Ausfälle ------------------------------------------------------------------
  section("Ausfälle");
  await page.route("**/api/tmdb/**", (route) => route.abort("failed"));
  await page.evaluate(() => { for (const k of Object.keys(localStorage)) if (k.startsWith("nori.tmdb")) localStorage.removeItem(k); });
  await page.reload({ waitUntil: "domcontentloaded" });
  await page.waitForTimeout(4500);
  await goto(page, "#/", 2000);
  const noTmdbRails = await page.$$eval("[data-rail] .section-head h2", (els) => els.map((e) => e.textContent?.trim()));
  check("TMDB-Ausfall: Startseite steht", noTmdbRails.length > 0 && Boolean(await focused(page)), noTmdbRails.join(", "));
  check("TMDB-Ausfall: keine Reihe behauptet „Neu & beliebt“", !noTmdbRails.includes("Neu & beliebt"));
  check("TMDB-Ausfall: Hero trotzdem mit echtem Titel", Boolean(await page.$(".hero-home .hero-title, .hero-home .hero-logo")));
  await page.unroute("**/api/tmdb/**");

  await page.route("**/api/catalog/**", (route) => route.abort("failed"));
  await page.reload({ waitUntil: "domcontentloaded" });
  await page.waitForTimeout(3500);
  const outage = await page.evaluate(() => document.querySelector(".state-panel h2")?.textContent ?? null);
  check("Katalog-Ausfall: benannter Zustand", Boolean(outage), outage ?? "-");
  check("Katalog-Ausfall: Fernbedienung bleibt bedienbar", Boolean(await focused(page)));
  await page.unroute("**/api/catalog/**");

  const relevant = consoleErrors.filter((e) => !/Failed to load resource|net::ERR|ERR_FAILED|MEDIA_ELEMENT|no supported source|Unable to preventDefault/i.test(e));
  check("Keine Skriptfehler in der Konsole", relevant.length === 0, relevant.slice(0, 3).join(" | "));

  // --- 10. Frisch installiert ---------------------------------------------------------
  section("Frisch installiert");
  const fresh = await newTvPage(browser, 1920, 1080, { settings: false });
  await fresh.route("https://api.themoviedb.org/**", (route) => route.abort("failed"));
  await fresh.goto(`${BASE}/#/mehr/verbindung`, { waitUntil: "domcontentloaded" });
  await fresh.waitForTimeout(3000);
  const way = await fresh.evaluate(() => Array.from(document.querySelectorAll(".card-note")).map((n) => n.textContent ?? "").find((t) => t.startsWith("Weg:")) ?? "");
  check("Ohne Einstellungen ist TMDB mit dem mitgelieferten Schlüssel eingerichtet", way.includes("mitgelieferter Schlüssel"), way.slice(0, 100));
  await fresh.close();

  // --- 10b. Google Drive verbinden --------------------------------------------------------
  //
  // Mit abgefangenen Google-Endpunkten. Eingerichtet wird über den Weg, den auch
  // ein Update einer älteren Fassung nimmt: Zugangsdaten im Speicher des Geräts.
  // Eine echte Anmeldung bei Google prüft das nicht — die hängt an einem Konto.
  section("Google Drive verbinden");
  const oauth = await newTvPage(browser, 1920, 1080);
  const oauthLog = [];
  oauth.on("console", (msg) => oauthLog.push(msg.text()));
  oauth.on("pageerror", (err) => oauthLog.push(`pageerror: ${err.message}`));
  await oauth.route("https://api.themoviedb.org/**", (route) => route.abort("failed"));
  const DEVICE_CODE = "NORI-TEST-DEVICE-CODE";
  const USER_CODE = "WDXR-KQPF";
  const VERIFY = "https://www.google.com/device";
  let tokenCalls = 0;
  let grantAccess = false;
  let codeLifetime = 900;
  await oauth.route("https://oauth2.googleapis.com/device/code", (route) => route.fulfill({
    status: 200,
    contentType: "application/json",
    body: JSON.stringify({
      device_code: DEVICE_CODE, user_code: USER_CODE, verification_url: VERIFY, verification_uri: VERIFY,
      verification_uri_complete: `${VERIFY}?user_code=${USER_CODE}`, expires_in: codeLifetime, interval: 1,
    }),
  }));
  await oauth.route("https://oauth2.googleapis.com/token", (route) => {
    tokenCalls += 1;
    if (!grantAccess) {
      return route.fulfill({ status: 428, contentType: "application/json", body: JSON.stringify({ error: "authorization_pending" }) });
    }
    return route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ access_token: "test-access", refresh_token: "test-refresh", expires_in: 3600, scope: "https://www.googleapis.com/auth/drive.appdata" }),
    });
  });
  await oauth.route("https://www.googleapis.com/drive/v3/files**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ files: [] }) }));
  await oauth.route("https://www.googleapis.com/upload/drive/v3/files**", (route) => route.fulfill({
    status: 200, contentType: "application/json", body: JSON.stringify({ id: "test-file", modifiedTime: "2026-09-12T12:00:00.000Z", size: "42" }),
  }));
  await oauth.addInitScript(() => {
    localStorage.setItem("nori.google.clientId", "123456-test.apps.googleusercontent.com");
    localStorage.setItem("nori.google.clientSecret", "TEST-ONLY-not-a-real-secret");
  });

  // Aus Mehr: der Knopf steht direkt in der Karte.
  await oauth.goto(`${BASE}/#/mehr`, { waitUntil: "domcontentloaded" });
  await oauth.waitForTimeout(3000);
  await focusKey(oauth, "set-sync-connect");
  check("Mehr: „Mit Google Drive verbinden“ ist ein Knopf in der Karte", ((await oauth.textContent('[data-focus-key="set-sync-connect"]').catch(() => "")) ?? "").includes("Mit Google Drive verbinden"));
  await remote(oauth, "ok", 1000);
  check("Mehr: der Knopf öffnet den Gerätedialog", Boolean(await oauth.$(".device-dialog")));
  await remote(oauth, "back", 700);
  check("Zurück schließt den Dialog, Mehr bleibt, Fokus zurück auf dem Knopf",
    !(await oauth.$(".device-dialog")) && oauth.url().endsWith("#/mehr") && (await focused(oauth))?.key === "set-sync-connect",
    (await focused(oauth))?.key ?? "-");

  await goto(oauth, "#/mehr/abgleich", 1800);
  const configured = await oauth.evaluate(() => document.querySelector(".screen")?.textContent ?? "");
  check("Übernommene Zugangsdaten werden weiterbenutzt", configured.includes("nicht verbunden"), configured.slice(0, 120));
  check("Mit Diagnoseprotokoll: Herkunft benannt, Secret nicht", configured.includes("aus einer früheren Fassung übernommen") && !configured.includes("TEST-ONLY"));
  check("Abgleich: Startfokus auf „Mit Google Drive verbinden“", (await focused(oauth))?.key === "connect", (await focused(oauth))?.key ?? "-");
  await remote(oauth, "ok", 1000);
  const deviceDialog = await oauth.evaluate(() => {
    const panel = document.querySelector(".device-dialog");
    if (!panel) return null;
    const svg = panel.querySelector("svg.qr");
    const box = panel.getBoundingClientRect();
    return {
      code: panel.querySelector(".device-value")?.textContent?.trim() ?? "",
      url: panel.querySelector(".device-url")?.textContent?.trim() ?? "",
      hint: panel.querySelector(".device-hint")?.textContent?.trim() ?? "",
      modules: ((svg?.querySelector("path")?.getAttribute("d") ?? "").match(/M/g) ?? []).length,
      qrSide: Math.round(svg?.getBoundingClientRect().width ?? 0),
      inside: box.left >= 0 && box.top >= 0 && box.right <= window.innerWidth && box.bottom <= window.innerHeight,
      focusInside: panel.contains(document.activeElement),
    };
  });
  check("Gerätedialog: Code von Google", deviceDialog?.code === USER_CODE, deviceDialog?.code ?? "kein Dialog");
  check("Gerätedialog: Adresse ohne Schema", deviceDialog?.url === "www.google.com/device", deviceDialog?.url ?? "-");
  check("Gerätedialog: QR-Code gezeichnet und groß genug (≥ 300 px)", (deviceDialog?.modules ?? 0) > 150 && (deviceDialog?.qrSide ?? 0) >= 300, `${deviceDialog?.modules} Module, ${deviceDialog?.qrSide} px`);
  check("Gerätedialog: Restlaufzeit", /Der Code gilt noch \d+:\d\d Minuten/.test(deviceDialog?.hint ?? ""), deviceDialog?.hint ?? "-");
  check("Gerätedialog passt ins Bild, Fokus darin", deviceDialog?.inside === true && deviceDialog?.focusInside === true);
  await shot(oauth, "27-abgleich-geraetecode");
  await stress(oauth, "Gerätedialog: Fokus bleibt eingesperrt", ["left", "right", "up", "down", "down"]);
  await remote(oauth, "back", 700);
  check("Zurück bricht ab, Fokus zurück auf „Verbinden“", !(await oauth.$(".device-dialog")) && (await focused(oauth))?.key === "connect", (await focused(oauth))?.key ?? "-");

  grantAccess = true;
  const callsBefore = tokenCalls;
  await remote(oauth, "ok", 4500);
  const connectedState = await oauth.evaluate(() => ({
    dialog: Boolean(document.querySelector(".device-dialog")),
    keys: Array.from(document.querySelectorAll(".screen .spottable")).map((n) => n.getAttribute("data-focus-key")),
    tokens: Boolean(localStorage.getItem("nori.google.tokens")),
  }));
  check("Nach der Zustimmung schließt der Dialog von selbst", !connectedState.dialog && tokenCalls > callsBefore, `${tokenCalls} Abrufe`);
  check("Verbunden: Abgleichen, Trennen, Widerrufen", ["sync-now", "disconnect", "revoke"].every((k) => connectedState.keys.includes(k)), connectedState.keys.join(", "));
  check("Die Berechtigung liegt im Speicher des Geräts", connectedState.tokens);
  check("Nach dem Verbinden bleibt der Fokus erhalten", Boolean(await focused(oauth)));
  await shot(oauth, "28-abgleich-verbunden");
  const leaked = oauthLog.filter((line) => /test-access|test-refresh|TEST-ONLY-not-a-real-secret|NORI-TEST-DEVICE-CODE/.test(line));
  check("Kein Token und kein Secret im Protokoll", leaked.length === 0, leaked.slice(0, 2).join(" | "));

  await oauth.reload({ waitUntil: "domcontentloaded" });
  await oauth.waitForTimeout(3000);
  await goto(oauth, "#/mehr/abgleich", 1500);
  check("Nach dem Neustart verbunden, ohne erneute Anmeldung",
    !(await oauth.$(".device-dialog")) && Boolean(await oauth.$('[data-focus-key="sync-now"]')));

  // Abgelaufener Code: ein Satz und ein neuer Code auf einen Druck.
  await oauth.evaluate(() => localStorage.removeItem("nori.google.tokens"));
  grantAccess = false;
  codeLifetime = 1;
  await oauth.reload({ waitUntil: "domcontentloaded" });
  await oauth.waitForTimeout(2500);
  await goto(oauth, "#/mehr/abgleich", 1500);
  await focusKey(oauth, "connect");
  await remote(oauth, "ok", 3500);
  const expiredView = await oauth.evaluate(() => ({
    text: document.querySelector(".device-dialog")?.textContent ?? "",
    focus: document.activeElement?.getAttribute("data-focus-key"),
  }));
  check("Abgelaufener Code in einem Satz, ohne OAuth-Fehlertext",
    expiredView.text.includes("Der Anmeldecode ist abgelaufen.") && !/expired_token|invalid_grant|authorization_pending/.test(expiredView.text),
    expiredView.text.slice(0, 80));
  check("Fokus auf „Neuen Code erzeugen“", expiredView.focus === "device-retry", expiredView.focus ?? "-");
  await shot(oauth, "29-abgleich-code-abgelaufen");
  await oauth.close();

  // Ohne Diagnoseschalter ist von OAuth nichts zu sehen.
  const quiet = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  await quiet.route("https://api.themoviedb.org/**", (route) => route.abort("failed"));
  await quiet.addInitScript((base) => {
    localStorage.setItem("nori.webos.settings", JSON.stringify({
      transport: "server", serverUrl: base, controlsTimeout: 4, seekStep: 10,
      autoplayCountdown: 3, tmdbMode: "server", tmdbKey: "", reduceEffects: false, debug: false,
    }));
    localStorage.setItem("nori.google.clientId", "123456-test.apps.googleusercontent.com");
    localStorage.setItem("nori.google.clientSecret", "TEST-ONLY-not-a-real-secret");
  }, BASE);
  await quiet.goto(`${BASE}/#/mehr/abgleich`, { waitUntil: "domcontentloaded" });
  await quiet.waitForTimeout(2500);
  const quietText = await quiet.evaluate(() => document.querySelector(".screen")?.textContent ?? "");
  check("Ohne Diagnoseprotokoll keine Client-ID auf dem Bildschirm", quietText.length > 0 && !/Client-ID|Client-Secret|appdata/.test(quietText), quietText.slice(0, 120));
  check("Der Knopf zum Anmelden steht trotzdem", quietText.includes("Mit Google Drive verbinden"));
  await quiet.close();

  // --- 11. 4K ---------------------------------------------------------------------------
  section("3840 × 2160");
  const uhd = await newTvPage(browser, 3840, 2160);
  await uhd.goto(BASE, { waitUntil: "domcontentloaded" });
  await uhd.waitForTimeout(6000);
  const scale = await uhd.evaluate(() => ({
    rem: parseFloat(getComputedStyle(document.documentElement).fontSize),
    sidebar: document.querySelector(".sidebar").getBoundingClientRect().width,
    heroH: document.querySelector(".hero")?.getBoundingClientRect().height ?? 0,
    poster: document.querySelector(".poster-card .art img")?.getAttribute("src") ?? "",
    hero: document.querySelector(".hero-media .art img")?.getAttribute("src") ?? "",
    navCenter: (() => {
      const l = Array.from(document.querySelectorAll(".navbtn"));
      return (l[0].getBoundingClientRect().top + l[l.length - 1].getBoundingClientRect().bottom) / 2;
    })(),
    focus: document.activeElement?.getAttribute("data-focus-key"),
  }));
  check("4K: 1 rem = 32 px (proportional skaliert)", scale.rem === 32, `${scale.rem} px`);
  check("4K: Seitenleiste doppelt so breit, nicht breiter", Math.abs(scale.sidebar - 496) < 2, `${scale.sidebar} px`);
  check("4K: Hero doppelt so hoch", Math.abs(scale.heroH - 1040) < 4, `${scale.heroH} px`);
  check("4K: Navigation vertikal zentriert", Math.abs(scale.navCenter - 1080) < 12, `${Math.round(scale.navCenter)}`);
  check("4K: Poster in größerer TMDB-Stufe (w780)", scale.poster.includes("/w780/"), scale.poster.split("/t/p/")[1] ?? scale.poster);
  check("4K: Hero-Breitbild in original statt hochskaliertem w1280", scale.hero.includes("/original/"), scale.hero.split("/t/p/")[1] ?? scale.hero);
  check("4K: Startfokus „Jetzt ansehen“", scale.focus === "hero-play", scale.focus ?? "-");
  await shot(uhd, "30-4k-start");
  await layoutAudit(uhd, "4K Startseite", 26);
  await stress(uhd, "4K Startseite Matrix", MATRIX);

  await goto(uhd, "#/katalog", 2600);
  const uhdCols = await uhd.evaluate(() => {
    const cards = Array.from(document.querySelectorAll(".catalog-grid > .poster-card"));
    const top = cards[0]?.getBoundingClientRect().top;
    return cards.filter((c) => Math.abs(c.getBoundingClientRect().top - top) < 60).length;
  });
  check("4K Katalog: fünf große Poster statt zehn winziger", uhdCols === 5, `${uhdCols}`);
  await shot(uhd, "31-4k-katalog");
  await layoutAudit(uhd, "4K Katalog", 26);
  await stress(uhd, "4K Katalog Matrix", MATRIX);

  await goto(uhd, "#/titel/aniworld/frieren", 3200);
  await shot(uhd, "32-4k-detail");
  await layoutAudit(uhd, "4K Detailseite", 26);
  await stress(uhd, "4K Detailseite Matrix", MATRIX);
  await goto(uhd, "#/kalender", 2400);
  await shot(uhd, "33-4k-kalender");
  await layoutAudit(uhd, "4K Kalender", 26);
  await stress(uhd, "4K Kalender Matrix", MATRIX.slice(0, 30));
  await goto(uhd, "#/mehr", 2000);
  await shot(uhd, "34-4k-mehr");
  await layoutAudit(uhd, "4K Mehr", 26);
  await stress(uhd, "4K Mehr Matrix", MATRIX);
  await uhd.close();

  // --- 12. file:// ----------------------------------------------------------------------------
  section("Von file:// geladen");
  const fileErrors = [];
  const filePage = await newTvPage(browser, 1920, 1080);
  filePage.on("pageerror", (e) => fileErrors.push(e.message));
  filePage.on("console", (m) => { if (m.type() === "error") fileErrors.push(m.text()); });
  await filePage.goto(`file://${join(APP, "dist", "index.html")}`, { waitUntil: "commit" });
  await filePage.waitForTimeout(120);
  await filePage.screenshot({ path: join(SHOTS, "00-bootscreen.png") });
  await filePage.waitForTimeout(6000);
  const fileState = await filePage.evaluate(() => ({
    mounted: Boolean(document.querySelector(".app-shell")),
    splashGone: !document.querySelector(".boot-splash"),
    rails: document.querySelectorAll("[data-rail]").length,
    cards: document.querySelectorAll(".poster-card, .land-card").length,
    accent: getComputedStyle(document.documentElement).getPropertyValue("--accent").trim(),
  }));
  check("file://: App baut sich auf", fileState.mounted && fileState.splashGone, JSON.stringify(fileState));
  check("file://: Stile geladen", fileState.accent === "#79c7ff", fileState.accent);
  check("file://: Daten kommen an", fileState.rails > 0 && fileState.cards > 5, `${fileState.rails} Reihen, ${fileState.cards} Karten`);
  check("file://: Fokus sitzt", Boolean(await focused(filePage)));
  await filePage.screenshot({ path: join(SHOTS, "35-von-file.png") });
  const fileRelevant = fileErrors.filter((m) => !/Failed to load resource|net::ERR|ERR_FAILED|MEDIA_ELEMENT|no supported source/i.test(m));
  check("file://: keine Skriptfehler", fileRelevant.length === 0, fileRelevant.slice(0, 3).join(" | "));
  await filePage.close();
} catch (error) {
  crashed = error;
  check("Der Lauf kommt bis zum Ende", false, `${error?.name ?? "Fehler"}: ${String(error?.message ?? error).split("\n")[0]}`);
  try { await shot(page, "99-abbruch"); } catch { /* nichts mehr möglich */ }
}

await browser.close();

console.log(`\n${results.join("\n")}`);
const total = results.filter((line) => !line.startsWith("\n")).length;
console.log(`\n${results.filter((line) => line.startsWith("PASS")).length}/${total} bestanden`);
console.log(`Bildschirmfotos: ${SHOTS}`);
if (crashed) console.error("\nAbbruch:", crashed);
process.exit(failures > 0 ? 1 : 0);
