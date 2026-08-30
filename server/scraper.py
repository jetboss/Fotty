import logging
import os
import threading
import time
from datetime import datetime, timezone
from typing import Any
from urllib.parse import unquote

import requests
from flask import Flask, jsonify

try:
    from p2p_scraper_queries import build_scraper_search_queries
except ImportError:  # acestream-scraper image may only bundle scraper.py
    def build_scraper_search_queries(dynamic_queries=None, max_queries=None):
        raw = os.getenv(
            "P2P_SCRAPER_EXTRA_QUERIES",
            "nfl network,mlb network,nhl network,sky sports f1,racing tv,premier league,bt sport",
        )
        base = [q.strip() for q in raw.split(",") if q.strip()]
        dynamic = dynamic_queries or []
        seen: set[str] = set()
        out: list[str] = []
        for query in base + dynamic:
            key = query.casefold()
            if key in seen:
                continue
            seen.add(key)
            out.append(query)
        limit = max_queries if max_queries is not None else int(os.getenv("P2P_SCRAPER_MAX_TEXT_QUERIES", "80"))
        return out[:limit]

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

app = Flask(__name__)

ACE_ENGINE = os.getenv("ACE_ENGINE", "http://127.0.0.1:6878").rstrip("/")
LISTEN_PORT = int(os.getenv("PORT", "8005"))
REFRESH_SECONDS = int(os.getenv("REFRESH_SECONDS", "180"))

_lock = threading.Lock()
_matches_cache: list[dict[str, Any]] = []
_last_updated: str | None = None
_engine_version: str | None = None
_last_refresh_error: str | None = None


def _engine_get(path: str, params: dict[str, Any], timeout: float = 10.0) -> requests.Response:
    return requests.get(f"{ACE_ENGINE}{path}", params=params, timeout=timeout)


def get_engine_token() -> str:
    try:
        response = _engine_get("/webui/api/service", {"method": "get_api_access_token"}, timeout=6)
        response.raise_for_status()
        payload = response.json()
        return ((payload.get("result") or {}).get("token") or "").strip()
    except Exception as exc:
        log.warning("Failed to fetch API token: %s", exc)
        return ""


def get_engine_version() -> str | None:
    try:
        response = _engine_get("/webui/api/service", {"method": "get_version"}, timeout=6)
        response.raise_for_status()
        payload = response.json()
        version = ((payload.get("result") or {}).get("version") or "").strip()
        return version or None
    except Exception as exc:
        log.warning("Failed to fetch engine version: %s", exc)
        return None


def search_engine(query: str, token: str, page_size: int = 80) -> list[dict[str, Any]]:
    try:
        response = _engine_get(
            "/server/api",
            {
                "api_version": 3,
                "method": "search",
                "query": query,
                "token": token,
                "page_size": page_size,
            },
            timeout=15,
        )
        response.raise_for_status()
        payload = response.json()
        return ((payload.get("result") or {}).get("results") or [])
    except Exception as exc:
        log.warning("Search failed for '%s': %s", query, exc)
        return []


def search_by_category(category: str, token: str, page_size: int = 120) -> list[dict[str, Any]]:
    try:
        response = _engine_get(
            "/server/api",
            {
                "api_version": 3,
                "method": "search",
                "category": category,
                "token": token,
                "page_size": page_size,
            },
            timeout=15,
        )
        response.raise_for_status()
        payload = response.json()
        return ((payload.get("result") or {}).get("results") or [])
    except Exception as exc:
        log.warning("Category search failed for '%s': %s", category, exc)
        return []


def flatten_results(results: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: dict[str, dict[str, Any]] = {}

    for parent in results:
        stream_items = parent.get("items") or [parent]
        for item in stream_items:
            cid = (item.get("infohash") or item.get("cid") or "").strip()
            if not cid:
                continue
            if cid in seen:
                continue

            raw_availability = item.get("availability", 0)
            try:
                availability = float(raw_availability)
            except (TypeError, ValueError):
                availability = 0.0

            seen[cid] = {
                "title": (item.get("name") or parent.get("name") or "Unknown Channel").strip(),
                "cid": cid,
                "availability": availability,
                "bitrate_kbps": int((item.get("bitrate") or 0) / 1000),
                "categories": item.get("categories") or [],
                "source": "ace-engine",
            }

    channels = list(seen.values())
    channels.sort(key=lambda channel: channel.get("availability", 0.0), reverse=True)
    return channels


def refresh_loop() -> None:
    global _matches_cache, _last_updated, _engine_version, _last_refresh_error

    while True:
        token = get_engine_token()
        if not token:
            with _lock:
                _last_refresh_error = "token_unavailable"
            time.sleep(20)
            continue

        engine_version = get_engine_version()
        sport_page = int(os.getenv("P2P_SCRAPER_SPORT_PAGE_SIZE", "120"))
        extra_page = int(os.getenv("P2P_SCRAPER_EXTRA_PAGE_SIZE", "80"))
        sport_results = search_by_category("sport", token=token, page_size=sport_page)
        if not sport_results:
            sport_results = search_engine("sport", token=token, page_size=sport_page)

        merged_raw: list[dict[str, Any]] = list(sport_results) if sport_results else []
        for query in build_scraper_search_queries():
            extra = search_engine(query, token=token, page_size=extra_page)
            if extra:
                merged_raw.extend(extra)

        channels = flatten_results(merged_raw) if merged_raw else []
        now_iso = datetime.now(timezone.utc).isoformat()

        with _lock:
            _engine_version = engine_version
            if channels:
                _matches_cache = channels
                _last_updated = now_iso
                _last_refresh_error = None
            else:
                _last_refresh_error = "empty_results"

        if channels:
            log.info("Refreshed sport channels: %s", len(channels))
        else:
            log.warning("Refresh completed with no channels.")

        time.sleep(REFRESH_SECONDS)


def snapshot_matches() -> list[dict[str, Any]]:
    with _lock:
        return list(_matches_cache)


@app.get("/")
@app.get("/health")
@app.get("/pulse")
def health() -> Any:
    with _lock:
        payload = {
            "status": "ok",
            "engine": ACE_ENGINE,
            "engine_version": _engine_version,
            "count": len(_matches_cache),
            "last_updated": _last_updated,
            "last_refresh_error": _last_refresh_error,
        }
    return jsonify(payload)


@app.get("/matches")
@app.get("/status")
def matches() -> Any:
    return jsonify(snapshot_matches())


@app.get("/search/<path:query>")
def search(query: str) -> Any:
    decoded = unquote(query).strip()
    if not decoded:
        return jsonify([])

    token = get_engine_token()
    if not token:
        return jsonify([])

    results = search_engine(decoded, token=token, page_size=80)
    return jsonify(flatten_results(results))


@app.post("/log")
def app_log() -> Any:
    # Keep backward compatibility with clients that fire-and-forget log events.
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    threading.Thread(target=refresh_loop, daemon=True).start()
    app.run(host="0.0.0.0", port=LISTEN_PORT)
