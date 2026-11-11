#!/usr/bin/env python3
"""Read-only Swift source/explicit Xcode target membership gate; no Xcode needed.

Compare the filesystem with the project's resolved PBX groups, not comment text
or bare basenames. Synchronized groups and build-variable paths need a reviewed
policy before this explicit-membership gate can safely cover them.
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys


TARGET_ROOTS = {
    "Fotty": "Fotty",
    "FottyTests": "FottyTests",
    "FottyUITests": "FottyUITests",
    "FottyLiveActivityExtension": "FottyLiveActivityExtension",
}
SHARED_EXTENSION_SOURCE = "Fotty/Core/LiveActivities/FottyMatchActivityAttributes.swift"
SHARED_EXTENSION_SOURCES = {SHARED_EXTENSION_SOURCE, "Fotty/Core/Continuity/SportsWidgetSnapshot.swift"}
MAX_PROJECT_BYTES = 8 * 1024 * 1024
MAX_JSON_BYTES = 16 * 1024 * 1024
MAX_OBJECTS = 20000
MAX_ENTRIES = 100000
MAX_GROUP_DEPTH = 128


class MembershipError(ValueError):
    pass


def checked_list(value, label):
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise MembershipError(f"Invalid reference list: {label}")
    return value


def safe_relative(value, label, allow_empty=False):
    if not isinstance(value, str) or (not value and not allow_empty):
        raise MembershipError(f"Missing path: {label}")
    if "\\" in value or "\x00" in value or "$" in value:
        raise MembershipError(f"Unresolved or unsafe path: {label}")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts:
        raise MembershipError(f"Path escapes source root: {label}")
    return path


def filesystem_sources(root):
    inventories = {}
    entries = 0
    for target, directory in TARGET_ROOTS.items():
        folder = root / directory
        if folder.is_symlink() or not folder.is_dir():
            raise MembershipError(f"Missing or symlinked source directory: {directory}")
        sources = set()
        for base, directories, files in os.walk(folder, followlinks=False):
            entries += len(directories) + len(files) + 1
            if entries > MAX_ENTRIES:
                raise MembershipError("Filesystem inventory exceeds bounded entry limit")
            for name in directories:
                if (Path(base) / name).is_symlink():
                    raise MembershipError(f"Symlinked source directory: {Path(base, name).relative_to(root)}")
            for name in files:
                if not name.endswith(".swift"):
                    continue
                path = Path(base) / name
                if path.is_symlink() or not path.is_file():
                    raise MembershipError(f"Unsafe Swift source: {path.relative_to(root)}")
                sources.add(path.relative_to(root).as_posix())
        inventories[target] = sources
    if not SHARED_EXTENSION_SOURCES.issubset(inventories["Fotty"]):
        raise MembershipError("Deliberately shared activity attributes source is missing")
    inventories["FottyLiveActivityExtension"].update(SHARED_EXTENSION_SOURCES)
    return inventories


def audit_membership(root, project):
    """Return per-target counts or fail closed; accepts parsed plutil JSON."""
    root = Path(root).resolve()
    if not isinstance(project, dict):
        raise MembershipError("Invalid PBX project document")
    objects = project.get("objects")
    if not isinstance(objects, dict) or not objects or len(objects) > MAX_OBJECTS:
        raise MembershipError("Invalid or oversized PBX object table")

    def object_for(identifier, expected=None):
        value = objects.get(identifier) if isinstance(identifier, str) else None
        if not isinstance(value, dict) or (expected and value.get("isa") != expected):
            raise MembershipError(f"Unresolved or invalid {expected or 'PBX'} reference: {identifier}")
        return value

    owner = object_for(project.get("rootObject"), "PBXProject")
    if owner.get("projectDirPath", "") or owner.get("projectRoot", ""):
        raise MembershipError("Non-default project root needs an explicit reviewed path policy")
    for value in objects.values():
        if not isinstance(value, dict) or not isinstance(value.get("isa"), str):
            raise MembershipError("Invalid PBX object")
        if "Synchronized" in str(value.get("isa", "")):
            raise MembershipError("Synchronized groups are not explicit Sources membership")

    # One file may have display aliases, but it must not have multiple group
    # placements: the meaning of a <group> source would otherwise be ambiguous.
    resolved = {}
    visited = set()

    def visit(identifier, parent, ancestors):
        if len(ancestors) >= MAX_GROUP_DEPTH or identifier in ancestors:
            raise MembershipError("Cyclic or excessively deep PBX group hierarchy")
        if identifier in visited:
            raise MembershipError(f"Ambiguous repeated PBX group/file placement: {identifier}")
        visited.add(identifier)
        value = object_for(identifier)
        kind = value.get("isa")
        if kind in {"PBXGroup", "PBXVariantGroup"}:
            tree = value.get("sourceTree", "<group>")
            if not isinstance(tree, str) or tree not in {"<group>", "SOURCE_ROOT"}:
                raise MembershipError(f"Unsupported group source tree: {identifier}")
            component = safe_relative(value.get("path", ""), identifier, allow_empty=True)
            location = (parent if tree == "<group>" else PurePosixPath()) / component
            for child in checked_list(value.get("children", []), identifier):
                visit(child, location, ancestors | {identifier})
        elif kind == "PBXFileReference":
            tree = value.get("sourceTree", "<group>")
            # Products are permitted in the navigator, never as compiled source.
            if tree == "BUILT_PRODUCTS_DIR":
                return
            if not isinstance(tree, str) or tree not in {"<group>", "SOURCE_ROOT"}:
                raise MembershipError(f"Unsupported file source tree: {identifier}")
            component = safe_relative(value.get("path"), identifier)
            location = (parent if tree == "<group>" else PurePosixPath()) / component
            resolved[identifier] = location.as_posix()
        else:
            raise MembershipError(f"Unsupported group child: {identifier} ({kind})")

    visit(owner.get("mainGroup"), PurePosixPath(), set())
    targets = {}
    for identifier in checked_list(owner.get("targets"), "project targets"):
        target = object_for(identifier, "PBXNativeTarget")
        name = target.get("name")
        if not isinstance(name, str) or name not in TARGET_ROOTS or name in targets:
            raise MembershipError(f"Missing policy or duplicate native target: {name}")
        targets[name] = target
    if set(targets) != set(TARGET_ROOTS):
        raise MembershipError("Native target set does not match the four reviewed source scopes")

    expected = filesystem_sources(root)
    errors = []
    counts = {}
    for name, target in targets.items():
        phases = []
        for identifier in checked_list(target.get("buildPhases"), f"{name} build phases"):
            phase = object_for(identifier)
            if phase.get("isa") == "PBXSourcesBuildPhase":
                phases.append(phase)
        if len(phases) != 1:
            raise MembershipError(f"{name}: expected exactly one explicit Sources phase")
        membership = []
        for identifier in checked_list(phases[0].get("files"), f"{name} Sources"):
            build = object_for(identifier, "PBXBuildFile")
            ref = build.get("fileRef")
            file = object_for(ref, "PBXFileReference")
            path = resolved.get(ref)
            if path is None:
                raise MembershipError(f"{name}: unplaced or product source reference: {ref}")
            # Conditional compilation membership is not full target coverage.
            if build.get("platformFilter") or build.get("platformFilters"):
                raise MembershipError(f"{name}: filtered Sources membership needs a reviewed policy: {path}")
            if (path.endswith(".swift") or file.get("lastKnownFileType") == "sourcecode.swift"
                    or file.get("explicitFileType") == "sourcecode.swift"):
                if not path.endswith(".swift"):
                    raise MembershipError(f"{name}: Swift file type has a non-Swift path: {path}")
                membership.append(path)
        actual = set(membership)
        for path, count in Counter(membership).items():
            if count > 1:
                errors.append(f"{name}: duplicate Sources membership ({count}): {path}")
        errors.extend(f"{name}: missing Sources membership: {path}" for path in sorted(expected[name] - actual))
        errors.extend(f"{name}: extra or stale Sources membership: {path}" for path in sorted(actual - expected[name]))
        counts[name] = len(actual)
    if errors:
        raise MembershipError("\n".join(errors))
    return counts


def read_project(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_PROJECT_BYTES:
        raise MembershipError("Missing, symlinked or oversized PBX project")
    try:
        result = subprocess.run(["/usr/bin/plutil", "-convert", "json", "-o", "-", str(path)],
                                capture_output=True, timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise MembershipError("plutil could not read the PBX project") from error
    if result.returncode or len(result.stdout) > MAX_JSON_BYTES:
        raise MembershipError("PBX conversion failed or exceeded bounded output limit")
    try:
        return json.loads(result.stdout)
    except (ValueError, UnicodeDecodeError) as error:
        raise MembershipError("plutil returned an invalid PBX document") from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--project", type=Path, help="Defaults to ROOT/Fotty.xcodeproj/project.pbxproj")
    args = parser.parse_args()
    try:
        project = args.project or args.root / "Fotty.xcodeproj/project.pbxproj"
        counts = audit_membership(args.root, read_project(project))
    except (MembershipError, OSError) as error:
        print(f"Native source membership failed: {error}", file=sys.stderr)
        return 1
    print("Native source membership coherent: " + ", ".join(
        f"{name}={counts[name]}" for name in TARGET_ROOTS) + ". Shared activity attributes verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
