import { chromium } from '@playwright/test';

(async () => {
    const browser = await chromium.launch({
        headless: true,
        executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    });
    const page = await browser.newPage({
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15'
    });

    console.log("Navigating to live Cloudflare Pages URL: https://getfotty.pages.dev ...");
    await page.goto('https://getfotty.pages.dev', { waitUntil: 'networkidle', timeout: 30000 });
    
    const title = await page.title();
    console.log("Page Title:", title);

    const matchCards = await page.$$eval('[data-match-id], a[href*="/watch/"]', els => els.map(e => ({ href: e.href, text: e.innerText.slice(0, 80) })));
    console.log(`Found ${matchCards.length} watch match links on homepage.`);
    console.log("Sample watch links:", matchCards.slice(0, 5));

    if (matchCards.length > 0) {
        const firstWatchUrl = matchCards[0].href;
        console.log(`\nNavigating to first watch page: ${firstWatchUrl}`);
        await page.goto(firstWatchUrl, { waitUntil: 'networkidle', timeout: 30000 });
        await page.waitForTimeout(3000);

        const iframes = await page.$$eval('iframe', els => els.map(e => ({ src: e.src, allow: e.allow, sandbox: e.sandbox.value })));
        console.log("Watch page iframes:", iframes);
    }

    await browser.close();
})();
