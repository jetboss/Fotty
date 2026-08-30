#!/usr/bin/env node

// Measures real decoded playback across a representative set of currently-live
// Nexus source families. Catalog health and iframe/page load are deliberately not
// counted as playback success.

import { webkit } from "../web/node_modules/@playwright/test/index.mjs";

const catalogURL = process.env.FOTTY_CATALOG_URL || "https://www.streamex.net/api/live/matches/all";
const samplesPerFamily = Number(process.env.FOTTY_SAMPLES_PER_FAMILY || 3);
const streamVariants = Number(process.env.FOTTY_STREAM_VARIANTS || 2);
const concurrency = Number(process.env.FOTTY_MATRIX_CONCURRENCY || 4);
const observationSeconds = Number(process.env.FOTTY_OBSERVATION_SECONDS || 12);
const holdAfterDecodeSeconds = Number(process.env.FOTTY_HOLD_AFTER_DECODE_SECONDS || 0);
const families = (process.env.FOTTY_SOURCE_FAMILIES || "admin,delta,golf,hotel,echo")
  .split(",")
  .map(value => value.trim().toLowerCase())
  .filter(Boolean);

const userAgent = "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";

function refererFor(family) {
  if (family === "hotel") return "https://www.score808live.tv/";
  if (family === "echo") return "https://www.vipleague.im/";
  return "https://www.streamex.net/";
}

function embedURL(source, streamNumber) {
  return `https://embed.st/embed/${encodeURIComponent(source.source)}/${encodeURIComponent(source.id)}/${streamNumber}`;
}

function isNearLiveWindow(event, now = Date.now()) {
  const kickoff = Number(event.date || 0);
  return kickoff >= now - 3 * 60 * 60 * 1000 && kickoff <= now + 30 * 60 * 1000;
}

async function snapshotFrames(page) {
  const snapshots = [];
  for (const frame of page.frames()) {
    try {
      const frameState = await frame.evaluate(() => {
        const videos = Array.from(document.querySelectorAll("video")).map(video => ({
          currentTime: Number.isFinite(video.currentTime) ? video.currentTime : 0,
          paused: video.paused,
          ended: video.ended,
          readyState: video.readyState,
          width: video.videoWidth,
          height: video.videoHeight,
          error: video.error ? `${video.error.code}:${video.error.message || "media error"}` : null
        }));
        let jwState = null;
        try {
          const jw = typeof window.jwplayer === "function" ? window.jwplayer("player") || window.jwplayer() : null;
          if (jw && typeof jw.getState === "function") jwState = jw.getState();
        } catch {}
        return {
          url: location.href,
          title: document.title,
          body: document.body ? document.body.innerText.slice(0, 160) : "",
          videos,
          jwState
        };
      });
      snapshots.push(frameState);
    } catch {}
  }
  return snapshots;
}

async function minimalPlaybackAssist(page) {
  for (const frame of page.frames()) {
    try {
      await frame.evaluate(() => {
        for (const video of document.querySelectorAll("video")) {
          video.playsInline = true;
          video.muted = true;
          void video.play().catch(() => {});
        }
        const selectors = [
          ".jw-icon-playback",
          ".vjs-big-play-button",
          "[aria-label='Play']",
          "button[title='Play']",
          "[data-player-play]"
        ];
        for (const selector of selectors) {
          const element = document.querySelector(selector);
          if (element instanceof HTMLElement) {
            element.click();
            break;
          }
        }
      });
    } catch {}
  }
}

function decodedPlaybackState(snapshots) {
  const videos = snapshots.flatMap(frame => frame.videos);
  const decoded = videos.filter(video => video.readyState >= 2 && video.width >= 16 && video.height >= 16);
  return {
    decodedCount: decoded.length,
    furthestTime: decoded.reduce((maximum, video) => Math.max(maximum, video.currentTime), 0),
    playing: decoded.some(video => !video.paused && !video.ended)
  };
}

