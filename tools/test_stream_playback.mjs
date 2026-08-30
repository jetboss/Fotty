// The repository keeps its JavaScript runtime dependencies in web/node_modules.
import { webkit } from "../web/node_modules/@playwright/test/index.mjs";
import path from "path";

const targetUrl = process.argv[2] || "https://embed.st/embed/echo/vasco-da-gama-vs-olimpia-football-1607199/1";
const referer = process.argv[3] || "https://www.streamex.net/";
const outputPath = process.argv[4] || "/tmp/fotty-stream-test-output.png";

console.log(`[Stream Tester] Launching WebKit for: ${targetUrl}`);
console.log(`[Stream Tester] Referer: ${referer}`);

async function run() {
  const browser = await webkit.launch({ headless: true });
  const context = await browser.newContext({
    userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
    viewport: { width: 820, height: 1180 },
    extraHTTPHeaders: {
      "Referer": referer
    }
  });

  const page = await context.newPage();

  page.on("console", (msg) => {
    console.log(`[Console ${msg.type()}]: ${msg.text()}`);
  });

  page.on("pageerror", (err) => {
    console.log(`[Page Error]: ${err.message}`);
  });

  page.on("requestfailed", (req) => {
    console.log(`[Request Failed]: ${req.url()} (${req.failure()?.errorText})`);
  });

  page.on("response", (res) => {
    const url = res.url();
    if (url.includes(".m3u8") || url.includes(".ts") || url.includes("manifest")) {
      console.log(`[Media Response ${res.status()}]: ${url.slice(0, 100)}...`);
    }
  });

  console.log("[Stream Tester] Navigating to page...");
  try {
    await page.goto(targetUrl, { waitUntil: "domcontentloaded", timeout: 15000 });
  } catch (e) {
    console.log(`[Stream Tester] Navigation error: ${e.message}`);
  }

  console.log("[Stream Tester] Waiting for video element or JW Player setup...");
  let playbackVerified = false;
  let firstObservedTime = null;
  for (let i = 1; i <= 15; i++) {
    await page.waitForTimeout(1000);
    if (i === 2) {
      await page.evaluate(() => {
        const playButton = document.querySelector(".jw-icon-playback, [aria-label*='Play'], button[title*='Play']");
        if (playButton instanceof HTMLElement) playButton.click();
        for (const video of document.querySelectorAll("video")) {
          video.muted = true;
          void video.play().catch(() => {});
        }
      });
    }
    const state = await page.evaluate(() => {
      const videos = Array.from(document.querySelectorAll("video"));
      const jw = typeof window.jwplayer === "function" ? window.jwplayer("player") || window.jwplayer() : null;
      let jwState = null;
      if (jw && typeof jw.getState === "function") {
        try { jwState = jw.getState(); } catch (e) { jwState = "err: " + e.message; }
      }
      return {
        videosCount: videos.length,
        jwState: jwState,
        videos: videos.map(v => ({
          paused: v.paused,
          currentTime: v.currentTime,
          duration: v.duration,
          readyState: v.readyState,
          videoWidth: v.videoWidth,
          videoHeight: v.videoHeight,
          src: v.src || v.currentSrc
        })),
        htmlPreview: document.body ? document.body.innerText.slice(0, 200) : ""
      };
    });

    console.log(`[Tick ${i}s] State:`, JSON.stringify(state));

    const decodedVideo = state.videos.find(v => v.readyState >= 2 && v.videoWidth > 0 && v.videoHeight > 0);
    if (decodedVideo && firstObservedTime === null) firstObservedTime = decodedVideo.currentTime;
    if (decodedVideo && decodedVideo.currentTime - firstObservedTime > 0.5 && !decodedVideo.paused) {
      playbackVerified = true;
      console.log("✅ PLAYBACK VERIFIED: decoded dimensions and advancing playhead observed.");
      break;
    }
  }

  const screenshotPath = path.resolve(outputPath);
  await page.screenshot({ path: screenshotPath });
  console.log(`[Stream Tester] Saved screenshot to ${screenshotPath}`);

  await browser.close();
  if (!playbackVerified) {
    console.error("❌ PLAYBACK NOT VERIFIED: no decoded, advancing video was observed within 15 seconds.");
    process.exitCode = 2;
  }
}

run().catch(err => {
  console.error("[Stream Tester] Fatal:", err);
  process.exit(1);
});
