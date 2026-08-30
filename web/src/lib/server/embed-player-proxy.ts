const IOS_SAFARI_USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";

const EXPOSESTRAT_ORIGIN = "https://exposestrat.com";
const EMBED_ST_ORIGIN = "https://embed.st";
const EMBED_HD_ORIGIN = "https://embedhd.org";
const STREAMEX_REFERER = "https://www.streamex.net/";

const AD_SCRIPT_PATTERN =
  /<(script|iframe)[^>]*(llvpn\.com|aclib|adcashexp|sculshbises|histats|tag\.min\.js|ad\.html|dontfoid)[^>]*>[\s\S]*?<\/\1>/gi;

const AD_SCRIPT_SRC_PATTERN = /<script[^>]+src="[^"]*(llvpn|aclib|adcashexp|sculshbises|histats|tag\.min|ad\.html)[^"]*"[^>]*>\s*<\/script>/gi;

function extractFirstMatch(html: string, pattern: RegExp) {
  const match = html.match(pattern);
  return match?.[1]?.trim() || null;
}

async function fetchText(url: string, referer?: string, userAgent = IOS_SAFARI_USER_AGENT) {
  const response = await fetch(url, {
    headers: {
      Accept: "text/html,application/xhtml+xml",
      "User-Agent": userAgent,
      ...(referer ? { Referer: referer } : {}),
    },
    cache: "no-store",
  });
  if (!response.ok) return null;
  return response.text();
}

export function embedStPlayerUrl(source: string, id: string, streamNo: number) {
  return `${EMBED_ST_ORIGIN}/embed/${encodeURIComponent(source)}/${encodeURIComponent(id)}/${streamNo}`;
}

export async function resolveExposestratPlayerUrl(
  source: string,
  id: string,
  streamNo: number,
  userAgent = IOS_SAFARI_USER_AGENT
) {
  const embedStUrl = embedStPlayerUrl(source, id, streamNo);
  const embedStHtml = await fetchText(embedStUrl, STREAMEX_REFERER, userAgent);
  if (!embedStHtml) return null;

  const embedHdPath = extractFirstMatch(embedStHtml, /iframe[^>]+src="([^"]+embedhd\.org[^"]+)"/i);
  if (!embedHdPath) return null;

  const embedHdUrl = embedHdPath.startsWith("http") ? embedHdPath : `https:${embedHdPath}`;
  const embedHdHtml = await fetchText(embedHdUrl, embedStUrl, userAgent);
  if (!embedHdHtml) return null;

  const liveId = extractFirstMatch(embedHdHtml, /fid\s*=\s*["']([^"']+)["']/i);
  if (!liveId) return null;

  return `${EXPOSESTRAT_ORIGIN}/maestrohd1.php?player=desktop&live=${encodeURIComponent(liveId)}`;
}

function absolutizeEmbedAssetUrls(html: string, origin: string) {
  return html
    .replace(/\b(href|src)=["'](?!https?:|\/\/|data:|#)([^"']+)["']/gi, (_, attr, path) => {
      const normalized = path.startsWith("/") ? path : `/${path}`;
      return `${attr}="${origin}${normalized}"`;
    })
    .replace(/\b(href|src)=["'](\/[^"']+)["']/gi, (_, attr, path) => `${attr}="${origin}${path}"`);
}

function stripEmbedAdNoise(html: string) {
  return html
    .replace(AD_SCRIPT_PATTERN, "")
    .replace(AD_SCRIPT_SRC_PATTERN, "")
    .replace(/<script[^>]*src=["'][^"']*llvpn[^"']*["'][^>]*>\s*<\/script>/gi, "")
    .replace(/<script[^>]*>[\s\S]*?llvpn\.com[\s\S]*?<\/script>/gi, "")
    .replace(/<script[^>]*>[\s\S]*?aclib\.runPop[\s\S]*?<\/script>/gi, "")
    .replace(/<script[^>]*>[\s\S]*?dontfoid[\s\S]*?<\/script>/gi, "")
    .replace(/<script[^>]*>[\s\S]*?Histats[\s\S]*?<\/script>/gi, "")
    .replace(/<script[^>]*>\(\(\)=>\{let a=\(\)=>\{document\.body\.insertAdjacentHTML[\s\S]*?<\/script>/gi, "")
    .replace(/<noscript>[\s\S]*?histats[\s\S]*?<\/noscript>/gi, "")
    .replace(/<div[^>]+id=["']dontfoid["'][^>]*>[\s\S]*?<\/div>/gi, "");
}

export function buildEmbedPlaybackInjection(origin: string) {
  return `
<base href="${origin}/" />
<script>
(function () {
  var lastPlayingAt = 0;
  var hadPlaying = false;

  function purge() {
    try {
      document.querySelectorAll('#dontfoid, [id*="dontfoid"], [znid], iframe[id="close"], iframe[src*="ad.html"]').forEach(function (node) {
        node.remove();
      });
    } catch (e) {}
  }
  purge();
  setInterval(purge, 400);

  function emitPlayback(eventName) {
    try {
      window.parent.postMessage({ type: "fotty:playback-" + eventName }, "*");
    } catch (e) {}
  }

  function noteDecodedProgress(video) {
    try {
      var currentTime = Number(video.currentTime) || 0;
      var previousTime = Number(video.__fottyLastCurrentTime) || 0;
      video.__fottyLastCurrentTime = currentTime;
      if (
        video.paused ||
        video.ended ||
        video.readyState < 2 ||
        video.videoWidth <= 0 ||
        currentTime <= previousTime + 0.05
      ) {
        return false;
      }
      hadPlaying = true;
      lastPlayingAt = Date.now();
      if (!video.__fottyDecodedStarted) {
        video.__fottyDecodedStarted = true;
        emitPlayback("started");
      }
      emitPlayback("pulse");
      return true;
    } catch (e) {
      return false;
    }
  }

  function attachVideoWatchers(video) {
    if (!video || video.__fottyPlaybackWatched) return;
    video.__fottyPlaybackWatched = true;
    video.__fottyLastCurrentTime = Number(video.currentTime) || 0;
    video.addEventListener("timeupdate", function () { noteDecodedProgress(video); });
    video.addEventListener("waiting", function () {
      emitPlayback("waiting");
    });
    video.addEventListener("ended", function () {
      emitPlayback("stalled");
    });
    video.addEventListener("error", function () {
      emitPlayback("error");
    });
  }

  function scanForVideo() {
    document.querySelectorAll("video").forEach(attachVideoWatchers);
  }
  scanForVideo();
  setInterval(scanForVideo, 500);

  setInterval(function () {
    var progressed = false;
    try {
      progressed = Array.prototype.slice.call(document.querySelectorAll("video")).some(noteDecodedProgress);
    } catch (e) {}
    if (progressed) return;
    if (hadPlaying && lastPlayingAt > 0 && Date.now() - lastPlayingAt > 20000) {
      hadPlaying = false;
      lastPlayingAt = 0;
      emitPlayback("stalled");
    }
  }, 2000);

  function kickEmbedPlayback(unmute) {
    try {
      if (unmute && typeof window.WSUnmute === "function") window.WSUnmute();
      document.querySelectorAll("video").forEach(function (video) {
        if (unmute) video.muted = false;
        else video.muted = true;
        video.playsInline = true;
        video.setAttribute("playsinline", "");
        var promise = video.play && video.play();
        if (promise && promise.catch) promise.catch(function () {});
      });
      ["#pl_but", ".jw-display-icon-display", ".jw-icon-display", "[aria-label=\\"Play\\"]"].forEach(function (sel) {
        document.querySelectorAll(sel).forEach(function (node) { node.click(); });
      });
    } catch (e) {}
  }

  window.addEventListener("message", function (event) {
    if (!event || !event.data || !event.data.type) return;
    if (event.data.type === "fotty:unmute") {
      kickEmbedPlayback(true);
      return;
    }
    if (event.data.type === "fotty:play") {
      kickEmbedPlayback(false);
    }
  });

  kickEmbedPlayback(false);
  document.addEventListener("DOMContentLoaded", function () {
    kickEmbedPlayback(false);
  });
  setTimeout(function () { kickEmbedPlayback(false); }, 300);
  setTimeout(function () { kickEmbedPlayback(false); }, 1200);

  setInterval(function () {
    try {
      document.querySelectorAll("video").forEach(function (video) {
        if (!video.paused && !video.ended && video.readyState >= 2) return;
        video.muted = true;
        video.playsInline = true;
        var promise = video.play && video.play();
        if (promise && promise.catch) promise.catch(function () {});
      });
      ["#pl_but", ".jw-display-icon-display", "[aria-label=\\"Play\\"]"].forEach(function (sel) {
        document.querySelectorAll(sel).forEach(function (node) { node.click(); });
      });
    } catch (e) {}
  }, 900);
})();
</script>`;
}

function injectIntoHtmlHead(html: string, injection: string) {
  if (html.match(/<head[^>]*>/i)) {
    return html.replace(/<head([^>]*)>/i, `<head$1>\n${injection}\n`);
  }
  return `<head>${injection}</head>\n${html}`;
}

function sanitizeEmbedStHtml(html: string) {
  let cleaned = stripEmbedAdNoise(html);
  cleaned = absolutizeEmbedAssetUrls(cleaned, EMBED_ST_ORIGIN);
  return injectIntoHtmlHead(cleaned, buildEmbedPlaybackInjection(EMBED_ST_ORIGIN));
}

function sanitizeExposestratHtml(html: string, watchToken?: string) {
  let cleaned = stripEmbedAdNoise(html);
  cleaned = absolutizeEmbedAssetUrls(cleaned, EXPOSESTRAT_ORIGIN);

  const tokenLiteral = watchToken ? JSON.stringify(watchToken) : "null";
  const injection = `
<base href="${EXPOSESTRAT_ORIGIN}/" />
<script>
(function () {
  var fottyWatchToken = ${tokenLiteral} || new URLSearchParams(window.location.search).get("watchToken");

  function proxyHlsUrl(url) {
    try {
      var value = String(url || "");
      if (value.indexOf("/api/embed/hls") !== -1) return url;
      if (value.indexOf("zohanayaan") === -1 && value.indexOf(".m3u8") === -1 && value.indexOf("/hls/") === -1 && value.indexOf(".ts") === -1 && value.indexOf("cloudfront.net") === -1 && value.indexOf("exposestrat.com") === -1) {
        return url;
      }
      var absolute = value;
      if (absolute.indexOf("http") !== 0) {
        absolute = "${EXPOSESTRAT_ORIGIN}" + (absolute.startsWith("/") ? absolute : "/" + absolute);
      }
      var proxied = window.location.origin + "/api/embed/hls?url=" + encodeURIComponent(absolute);
      if (fottyWatchToken) proxied += "&watchToken=" + encodeURIComponent(fottyWatchToken);
      return proxied;
    } catch (e) {
      return url;
    }
  }

  var originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function (input, init) {
      var url = typeof input === "string" ? input : input && input.url;
      var proxied = proxyHlsUrl(url);
      if (proxied !== url) {
        return originalFetch.call(this, proxied, init);
      }
      return originalFetch.apply(this, arguments);
    };
  }

  var openRequest = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    var args = Array.prototype.slice.call(arguments);
    args[1] = proxyHlsUrl(url);
    return openRequest.apply(this, args);
  };

  function purge() {
    try {
      document.querySelectorAll('#dontfoid, [id*="dontfoid"], [znid], iframe[src*="ad.html"], iframe[id="close"]').forEach(function (node) {
        node.remove();
      });
    } catch (e) {}
  }
  purge();
  setInterval(purge, 400);

  window.addEventListener("message", function (event) {
    if (!event || !event.data || event.data.type !== "fotty:unmute") return;
    try {
      if (typeof window.WSUnmute === "function") window.WSUnmute();
    } catch (e) {}
  });

  function emitPlayback(eventName) {
    try {
      window.parent.postMessage({ type: "fotty:playback-" + eventName }, "*");
    } catch (e) {}
  }

  function noteDecodedProgress(video) {
    try {
      var currentTime = Number(video.currentTime) || 0;
      var previousTime = Number(video.__fottyLastCurrentTime) || 0;
      video.__fottyLastCurrentTime = currentTime;
      if (
        video.paused ||
        video.ended ||
        video.readyState < 2 ||
        video.videoWidth <= 0 ||
        currentTime <= previousTime + 0.05
      ) {
        return;
      }
      if (!video.__fottyDecodedStarted) {
        video.__fottyDecodedStarted = true;
        emitPlayback("started");
      }
      emitPlayback("pulse");
    } catch (e) {}
  }

  function attachVideoWatchers(video) {
    if (!video || video.__fottyPlaybackWatched) return;
    video.__fottyPlaybackWatched = true;
    video.__fottyLastCurrentTime = Number(video.currentTime) || 0;
    video.addEventListener("timeupdate", function () { noteDecodedProgress(video); });
    video.addEventListener("error", function () { emitPlayback("error"); });
  }

  function scanForVideo() {
    document.querySelectorAll("video").forEach(attachVideoWatchers);
  }
  scanForVideo();
  setInterval(scanForVideo, 500);
  setInterval(function () {
    try {
      document.querySelectorAll("video").forEach(noteDecodedProgress);
    } catch (e) {}
  }, 2000);

  setInterval(function () {
    try {
      document.querySelectorAll("video").forEach(function (video) {
        video.muted = true;
        video.playsInline = true;
        var promise = video.play && video.play();
        if (promise && promise.catch) promise.catch(function () {});
      });
      ["#pl_but", ".jw-display-icon-display", "[aria-label=\\"Play\\"]"].forEach(function (sel) {
        document.querySelectorAll(sel).forEach(function (node) { node.click(); });
      });
    } catch (e) {}
  }, 900);
})();
</script>`;

  return injectIntoHtmlHead(cleaned, injection);
}

export async function buildProxiedEmbedPlayerHtml(
  source: string,
  id: string,
  streamNo: number,
  watchToken?: string,
  userAgent = IOS_SAFARI_USER_AGENT
) {
  const embedStUrl = embedStPlayerUrl(source, id, streamNo);
  const embedStHtml = await fetchText(embedStUrl, STREAMEX_REFERER, userAgent);
  if (embedStHtml) {
    return sanitizeEmbedStHtml(embedStHtml);
  }

  const playerUrl = await resolveExposestratPlayerUrl(source, id, streamNo, userAgent);
  if (!playerUrl) return null;

  const playerHtml = await fetchText(playerUrl, EMBED_HD_ORIGIN, userAgent);
  if (!playerHtml) return null;

  return sanitizeExposestratHtml(playerHtml, watchToken);
}
