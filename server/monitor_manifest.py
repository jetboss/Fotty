import os
import sys
import time

import requests

API_PASSWORD = os.getenv("P2P_API_PASSWORD", "").strip()
if not API_PASSWORD:
    raise SystemExit("Set P2P_API_PASSWORD before running monitor_manifest.py")

infohash = os.getenv(
    "P2P_MONITOR_INFOHASH",
    "19c5c13a8e7273d78d53fdaea3deaf1b80e938fa",
)
base = os.getenv("P2P_MONITOR_BASE", "https://p2p.pixel-invoice.com").rstrip("/")
url = f"{base}/proxy/acestream/manifest.m3u8?infohash={infohash}&api_password={API_PASSWORD}"

print(f"Monitoring manifest progression for: {url}")

for i in range(10):
    try:
        start = time.perf_counter()
        resp = requests.get(url, timeout=10)
        ttfb = int((time.perf_counter() - start) * 1000)

        lines = resp.text.splitlines()
        seq = next((line for line in lines if "MEDIA-SEQUENCE" in line), "Unknown")
        segments = [line for line in lines if line.endswith(".ts") or "/proxy" in line]

        print(f"[{i}] {seq} | Segments: {len(segments)} | TTFB: {ttfb}ms | Status: {resp.status_code}")
        if segments:
            print(f"    First segment: {segments[0][:120]}")
    except Exception as exc:
        print(f"[{i}] Error: {exc}", file=sys.stderr)

    time.sleep(3)
