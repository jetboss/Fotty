import { expect, test } from "@playwright/test";
import { createCipheriv, createHash, createHmac } from "node:crypto";

interface LiveStreamexEvent {
  id: string;
  source: string;
  title: string;
}

const enabled = process.env.FOTTY_RUN_LIVE_STREAMEX_E2E === "1";
const watchStreamSecret = process.env.FOTTY_WATCH_STREAM_SECRET?.trim();
const soakSeconds = Number(process.env.FOTTY_STREAMEX_SOAK_SECONDS || "300");
const configuredEvents = (() => {
  try {
    const value = JSON.parse(process.env.FOTTY_STREAMEX_E2E_EVENTS || "[]");
    return Array.isArray(value) ? (value as LiveStreamexEvent[]) : [];
  } catch {
    return [];
  }
})();

function issueWatchToken() {
  if (!watchStreamSecret) return null;
  const payload = JSON.stringify({
    subject: createHmac("sha256", watchStreamSecret).update("e2e-streamex").digest("base64url"),
    entitlement: "plus",
    nonce: `streamex-${Date.now()}`,
    exp: Date.now() + (soakSeconds + 10 * 60) * 1000,
  });
  const iv = createHash("sha256").update(payload).digest().subarray(0, 12);
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

test.describe("live StreameX HD continuity", () => {
  test.skip(!enabled, "Set FOTTY_RUN_LIVE_STREAMEX_E2E=1 for real provider testing.");
  test.skip(!watchStreamSecret, "Set FOTTY_WATCH_STREAM_SECRET to match the test web server.");
  test.skip(configuredEvents.length === 0, "Set FOTTY_STREAMEX_E2E_EVENTS to active event sources.");

  for (const event of configuredEvents) {
    test(`${event.title} produces continuous decoded playback signals`, async ({ page }) => {
      test.setTimeout((soakSeconds + 90) * 1000);
      const watchToken = issueWatchToken() as string;

      await page.addInitScript(() => {
        const bridge = {
          started: 0,
          pulses: 0,
          stalled: 0,
          errors: 0,
          lastSignalAt: 0,
        };
        Object.assign(window, { __fottyStreamexBridge: bridge });
        window.addEventListener("message", (message) => {
          const type = message.data?.type;
          if (type === "fotty:playback-started") bridge.started += 1;
          if (type === "fotty:playback-pulse") bridge.pulses += 1;
          if (type === "fotty:playback-stalled") bridge.stalled += 1;
          if (type === "fotty:playback-error") bridge.errors += 1;
          if (typeof type === "string" && type.startsWith("fotty:playback-")) {
            bridge.lastSignalAt = Date.now();
          }
        });
      });

      await page.route(/\/api\/stream\/token/, (route) =>
        route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({ watchToken, expiresIn: soakSeconds + 10 * 60 }),
        })
      );
      await page.route(/\/api\/pocketbase\/entitlement/, (route) =>
        route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({ entitlement: "plus", entitlementExpiresAt: null }),
        })
      );

      await page.goto("/", { waitUntil: "domcontentloaded" });
      await page.evaluate((token) => {
        localStorage.setItem(
          "fotty.web.auth.v1",
          JSON.stringify({
            email: "streamex-e2e@fotty.app",
            signedInAt: new Date().toISOString(),
            provider: "local",
            entitlement: "plus",
            token,
          })
        );
      }, watchToken);

      const params = new URLSearchParams({
        id: event.id,
        eventId: event.id,
        title: event.title,
        playback: "event",
        source: event.source,
      });
      await page.goto(`/watch/index?${params.toString()}`, { waitUntil: "domcontentloaded" });
      const iframe = page.locator(`iframe[title*="${event.title.replaceAll('"', '\\"')}"]`);
      await expect(iframe).toBeVisible({ timeout: 30_000 });
      await expect
        .poll(
          () =>
            page.evaluate(
              () =>
                (
                  window as typeof window & {
                    __fottyStreamexBridge?: { started: number };
                  }
                ).__fottyStreamexBridge?.started || 0
            ),
          { timeout: 45_000 }
        )
        .toBeGreaterThan(0);

      const initialPulses = await page.evaluate(
        () =>
          (
            window as typeof window & {
              __fottyStreamexBridge?: { pulses: number };
            }
          ).__fottyStreamexBridge?.pulses || 0
      );
      await page.waitForTimeout(soakSeconds * 1000);

      const result = await page.evaluate(() => {
        const bridge = (
          window as typeof window & {
            __fottyStreamexBridge?: {
              started: number;
              pulses: number;
              stalled: number;
              errors: number;
              lastSignalAt: number;
            };
          }
        ).__fottyStreamexBridge;
        return {
          bridge,
          iframeSrc: document.querySelector("iframe")?.getAttribute("src") || "",
          bodyText: document.body.innerText,
        };
      });

      expect(result.bridge?.pulses || 0).toBeGreaterThan(initialPulses);
      expect(result.bridge?.stalled || 0).toBe(0);
      expect(result.bridge?.errors || 0).toBe(0);
      expect(Date.now() - (result.bridge?.lastSignalAt || 0)).toBeLessThan(15_000);
      expect(result.iframeSrc).toContain("/api/embed/player");
      expect(result.bodyText).not.toMatch(/All direct feeds were tried|No playable stream/i);
    });
  }
});