async function probe(browser, candidate) {
  const startedAt = Date.now();
  const mediaResponses = [];
  const requestFailures = [];
  const popupURLs = [];
  const context = await browser.newContext({
    userAgent,
    viewport: { width: 1024, height: 768 }
  });
  const page = await context.newPage();
  page.on("popup", popup => {
    popupURLs.push(popup.url());
    void popup.close();
  });
  page.on("response", response => {
    const url = response.url().toLowerCase();
    if (url.includes(".m3u8") || url.includes("manifest") || url.includes(".mpd")) {
      mediaResponses.push({ status: response.status(), url: response.url() });
    }
  });
  page.on("requestfailed", request => {
    const url = request.url().toLowerCase();
    if (url.includes(".m3u8") || url.includes("manifest") || url.includes(".mpd")) {
      requestFailures.push({ error: request.failure()?.errorText || "request failed", url: request.url() });
    }
  });

  let navigationStatus = null;
  let navigationError = null;
  try {
    const response = await page.goto(candidate.url, {
      waitUntil: "domcontentloaded",
      timeout: 15_000,
      // Apply the catalog/provider referer to the embed navigation only. A
      // context-wide Referer override also leaks onto HLS requests and replaces
      // the required embed.st media referer, producing an audit-created 403.
      referer: candidate.referer
    });
    navigationStatus = response?.status() ?? null;
  } catch (error) {
    navigationError = error instanceof Error ? error.message : String(error);
  }

  let firstDecodedTime = null;
  let firstDecodedAt = null;
  let playbackVerified = false;
  let assisted = false;
  let lastSnapshot = [];
  let verificationMediaTime = null;

  for (let second = 1; second <= observationSeconds; second++) {
    await page.waitForTimeout(1000);
    if (second === 4) {
      assisted = true;
      await minimalPlaybackAssist(page);
    }
    lastSnapshot = await snapshotFrames(page);
    const state = decodedPlaybackState(lastSnapshot);
    if (state.decodedCount > 0 && firstDecodedTime === null) {
      firstDecodedTime = state.furthestTime;
      firstDecodedAt = Date.now();
    }
    if (state.playing && firstDecodedTime !== null && state.furthestTime > firstDecodedTime + 0.5) {
      playbackVerified = true;
      verificationMediaTime = state.furthestTime;
      break;
    }
  }

  let sustainedPlaybackVerified = null;
  let sustainedPlaybackSeconds = null;
  let longestFrozenMs = null;
  let finalPlaybackState = null;
  if (playbackVerified && holdAfterDecodeSeconds > 0 && verificationMediaTime !== null) {
    const holdStartedAt = Date.now();
    let lastAdvancingAt = holdStartedAt;
    let lastMediaTime = verificationMediaTime;
    let maximumMediaTime = verificationMediaTime;
    longestFrozenMs = 0;
    for (let second = 1; second <= holdAfterDecodeSeconds; second++) {
      await page.waitForTimeout(1000);
      lastSnapshot = await snapshotFrames(page);
      const state = decodedPlaybackState(lastSnapshot);
      maximumMediaTime = Math.max(maximumMediaTime, state.furthestTime);
      if (state.furthestTime > lastMediaTime + 0.1) {
        lastMediaTime = state.furthestTime;
        lastAdvancingAt = Date.now();
      } else {
        longestFrozenMs = Math.max(longestFrozenMs, Date.now() - lastAdvancingAt);
      }
    }
    sustainedPlaybackSeconds = Math.max(0, maximumMediaTime - verificationMediaTime);
    finalPlaybackState = decodedPlaybackState(lastSnapshot);
    // Judge the complete hold window, not one final readyState snapshot. A
    // healthy HLS player can transiently report HAVE_METADATA between segment
    // downloads even after advancing for the full window.
    sustainedPlaybackVerified = sustainedPlaybackSeconds >= Math.max(1, holdAfterDecodeSeconds * 0.7)
      && longestFrozenMs < 10_000;
  }

  const result = {
    eventID: candidate.eventID,
    title: candidate.title,
    category: candidate.category,
    family: candidate.family,
    streamNumber: candidate.streamNumber,
    url: candidate.url,
    referer: candidate.referer,
    navigationStatus,
    navigationError,
    finalURL: page.url(),
    playbackVerified,
    sustainedPlaybackVerified,
    holdAfterDecodeSeconds,
    sustainedPlaybackSeconds,
    longestFrozenMs,
    finalPlaybackState,
    playbackMode: playbackVerified ? (firstDecodedAt && firstDecodedAt - startedAt < 4_000 ? "unassisted" : assisted ? "minimal-assist" : "unassisted") : null,
    firstDecodedMs: firstDecodedAt ? firstDecodedAt - startedAt : null,
    elapsedMs: Date.now() - startedAt,
    mediaResponses,
    requestFailures,
    popupCount: popupURLs.length,
    frames: lastSnapshot
  };

  await context.close();
  return result;
}

