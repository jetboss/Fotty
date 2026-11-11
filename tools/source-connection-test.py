#!/usr/bin/env python3
"""Run the explicit all-enabled-source test bundle on a named physical iPad.

Reuse one owned --gate for build, metadata and physical runs. No simulator,
provider toggles, Watch integration, publication, cloud changes or TestFlight.
Only redacted tool attachments are exported into --report; raw results stay in
the owned gate and must be cleaned when the active qualification gate ends.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from copy import deepcopy

ROOT = Path(__file__).resolve().parents[1]
METHOD = "SourceConnectionToolTests/testAllEnabledSourcesForVerifiedFootballFixture"


def targets(value):
    if isinstance(value, dict):
        if "TestBundlePath" in value:
            yield value
        else:
            for child in value.values():
                yield from targets(child)
    elif isinstance(value, list):
        for child in value:
            yield from targets(child)


def prepare_run(document, fixture, playback, labels):
    selected = 0
    for target in targets(document):
        is_unit = "FottyTests.xctest" in target["TestBundlePath"]
        target["IsEnabled"] = is_unit
        if not is_unit:
            continue
        selected += 1
        target["OnlyTestIdentifiers"] = [METHOD]
        target.pop("SkipTestIdentifiers", None)
        env = target.setdefault("EnvironmentVariables", {})
        env.pop("FOTTY_PHYSICAL_LIVE_TEST", None)
        env.update(FOTTY_SOURCE_CONNECTION_TOOL="1", FOTTY_AUTOMATED_TESTING="1",
                   FOTTY_CONNECTION_FIXTURE=fixture,
                   FOTTY_CONNECTION_PLAYBACK="1" if playback else "0",
                   FOTTY_CONNECTION_LABELS=labels)
    if selected != 1:
        raise ValueError("Expected exactly one actual FottyTests target")
    return document


def reports(folder):
    results = []
    for path in folder.rglob("*"):
        if not path.is_file() or path.stat().st_size > 256 * 1024:
            continue
        try:
            obj = json.loads(path.read_text())
        except (ValueError, UnicodeError):
            continue
        if isinstance(obj, dict) and obj.get("schemaVersion") == 1 and "rows" in obj and "kickoffUTC" in obj:
            # The producer's typed schema contains no URLs/headers/credentials.
            # Recheck externally before preserving its report beyond the gate.
            text = json.dumps(obj)
            if re.search(r"https?://|Bearer |BEGIN PRIVATE|playableURL|requiredHeaders", text, re.I):
                raise ValueError("Rejected unexpected private/transport data in tool report")
            results.append(obj)
    return results


def execution_receipt(report, exit_code):
    value = deepcopy(report)
    complete = value.get("completion", "running") != "running"
    value["executionExitCode"] = exit_code
    value["executionState"] = ("collection_complete" if exit_code == 0 and complete else
                               "incomplete" if exit_code == 0 else
                               "interrupted" if exit_code in (75, 130, -2, -15) else "test_failed")
    return value


def run(args):
    gate = Path(args.gate).resolve()
    if not gate.is_dir() or not gate.name.startswith("fotty-connection-tool."):
        raise ValueError("Use one explicitly owned fotty-connection-tool.* gate")
    if not re.fullmatch(r"[A-Fa-f0-9-]{20,40}", args.device):
        raise ValueError("Explicit physical iPad identifier required")
    if not re.fullmatch(r"sports-fixture:(?:premier-league|champions-league):[A-Za-z0-9_-]{1,80}", args.fixture):
        raise ValueError("Pin an official Premier League or Champions League fixture")
    details = gate / "device.json"
    subprocess.run(["xcrun", "devicectl", "device", "info", "details", "--device", args.device,
                    "--json-output", str(details)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    hardware = json.loads(details.read_text()).get("result", {}).get("hardwareProperties", {})
    if not hardware.get("productType", "").startswith("iPad"):
        raise ValueError("This gate is iPad-only; phones are excluded")
    lock = gate / "lock.json"
    subprocess.run(["xcrun", "devicectl", "device", "info", "lockState", "--device", args.device,
                    "--json-output", str(lock)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    if json.loads(lock.read_text()).get("result", {}).get("passcodeRequired"):
        raise ValueError("The iPad needs manual unlock; no test was started")
    if args.build:
        import shutil
        if shutil.disk_usage(gate).free < 8 * 1024 ** 3:
            raise ValueError("Insufficient free disk for the bounded physical build")
        with (gate / "build.log").open("w") as output:
            subprocess.run(["xcodebuild", "build-for-testing", "-project", "Fotty.xcodeproj", "-scheme", "Fotty",
                "-configuration", "Debug", "-destination", "platform=iOS,id=" + args.device,
                "-derivedDataPath", str(gate / "DerivedData"), "-jobs", "2", "-parallel-testing-enabled", "NO",
                "-allowProvisioningUpdates", "ENABLE_TESTABILITY=YES", "OTHER_SWIFT_FLAGS=$(inherited) -DFOTTY_SOURCE_CONNECTION_TOOL -DFOTTY_REVIEWED_ADDON_CANARY"],
                cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True)
    candidates = []
    for path in (gate / "DerivedData/Build/Products").glob("*.xctestrun"):
        if path.name == "connection.xctestrun" or path.name.startswith("Jet-live-"):
            continue
        with path.open("rb") as stream:
            if any(t["TestBundlePath"].endswith("/FottyTests.xctest") for t in targets(plistlib.load(stream))):
                candidates.append(path)
    if len(candidates) != 1:
        raise ValueError("Build the opt-in tool once for this physical iPad before running it")
    with candidates[0].open("rb") as stream:
        document = prepare_run(plistlib.load(stream), args.fixture, args.mode == "playback", args.labels)
    # __TESTROOT__ is relative to this file, not the runner's working directory.
    configured = candidates[0].with_name("connection.xctestrun")
    with configured.open("wb") as stream:
        plistlib.dump(document, stream)
    result = gate / (args.mode + ".xcresult")
    if result.exists():
        raise ValueError("Preserve/export the previous run before reusing this result name")
    log = gate / (args.mode + ".log")
    with log.open("w") as output:
        completed = subprocess.run(["xcodebuild", "test-without-building", "-xctestrun", str(configured),
            "-destination", "platform=iOS,id=" + args.device, "-parallel-testing-enabled", "NO",
            "-only-testing:FottyTests/" + METHOD, "-resultBundlePath", str(result)],
            cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    exported = gate / (args.mode + "-attachments")
    if result.exists():
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
            "--output-path", str(exported)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    receipts = reports(exported) if exported.exists() else []
    if receipts:
        latest = execution_receipt(max(receipts, key=lambda row: (row.get("sequence", 0), row["observedAtUTC"],
                                               len(row["rows"]), row["completion"] != "running")), completed.returncode)
        target = Path(args.report).resolve()
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(latest, indent=2) + "\n")
        print(json.dumps({"report": str(target), "collection": latest["completion"],
                          "providersRecorded": len(latest["rows"]), "executionState": latest["executionState"],
                          "decodedHolds": sum(choice["result"].startswith("decoded_90_seconds") for row in latest["rows"] for choice in row.get("deliveries", [])),
                          "manualWebGates": sum(choice["result"] == "manual_web_gate_required" for row in latest["rows"] for choice in row.get("deliveries", [])),
                          "xcodeExitCode": completed.returncode}))
    else:
        print("No connection receipt was produced. Inspect the owned gate; this is not a source/playback pass.", file=sys.stderr)
    return completed.returncode or (0 if receipts else 2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gate", required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--fixture", required=True)
    parser.add_argument("--mode", choices=["metadata", "playback"], required=True)
    parser.add_argument("--labels", default="", help="Optional exact opaque labels to restrict physical holds, never source opt-ins")
    parser.add_argument("--build", action="store_true", help="Build once in the same bounded gate before testing")
    parser.add_argument("--report", required=True)
    try:
        sys.exit(run(parser.parse_args()))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(type(error).__name__ + ": " + str(error), file=sys.stderr)
        sys.exit(2)
