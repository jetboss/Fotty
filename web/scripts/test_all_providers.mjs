import https from 'https';
import { chromium } from '@playwright/test';

function fetchJSON(url) {
    return new Promise((resolve, reject) => {
        https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, res => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try { resolve(JSON.parse(data)); } catch(e) { resolve(data); }
            });
        }).on('error', reject);
    });
}

(async () => {
    console.log("Fetching live matches from streamed.pk to test all provider types...");
    const matches = await fetchJSON('https://streamed.pk/api/matches/live');
    if (!Array.isArray(matches)) {
        console.log("Failed to fetch matches:", matches);
        return;
    }

    const browser = await chromium.launch({
        headless: true,
        executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    });

    const context = await browser.newContext({
        userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'
    });

    // Test distinct sources: hotel, echo, delta, golf, admin
    const foundSources = {};
    for (const match of matches) {
        for (const src of match.sources || []) {
            if (!foundSources[src.source]) {
                foundSources[src.source] = { matchTitle: match.title, source: src.source, id: src.id };
            }
        }
    }

    console.log("Distinct sources to test:", Object.keys(foundSources));

    for (const [sourceCode, info] of Object.entries(foundSources)) {
        console.log(`\n========================================`);
        console.log(`TESTING SOURCE: [${sourceCode}] for match: ${info.matchTitle} (id: ${info.id})`);
        
        for (const streamNo of [1, 2]) {
            const embedUrl = `https://embed.st/embed/${sourceCode}/${info.id}/${streamNo}`;
            console.log(`  Checking embed URL: ${embedUrl}`);

            const page = await context.newPage();
            let m3u8Status = null;
            let m3u8Url = null;
            let jwError = null;

            page.on('response', resp => {
                if (resp.url().includes('m3u8') || resp.url().includes('playlist')) {
                    m3u8Status = resp.status();
                    m3u8Url = resp.url();
                }
            });

            page.on('console', msg => {
                const text = msg.text();
                if (text.includes('Error') || text.includes('error') || text.includes('hls')) {
                    jwError = text;
                }
            });

            try {
                await page.goto(embedUrl, { waitUntil: 'domcontentloaded', timeout: 12000 });
                await page.waitForTimeout(4000);

                const pageErrorText = await page.evaluate(() => {
                    const el = document.querySelector('.jw-error-msg, .jw-error');
                    return el ? el.innerText : null;
                });

                const videoCount = await page.$$eval('video', vs => vs.length);

                console.log(`    Result: Video elements: ${videoCount} | m3u8 status: ${m3u8Status} | DOM Error: ${pageErrorText || 'None'}`);
                if (m3u8Url) console.log(`    m3u8 URL: ${m3u8Url}`);
                if (jwError) console.log(`    Console Error: ${jwError}`);
            } catch(e) {
                console.log(`    Navigation Error: ${e.message}`);
            } finally {
                await page.close();
            }
        }
    }

    await browser.close();
})();
