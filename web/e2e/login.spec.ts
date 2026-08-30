import { expect, test } from "@playwright/test";

test("login page shows account form", async ({ page }) => {
  await page.goto("/login", { waitUntil: "domcontentloaded" });
  await expect(page.getByRole("heading", { name: /Sign in to Fotty/i })).toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByRole("textbox", { name: /Email/i }).first()).toBeVisible();
  await expect(page.getByRole("button", { name: /Sign in/i }).first()).toBeVisible();
});
