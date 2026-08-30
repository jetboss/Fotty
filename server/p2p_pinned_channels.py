"""Merge operator-provided AceStream CIDs into the P2P /matches cache."""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any

_CID_RE = re.compile(r"^[a-f0-9]{40}$", re.IGNORECASE)
_DEFAULT_FILE = Path(__file__).resolve().parent / "p2p_pinned_channels.json"


def _pinned_channels_path() -> Path:
    raw = os.getenv("P2P_PINNED_CHANNELS_FILE", "").strip()
    return Path(raw) if raw else _DEFAULT_FILE


def load_pinned_channels() -> list[dict[str, Any]]:
    path = _pinned_channels_path()
    if not path.is_file():
        return []

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return []

    rows = payload.get("channels") if isinstance(payload, dict) else payload
    if not isinstance(rows, list):
        return []

    out: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        cid = str(row.get("cid") or row.get("infohash") or "").strip().lower()
        if not _CID_RE.match(cid):
            continue
        title = str(row.get("title") or row.get("fottyName") or row.get("name") or "Pinned channel").strip()
        out.append(
            {
                "title": title,
                "cid": cid,
                "availability": float(row.get("availability") or 1.0),
                "bitrate_kbps": int(row.get("bitrate_kbps") or 0),
                "categories": row.get("categories") or ["sport"],
                "source": "pinned-catalog",
            }
        )
    return out


def merge_pinned_channels(channels: list[dict[str, Any]]) -> list[dict[str, Any]]:
    pinned = load_pinned_channels()
    if not pinned:
        return channels

    seen = {str(channel.get("cid") or "").lower() for channel in channels if channel.get("cid")}
    merged = list(channels)
    for channel in pinned:
        cid = channel["cid"]
        if cid in seen:
            continue
        merged.append(channel)
        seen.add(cid)
    merged.sort(key=lambda channel: float(channel.get("availability") or 0.0), reverse=True)
    return merged
