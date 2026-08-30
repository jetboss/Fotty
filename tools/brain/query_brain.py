#!/usr/bin/env python3
"""Retrieve (and optionally synthesize) answers from tools/brain/.cache/knowledge.jsonl. Stdlib only."""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


def ollama_embed(host: str, model: str, prompt: str, timeout: int) -> list[float]:
    url = host.rstrip("/") + "/api/embeddings"
    body = json.dumps({"model": model, "prompt": prompt}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.load(resp)
    emb = data.get("embedding")
    if not isinstance(emb, list):
        raise SystemExit(f"Unexpected embeddings response: {data!r}")
    return [float(x) for x in emb]


def cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0.0 or nb == 0.0:
        return 0.0
    return dot / (na * nb)


def ollama_chat(host: str, model: str, system: str, user: str, timeout: int, bearer: str) -> str:
    url = host.rstrip("/") + "/v1/chat/completions"
    body = json.dumps(
        {
            "model": model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "stream": False,
        }
    ).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if bearer:
        headers["Authorization"] = f"Bearer {bearer}"
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"Chat HTTP {e.code}: {e.read().decode('utf-8', errors='replace')}") from e
    try:
        return str(data["choices"][0]["message"]["content"])
    except (KeyError, IndexError, TypeError):
        raise SystemExit(f"Unexpected chat response: {data!r}")


def load_records(path: Path) -> list[dict]:
    rows: list[dict] = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def main() -> None:
    ap = argparse.ArgumentParser(description="Query local brain index (semantic retrieval)")
    ap.add_argument("question", help="Natural-language question")
    ap.add_argument("--root", type=Path, default=Path.cwd())
    ap.add_argument(
        "--index",
        type=Path,
        default=None,
        help="Path to knowledge.jsonl (default: tools/brain/.cache/knowledge.jsonl)",
    )
    ap.add_argument(
        "--ollama-host",
        default=os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434"),
    )
    ap.add_argument("--embed-model", default="nomic-embed-text")
    ap.add_argument("--top", type=int, default=5)
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument(
        "--synthesize",
        action="store_true",
        help="Ask chat model to answer using only retrieved chunks (still verify in repo).",
    )
    ap.add_argument("--chat-model", default=os.environ.get("OV_AI_CHAT_MODEL", "qwen2.5:3b"))
    ap.add_argument(
        "--bearer",
        default=os.environ.get("OV_AI_BEARER", "ollama"),
        help="Bearer token for OpenAI-compatible /v1 (Ollama often ignores value).",
    )
    args = ap.parse_args()
    root = args.root.resolve()
    idx = args.index or (root / "tools" / "brain" / ".cache" / "knowledge.jsonl")
    if not idx.is_file():
        print(f"Missing index at {idx}; run tools/private-kb-sync.sh first.", file=sys.stderr)
        sys.exit(1)

    records = load_records(idx)
    q_emb = ollama_embed(args.ollama_host, args.embed_model, args.question, args.timeout)
    scored: list[tuple[float, dict]] = []
    for rec in records:
        emb = rec.get("embedding")
        if not isinstance(emb, list):
            continue
        f = [float(x) for x in emb]
        scored.append((cosine(q_emb, f), rec))
    scored.sort(key=lambda x: x[0], reverse=True)
    top = scored[: max(1, args.top)]

    out_lines: list[str] = []
    for rank, (score, rec) in enumerate(top, start=1):
        src = rec.get("source", "?")
        chunk_i = rec.get("chunk_index", "?")
        text = rec.get("text", "")
        out_lines.append(
            f"--- Hit #{rank} score={score:.4f} source={src} chunk={chunk_i} ---\n{text}\n"
        )
    context = "\n".join(out_lines)
    print(context)

    if args.synthesize:
        system = (
            "You answer using ONLY the CONTEXT below. If the context is insufficient, "
            "say what is missing. Cite sources by their path when possible."
        )
        user = f"QUESTION:\n{args.question}\n\nCONTEXT:\n{context}"
        ans = ollama_chat(
            args.ollama_host,
            args.chat_model,
            system,
            user,
            args.timeout,
            args.bearer.strip(),
        )
        print("\n=== Synthesized (verify in git) ===\n")
        print(ans)


if __name__ == "__main__":
    main()
