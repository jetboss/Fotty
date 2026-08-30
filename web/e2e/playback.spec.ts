import { expect, test } from "@playwright/test";
import { createCipheriv, createHash, createHmac } from "node:crypto";

const configuredCid = process.env.FOTTY_P2P_E2E_CID?.trim();
const watchStreamSecret = process.env.FOTTY_WATCH_STREAM_SECRET?.trim();

function issueE2EWatchToken() {
  if (!watchStreamSecret) return null;
  const payload = JSON.stringify({
    subject: createHmac("sha256", watchStreamSecret).update("e2e-smoke").digest("base64url"),
    entitlement: "plus",
    nonce: "e2e-playback",
    exp: Date.now() + 10 * 60 * 1000,
  });
  const iv = Buffer.alloc(12, 7);
  const key = createHash("sha256")
    .update(`fotty-watch-stream-v2:${watchStreamSecret}`)
    .digest();
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  cipher.setAAD(Buffer.from("fotty-watch-stream-v2", "utf8"));
  const encrypted = Buffer.concat([cipher.update(payload, "utf8"), cipher.final()]);
  return `v2.${iv.toString("base64url")}.${encrypted.toString("base64url")}.${cipher
    .getAuthTag()
    .toString("base64url")}`;
}

test("real browser playback test for P2P stream", async ({ page }, testInfo) => {
  test.skip(!configuredCid, "Set FOTTY_P2P_E2E_CID when a production-like broker is available.");
  test.skip(!watchStreamSecret, "Set FOTTY_WATCH_STREAM_SECRET to match the test web server.");
  test.setTimeout(120000);
  const screenshotPath = testInfo.outputPath("playback-success.png");
  const watchToken = issueE2EWatchToken() as string;
  
  // Set up console log listeners to check HLS.js debug and potential errors
  page.on("console", (msg) => {
    console.log(`[Browser Console] ${msg.type()}: ${msg.text()}`);
  });
  page.on("response", (response) => {
    if (response.status() >= 400) {
      console.log(`[Browser Response] ${response.status()} ${response.url()}`);
    }
  });

  // 1. Load the home page first to establish the domain context in localStorage
  console.log("Loading home page...");
  await page.goto("/", { waitUntil: "domcontentloaded" });

  // 2. Inject a signed-in session with active 'plus' entitlement directly into localStorage
  console.log("Injecting paid Fotty Plus session...");
  await page.route(/\/api\/stream\/token/, (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ watchToken, expiresIn: 3_600 }),
    })
  );
  await page.route(/\/api\/pocketbase\/entitlement/, (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ entitlement: "plus", entitlementExpiresAt: null }),
    })
  );
  await page.evaluate((token) => {
    localStorage.setItem("fotty.web.auth.v1", JSON.stringify({
      email: "smoke@fotty.app",
      signedInAt: new Date().toISOString(),
      provider: "local",
      entitlement: "plus",
      token,
    }));
  }, watchToken);

  // 3. Navigate directly to the watch page with the known active P2P stream CID
  const activeCid = configuredCid as string;
  console.log(`Navigating to watch page for stream: ${activeCid}`);
  const watchParams = new URLSearchParams({
    cid: activeCid,
    title: "E2E Test Live Stream",
    kind: "channel",
    playback: "p2p",
  });
  await page.goto(`/watch/index?${watchParams.toString()}`, { waitUntil: "domcontentloaded" });

  // 4. Wait for player containers and video element to load
  console.log("Waiting for video element to mount...");
  const videoElement = page.locator("video");
  await expect(videoElement).toBeVisible({ timeout: 80_000 });

  // Chromium may require an explicit user gesture for unmuted autoplay.
  const playStreamButton = page.getByRole("button", { name: "Play stream" });
  if (await playStreamButton.isVisible().catch(() => false)) {
    await playStreamButton.click();
  }

  // Give the stream engine time to start playback and fetch initial segments.
  console.log("Allowing playback to start...");
  await expect.poll(
    () => videoElement.evaluate((video: HTMLVideoElement) => video.currentTime),
    { timeout: 30_000 }
  ).toBeGreaterThan(0);

  const initialTime = await videoElement.evaluate((video: HTMLVideoElement) => video.currentTime);
  await page.waitForTimeout(3_000);

  // 5. Query and verify actual video element state inside the browser
  const playerState = await videoElement.evaluate((video: HTMLVideoElement) => {
    return {
      paused: video.paused,
      currentTime: video.currentTime,
      readyState: video.readyState,
      videoWidth: video.videoWidth,
      videoHeight: video.videoHeight,
      networkState: video.networkState,
    };
  });

  console.log("Verified Live Video Player State in Browser:", playerState);

  // Assert that video has loaded meta/media frame data successfully
  // readyState >= 2 means HAVE_CURRENT_DATA or higher, indicating frames are available and video can play
  expect(playerState.readyState).toBeGreaterThanOrEqual(2);
  expect(playerState.videoWidth).toBeGreaterThan(0);
  expect(playerState.videoHeight).toBeGreaterThan(0);
  expect(playerState.currentTime).toBeGreaterThan(initialTime);
  console.log(`Playback successfully running in browser! Current Time: ${playerState.currentTime}s, ReadyState: ${playerState.readyState}`);

  // 6. Capture full screenshot of the playing web app stream
  console.log(`Taking verification screenshot at: ${screenshotPath}`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  console.log("Screenshot successfully captured and saved!");
});
