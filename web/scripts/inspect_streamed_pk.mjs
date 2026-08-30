import { chromium } from "@playwright/test";

async function main() {
  const browser = await chromium.launch({
    executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    headless: true
  });
  const page = await browser.newPage();

  page.on("request", req => {
    const url = req.url();
    if (url.includes("embed") || url.includes("stream") || url.includes("player") || url.includes(".m3u8")) {
      console.log(`[STREAMED.PK NET]: ${req.method()} ${url}`);
    }
  });

  console.log("Navigating to streamed.pk...");
  await page.goto("https://streamed.pk/", { waitUntil: "networkidle" });

  const matches = await page.evaluate(() => {
    const cards = Array.from(document.querySelectorAll("a, button, div.match, tr, li"));
    return cards.map(c => ({ text: c.innerText?.slice(0, 50), href: c.getAttribute("href") })).filter(c => c.text && c.text.length > 5);
  });
  console.log("Found matches on streamed.pk:", matches.slice(0, 5));

  // Find first clickable match card
  const firstMatchLink = await page.locator("a[href*='/watch/'], a[href*='/match/'], a[href*='/stream/'], div[class*='match']").first();
  if (await firstMatchLink.count() > 0) {
    console.log("Clicking first match...");
    await firstMatchLink.click();
    await page.waitForTimeout(5000);
    console.log("Current URL:", page.url());
    const iframes = await page.evaluate(() => Array.from(document.querySelectorAll("iframe")).map(f => f.src));
    console.log("Iframes after click:", iframes);
  }

  await browser.close();
}

main().catch(console.error);
