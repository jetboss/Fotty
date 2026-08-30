#!/usr/bin/env python3
"""Build a local JSONL embedding index for docs (Ollama /api/embeddings). Stdlib only."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def chunk_text(text: str, size: int, overlap: int) -> list[str]:
    text = text.strip()
    if not text:
        return []
    chunks: list[str] = []
    start = 0
    n = len(text)
    while start < n:
        end = min(start + size, n)
        piece = text[start:end].strip()
        if piece:
            chunks.append(piece)
        if end >= n:
            break
        start = max(0, end - overlap)
    return chunks


def ollama_embed(host: str, model: str, prompt: str, timeout: int) -> list[float]:
    url = host.rstrip("/") + "/api/embeddings"
    body = json.dumps({"model": model, "prompt": prompt}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"Ollama HTTP {e.code}: {e.read().decode('utf-8', errors='replace')}") from e
    except urllib.error.URLError as e:
        raise SystemExit(f"Cannot reach Ollama at {url}: {e}") from e
    emb = data.get("embedding")
    if not isinstance(emb, list):
        raise SystemExit(f"Unexpected embeddings response: {data!r}")
    return [float(x) for x in emb]


def collect_sources(root: Path) -> list[tuple[str, Path]]:
    pairs: list[tuple[str, Path]] = []
    generated_sources = [
        root / "docs" / "notebooklm" / "Fotty-NotebookLM-Source.md",
        root / "docs" / "notebooklm" / "NotebookLM-Source.md",
    ]
    nb = next((p for p in generated_sources if p.is_file() and p.stat().st_size > 0), None)
    if nb is not None:
        pairs.append((str(nb.relative_to(root)), nb))
    else:
        d = root / "docs" / "notebooklm"
        if d.is_dir():
            for p in sorted(d.glob("*.md")):
                if p.name == "NotebookLM-Source.md":
                    continue
                pairs.append((str(p.relative_to(root)), p))
    ag = root / "agent"
    if ag.is_dir():
        for p in sorted(ag.glob("*.md")):
            pairs.append((str(p.relative_to(root)), p))
    playbooks = root / "agent" / "playbooks"
    if playbooks.is_dir():
        for p in sorted(playbooks.glob("*.md")):
            pairs.append((str(p.relative_to(root)), p))
    crs = root / ".cursorrules"
    if crs.is_file():
        pairs.append((".cursorrules", crs))
    cursor_rules = root / ".cursor" / "rules"
    if cursor_rules.is_dir():
        for p in sorted(cursor_rules.glob("*.mdc")):
            pairs.append((str(p.relative_to(root)), p))
    root_agents = root / "AGENTS.md"
    if root_agents.is_file():
        pairs.append(("AGENTS.md", root_agents))
    return pairs


def main() -> None:
    ap = argparse.ArgumentParser(description="Embed docs/notebooklm into tools/brain/.cache")
    ap.add_argument("--root", type=Path, default=Path.cwd())
    ap.add_argument(
        "--ollama-host",
        default=os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434"),
        help="Ollama base URL (default $OLLAMA_HOST or http://127.0.0.1:11434)",
    )
    ap.add_argument("--model", default="nomic-embed-text")
    ap.add_argument("--chunk-size", type=int, default=1200)
    ap.add_argument("--overlap", type=int, default=200)
    ap.add_argument("--sleep", type=float, default=0.0, help="Seconds between embedding requests")
    ap.add_argument("--timeout", type=int, default=120)
    args = ap.parse_args()
    root = args.root.resolve()
    cache_dir = root / "tools" / "brain" / ".cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    out_path = cache_dir / "knowledge.jsonl"

    sources = collect_sources(root)
    if not sources:
        print("No source files found; run ./tools/notebooklm-refresh.sh first.", file=sys.stderr)
        sys.exit(1)

    total = 0
    with out_path.open("w", encoding="utf-8") as out:
        for rel, path in sources:
            text = path.read_text(encoding="utf-8", errors="replace")
            for i, chunk in enumerate(chunk_text(text, args.chunk_size, args.overlap)):
                if args.sleep > 0 and total > 0:
                    time.sleep(args.sleep)
                emb = ollama_embed(args.ollama_host, args.model, chunk, args.timeout)
                rec = {"source": rel, "chunk_index": i, "text": chunk, "embedding": emb}
                out.write(json.dumps(rec, ensure_ascii=False) + "\n")
                total += 1
                print(f"embedded {rel} #{i} ({len(chunk)} chars)", file=sys.stderr)

    print(f"Wrote {total} vectors to {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
