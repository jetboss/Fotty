import { chromium } from '@playwright/test';

(async () => {
    const browser = await chromium.launch({
        headless: true,
        executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    });
    const page = await browser.newPage();
    
    page.on('request', req => {
        const u = req.url();
        if (u.includes('m3u8') || u.includes('embed') || u.includes('stream') || u.includes('player') || u.includes('live')) {
            console.log('[MEDIA/EMBED REQ]:', u);
        }
    });

    const targetUrl = 'https://www.score808live.tv/score808-live-football-scores-real-time-match-updates-results/';
    console.log('Navigating to user URL:', targetUrl);
    await page.goto(targetUrl, { waitUntil: 'networkidle', timeout: 30000 });
    
    const iframes = await page.$$eval('iframe', els => els.map(e => ({ src: e.src, id: e.id, class: e.className })));
    console.log('Iframes on page:', iframes);

    const videos = await page.$$eval('video', els => els.map(e => ({ src: e.src, currentSrc: e.currentSrc })));
    console.log('Videos on page:', videos);

    const pageText = await page.evaluate(() => document.body.innerText);
    console.log('Page Title:', await page.title());
    console.log('Snippet of Page Text:', pageText.slice(0, 500));

    await browser.close();
})();
