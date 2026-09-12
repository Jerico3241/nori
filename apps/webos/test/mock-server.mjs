// Ein Nachbau des Nori-Servers mit festen Daten.
//
// Wofür: die TV-Oberfläche lässt sich damit vollständig durchspielen, ohne
// AniWorld und Serienstream anzufassen. Das ist nicht nur höflich gegenüber den
// Quellen — es macht den Ablauf auch wiederholbar. Ein Test, der von einer
// fremden Webseite abhängt, sagt am Ende mehr über deren Tagesform als über
// Nori.
//
// Der Dienst liefert dieselben Formen wie `services/nori-api`, dazu den
// gebauten Stand aus `dist/` und einen Tonschnipsel als abspielbare Datei.

import { createServer } from "node:http";
import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { handleTmdb, seasonCountFor } from "./mock-tmdb.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const APP = resolve(HERE, "..");
const DIST = join(APP, "dist");
const PORT = Number(process.env.NORI_MOCK_PORT ?? 8799);

/*
 * Die Titelliste ist nicht beliebig.
 *
 * Die ersten sind die, die der TMDB-Nachbau kennt — damit die Zuordnung
 * tatsächlich geprüft wird und nicht nur der leere Fall. „Barakamon" und die
 * übrigen kennt er **nicht**: ein Titel ohne TMDB-Eintrag muss ohne Bild und
 * ohne Fehler dastehen, und dieser Fall gehört in denselben Lauf.
 */
const TITLES = [
  "Frieren", "One Piece", "Vinland Saga", "Jujutsu Kaisen", "Dandadan",
  "Detektiv Conan", "Pluto", "Monster", "Dark", "Breaking Bad",
  "Bocchi the Rock", "Steins Gate", "Mushishi", "Dexter", "Fringe", "The Wire",
  "Chainsaw Man", "Ranking of Kings", "Odd Taxi",
  "Kaiji", "Hyouka", "Barakamon", "Sakamoto Days", "Apothecary",
  "Blue Lock", "Oshi no Ko", "Spy Family", "Made in Abyss", "Dorohedoro",
];
const GENRES = ["Action", "Drama", "Abenteuer", "Comedy", "Mystery", "K-Drama"];

function catalog(provider) {
  const items = [];
  for (let i = 0; i < 40; i += 1) {
    const suffix = i >= TITLES.length ? ` ${Math.floor(i / TITLES.length) + 1}` : "";
    const title = `${TITLES[i % TITLES.length]}${suffix}`;
    items.push({
      slug: title.toLowerCase().replace(/[^a-z0-9]+/g, "-"),
      title,
      alts: [],
      genres: [GENRES[i % GENRES.length]],
      provider,
    });
  }
  return { items, source: "mock", fetchedAt: Date.now() };
}

function series(provider, slug, season) {
  const active = season ?? "1";
  const prefix = provider === "aniworld" ? "/anime/stream" : "/serie";
  // Staffelzahl wie im TMDB-Nachbau, mindestens zwei plus „Filme". Detektiv
  // Conan bekommt damit dreißig — der Fall, für den es das Auswahlraster gibt.
  const count = Math.max(2, seasonCountFor(slug));
  const seasons = [
    ...Array.from({ length: count }, (_, i) => ({ id: String(i + 1), label: `Staffel ${i + 1}` })),
    { id: "filme", label: "Filme" },
  ];
  /*
   * Folgentitel ohne eigenen Namen bei Staffel 2.
   *
   * Absicht: Bei AniWorld heißt eine Folge oft nur „Folge 7". Dann ist der
   * TMDB-Titel die einzige Auskunft — und die Versatzerkennung hat nichts zum
   * Vergleichen, muss also bei Nummer bleiben. Staffel 1 trägt dagegen echte
   * Titel, damit der Versatz dort erkannt wird.
   */
  const named = active === "1";
  return {
    slug,
    title: slug.replace(/-/g, " ").replace(/\b\w/g, (c) => c.toUpperCase()),
    alts: ["Alternativtitel"],
    description:
      "Eine Beschreibung, die lang genug ist, um in drei Zeilen zu passen und dann "
      + "abgeschnitten zu werden. Sie erklärt worum es geht, ohne zu viel zu verraten.",
    coverPath: "/cover.png",
    yearStart: "2021", yearEnd: "2024", fsk: "12", imdb: "tt1234567",
    genres: ["Action", "Drama"],
    seasons,
    activeSeason: active,
    episodes: Array.from({ length: 12 }, (_, i) => ({
      number: i + 1,
      germanTitle: named ? EPISODE_TITLES[i % EPISODE_TITLES.length] : `Folge ${i + 1}`,
      englishTitle: `Episode ${i + 1}`,
      path: `${prefix}/${slug}/staffel-${active}/episode-${i + 1}`,
      hosters: ["VOE", "Vidmoly"],
      languages: ["DE", "GerSub"],
    })),
  };
}

