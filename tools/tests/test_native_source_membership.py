"""Synthetic, offline PBX groups/source trees; never changes the user project."""
import copy
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest


TOOL = Path(__file__).resolve().parents[1] / "check_native_source_membership.py"
spec = importlib.util.spec_from_file_location("native_membership", TOOL)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class NativeSourceMembershipTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="FottyMembershipTest-")
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.objects = {
            "PROJECT": {"isa": "PBXProject", "mainGroup": "MAIN", "targets": []},
            "MAIN": {"isa": "PBXGroup", "sourceTree": "<group>", "children": []},
        }
        self.project = {"rootObject": "PROJECT", "objects": self.objects}
        self.sources = {}
        for target, directory in gate.TARGET_ROOTS.items():
            (self.root / directory).mkdir()
            self.objects["MAIN"]["children"].append("GROUP_" + target)
            self.objects["GROUP_" + target] = {
                "isa": "PBXGroup", "path": directory, "sourceTree": "<group>", "children": []}
            self.objects["PROJECT"]["targets"].append(target)
            self.objects[target] = {"isa": "PBXNativeTarget", "name": target, "buildPhases": ["PHASE_" + target]}
            self.objects["PHASE_" + target] = {"isa": "PBXSourcesBuildPhase", "files": []}
            self.add_source(target, directory + "/" + target + ".swift")
        self.shared_ref = self.add_source("Fotty", gate.SHARED_EXTENSION_SOURCE, source_root=True)
        self.add_membership("FottyLiveActivityExtension", self.shared_ref)
        for path in gate.SHARED_EXTENSION_SOURCES - {gate.SHARED_EXTENSION_SOURCE}:
            self.add_membership("FottyLiveActivityExtension", self.add_source("Fotty", path, source_root=True))

    def add_source(self, target, path, source_root=False):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text("// tiny synthetic source\n")
        ref = "REF_" + str(len(self.sources))
        self.sources[path] = ref
        self.objects[ref] = {"isa": "PBXFileReference", "path": path if source_root else Path(path).name,
                             "sourceTree": "SOURCE_ROOT" if source_root else "<group>",
                             "lastKnownFileType": "sourcecode.swift"}
        self.objects["GROUP_" + target]["children"].append(ref)
        self.add_membership(target, ref)
        return ref

    def add_membership(self, target, ref):
        build = "BUILD_" + str(len(self.objects))
        self.objects[build] = {"isa": "PBXBuildFile", "fileRef": ref}
        self.objects["PHASE_" + target]["files"].append(build)
        return build

    def audit(self):
        return gate.audit_membership(self.root, self.project)

    def rejects(self, fragment):
        with self.assertRaises(gate.MembershipError) as raised:
            self.audit()
        self.assertIn(fragment, str(raised.exception))

    def test_four_targets_and_deliberate_shared_source_pass(self):
        self.assertEqual(self.audit(), {"Fotty": 3, "FottyTests": 1, "FottyUITests": 1,
                                      "FottyLiveActivityExtension": 3})

    def test_new_file_without_sources_registration_fails(self):
        (self.root / "Fotty/New.swift").write_text("// new\n")
        self.rejects("missing Sources membership: Fotty/New.swift")

    def test_stale_membership_for_deleted_file_fails(self):
        (self.root / "Fotty/Fotty.swift").unlink()
        self.rejects("extra or stale Sources membership: Fotty/Fotty.swift")

    def test_wrong_target_membership_fails(self):
        ref = self.sources["FottyTests/FottyTests.swift"]
        self.add_membership("Fotty", ref)
        self.rejects("Fotty: extra or stale Sources membership: FottyTests/FottyTests.swift")

    def test_duplicate_membership_different_build_ids_fails(self):
        self.add_membership("Fotty", self.shared_ref)
        self.rejects("duplicate Sources membership (2)")

    def test_duplicate_membership_same_build_id_fails(self):
        files = self.objects["PHASE_Fotty"]["files"]
        files.append(files[0])
        self.rejects("duplicate Sources membership (2)")

    def test_same_basename_in_separate_nested_groups_is_resolved(self):
        ref = self.add_source("Fotty", "Fotty/Nested/Fotty.swift")
        group = "NESTED"
        self.objects[group] = {"isa": "PBXGroup", "path": "Nested", "sourceTree": "<group>", "children": [ref]}
        children = self.objects["GROUP_Fotty"]["children"]
        children.remove(ref)
        children.append(group)
        self.assertEqual(self.audit()["Fotty"], 4)

    def test_source_root_group_ignores_display_parent_path(self):
        ref = self.add_source("Fotty", "Fotty/Nested/New.swift")
        self.objects["ABS_GROUP"] = {"isa": "PBXGroup", "path": "Fotty/Nested", "sourceTree": "SOURCE_ROOT", "children": [ref]}
        children = self.objects["GROUP_Fotty"]["children"]
        children.remove(ref)
        children.append("ABS_GROUP")
        self.assertEqual(self.audit()["Fotty"], 4)

    def test_cosmetic_group_name_is_not_treated_as_directory(self):
        self.objects["COSMETIC"] = {"isa": "PBXGroup", "name": "Presentation", "sourceTree": "<group>", "children": []}
        self.objects["MAIN"]["children"].append("COSMETIC")
        self.assertEqual(self.audit()["Fotty"], 3)

    def test_escape_path_is_rejected(self):
        self.objects[self.shared_ref]["path"] = "../outside.swift"
        self.rejects("Path escapes source root")

    def test_absolute_and_build_variable_paths_are_rejected(self):
        original = self.objects[self.shared_ref]["path"]
        for path, message in [("/tmp/outside.swift", "Path escapes"),
                              ("$(SRCROOT)/" + original, "unsafe path"),
                              ("${SRCROOT}/" + original, "unsafe path")]:
            with self.subTest(path=path):
                self.objects[self.shared_ref]["path"] = path
                self.rejects(message)
        self.objects[self.shared_ref]["path"] = original

    def test_ambiguous_repeated_file_placement_is_rejected(self):
        self.objects["MAIN"]["children"].append(self.shared_ref)
        self.rejects("Ambiguous repeated")

    def test_cyclic_group_is_rejected(self):
        self.objects["GROUP_Fotty"]["children"].append("MAIN")
        self.rejects("Cyclic")

    def test_missing_group_reference_is_rejected(self):
        self.objects["MAIN"]["children"].append("MISSING")
        self.rejects("Unresolved or invalid")

    def test_missing_build_file_reference_is_rejected(self):
        build = self.objects["PHASE_Fotty"]["files"][0]
        self.objects[build]["fileRef"] = "MISSING"
        self.rejects("Unresolved or invalid PBXFileReference")

    def test_malformed_object_type_is_rejected(self):
        self.objects["MAIN"]["isa"] = []
        self.rejects("Invalid PBX object")

    def test_malformed_source_tree_is_rejected(self):
        self.objects[self.shared_ref]["sourceTree"] = []
        self.rejects("Unsupported file source tree")

    def test_malformed_target_name_is_rejected(self):
        self.objects["Fotty"]["name"] = []
        self.rejects("duplicate native target")

    def test_unplaced_sources_reference_is_rejected(self):
        self.objects["GROUP_Fotty"]["children"].remove(self.shared_ref)
        self.rejects("unplaced or product source reference")

    def test_product_cannot_be_compiled_as_source(self):
        self.objects[self.shared_ref]["sourceTree"] = "BUILT_PRODUCTS_DIR"
        self.rejects("unplaced or product source reference")

    def test_shared_source_must_be_in_extension(self):
        files = self.objects["PHASE_FottyLiveActivityExtension"]["files"]
        files[:] = [build for build in files if self.objects[build]["fileRef"] != self.shared_ref]
        self.rejects("FottyLiveActivityExtension: missing Sources membership: " + gate.SHARED_EXTENSION_SOURCE)

    def test_missing_native_target_is_rejected(self):
        self.objects["PROJECT"]["targets"].remove("FottyTests")
        self.rejects("Native target set")

    def test_duplicate_target_name_is_rejected(self):
        self.objects["FottyUITests"]["name"] = "FottyTests"
        self.rejects("duplicate native target")

    def test_multiple_sources_phases_are_rejected(self):
        self.objects["Fotty"]["buildPhases"].append("PHASE_Fotty")
        self.rejects("exactly one explicit Sources phase")

    def test_filtered_membership_is_rejected(self):
        build = self.objects["PHASE_Fotty"]["files"][0]
        self.objects[build]["platformFilter"] = "ios"
        self.rejects("filtered Sources membership")

    def test_synchronized_groups_are_rejected(self):
        self.objects["SYNC"] = {"isa": "PBXFileSystemSynchronizedRootGroup"}
        self.rejects("Synchronized groups")

    def test_symlinked_swift_file_is_rejected(self):
        (self.root / "Fotty/Linked.swift").symlink_to(self.root / "Fotty/Fotty.swift")
        self.rejects("Unsafe Swift source")

    def test_symlinked_source_directory_is_rejected(self):
        (self.root / "Fotty/Linked").symlink_to(self.root / "FottyTests", target_is_directory=True)
        self.rejects("Symlinked source directory")

    def test_missing_source_scope_is_rejected(self):
        (self.root / "FottyTests/FottyTests.swift").unlink()
        (self.root / "FottyTests").rmdir()
        self.rejects("Missing or symlinked source directory")

    def test_non_swift_resources_are_not_compiler_membership(self):
        (self.root / "Fotty/asset.png").write_bytes(b"tiny resource")
        self.assertEqual(self.audit()["Fotty"], 3)

    def test_object_limit_is_enforced(self):
        oversized = copy.deepcopy(self.project)
        oversized["objects"].update({"EXTRA_" + str(i): {} for i in range(gate.MAX_OBJECTS)})
        with self.assertRaisesRegex(gate.MembershipError, "oversized"):
            gate.audit_membership(self.root, oversized)

    @unittest.skipUnless(sys.platform == "darwin", "macOS plutil conversion")
    def test_cli_converts_property_list_and_never_rewrites_it(self):
        path = self.root / "project.pbxproj"
        content = plistlib.dumps(self.project)
        path.write_bytes(content)
        result = subprocess.run([sys.executable, str(TOOL), "--root", str(self.root), "--project", str(path)],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Shared activity attributes verified", result.stdout)
        self.assertEqual(path.read_bytes(), content)


if __name__ == "__main__":
    unittest.main()
