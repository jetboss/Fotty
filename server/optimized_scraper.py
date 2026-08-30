import requests
import json
import time
import logging
import os
from bs4 import BeautifulSoup
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Configuration
CACHE_FILE = "matches.json"
INTERVAL = 120

# Providers from AnalyticalDataEngine.swift
PROVIDERS = [
    {"label": "Nexus Alpha", "url": "https://www.streamex.net/api/live/matches/all"},
    {"label": "Nexus Alpha Mirror", "url": "https://streamex.sh/api/live/matches/all"},
    {"label": "Nexus Beta", "url": "https://streamed.pk/api/matches/all"},
    {"label": "VipLeague", "url": "https://www.vipleague.im/"},
    {"label": "MethStreams", "url": "https://methstreams.com/"},
    {"label": "Direct Scrape", "url": "https://embedsports.top/"}
]

def scrape_nextjs_data(url):
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Referer": url,
            "Upgrade-Insecure-Requests": "1"
        }
        response = requests.get(url, headers=headers, timeout=15)
        response.raise_for_status()

        if "/api/" in url:
            # It's an API provider
            data = response.json()
            # If it's a list, return it. If it's a dict with 'matches', return that.
            if isinstance(data, list): return data
            return data.get('matches', []) or data.get('events', []) or []
        else:
            # It's a website to scrape Next.js data
            soup = BeautifulSoup(response.text, 'html.parser')
            script_tag = soup.find('script', id='__NEXT_DATA__')
            if not script_tag: return []
            
            data = json.loads(script_tag.string)
            props = data.get('props', {})
            page_props = props.get('pageProps', {})
            matches = page_props.get('matches', []) or \
                      page_props.get('events', []) or \
                      page_props.get('games', []) or \
                      page_props.get('scheduledEvents', []) or \
                      page_props.get('fixtures', [])
            if not matches: matches = find_matches_in_dict(page_props)
            return matches

    except Exception as e:
        logger.error(f"Failed to fetch from {url}: {e}")
        return []

def find_matches_in_dict(d):
    if isinstance(d, list):
        if len(d) > 0 and isinstance(d[0], dict) and ('id' in d[0] or 'title' in d[0] or 'home' in d[0]):
            return d
        for item in d:
            result = find_matches_in_dict(item)
            if result: return result
    elif isinstance(d, dict):
        for k, v in d.items():
            if k.lower() in ['matches', 'events', 'data', 'games', 'scheduledevents', 'fixtures', 'live']:
                if isinstance(v, list): return v
            result = find_matches_in_dict(v)
            if result: return result
    return []

def deduplicate_matches(all_matches):
    merged = {}
    for match in all_matches:
        match_id = str(match.get('id', ''))
        if not match_id: continue
        
        if match_id not in merged:
            merged[match_id] = match
        else:
            # Merge sources from different providers for the same match
            existing_sources = merged[match_id].get('sources', [])
            new_sources = match.get('sources', [])
            
            # Keep track of unique source IDs within this match
            seen_source_ids = {str(s.get('id', '')) for s in existing_sources if s.get('id')}
            
            for s in new_sources:
                sid = str(s.get('id', ''))
                if sid and sid not in seen_source_ids:
                    existing_sources.append(s)
                    seen_source_ids.add(sid)
            
            merged[match_id]['sources'] = existing_sources
    
    return list(merged.values())

def main():
    while True:
        all_matches = []
        for provider in PROVIDERS:
            logger.info(f"Fetching from {provider['label']}...")
            matches = scrape_nextjs_data(provider['url'])
            if matches:
                # Tag each source with the provider label so the app can identify them
                for m in matches:
                    if isinstance(m.get('sources'), list):
                        for s in m['sources']:
                            if isinstance(s, dict) and 'provider' not in s:
                                s['provider'] = provider['label']
                
                logger.info(f"Found {len(matches)} matches from {provider['label']}")
                all_matches.extend(matches)
        
        unique_matches = deduplicate_matches(all_matches)
        logger.info(f"Total unique matches: {len(unique_matches)}")
        
        if unique_matches:
            data = {
                "last_updated": datetime.utcnow().isoformat(),
                "matches": unique_matches
            }
            with open(CACHE_FILE, "w") as f:
                json.dump(data, f, indent=2)
            logger.info(f"Cache updated and saved to {CACHE_FILE}")
        
        logger.info(f"Sleeping for {INTERVAL} seconds...")
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