/** Dieselben Titel, die der TMDB-Nachbau führt — damit der Versatz auffällt. */
const EPISODE_TITLES = [
  "Das Ende der Reise", "Es hat sich nichts geändert", "Die Zauberin der Asche",
  "Der Mann des Nordens", "Zwei Brüder im Kampf", "Dämmerung der Menschheit",
  "Vergeltungsschlacht", "Der lange Weg zurück", "Was bleibt", "Die Prüfung",
  "Ein Versprechen", "Der letzte Sommer",
];

function watch(path) {
  return {
    path,
    title: "Titel",
    germanTitle: "Der Anfang",
    englishTitle: "The Beginning",
    hosters: [
      { name: "VOE", lang: "DE", langKey: "1", redirectPath: "/redirect/1" },
      { name: "Vidmoly", lang: "DE", langKey: "1", redirectPath: "/redirect/2" },
      { name: "Filemoon", lang: "GerSub", langKey: "3", redirectPath: "/redirect/3" },
    ],
  };
}

function calendarPayload(provider) {
  const now = new Date();
  const dayKey = now.toISOString().slice(0, 10);
  const entry = (i, offset) => ({
    airingAt: now.getTime() + offset,
    episode: i + 1,
    season: "1",
    title: TITLES[i % TITLES.length],
    english: null,
    slug: TITLES[i % TITLES.length].toLowerCase().replace(/\s+/g, "-"),
    languages: ["DE"],
    dayKey,
    dayLabel: "Heute",
    coverPath: "/cover.png",
    provider,
  });
  return {
    upcoming: [entry(0, 3_600_000), entry(1, 7_200_000)],
    recent: [entry(2, -3_600_000), entry(3, -7_200_000)],
    fetchedAt: Date.now(),
  };
}

/**
 * Zehn Minuten Ton als WAV.
 *
 * Kein Video: die Browser dieser Umgebung bringen keinen H.264-Decoder mit, und
 * ein `<video>` spielt eine Tonspur genauso ab — Dauer, Position, Puffer und
 * das Ende der Wiedergabe verhalten sich dabei wie bei einer Folge. Erzeugt
 * statt mitgeliefert, weil zehn Megabyte nicht ins Repository gehören.
 */
function clip() {
  const rate = 8000;
  const seconds = 600;
  const samples = rate * seconds;
  const body = Buffer.alloc(samples * 2);
  for (let i = 0; i < samples; i += 1) {
    body.writeInt16LE(Math.round(2000 * Math.sin(i / 50)), i * 2);
  }
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + body.length, 4);
  header.write("WAVEfmt ", 8);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(rate, 24);
  header.writeUInt32LE(rate * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(body.length, 40);
  return Buffer.concat([header, body]);
}

const CLIP = clip();
const COVER = readFileSync(join(APP, "public", "icon-400.png"));
const MIME = {
  ".html": "text/html", ".js": "text/javascript", ".css": "text/css",
  ".png": "image/png", ".json": "application/json", ".wav": "audio/wav",
};
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "Content-Type" };

createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", "http://localhost");
  const json = (body, status = 200) => {
    res.writeHead(status, { "Content-Type": "application/json", ...CORS });
    res.end(JSON.stringify(body));
  };
  const parts = url.pathname.split("/").filter(Boolean);

  if (req.method === "OPTIONS") {
    res.writeHead(204, CORS);
    return res.end();
  }

  if (parts[0] === "api") {
    switch (parts[1]) {
      case "health":
        return json({
          name: "nori-api",
          version: "mock",
          providers: ["aniworld", "serienstream"],
          features: { tmdb: true, tmdbCacheEntries: 0 },
        });
      case "tmdb": {
        // Derselbe Weg wie beim echten Dienst: der Pfad dahinter ist der
        // TMDB-Pfad, den Schlüssel hält der Server.
        const body = handleTmdb(parts.slice(2).join("/"), url.searchParams);
        if (!body) return json({ error: "TMDB-Pfad nicht freigegeben", kind: "notFound" }, 404);
        return json(body);
      }
      case "catalog": return json(catalog(parts[2]));
      case "series": return json(series(parts[2], decodeURIComponent(parts[3]), url.searchParams.get("season")));
      case "watch": return json(watch(url.searchParams.get("path")));
      case "calendar": return json(calendarPayload(parts[2]));
      case "image":
        res.writeHead(200, { "Content-Type": "image/png", ...CORS });
        return res.end(COVER);
      case "resolve": {
        let body = "";
        for await (const chunk of req) body += chunk;
        const parsed = JSON.parse(body || "{}");
        const pick = parsed.pick ?? { name: "VOE", lang: parsed.preferredLang ?? "DE" };
        /*
         * Ein Pfad mit „kaputt" liefert einen Hosterfehler.
         *
         * Dafür gibt es keinen anderen Weg: Der Fehlerzustand des Players ist
         * der wichtigste Zustand überhaupt — ohne ihn bleibt auf dem Fernseher
         * eine schwarze Fläche stehen, und die sieht aus wie ein Absturz. Er
         * muss also in denselben Lauf, und dazu muss sich ein Fehlschlag
         * bestellen lassen.
         */
        if (String(parsed.episodePath ?? "").includes("kaputt")) {
          return json({ error: "Kein Hoster lieferte einen Stream.", kind: "hoster" }, 502);
        }
        return json({
          kind: "mp4",
          url: `http://127.0.0.1:${PORT}/clip.wav`,
          hoster: pick.name,
          lang: pick.lang,
          referer: "https://example.invalid/",
          playbackUrl: "/clip.wav",
        });
      }
      default: return json({ error: "Unbekannter Pfad", kind: "notFound" }, 404);
    }
  }

  if (url.pathname === "/clip.wav") {
    const range = req.headers.range;
    const match = range ? /bytes=(\d*)-(\d*)/.exec(range) : null;
    if (match) {
      const start = Number(match[1] || 0);
      const end = match[2] ? Number(match[2]) : CLIP.length - 1;
      res.writeHead(206, {
        "Content-Type": "audio/wav",
        "Content-Range": `bytes ${start}-${end}/${CLIP.length}`,
        "Accept-Ranges": "bytes",
        "Content-Length": end - start + 1,
        ...CORS,
      });
      return res.end(CLIP.subarray(start, end + 1));
    }
    res.writeHead(200, {
      "Content-Type": "audio/wav", "Accept-Ranges": "bytes",
      "Content-Length": CLIP.length, ...CORS,
    });
    return res.end(CLIP);
  }

  if (url.pathname === "/cover.png") {
    res.writeHead(200, { "Content-Type": "image/png", ...CORS });
    return res.end(COVER);
  }

  let file = join(DIST, url.pathname === "/" ? "index.html" : url.pathname);
  if (!existsSync(file) || !statSync(file).isFile()) file = join(DIST, "index.html");
  if (!existsSync(file)) {
    res.writeHead(500, { "Content-Type": "text/plain" });
    return res.end("dist/ fehlt — erst `npm run build`.");
  }
  res.writeHead(200, { "Content-Type": MIME[extname(file)] ?? "application/octet-stream", ...CORS });
  res.end(readFileSync(file));
}).listen(PORT, "127.0.0.1", () => {
  console.log(`[Nori:mock] http://127.0.0.1:${PORT}`);
});
