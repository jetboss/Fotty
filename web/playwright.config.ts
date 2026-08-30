import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.FOTTY_WEB_BASE_URL || "http://localhost:3000";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  reporter: "list",
  use: {
    baseURL,
    serviceWorkers: "block",
    trace: "on-first-retry",
  },
  webServer:
    process.env.CI || process.env.FOTTY_WEB_BASE_URL
      ? undefined
      : {
          command: "NEXT_PUBLIC_FOTTY_ALLOW_LOCAL_AUTH=true npm run dev",
          url: baseURL,
          reuseExistingServer: true,
          timeout: 120_000,
        },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] } },
  ],
});
