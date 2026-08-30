import { expect, test } from "@playwright/test";

test("home loads", async ({ page }) => {
  await page.goto("/", { waitUntil: "domcontentloaded" });
  await expect(page.locator('[data-shell="v2"]').first()).toBeVisible({ timeout: 20_000 });
});

test("watch page shows sign-in gate when logged out", async ({ page }) => {
  await page.goto("/watch/index?id=test-cid&title=Test%20Match&returnTo=/", {
    waitUntil: "domcontentloaded",
  });
  await expect(page.getByText("Sign in to watch", { exact: true })).toBeVisible({ timeout: 15_000 });
});
