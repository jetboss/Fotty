import json
import tempfile
import unittest
from pathlib import Path

from p2p_pinned_channels import load_pinned_channels, merge_pinned_channels


class P2PPinnedChannelsTests(unittest.TestCase):
    def test_skips_empty_cid(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "pins.json"
            path.write_text(
                json.dumps(
                    {
                        "channels": [
                            {"title": "NFL Network", "cid": ""},
                            {
                                "title": "MLB Network HD [US]",
                                "cid": "a" * 40,
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            import os

            previous = os.environ.get("P2P_PINNED_CHANNELS_FILE")
            os.environ["P2P_PINNED_CHANNELS_FILE"] = str(path)
            try:
                loaded = load_pinned_channels()
                self.assertEqual(len(loaded), 1)
                merged = merge_pinned_channels([{"title": "ESPN", "cid": "b" * 40, "availability": 1}])
                self.assertEqual(len(merged), 2)
            finally:
                if previous is None:
                    os.environ.pop("P2P_PINNED_CHANNELS_FILE", None)
                else:
                    os.environ["P2P_PINNED_CHANNELS_FILE"] = previous


if __name__ == "__main__":
    unittest.main()
