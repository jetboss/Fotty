from __future__ import annotations

import json
import logging
import os
import base64
import hashlib
import hmac
import threading
import time
import uuid
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import parse_qs, quote, urlparse, urlunparse, unquote

import requests
from flask import Flask, Response, jsonify, request, stream_with_context
try:
    import redis as redis_lib
except ImportError:  # pragma: no cover - optional runtime dependency for local tests
    redis_lib = None

from p2p_proxy_core import (
    absolute_url,
    classify_manifest_failure,
    classify_segment_failure,
    is_segment_line,
    parse_manifest_lines,
    rewrite_manifest,
    extract_media_sequence,
)
from p2p_config import get_p2p_api_password, is_production_runtime
from p2p_pinned_channels import merge_pinned_channels
from p2p_scraper_queries import build_scraper_search_queries, extra_sport_queries


logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

app = Flask(__name__)

_CORS_PATH_PREFIXES = ("/ace/proxy", "/proxy/acestream")


@app.after_request
def _apply_browser_cors(response: Response) -> Response:
    path = request.path or ""
    if any(path.startswith(prefix) for prefix in _CORS_PATH_PREFIXES):
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Methods"] = "GET, HEAD, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = (
            "Range, Accept, Authorization, api-password, Content-Type"
        )
        response.headers["Access-Control-Expose-Headers"] = (
            "Content-Length, Content-Range, Accept-Ranges"
        )
    return response


@app.before_request
def _handle_browser_cors_preflight() -> Optional[Response]:
    if request.method != "OPTIONS":
        return None
    path = request.path or ""
    if not any(path.startswith(prefix) for prefix in _CORS_PATH_PREFIXES):
        return None
    return Response("", status=204)


UPSTREAM_BASE_URL = os.getenv("P2P_UPSTREAM_BASE_URL", "http://127.0.0.1:6878").rstrip("/")
UPSTREAM_KIND = os.getenv("P2P_UPSTREAM_KIND", "engine").strip().lower()
EXPECTED_API_PASSWORD = get_p2p_api_password()
if not EXPECTED_API_PASSWORD:
    if is_production_runtime():
        raise RuntimeError("P2P_API_PASSWORD is required in production.")
    log.warning("P2P_API_PASSWORD is unset — broker password auth is disabled until configured.")
PUBLIC_STREAM_TOKEN_SECRET = (
    os.getenv("P2P_PUBLIC_STREAM_TOKEN_SECRET", "").strip() or EXPECTED_API_PASSWORD
)
PUBLIC_STREAM_TOKEN_TTL_SECONDS = int(os.getenv("P2P_PUBLIC_STREAM_TOKEN_TTL_SECONDS", "1800"))
EXPECTED_SERVICE_TOKEN_ID = os.getenv("P2P_CF_ACCESS_CLIENT_ID", "").strip()
EXPECTED_SERVICE_TOKEN_SECRET = os.getenv("P2P_CF_ACCESS_CLIENT_SECRET", "").strip()
PORT = int(os.getenv("PORT", "8006"))

MANIFEST_TIMEOUT_SECONDS = float(os.getenv("P2P_MANIFEST_TIMEOUT_SECONDS", "20"))
ENGINE_SESSION_CREATE_TIMEOUT_SECONDS = float(os.getenv("P2P_ENGINE_SESSION_CREATE_TIMEOUT_SECONDS", "20"))
SEGMENT_TIMEOUT_SECONDS = float(os.getenv("P2P_SEGMENT_TIMEOUT_SECONDS", "15"))
ENGINE_WARMUP_TIMEOUT_SECONDS = float(os.getenv("P2P_ENGINE_WARMUP_TIMEOUT_SECONDS", "150"))
ENGINE_WARMUP_POLL_SECONDS = float(os.getenv("P2P_ENGINE_WARMUP_POLL_SECONDS", "3"))
MIN_SEGMENT_BYTES = int(os.getenv("P2P_MIN_SEGMENT_BYTES", "512"))
MAX_SEGMENTS_TO_VALIDATE = int(os.getenv("P2P_MAX_SEGMENTS_TO_VALIDATE", "12"))

BROKER_SESSION_TTL_SECONDS = int(os.getenv("P2P_BROKER_SESSION_TTL_SECONDS", "600"))
BROKER_ACTIVE_STATES = {"starting", "warming", "retrying", "refreshing"}
BROKER_REFRESH_LEEWAY_SECONDS = int(os.getenv("P2P_BROKER_REFRESH_LEEWAY_SECONDS", "20"))
BROKER_RETRY_COOLDOWN_SECONDS = float(os.getenv("P2P_BROKER_RETRY_COOLDOWN_SECONDS", "12"))
BROKER_MAX_RETRYABLE_PREPARE_ATTEMPTS = int(os.getenv("P2P_BROKER_MAX_RETRYABLE_PREPARE_ATTEMPTS", "3"))
BROKER_MANIFEST_FRESH_SECONDS = int(os.getenv("P2P_BROKER_MANIFEST_FRESH_SECONDS", "3"))
FROZEN_SEQUENCE_RESTART_SECONDS = int(os.getenv("P2P_FROZEN_SEQUENCE_RESTART_SECONDS", "15"))
BROKER_MANIFEST_STALE_GRACE_SECONDS = int(os.getenv("P2P_BROKER_MANIFEST_STALE_GRACE_SECONDS", "15"))
BROKER_READY_REUSE_GRACE_SECONDS = int(os.getenv("P2P_BROKER_READY_REUSE_GRACE_SECONDS", "900"))
BROKER_EVENT_LIMIT = int(os.getenv("P2P_BROKER_EVENT_LIMIT", "80"))
REDIS_URL = os.getenv("P2P_REDIS_URL", os.getenv("REDIS_URL", "")).strip()
REDIS_KEY_PREFIX = os.getenv("P2P_REDIS_KEY_PREFIX", "fotty:p2p:broker").strip().rstrip(":")
REDIS_RECORD_TTL_SECONDS = int(
    os.getenv(
        "P2P_BROKER_REDIS_RECORD_TTL_SECONDS",
        str(int(max(BROKER_SESSION_TTL_SECONDS + 300, ENGINE_WARMUP_TIMEOUT_SECONDS + 300))),
    )
)
REDIS_HEALTH_TTL_SECONDS = int(os.getenv("P2P_BROKER_REDIS_HEALTH_TTL_SECONDS", str(7 * 24 * 60 * 60)))
REDIS_LOCK_TIMEOUT_SECONDS = float(os.getenv("P2P_BROKER_REDIS_LOCK_TIMEOUT_SECONDS", "20"))
REDIS_CONNECT_TIMEOUT_SECONDS = float(os.getenv("P2P_BROKER_REDIS_CONNECT_TIMEOUT_SECONDS", "2"))
REDIS_SOCKET_TIMEOUT_SECONDS = float(os.getenv("P2P_BROKER_REDIS_SOCKET_TIMEOUT_SECONDS", "2"))
PREPARE_INFLIGHT_STALE_SECONDS = float(
    os.getenv("P2P_BROKER_PREPARE_INFLIGHT_STALE_SECONDS", str(ENGINE_WARMUP_TIMEOUT_SECONDS + 45))
)
PREWARM_ENABLED = os.getenv("P2P_PREWARM_ENABLED", "").strip().lower() in {"1", "true", "yes", "on"}
PREWARM_CHANNEL_SOURCE_URL = os.getenv("P2P_PREWARM_CHANNEL_SOURCE_URL", "").strip()
PREWARM_BASE_URL = os.getenv("P2P_PREWARM_BASE_URL", "https://p2p.pixel-invoice.com").strip().rstrip("/")
PREWARM_INTERVAL_SECONDS = float(os.getenv("P2P_PREWARM_INTERVAL_SECONDS", "45"))
PREWARM_LIMIT = int(os.getenv("P2P_PREWARM_LIMIT", "6"))
PREWARM_CONCURRENT_LIMIT = int(os.getenv("P2P_PREWARM_CONCURRENT_LIMIT", "1"))
PREWARM_RUN_LOCK_SECONDS = float(os.getenv("P2P_PREWARM_RUN_LOCK_SECONDS", "30"))
PREWARM_MIN_AVAILABILITY = float(os.getenv("P2P_PREWARM_MIN_AVAILABILITY", "0.75"))
PREWARM_FAILED_COOLDOWN_SECONDS = float(os.getenv("P2P_PREWARM_FAILED_COOLDOWN_SECONDS", "300"))
PREWARM_EVIDENCE_MAX_AGE_SECONDS = float(
    os.getenv("P2P_PREWARM_EVIDENCE_MAX_AGE_SECONDS", str(6 * 60 * 60))
)
PREWARM_REQUEST_TIMEOUT_SECONDS = float(os.getenv("P2P_PREWARM_REQUEST_TIMEOUT_SECONDS", "8"))
PREWARM_PINNED_CIDS = {
    cid.strip()
    for cid in os.getenv("P2P_PREWARM_PINNED_CIDS", "").split(",")
    if cid.strip()
}

DASHBOARD_ENABLED = os.getenv("P2P_DASHBOARD_ENABLED", "1").strip().lower() in {"1", "true", "yes", "on"}
# If set, require ?key=<value> to open /dashboard (same-origin fetch still works in-page).
DASHBOARD_KEY = os.getenv("P2P_DASHBOARD_KEY", "").strip()

# Scraper state
SCRAPER_REFRESH_SECONDS = int(os.getenv("P2P_SCRAPER_REFRESH_SECONDS", "180"))
# Text searches merged into /matches (US/UK nets first, then PL/UCL/NBA). See p2p_scraper_queries.py.
SCRAPER_SPORT_CATEGORY_PAGE_SIZE = int(os.getenv("P2P_SCRAPER_SPORT_PAGE_SIZE", "240"))
SCRAPER_EXTRA_QUERY_PAGE_SIZE = int(os.getenv("P2P_SCRAPER_EXTRA_PAGE_SIZE", "140"))
SCRAPER_MAX_TEXT_QUERIES = int(os.getenv("P2P_SCRAPER_MAX_TEXT_QUERIES", "120"))
SCRAPER_EXTRA_TEXT_QUERIES = extra_sport_queries()
_scraper_lock = threading.Lock()
_scraper_matches_cache: List[Dict[str, Any]] = []
_scraper_last_updated: Optional[str] = None
_scraper_engine_version: Optional[str] = None
_scraper_last_refresh_error: Optional[str] = None


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def isoformat(value: Optional[datetime]) -> Optional[str]:
    if value is None:
        return None
    return value.astimezone(timezone.utc).isoformat()


def parse_datetime(value: Any) -> Optional[datetime]:
    if not value:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else parsed.replace(tzinfo=timezone.utc)


class ProxyMetrics:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.manifest_requests = 0
        self.manifest_failures = 0
        self.manifest_ttfb_ms = deque(maxlen=2000)
        self.segment_requests = 0
        self.segment_successes = 0
        self.segment_failures = 0
        self.cid_failures: Dict[str, Dict[str, object]] = {}

    def record_manifest(self, ttfb_ms: int, success: bool, cid: str, reason: str = "") -> None:
        with self._lock:
            self.manifest_requests += 1
            if success:
                self.manifest_ttfb_ms.append(ttfb_ms)
                return
            self.manifest_failures += 1
            entry = self.cid_failures.get(cid, {"count": 0, "reason": "", "updated_at": 0.0})
            entry["count"] = int(entry["count"]) + 1
            entry["reason"] = reason
            entry["updated_at"] = time.time()
            self.cid_failures[cid] = entry

    def record_segment(self, status_code: int) -> None:
        with self._lock:
            self.segment_requests += 1
            if 200 <= status_code <= 299:
                self.segment_successes += 1
            else:
                self.segment_failures += 1

    def snapshot(self) -> Dict[str, object]:
        with self._lock:
            ttfb_samples = list(self.manifest_ttfb_ms)
            segment_rate = (
                float(self.segment_successes) / float(self.segment_requests)
                if self.segment_requests > 0
                else 0.0
            )
            return {
                "manifest_requests": self.manifest_requests,
                "manifest_failures": self.manifest_failures,
                "manifest_ttfb_ms_avg": round(sum(ttfb_samples) / len(ttfb_samples), 2) if ttfb_samples else 0.0,
                "manifest_ttfb_ms_p50": percentile(ttfb_samples, 0.5),
                "manifest_ttfb_ms_p95": percentile(ttfb_samples, 0.95),
                "segment_requests": self.segment_requests,
                "segment_successes": self.segment_successes,
                "segment_failures": self.segment_failures,
                "segment_2xx_rate": round(segment_rate, 4),
                "cid_failures": self.cid_failures,
            }


metrics = ProxyMetrics()


def percentile(values: List[int], q: float) -> float:
    if not values:
        return 0.0
    sorted_values = sorted(values)
    index = int(round((len(sorted_values) - 1) * q))
    return float(sorted_values[max(0, min(index, len(sorted_values) - 1))])


def fail_manifest(cid: str, error_code: str, detail: str, started_at: float) -> Tuple[Response, int]:
    metrics.record_manifest(
        ttfb_ms=int((time.perf_counter() - started_at) * 1000),
        success=False,
        cid=cid,
        reason=error_code,
    )
    payload = {
        "error": "stream_unavailable",
        "code": error_code,
        "cid": cid,
        "detail": detail,
    }
    return jsonify(payload), 503


def request_api_password() -> str:
    api_password = request.args.get("api_password", "").strip()
    if api_password:
        return api_password

    header_password = request.headers.get("api-password", "").strip()
    if header_password:
        return header_password

    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        return auth_header.replace("Bearer ", "").strip()

    if request.method in {"POST", "PUT", "PATCH"}:
        payload = request.get_json(silent=True)
        if isinstance(payload, dict):
            body_password = str(payload.get("api_password") or "").strip()
            if body_password:
                return body_password

    return ""


def request_cid() -> str:
    return request.args.get("infohash", "").strip() or request.args.get("id", "").strip()


def request_stream_cid() -> str:
    return request_cid() or request.args.get("cid", "").strip()


def request_public_stream_token() -> str:
    return request.args.get("stream_token", "").strip() or request.args.get("p2p_token", "").strip()


def _base64url_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode((value + padding).encode("utf-8"))


def _base64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("utf-8").rstrip("=")


def verify_public_stream_token(token: str, cid: str) -> bool:
    if not token or not cid or not PUBLIC_STREAM_TOKEN_SECRET:
        return False

    try:
        body, supplied_sig = token.split(".", 1)
    except ValueError:
        return False

    expected_sig = _base64url_encode(
        hmac.new(PUBLIC_STREAM_TOKEN_SECRET.encode("utf-8"), body.encode("utf-8"), hashlib.sha256).digest()
    )
    if not hmac.compare_digest(supplied_sig, expected_sig):
        return False

    try:
        payload = json.loads(_base64url_decode(body).decode("utf-8"))
    except Exception:
        return False

    token_cid = str(payload.get("cid") or "").strip()
    try:
        exp = float(payload.get("exp") or 0)
    except (TypeError, ValueError):
        return False

    return token_cid == cid and exp >= time.time()


def resolve_playback_api_password(cid: str) -> str:
    api_password = request_api_password()
    if EXPECTED_API_PASSWORD and api_password == EXPECTED_API_PASSWORD:
        return api_password

    if verify_public_stream_token(request_public_stream_token(), cid):
        return EXPECTED_API_PASSWORD

    return api_password


def request_base_url() -> str:
    forwarded_proto = request.headers.get("X-Forwarded-Proto", "").split(",", 1)[0].strip()
    forwarded_host = request.headers.get("X-Forwarded-Host", "").split(",", 1)[0].strip()
    host = forwarded_host or request.headers.get("Host", "").strip()
    if host:
        scheme = forwarded_proto or request.scheme or "https"
        return f"{scheme}://{host}"
    return request.host_url.rstrip("/")


def upstream_config_error() -> str | None:
    parsed = urlparse(UPSTREAM_BASE_URL)
    if parsed.netloc.lower() == "p2p.pixel-invoice.com":
        return "P2P_UPSTREAM_BASE_URL must point at an internal upstream, not the public proxy host."
    if UPSTREAM_KIND not in {"engine", "mediaflow"}:
        return "P2P_UPSTREAM_KIND must be either 'engine' or 'mediaflow'."
    return None


def _normalized_origin(value: str) -> str | None:
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return None
    if parsed.username or parsed.password:
        return None
    try:
        port = parsed.port
    except ValueError:
        return None
    default_port = 80 if parsed.scheme == "http" else 443
    return f"{parsed.scheme.lower()}://{parsed.hostname.lower()}:{port or default_port}"


def allowed_segment_upstream_origins() -> set[str]:
    candidates = [UPSTREAM_BASE_URL]
    candidates.extend(
        item.strip()
        for item in os.getenv("P2P_SEGMENT_ALLOWED_ORIGINS", "").split(",")
        if item.strip()
    )
    return {origin for candidate in candidates if (origin := _normalized_origin(candidate))}


def is_allowed_segment_upstream_url(value: str) -> bool:
    origin = _normalized_origin(value)
    return bool(origin and origin in allowed_segment_upstream_origins())


