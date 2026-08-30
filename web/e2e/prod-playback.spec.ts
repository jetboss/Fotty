import { expect, test } from "@playwright/test";

const runProductionPlayback = process.env.FOTTY_RUN_PROD_PLAYBACK_E2E === "1";

test.skip(!runProductionPlayback, "Set FOTTY_RUN_PROD_PLAYBACK_E2E=1 to run against production.");

test("production active playback test using real pocketbase user session", async ({ page }, testInfo) => {
  test.setTimeout(60000);
  const email = process.env.FOTTY_PROD_TEST_EMAIL;
  const password = process.env.FOTTY_PROD_TEST_PASSWORD;
  const activeCid = process.env.FOTTY_PROD_TEST_CID;
  const productionBaseUrl = process.env.FOTTY_PROD_BASE_URL || "https://fotty.pixel-invoice.com";
  const pocketBaseUrl = process.env.FOTTY_PROD_POCKETBASE_URL || "https://fotty-api.pixel-invoice.com";
  const screenshotPath = testInfo.outputPath("prod-playback.png");

  if (!email || !password || !activeCid) {
    throw new Error(
      "Production playback requires FOTTY_PROD_TEST_EMAIL, FOTTY_PROD_TEST_PASSWORD, and FOTTY_PROD_TEST_CID."
    );
  }

  // Set up console log listeners to monitor browser console
  page.on("console", (msg) => {
    console.log(`[Browser Console] ${msg.type()}: ${msg.text()}`);
  });

  // 1. Authenticate with PocketBase dynamically to get a fresh JWT token
  console.log("Fetching fresh PocketBase JWT for the configured smoke user...");
  const authResponse = await fetch(`${pocketBaseUrl}/api/collections/users/auth-with-password`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ identity: email, password }),
  });

  if (!authResponse.ok) {
    throw new Error(`Failed to authenticate with PocketBase: ${await authResponse.text()}`);
  }

  const authData = (await authResponse.json()) as { token: string; record: { id: string; email: string } };
  const token = authData.token;
  const userID = authData.record.id;
  console.log(`Successfully authenticated! User ID: ${userID}, Token length: ${token.length}`);

  // 2. Set localStorage on the production domain first
  console.log("Loading production domain to set localStorage...");
  await page.goto(productionBaseUrl, { waitUntil: "domcontentloaded" });

  console.log("Injecting authenticated PocketBase session into localStorage...");
  await page.evaluate(({ email, userID, token }) => {
    localStorage.setItem("fotty.web.auth.v1", JSON.stringify({
      email: email,
      userID: userID,
      signedInAt: new Date().toISOString(),
      provider: "pocketbase",
      entitlement: "plus",
      token: token
    }));
  }, { email, userID, token });

  // 3. Navigate directly to the watch page with the active Sky Sport F1 HD stream
  const watchParams = new URLSearchParams({
    cid: activeCid,
    title: "Production playback smoke test",
    league: "P2P",
    returnTo: "/",
    matchId: activeCid,
    playback: "p2p",
    kind: "channel",
  });
  const watchUrl = `${productionBaseUrl}/watch/index?${watchParams.toString()}`;

  console.log(`Navigating to Watch URL: ${watchUrl}`);
  await page.goto(watchUrl, { waitUntil: "domcontentloaded" });

  // 4. Wait for player container and video element to mount
  console.log("Waiting for video element to mount...");
  const videoElement = page.locator("video");
  await expect(videoElement).toBeVisible({ timeout: 25000 });

  // 5. Allow some buffering and playback time, then verify active video frames
  console.log("Waiting for active video playback to start (up to 40 seconds)...");
  type PlayerState = {
    paused: boolean;
    currentTime: number;
    readyState: number;
    videoWidth: number;
    videoHeight: number;
    networkState: number;
    ended: boolean;
  };
  let playerState: PlayerState | null = null;

  for (let i = 0; i < 20; i++) {
    await page.waitForTimeout(2000);
    playerState = await videoElement.evaluate((video: HTMLVideoElement) => {
      return {
        paused: video.paused,
        currentTime: video.currentTime,
        readyState: video.readyState,
        videoWidth: video.videoWidth,
        videoHeight: video.videoHeight,
        networkState: video.networkState,
        ended: video.ended,
      };
    });

    console.log(`[Poll ${i + 1}/20] Player state: readyState=${playerState.readyState}, currentTime=${playerState.currentTime}, paused=${playerState.paused}`);

    if (playerState.readyState >= 2 && playerState.currentTime > 0 && playerState.videoWidth > 0) {
      break;
    }
  }

  console.log("Final Production Active Video Player State:", playerState);

  // Assert that the video is successfully playing
  expect(playerState).not.toBeNull();
  expect(playerState!.readyState).toBeGreaterThanOrEqual(2);
  expect(playerState!.currentTime).toBeGreaterThan(0);
  expect(playerState!.videoWidth).toBeGreaterThan(0);

  console.log(`Active playback confirmed! Time: ${playerState!.currentTime}s, Size: ${playerState!.videoWidth}x${playerState!.videoHeight}`);

  // 6. Capture screenshot of active playback
  console.log(`Taking active playback screenshot at: ${screenshotPath}`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  console.log("Active playback screenshot captured successfully!");
});
