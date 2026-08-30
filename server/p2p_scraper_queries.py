"""AceStream text-search queries for Fotty P2P channel discovery (US/UK sports nets)."""

from __future__ import annotations

import os

# Priority: US league nets + UK depth channels missing from sport-category crawl alone.
US_UK_NETWORK_QUERIES = [
    "nfl",
    "nfl network",
    "nfl redzone",
    "mlb",
    "mlb network",
    "nhl",
    "nhl network",
    "cbs sports network",
    "cbsn",
    "cbssn",
    "fs1",
    "nba tv",
    "tennis channel",
    "golf channel",
    "usa network",
    "nbc sports",
    "nbc sports network",
    "peacock sports",
    "sec network",
    "acc network",
    "big ten network",
    "btn",
    "fox sports 1",
    "fox sports 2",
    "espnu",
    "espn u",
    "espnews",
    "espn usa",
    "espn deportes",
    "sky sports f1",
    "sky sports golf",
    "sky sports main event",
    "sky sports premier league",
    "sky sports football",
    "sky sports cricket",
    "sky sports arena",
    "sky sports action",
    "sky sports mix",
    "sky sports news",
    "racing tv",
    "premier sports 1",
    "premier sports 2",
    "tnt sports 1",
    "tnt sports 2",
    "tnt sports 3",
    "bt sport",
]

CORE_SPORT_QUERIES = [
    "premier league",
    "epl",
    "english premier league",
    "champions league",
    "uefa champions league",
    "ucl",
    "tnt sports",
    "nba",
    "basketball",
    "tnt nba",
    "espn nba",
]


def _parse_env_queries(name: str, fallback: list[str]) -> list[str]:
    raw = os.getenv(name, "").strip()
    if not raw:
        return list(fallback)
    return [q.strip() for q in raw.split(",") if q.strip()]


def us_uk_network_queries() -> list[str]:
    return _parse_env_queries("P2P_SCRAPER_US_UK_QUERIES", US_UK_NETWORK_QUERIES)


def extra_sport_queries() -> list[str]:
    return _parse_env_queries("P2P_SCRAPER_EXTRA_QUERIES", CORE_SPORT_QUERIES)


def dedupe_queries(queries: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for query in queries:
        key = query.casefold()
        if key in seen:
            continue
        seen.add(key)
        out.append(query)
    return out


def build_scraper_search_queries(
    dynamic_queries: list[str] | None = None,
    max_queries: int | None = None,
) -> list[str]:
    """US/UK network queries first, then core sport terms, then match-derived titles."""
    limit = max_queries if max_queries is not None else int(os.getenv("P2P_SCRAPER_MAX_TEXT_QUERIES", "120"))
    dynamic = dynamic_queries or []
    merged = dedupe_queries(us_uk_network_queries() + extra_sport_queries() + dynamic)
    return merged[:limit]
