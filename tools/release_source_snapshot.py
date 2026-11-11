#!/usr/bin/env python3
"""Local, history-free recovery bundles. Never modifies the source Git index/refs.

Capture before archive, record the receipt in the release note, and compare the
working tree again before upload. A post-release capture is recovery evidence, not historical
build provenance. Secrets/signing inputs and ignored files are never a backup API.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
from datetime import datetime, timezone

MAX_BYTES = 256 * 1024 * 1024
MAX_FILE_BYTES = 32 * 1024 * 1024


def run(args, cwd):
    # Do not inherit alternate indexes, Git directories, identities or hooks.
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f"{args[0]} {args[1]} failed (exit {result.returncode}); output withheld")
    return result.stdout


def selected_paths(root):
    if run(["git", "ls-files", "-u"], root):
        raise ValueError("Resolve merge conflicts before capturing source")
    values = run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], root)
    return sorted(set(p.decode("utf-8") for p in values.split(b"\0") if p))


def file_data(root, name):
    path = root / name
    if Path(name).is_absolute() or ".." in Path(name).parts or ".git" in Path(name).parts:
        raise ValueError("Unsafe source path")
    # Reject symlinks in every component, even a tracked directory replaced by a link.
    for parent in [path, *path.parents]:
        if parent == root:
            break
        if parent.is_symlink():
            raise ValueError("Symlinks need an explicit recovery policy")
    if not path.exists():
        return None  # Working-tree deletion, not an instruction to restore HEAD.
    if not path.is_file():
        raise ValueError("Submodules and non-file entries need an explicit recovery policy")
    lower = path.name.lower()
    if (lower == "cert.json" or lower == ".env"
            or (lower.startswith(".env.") and not lower.endswith((".example", ".sample")))
            or path.suffix.lower() in {".p8", ".p12", ".pem", ".key", ".mobileprovision"}):
        raise ValueError("Credential-shaped file is Git-visible; capture refused")
    with path.open("rb") as stream:
        content = stream.read(MAX_FILE_BYTES + 1)
    if len(content) > MAX_FILE_BYTES:
        raise ValueError("Source file exceeds bounded recovery size")
    mode = "100755" if path.stat().st_mode & stat.S_IXUSR else "100644"
    return content, mode


def manifest(root, destination=None):
    files, total = [], 0
    for name in selected_paths(root):
        data = file_data(root, name)
        if data is None:
            continue
        content, mode = data
        total += len(content)
        if total > MAX_BYTES:
            raise ValueError("Source exceeds the 256 MiB recovery budget")
        files.append({"path": name, "mode": mode, "bytes": len(content),
                      "sha256": hashlib.sha256(content).hexdigest()})
        if destination:
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            target.chmod(0o755 if mode == "100755" else 0o644)
    if not files:
        raise ValueError("No source files selected")
    return files


def digest(files):
    return hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def verified_public_checksum(root, finding):
    """Prove a copied file's checksum; never suppress a file or arbitrary key."""
    dashboard = "owner-tools/testflight-usage-dashboard/protected-runtime.json"
    source_receipts = {
        "docs/testing/fotty30-broadcast-first/excluded-baseline.json",
        "docs/testing/fotty25-remaining-2026-10-29/protected-inputs.json",
        "docs/testing/product-return-discovery-2026-10-29/protected-inputs.json",
        "docs/testing/fotty185-ipad-2026-10-29/source-hashes.json",
        "docs/testing/fotty25-remaining-2026-10-29/source-hashes.json",
    }
    try:
        path = Path(finding["File"])
        if not path.is_absolute():
            path = root / path
        manifest_name = path.resolve().relative_to(root.resolve()).as_posix()
        if manifest_name not in source_receipts and manifest_name != dashboard:
            return False
        line = finding["StartLine"]
        if (finding["RuleID"] != "generic-api-key" or type(line) is not int
                or line < 1 or finding["EndLine"] != line):
            return False
        content, _ = file_data(root, manifest_name)
        text = content.decode("utf-8")
        pattern = (r'"(src/charting/SankeyRenderer\.jsx)"\s*:\s*"([a-f0-9]{64})"\s*,?'
                   if manifest_name == dashboard else
                   r'"(Fotty(?:Tests)?/[A-Za-z0-9_./ -]+\.swift)"\s*:\s*"([a-f0-9]{64})"\s*,?')
        match = re.fullmatch(pattern, text.splitlines()[line - 1].strip())
        if not match:
            return False
        key, checksum = match.groups()
        # Exactly one mapping must carry this exact digest. Other findings on
        # the same file still go through the unchanged default scanner.
        matches = []
        def visit(value):
            if isinstance(value, dict):
                if key in value:
                    matches.append(value[key])
                for child in value.values():
                    visit(child)
            elif isinstance(value, list):
                for child in value:
                    visit(child)
        visit(json.loads(text))
        if matches != [checksum]:
            return False
        target = "owner-tools/testflight-usage-dashboard/" + key if manifest_name == dashboard else key
        original, _ = file_data(root, target)
        return hashlib.sha256(original).hexdigest() == checksum
    except (ValueError, OSError, KeyError, IndexError, TypeError, AttributeError):
        return False


