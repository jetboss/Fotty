"""Recovery fixtures only; no real repository, secret or remote is modified."""
from pathlib import Path
import hashlib
import json
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release_source_snapshot as snapshot


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="FottyRecoveryTest-")
        self.addCleanup(self.temp.cleanup)
        self.parent = Path(self.temp.name)
        self.root = self.parent / "source"
        self.root.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "commit.gpgSign", "false")
        (self.root / "app.swift").write_text("old source")
        (self.root / "deleted.swift").write_text("old source")
        (self.root / ".gitignore").write_text(".env*\nbackups/\n*.log\n")
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture ancestor")
        (self.root / "app.swift").write_text("current source")
        (self.root / "deleted.swift").unlink()
        (self.root / "new file.swift").write_text("new source")
        (self.root / "tool.sh").write_text("#!/bin/sh\nexit 0\n")
        (self.root / "tool.sh").chmod(0o755)
        (self.root / ".env.ios.local").write_text("ignored private input")
        (self.root / "build.log").write_text("ignored output")
        self.output = self.parent / "recovery"
        self.scan = patch.object(snapshot, "secret_scan")
        self.scan.start()
        self.addCleanup(self.scan.stop)

    def git(self, *args):
        return snapshot.run(["git", *args], self.root)

    def capture(self):
        return snapshot.capture(self.root, self.output, "2.0.0-93", "post-release-recovery")

    def test_roundtrip_preserves_working_tree_not_old_history_or_ignored_files(self):
        status = self.git("status", "--porcelain")
        head, index = self.git("rev-parse", "HEAD"), (self.root / ".git/index").read_bytes()
        receipt = self.capture()
        paths = [f["path"] for f in receipt["files"]]
        self.assertIn("new file.swift", paths)
        self.assertNotIn("deleted.swift", paths)
        self.assertNotIn(".env.ios.local", paths)
        self.assertNotIn("build.log", paths)
        self.assertEqual(next(f["mode"] for f in receipt["files"] if f["path"] == "tool.sh"), "100755")
        self.assertEqual(snapshot.verify(self.output), receipt)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertEqual((self.root / ".git/index").read_bytes(), index)
        self.assertEqual(self.git("status", "--porcelain"), status)

    def test_never_overwrites_prior_snapshot(self):
        self.capture()
        original = (self.output / "source.bundle").read_bytes()
        with self.assertRaises(ValueError):
            self.capture()
        self.assertEqual((self.output / "source.bundle").read_bytes(), original)

    def test_modified_bundle_is_rejected(self):
        self.capture()
        with (self.output / "source.bundle").open("ab") as stream:
            stream.write(b"changed")
        with self.assertRaisesRegex(ValueError, "checksum"):
            snapshot.verify(self.output)

    def test_compare_detects_new_changed_deleted_files_and_executable_mode(self):
        self.capture()
        snapshot.compare(self.root, self.output)
        (self.root / "ignored.log").write_text("build output is not source")
        snapshot.compare(self.root, self.output)
        for mutation in ("new", "changed", "deleted", "mode"):
            with self.subTest(mutation=mutation):
                app = self.root / "app.swift"
                added = self.root / "extra.swift"
                if mutation == "new":
                    added.write_text("unexpected source")
                elif mutation == "changed":
                    app.write_text("modified source")
                elif mutation == "deleted":
                    app.unlink()
                else:
                    app.chmod(0o755)
                with self.assertRaisesRegex(ValueError, "differs"):
                    snapshot.compare(self.root, self.output)
                if added.exists():
                    added.unlink()
                app.write_text("current source")
                app.chmod(0o644)

    def test_rejects_tracked_credentials_instead_of_silently_omitting(self):
        self.git("add", "-f", ".env.ios.local")
        with self.assertRaisesRegex(ValueError, "Credential"):
            self.capture()
        self.assertFalse(self.output.exists())

    def test_rejects_symlink_escape(self):
        (self.root / "linked.swift").symlink_to(self.parent / "outside")
        with self.assertRaisesRegex(ValueError, "Symlinks"):
            self.capture()

    def test_scan_failure_cleans_disposable_output(self):
        with patch.object(snapshot, "secret_scan", side_effect=ValueError("Secret scan failed")):
            with self.assertRaises(ValueError):
                self.capture()
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.parent.glob(".FottySourceCapture-*")), [])

    def test_source_race_refuses_publication(self):
        original = snapshot.manifest
        calls = 0
        def changing(root, destination=None):
            nonlocal calls
            calls += 1
            if calls == 2:
                (self.root / "app.swift").write_text("concurrent change")
            return original(root, destination)
        with patch.object(snapshot, "manifest", side_effect=changing):
            with self.assertRaisesRegex(ValueError, "changed"):
                self.capture()
        self.assertFalse(self.output.exists())


class PublicChecksumTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="FottyChecksumTest-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "owner-tools/testflight-usage-dashboard"
        self.renderer = self.app / "src/charting/SankeyRenderer.jsx"
        self.renderer.parent.mkdir(parents=True)
        self.renderer.write_text("export default function Chart() { return null; }\n")
        self.digest = hashlib.sha256(self.renderer.read_bytes()).hexdigest()
        self.path = self.app / "protected-runtime.json"
        self.path.write_text(json.dumps({"version": 1, "editablePaths": [],
                                       "files": {"src/charting/SankeyRenderer.jsx": self.digest}}, indent=2))
        self.line = next(i for i, line in enumerate(self.path.read_text().splitlines(), 1)
                         if "SankeyRenderer" in line)
        self.finding = {"File": str(self.path), "RuleID": "generic-api-key",
                        "StartLine": self.line, "EndLine": self.line}

    def test_only_exact_digest_of_copied_renderer_is_accepted(self):
        self.assertTrue(snapshot.verified_public_checksum(self.root, self.finding))
        self.renderer.write_text("changed renderer")
        self.assertFalse(snapshot.verified_public_checksum(self.root, self.finding))

    def test_wrong_rule_path_line_missing_target_and_malformed_manifest_reject(self):
        for change in ({"RuleID": "private-key"}, {"File": str(self.root / "other.json")},
                       {"StartLine": 0}, {"StartLine": "5"}, {"EndLine": self.line + 1},
                       {"StartLine": 999, "EndLine": 999}):
            with self.subTest(change=change):
                self.assertFalse(snapshot.verified_public_checksum(self.root, self.finding | change))
        self.renderer.unlink()
        self.assertFalse(snapshot.verified_public_checksum(self.root, self.finding))
        self.path.write_text("not a manifest")
        self.assertFalse(snapshot.verified_public_checksum(self.root, self.finding))

    def test_any_other_finding_or_scanner_error_still_blocks(self):
        from subprocess import CompletedProcess
        for result in (CompletedProcess([], 1, json.dumps([self.finding, self.finding | {"RuleID": "private-key"}]).encode()),
                       CompletedProcess([], 2, json.dumps([self.finding]).encode()),
                       CompletedProcess([], 1, b"[]"), CompletedProcess([], 1, b"not JSON")):
            with self.subTest(result=result):
                with patch.object(snapshot.subprocess, "run", return_value=result):
                    with self.assertRaisesRegex(ValueError, "Secret scan failed"):
                        snapshot.secret_scan(self.root)

    def test_same_line_duplicate_keys_cannot_hide_a_secret_behind_a_valid_checksum(self):
        lines = self.path.read_text().splitlines()
        lines[self.line - 1] = ('    "src/charting/SankeyRenderer.jsx": "unrelated-value", '
                               f'"src/charting/SankeyRenderer.jsx": "{self.digest}"')
        self.path.write_text("\n".join(lines))
        self.assertFalse(snapshot.verified_public_checksum(self.root, self.finding))

    @unittest.skipUnless(shutil.which("gitleaks"), "gitleaks not installed")
    def test_real_default_scanner_allows_checksum_but_rejects_another_credential(self):
        snapshot.secret_scan(self.root)
        # Synthetic scanner fixture, not a service credential; never print it.
        key = "".join(("c4L7w2X9m8Q3v6R1", "t5Y0p7B4n9H2s8D6"))
        (self.root / "fixture.txt").write_text(f'api_key = "{key}"\n')
        with self.assertRaisesRegex(ValueError, "Secret scan failed"):
            snapshot.secret_scan(self.root)


class SourceReceiptChecksumTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="FottySourceChecksumTest-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.key = "Fotty/Features/FPL/Services/FPLCoachAccessStore.swift"
        self.source = self.root / self.key
        self.source.parent.mkdir(parents=True)
        self.source.write_text("struct ExampleAccessStore {}\n")
        self.digest = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.path = self.root / "docs/testing/fotty25-remaining-2026-10-29/source-hashes.json"
        self.path.parent.mkdir(parents=True)
        self.path.write_text(json.dumps({"files": {self.key: self.digest}}, indent=2))
        line = next(i for i, text in enumerate(self.path.read_text().splitlines(), 1) if self.key in text)
        self.finding = {"File": str(self.path), "RuleID": "generic-api-key", "StartLine": line, "EndLine": line}

    def test_current_copied_source_digest_is_proven_and_changed_source_rejects(self):
        self.assertTrue(snapshot.verified_public_checksum(self.root, self.finding))
        self.source.write_text("changed source")
        self.assertFalse(snapshot.verified_public_checksum(self.root, self.finding))

    def test_arbitrary_manifest_wrong_rule_and_unproven_digest_reject(self):
        other = self.root / "other.json"
        other.write_bytes(self.path.read_bytes())
        self.assertFalse(snapshot.verified_public_checksum(self.root, self.finding | {"File": str(other)}))
        self.assertFalse(snapshot.verified_public_checksum(self.root, self.finding | {"RuleID": "private-key"}))
        self.path.write_text(self.path.read_text().replace(self.digest, "a" * 64))
        self.assertFalse(snapshot.verified_public_checksum(self.root, self.finding))

    def test_duplicate_mapping_and_symlink_cannot_supply_checksum_authority(self):
        self.path.write_text(json.dumps({"before": {self.key: self.digest}, "after": {self.key: self.digest}}, indent=2))
        line = next(i for i, text in enumerate(self.path.read_text().splitlines(), 1) if self.key in text)
        self.assertFalse(snapshot.verified_public_checksum(self.root, self.finding | {"StartLine": line, "EndLine": line}))
        self.path.write_text(json.dumps({"files": {self.key: self.digest}}, indent=2))
        target = self.root / "outside.swift"
        target.write_bytes(self.source.read_bytes())
        self.source.unlink()
        self.source.symlink_to(target)
        self.assertFalse(snapshot.verified_public_checksum(self.root, self.finding))

    @unittest.skipUnless(shutil.which("gitleaks"), "gitleaks not installed")
    def test_real_scanner_proves_only_checksum_and_still_blocks_credential(self):
        snapshot.secret_scan(self.root)
        key = "".join(("c4L7w2X9m8Q3v6R1", "t5Y0p7B4n9H2s8D6"))
        (self.root / "fixture.txt").write_text(f'api_key = "{key}"\n')
        with self.assertRaisesRegex(ValueError, "Secret scan failed"):
            snapshot.secret_scan(self.root)


if __name__ == "__main__":
    unittest.main()
