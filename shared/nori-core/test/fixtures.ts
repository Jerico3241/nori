// Dieselben HTML-Ausschnitte wie `native/Tests/NoriCoreTests/Fixtures.swift`.
//
// Absicht: Swift-Kern und TypeScript-Kern werden gegen identische Eingaben
// geprüft. Weicht ein Ergebnis ab, ist die Portierung falsch — nicht der Test.

export const aniworldCatalog = `
<html><body>
  <div class="genre">
    <h3>Action</h3>
    <ul>
      <li><a href="/anime/stream/one-piece" data-alternative-title="One Piece, Wan Pisu">One Piece</a></li>
      <li><a href="/anime/stream/naruto" data-alternative-title="Naruto">Naruto</a></li>
      <li><a href="/impressum">Impressum</a></li>
    </ul>
  </div>
  <div class="genre">
    <h3>Abenteuer</h3>
    <ul>
      <li><a href="https://aniworld.to/anime/stream/one-piece">One Piece</a></li>
    </ul>
  </div>
</body></html>`;

export const aniworldSeries = `
<html><body>
  <div class="series-title"><h1 data-alternativeTitles="Animes Stream: Wan Pisu, One Piece"><span>One Piece</span></h1></div>
  <p class="seri_des" data-full-description="Ruffy will Piratenkönig werden.">Ruffy will Piratenkönig werden. mehr anzeigen</p>
  <div class="seriesCoverBox"><img data-src="/public/img/cover/one-piece-stream-cover-WWoAujz6fnp93s8iZ3F9iqqjO7WtXiIV_220x330.jpg"></div>
  <span itemprop="startDate">1999</span>
  <span itemprop="endDate">2026</span>
  <div data-fsk="12"></div>
  <a class="imdb-link" data-imdb="tt0388629"></a>
  <div class="genres">
    <a class="genreButton" href="/genre/action">Action</a>
    <a class="genreButton" href="/genre/abenteuer">Abenteuer</a>
    <a class="genreButton" href="/gersub">GerSub</a>
  </div>
  <div class="hosterSiteDirectNav">
    <ul>
      <li><a href="/anime/stream/one-piece/staffel-1">1</a></li>
      <li><a href="/anime/stream/one-piece/staffel-2">2</a></li>
      <li><a href="/anime/stream/one-piece/filme">Filme</a></li>
    </ul>
  </div>
  <table class="seasonEpisodesList"><tbody>
    <tr>
      <td>1</td>
      <td class="seasonEpisodeTitle">
        <a href="/anime/stream/one-piece/staffel-1/episode-1"><strong>Ich bin Ruffy</strong><span>I'm Luffy</span></a>
      </td>
      <td><i class="icon" title="Hoster VOE"></i><i class="icon" title="Vidmoly"></i></td>
      <td><img class="flag" title="Deutsch"><img class="flag" title="Mit Untertitel Deutsch"></td>
    </tr>
    <tr>
      <td>2</td>
      <td class="seasonEpisodeTitle">
        <a href="/anime/stream/one-piece/staffel-1/episode-2"><strong>Der Schwertkämpfer</strong><span>The Swordsman</span></a>
      </td>
      <td><i class="icon" title="Hoster VOE"></i></td>
      <td><img class="flag" alt="English"></td>
    </tr>
  </tbody></table>
</body></html>`;

export const aniworldWatch = `
<html><body>
  <h1>One Piece</h1>
  <div class="seasonEpisodeTitle"><strong>Ich bin Ruffy</strong><span>I'm Luffy</span></div>
  <ul>
    <li data-link-id="123456" data-lang-key="1"><h4>VOE</h4></li>
    <li data-link-id="123456" data-lang-key="1"><h4>VOE</h4></li>
    <li data-link-id="234567" data-lang-key="3"><h4>Vidmoly</h4></li>
    <li data-link-id="345678" data-lang-key="2" data-link-target="/redirect/345678"><h4>Filemoon</h4></li>
  </ul>
</body></html>`;

