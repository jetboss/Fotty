#!/usr/bin/env python3
"""Offline, bounded project-memory retrieval and defensive sharing export."""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import signal
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
SEARCH_FILES = (
    "docs/notebooklm/Current-State.md", "docs/notebooklm/Project-Memory.md",
    "docs/notebooklm/Decisions-Log.md", "docs/notebooklm/Architecture-Map.md",
    "docs/notebooklm/Risks.md", "docs/notebooklm/QA-Playbook.md",
    "docs/notebooklm/Workflow.md", "agent/AGENT-START.md", "agent/OPERATOR.md",
)
EXPORT_FILES = SEARCH_FILES + (
    "IOS_MANUAL_DEPLOY.md", "MAC_CATALYST_TESTING.md", "TESTFLIGHT_READINESS.md",
    "AGENTS.md", "agent/playbooks/brain-ops.md", "agent/playbooks/playback.md",
)
STOP = set("a an and are as at be been before by can completed could current describe do "
           "does for from have how i in into investigate is it its local me my of on or "
           "our please prior project return risks should some suggest task that the their "
           "them then these they this to using verification was we what when where which "
           "while why will with work would you your fotty checks files likely decisions".split())
URL = re.compile(r"https?://[^\s<>\"'`]+", re.I)
KEY = r"(?:api[_-]?key|api[_-]?password|access[_-]?token|refresh[_-]?token|client[_-]?secret|private[_-]?key|password|passwd|secret|token|signing[_-]?key)"
ASSIGNMENT = re.compile(
    rf"(?P<prefix>(?<![\w-])[\"'`]?{KEY}[\"'`]?\s*[:=]\s*)"
    r"(?P<value>\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|`[^`]*`|\[REDACTED\]|[^\s,;}&<]+)", re.I)
BEARER = re.compile(r"\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+", re.I)
PEM = re.compile(r"-----BEGIN [^-\n]*PRIVATE KEY-----[\s\S]*?-----END [^-\n]*PRIVATE KEY-----")
TOKEN = re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(?:proj-)?[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{15,}|AKIA[A-Z0-9]{16}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})\b")


def redact(text: str) -> str:
    text = PEM.sub("[REDACTED PRIVATE KEY]", text)
    text = re.sub(rf"(?im)^(?P<indent>[ \t]*)(?P<key>[\"']?{KEY}[\"']?\s*:)\s*[|>][-+]?[^\n]*\n(?:[ \t]+[^\n]*\n|\n)*",
                  lambda m: m["indent"] + m["key"] + " [REDACTED]\n", text)
    # YAML permits unquoted multi-word passwords; redact the whole scalar line.
    text = re.sub(rf"(?im)^(?P<prefix>[ \t-]*[\"']?{KEY}[\"']?\s*:[ \t]*)[^\n]+",
                  lambda m: m["prefix"] + "[REDACTED]", text)
    text = ASSIGNMENT.sub(lambda m: m["prefix"] + "[REDACTED]", text)
    text = BEARER.sub(lambda m: m[1] + " [REDACTED]", text)
    text = TOKEN.sub("[REDACTED TOKEN]", text)

    def safe_url(match: re.Match) -> str:
        try:
            parsed = urlsplit(match[0])
            host = parsed.hostname
            if not host:
                return "[REDACTED URL]"
            if ":" in host:
                host = "[" + host + "]"
            port = ":" + str(parsed.port) if parsed.port else ""
            return parsed.scheme + "://" + host + port + "/[URL_REDACTED]"
        except ValueError:
            return "[REDACTED URL]"

    return URL.sub(safe_url, text)


def privacy_issues(text: str) -> list[str]:
    """Return categories only, never a suspected credential in diagnostics."""
    issues = []
    if re.search(r"-----BEGIN [^-\n]*(?:PRIVATE KEY|CERTIFICATE)-----", text):
        issues.append("unreviewed signing material")
    if TOKEN.search(text):
        issues.append("credential-shaped token")
    if any(m["value"].strip("\"'`") != "[REDACTED]" for m in ASSIGNMENT.finditer(text)):
        issues.append("unredacted credential assignment")
    if BEARER.search(text):
        issues.append("authorization value")
    for match in URL.finditer(text):
        try:
            if urlsplit(match[0]).username is not None:
                issues.append("URL credentials")
        except ValueError:
            issues.append("malformed URL")
    return sorted(set(issues))


