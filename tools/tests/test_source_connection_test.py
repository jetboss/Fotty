import importlib.util
from pathlib import Path
import tempfile
import unittest
import json

MODULE = Path(__file__).resolve().parents[1] / "source-connection-test.py"
SPEC = importlib.util.spec_from_file_location("connection_tool", MODULE)
tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tool)


class ConnectionToolTests(unittest.TestCase):
    def test_crash_interruption_and_incomplete_runs_never_become_collection_passes(self):
        original = {"completion": "running", "rows": [{"deliveries": [{"result": "decoding"}]}]}
        for code, state in [(65, "test_failed"), (75, "interrupted"), (130, "interrupted"), (0, "incomplete")]:
            result = tool.execution_receipt(original, code)
            self.assertEqual(result["executionState"], state)
            self.assertEqual(result["completion"], "running")
            self.assertEqual(result["rows"][0]["deliveries"][0]["result"], "decoding")
        self.assertNotIn("executionState", original)
        completed = tool.execution_receipt({"completion": "physical_collection_complete_review_each_delivery", "rows": []}, 0)
        self.assertEqual(completed["executionState"], "collection_complete")

    def test_selects_only_connection_case_and_preserves_actual_source_preferences(self):
        document = {"TestConfigurations": [{"TestTargets": [
            {"TestBundlePath": "__TESTROOT__/FottyTests.xctest", "EnvironmentVariables": {"KEEP": "value"}},
            {"TestBundlePath": "__TESTROOT__/FottyUITests.xctest"},
        ]}]}
        result = tool.prepare_run(document, "sports-fixture:premier-league:example", True, "AS1")
        unit, ui = result["TestConfigurations"][0]["TestTargets"]
        self.assertTrue(unit["IsEnabled"])
        self.assertFalse(ui["IsEnabled"])
        self.assertEqual(unit["OnlyTestIdentifiers"], [tool.METHOD])
        self.assertEqual(unit["EnvironmentVariables"]["KEEP"], "value")
        self.assertEqual(unit["EnvironmentVariables"]["FOTTY_AUTOMATED_TESTING"], "1")
        self.assertNotIn("FOTTY_PHYSICAL_LIVE_TEST", unit["EnvironmentVariables"])
        self.assertFalse(any("enable" in key.lower() for key in unit["EnvironmentVariables"]))

    def test_missing_or_duplicated_actual_unit_target_is_rejected(self):
        for document in [{}, {"a": {"TestBundlePath": "FottyTests.xctest"},
                              "b": {"TestBundlePath": "FottyTests.xctest"}}]:
            with self.assertRaises(ValueError):
                tool.prepare_run(document, "fixture", False, "")

    def test_transport_data_cannot_escape_in_retained_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = {"schemaVersion": 1, "kickoffUTC": "2026-10-31T20:00:00Z", "rows": []}
            (root / "safe.txt").write_text(json.dumps(base))
            self.assertEqual(tool.reports(root), [base])
            (root / "unsafe.txt").write_text(json.dumps(base | {"unexpected": "https://media.example/private"}))
            with self.assertRaises(ValueError):
                tool.reports(root)


if __name__ == "__main__":
    unittest.main()
