import { webkit, chromium } from "@playwright/test";
import fs from "fs";
import path from "path";

const targetUrl = process.argv[2] || "https://embed.st/embed/echo/vasco-da-gama-vs-olimpia-football-1607199/1";
const referer = process.argv[3] || "https://www.streamex.net/";

console.log(`[Stream Tester] Launching WebKit for: ${targetUrl}`);
console.log(`[Stream Tester] Referer: ${referer}`);

async function run() {
  const browser = await chromium.launch({
    executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    headless: true,
    args: ["--no-sandbox", "--autoplay-policy=no-user-gesture-required"]
  });
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

  page.on("request", (req) => {
    console.log(`[Request]: ${req.method()} ${req.url()}`);
  });

  page.on("response", (res) => {
    const url = res.url();
    if (res.status() >= 400 || url.includes("stream") || url.includes("embed") || url.includes("m3u8")) {
      console.log(`[Response ${res.status()}]: ${url}`);
    }
  });

  console.log("[Stream Tester] Navigating to page...");
  try {
    await page.goto(targetUrl, { waitUntil: "domcontentloaded", timeout: 15000 });
  } catch (e) {
    console.log(`[Stream Tester] Navigation error: ${e.message}`);
  }

  console.log("[Stream Tester] Waiting for video element or JW Player setup...");
  for (let i = 1; i <= 15; i++) {
    await page.waitForTimeout(1000);
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
          src: (v.src || v.currentSrc || "").slice(0, 80)
        })),
        htmlPreview: document.body ? document.body.innerText.slice(0, 200).replace(/\n/g, " ") : ""
      };
    });

    console.log(`[Tick ${i}s] State:`, JSON.stringify(state));

    if (state.videosCount > 0 || state.jwState) {
      await page.evaluate(() => {
        try {
          if (window.jwplayer) {
            var jw = window.jwplayer("player") || window.jwplayer();
            if (jw && typeof jw.play === "function") { jw.play(); }
          }
          var v = document.querySelector("video");
          if (v) { v.muted = true; v.play(); }
        } catch(e) {}
      });
    }

    if (state.videos.some(v => v.currentTime > 0.5 && !v.paused)) {
      console.log("✅ PLAYBACK VERIFIED: Video is actively streaming frames!");
      break;
    }
  }

  const screenshotPath = path.resolve("./stream_test_output.png");
  await page.screenshot({ path: screenshotPath });
  console.log(`[Stream Tester] Saved screenshot to ${screenshotPath}`);

  await browser.close();
}

run().catch(err => {
  console.error("[Stream Tester] Fatal:", err);
  process.exit(1);
});