async function worker(browser, queue, results) {
  while (queue.length > 0) {
    const candidate = queue.shift();
    if (!candidate) return;
    const result = await probe(browser, candidate);
    results.push(result);
    const marker = result.playbackVerified && result.sustainedPlaybackVerified !== false ? "PASS" : "FAIL";
    const media = result.mediaResponses.map(item => item.status).join(",") || "none";
    console.error(`${marker.padEnd(4)} ${result.family.padEnd(6)} #${result.streamNumber} ${result.title} media=${media} final=${result.finalURL}`);
  }
}

async function main() {
  const response = await fetch(catalogURL, { headers: { Accept: "application/json", "User-Agent": userAgent } });
  if (!response.ok) throw new Error(`Catalog returned HTTP ${response.status}`);
  const catalog = await response.json();
  if (!Array.isArray(catalog)) throw new Error("Catalog response is not an array");

  // Do not pass the function directly to `filter`: its second argument would be
  // the array index and would override the helper's default `now` value.
  const liveEvents = catalog.filter(event => isNearLiveWindow(event));
  const candidates = [];
  for (const family of families) {
    const familyEvents = liveEvents
      .filter(event => Array.isArray(event.sources) && event.sources.some(source => source.source?.toLowerCase() === family))
      .slice(0, samplesPerFamily);
    for (const event of familyEvents) {
      const source = event.sources.find(item => item.source?.toLowerCase() === family);
      for (let streamNumber = 1; streamNumber <= streamVariants; streamNumber++) {
        candidates.push({
          eventID: event.id,
          title: event.title || event.id,
          category: event.category || "unknown",
          family,
          streamNumber,
          referer: refererFor(family),
          url: embedURL(source, streamNumber)
        });
      }
    }
  }

  console.error(`Catalog events: ${catalog.length}; near-live events: ${liveEvents.length}; candidates: ${candidates.length}`);
  const browser = await webkit.launch({ headless: true });
  const queue = [...candidates];
  const results = [];
  await Promise.all(Array.from({ length: Math.min(concurrency, candidates.length) }, () => worker(browser, queue, results)));
  await browser.close();

  const familySummary = Object.fromEntries(families.map(family => {
    const familyResults = results.filter(result => result.family === family);
    return [family, {
      attempted: familyResults.length,
      playable: familyResults.filter(result => result.playbackVerified).length,
      sustainedPlayable: familyResults.filter(result => result.sustainedPlaybackVerified === true).length,
      unassisted: familyResults.filter(result => result.playbackMode === "unassisted").length,
      minimallyAssisted: familyResults.filter(result => result.playbackMode === "minimal-assist").length
    }];
  }));
  const report = {
    generatedAt: new Date().toISOString(),
    catalogURL,
    catalogEvents: catalog.length,
    nearLiveEvents: liveEvents.length,
    attempted: results.length,
    playable: results.filter(result => result.playbackVerified).length,
    sustainedPlayable: results.filter(result => result.sustainedPlaybackVerified === true).length,
    holdAfterDecodeSeconds,
    familySummary,
    results
  };
  // Keep network-controlled audit data off the filesystem. Stdout is the
  // structured report; callers that need an artifact can choose an explicit
  // destination with normal shell redirection.
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  const passed = holdAfterDecodeSeconds > 0 ? report.sustainedPlayable > 0 : report.playable > 0;
  process.exitCode = passed ? 0 : 2;
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
