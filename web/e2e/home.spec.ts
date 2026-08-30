import { expect, test } from "@playwright/test";

test("home loads with match-day content", async ({ page }) => {
  await page.goto("/", { waitUntil: "domcontentloaded" });

  await expect(page.getByRole("heading", { name: "Fotty Home" })).toBeVisible();
  await expect(page.getByRole("link", { name: /Watch live/i }).first()).toBeVisible({
    timeout: 20_000,
  });
  await expect(page.getByRole("heading", { name: "Tonight", exact: true })).toBeVisible();
  await expect(page.getByText(/\bvs\.?\b/i).first()).toBeVisible({ timeout: 15_000 });
});

test("live playable fixture replaces a finished hero and opens watch", async ({ page }) => {
  const shared = {
    kind: "fixture",
    league: "Premier League",
    sport: "Football",
    quality: "HD",
    sourceCount: 1,
  };
  await page.route(/\/api\/matches\/?(\?.*)?$/, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([
        {
          ...shared,
          id: "france-vs-morocco",
          cid: "france-vs-morocco",
          title: "France vs Morocco",
          status: "Finished",
          rank: 10_000,
        },
        {
          ...shared,
          id: "spain-vs-belgium",
          cid: "spain-vs-belgium",
          title: "Spain vs Belgium",
          status: "Live",
          startsAt: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
          eventSource: {
            source: "echo",
            id: "spain-vs-belgium-stream",
          },
          playbackType: "event",
          coverage: "direct",
          sourceIds: ["spain-vs-belgium-stream"],
        },
      ]),
    });
  });

  await page.goto("/", { waitUntil: "domcontentloaded" });

  await expect(page.getByRole("heading", { name: /Spain.*Belgium/i }).first()).toBeVisible({
    timeout: 20_000,
  });
  const watchLink = page.getByRole("link", { name: "Watch live" }).first();
  await expect(watchLink).toBeVisible();
  await expect(watchLink).toHaveAttribute("href", /playback=event/);
  await expect(watchLink).toHaveAttribute("href", /eventId=[^&]+/);
});

test("football standings api is configured", async ({ request }) => {
  const response = await request.get("/api/football/standings?league=premierLeague&scorers=1");
  expect(response.ok()).toBeTruthy();
  const data = await response.json();
  expect(data.configured).toBeTruthy();
  expect((data.standings?.length ?? 0) > 0).toBeTruthy();
});

test("tables page loads", async ({ page }) => {
  await page.goto("/tables", { waitUntil: "domcontentloaded" });
  await expect(page.getByRole("heading", { name: "League tables" })).toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole("tab", { name: "Premier League" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Premier League table" })).toBeVisible();
});

test("welcome page links into the app", async ({ page }) => {
  await page.goto("/welcome", { waitUntil: "domcontentloaded" });
  await expect(page.getByRole("heading", { name: /Match day in your browser/i })).toBeVisible();
  await expect(page.getByRole("link", { name: "Enter Fotty Home" })).toBeVisible();
});
