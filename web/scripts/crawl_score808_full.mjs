import { chromium } from '@playwright/test';

(async () => {
    const browser = await chromium.launch({
        headless: true,
        executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    });
    const page = await browser.newPage();
    
    const mediaUrls = [];
    const iframeUrls = [];

    page.on('request', req => {
        const u = req.url();
        if (u.includes('m3u8') || u.includes('embed') || u.includes('stream') || u.includes('player') || u.includes('strmd')) {
            mediaUrls.push({ url: u, type: req.resourceType(), method: req.method() });
        }
    });

    console.log('Navigating to https://www.score808live.tv ...');
    await page.goto('https://www.score808live.tv', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(5000);

    const iframes = await page.$$eval('iframe', els => els.map(e => e.src));
    console.log('All iframes found on homepage:', iframes);

    const allLinks = await page.$$eval('a', els => els.map(e => ({ href: e.href, text: e.innerText.trim() })).filter(l => l.href && l.href.length > 0));
    console.log('Sample links on homepage:', allLinks.slice(0, 25));

    console.log('Media URLs intercepted on homepage:', mediaUrls);

    await browser.close();
})();
