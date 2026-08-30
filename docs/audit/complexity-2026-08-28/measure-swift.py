"""Read-only Swift metrics; no build, cache, global install or persistent download.

Run from the repository root: PYTHONDONTWRITEBYTECODE=1 python3 <this file>
The pinned official portable SwiftLint binary is verified and trap-cleaned by
TemporaryDirectory. Only this audit's configuration is used; no autocorrection.
"""
import collections
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[3]
VERSION = "0.65.1"
DIGEST = "c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"
CONFIG = Path(__file__).with_name("swiftlint.yml")


def main():
    with tempfile.TemporaryDirectory(prefix="fotty-swiftlint-audit-") as temporary:
        archive = Path(temporary) / "swiftlint.zip"
        subprocess.run([
            "curl", "-fsSL", "--max-time", "90",
            f"https://github.com/realm/SwiftLint/releases/download/{VERSION}/portable_swiftlint.zip",
            "-o", str(archive),
        ], check=True)
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == DIGEST
        with zipfile.ZipFile(archive) as package:
            assert all(not p.startswith("/") and ".." not in PurePosixPath(p).parts
                       for p in package.namelist())
            package.extractall(temporary)
        binary = Path(temporary) / "swiftlint"
        os.chmod(binary, 0o755)
        command = [str(binary), "lint", "--config", str(CONFIG), "--no-cache",
                   "--quiet", "--disable-sourcekit", "--reporter", "json"]
        calibration = []
        for source in [
            "func f() { if a { b() }; guard c else { return }; while d { e() } }",
            "func f() { switch x { case .a: a(); case .b: b(); default: c() } }",
            'func f() { let s = #"""\nif (a) { if (b) {} }\n"""#; if x { y() } }',
        ]:
            run = subprocess.run(command + ["--use-stdin"], input=source,
                                 text=True, capture_output=True, timeout=30)
            assert run.returncode in (0, 2), run.stderr
            calibration.append(json.loads(run.stdout))
        run = subprocess.run(command + [str(ROOT / "Fotty"),
                                       str(ROOT / "FottyLiveActivityExtension")],
                             text=True, capture_output=True, timeout=120)
        assert run.returncode in (0, 2), run.stderr
        rows = {}
        for finding in json.loads(run.stdout):
            path = str(Path(finding["file"]).relative_to(ROOT))
            line = finding["line"]
            row = rows.setdefault((path, line), {
                "file": path, "line": line,
                "declaration": Path(finding["file"]).read_text().splitlines()[line - 1].strip(),
            })
            # Both selected official rule messages end with the observed value.
            observed = int(re.findall(r"\d+", finding["reason"])[-1])
            key = "cc" if finding["rule_id"] == "cyclomatic_complexity" else "bodyLines"
            row[key] = observed
        rows = list(rows.values())
        functions = [row for row in rows if "cc" in row]
        groups = collections.defaultdict(list)
        for row in functions:
            group = ("FPL" if "/FPL/" in row["file"] else
                     "Player" if "/Player/" in row["file"] else "Other app/extension")
            groups[group].append(row)
        print(json.dumps({
            "tool": f"SwiftLint {VERSION}", "scanExit": run.returncode,
            "metricNote": "SwiftLint decision-syntax score, not ESLint classic CC; zero-score bodies omitted from the complexity summary. Conditional compilation branches are not resolved.",
            "sourceFileCount": sum(1 for folder in [ROOT / "Fotty", ROOT / "FottyLiveActivityExtension"]
                                   for _ in folder.rglob("*.swift")),
            "stderr": run.stderr, "calibration": calibration,
            "summary": {group: {
                "nonZeroComplexityBodies": len(values),
                "over10": sum(row["cc"] > 10 for row in values),
                "over20": sum(row["cc"] > 20 for row in values),
                "max": max(row["cc"] for row in values),
            } for group, values in groups.items()},
            "hotspots": sorted([row for row in functions if row["cc"] > 10],
                               key=lambda row: -row["cc"]),
            "longest": sorted(rows, key=lambda row: -row.get("bodyLines", 0))[:12],
        }, separators=(",", ":")))


if __name__ == "__main__":
    main()
