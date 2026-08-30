#!/usr/bin/env python3
"""Capture comparable free-vs-Proxy-Server broker reliability windows."""

import argparse
import json
import os
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


COUNTERS = (
    "manifest_requests",
    "manifest_failures",
    "segment_requests",
    "segment_successes",
    "segment_failures",
)


def fetch_metrics(base_url: str, api_password: str) -> Dict[str, Any]:
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/metrics",
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {api_password}",
        },
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)


def delta(after: Dict[str, Any], before: Dict[str, Any], key: str) -> int:
    return max(int(after.get(key) or 0) - int(before.get(key) or 0), 0)


def summarize(label: str, seconds: int, before: Dict[str, Any], after: Dict[str, Any]) -> Dict[str, Any]:
    values = {key: delta(after, before, key) for key in COUNTERS}
    manifest_ok = max(values["manifest_requests"] - values["manifest_failures"], 0)
    values["manifest_success_rate"] = (
        round(manifest_ok / values["manifest_requests"], 4) if values["manifest_requests"] else None
    )
    values["segment_2xx_rate"] = (
        round(values["segment_successes"] / values["segment_requests"], 4)
        if values["segment_requests"]
        else None
    )
    values.update(
        {
            "label": label,
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "window_seconds": seconds,
            "manifest_ttfb_ms_p50": after.get("manifest_ttfb_ms_p50"),
            "manifest_ttfb_ms_p95": after.get("manifest_ttfb_ms_p95"),
            "engine": after.get("engine") or {},
        }
    )
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", required=True, choices=("free", "proxy-server"))
    parser.add_argument("--base-url", default="http://127.0.0.1:8006")
    parser.add_argument("--window-seconds", type=int, default=300)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    api_password = os.getenv("P2P_API_PASSWORD", "").strip()
    if not api_password:
        parser.error("P2P_API_PASSWORD is required in the environment")

    before = fetch_metrics(args.base_url, api_password)
    if args.window_seconds > 0:
        time.sleep(args.window_seconds)
    after = fetch_metrics(args.base_url, api_password)
    summary = summarize(args.label, args.window_seconds, before, after)
    encoded = json.dumps(summary, sort_keys=True)
    print(json.dumps(summary, indent=2, sort_keys=True))
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("a", encoding="utf-8") as handle:
            handle.write(encoded + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
