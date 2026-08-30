#!/usr/bin/env python3
"""
Fotty Stream Health Checker
Probes live catalog mirrors (Nexus Alpha, Mirror, Beta, StreamEx, Score808)
and reports latency, status code, and match counts.
"""

import sys
import time
import json
import urllib.request
import urllib.error

FEEDS = [
    {"name": "Nexus Alpha (Primary)", "url": "https://www.streamex.net/api/live/matches/all"},
    {"name": "Nexus Mirror", "url": "https://streamex.sh/api/live/matches/all"},
    {"name": "Nexus Beta", "url": "https://streamed.pk/api/matches/all"}
]

HEADERS = {
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
    "Accept": "application/json"
}

def check_feed(feed):
    name = feed["name"]
    url = feed["url"]
    start = time.time()
    
    try:
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=8) as response:
            duration_ms = int((time.time() - start) * 1000)
            status = response.status
            data = json.loads(response.read().decode())
            matches = data if isinstance(data, list) else data.get("matches", [])
            live_count = len(matches)
            print(f"✅ {name:25} | Status: {status} | Latency: {duration_ms:4d}ms | Matches: {live_count:3d}")
            return True
    except urllib.error.HTTPError as e:
        duration_ms = int((time.time() - start) * 1000)
        print(f"⚠️  {name:25} | HTTP Error: {e.code} | Latency: {duration_ms:4d}ms")
        return False
    except Exception as e:
        duration_ms = int((time.time() - start) * 1000)
        print(f"❌ {name:25} | Failed: {str(e)[:40]} | Latency: {duration_ms:4d}ms")
        return False

def main():
    print("==================================================")
    print(" 📡 FOTTY LIVE STREAM CATALOG HEALTH PROBE")
    print("==================================================")
    
    success_count = 0
    for feed in FEEDS:
        if check_feed(feed):
            success_count += 1
            
    print("==================================================")
    print(f"Summary: {success_count}/{len(FEEDS)} feeds operational.")
    print("==================================================")
    
    return 0 if success_count > 0 else 1

if __name__ == "__main__":
    sys.exit(main())
