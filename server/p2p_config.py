"""Shared P2P broker configuration — never hardcode API passwords in source."""

from __future__ import annotations

import os
import sys


def get_p2p_api_password() -> str:
    return os.getenv("P2P_API_PASSWORD", "").strip()


def is_production_runtime() -> bool:
    env = os.getenv("FOTTY_ENV", os.getenv("NODE_ENV", "")).strip().lower()
    return env in {"production", "prod"}


def require_p2p_api_password(context: str = "") -> str:
    value = get_p2p_api_password()
    if value:
        return value
    suffix = f" ({context})" if context else ""
    raise RuntimeError(
        f"P2P_API_PASSWORD is required{suffix}. "
        "Export it in your shell or add it to the service .env file."
    )


def require_p2p_api_password_or_exit(context: str = "broker startup") -> str:
    try:
        return require_p2p_api_password(context)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1) from exc
