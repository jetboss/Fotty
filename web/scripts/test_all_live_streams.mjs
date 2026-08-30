import { chromium } from "@playwright/test";

async function main() {
  console.log("==================================================");
  console.log(" 🔍 FOTTY AUTOMATED STREAM PLAYBACK AUDIT");
  console.log("==================================================");

  const res = await fetch("https://www.streamex.net/api/live/matches/all", {
    headers: { "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)" }
  });
  const matches = await res.json();
  console.log(`Fetched ${matches.length} matches from StreamEx catalog.`);

  const now = Date.now();
  // Filter matches that started within last 2.5 hours or are starting in next 10 mins
  const liveMatches = matches.filter(m => {
    if (!m.date) return false;
    const diff = (now - m.date) / 1000 / 60; // minutes since kickoff
    return diff >= -15 && diff <= 150 && m.sources && m.sources.length > 0;
  });

  console.log(`Found ${liveMatches.length} currently live matches with streams:\n`);

  const browser = await chromium.launch({
    executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    headless: true,
    args: ["--no-sandbox", "--autoplay-policy=no-user-gesture-required"]
  });

  const results = [];

  for (const match of liveMatches.slice(0, 10)) {
    const title = match.title;
    console.log(`▶️ Testing: [${match.category}] ${title}`);

    for (const src of match.sources) {
      if (src.source === "admin") continue; // skip P2P
      const embedUrl = `https://embed.st/embed/${src.source}/${src.id}/1`;
      console.log(`   Source [${src.source}]: ${embedUrl}`);

      const context = await browser.newContext({
        userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
        viewport: { width: 820, height: 1180 },
        extraHTTPHeaders: { "Referer": "https://www.streamex.net/" }
      });

      const page = await context.newPage();
      let fetchStatus = null;
      let mediaRequests = 0;
      let errorMsg = null;

      page.on("response", (r) => {
        if (r.url().includes("/fetch")) {
          fetchStatus = r.status();
        }
        if (r.url().includes(".m3u8") || r.url().includes(".ts")) {
          mediaRequests++;
        }
      });

      page.on("pageerror", (err) => {
        errorMsg = err.message;
      });

      try {
        await page.goto(embedUrl, { waitUntil: "domcontentloaded", timeout: 10000 });
      } catch (e) {
        console.log(`      Navigation timeout: ${e.message}`);
      }

      let isPlaying = false;
      let videoInfo = null;

      for (let s = 1; s <= 7; s++) {
        await page.waitForTimeout(1000);
        videoInfo = await page.evaluate(() => {
          const v = document.querySelector("video");
          if (!v) return null;
          return {
            paused: v.paused,
            currentTime: v.currentTime,
            readyState: v.readyState,
            videoWidth: v.videoWidth,
            videoHeight: v.videoHeight,
            src: (v.src || v.currentSrc || "").slice(0, 60)
          };
        });

        if (videoInfo && videoInfo.currentTime > 0.5 && !videoInfo.paused) {
          isPlaying = true;
          break;
        }
      }

      if (isPlaying) {
        console.log(`      ✅ STREAM PLAYING! currentTime: ${videoInfo.currentTime.toFixed(1)}s, ${videoInfo.videoWidth}x${videoInfo.videoHeight}`);
        results.push({ match: title, source: src.source, status: "PLAYING" });
      } else {
        console.log(`      ❌ FAILED. /fetch status: ${fetchStatus}, mediaRequests: ${mediaRequests}, video: ${JSON.stringify(videoInfo)}`);
        results.push({ match: title, source: src.source, status: `FAILED (fetch: ${fetchStatus})` });
      }

      await context.close();
    }
  }

  await browser.close();

  console.log("\n==================================================");
  console.log(" 📊 PLAYBACK AUDIT SUMMARY");
  console.log("==================================================");
  console.table(results);
}

main().catch(err => {
  console.error("Audit error:", err);
  process.exit(1);
});
