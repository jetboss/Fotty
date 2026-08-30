import { chromium } from '@playwright/test';

(async () => {
    const browser = await chromium.launch({
        headless: true,
        executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    });

    console.log("=== COMPARISON TEST 1: DESKTOP MACBOOK SAFARI / CHROME ===");
    const desktopContext = await browser.newContext({
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
        viewport: { width: 1440, height: 900 }
    });
    const desktopPage = await desktopContext.newPage();
    
    desktopPage.on('response', resp => {
        if (resp.url().includes('m3u8') || resp.url().includes('fetch')) {
            console.log('[DESKTOP RESP]', resp.status(), resp.url());
        }
    });

    const testUrls = [
        'https://embed.st/embed/admin/ppv-liverpool-vs-como/1',
        'https://embed.st/embed/delta/live_mlb_mets-nationals-live-streaming-593466048/1',
        'https://embed.st/embed/echo/new-york-mets-vs-washington-nationals-baseball-179876/1'
    ];

    for (const u of testUrls) {
        console.log(`\nTesting Desktop UA on: ${u}`);
        try {
            await desktopPage.goto(u, { waitUntil: 'domcontentloaded', timeout: 10000 });
            await desktopPage.waitForTimeout(4000);
            const err = await desktopPage.evaluate(() => {
                const el = document.querySelector('.jw-error-msg, .jw-error');
                return el ? el.innerText : null;
            });
            console.log(`  Desktop error: ${err || 'NONE (PLAYING!)'}`);
        } catch(e) {
            console.log(`  Desktop navigation err: ${e.message}`);
        }
    }

    console.log("\n=== COMPARISON TEST 2: MOBILE IPHONE UA ===");
    const mobileContext = await browser.newContext({
        userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
        viewport: { width: 390, height: 844 },
        isMobile: true
    });
    const mobilePage = await mobileContext.newPage();
    
    mobilePage.on('response', resp => {
        if (resp.url().includes('m3u8') || resp.url().includes('fetch')) {
            console.log('[MOBILE RESP]', resp.status(), resp.url());
        }
    });

    for (const u of testUrls) {
        console.log(`\nTesting Mobile UA on: ${u}`);
        try {
            await mobilePage.goto(u, { waitUntil: 'domcontentloaded', timeout: 10000 });
            await mobilePage.waitForTimeout(4000);
            const err = await mobilePage.evaluate(() => {
                const el = document.querySelector('.jw-error-msg, .jw-error');
                return el ? el.innerText : null;
            });
            console.log(`  Mobile error: ${err || 'NONE (PLAYING!)'}`);
        } catch(e) {
            console.log(`  Mobile navigation err: ${e.message}`);
        }
    }

    await browser.close();
})();