def terms_for(question: str) -> set[str]:
    question = re.sub(r"picture[\s-]+in[\s-]+picture", "pip", question.lower())
    for phrase, acronym in (("champions league", "ucl"), ("fantasy premier league", "fpl"),
                            ("caribbean premier league", "cpl")):
        question = question.replace(phrase, phrase + " " + acronym)
    return {w for w in re.findall(r"[a-z0-9]+", question) if len(w) >= 3 and w not in STOP}


@dataclass
class Section:
    path: str
    line: int
    title: str
    body: str
    date: str


def sections(root: Path) -> list[Section]:
    result = []
    for name in SEARCH_FILES:
        path = root / name
        if not path.is_file():
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        start, title, date, body, fenced = 1, name, "", [], False
        parent_dates = {}
        for number, line in enumerate(lines, 1):
            if line.startswith("```"):
                fenced = not fenced
            if not fenced and re.match(r"^#{1,4} ", line):
                if body:
                    result.append(Section(name, start, title, "\n".join(body), date))
                start, title, body = number, line.lstrip("# "), []
                level = len(line) - len(line.lstrip("#"))
                parent_dates = {k: v for k, v in parent_dates.items() if k < level}
                found = re.search(r"20\d\d-\d\d-\d\d", title)
                date = found[0] if found else parent_dates.get(max(parent_dates, default=0), "")
                parent_dates[level] = date
            else:
                body.append(line)
        if body:
            result.append(Section(name, start, title, "\n".join(body), date))
    return result


def search(root: Path, question: str, budget: int = 6000) -> str:
    if len(question) > 16000:
        raise ValueError("Query exceeds 16,000 characters; give the focused task, not a transcript.")
    terms, ranked = terms_for(question), []
    for section in sections(root):
        title_terms, body_terms = terms_for(section.title), terms_for(section.body)
        overlap = terms & (title_terms | body_terms)
        if not overlap:
            continue
        score = 8 * len(terms & title_terms) + 3 * len(overlap) / max(1, len(terms))
        if section.path.endswith("Current-State.md"):
            score += 100  # Explicit current authority precedes equally relevant history.
        if section.path.endswith("Decisions-Log.md"):
            score -= 0.5
        if re.search(r"\b(retired|rejected|superseded)\b", section.title, re.I):
            score -= 1
        if not terms & {"release", "build", "testflight", "deploy", "invite"} and re.search(
                r"\b(release|promote|invite|invitation)\b", section.title, re.I):
            score -= 12
        ranked.append((score, section.date, section))
    ranked.sort(key=lambda item: (item[0], item[1]), reverse=True)
    if not ranked:
        return "No relevant memory sections found. Fallback: read docs/notebooklm/Current-State.md, then inspect the task's current source.\n"
    parts = ["Local memory matches (retrieval evidence, not current-state verification):\n"]
    used = len(parts[0])
    current_seen = False
    selected_sections = []
    for _, _, section in ranked:
        if section.path.endswith("Current-State.md"):
            if current_seen:
                continue
            current_seen = True
        selected_sections.append(section)
        if len(selected_sections) == 5:
            break
    for section in selected_sections:
        kind = "CURRENT SUMMARY" if section.path.endswith("Current-State.md") else "REFERENCE / DATED HISTORY; verify applicability"
        prefix = f"\n{section.path}:{section.line} — {section.title}\n[{kind}; date: {section.date or 'see source'}]\n"
        lines = section.body.splitlines()
        best = sorted(range(len(lines)), key=lambda i: len(terms & terms_for(lines[i])), reverse=True)[:3]
        # Never omit a rejection/supersession caveat merely because its line lacks the search term.
        caveats = [line for line in lines if re.search(r"\b(rejected|superseded|must not be promoted)\b", line, re.I)]
        selected = sorted({j for i in best for j in range(max(0, i - 1), min(len(lines), i + 2))})
        snippet = "\n".join(lines[i][:550] for i in selected)[:900]
        warning = "\nRecorded caveat: " + " ".join(caveats)[:450] if caveats else ""
        block = redact(prefix + snippet + warning) + "\n[Open the source section for full context.]\n"
        if used + len(block) > budget:
            break
        parts.append(block)
        used += len(block)
    return "".join(parts)


