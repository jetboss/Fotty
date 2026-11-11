"""Offline version/configuration fixtures; no Xcode or user source mutation."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which("ruby"), "System Ruby is required for the native gate")
class NativeVersionCheckTests(unittest.TestCase):
    verifier = Path(__file__).resolve().parents[1] / "verify-native-version.rb"
    project = """targets:
  Fotty:
    settings:
      base:
        MARKETING_VERSION: 2.0.1
        CURRENT_PROJECT_VERSION: 113
      configs:
        Debug:
          SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG
  FottyLiveActivityExtension:
    settings:
      base:
        MARKETING_VERSION: 2.0.1
        CURRENT_PROJECT_VERSION: 113
"""
    xcode = ("MARKETING_VERSION = 2.0.1;\nCURRENT_PROJECT_VERSION = 113;\n" * 4)

    def check(self, project=None, xcode=None):
        with tempfile.TemporaryDirectory(prefix="FottyVersionTest-") as work:
            root = Path(work)
            config = root / "project.yml"
            pbx = root / "project.pbxproj"
            config.write_text(self.project if project is None else project)
            pbx.write_text(self.xcode if xcode is None else xcode)
            return subprocess.run(["ruby", str(self.verifier), str(config), str(pbx)],
                                  capture_output=True, text=True, check=False)

    def test_matching_source_and_four_configurations_pass(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("2.0.1 (113)", result.stdout)

    def test_malformed_source_indentation_is_rejected(self):
        changed = self.project.replace("        CURRENT_PROJECT_VERSION: 113",
                                       "    CURRENT_PROJECT_VERSION: 113", 1)
        self.assertNotEqual(self.check(project=changed).returncode, 0)

    def test_valid_yaml_with_missing_base_version_is_rejected(self):
        changed = self.project.replace("        CURRENT_PROJECT_VERSION: 113\n", "", 1)
        self.assertNotEqual(self.check(project=changed).returncode, 0)

    def test_differing_extension_build_is_rejected(self):
        changed = self.project.replace("CURRENT_PROJECT_VERSION: 113", "CURRENT_PROJECT_VERSION: 114", 1)
        self.assertNotEqual(self.check(project=changed).returncode, 0)

    def test_generated_project_drift_is_rejected(self):
        changed = self.xcode.replace("CURRENT_PROJECT_VERSION = 113;", "CURRENT_PROJECT_VERSION = 112;", 1)
        self.assertNotEqual(self.check(xcode=changed).returncode, 0)

    def test_missing_generated_configuration_is_rejected(self):
        changed = self.xcode.replace("CURRENT_PROJECT_VERSION = 113;\n", "", 1)
        self.assertNotEqual(self.check(xcode=changed).returncode, 0)

    def test_invalid_build_number_is_rejected(self):
        changed = self.project.replace("CURRENT_PROJECT_VERSION: 113", "CURRENT_PROJECT_VERSION: 0")
        self.assertNotEqual(self.check(project=changed).returncode, 0)


if __name__ == "__main__":
    unittest.main()
