import os

os.environ.setdefault("P2P_API_PASSWORD", "test-p2p-password")

import unittest

from p2p_scraper_queries import (
    US_UK_NETWORK_QUERIES,
    build_scraper_search_queries,
    dedupe_queries,
)


class P2PScraperQueriesTests(unittest.TestCase):
    def test_us_uk_queries_prioritized(self):
        queries = build_scraper_search_queries(["Arsenal Chelsea"], max_queries=50)
        self.assertIn("nfl network", queries)
        self.assertIn("sky sports f1", queries)
        self.assertLess(queries.index("nfl network"), queries.index("premier league"))

    def test_dedupe_preserves_order(self):
        self.assertEqual(
            dedupe_queries(["nba", "NBA", "nba tv", "nba"]),
            ["nba", "nba tv"],
        )

    def test_env_override_extra_queries(self):
        previous = os.environ.get("P2P_SCRAPER_EXTRA_QUERIES")
        os.environ["P2P_SCRAPER_EXTRA_QUERIES"] = "custom league"
        try:
            queries = build_scraper_search_queries(max_queries=80)
            self.assertIn("custom league", queries)
        finally:
            if previous is None:
                os.environ.pop("P2P_SCRAPER_EXTRA_QUERIES", None)
            else:
                os.environ["P2P_SCRAPER_EXTRA_QUERIES"] = previous

    def test_us_uk_list_covers_phase_b_targets(self):
        joined = " ".join(US_UK_NETWORK_QUERIES).lower()
        for needle in ("nfl network", "mlb network", "nhl network", "cbs sports", "racing tv", "sky sports f1"):
            self.assertIn(needle, joined)


if __name__ == "__main__":
    unittest.main()