def secret_scan(root):
    # Always scan the actual copied tree, including files originally tracked but
    # now ignored. Do not accept repository-provided scanner overrides.
    env = {k: v for k, v in os.environ.items() if not k.startswith("GITLEAKS_")}
    result = subprocess.run(["gitleaks", "dir", str(root), "--redact", "--no-banner",
                             "--report-format", "json", "--report-path", "-"],
                            cwd=root.parent, env=env, capture_output=True)
    if result.returncode:
        # Default rules still scan every copied file. Accept only a content-proven
        # public checksum; do not load a repo allowlist, print findings or skip files.
        try:
            findings = json.loads(result.stdout)
            if (result.returncode == 1 and isinstance(findings, list) and findings
                    and all(verified_public_checksum(root, finding) for finding in findings)):
                return
        except (ValueError, TypeError):
            pass
        raise ValueError("Secret scan failed; no recovery bundle was published (output withheld)")


def verify(folder):
    receipt = json.loads((folder / "receipt.json").read_text())
    bundle = folder / "source.bundle"
    if hashlib.sha256(bundle.read_bytes()).hexdigest() != receipt["bundleSHA256"]:
        raise ValueError("Bundle checksum mismatch")
    with tempfile.TemporaryDirectory(prefix="FottySourceVerify-") as work:
        checkout = Path(work) / "checkout"
        run(["git", "clone", "--quiet", str(bundle.resolve()), str(checkout)], Path(work))
        if run(["git", "rev-list", "--count", "HEAD"], checkout).strip() != b"1":
            raise ValueError("Recovery bundle must not contain old ancestry")
        if run(["git", "rev-parse", "HEAD"], checkout).decode().strip() != receipt["commit"]:
            raise ValueError("Commit mismatch")
        restored = manifest(checkout)
        if restored != receipt["files"] or digest(restored) != receipt["sourceSHA256"]:
            raise ValueError("Restored source does not match receipt")
        secret_scan(checkout)
    return receipt


def capture(root, output, label, purpose):
    root, output = root.resolve(), output.resolve()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,70}", label):
        raise ValueError("Use a short version/build label")
    if output.exists():
        raise ValueError("Destination exists; never overwrite a recovery snapshot")
    if output == root or root in output.parents:
        if root / "backups" / "release-source" not in output.parents:
            raise ValueError("In-repo snapshots belong only under ignored backups/release-source")
        run(["git", "check-ignore", "--quiet", str(output)], root)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".FottySourceCapture-", dir=output.parent) as work:
        staging = Path(work) / "tree"
        staging.mkdir()
        files = manifest(root, staging)
        if files != manifest(root):
            raise ValueError("Source changed during capture; retry when editing stops")
        secret_scan(staging)
        run(["git", "init", "--quiet", "-b", f"codex/recovery-{label}"], staging)
        run(["git", "config", "user.name", "Fotty Local Recovery"], staging)
        run(["git", "config", "user.email", "recovery@example.invalid"], staging)
        run(["git", "config", "commit.gpgSign", "false"], staging)
        run(["git", "config", "core.hooksPath", "/dev/null"], staging)
        run(["git", "add", "--force", "--all"], staging)
        run(["git", "commit", "--quiet", "-m", f"Local source recovery {label}"], staging)
        package = Path(work) / "package"
        package.mkdir()
        bundle = package / "source.bundle"
        run(["git", "bundle", "create", str(bundle), "HEAD", f"refs/heads/codex/recovery-{label}"], staging)
        receipt = {"schemaVersion": 1, "label": label, "purpose": purpose,
                   "capturedAt": datetime.now(timezone.utc).isoformat(),
                   "provenance": "working-tree capture; not proof of a previously built binary",
                   "commit": run(["git", "rev-parse", "HEAD"], staging).decode().strip(),
                   "sourceSHA256": digest(files),
                   "bundleSHA256": hashlib.sha256(bundle.read_bytes()).hexdigest(),
                   "files": files}
        (package / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        verify(package)
        if files != manifest(root):
            raise ValueError("Source changed during verification; capture not published")
        package.rename(output)
    return receipt


def compare(root, folder):
    receipt = verify(folder)
    current = manifest(root.resolve())
    if current != receipt["files"] or digest(current) != receipt["sourceSHA256"]:
        raise ValueError("Working tree differs from recovery receipt; review changes and capture a new candidate")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("capture")
    create.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    create.add_argument("--output", type=Path, required=True)
    create.add_argument("--label", required=True)
    create.add_argument("--purpose", choices=["post-release-recovery", "pre-build"], required=True)
    check = commands.add_parser("verify")
    check.add_argument("folder", type=Path)
    match = commands.add_parser("compare")
    match.add_argument("folder", type=Path)
    match.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        if args.command == "capture":
            receipt = capture(args.root, args.output, args.label, args.purpose)
        elif args.command == "compare":
            receipt = compare(args.root, args.folder)
        else:
            receipt = verify(args.folder)
        print(json.dumps({k: receipt[k] for k in ("label", "purpose", "commit", "sourceSHA256", "bundleSHA256")}))
        print(f"Verified {len(receipt['files'])} files; one history-free commit; no remote changes.")
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        parser.exit(1, f"Recovery failed: {error}\n")


if __name__ == "__main__":
    main()
