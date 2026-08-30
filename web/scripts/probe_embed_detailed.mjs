import { chromium } from '@playwright/test';

(async () => {
    const browser = await chromium.launch({
        headless: true,
        executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    });
    const context = await browser.newContext({
        userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'
    });
    const page = await context.newPage();

    page.on('request', req => {
        const u = req.url();
        if (u.includes('m3u8') || u.includes('fetch') || u.includes('playlist') || u.includes('strmd') || u.includes('embed')) {
            console.log('[REQ]', req.method(), u, 'Headers:', JSON.stringify(req.headers()));
        }
    });

    page.on('response', async resp => {
        const u = resp.url();
        if (u.includes('m3u8') || u.includes('fetch') || u.includes('playlist') || u.includes('strmd')) {
            console.log('[RESP STATUS]', resp.status(), u);
            try {
                const text = await resp.text();
                console.log('[RESP BODY (first 200 chars)]:', text.slice(0, 200));
            } catch(e) {
                console.log('[RESP BODY ERR]:', e.message);
            }
        }
    });

    page.on('console', msg => console.log('[BROWSER CONSOLE]:', msg.type(), msg.text()));

    console.log('Navigating to stream 1...');
    await page.goto('https://embed.st/embed/admin/ppv-liverpool-vs-como/1', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(10000);

    console.log('Navigating to stream 2...');
    await page.goto('https://embed.st/embed/admin/ppv-liverpool-vs-como/2', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(10000);

    await browser.close();
})();
