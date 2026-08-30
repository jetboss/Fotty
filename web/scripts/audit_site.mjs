import { chromium } from '@playwright/test';

(async () => {
    const browser = await chromium.launch({
        headless: true,
        executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    });
    const page = await browser.newPage({
        viewport: { width: 1280, height: 800 },
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15'
    });

    const results = [];

    const routes = [
        { path: '/', name: 'Home' },
        { path: '/schedule', name: 'Schedule' },
        { path: '/search', name: 'Search' },
        { path: '/tables', name: 'Tables' },
        { path: '/teams', name: 'Teams' },
        { path: '/favorites', name: 'Favorites' },
        { path: '/settings', name: 'Settings' }
    ];

    for (const route of routes) {
        const consoleErrors = [];
        page.on('console', msg => {
            if (msg.type() === 'error') consoleErrors.push(msg.text());
        });

        const url = `https://getfotty.pages.dev${route.path}`;
        const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });
        await page.waitForTimeout(2000);

        const status = response ? response.status() : 'failed';
        const title = await page.title();
        const hasBrokenImages = await page.$$eval('img', imgs => imgs.filter(i => !i.complete || i.naturalWidth === 0).length);

        results.push({
            route: route.name,
            path: route.path,
            status,
            title,
            brokenImages: hasBrokenImages,
            consoleErrors: consoleErrors.slice(0, 3)
        });
    }

    console.log("=== AUDIT RESULTS ===");
    console.log(JSON.stringify(results, null, 2));

    await browser.close();
})();
