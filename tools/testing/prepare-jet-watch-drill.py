#!/usr/bin/env python3
"""Pin the compiled UI suite to one fresh, actually live official fixture. Never installs or changes source settings."""
import argparse, datetime as dt, json, plistlib, re, subprocess
from pathlib import Path

UTC = dt.timezone.utc
BASE = "https://fotty-playback-v3.adaptive-rhubarb.workers.dev/api/"
TEST = "WatchRetry220PhysicalUITests/testCurrentNamedMatchThroughWatch"

def instant(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(UTC)

def fresh(s, now):
    return -300 <= (now - instant(s)).total_seconds() <= 600

def live_pin(doc, fixture, now):
    kind = "cricket" if fixture.startswith("cricket-fixture:") else "sports"
    raw_id = fixture.removeprefix("cricket-fixture:") if kind == "cricket" else fixture
    if doc.get("sourceStatus") not in {"verified", "partial"} or not fresh(doc["checkedAt"], now):
        raise ValueError("No fresh official fixture snapshot")
    rows = [r for r in doc["fixtures"] if r["id"] == raw_id]
    if len(rows) != 1:
        raise ValueError("Fixture absent or ambiguous")
    row = rows[0]
    if row["status"] != "live" or row["source"].get("verification", "verified") != "verified" or not fresh(row["source"]["observedAt"], now):
        raise ValueError("No verified current in-progress status (kickoff alone is insufficient)")
    if kind == "cricket":
        teams = [row["home"]["name"], row["away"]["name"]]
    else:
        if row["competitionId"] != fixture.split(":")[1]:
            raise ValueError("Official fixture ID and competition disagree")
        teams = [p["name"] for p in row["participants"]]
    if len(teams) != 2 or teams[0] == teams[1]:
        raise ValueError("No exact two-participant fixture")
    return row.get("title") or " vs ".join(teams)

def pin_suite(path, target_id, title, force):
    with path.open("rb") as f:
        config = plistlib.load(f)
    version = config.get("__xctestrun_metadata__", {}).get("FormatVersion")
    if version == 1:
        # v1 uses top-level named test targets; never leave a sibling executable enabled.
        targets = [value for key, value in config.items() if not key.startswith("__") and isinstance(value, dict)]
        if len(targets) != 1:
            raise ValueError("Use the dedicated physical UI scheme for v1")
    elif version == 2 or "TestConfigurations" in config:
        targets = [target for group in config.get("TestConfigurations", []) for target in group.get("TestTargets", [])]
    else:
        raise ValueError("Unsupported compiled test-run format")
    selected = 0
    for target in targets:
        is_ui = target.get("BlueprintName") == "FottyUITests"
        if version != 1:
            target["IsEnabled"] = is_ui
        if not is_ui:
            continue
        selected += 1
        target["OnlyTestIdentifiers"] = [TEST]
        target.pop("SkipTestIdentifiers", None)
        env = target.setdefault("EnvironmentVariables", {})
        env.update(FOTTY_WATCH220_PHYSICAL="1", FOTTY_FIXTURE_GATE_ID=target_id, FOTTY_FIXTURE_GATE_TITLE=title,
                   FOTTY_FORCE_SOURCE_FAILURE="1" if force else "0")
    if selected != 1:
        raise ValueError("Expected exactly one compiled FottyUITests target")
    return config

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("xctestrun", type=Path)
    ap.add_argument("fixture")
    ap.add_argument("--force-source-failure", action="store_true")
    args = ap.parse_args()
    if not re.fullmatch(r"(?:sports-fixture:(?:nhl|premier-league|champions-league):[a-zA-Z0-9_-]{1,80}|cricket-fixture:[a-zA-Z0-9:_-]{1,100})", args.fixture):
        raise ValueError("Unsupported qualification fixture ID")
    endpoint = ("cricket" if args.fixture.startswith("cricket-fixture:") else "sports") + "/fixtures"
    raw = subprocess.check_output(["curl", "--fail", "--silent", "--show-error", "--max-time", "20",
                                    "--max-filesize", "3600000", "--proto", "=https",
                                    "-H", "Accept: application/json", BASE + endpoint])
    doc = json.loads(raw)
    title = live_pin(doc, args.fixture, dt.datetime.now(UTC))
    path = args.xctestrun.resolve()
    output = path.with_name("Jet-live-outage.xctestrun" if args.force_source_failure else "Jet-live-watch.xctestrun")
    if path == output or not path.is_file():
        raise ValueError("Use a separate original compiled test run")
    result = pin_suite(path, args.fixture, title, args.force_source_failure)
    with output.open("wb") as f:
        plistlib.dump(result, f)
    print(json.dumps({"fixture": args.fixture, "title": title, "verifiedAt": doc["checkedAt"], "xctestrun": str(output)}))

if __name__ == "__main__":
    main()