def upstream_manifest_request(cid: str, api_password: str) -> tuple[str, dict[str, str | None]]:
    if UPSTREAM_KIND == "mediaflow":
        return (
            f"{UPSTREAM_BASE_URL}/proxy/acestream/manifest.m3u8",
            {"infohash": cid, "id": cid, "api_password": api_password},
        )
    return (
        f"{UPSTREAM_BASE_URL}/ace/getstream",
        {"id": cid, "infohash": cid, "api_password": api_password},
    )


def normalize_upstream_url(url: str) -> str:
    parsed = urlparse(url)
    upstream = urlparse(UPSTREAM_BASE_URL)
    if parsed.hostname not in {"127.0.0.1", "localhost"}:
        return url
    replacement_netloc = upstream.netloc
    if not replacement_netloc:
        return url
    return urlunparse(
        (
            upstream.scheme or parsed.scheme,
            replacement_netloc,
            parsed.path,
            parsed.params,
            parsed.query,
            parsed.fragment,
        )
    )


def validate_service_token() -> Tuple[Response, int] | None:
    client_id = request.headers.get("CF-Access-Client-Id", "").strip()
    client_secret = request.headers.get("CF-Access-Client-Secret", "").strip()
    if (
        EXPECTED_SERVICE_TOKEN_ID
        and EXPECTED_SERVICE_TOKEN_SECRET
        and hmac.compare_digest(client_id, EXPECTED_SERVICE_TOKEN_ID)
        and hmac.compare_digest(client_secret, EXPECTED_SERVICE_TOKEN_SECRET)
    ):
        return None

    api_password = request_api_password()
    if EXPECTED_API_PASSWORD and hmac.compare_digest(api_password, EXPECTED_API_PASSWORD):
        return None

    cid = request_stream_cid()
    if cid and verify_public_stream_token(request_public_stream_token(), cid):
        return None

    return jsonify(
        {
            "error": "service_token_required",
            "detail": "Missing or invalid broker service credential.",
        }
    ), 403


def validate_operator_access() -> Tuple[Response, int] | None:
    supplied_dashboard_key = request.args.get("key", "").strip()
    if DASHBOARD_KEY and hmac.compare_digest(supplied_dashboard_key, DASHBOARD_KEY):
        return None
    return validate_service_token()


def proxy_auth_headers(api_password: str) -> Dict[str, str]:
    return {
        "Accept": "application/vnd.apple.mpegurl, application/x-mpegurl;q=0.9, */*;q=0.8",
        "Authorization": f"Bearer {api_password}",
        "api-password": api_password,
    }


def runtime_config_error_response() -> Tuple[Response, int] | None:
    config_error = upstream_config_error()
    if config_error:
        return jsonify({"error": "proxy_misconfigured", "detail": config_error}), 503
    return None


@dataclass
class SegmentProbe:
    original_url: str
    proxy_url: str
    status_code: int
    bytes_read: int
    failure_class: str


def segment_proxy_url(
    base_proxy_url: str,
    cid: str,
    api_password: str,
    segment_url: str,
    public_stream_token: Optional[str] = None,
) -> str:
    if public_stream_token:
        auth_query = f"stream_token={quote(public_stream_token)}"
    else:
        auth_query = f"api_password={quote(api_password)}"
    return (
        f"{base_proxy_url.rstrip('/')}/ace/proxy"
        f"?cid={quote(cid)}&{auth_query}&url={quote(segment_url, safe='')}"
    )


def probe_segment_for_manifest(
    segment_url: str,
    cid: str,
    base_proxy_url: str,
    api_password: str,
    public_stream_token: Optional[str] = None,
) -> SegmentProbe:
    try:
        response = requests.get(
            segment_url,
            headers={"Range": "bytes=0-4095"},
            timeout=(2, SEGMENT_TIMEOUT_SECONDS),
        )
        status_code = response.status_code
        bytes_read = len(response.content or b"")
        if status_code == 416:
            response = requests.get(
                segment_url,
                timeout=(2, SEGMENT_TIMEOUT_SECONDS),
            )
            status_code = response.status_code
            bytes_read = len(response.content or b"")
    except requests.Timeout:
        status_code = 0
        bytes_read = 0
    except requests.RequestException:
        status_code = -1
        bytes_read = 0

    metrics.record_segment(status_code=status_code)
    failure_class = classify_segment_failure(
        status_code=status_code,
        bytes_read=bytes_read,
        minimum_segment_bytes=MIN_SEGMENT_BYTES,
    )
    proxy_url = segment_proxy_url(base_proxy_url, cid, api_password, segment_url, public_stream_token)
    return SegmentProbe(
        original_url=segment_url,
        proxy_url=proxy_url,
        status_code=status_code,
        bytes_read=bytes_read,
        failure_class=failure_class,
    )


@dataclass
class ManifestPreparationResult:
    cid: str
    api_password: str
    rewritten_manifest: str
    manifest_ttfb_ms: int
    validated_segment_count: int
    upstream_manifest_url: str
    rejection_reasons: List[str]
    first_segment_url: Optional[str]
    first_upstream_segment_url: Optional[str]
    engine_session: Optional["EnginePlaybackSession"] = None


@dataclass
class EnginePlaybackSession:
    playback_url: str
    stat_url: str
    command_url: str
    playback_session_id: str
    event_url: str = ""
    events: List[Dict[str, Any]] = field(default_factory=list)


@dataclass
class ManifestPreparationFailure(Exception):
    cid: str
    error_code: str
    detail: str
    engine_session: Optional["EnginePlaybackSession"] = None

    @property
    def retryable(self) -> bool:
        return self.error_code in {
            "timeout",
            "524",
            "manifest_404",
            "manifest_403",
            "manifest_500",
            "manifest_502",
            "manifest_503",
            "manifest_504",
            "segment_0",
            "segment_-1",
            "segment_small",
            "segment_timeout",
            "segment_proxy_error",
            "segment_unavailable",
            "segment_probe_failed",
            "manifest_empty",
        }


