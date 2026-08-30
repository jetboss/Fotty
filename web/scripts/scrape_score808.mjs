import { chromium } from "@playwright/test";

async function main() {
  const browser = await chromium.launch({
    executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    headless: true
  });
  const page = await browser.newPage();

  page.on("request", req => {
    const url = req.url();
    if (url.includes("api") || url.includes("match") || url.includes("live") || url.includes("embed")) {
      console.log(`[SCORE808 API]: ${req.method()} ${url}`);
    }
  });

  console.log("Navigating to https://www.score808live.tv/...");
  await page.goto("https://www.score808live.tv/", { waitUntil: "networkidle", timeout: 20000 });

  const pageTitle = await page.title();
  console.log("Page title:", pageTitle);

  const matchLinks = await page.evaluate(() => {
    return Array.from(document.querySelectorAll("a, div"))
      .map(el => ({
        text: el.innerText?.trim()?.slice(0, 80),
        href: el.getAttribute("href")
      }))
      .filter(m => m.href && (m.href.includes("/live/") || m.href.includes("/football/") || m.href.includes("/match/")));
  });

  console.log("Found matches on Score808 website:", matchLinks.slice(0, 10));

  await browser.close();
}

main().catch(console.error);