export const aniworldCalendar = `
<html><body>
  <section class="calendarList">
    <h3>Montag, 14.09.2026</h3>
    <a href="/anime/stream/one-piece/staffel-21/episode-1120">
      <h3 class="seriesTitle">One Piece</h3>
      <small>S21E1120 · 09:30</small>
      <img data-src="/public/img/cover/one-piece-stream-cover-WWoAujz6fnp93s8iZ3F9iqqjO7WtXiIV_220x330.jpg">
      <img class="flag" title="Deutsch">
    </a>
    <a href="/anime/stream/one-piece/staffel-21/episode-1120">
      <h3 class="seriesTitle">One Piece</h3>
      <small>S21E1120 · 09:30</small>
      <img class="flag" title="Japanisch">
    </a>
    <a href="/anime/stream/frieren/staffel-2/episode-3">
      <h3 class="seriesTitle">Frieren</h3>
      <small>S2E3 · 18:00</small>
      <img class="flag" title="Mit Untertitel">
    </a>
  </section>
  <section class="calendarList">
    <h3>Dienstag, 15.09.2026</h3>
    <a href="/anime/stream/ohne-zeit/staffel-1/episode-2">
      <h3 class="seriesTitle">Ohne Zeit</h3>
      <small>S1E2</small>
      <img class="flag" title="Deutsch">
    </a>
  </section>
</body></html>`;

export const serienstreamCatalog = `
<html><body>
  <div><h3>Drama</h3></div>
  <ul class="series-list">
    <li class="series-item" data-search="Dexter|Dexter Morgan"><a href="/serie/dexter">Dexter</a></li>
    <li class="series-item"><a href="/serie/breaking-bad">Breaking Bad</a></li>
    <li class="series-item"><a href="/serie/dexter/staffel-1">Staffel 1</a></li>
  </ul>
  <div><h3>Anime</h3></div>
  <ul class="series-list">
    <li class="series-item"><a href="/serie/naruto">Naruto</a></li>
  </ul>
</body></html>`;

export const serienstreamSeries = `
<html><head>
  <meta name="description" content="Aus dem Kopf der Suchmaschine.">
  <meta property="og:image" content="https://s.to/media/images/channel/desktop/dexter-7sqv7dhs?format=avif">
</head><body>
  <h1>Dexter</h1>
  <div class="description-text">Ein Forensiker mit einem Nebengewerbe.</div>
  <nav>
    <a href="/serie/dexter/staffel-1">1</a>
    <a href="/serie/dexter/staffel-2" class="active">2</a>
    <a href="/serie/dexter/filme">Filme</a>
  </nav>
  <div class="episode-row" onclick="location.href='/serie/dexter/staffel-2/episode-1?ref=list'">
    <span class="episode-number-cell">1</span>
    <span class="episode-title-ger">Es ist Zeit</span>
    <span class="episode-title-eng">It's Alive</span>
    <img class="watch-link" alt="VOE">
    <svg class="watch-language flag-german"></svg>
  </div>
  <div class="episode-row">
    <span class="episode-number-cell">2</span>
    <span class="episode-title-ger">Waffenbrüder</span>
    <span class="episode-title-eng">Waiting to Exhale</span>
    <a href="/serie/dexter/staffel-2/episode-2">Ansehen</a>
    <img class="watch-link" alt="Hoster Vidoza">
  </div>
</body></html>`;

export const serienstreamWatch = `
<html><body>
  <h1>Dexter</h1>
  <span class="episode-title-ger">Es ist Zeit</span>
  <span class="episode-title-eng">It's Alive</span>
  <button class="link-box" data-play-url="/r?t=abc123" data-provider-name="VOE" data-language-id="1"></button>
  <button class="link-box" data-play-url="/r?t=def456" data-provider-name="Vidoza" data-language-id="3"></button>
  <button class="link-box" data-play-url="https://fremde.example/play" data-provider-name="Fremd" data-language-id="1"></button>
</body></html>`;

export const serienstreamCalendarJSON = {
  "2026-09-14": [
    {
      url: "/serie/dexter/staffel-2/episode-3",
      poster: "/media/images/channel/desktop/dexter-7sqv7dhs?format=avif",
      title: "Dexter",
      time: "20:15",
      season: 2,
      episode: 3,
      language_id: 1,
    },
    {
      url: "/serie/dexter/staffel-2/episode-3",
      poster: "/media/images/channel/desktop/dexter-7sqv7dhs?format=avif",
      title: "Dexter",
      time: "20:15",
      season: 2,
      episode: 3,
      language_id: 2,
    },
  ],
  "2026-09-15": [
    {
      url: "/serie/ohne-zeit/staffel-1/episode-5",
      poster: "/media/images/channel/desktop/ohne-zeit-1a2b3c4d?format=avif",
      title: "Ohne Zeit",
      // Serienstream schreibt in jede Zeile „00:00" — ein Platzhalter, keine
      // Ausstrahlungszeit. Genau diese Form kommt in der Praxis an.
      time: "00:00",
      season: 1,
      episode: 5,
      language_id: 1,
    },
  ],
  "kein-datum": [{ url: "/serie/ignoriert", title: "Ignoriert", time: "10:00" }],
};