def prepare_manifest_material(
    cid: str,
    api_password: str,
    existing_engine_session: Optional["EnginePlaybackSession"] = None,
    base_proxy_url: Optional[str] = None,
    public_stream_token: Optional[str] = None,
) -> ManifestPreparationResult:
    started_at = time.perf_counter()
    resolved_base_proxy_url = (base_proxy_url or request_base_url()).rstrip("/")
    upstream_manifest_url, upstream_query = upstream_manifest_request(cid=cid, api_password=api_password)

    if UPSTREAM_KIND == "engine":
        playback_session = existing_engine_session or create_engine_hls_session(cid=cid)
        upstream_manifest_url = playback_session.playback_url
        try:
            manifest_text = wait_for_engine_manifest(
                cid=cid,
                engine_session=playback_session,
                started_at=started_at,
            )
        except ManifestPreparationFailure as failure:
            failure.engine_session = playback_session
            raise
    else:
        try:
            upstream_response = requests.get(
                upstream_manifest_url,
                params=upstream_query,
                headers=proxy_auth_headers(api_password),
                timeout=(2, MANIFEST_TIMEOUT_SECONDS),
            )
        except requests.Timeout:
            error_code = classify_manifest_failure(timed_out=True)
            metrics.record_manifest(
                ttfb_ms=int((time.perf_counter() - started_at) * 1000),
                success=False,
                cid=cid,
                reason=error_code,
            )
            raise ManifestPreparationFailure(
                cid=cid,
                error_code=error_code,
                detail=f"Manifest probe exceeded {MANIFEST_TIMEOUT_SECONDS}s timeout.",
            )
        except requests.RequestException as exc:
            error_code = classify_manifest_failure()
            metrics.record_manifest(
                ttfb_ms=int((time.perf_counter() - started_at) * 1000),
                success=False,
                cid=cid,
                reason=error_code,
            )
            raise ManifestPreparationFailure(
                cid=cid,
                error_code=error_code,
                detail=f"Manifest request failed: {exc}",
            )
        except Exception as exc:
            error_code = "manifest_error"
            metrics.record_manifest(
                ttfb_ms=int((time.perf_counter() - started_at) * 1000),
                success=False,
                cid=cid,
                reason=error_code,
            )
            raise ManifestPreparationFailure(
                cid=cid,
                error_code=error_code,
                detail=f"Manifest request failed unexpectedly: {exc}",
            )

        if upstream_response.status_code < 200 or upstream_response.status_code > 299:
            error_code = classify_manifest_failure(status_code=upstream_response.status_code)
            metrics.record_manifest(
                ttfb_ms=int((time.perf_counter() - started_at) * 1000),
                success=False,
                cid=cid,
                reason=error_code,
            )
            raise ManifestPreparationFailure(
                cid=cid,
                error_code=error_code,
                detail=f"Upstream manifest returned HTTP {upstream_response.status_code}.",
            )

        manifest_text = upstream_response.text
    if "#EXTM3U" not in manifest_text:
        error_code = "manifest_parse"
        metrics.record_manifest(
            ttfb_ms=int((time.perf_counter() - started_at) * 1000),
            success=False,
            cid=cid,
            reason=error_code,
        )
        raise ManifestPreparationFailure(
            cid=cid,
            error_code=error_code,
            detail="Upstream body is not a valid HLS manifest.",
        )

    segment_lines = [line.strip() for line in parse_manifest_lines(manifest_text) if is_segment_line(line)]
    if not segment_lines:
        error_code = "manifest_empty"
        metrics.record_manifest(
            ttfb_ms=int((time.perf_counter() - started_at) * 1000),
            success=False,
            cid=cid,
            reason=error_code,
        )
        raise ManifestPreparationFailure(
            cid=cid,
            error_code=error_code,
            detail="Manifest has no segment URLs.",
        )

    # Probe a mix of older and newer segments to avoid head-of-stream timeouts.
    # Always include the playlist head: we must not publish a manifest whose first
    # segment URL still returns "download not found" while later segments probe OK.
    if len(segment_lines) > MAX_SEGMENTS_TO_VALIDATE:
        probe_window = segment_lines[:MAX_SEGMENTS_TO_VALIDATE // 2] + segment_lines[-(MAX_SEGMENTS_TO_VALIDATE // 2):]
    else:
        probe_window = list(segment_lines)

    head_line = segment_lines[0]
    if not probe_window:
        probe_window = [head_line]
    elif head_line not in probe_window:
        probe_window = [head_line] + list(probe_window)

    seen_probe: set[str] = set()
    probe_window_deduped: List[str] = []
    for ln in probe_window:
        if ln not in seen_probe:
            seen_probe.add(ln)
            probe_window_deduped.append(ln)
    probe_window = probe_window_deduped

    validated: Dict[str, str] = {}
    rejection_reasons: List[str] = []

    # Pre-populate unprobed segments so long playlists stay contiguous; probed URLs
    # that fail are removed below so rewrite_manifest drops only bad lines.
    for line in segment_lines:
        resolved = absolute_url(line, upstream_manifest_url)
        proxy_url = segment_proxy_url(
            resolved_base_proxy_url,
            cid,
            api_password,
            resolved,
            public_stream_token,
        )
        validated[resolved] = proxy_url

    from concurrent.futures import ThreadPoolExecutor

    def probe_one(line: str) -> tuple[str, SegmentProbe]:
        resolved = absolute_url(line, upstream_manifest_url)
        probe = probe_segment_for_manifest(
            resolved,
            cid=cid,
            base_proxy_url=resolved_base_proxy_url,
            api_password=api_password,
            public_stream_token=public_stream_token,
        )
        return resolved, probe

    with ThreadPoolExecutor(max_workers=max(1, len(probe_window))) as executor:
        probes = list(executor.map(probe_one, probe_window)) if probe_window else []

    first_resolved = absolute_url(segment_lines[0], upstream_manifest_url)
    probes_by_resolved = {resolved: probe for resolved, probe in probes}
    first_probe = probes_by_resolved.get(first_resolved)

    if first_probe is None or first_probe.failure_class != "ok":
        fc = first_probe.failure_class if first_probe else "segment_0"
        metrics.record_manifest(
            ttfb_ms=int((time.perf_counter() - started_at) * 1000),
            success=False,
            cid=cid,
            reason=fc,
        )
        raise ManifestPreparationFailure(
            cid=cid,
            error_code=fc,
            detail="First HLS segment is not fetchable from upstream yet.",
        )

    ok_count = 0
    for resolved, probe in probes:
        if probe.failure_class != "ok":
            rejection_reasons.append(probe.failure_class)
            validated.pop(resolved, None)
        else:
            ok_count += 1

    if probe_window and ok_count == 0:
        reason = rejection_reasons[0] if rejection_reasons else "probe_failed"
        metrics.record_manifest(
            ttfb_ms=int((time.perf_counter() - started_at) * 1000),
            success=False,
            cid=cid,
            reason=reason,
        )
        raise ManifestPreparationFailure(
            cid=cid,
            error_code=reason,
            detail="All candidate segments failed validation.",
        )

    rewritten_manifest = rewrite_manifest(
        original_manifest=manifest_text,
        manifest_url=upstream_manifest_url,
        valid_segment_urls=validated,
    )

    rewritten_segment_lines = [line for line in parse_manifest_lines(rewritten_manifest) if is_segment_line(line)]
    if not rewritten_segment_lines:
        error_code = "segment_unavailable"
        metrics.record_manifest(
            ttfb_ms=int((time.perf_counter() - started_at) * 1000),
            success=False,
            cid=cid,
            reason=error_code,
        )
        raise ManifestPreparationFailure(
            cid=cid,
            error_code=error_code,
            detail="No valid segment URLs remained after manifest sanitization.",
        )

    ttfb_ms = int((time.perf_counter() - started_at) * 1000)
    metrics.record_manifest(ttfb_ms=ttfb_ms, success=True, cid=cid)
    first_upstream_segment_url = first_resolved if first_resolved in validated else None
    return ManifestPreparationResult(
        cid=cid,
        api_password=api_password,
        rewritten_manifest=rewritten_manifest,
        manifest_ttfb_ms=ttfb_ms,
        validated_segment_count=ok_count,
        upstream_manifest_url=upstream_manifest_url,
        rejection_reasons=rejection_reasons,
        first_segment_url=rewritten_segment_lines[0] if rewritten_segment_lines else None,
        first_upstream_segment_url=first_upstream_segment_url,
        engine_session=playback_session if UPSTREAM_KIND == "engine" else None,
    )


def create_engine_hls_session(cid: str) -> EnginePlaybackSession:
    import hashlib
    # Ace Engine binds live HLS segment names to the playback pid. A stable pid
    # can resurrect an expired playlist (/0.ts returning "download not found"),
    # which makes web playback stop shortly after it starts.
    pid = hashlib.md5(f"{cid}:{uuid.uuid4().hex}".encode()).hexdigest()
    session_url = f"{UPSTREAM_BASE_URL}/ace/manifest.m3u8"
    try:
        response = requests.get(
            session_url,
            params={
                "format": "json",
                "infohash": cid,
                "pid": pid,
                "use_api_events": 1,
                "use_stop_notifications": 1,
            },
            timeout=(2, ENGINE_SESSION_CREATE_TIMEOUT_SECONDS),
        )
    except requests.Timeout as exc:
        raise ManifestPreparationFailure(
            cid=cid,
            error_code="timeout",
            detail=f"Engine session creation exceeded {ENGINE_SESSION_CREATE_TIMEOUT_SECONDS}s timeout: {exc}",
        ) from exc
    except requests.RequestException as exc:
        raise ManifestPreparationFailure(
            cid=cid,
            error_code="manifest_error",
            detail=f"Engine session creation failed: {exc}",
        ) from exc

    if response.status_code < 200 or response.status_code > 299:
        raise ManifestPreparationFailure(
            cid=cid,
            error_code=classify_manifest_failure(status_code=response.status_code),
            detail=f"Engine session creation returned HTTP {response.status_code}.",
        )

    try:
        payload = response.json()
    except ValueError as exc:
        raise ManifestPreparationFailure(
            cid=cid,
            error_code="manifest_parse",
            detail="Engine session creation did not return valid JSON.",
        ) from exc

    error_text = str(payload.get("error") or "").strip()
    if error_text:
        extra_data = payload.get("extra_data") if isinstance(payload.get("extra_data"), dict) else {}
        missing_option = str(extra_data.get("option") or "").strip()
        if str(extra_data.get("reason") or "").strip() == "missing_option" and missing_option:
            raise ManifestPreparationFailure(
                cid=cid,
                error_code=f"missing_entitlement_{missing_option}",
                detail=f"AceStream engine is missing required service option: {missing_option}.",
            )
        raise ManifestPreparationFailure(
            cid=cid,
            error_code="manifest_error",
            detail=f"Engine session creation failed: {error_text}",
        )

    result = payload.get("response") or {}
    playback_url = str(result.get("playback_url") or "").strip()
    if not playback_url:
        raise ManifestPreparationFailure(
            cid=cid,
            error_code="manifest_empty",
            detail="Engine session creation returned no playback URL.",
        )

    return EnginePlaybackSession(
        playback_url=normalize_upstream_url(playback_url),
        stat_url=normalize_upstream_url(str(result.get("stat_url") or "").strip()),
        command_url=normalize_upstream_url(str(result.get("command_url") or "").strip()),
        playback_session_id=str(result.get("playback_session_id") or "").strip(),
        event_url=normalize_upstream_url(str(result.get("event_url") or "").strip()),
    )


def parse_engine_event_payload(payload: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    event = payload.get("response")
    if isinstance(event, str):
        try:
            event = json.loads(event)
        except (TypeError, ValueError):
            return None
    if not isinstance(event, dict):
        return None
    name = str(event.get("name") or "").strip()
    if not name:
        return None
    params = event.get("params") if isinstance(event.get("params"), dict) else {}
    return {"name": name, "params": params}


def poll_engine_event(event_url: str, timeout_seconds: float = 0.35) -> Optional[Dict[str, Any]]:
    if not event_url:
        return None
    try:
        response = requests.get(event_url, timeout=(0.2, timeout_seconds))
        response.raise_for_status()
        return parse_engine_event_payload(response.json())
    except requests.Timeout:
        return None
    except Exception as exc:
        log.debug("AceStream event poll failed: %s", exc)
        return None


def terminal_engine_event_failure(
    cid: str,
    event: Dict[str, Any],
    engine_session: EnginePlaybackSession,
) -> Optional[ManifestPreparationFailure]:
    name = str(event.get("name") or "")
    params = event.get("params") if isinstance(event.get("params"), dict) else {}
    reason = str(params.get("reason") or "").strip()
    option = str(params.get("option") or "").strip()
    if name == "download_stopped" and reason == "missing_option" and option:
        return ManifestPreparationFailure(
            cid=cid,
            error_code=f"missing_entitlement_{option}",
            detail=f"AceStream engine is missing required service option: {option}.",
            engine_session=engine_session,
        )
    if name == "segmenter_failed":
        return ManifestPreparationFailure(
            cid=cid,
            error_code="engine_segmenter_failed",
            detail="AceStream could not segment this source into browser-compatible HLS.",
            engine_session=engine_session,
        )
    if name == "download_stopped":
        return ManifestPreparationFailure(
            cid=cid,
            error_code="engine_download_stopped",
            detail=f"AceStream stopped this source ({reason or 'unspecified reason'}).",
            engine_session=engine_session,
        )
    return None


def wait_for_engine_manifest(
    cid: str,
    engine_session: EnginePlaybackSession,
    started_at: float,
) -> str:
    deadline = time.perf_counter() + ENGINE_WARMUP_TIMEOUT_SECONDS
    last_status_code = 0
    last_error: Optional[Exception] = None
    while time.perf_counter() < deadline:
        event = poll_engine_event(engine_session.event_url)
        if event:
            engine_session.events.append(event)
            terminal_failure = terminal_engine_event_failure(cid, event, engine_session)
            if terminal_failure:
                raise terminal_failure
        try:
            response = requests.get(
                engine_session.playback_url,
                timeout=(2, MANIFEST_TIMEOUT_SECONDS),
            )
            last_status_code = response.status_code
            if 200 <= response.status_code <= 299:
                manifest_text = response.text
                if "#EXTM3U" in manifest_text:
                    return manifest_text
            elif response.status_code in {404, 500, 502, 503, 504}:
                time.sleep(ENGINE_WARMUP_POLL_SECONDS)
                continue
        except requests.Timeout as exc:
            last_error = exc
            time.sleep(ENGINE_WARMUP_POLL_SECONDS)
            continue
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(ENGINE_WARMUP_POLL_SECONDS)
            continue

        time.sleep(ENGINE_WARMUP_POLL_SECONDS)

    if last_status_code:
        raise ManifestPreparationFailure(
            cid=cid,
            error_code=classify_manifest_failure(status_code=last_status_code),
            detail=f"Engine playback manifest did not become ready before timeout (last HTTP {last_status_code}).",
            engine_session=engine_session,
        )
    if last_error:
        raise ManifestPreparationFailure(
            cid=cid,
            error_code="timeout",
            detail=f"Engine playback manifest did not become ready before timeout: {last_error}",
            engine_session=engine_session,
        )
    raise ManifestPreparationFailure(
        cid=cid,
        error_code="timeout",
        detail=f"Engine playback manifest did not become ready within {ENGINE_WARMUP_TIMEOUT_SECONDS}s.",
        engine_session=engine_session,
    )


def manifest_failure_response(error: ManifestPreparationFailure) -> Tuple[Response, int]:
    payload = {
        "error": "stream_unavailable",
        "code": error.error_code,
        "cid": error.cid,
        "detail": error.detail,
    }
    return jsonify(payload), 503


def get_engine_token() -> str:
    try:
        response = requests.get(
            f"{UPSTREAM_BASE_URL}/webui/api/service",
            params={"method": "get_api_access_token"},
            timeout=5,
        )
        response.raise_for_status()
        payload = response.json()
        return ((payload.get("result") or {}).get("token") or "").strip()
    except Exception:
        return ""


def fetch_engine_status_snapshot(
    cid: str,
    engine_session: Optional["EnginePlaybackSession"] = None,
) -> Dict[str, Any]:
    if engine_session is not None and engine_session.stat_url:
        try:
            resp = requests.get(engine_session.stat_url, timeout=5)
            resp.raise_for_status()
            payload = resp.json()
            session_data = payload.get("response") or payload.get("result") or {}
            if isinstance(session_data, dict):
                snapshot = engine_session_status_to_snapshot(session_data)
                event = poll_engine_event(engine_session.event_url)
                if event:
                    snapshot["engine_event"] = event
                return snapshot
        except Exception as exc:
            return empty_engine_status_snapshot(error=str(exc))

    token = get_engine_token()
    status_url = f"{UPSTREAM_BASE_URL}/server/api"
    params = {
        "api_version": 3,
        "method": "get_status",
        "infohash": cid,
        "token": token,
    }

    try:
        resp = requests.get(status_url, params=params, timeout=5)
        resp.raise_for_status()
        swarm_data = resp.json().get("result", {})
        return {
            "peer_count": swarm_data.get("peers", 0),
            "download_speed_kbps": float(swarm_data.get("download_speed", 0)) / 1024.0,
            "upload_speed_kbps": float(swarm_data.get("upload_speed", 0)) / 1024.0,
            "buffer_seconds": float(swarm_data.get("buffer_progress", 0)),
            "ready_segment_count": swarm_data.get("ready_segments", 0),
            "first_segment_ready": swarm_data.get("ready_segments", 0) > 0,
            "estimated_startup_seconds": swarm_data.get("estimated_startup_seconds"),
            "error": None,
        }
    except Exception as exc:
        return empty_engine_status_snapshot(error=str(exc))


def empty_engine_status_snapshot(error: Optional[str] = None) -> Dict[str, Any]:
    return {
        "peer_count": 0,
        "download_speed_kbps": 0.0,
        "upload_speed_kbps": 0.0,
        "buffer_seconds": 0.0,
        "ready_segment_count": 0,
        "first_segment_ready": False,
        "estimated_startup_seconds": None,
        "error": error,
    }


def engine_session_status_to_snapshot(session_data: Dict[str, Any]) -> Dict[str, Any]:
    def numeric(*keys: str, default: float = 0.0) -> float:
        for key in keys:
            value = session_data.get(key)
            if value is None:
                continue
            try:
                return float(value)
            except (TypeError, ValueError):
                continue
        return default

    livepos = session_data.get("livepos") if isinstance(session_data.get("livepos"), dict) else {}
    ready_segment_count = int(numeric("ready_segments", default=0.0))
    if ready_segment_count <= 0 and livepos:
        ready_segment_count = int(numeric_from(livepos, "buffer_pieces", default=0.0))

    downloaded = numeric("downloaded", default=0.0)
    status = str(session_data.get("status") or "").lower()
    stream_status = int(numeric("stream_status", default=-1.0))
    first_segment_ready = ready_segment_count > 0 or downloaded > 0 or status == "dl" or stream_status >= 0

    # Ace Stream documents speed_down/speed_up as KBytes/s on the playback stat URL.
    # Fotty exposes Kbps to the app, so multiply by eight when those fields exist.
    speed_down_kbps = numeric("download_speed", default=-1.0)
    if speed_down_kbps < 0:
        speed_down_kbps = numeric("speed_down", default=0.0) * 8.0
    speed_up_kbps = numeric("upload_speed", default=-1.0)
    if speed_up_kbps < 0:
        speed_up_kbps = numeric("speed_up", default=0.0) * 8.0

    return {
        "peer_count": int(numeric("peers", "peer_count", default=0.0)),
        "download_speed_kbps": speed_down_kbps,
        "upload_speed_kbps": speed_up_kbps,
        "buffer_seconds": numeric("buffer_progress", default=float(ready_segment_count)),
        "ready_segment_count": ready_segment_count,
        "first_segment_ready": first_segment_ready,
        "estimated_startup_seconds": session_data.get("estimated_startup_seconds"),
        "error": None,
    }


def numeric_from(payload: Dict[str, Any], key: str, default: float = 0.0) -> float:
    value = payload.get(key)
    if value is None:
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def get_engine_version() -> Optional[str]:
    try:
        response = requests.get(
            f"{UPSTREAM_BASE_URL}/webui/api/service",
            params={"method": "get_version"},
            timeout=5,
        )
        response.raise_for_status()
        payload = response.json()
        version = ((payload.get("result") or {}).get("version") or "").strip()
        return version or None
    except Exception:
        return None


def search_engine(query: str, token: str, page_size: int = 80) -> List[Dict[str, Any]]:
    try:
        response = requests.get(
            f"{UPSTREAM_BASE_URL}/server/api",
            params={
                "api_version": 3,
                "method": "search",
                "query": query,
                "token": token,
                "page_size": page_size,
            },
            timeout=15,
        )
        response.raise_for_status()
        payload = response.json()
        return (payload.get("result") or {}).get("results") or []
    except Exception as exc:
        log.warning("Search failed for '%s': %s", query, exc)
        return []


def search_by_category(category: str, token: str, page_size: int = 120) -> List[Dict[str, Any]]:
    try:
        response = requests.get(
            f"{UPSTREAM_BASE_URL}/server/api",
            params={
                "api_version": 3,
                "method": "search",
                "category": category,
                "token": token,
                "page_size": page_size,
            },
            timeout=15,
        )
        response.raise_for_status()
        payload = response.json()
        return (payload.get("result") or {}).get("results") or []
    except Exception as exc:
        log.warning("Category search failed for '%s': %s", category, exc)
        return []


def flatten_scraper_results(results: List[Dict[Dict[str, Any]]]) -> List[Dict[str, Any]]:
    seen: Dict[str, Dict[str, Any]] = {}
    for parent in results:
        stream_items = parent.get("items") or [parent]
        for item in stream_items:
            cid = (item.get("infohash") or item.get("cid") or "").strip()
            if not cid:
                continue
            if cid in seen:
                continue
            raw_availability = item.get("availability", 0)
            try:
                availability = float(raw_availability)
            except (TypeError, ValueError):
                availability = 0.0
            seen[cid] = {
                "title": (item.get("name") or parent.get("name") or "Unknown Channel").strip(),
                "cid": cid,
                "availability": availability,
                "bitrate_kbps": int((item.get("bitrate") or 0) / 1000),
                "categories": item.get("categories") or [],
                "source": "ace-engine",
            }
    channels = list(seen.values())
    channels.sort(key=lambda channel: channel.get("availability", 0.0), reverse=True)
    return channels


def scraper_refresh_loop() -> None:
    global _scraper_matches_cache, _scraper_last_updated, _scraper_engine_version, _scraper_last_refresh_error
    while True:
        token = get_engine_token()
        if not token:
            with _scraper_lock:
                _scraper_last_refresh_error = "token_unavailable"
            time.sleep(20)
            continue
        engine_version = get_engine_version()
        sport_page = SCRAPER_SPORT_CATEGORY_PAGE_SIZE
        sport_results = search_by_category("sport", token=token, page_size=sport_page)
        if not sport_results:
            sport_results = search_engine("sport", token=token, page_size=sport_page)

        merged_raw: List[Dict[str, Any]] = []
        if sport_results:
            merged_raw.extend(sport_results)

        # Dynamic team-based search queries from web catalog
        dynamic_queries: List[str] = []
        try:
            matches_path = os.path.join(os.path.dirname(__file__), "matches.json")
            if os.path.exists(matches_path):
                with open(matches_path, "r") as f:
                    matches_data = json.load(f)
                    for m in matches_data.get("matches", []):
                        title = m.get("title")
                        if title:
                            dynamic_queries.append(title)
                        
                        teams = m.get("teams") or {}
                        home = teams.get("home", {}).get("name")
                        away = teams.get("away", {}).get("name")
                        if home and away:
                            dynamic_queries.append(f"{home} {away}")
                        if home: dynamic_queries.append(home)
                        if away: dynamic_queries.append(away)
        except Exception as e:
            log.warning("Failed to read matches.json for dynamic P2P queries: %s", e)

        all_search_queries = build_scraper_search_queries(
            dynamic_queries,
            max_queries=SCRAPER_MAX_TEXT_QUERIES,
        )
        
        extra_ps = SCRAPER_EXTRA_QUERY_PAGE_SIZE
        for q in all_search_queries:
            extra = search_engine(q, token=token, page_size=extra_ps)
            if extra:
                merged_raw.extend(extra)

        discovered_channels = flatten_scraper_results(merged_raw) if merged_raw else []
        channels = merge_pinned_channels(discovered_channels)
        now_iso = utcnow().isoformat()
        refresh_error = None
        redis_client = session_store.get_redis_client()
        redis_channels: List[Dict[str, Any]] = []
        if redis_client:
            try:
                raw_redis_channels = redis_client.get("scraper:matches_cache")
                if raw_redis_channels:
                    parsed_redis_channels = json.loads(raw_redis_channels)
                    if isinstance(parsed_redis_channels, list):
                        redis_channels = parsed_redis_channels
            except Exception as e:
                log.warning(f"Failed to read scraper cache from Redis: {e}")

        if not discovered_channels and redis_channels and len(redis_channels) > len(channels):
            channels = redis_channels
            refresh_error = "using_existing_cache_after_empty_discovery"

        with _scraper_lock:
            _scraper_engine_version = engine_version
            if channels:
                _scraper_matches_cache = channels
                _scraper_last_updated = now_iso
                _scraper_last_refresh_error = refresh_error
            else:
                _scraper_last_refresh_error = "empty_results"
        if channels:
            log.info(
                "Refreshed sport channels: %s unique (%s discovered, sport page=%s + %s text queries @ %s)",
                len(channels),
                len(discovered_channels),
                sport_page,
                len(all_search_queries),
                extra_ps,
            )
            # Share with other workers via Redis
            if redis_client:
                try:
                    ttl = SCRAPER_REFRESH_SECONDS * 3
                    redis_client.setex("scraper:matches_cache", ttl, json.dumps(channels))
                    redis_client.setex(
                        "scraper:matches_meta",
                        ttl,
                        json.dumps({"last_updated": now_iso, "last_refresh_error": refresh_error}),
                    )
                except Exception as e:
                    log.warning(f"Failed to sync scraper cache to Redis: {e}")
        else:
            log.warning("Refresh completed with no channels.")
            redis_client = session_store.get_redis_client()
            if redis_client:
                try:
                    redis_client.setex(
                        "scraper:matches_meta",
                        SCRAPER_REFRESH_SECONDS * 3,
                        json.dumps(
                            {
                                "last_updated": _scraper_last_updated,
                                "last_refresh_error": _scraper_last_refresh_error,
                            }
                        ),
                    )
                except Exception as e:
                    log.warning(f"Failed to sync scraper meta to Redis: {e}")
        time.sleep(SCRAPER_REFRESH_SECONDS)


def snapshot_scraper_matches() -> List[Dict[str, Any]]:
    # Prefer the largest healthy cache so an internal pinned-only refresh cannot
    # hide the standalone scraper's broader channel catalog.
    local_matches: List[Dict[str, Any]] = []
    with _scraper_lock:
        if _scraper_matches_cache:
            local_matches = list(_scraper_matches_cache)

    redis_client = session_store.get_redis_client()
    if redis_client:
        raw = redis_client.get("scraper:matches_cache")
        if raw:
            try:
                matches = json.loads(raw)
                if isinstance(matches, list) and len(matches) > len(local_matches):
                    with _scraper_lock:
                        _scraper_matches_cache[:] = matches
                    return matches
            except Exception:
                pass

    if local_matches:
        return local_matches

    return []


@dataclass
class BrokerEvent:
    name: str
    state: str
    message: str
    timestamp: datetime = field(default_factory=utcnow)
    metadata: Dict[str, Any] = field(default_factory=dict)

    def serialize(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "state": self.state,
            "message": self.message,
            "timestamp": isoformat(self.timestamp),
            "metadata": self.metadata,
        }

    @staticmethod
    def from_payload(payload: Dict[str, Any]) -> "BrokerEvent":
        return BrokerEvent(
            name=str(payload.get("name") or ""),
            state=str(payload.get("state") or ""),
            message=str(payload.get("message") or ""),
            timestamp=parse_datetime(payload.get("timestamp")) or utcnow(),
            metadata=payload.get("metadata") if isinstance(payload.get("metadata"), dict) else {},
        )


@dataclass
class CIDHealthHistory:
    success_count: int = 0
    failure_count: int = 0
    stale_failure_count: int = 0
    segment_success_count: int = 0
    segment_failure_count: int = 0
    last_ready_ttfb_ms: Optional[int] = None
    best_ready_ttfb_ms: Optional[int] = None
    last_ready_at: Optional[datetime] = None
    last_failure_code: Optional[str] = None
    last_failure_at: Optional[datetime] = None

    def record_success(self, ttfb_ms: int, segment_count: int) -> None:
        self.success_count += 1
        self.segment_success_count += max(segment_count, 0)
        self.last_ready_ttfb_ms = ttfb_ms
        if self.best_ready_ttfb_ms is None or ttfb_ms < self.best_ready_ttfb_ms:
            self.best_ready_ttfb_ms = ttfb_ms
        self.last_ready_at = utcnow()

    def record_failure(self, code: str, stale: bool = False) -> None:
        self.failure_count += 1
        self.segment_failure_count += 1
        if stale:
            self.stale_failure_count += 1
        self.last_failure_code = code
        self.last_failure_at = utcnow()

    def segment_success_rate(self) -> float:
        total = self.segment_success_count + self.segment_failure_count
        if total <= 0:
            return 0.0
        return round(float(self.segment_success_count) / float(total), 4)

    def score(self) -> int:
        score = 50
        score += min(self.success_count * 8, 32)
        score -= min(self.failure_count * 6, 42)
        score -= min(self.stale_failure_count * 10, 30)
        if self.best_ready_ttfb_ms is not None:
            score += max(0, 20 - int(self.best_ready_ttfb_ms / 5000))
        score += int(self.segment_success_rate() * 20)
        return max(0, min(score, 100))

    def serialize(self) -> Dict[str, Any]:
        return {
            "score": self.score(),
            "success_count": self.success_count,
            "failure_count": self.failure_count,
            "stale_failure_count": self.stale_failure_count,
            "segment_success_count": self.segment_success_count,
            "segment_failure_count": self.segment_failure_count,
            "segment_success_rate": self.segment_success_rate(),
            "last_ready_ttfb_ms": self.last_ready_ttfb_ms,
            "best_ready_ttfb_ms": self.best_ready_ttfb_ms,
            "last_ready_at": isoformat(self.last_ready_at),
            "last_failure_code": self.last_failure_code,
            "last_failure_at": isoformat(self.last_failure_at),
        }

    @staticmethod
    def from_payload(payload: Dict[str, Any]) -> "CIDHealthHistory":
        history = CIDHealthHistory()
        history.success_count = int(payload.get("success_count") or 0)
        history.failure_count = int(payload.get("failure_count") or 0)
        history.stale_failure_count = int(payload.get("stale_failure_count") or 0)
        history.segment_success_count = int(payload.get("segment_success_count") or 0)
        history.segment_failure_count = int(payload.get("segment_failure_count") or 0)
        history.last_ready_ttfb_ms = payload.get("last_ready_ttfb_ms")
        history.best_ready_ttfb_ms = payload.get("best_ready_ttfb_ms")
        history.last_ready_at = parse_datetime(payload.get("last_ready_at"))
        history.last_failure_code = payload.get("last_failure_code")
        history.last_failure_at = parse_datetime(payload.get("last_failure_at"))
        return history


@dataclass
class BrokerSessionRecord:
    session_id: str
    cid: str
    api_password: str
    title: Optional[str]
    category: Optional[str]
    availability: Optional[float]
    bitrate_kbps: Optional[int]
    categories: List[str]
    source: Optional[str]
    manifest_url: str
    status_url: str
    events_url: str
    state: str = "starting"
    message: str = "Preparing stream..."
    created_at: datetime = field(default_factory=utcnow)
    updated_at: datetime = field(default_factory=utcnow)
    expires_at: datetime = field(default_factory=lambda: utcnow() + timedelta(seconds=BROKER_SESSION_TTL_SECONDS))
    manifest_text: Optional[str] = None
    manifest_ttfb_ms: Optional[int] = None
    last_error: Optional[str] = None
    last_error_code: Optional[str] = None
    peer_count: int = 0
    download_speed_kbps: float = 0.0
    upload_speed_kbps: float = 0.0
    buffer_seconds: float = 0.0
    ready_segment_count: int = 0
    first_segment_ready: bool = False
    estimated_startup_seconds: Optional[float] = None
    first_segment_url: Optional[str] = None
    first_upstream_segment_url: Optional[str] = None
    engine_playback_url: Optional[str] = None
    engine_stat_url: Optional[str] = None
    engine_command_url: Optional[str] = None
    engine_event_url: Optional[str] = None
    engine_playback_session_id: Optional[str] = None
    manifest_revalidated_until: Optional[datetime] = None
    broker_health: Dict[str, Any] = field(default_factory=dict)
    prepare_attempts: int = 0
    refresh_attempts: int = 0
    prepare_inflight: bool = False
    last_prepare_started_at: Optional[datetime] = None
    last_prepare_completed_at: Optional[datetime] = None
    last_refresh_at: Optional[datetime] = None
    last_sequence_change_at: datetime = field(default_factory=utcnow)
    events: List[BrokerEvent] = field(default_factory=list)

    def add_event(self, name: str, state: str, message: str, metadata: Optional[Dict[str, Any]] = None) -> None:
        self.events.append(
            BrokerEvent(
                name=name,
                state=state,
                message=message,
                metadata=metadata or {},
            )
        )
        if len(self.events) > BROKER_EVENT_LIMIT:
            self.events = self.events[-BROKER_EVENT_LIMIT:]

    def serialize(self, include_events: bool = False) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "session_id": self.session_id,
            "source_id": self.cid,
            "title": self.title,
            "category": self.category,
            "availability": self.availability,
            "bitrate_kbps": self.bitrate_kbps,
            "categories": self.categories,
            "source": self.source,
            "state": self.state,
            "message": self.message,
            "peer_count": self.peer_count,
            "download_speed_kbps": self.download_speed_kbps,
            "upload_speed_kbps": self.upload_speed_kbps,
            "buffer_seconds": self.buffer_seconds,
            "ready_segment_count": self.ready_segment_count,
            "first_segment_ready": self.first_segment_ready,
            "estimated_startup_seconds": self.estimated_startup_seconds,
            "manifest_url": self.manifest_url,
            "status_url": self.status_url,
            "events_url": self.events_url,
            "first_segment_url": self.first_segment_url,
            "last_error": self.last_error,
            "last_error_code": self.last_error_code,
            "created_at": isoformat(self.created_at),
            "updated_at": isoformat(self.updated_at),
            "expires_at": isoformat(self.expires_at),
            "prepare_attempts": self.prepare_attempts,
            "refresh_attempts": self.refresh_attempts,
            "manifest_ttfb_ms": self.manifest_ttfb_ms,
            "broker_health": self.broker_health,
            "event_count": len(self.events),
        }
        if include_events:
            payload["events"] = [event.serialize() for event in self.events]
        return payload

    def persist_payload(self) -> Dict[str, Any]:
        payload = self.serialize(include_events=True)
        payload.update(
            {
                "cid": self.cid,
                "api_password": self.api_password,
                "manifest_text": self.manifest_text,
                "first_upstream_segment_url": self.first_upstream_segment_url,
                "engine_playback_url": self.engine_playback_url,
                "engine_stat_url": self.engine_stat_url,
                "engine_command_url": self.engine_command_url,
                "engine_event_url": self.engine_event_url,
                "engine_playback_session_id": self.engine_playback_session_id,
                "manifest_revalidated_until": isoformat(self.manifest_revalidated_until),
                "prepare_inflight": self.prepare_inflight,
                "last_prepare_started_at": isoformat(self.last_prepare_started_at),
                "last_prepare_completed_at": isoformat(self.last_prepare_completed_at),
                "last_refresh_at": isoformat(self.last_refresh_at),
                "last_sequence_change_at": isoformat(self.last_sequence_change_at),
            }
        )
        return payload

    @staticmethod
    def from_payload(payload: Dict[str, Any]) -> "BrokerSessionRecord":
        record = BrokerSessionRecord(
            session_id=str(payload.get("session_id") or ""),
            cid=str(payload.get("cid") or payload.get("source_id") or ""),
            api_password=str(payload.get("api_password") or ""),
            title=payload.get("title"),
            category=payload.get("category"),
            availability=payload.get("availability"),
            bitrate_kbps=payload.get("bitrate_kbps"),
            categories=payload.get("categories") if isinstance(payload.get("categories"), list) else [],
            source=payload.get("source"),
            manifest_url=str(payload.get("manifest_url") or ""),
            status_url=str(payload.get("status_url") or ""),
            events_url=str(payload.get("events_url") or ""),
            state=str(payload.get("state") or "starting"),
            message=str(payload.get("message") or "Preparing stream..."),
            created_at=parse_datetime(payload.get("created_at")) or utcnow(),
            updated_at=parse_datetime(payload.get("updated_at")) or utcnow(),
            expires_at=parse_datetime(payload.get("expires_at")) or utcnow() + timedelta(seconds=BROKER_SESSION_TTL_SECONDS),
        )
        record.manifest_text = payload.get("manifest_text")
        record.manifest_ttfb_ms = payload.get("manifest_ttfb_ms")
        record.last_error = payload.get("last_error")
        record.last_error_code = payload.get("last_error_code")
        record.peer_count = int(payload.get("peer_count") or 0)
        record.download_speed_kbps = float(payload.get("download_speed_kbps") or 0.0)
        record.upload_speed_kbps = float(payload.get("upload_speed_kbps") or 0.0)
        record.buffer_seconds = float(payload.get("buffer_seconds") or 0.0)
        record.ready_segment_count = int(payload.get("ready_segment_count") or 0)
        record.first_segment_ready = bool(payload.get("first_segment_ready") or False)
        record.estimated_startup_seconds = payload.get("estimated_startup_seconds")
        record.first_segment_url = payload.get("first_segment_url")
        record.first_upstream_segment_url = payload.get("first_upstream_segment_url")
        record.engine_playback_url = payload.get("engine_playback_url")
        record.engine_stat_url = payload.get("engine_stat_url")
        record.engine_command_url = payload.get("engine_command_url")
        record.engine_event_url = payload.get("engine_event_url")
        record.engine_playback_session_id = payload.get("engine_playback_session_id")
        record.manifest_revalidated_until = parse_datetime(payload.get("manifest_revalidated_until"))
        record.broker_health = payload.get("broker_health") if isinstance(payload.get("broker_health"), dict) else {}
        record.prepare_attempts = int(payload.get("prepare_attempts") or 0)
        record.refresh_attempts = int(payload.get("refresh_attempts") or 0)
        record.prepare_inflight = bool(payload.get("prepare_inflight") or False)
        record.last_prepare_started_at = parse_datetime(payload.get("last_prepare_started_at"))
        record.last_prepare_completed_at = parse_datetime(payload.get("last_prepare_completed_at"))
        record.last_refresh_at = parse_datetime(payload.get("last_refresh_at"))
        record.last_sequence_change_at = parse_datetime(payload.get("last_sequence_change_at")) or utcnow()
        events = payload.get("events") if isinstance(payload.get("events"), list) else []
        record.events = [BrokerEvent.from_payload(event) for event in events if isinstance(event, dict)]
        return record


class BrokerSessionStore:
    def __init__(self, redis_client: Optional[Any] = None, redis_url: Optional[str] = None) -> None:
        self._lock = threading.RLock()
        self._sessions: Dict[str, BrokerSessionRecord] = {}
        self._cid_sessions: Dict[str, str] = {}
        self._cid_health: Dict[str, CIDHealthHistory] = {}
        self._redis = redis_client
        configured_url = REDIS_URL if redis_url is None else redis_url
        if self._redis is None and configured_url:
            if redis_lib is None:
                log.warning("P2P Redis URL configured but redis package is not installed; using in-memory broker store.")
            else:
                try:
                    self._redis = redis_lib.Redis.from_url(
                        configured_url,
                        decode_responses=True,
                        socket_connect_timeout=REDIS_CONNECT_TIMEOUT_SECONDS,
                        socket_timeout=REDIS_SOCKET_TIMEOUT_SECONDS,
                    )
                    self._redis.ping()
                    log.info("P2P broker session store connected to Redis.")
                except Exception as exc:
                    log.warning("P2P Redis unavailable (%s); using in-memory broker store.", exc)
                    self._redis = None
    
    def get_redis_client(self) -> Optional[Any]:
        return self._redis

    @property
    def backend_name(self) -> str:
        return "redis" if self._redis is not None else "memory"

    def _key(self, *parts: str) -> str:
        return ":".join([REDIS_KEY_PREFIX, *parts])

    def _session_key(self, session_id: str) -> str:
        return self._key("session", session_id)

    def _cid_key(self, cid: str) -> str:
        return self._key("cid", cid)

    def _health_key(self, cid: str) -> str:
        return self._key("health", cid)

    def _sessions_set_key(self) -> str:
        return self._key("sessions")

    def _health_set_key(self) -> str:
        return self._key("health_cids")

    def _lock_name(self, *parts: str) -> str:
        return self._key("lock", *parts)

    def _redis_lock(self, *parts: str):
        if self._redis is None:
            return self._lock
        return self._redis.lock(
            self._lock_name(*parts),
            timeout=REDIS_LOCK_TIMEOUT_SECONDS,
            blocking_timeout=5,
        )

    def try_acquire_lock(self, *parts: str, timeout: float = 30.0):
        if self._redis is None:
            acquired = self._lock.acquire(blocking=False)
            return self._lock if acquired else None
        lock = self._redis.lock(
            self._lock_name(*parts),
            timeout=timeout,
            blocking_timeout=0,
        )
        try:
            return lock if lock.acquire(blocking=False) else None
        except Exception as exc:
            log.warning("Failed to acquire Redis lock %s: %s", self._lock_name(*parts), exc)
            return None

    def _load_record_locked(self, session_id: str) -> Optional[BrokerSessionRecord]:
        if self._redis is None:
            return self._sessions.get(session_id)
        raw = self._redis.get(self._session_key(session_id))
        if not raw:
            return None
        try:
            payload = json.loads(raw)
            if not isinstance(payload, dict):
                return None
            return BrokerSessionRecord.from_payload(payload)
        except Exception as exc:
            log.warning("Failed to decode broker session %s from Redis: %s", session_id, exc)
            return None

    def _save_record_locked(self, record: BrokerSessionRecord) -> None:
        self._attach_health_locked(record)
        if self._redis is None:
            self._sessions[record.session_id] = record
            self._cid_sessions[record.cid] = record.session_id
            return
        payload = json.dumps(record.persist_payload(), separators=(",", ":"))
        self._redis.setex(self._session_key(record.session_id), REDIS_RECORD_TTL_SECONDS, payload)
        self._redis.setex(self._cid_key(record.cid), REDIS_RECORD_TTL_SECONDS, record.session_id)
        self._redis.sadd(self._sessions_set_key(), record.session_id)

    def _load_cid_session_locked(self, cid: str) -> Optional[str]:
        if self._redis is None:
            return self._cid_sessions.get(cid)
        return self._redis.get(self._cid_key(cid))

    def _clear_cid_session_locked(self, cid: str) -> None:
        if self._redis is None:
            self._cid_sessions.pop(cid, None)
            return
        self._redis.delete(self._cid_key(cid))

    def _load_history_locked(self, cid: str) -> Optional[CIDHealthHistory]:
        if self._redis is None:
            return self._cid_health.get(cid)
        raw = self._redis.get(self._health_key(cid))
        if not raw:
            return None
        try:
            payload = json.loads(raw)
            if not isinstance(payload, dict):
                return None
            return CIDHealthHistory.from_payload(payload)
        except Exception as exc:
            log.warning("Failed to decode CID health %s from Redis: %s", cid, exc)
            return None

    def _save_history_locked(self, cid: str, history: CIDHealthHistory) -> None:
        if self._redis is None:
            self._cid_health[cid] = history
            return
        payload = json.dumps(history.serialize(), separators=(",", ":"))
        self._redis.setex(self._health_key(cid), REDIS_HEALTH_TTL_SECONDS, payload)
        self._redis.sadd(self._health_set_key(), cid)

    def create(
        self,
        *,
        cid: str,
        api_password: str,
        title: Optional[str],
        category: Optional[str],
        availability: Optional[float],
        bitrate_kbps: Optional[int],
        categories: List[str],
        source: Optional[str],
        base_url: str,
        force_new: bool = False,
    ) -> Tuple[BrokerSessionRecord, bool]:
        now = utcnow()
        with self._redis_lock("cid", cid):
            existing_id = self._load_cid_session_locked(cid)
            existing = self._load_record_locked(existing_id or "")
            if (
                not force_new
                and existing is not None
                and self._can_reuse_locked(existing, api_password=api_password, now=now)
            ):
                self._merge_context_locked(
                    existing,
                    title=title,
                    category=category,
                    availability=availability,
                    bitrate_kbps=bitrate_kbps,
                    categories=categories,
                    source=source,
                )
                existing.updated_at = now
                existing.add_event(
                    name="session_reused",
                    state=existing.state,
                    message="Existing broker session reused for CID.",
                    metadata={"cid": cid, "reason": "cid_dedupe"},
                )
                self._save_record_locked(existing)
                return existing, False
            if existing_id and existing is None:
                self._clear_cid_session_locked(cid)

            session_id = uuid.uuid4().hex
            manifest_url = f"{base_url}/proxy/acestream/session/{session_id}/manifest.m3u8"
            status_url = f"{base_url}/proxy/acestream/session/{session_id}/status"
            events_url = f"{base_url}/proxy/acestream/session/{session_id}/events"
            record = BrokerSessionRecord(
                session_id=session_id,
                cid=cid,
                api_password=api_password,
                title=title,
                category=category,
                availability=availability,
                bitrate_kbps=bitrate_kbps,
                categories=categories,
                source=source,
                manifest_url=manifest_url,
                status_url=status_url,
                events_url=events_url,
                message="Looking for peers...",
            )
            record.add_event(
                name="session_created",
                state=record.state,
                message="P2P broker session created.",
                metadata={
                    "cid": cid,
                    "category": category or "",
                    "source": source or "",
                    "bitrate_kbps": bitrate_kbps or 0,
                    "force_new": force_new,
                },
            )
            self._save_record_locked(record)
            return record, True

    def _history_for_locked(self, cid: str) -> CIDHealthHistory:
        history = self._load_history_locked(cid)
        if history is None:
            history = CIDHealthHistory()
            self._save_history_locked(cid, history)
        return history

    def _attach_health_locked(self, record: BrokerSessionRecord) -> None:
        record.broker_health = self._history_for_locked(record.cid).serialize()

    def _merge_context_locked(
        self,
        record: BrokerSessionRecord,
        *,
        title: Optional[str],
        category: Optional[str],
        availability: Optional[float],
        bitrate_kbps: Optional[int],
        categories: List[str],
        source: Optional[str],
    ) -> None:
        if title and not record.title:
            record.title = title
        if category and not record.category:
            record.category = category
        if availability is not None:
            record.availability = max(record.availability or 0.0, availability)
        if bitrate_kbps is not None and (record.bitrate_kbps is None or bitrate_kbps > record.bitrate_kbps):
            record.bitrate_kbps = bitrate_kbps
        if categories:
            merged = list(dict.fromkeys(record.categories + categories))
            record.categories = merged
        if source and not record.source:
            record.source = source

    def _can_reuse_locked(self, record: BrokerSessionRecord, api_password: str, now: datetime) -> bool:
        if api_password and record.api_password != api_password:
            return False
        if record.prepare_inflight:
            return True
        if record.state in BROKER_ACTIVE_STATES:
            return True
        if record.manifest_text and record.state == "ready" and not record.last_error_code and record.expires_at > now:
            return True
        if (
            record.manifest_text
            and record.state == "ready"
            and not record.last_error_code
            and record.engine_playback_url
            and record.expires_at > now - timedelta(seconds=BROKER_READY_REUSE_GRACE_SECONDS)
        ):
            return True
        if record.manifest_revalidated_until and record.manifest_revalidated_until > now:
            return True
        return False

    def get(self, session_id: str) -> Optional[BrokerSessionRecord]:
        with self._redis_lock("session", session_id):
            record = self._load_record_locked(session_id)
            if record is not None:
                self._attach_health_locked(record)
            return record

    def get_by_cid(self, cid: str) -> Optional[BrokerSessionRecord]:
        with self._redis_lock("cid", cid):
            session_id = self._load_cid_session_locked(cid)
            if not session_id:
                return None
            record = self._load_record_locked(session_id)
            if record is not None:
                self._attach_health_locked(record)
            return record

    def health_for(self, cid: str) -> Dict[str, Any]:
        with self._redis_lock("health", cid):
            history = self._load_history_locked(cid)
            if history is None:
                return CIDHealthHistory().serialize()
            return history.serialize()

    def hydrate_telemetry(self, session_id: str, telemetry: Dict[str, Any]) -> Optional[BrokerSessionRecord]:
        with self._redis_lock("session", session_id):
            record = self._load_record_locked(session_id)
            if record is None:
                return None
            record.peer_count = int(telemetry.get("peer_count", 0) or 0)
            record.download_speed_kbps = float(telemetry.get("download_speed_kbps", 0.0) or 0.0)
            record.upload_speed_kbps = float(telemetry.get("upload_speed_kbps", 0.0) or 0.0)
            record.buffer_seconds = float(telemetry.get("buffer_seconds", 0.0) or 0.0)
            telemetry_ready_segment_count = int(telemetry.get("ready_segment_count", 0) or 0)
            record.ready_segment_count = max(record.ready_segment_count, telemetry_ready_segment_count)
            record.first_segment_ready = (
                record.first_segment_ready
                or bool(telemetry.get("first_segment_ready", False))
                or record.ready_segment_count > 0
            )
            estimated = telemetry.get("estimated_startup_seconds")
            record.estimated_startup_seconds = float(estimated) if estimated is not None else None
            if telemetry.get("error"):
                record.last_error = str(telemetry["error"])
            engine_event = telemetry.get("engine_event")
            if isinstance(engine_event, dict):
                name = str(engine_event.get("name") or "event")
                params = engine_event.get("params") if isinstance(engine_event.get("params"), dict) else {}
                record.add_event(
                    name=f"engine_{name}",
                    state=record.state,
                    message="AceStream engine event received.",
                    metadata=params,
                )
                reason = str(params.get("reason") or "").strip()
                option = str(params.get("option") or "").strip()
                if name == "download_stopped" and reason == "missing_option" and option:
                    record.state = "failed"
                    record.message = "This server is missing a required AceStream service option."
                    record.last_error_code = f"missing_entitlement_{option}"
                    record.last_error = f"AceStream engine is missing required service option: {option}."
                    record.prepare_attempts = BROKER_MAX_RETRYABLE_PREPARE_ATTEMPTS
                elif name == "segmenter_failed":
                    record.state = "failed"
                    record.message = "This source is not browser-compatible."
                    record.last_error_code = "engine_segmenter_failed"
                    record.last_error = "AceStream could not segment this source into browser-compatible HLS."
                    record.prepare_attempts = BROKER_MAX_RETRYABLE_PREPARE_ATTEMPTS
                elif name == "download_stopped":
                    record.state = "retrying"
                    record.message = "The engine stopped this source. Trying one bounded recovery."
                    record.last_error_code = "engine_download_stopped"
                    record.last_error = f"AceStream stopped this source ({reason or 'unspecified reason'})."
            record.updated_at = utcnow()
            self._save_record_locked(record)
            return record

    def broker_snapshot(self) -> Dict[str, Any]:
        with self._lock:
            states: Dict[str, int] = {}
            preparing = 0
            health: Dict[str, Dict[str, Any]] = {}
            records: List[BrokerSessionRecord] = []
            if self._redis is None:
                records = list(self._sessions.values())
                health = {cid: history.serialize() for cid, history in self._cid_health.items()}
            else:
                for session_id in self._redis.smembers(self._sessions_set_key()):
                    record = self._load_record_locked(str(session_id))
                    if record is not None:
                        records.append(record)
                    else:
                        self._redis.srem(self._sessions_set_key(), session_id)
                for cid in self._redis.smembers(self._health_set_key()):
                    history = self._load_history_locked(str(cid))
                    if history is not None:
                        health[str(cid)] = history.serialize()
            for record in records:
                states[record.state] = states.get(record.state, 0) + 1
                if record.prepare_inflight:
                    preparing += 1
            return {
                "backend": self.backend_name,
                "total_sessions": len(records),
                "states": states,
                "preparing": preparing,
                "cid_health": health,
            }

    def records_snapshot(self) -> List[BrokerSessionRecord]:
        with self._lock:
            if self._redis is None:
                records = list(self._sessions.values())
            else:
                records = []
                for session_id in self._redis.smembers(self._sessions_set_key()):
                    record = self._load_record_locked(str(session_id))
                    if record is not None:
                        records.append(record)
                    else:
                        self._redis.srem(self._sessions_set_key(), session_id)
            for record in records:
                self._attach_health_locked(record)
            return records

    def get_engine_session(self, session_id: str) -> Optional[EnginePlaybackSession]:
        with self._redis_lock("session", session_id):
            record = self._load_record_locked(session_id)
            if record is None or not record.engine_playback_url:
                return None
            return EnginePlaybackSession(
                playback_url=record.engine_playback_url,
                stat_url=record.engine_stat_url or "",
                command_url=record.engine_command_url or "",
                playback_session_id=record.engine_playback_session_id or "",
                event_url=record.engine_event_url or "",
            )

    def ensure_prepare_context(self, session_id: str, reason: str, force: bool = False) -> Optional[Dict[str, str]]:
        now = utcnow()
        with self._redis_lock("session", session_id):
            record = self._load_record_locked(session_id)
            if record is None:
                return None
            if record.prepare_inflight:
                if (
                    record.last_prepare_started_at is not None
                    and (now - record.last_prepare_started_at).total_seconds() > PREPARE_INFLIGHT_STALE_SECONDS
                ):
                    record.prepare_inflight = False
                    record.add_event(
                        name="prepare_recovered",
                        state=record.state,
                        message="Stale prepare lock was cleared.",
                        metadata={"reason": reason},
                    )
                else:
                    return None

            if (
                not force
                and record.state != "ready"
                and record.prepare_attempts >= BROKER_MAX_RETRYABLE_PREPARE_ATTEMPTS
            ):
                record.prepare_inflight = False
                record.state = "failed"
                record.message = "No playable stream is available right now."
                record.manifest_text = None
                record.first_segment_url = None
                record.first_upstream_segment_url = None
                record.updated_at = now
                record.add_event(
                    name="prepare_budget_exhausted",
                    state=record.state,
                    message=record.message,
                    metadata={"reason": reason, "attempts": record.prepare_attempts},
                )
                self._save_record_locked(record)
                return None

            is_expiring = record.expires_at <= now + timedelta(seconds=BROKER_REFRESH_LEEWAY_SECONDS)
            is_stale = not cached_manifest_is_fresh(record)
            should_prepare = force or record.manifest_text is None or record.state != "ready" or is_expiring or is_stale
            if not should_prepare:
                return None
            if (
                not force
                and record.last_prepare_started_at is not None
                and (now - record.last_prepare_started_at).total_seconds() < BROKER_RETRY_COOLDOWN_SECONDS
            ):
                return None

            record.prepare_inflight = True
            record.prepare_attempts += 1
            if record.manifest_text and record.state == "ready":
                record.state = "refreshing"
                record.message = "Refreshing playable session..."
                record.refresh_attempts += 1
            else:
                record.state = "warming"
                record.message = "Looking for peers..."
            record.last_prepare_started_at = now
            record.updated_at = now
            record.add_event(
                name="prepare_started",
                state=record.state,
                message=record.message,
                metadata={"reason": reason, "attempt": record.prepare_attempts},
            )
            self._save_record_locked(record)
            return {
                "session_id": record.session_id,
                "cid": record.cid,
                "api_password": record.api_password,
                "base_proxy_url": record.manifest_url.rsplit("/proxy/acestream/session/", 1)[0],
            }

    def complete_success(
        self,
        session_id: str,
        result: ManifestPreparationResult,
        telemetry: Dict[str, Any],
        reason: str,
    ) -> Optional[BrokerSessionRecord]:
        with self._redis_lock("session", session_id):
            record = self._load_record_locked(session_id)
            if record is None:
                return None
            now = utcnow()
            record.prepare_inflight = False
            record.state = "ready"
            record.message = "Playable stream is ready."
            record.updated_at = now
            record.last_prepare_completed_at = now
            record.last_refresh_at = now
            record.expires_at = now + timedelta(seconds=BROKER_SESSION_TTL_SECONDS)
            completed_attempt = record.prepare_attempts
            record.prepare_attempts = 0
            old_engine_pid = record.engine_playback_session_id
            old_seq = extract_media_sequence(record.manifest_text)
            new_seq = extract_media_sequence(result.rewritten_manifest)
            new_engine_pid = (
                str(result.engine_session.playback_session_id or "")
                if result.engine_session is not None
                else ""
            )
            if new_seq is not None and (
                old_seq is None
                or new_seq != old_seq
                or (new_engine_pid and new_engine_pid != old_engine_pid)
            ):
                record.last_sequence_change_at = now

            record.manifest_text = result.rewritten_manifest
            record.manifest_ttfb_ms = result.manifest_ttfb_ms
            if result.engine_session is not None:
                record.engine_playback_url = result.engine_session.playback_url
                record.engine_stat_url = result.engine_session.stat_url
                record.engine_command_url = result.engine_session.command_url
                record.engine_event_url = result.engine_session.event_url
                record.engine_playback_session_id = result.engine_session.playback_session_id
                for engine_event in result.engine_session.events:
                    record.add_event(
                        name=f"engine_{engine_event.get('name') or 'event'}",
                        state=record.state,
                        message="AceStream engine event received.",
                        metadata=engine_event.get("params") if isinstance(engine_event.get("params"), dict) else {},
                    )
            record.ready_segment_count = max(result.validated_segment_count, int(telemetry.get("ready_segment_count", 0) or 0))
            record.first_segment_ready = record.ready_segment_count > 0 or bool(telemetry.get("first_segment_ready", False))
            record.first_segment_url = result.first_segment_url
            record.first_upstream_segment_url = result.first_upstream_segment_url
            record.manifest_revalidated_until = None
            record.peer_count = int(telemetry.get("peer_count", 0) or 0)
            record.download_speed_kbps = float(telemetry.get("download_speed_kbps", 0.0) or 0.0)
            record.upload_speed_kbps = float(telemetry.get("upload_speed_kbps", 0.0) or 0.0)
            record.buffer_seconds = float(telemetry.get("buffer_seconds", 0.0) or 0.0)
            estimated = telemetry.get("estimated_startup_seconds")
            record.estimated_startup_seconds = float(estimated) if estimated is not None else None
            record.last_error = None
            record.last_error_code = None
            record.add_event(
                name="prepare_succeeded",
                state=record.state,
                message="Validated manifest is ready for playback.",
                metadata={
                    "reason": reason,
                    "manifest_ttfb_ms": result.manifest_ttfb_ms,
                    "validated_segment_count": result.validated_segment_count,
                    "engine_playback_session_id": new_engine_pid,
                    "attempt": completed_attempt,
                    "cid": record.cid,
                },
            )
            history = self._history_for_locked(record.cid)
            history.record_success(
                ttfb_ms=result.manifest_ttfb_ms,
                segment_count=result.validated_segment_count,
            )
            self._save_history_locked(record.cid, history)
            self._save_record_locked(record)
            return record

    def complete_failure(
        self,
        session_id: str,
        failure: ManifestPreparationFailure,
        telemetry: Dict[str, Any],
        reason: str,
    ) -> Optional[BrokerSessionRecord]:
        with self._redis_lock("session", session_id):
            record = self._load_record_locked(session_id)
            if record is None:
                return None
            now = utcnow()
            had_cached_manifest = bool(record.manifest_text)
            exhausted_retry_budget = record.prepare_attempts >= BROKER_MAX_RETRYABLE_PREPARE_ATTEMPTS
            should_keep_retrying = failure.retryable and not exhausted_retry_budget
            record.prepare_inflight = False
            record.state = "retrying" if should_keep_retrying else "failed"
            record.message = (
                "This source is not playable yet. Trying again shortly."
                if should_keep_retrying
                else "No playable stream is available right now."
            )
            record.updated_at = now
            record.last_prepare_completed_at = now
            record.peer_count = int(telemetry.get("peer_count", 0) or 0)
            record.download_speed_kbps = float(telemetry.get("download_speed_kbps", 0.0) or 0.0)
            record.upload_speed_kbps = float(telemetry.get("upload_speed_kbps", 0.0) or 0.0)
            record.buffer_seconds = float(telemetry.get("buffer_seconds", 0.0) or 0.0)
            record.ready_segment_count = int(telemetry.get("ready_segment_count", 0) or 0)
            record.first_segment_ready = bool(telemetry.get("first_segment_ready", False))
            if failure.engine_session is not None:
                record.engine_playback_url = failure.engine_session.playback_url or record.engine_playback_url
                record.engine_stat_url = failure.engine_session.stat_url or record.engine_stat_url
                record.engine_command_url = failure.engine_session.command_url or record.engine_command_url
                record.engine_event_url = failure.engine_session.event_url or record.engine_event_url
                record.engine_playback_session_id = (
                    failure.engine_session.playback_session_id or record.engine_playback_session_id
                )
                for engine_event in failure.engine_session.events:
                    record.add_event(
                        name=f"engine_{engine_event.get('name') or 'event'}",
                        state=record.state,
                        message="AceStream engine event received.",
                        metadata=engine_event.get("params") if isinstance(engine_event.get("params"), dict) else {},
                    )
            estimated = telemetry.get("estimated_startup_seconds")
            record.estimated_startup_seconds = float(estimated) if estimated is not None else None
            record.last_error = failure.detail
            record.last_error_code = failure.error_code
            record.manifest_revalidated_until = None
            if not should_keep_retrying:
                record.manifest_text = None
                record.first_segment_url = None
                record.first_upstream_segment_url = None
            record.add_event(
                name="prepare_failed",
                state=record.state,
                message=record.message,
                metadata={
                    "reason": reason,
                    "failure_code": failure.error_code,
                    "retryable": failure.retryable,
                    "retry_budget_exhausted": exhausted_retry_budget,
                },
            )
            history = self._history_for_locked(record.cid)
            history.record_failure(
                failure.error_code,
                stale=had_cached_manifest,
            )
            self._save_history_locked(record.cid, history)
            self._save_record_locked(record)
            return record

    def mark_cached_manifest_revalidated(self, session_id: str) -> Optional[BrokerSessionRecord]:
        with self._redis_lock("session", session_id):
            record = self._load_record_locked(session_id)
            if record is None:
                return None
            now = utcnow()
            if record.manifest_text and extract_media_sequence(record.manifest_text) is not None:
                record.manifest_revalidated_until = None
            else:
                record.manifest_revalidated_until = now + timedelta(seconds=BROKER_MANIFEST_STALE_GRACE_SECONDS)
            record.updated_at = now
            record.last_error = None
            record.last_error_code = None
            record.add_event(
                name="cached_manifest_revalidated",
                state=record.state,
                message="Cached manifest segment probe succeeded.",
                metadata={"grace_seconds": BROKER_MANIFEST_STALE_GRACE_SECONDS if record.manifest_revalidated_until else 0},
            )
            self._save_record_locked(record)
            return record

    def mark_cached_manifest_stale(self, session_id: str, reason: str) -> Optional[BrokerSessionRecord]:
        with self._redis_lock("session", session_id):
            record = self._load_record_locked(session_id)
            if record is None:
                return None
            record.manifest_revalidated_until = None
            record.state = "refreshing"
            record.message = "Playable stream is being refreshed."
            record.last_error_code = reason
            record.last_error = "Cached manifest failed segment revalidation."
            record.first_segment_ready = False
            record.ready_segment_count = 0
            record.updated_at = utcnow()
            record.add_event(
                name="cached_manifest_rejected",
                state=record.state,
                message="Cached manifest was not served because segment validation failed.",
                metadata={"failure_code": reason},
            )
            history = self._history_for_locked(record.cid)
            history.record_failure(reason, stale=True)
            self._save_history_locked(record.cid, history)
            self._save_record_locked(record)
            return record


session_store = BrokerSessionStore()


def launch_background_task(target, *args) -> None:
    thread = threading.Thread(target=target, args=args, daemon=True)
    thread.start()


def kickoff_prepare(session_id: str, reason: str, force: bool = False) -> None:
    context = session_store.ensure_prepare_context(session_id, reason=reason, force=force)
    if not context:
        return
    launch_background_task(
        prepare_session_job,
        context["session_id"],
        context["cid"],
        context["api_password"],
        context["base_proxy_url"],
        reason,
    )


_prewarm_state_lock = threading.Lock()
_prewarm_state: Dict[str, Any] = {
    "enabled": PREWARM_ENABLED,
    "started": False,
    "last_started_at": None,
    "last_completed_at": None,
    "last_error": None,
    "last_candidate_count": 0,
    "last_selected_count": 0,
    "active_session_count": 0,
    "last_selected": [],
}


def normalize_prewarm_channel(raw: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    cid = str(raw.get("cid") or raw.get("infohash") or raw.get("source_id") or "").strip()
    if not cid:
        return None

    title = str(raw.get("title") or raw.get("name") or "P2P Channel").strip()
    category = str(raw.get("category") or "").strip()
    raw_categories = raw.get("categories") if isinstance(raw.get("categories"), list) else []
    categories = [str(value).strip() for value in raw_categories if str(value).strip()]
    if not category and categories:
        category = categories[0]

    try:
        availability = float(raw.get("availability") or 0.0)
    except (TypeError, ValueError):
        availability = 0.0

    try:
        bitrate_kbps = int(raw.get("bitrate_kbps") or 0)
    except (TypeError, ValueError):
        bitrate_kbps = 0

    return {
        "cid": cid,
        "title": title,
        "category": category or "sport",
        "availability": availability,
        "bitrate_kbps": bitrate_kbps,
        "categories": categories,
        "source": str(raw.get("source") or "prewarm").strip(),
    }


def fetch_prewarm_channels() -> List[Dict[str, Any]]:
    if not PREWARM_CHANNEL_SOURCE_URL:
        return []
    headers = {"Accept": "application/json"}
    if EXPECTED_API_PASSWORD:
        headers["Authorization"] = f"Bearer {EXPECTED_API_PASSWORD}"
    response = requests.get(
        PREWARM_CHANNEL_SOURCE_URL,
        headers=headers,
        timeout=PREWARM_REQUEST_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    if not isinstance(payload, list):
        return []
    channels: List[Dict[str, Any]] = []
    seen: set[str] = set()
    for item in payload:
        if not isinstance(item, dict):
            continue
        channel = normalize_prewarm_channel(item)
        if channel is None or channel["cid"] in seen:
            continue
        seen.add(channel["cid"])
        channels.append(channel)
    return channels


def parse_iso_timestamp(value: Any) -> Optional[datetime]:
    return parse_datetime(value)


def prewarm_channel_score(channel: Dict[str, Any], health: Dict[str, Any], now: Optional[datetime] = None) -> float:
    now = now or utcnow()
    cid = str(channel.get("cid") or "")
    availability = float(channel.get("availability") or 0.0)
    bitrate_kbps = int(channel.get("bitrate_kbps") or 0)
    success_count = int(health.get("success_count") or 0)
    failure_count = int(health.get("failure_count") or 0)
    score = 0.0

    if cid in PREWARM_PINNED_CIDS:
        score += 1000.0
    score += min(max(availability, 0.0), 1.0) * 100.0
    score += min(bitrate_kbps / 1000.0, 8.0)
    score += min(success_count * 18.0, 90.0)
    score -= min(failure_count * 20.0, 140.0)
    score += float(health.get("segment_success_rate") or 0.0) * 60.0

    best_ready = health.get("best_ready_ttfb_ms")
    if isinstance(best_ready, (int, float)) and best_ready > 0:
        score += max(0.0, 45.0 - (float(best_ready) / 2000.0))

    last_failure_at = parse_iso_timestamp(health.get("last_failure_at"))
    last_ready_at = parse_iso_timestamp(health.get("last_ready_at"))
    if last_failure_at and (not last_ready_at or last_failure_at > last_ready_at):
        seconds_since_failure = (now - last_failure_at).total_seconds()
        if seconds_since_failure < PREWARM_FAILED_COOLDOWN_SECONDS and cid not in PREWARM_PINNED_CIDS:
            score -= 500.0

    return score


def select_prewarm_channels(channels: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    now = utcnow()
    scored: List[Tuple[float, Dict[str, Any]]] = []
    for channel in channels:
        cid = str(channel.get("cid") or "")
        availability = float(channel.get("availability") or 0.0)
        if availability < PREWARM_MIN_AVAILABILITY and cid not in PREWARM_PINNED_CIDS:
            continue
        health = session_store.health_for(cid)
        last_ready_at = parse_iso_timestamp(health.get("last_ready_at"))
        has_recent_evidence = bool(
            int(health.get("success_count") or 0) > 0
            and last_ready_at
            and (now - last_ready_at).total_seconds() <= PREWARM_EVIDENCE_MAX_AGE_SECONDS
        )
        if cid not in PREWARM_PINNED_CIDS and not has_recent_evidence:
            continue
        score = prewarm_channel_score(channel, health, now=now)
        if score <= 0 and cid not in PREWARM_PINNED_CIDS:
            continue
        enriched = dict(channel)
        enriched["prewarm_score"] = round(score, 2)
        enriched["broker_health"] = health
        existing = session_store.get_by_cid(cid)
        if existing is not None:
            enriched["broker_state"] = existing.state
            enriched["broker_session_id"] = existing.session_id
        scored.append((score, enriched))

    scored.sort(key=lambda item: item[0], reverse=True)
    return [channel for _score, channel in scored[: max(PREWARM_LIMIT, 0)]]


def prewarm_once(reason: str = "loop") -> Dict[str, Any]:
    run_lock = session_store.try_acquire_lock("prewarm", "run", timeout=PREWARM_RUN_LOCK_SECONDS)
    if run_lock is None:
        with _prewarm_state_lock:
            _prewarm_state["last_error"] = None
        return prewarm_snapshot()

    started_at = utcnow()
    try:
        with _prewarm_state_lock:
            _prewarm_state["last_started_at"] = isoformat(started_at)
            _prewarm_state["last_error"] = None

        active_records = [
            record
            for record in session_store.records_snapshot()
            if record.state in BROKER_ACTIVE_STATES or record.prepare_inflight
        ]
        inflight_records = [record for record in active_records if record.prepare_inflight]
        start_capacity = max(PREWARM_CONCURRENT_LIMIT - len(inflight_records), 0)
        active_payload = [
            {
                "cid": record.cid,
                "title": record.title,
                "session_id": record.session_id,
                "state": record.state,
                "created": False,
                "active": True,
            }
            for record in active_records[: max(PREWARM_LIMIT, 0)]
        ]
        retry_candidates = [record for record in active_records if not record.prepare_inflight]
        active_start_count = min(len(retry_candidates), start_capacity)
        for record in retry_candidates[:active_start_count]:
            kickoff_prepare(record.session_id, reason=f"prewarm_{reason}_active", force=False)
        start_capacity = max(start_capacity - active_start_count, 0)

        if len(active_records) >= max(PREWARM_LIMIT, 0) or start_capacity <= 0:
            with _prewarm_state_lock:
                _prewarm_state["last_completed_at"] = isoformat(utcnow())
                _prewarm_state["last_candidate_count"] = 0
                _prewarm_state["last_selected_count"] = len(active_payload)
                _prewarm_state["active_session_count"] = len(active_records)
                _prewarm_state["last_selected"] = active_payload
            return prewarm_snapshot()

        remaining_slots = min(max(PREWARM_LIMIT - len(active_records), 0), start_capacity)
        channels = fetch_prewarm_channels()
        if not channels:
            raise RuntimeError("Prewarm discovery returned no candidate channels.")
        selected = select_prewarm_channels(channels)[:remaining_slots]
        selected_payload: List[Dict[str, Any]] = []
        for channel in selected:
            record, created = session_store.create(
                cid=channel["cid"],
                api_password=EXPECTED_API_PASSWORD,
                title=channel.get("title"),
                category=channel.get("category"),
                availability=channel.get("availability"),
                bitrate_kbps=channel.get("bitrate_kbps") or None,
                categories=channel.get("categories") or [],
                source=channel.get("source") or "prewarm",
                base_url=PREWARM_BASE_URL,
            )
            kickoff_prepare(record.session_id, reason=f"prewarm_{reason}", force=created)
            selected_payload.append(
                {
                    "cid": channel["cid"],
                    "title": channel.get("title"),
                    "score": channel.get("prewarm_score"),
                    "session_id": record.session_id,
                    "state": record.state,
                    "created": created,
                }
            )

        completed_at = utcnow()
        with _prewarm_state_lock:
            _prewarm_state["last_completed_at"] = isoformat(completed_at)
            _prewarm_state["last_candidate_count"] = len(channels)
            _prewarm_state["last_selected_count"] = len(selected_payload)
            _prewarm_state["active_session_count"] = len(active_records)
            _prewarm_state["last_selected"] = selected_payload
        return prewarm_snapshot()
    except Exception as exc:
        log.warning("P2P prewarm failed: %s", exc)
        with _prewarm_state_lock:
            _prewarm_state["last_completed_at"] = isoformat(utcnow())
            _prewarm_state["last_error"] = str(exc)
        return prewarm_snapshot()
    finally:
        try:
            run_lock.release()
        except Exception:
            pass


def prewarm_loop() -> None:
    while True:
        prewarm_once(reason="loop")
        time.sleep(max(PREWARM_INTERVAL_SECONDS, 5.0))


def start_prewarm_daemon_if_enabled() -> None:
    if not PREWARM_ENABLED:
        return
    if not PREWARM_CHANNEL_SOURCE_URL:
        log.warning("P2P prewarm enabled but P2P_PREWARM_CHANNEL_SOURCE_URL is not set.")
        return
    with _prewarm_state_lock:
        if _prewarm_state["started"]:
            return
        _prewarm_state["started"] = True
    launch_background_task(prewarm_loop)
    log.info("P2P prewarm daemon started.")


def prewarm_snapshot() -> Dict[str, Any]:
    with _prewarm_state_lock:
        state = dict(_prewarm_state)
    state.update(
        {
            "channel_source_url": PREWARM_CHANNEL_SOURCE_URL,
            "base_url": PREWARM_BASE_URL,
            "interval_seconds": PREWARM_INTERVAL_SECONDS,
            "limit": PREWARM_LIMIT,
            "concurrent_limit": PREWARM_CONCURRENT_LIMIT,
            "min_availability": PREWARM_MIN_AVAILABILITY,
            "failed_cooldown_seconds": PREWARM_FAILED_COOLDOWN_SECONDS,
            "evidence_max_age_seconds": PREWARM_EVIDENCE_MAX_AGE_SECONDS,
            "pinned_count": len(PREWARM_PINNED_CIDS),
        }
    )
    return state


def prepare_session_job(session_id: str, cid: str, api_password: str, base_proxy_url: str, reason: str) -> None:
    existing_engine_session = session_store.get_engine_session(session_id)
    telemetry = fetch_engine_status_snapshot(cid, existing_engine_session)
    force_restart = reason == "media_sequence_frozen"
    if force_restart:
        log.warning("Restarting Ace engine playback session for frozen media sequence session_id=%s.", session_id)

    try:
        result = prepare_manifest_material(
            cid=cid,
            api_password=api_password,
            existing_engine_session=None if force_restart else existing_engine_session,
            base_proxy_url=base_proxy_url,
        )
        telemetry = fetch_engine_status_snapshot(cid, result.engine_session)
        session_store.complete_success(session_id=session_id, result=result, telemetry=telemetry, reason=reason)
        engine_pid = (
            str(result.engine_session.playback_session_id or "")
            if result.engine_session is not None
            else ""
        )
        log.info(
            "[PREPARE_OK] session_id=%s cid=%s engine_playback_session_id=%s manifest_ttfb_ms=%s prep_reason=%s",
            session_id,
            cid,
            engine_pid or "-",
            result.manifest_ttfb_ms,
            reason,
        )
    except ManifestPreparationFailure as failure:
        telemetry = fetch_engine_status_snapshot(cid, failure.engine_session or existing_engine_session)
        session_store.complete_failure(session_id=session_id, failure=failure, telemetry=telemetry, reason=reason)
        engine_pid = ""
        if failure.engine_session is not None:
            engine_pid = str(failure.engine_session.playback_session_id or "")
        log.warning(
            "[PREPARE_FAIL] session_id=%s cid=%s engine_playback_session_id=%s code=%s prep_reason=%s",
            session_id,
            cid,
            engine_pid or "-",
            failure.error_code,
            reason,
        )
    except Exception as exc:
        log.error("Unexpected error in prepare_session_job for session %s: %s", session_id, exc, exc_info=True)
        # Ensure we don't leave the record in 'inflight' state
        with session_store._redis_lock("session", session_id):
            record = session_store._load_record_locked(session_id)
            if record:
                record.prepare_inflight = False
                session_store._save_record_locked(record)


def build_session_manifest_response(record: BrokerSessionRecord) -> Response:
    response = Response(record.manifest_text or "", status=200, mimetype="application/vnd.apple.mpegurl")
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    if record.manifest_ttfb_ms is not None:
        response.headers["X-P2P-Manifest-TTFB-Ms"] = str(record.manifest_ttfb_ms)
    response.headers["X-P2P-Session-Id"] = record.session_id
    return response


def frozen_sequence_duration_seconds(record: BrokerSessionRecord, now: Optional[datetime] = None) -> Optional[float]:
    if not record.manifest_text or record.last_sequence_change_at is None:
        return None
    if extract_media_sequence(record.manifest_text) is None:
        return None
    checked_at = now or utcnow()
    last_manifest_check_at = record.last_prepare_completed_at or record.last_refresh_at
    if (
        last_manifest_check_at is None
        or (checked_at - last_manifest_check_at).total_seconds() > max(6, BROKER_MANIFEST_FRESH_SECONDS * 2)
    ):
        return None
    frozen_duration = (checked_at - record.last_sequence_change_at).total_seconds()
    return frozen_duration if frozen_duration > FROZEN_SEQUENCE_RESTART_SECONDS else None


def wait_for_refreshed_manifest(
    session_id: str,
    previous_sequence: Optional[int],
    previous_engine_pid: Optional[str],
    timeout_seconds: float = 6.0,
) -> Optional[BrokerSessionRecord]:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        refreshed = session_store.get(session_id)
        if (
            refreshed is not None
            and refreshed.manifest_text
            and refreshed.state == "ready"
            and not refreshed.prepare_inflight
        ):
            refreshed_sequence = extract_media_sequence(refreshed.manifest_text)
            engine_changed = bool(refreshed.engine_playback_session_id and refreshed.engine_playback_session_id != previous_engine_pid)
            sequence_changed = refreshed_sequence is not None and refreshed_sequence != previous_sequence
            if engine_changed or sequence_changed or cached_manifest_is_fresh(refreshed):
                return refreshed
        time.sleep(0.2)
    return None


def cached_manifest_is_fresh(record: BrokerSessionRecord) -> bool:
    now = utcnow()
    if not record.manifest_text:
        return False
    media_sequence = extract_media_sequence(record.manifest_text)
    if frozen_sequence_duration_seconds(record, now) is not None:
        return False
    if media_sequence is None and record.manifest_revalidated_until and record.manifest_revalidated_until > now:
        return True
    if record.state != "ready" or record.expires_at <= now:
        return False
    if record.last_prepare_completed_at is None:
        return False
    manifest_age = (now - record.last_prepare_completed_at).total_seconds()
    return manifest_age <= BROKER_MANIFEST_FRESH_SECONDS


def upstream_segment_url_for_cached_manifest(record: BrokerSessionRecord) -> Optional[str]:
    if record.first_upstream_segment_url:
        return record.first_upstream_segment_url
    if not record.first_segment_url:
        return None
    parsed = urlparse(record.first_segment_url)
    values = parse_qs(parsed.query).get("url")
    if not values:
        return None
    return values[0]


def revalidate_cached_manifest(record: BrokerSessionRecord) -> Tuple[bool, str]:
    upstream_segment_url = upstream_segment_url_for_cached_manifest(record)
    if not upstream_segment_url:
        return False, "cached_manifest_missing_segment"
    base_proxy_url = record.manifest_url.rsplit("/proxy/acestream/session/", 1)[0]
    probe = probe_segment_for_manifest(
        upstream_segment_url,
        cid=record.cid,
        base_proxy_url=base_proxy_url,
        api_password=record.api_password,
    )
    return probe.failure_class == "ok", probe.failure_class


def _scraper_public_meta() -> tuple[int, Optional[str], Optional[str]]:
    """Channel count and timestamps consistent across Gunicorn workers (Redis-backed)."""
    matches = snapshot_scraper_matches()
    count = len(matches)
    updated: Optional[str] = _scraper_last_updated
    err: Optional[str] = _scraper_last_refresh_error
    redis_client = session_store.get_redis_client()
    if redis_client:
        try:
            raw = redis_client.get("scraper:matches_meta")
            if raw:
                meta = json.loads(raw)
                updated = meta.get("last_updated") or updated
                if "last_refresh_error" in meta:
                    err = meta["last_refresh_error"]
        except Exception:
            pass
    return count, updated, err


@app.get("/health")
def health() -> Response:
    config_error = upstream_config_error()
    scraper_count, scraper_last_updated, scraper_last_refresh_error = _scraper_public_meta()
    return jsonify(
        {
            "status": "misconfigured" if config_error else "ok",
            "upstream": UPSTREAM_BASE_URL,
            "upstream_kind": UPSTREAM_KIND,
            "config_error": config_error,
            "manifest_timeout_seconds": MANIFEST_TIMEOUT_SECONDS,
            "engine_session_create_timeout_seconds": ENGINE_SESSION_CREATE_TIMEOUT_SECONDS,
            "engine_warmup_timeout_seconds": ENGINE_WARMUP_TIMEOUT_SECONDS,
            "segment_timeout_seconds": SEGMENT_TIMEOUT_SECONDS,
            "service_token_enabled": bool(EXPECTED_SERVICE_TOKEN_ID and EXPECTED_SERVICE_TOKEN_SECRET),
            "broker_session_ttl_seconds": BROKER_SESSION_TTL_SECONDS,
            "broker_retry_cooldown_seconds": BROKER_RETRY_COOLDOWN_SECONDS,
            "broker_max_retryable_prepare_attempts": BROKER_MAX_RETRYABLE_PREPARE_ATTEMPTS,
            "broker_manifest_fresh_seconds": BROKER_MANIFEST_FRESH_SECONDS,
            "broker_manifest_stale_grace_seconds": BROKER_MANIFEST_STALE_GRACE_SECONDS,
            "broker_store_backend": session_store.backend_name,
            "redis_enabled": session_store.backend_name == "redis",
            "prewarm_enabled": PREWARM_ENABLED,
            "prewarm_started": prewarm_snapshot()["started"],
            "prewarm_interval_seconds": PREWARM_INTERVAL_SECONDS,
            "prewarm_limit": PREWARM_LIMIT,
            "prewarm_concurrent_limit": PREWARM_CONCURRENT_LIMIT,
            "scraper_count": scraper_count,
            "scraper_last_updated": scraper_last_updated,
            "scraper_last_refresh_error": scraper_last_refresh_error,
        }
    )


@app.get("/metrics")
def get_metrics() -> Response:
    access_failure = validate_operator_access()
    if access_failure:
        return access_failure
    payload = metrics.snapshot()
    payload["broker"] = session_store.broker_snapshot()
    service_options = {"proxyServer": "unknown", "noAds": "unknown", "premium": "unknown"}
    event_counts: Dict[str, int] = {}
    last_codec_info: Dict[str, Any] = {}
    for record in session_store.records_snapshot():
        error_code = str(record.last_error_code or "")
        if error_code.startswith("missing_entitlement_"):
            option = error_code.removeprefix("missing_entitlement_")
            if option in service_options:
                service_options[option] = "missing"
        for event in record.events:
            if not event.name.startswith("engine_"):
                continue
            engine_event_name = event.name.removeprefix("engine_")
            event_counts[engine_event_name] = event_counts.get(engine_event_name, 0) + 1
            if engine_event_name == "got_codec_info":
                last_codec_info = {
                    key: value
                    for key, value in event.metadata.items()
                    if key in {"audio_codec_id", "video_codec_id"}
                }
    payload["engine"] = {
        "version": get_engine_version(),
        "service_options": service_options,
        "event_counts": event_counts,
        "last_codec_info": last_codec_info,
    }
    return jsonify(payload)


_LIVE_DASHBOARD_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Fotty P2P — live</title>
<style>
:root { --bg:#0d1117; --card:#161b22; --bd:#30363d; --tx:#e6edf3; --muted:#8b949e; --ok:#3fb950; --warn:#d29922; --bad:#f85149; --accent:#58a6ff; }
* { box-sizing: border-box; }
body { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; margin:0; padding:12px;
  background:var(--bg); color:var(--tx); font-size:13px; line-height:1.4; }
h1 { font-size:15px; font-weight:600; margin:0 0 10px; color:var(--accent); }
.row { display:flex; flex-wrap:wrap; gap:8px; margin-bottom:10px; align-items:center; }
.pill { background:var(--card); border:1px solid var(--bd); padding:4px 10px; border-radius:6px; color:var(--muted); }
.pill b { color:var(--tx); }
.grid { display:grid; grid-template-columns: repeat(auto-fill, minmax(160px,1fr)); gap:8px; margin-bottom:14px; }
.card { background:var(--card); border:1px solid var(--bd); border-radius:8px; padding:10px 12px; }
.card .k { color:var(--muted); font-size:11px; text-transform:uppercase; letter-spacing:.04em; }
.card .v { font-size:18px; font-weight:600; margin-top:4px; word-break:break-all; }
.card .v.ok { color:var(--ok); } .card .v.warn { color:var(--warn); } .card .v.bad { color:var(--bad); }
table { width:100%; border-collapse:collapse; font-size:12px; }
th, td { text-align:left; padding:6px 8px; border-bottom:1px solid var(--bd); }
th { color:var(--muted); font-weight:600; }
tr:hover td { background:#1c2128; }
.cid { max-width:120px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.err { color:var(--bad); margin-top:8px; }
</style>
</head>
<body>
<h1>Fotty P2P broker — live</h1>
<div class="row"><span class="pill">Updated <b id="ts">—</b></span><span class="pill">Interval <b>1.5s</b></span>
<span class="pill" id="lat"></span></div>
<div id="err" class="err" style="display:none"></div>
<div class="grid" id="cards"></div>
<div class="card" style="margin-bottom:10px"><div class="k">Session states</div><pre id="states" style="margin:8px 0 0;white-space:pre-wrap;color:var(--muted)"></pre></div>
<div class="card"><div class="k">CID health (worst first, top 15)</div>
<table><thead><tr><th>CID</th><th>Score</th><th>Seg OK</th><th>Fails</th><th>Last err</th></tr></thead><tbody id="tbody"></tbody></table></div>
<script>
(function(){
  var q = window.location.search || '';
  function esc(s){ return (s==null?'':String(s)).replace(/&/g,'&amp;').replace(/</g,'&lt;'); }
  function pill(v, cls){ return '<div class="card"><div class="k">' + esc(v.k) + '</div><div class="v ' + (cls||'') + '">' + esc(v.v) + '</div></div>'; }
  async function tick(){
    var t0 = performance.now();
    document.getElementById('err').style.display = 'none';
    try {
      var rh = fetch('/health' + q).then(function(r){ return r.json(); });
      var rm = fetch('/metrics' + q).then(function(r){ return r.json(); });
      var h = await rh;
      var m = await rm;
      var br = m.broker || {};
      var ms = Date.now();
      document.getElementById('ts').textContent = new Date(ms).toLocaleTimeString();
      document.getElementById('lat').innerHTML = 'Fetch <b>' + Math.round(performance.now()-t0) + ' ms</b>';
      var st = h.status === 'ok' && !h.config_error ? 'ok' : 'bad';
      var cards = [];
      cards.push({k:'Status', v: h.config_error ? 'misconfigured' : h.status, cls: st==='ok'?'ok':'bad'});
      cards.push({k:'Upstream', v: (h.upstream_kind||'') + ' ' + (h.upstream||'')});
      cards.push({k:'Redis', v: h.redis_enabled ? 'on' : 'off', cls: h.redis_enabled?'ok':'warn'});
      cards.push({k:'Scraper channels', v: String(h.scraper_count != null ? h.scraper_count : '—')});
      cards.push({k:'Scraper error', v: h.scraper_last_refresh_error || 'none', cls: h.scraper_last_refresh_error?'bad':'ok'});
      cards.push({k:'Manifest req / fail', v: (m.manifest_requests||0) + ' / ' + (m.manifest_failures||0)});
      cards.push({k:'Seg 2xx rate', v: String(m.segment_2xx_rate != null ? m.segment_2xx_rate : '—'),
        cls: (m.segment_2xx_rate >= 0.98 || !m.segment_requests) ? 'ok' : 'warn'});
      cards.push({k:'Manifest TTFB avg / p95', v: (m.manifest_ttfb_ms_avg||0) + ' / ' + (m.manifest_ttfb_ms_p95||0) + ' ms'});
      cards.push({k:'Segment req', v: String(m.segment_requests||0)});
      cards.push({k:'Broker sessions', v: String(br.total_sessions != null ? br.total_sessions : '—')});
      cards.push({k:'Preparing', v: String(br.preparing != null ? br.preparing : '—')});
      cards.push({k:'Prewarm', v: h.prewarm_enabled ? 'on' : 'off'});
      document.getElementById('cards').innerHTML = cards.map(function(c){ return pill(c, c.cls); }).join('');
      document.getElementById('states').textContent = JSON.stringify(br.states || {}, null, 0);
      var health = br.cid_health || {};
      var rows = Object.keys(health).map(function(cid){
        var x = health[cid] || {};
        var rate = x.segment_success_rate;
        var sr = rate != null ? rate : (x.segment_success_count||0) + '/' + ((x.segment_success_count||0)+(x.segment_failure_count||0));
        return { cid: cid, score: x.score, sr: sr, fc: x.failure_count||0, le: x.last_failure_code||'' };
      });
      rows.sort(function(a,b){ return (b.fc - a.fc) || ((a.score!=null&&b.score!=null)?(a.score-b.score):0); });
      rows = rows.slice(0, 15);
      document.getElementById('tbody').innerHTML = rows.map(function(r){
        var c = r.cid || '';
        var cs = c.length > 12 ? c.substring(0,10) + '…' : c;
        return '<tr><td class="cid" title="'+esc(c)+'">'+esc(cs)+'</td><td>'+esc(r.score)+'</td><td>'+esc(r.sr)+'</td><td>'+esc(r.fc)+'</td><td>'+esc(r.le)+'</td></tr>';
      }).join('') || '<tr><td colspan="5" style="color:var(--muted)">No CID history yet</td></tr>';
    } catch(e) {
      document.getElementById('err').style.display = 'block';
      document.getElementById('err').textContent = 'Refresh failed: ' + e;
    }
  }
  setInterval(tick, 1500);
  tick();
})();
</script>
</body>
</html>"""


@app.get("/dashboard")
def live_dashboard() -> Response:
    if not DASHBOARD_ENABLED:
        return Response("Dashboard disabled (P2P_DASHBOARD_ENABLED).", 404, mimetype="text/plain")
    access_failure = validate_operator_access()
    if access_failure:
        return access_failure
    return Response(_LIVE_DASHBOARD_HTML, mimetype="text/html; charset=utf-8")


def handle_direct_manifest_request() -> Tuple[Response, int] | Response:
    service_token_failure = validate_service_token()
    if service_token_failure:
        return service_token_failure

    cid = request_cid()
    stream_token = request_public_stream_token()
    api_password = resolve_playback_api_password(cid)

    if not cid:
        return jsonify(
            {
                "error": "stream_unavailable",
                "code": "missing_cid",
                "cid": "unknown",
                "detail": "Missing query parameter: id or infohash",
            }
        ), 400

    if EXPECTED_API_PASSWORD and api_password != EXPECTED_API_PASSWORD:
        return jsonify(
            {
                "error": "stream_unavailable",
                "code": "auth_failed",
                "cid": cid,
                "detail": "Invalid api_password",
            }
        ), 403

    config_failure = runtime_config_error_response()
    if config_failure:
        return config_failure

    try:
        result = prepare_manifest_material(
            cid=cid,
            api_password=api_password,
            public_stream_token=stream_token if verify_public_stream_token(stream_token, cid) else None,
        )
    except ManifestPreparationFailure as failure:
        return manifest_failure_response(failure)

    response = Response(result.rewritten_manifest, status=200, mimetype="application/vnd.apple.mpegurl")
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["X-P2P-Manifest-TTFB-Ms"] = str(result.manifest_ttfb_ms)
    return response


@app.get("/proxy/acestream/stream")
def proxy_acestream_stream() -> Tuple[Response, int] | Response:
    return handle_direct_manifest_request()


@app.get("/proxy/acestream/manifest.m3u8")
def proxy_acestream_manifest() -> Tuple[Response, int] | Response:
    session_id = request.args.get("session_id", "").strip()
    if session_id:
        return proxy_acestream_session_manifest(session_id)
    return handle_direct_manifest_request()


@app.post("/proxy/acestream/session")
def create_broker_session() -> Tuple[Response, int] | Response:
    service_token_failure = validate_service_token()
    if service_token_failure:
        return service_token_failure

    payload = request.get_json(silent=True) or {}
    cid = str(payload.get("cid") or payload.get("infohash") or request_cid()).strip()
    api_password = str(payload.get("api_password") or request_api_password()).strip()

    if not cid:
        return jsonify({"error": "missing_cid", "detail": "Missing cid or infohash."}), 400

    if EXPECTED_API_PASSWORD and api_password != EXPECTED_API_PASSWORD:
        return jsonify({"error": "auth_failed", "detail": "Invalid api_password."}), 403

    config_failure = runtime_config_error_response()
    if config_failure:
        return config_failure

    raw_categories = payload.get("categories") or []
    categories = [str(value).strip() for value in raw_categories if str(value).strip()] if isinstance(raw_categories, list) else []
    force_new = str(payload.get("force_new") or payload.get("forceNew") or "").strip().lower() in {"1", "true", "yes", "on"}
    availability_raw = payload.get("availability")
    bitrate_raw = payload.get("bitrate_kbps")
    try:
        availability = float(availability_raw) if availability_raw is not None else None
    except (TypeError, ValueError):
        availability = None
    try:
        bitrate_kbps = int(bitrate_raw) if bitrate_raw is not None else None
    except (TypeError, ValueError):
        bitrate_kbps = None

    record, created = session_store.create(
        cid=cid,
        api_password=api_password,
        title=str(payload.get("title")).strip() if payload.get("title") is not None else None,
        category=str(payload.get("category")).strip() if payload.get("category") is not None else None,
        availability=availability,
        bitrate_kbps=bitrate_kbps,
        categories=categories,
        source=str(payload.get("source")).strip() if payload.get("source") is not None else None,
        base_url=request_base_url(),
        force_new=force_new,
    )
    kickoff_prepare(record.session_id, reason="create" if created else "cid_reuse", force=created)
    return jsonify(record.serialize()), 202


@app.get("/proxy/acestream/session/<session_id>/status")
def proxy_acestream_session_status(session_id: str) -> Tuple[Response, int] | Response:
    service_token_failure = validate_service_token()
    if service_token_failure:
        return service_token_failure

    api_password = request_api_password()
    record = session_store.get(session_id)
    if record is None:
        return jsonify({"error": "session_not_found", "detail": "Unknown broker session."}), 404
    if EXPECTED_API_PASSWORD and api_password and api_password != record.api_password:
        return jsonify({"error": "auth_failed", "detail": "Invalid api_password."}), 403

    config_failure = runtime_config_error_response()
    if config_failure:
        return config_failure

    telemetry = fetch_engine_status_snapshot(record.cid, session_store.get_engine_session(session_id))
    record = session_store.hydrate_telemetry(session_id, telemetry) or record
    kickoff_prepare(session_id, reason="status_poll", force=False)
    return jsonify(record.serialize())


@app.get("/proxy/acestream/session/<session_id>/events")
def proxy_acestream_session_events(session_id: str) -> Tuple[Response, int] | Response:
    service_token_failure = validate_service_token()
    if service_token_failure:
        return service_token_failure

    record = session_store.get(session_id)
    if record is None:
        return jsonify({"error": "session_not_found", "detail": "Unknown broker session."}), 404
    return jsonify({"session_id": session_id, "events": [event.serialize() for event in record.events]})


@app.get("/proxy/acestream/session/<session_id>/manifest.m3u8")
def proxy_acestream_session_manifest(session_id: str) -> Tuple[Response, int] | Response:
    try:
        service_token_failure = validate_service_token()
        if service_token_failure:
            return service_token_failure

        api_password = request_api_password()
        record = session_store.get(session_id)
        if record is None:
            return jsonify({"error": "session_not_found", "detail": "Unknown broker session."}), 404
        if EXPECTED_API_PASSWORD and api_password and api_password != record.api_password:
            return jsonify({"error": "auth_failed", "detail": "Invalid api_password."}), 403

        config_failure = runtime_config_error_response()
        if config_failure:
            return config_failure

        if record.manifest_text:
            if cached_manifest_is_fresh(record):
                return build_session_manifest_response(record)

            frozen_duration = frozen_sequence_duration_seconds(record)
            if frozen_duration is not None:
                previous_sequence = extract_media_sequence(record.manifest_text)
                previous_engine_pid = record.engine_playback_session_id
                log.warning(
                    "Cached manifest sequence frozen session_id=%s cid=%s duration=%.1fs; forcing refresh.",
                    session_id,
                    getattr(record, "cid", None),
                    frozen_duration,
                )
                stale_record = session_store.mark_cached_manifest_stale(session_id, "media_sequence_frozen") or record
                kickoff_prepare(session_id, reason="media_sequence_frozen", force=True)
                refreshed_record = wait_for_refreshed_manifest(
                    session_id,
                    previous_sequence=previous_sequence,
                    previous_engine_pid=previous_engine_pid,
                )
                if refreshed_record is not None:
                    return build_session_manifest_response(refreshed_record)
                payload = stale_record.serialize()
                payload.update(
                    {
                        "error": "stream_unavailable",
                        "code": "media_sequence_frozen",
                        "detail": "The live playlist stopped advancing and is being refreshed.",
                    }
                )
                return jsonify(payload), 503

            try:
                revalidated, revalidation_reason = revalidate_cached_manifest(record)
            except Exception as exc:
                log.warning(
                    "Cached manifest revalidation errored session_id=%s cid=%s exc=%s",
                    session_id,
                    getattr(record, "cid", None),
                    exc,
                )
                revalidated = False
                revalidation_reason = "cached_manifest_revalidation_error"

            if revalidated:
                refreshed = session_store.mark_cached_manifest_revalidated(session_id) or record
                kickoff_prepare(session_id, reason="manifest_background_refresh", force=False)
                return build_session_manifest_response(refreshed)

            stale_record = session_store.mark_cached_manifest_stale(session_id, revalidation_reason) or record
            kickoff_prepare(session_id, reason=f"cached_manifest_{revalidation_reason}", force=False)
            payload = stale_record.serialize()
            payload.update(
                {
                    "error": "stream_unavailable",
                    "code": revalidation_reason,
                    "detail": "The stream is still preparing.",
                }
            )
            return jsonify(payload), 503

        # If we have no cached manifest yet, give the background prepare a brief
        # chance to populate it before returning 503. This reduces "multiple tries"
        # failures when the engine is slow but about to become ready.
        kickoff_prepare(session_id, reason="manifest_wait", force=False)

        deadline = time.time() + 2.0
        polled = record
        while time.time() < deadline:
            polled = session_store.get(session_id) or polled
            if getattr(polled, "manifest_text", None):
                return build_session_manifest_response(polled)
            time.sleep(0.15)

        record = polled
        payload = record.serialize()
        payload.update(
            {
                "error": "stream_unavailable",
                "code": record.last_error_code or "session_not_ready",
                "detail": record.last_error or "The stream is still preparing.",
            }
        )
        try:
            print(
                f"[MANIFEST] 503 session_id={session_id} cid={getattr(record, 'cid', None)} code={record.last_error_code} detail={(record.last_error or '')[:160]}",
                flush=True,
            )
        except Exception:
            pass
        return jsonify(payload), 503
    except Exception as e:
        import traceback
        tb = traceback.format_exc()
        log.error(f"[SERVER-ERROR] Manifest proxy failed: {e}\n{tb}")
        return jsonify({"error": "server_error", "detail": str(e)}), 500


@app.get("/proxy/acestream/status")
def proxy_acestream_status() -> Tuple[Response, int] | Response:
    service_token_failure = validate_service_token()
    if service_token_failure:
        return service_token_failure

    api_password = request_api_password()
    if EXPECTED_API_PASSWORD and api_password != EXPECTED_API_PASSWORD:
        return jsonify({"detail": "Could not validate credentials"}), 403

    session_id = request.args.get("session_id", "").strip()
    if session_id:
        return proxy_acestream_session_status(session_id)

    cid = request_cid()
    if not cid:
        return jsonify({"status": "ok", "enabled": True, "metrics": metrics.snapshot(), "broker": session_store.broker_snapshot()})

    telemetry = fetch_engine_status_snapshot(cid)
    normalized = {
        "source_id": cid,
        "state": "ready" if telemetry["ready_segment_count"] > 0 else "warming",
        "peer_count": telemetry["peer_count"],
        "download_speed_kbps": telemetry["download_speed_kbps"],
        "upload_speed_kbps": telemetry["upload_speed_kbps"],
        "buffer_seconds": telemetry["buffer_seconds"],
        "ready_segment_count": telemetry["ready_segment_count"],
        "first_segment_ready": telemetry["first_segment_ready"],
        "estimated_startup_seconds": telemetry["estimated_startup_seconds"],
        "first_segment_url": None,
        "last_error": telemetry.get("error"),
        "updated_at": isoformat(utcnow()),
    }
    return jsonify(normalized)


@app.get("/proxy/acestream/prewarm")
def proxy_acestream_prewarm_status() -> Tuple[Response, int] | Response:
    service_token_failure = validate_service_token()
    if service_token_failure:
        return service_token_failure

    api_password = request_api_password()
    if EXPECTED_API_PASSWORD and api_password != EXPECTED_API_PASSWORD:
        return jsonify({"detail": "Could not validate credentials"}), 403

    return jsonify({"status": "ok", "prewarm": prewarm_snapshot(), "broker": session_store.broker_snapshot()})


@app.post("/proxy/acestream/prewarm")
def proxy_acestream_prewarm_trigger() -> Tuple[Response, int] | Response:
    service_token_failure = validate_service_token()
    if service_token_failure:
        return service_token_failure

    api_password = request_api_password()
    if EXPECTED_API_PASSWORD and api_password != EXPECTED_API_PASSWORD:
        return jsonify({"detail": "Could not validate credentials"}), 403

    return jsonify({"status": "ok", "prewarm": prewarm_once(reason="manual")})


@app.get("/ace/proxy")
def proxy_segment() -> Tuple[Response, int] | Response:
    service_token_failure = validate_service_token()
    if service_token_failure:
        return service_token_failure

    upstream_url = request.args.get("url", "").strip()
    cid = request.args.get("cid", "").strip() or "unknown"
    api_password = resolve_playback_api_password(cid)
    if not upstream_url:
        metrics.record_segment(status_code=400)
        return jsonify({"error": "missing_url"}), 400

    if EXPECTED_API_PASSWORD and api_password != EXPECTED_API_PASSWORD:
        metrics.record_segment(status_code=403)
        return jsonify({"error": "auth_failed", "cid": cid, "detail": "Invalid stream token."}), 403

    if not is_allowed_segment_upstream_url(upstream_url):
        metrics.record_segment(status_code=403)
        log.warning("Blocked segment proxy target cid=%s url=%s", cid, upstream_url[:200])
        return jsonify({"error": "upstream_not_allowed", "cid": cid}), 403

    range_header = request.headers.get("Range", "")
    upstream_headers = {"Range": range_header} if range_header else None

    try:
        upstream_response = requests.get(
            upstream_url,
            stream=True,
            timeout=(5, SEGMENT_TIMEOUT_SECONDS),
            headers=upstream_headers,
        )
    except requests.Timeout:
        metrics.record_segment(status_code=503)
        metrics.record_manifest(ttfb_ms=0, success=False, cid=cid, reason="segment_timeout")
        try:
            log.warning("Segment proxy timeout cid=%s url=%s", cid, upstream_url[:200])
        except Exception:
            pass
        try:
            print(f"[SEGMENT] timeout cid={cid} url={upstream_url[:200]}", flush=True)
        except Exception:
            pass
        return jsonify({"error": "segment_timeout", "cid": cid}), 503
    except requests.RequestException as exc:
        metrics.record_segment(status_code=503)
        metrics.record_manifest(ttfb_ms=0, success=False, cid=cid, reason="segment_proxy_error")
        try:
            log.warning("Segment proxy request error cid=%s url=%s exc=%s", cid, upstream_url[:200], exc)
        except Exception:
            pass
        try:
            print(f"[SEGMENT] request_error cid={cid} url={upstream_url[:200]} exc={exc}", flush=True)
        except Exception:
            pass
        return jsonify({"error": "segment_proxy_error", "cid": cid, "detail": str(exc)}), 503
    except Exception as exc:
        metrics.record_segment(status_code=500)
        log.exception("[SERVER-ERROR] Segment fetch failed cid=%s url=%s", cid, upstream_url[:200])
        return jsonify({"error": "server_error", "detail": str(exc)}), 500

    status_code = upstream_response.status_code
    metrics.record_segment(status_code=status_code)

    # Special case: Ace engine can briefly return "download not found" for the first segment
    # even though the session is about to become valid. A tiny retry here avoids "multiple tries"
    # while still allowing us to hard-restart when it persists.
    if status_code == 500:
        try:
            body_prefix = (upstream_response.content or b"")[:256].decode("utf-8", "ignore").lower()
        except Exception:
            body_prefix = ""

        if "download not found" in body_prefix:
            upstream_response.close()
            last_body_prefix = body_prefix
            for attempt in range(1, 4):
                time.sleep(0.25 * attempt)
                try:
                    upstream_response = requests.get(
                        upstream_url,
                        stream=True,
                        timeout=(5, SEGMENT_TIMEOUT_SECONDS),
                        headers=upstream_headers,
                    )
                except Exception:
                    upstream_response = None
                    break

                status_code = upstream_response.status_code
                if 200 <= status_code <= 299:
                    break

                if status_code == 500:
                    try:
                        last_body_prefix = (upstream_response.content or b"")[:256].decode("utf-8", "ignore").lower()
                    except Exception:
                        last_body_prefix = ""
                    if "download not found" in last_body_prefix:
                        upstream_response.close()
                        continue

                break

            if upstream_response is None:
                metrics.record_manifest(ttfb_ms=0, success=False, cid=cid, reason="segment_retry_failed")
                return jsonify({"error": "segment_proxy_error", "cid": cid, "detail": "retry_failed"}), 503

            if status_code == 500 and "download not found" in (last_body_prefix or ""):
                metrics.record_manifest(ttfb_ms=0, success=False, cid=cid, reason="segment_download_not_found")
                try:
                    record = session_store.get_by_cid(cid)
                    if record is not None:
                        kickoff_prepare(record.session_id, reason="segment_download_not_found", force=True)
                except Exception:
                    pass
                try:
                    log.warning("Segment download not found cid=%s url=%s", cid, upstream_url[:200])
                except Exception:
                    pass
                try:
                    print(f"[SEGMENT] download_not_found cid={cid} url={upstream_url[:200]}", flush=True)
                except Exception:
                    pass
                upstream_response.close()
                resp = jsonify({"error": "segment_unavailable", "cid": cid, "detail": "download_not_found"})
                try:
                    resp.headers["Retry-After"] = "1"
                except Exception:
                    pass
                return resp, 503

    if status_code < 200 or status_code > 299:
        metrics.record_manifest(ttfb_ms=0, success=False, cid=cid, reason=f"segment_{status_code}")
        if status_code == 503:
            try:
                body_prefix = (upstream_response.content or b"")[:256].decode("utf-8", "ignore").lower()
            except Exception:
                body_prefix = ""
            try:
                log.warning("Segment upstream 503 cid=%s url=%s body=%s", cid, upstream_url[:200], body_prefix[:120])
            except Exception:
                pass
            try:
                print(
                    f"[SEGMENT] upstream_503 cid={cid} url={upstream_url[:200]} body={body_prefix[:120]}",
                    flush=True,
                )
            except Exception:
                pass

        # For other upstream failures, only nudge refresh on hard "lost state" signals.
        # For 503s, forcing restarts can create a thrash loop while the engine is transiently unhealthy.
        if status_code in {404, 500}:
            try:
                record = session_store.get_by_cid(cid)
                if record is not None:
                    kickoff_prepare(record.session_id, reason=f"segment_http_{status_code}", force=True)
            except Exception:
                pass

    def generate():
        try:
            for chunk in upstream_response.iter_content(chunk_size=64 * 1024):
                if chunk:
                    yield chunk
        finally:
            upstream_response.close()

    try:
        response = Response(stream_with_context(generate()), status=status_code)
        content_type = upstream_response.headers.get("Content-Type")
        content_length = upstream_response.headers.get("Content-Length")
        accept_ranges = upstream_response.headers.get("Accept-Ranges")
        content_range = upstream_response.headers.get("Content-Range")
        if cid.lower() != "unknown" or upstream_url.endswith(".ts"):
            response.headers["Content-Type"] = "video/mp2t"
        elif content_type:
            response.headers["Content-Type"] = content_type
        
        if content_length:
            response.headers["Content-Length"] = content_length
        if accept_ranges:
            response.headers["Accept-Ranges"] = accept_ranges
        if content_range:
            response.headers["Content-Range"] = content_range
        response.headers["Cache-Control"] = "no-store"
        return response
    except Exception as e:
        import traceback
        tb = traceback.format_exc()
        log.error(f"[SERVER-ERROR] Segment proxy failed: {e}\n{tb}")
        return jsonify({"error": "server_error", "detail": str(e)}), 500


@app.get("/matches")
@app.get("/status")
def get_matches() -> Any:
    access_failure = validate_service_token()
    if access_failure:
        return access_failure
    return jsonify(snapshot_scraper_matches())


@app.get("/search/<path:query>")
def search_discover(query: str) -> Any:
    access_failure = validate_service_token()
    if access_failure:
        return access_failure
    decoded = unquote(query).strip()
    if not decoded:
        return jsonify([])
    token = get_engine_token()
    if not token:
        return jsonify([])
    results = search_engine(decoded, token=token, page_size=120)
    return jsonify(flatten_scraper_results(results))


def start_scraper_daemon_singleton():
    # Ensure only ONE worker runs the background logic in a multi-worker environment
    def run_singleton():
        # Access the redis client from the session store
        redis_client = getattr(session_store, '_redis', None)
        if not redis_client:
            log.warning("Redis client unavailable for scraper lock. Falling back to simple daemon.")
            scraper_refresh_loop()
            return

        lock_key = "fotty_p2p_scraper_lock"
        # Using a blocking lock with a long timeout
        lock = redis_client.lock(lock_key, timeout=SCRAPER_REFRESH_SECONDS * 2)
        if lock.acquire(blocking=False):
            log.info("Acquired scraper singleton lock. Starting background loop.")
            try:
                scraper_refresh_loop()
            finally:
                lock.release()
        else:
            log.debug("Another worker is already running the scraper. Skipping.")

    # Start the check thread
    threading.Thread(target=run_singleton, daemon=True).start()

start_scraper_daemon_singleton()

@app.route('/log', methods=['POST'])
def client_log():
    try:
        data = request.get_json()
        msg = data.get('msg', '')
        level = data.get('level', 'INFO')
        # Log to both flask and our custom logger
        log.info(f"[CLIENT-{level}] {msg}")
        return jsonify({"status": "ok"}), 200
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400

@app.before_request
def log_request_info():
    request.start_time = time.perf_counter()

@app.after_request
def log_response_info(response):
    if hasattr(request, 'start_time'):
        duration = int((time.perf_counter() - request.start_time) * 1000)
        log.info(f"REQUEST: {request.method} {request.path} | STATUS: {response.status_code} | DURATION: {duration}ms")
    return response

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8006))
    app.run(host="0.0.0.0", port=port, debug=False)