def source_digest(root: Path, names=EXPORT_FILES) -> str:
    digest = hashlib.sha256()
    for name in names:
        digest.update(name.encode("utf-8") + b"\0")
        digest.update((root / name).read_bytes())
    return digest.hexdigest()


def export_bundle(root: Path, output: Path, names=EXPORT_FILES) -> None:
    digest = source_digest(root, names)
    chunks = [(name, (root / name).read_text(encoding="utf-8")) for name in names]
    header = ("# Fotty NotebookLM Master Source\n\n"
              f"Generated: {datetime.now(timezone.utc).isoformat()}\nSource digest: {digest}\n\n"
              "Defensively redacted local export. Review before sharing; pattern checks are not a privacy guarantee.\n"
              "Dated release/history entries are evidence from their recorded time, not live deployment authority.\n")
    text = redact(header + "".join(f"\n\n# Source: {name}\n\n{body}" for name, body in chunks))
    problems = privacy_issues(text)
    if problems:
        raise ValueError("Export blocked: " + ", ".join(problems) + ". Previous bundle retained; review source locally.")
    if source_digest(root, names) != digest:
        raise ValueError("Memory sources changed during export; previous bundle retained. Retry after edits finish.")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output.parent,
                                         prefix=".fotty-memory-", delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def health(root: Path, require_export: bool = False) -> list[str]:
    failures = []
    for name in EXPORT_FILES:
        if not (root / name).is_file() or (root / name).stat().st_size == 0:
            failures.append("Missing/empty source: " + name)
    current = root / "docs/notebooklm/Current-State.md"
    if current.is_file():
        body = current.read_text(encoding="utf-8")
        if len(body.encode("utf-8")) > 8000:
            failures.append("Current-State.md exceeds the 8 KB onboarding budget; move history to topic references.")
        for target in re.findall(r"`((?:docs|agent|tools)/[^`\s]+)`", body):
            if not (root / target).exists():
                failures.append("Broken current-state reference: " + target)
    output = root / "docs/notebooklm/Fotty-NotebookLM-Source.md"
    if require_export and not failures:
        if not output.is_file():
            failures.append("Sharing export is missing; run tools/notebooklm-refresh.sh.")
        else:
            text = output.read_text(encoding="utf-8")
            if f"Source digest: {source_digest(root)}" not in text:
                failures.append("Sharing export is stale; run tools/notebooklm-refresh.sh.")
            if privacy_issues(text):
                failures.append("Sharing export failed privacy-pattern checks; review locally before sharing.")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("search").add_argument("question", nargs="+")
    sub.add_parser("export").add_argument("--copy-path", action="store_true")
    sub.add_parser("health").add_argument("--export", dest="check_export", action="store_true")
    args = parser.parse_args()
    previous_handlers = {}

    def interrupted(signum, _frame):
        # Unwind export_bundle's finally block instead of abandoning its temporary file.
        raise SystemExit(128 + signum)

    for signum in (signal.SIGTERM, signal.SIGHUP):
        previous_handlers[signum] = signal.signal(signum, interrupted)
    try:
        if args.command == "search":
            print(search(args.root, " ".join(args.question)), end="")
        elif args.command == "export":
            output = args.root / "docs/notebooklm/Fotty-NotebookLM-Source.md"
            export_bundle(args.root, output)
            print("Local export refreshed atomically; privacy-pattern checks passed. Review before sharing.")
            if args.copy_path:
                subprocess.run(["pbcopy"], input=str(output), text=True, check=True)
                print("Export path copied to clipboard (explicit request).")
        else:
            failures = health(args.root, args.check_export)
            if failures:
                print("\n".join(failures), file=sys.stderr)
                return 1
            print("Memory source presence, current-summary size and reference checks passed.")
            print("Export digest/privacy-pattern checks passed." if args.check_export else
                  "Export freshness/privacy not checked (use --export); runtime claims are not verified.")
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
