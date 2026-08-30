import { chromium } from '@playwright/test';

(async () => {
    const browser = await chromium.launch({
        headless: true,
        executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    });
    
    // Simulate real Mobile Safari on iOS 18
    const context = await browser.newContext({
        userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
        viewport: { width: 390, height: 844 },
        deviceScaleFactor: 3,
        isMobile: true,
        hasTouch: true
    });
    
    const page = await context.newPage();

    let m3u8Url = null;
    let fetchResp = null;

    page.on('request', req => {
        const u = req.url();
        console.log('[REQ]', req.method(), u);
        if (u.includes('fetch')) {
            console.log('[FETCH HEADERS]:', JSON.stringify(req.headers()));
        }
    });

    page.on('response', async resp => {
        const u = resp.url();
        if (u.includes('fetch')) {
            try {
                fetchResp = await resp.json();
                console.log('[FETCH RESPONSE JSON]:', JSON.stringify(fetchResp));
            } catch(e) {}
        }
        if (u.includes('playlist.m3u8')) {
            m3u8Url = u;
            console.log('[M3U8 RESPONSE STATUS]:', resp.status(), u);
            console.log('[M3U8 HEADERS]:', JSON.stringify(resp.headers()));
            try {
                const body = await resp.text();
                console.log('[M3U8 BODY]:\n', body);
            } catch(e) {
                console.log('[M3U8 BODY ERR]:', e.message);
            }
        }
    });

    console.log('=== TEST 1: Loading embed.st/embed/admin/ppv-liverpool-vs-como/1 ===');
    await page.goto('https://embed.st/embed/admin/ppv-liverpool-vs-como/1', { waitUntil: 'networkidle' });
    await page.waitForTimeout(4000);

    console.log('=== TEST 2: Loading embed.st/embed/admin/ppv-liverpool-vs-como/2 ===');
    await page.goto('https://embed.st/embed/admin/ppv-liverpool-vs-como/2', { waitUntil: 'networkidle' });
    await page.waitForTimeout(4000);

    await browser.close();
})();
