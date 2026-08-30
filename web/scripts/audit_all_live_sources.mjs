import https from 'https';

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
    console.log("=== FETCHING ALL CURRENT LIVE MATCHES ===");
    const matches = await fetchJSON('https://streamed.pk/api/matches/live');
    if (!Array.isArray(matches)) {
        console.log("Matches response is not array:", matches);
        return;
    }

    console.log(`Found ${matches.length} live matches.\n`);

    for (const match of matches.slice(0, 10)) {
        console.log(`Match: ${match.title} (${match.category})`);
        console.log(`Sources:`, match.sources);

        for (const src of match.sources || []) {
            const streamApiUrl = `https://streamed.pk/api/stream/${src.source}/${src.id}`;
            const streamData = await fetchJSON(streamApiUrl);
            console.log(`  Source: ${src.source} (id: ${src.id}) -> API response:`, Array.isArray(streamData) ? `Array length ${streamData.length}` : streamData);
            if (Array.isArray(streamData) && streamData.length > 0) {
                console.log(`    Sample stream:`, streamData[0]);
            }
        }
        console.log('----------------------------------------------------');
    }
})();
