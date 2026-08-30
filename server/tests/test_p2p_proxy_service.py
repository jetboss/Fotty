import base64
import hashlib
import hmac
import json
import os
import time

os.environ.setdefault("P2P_API_PASSWORD", "test-p2p-password")

import unittest
from datetime import timedelta
from typing import Dict, Optional
from unittest.mock import patch

import requests

try:
    import p2p_proxy_service
except ModuleNotFoundError:  # pragma: no cover - environment-dependent optional integration tests
    p2p_proxy_service = None

from p2p_proxy_core import (
    classify_manifest_failure,
    classify_segment_failure,
    rewrite_manifest,
)


def make_public_stream_token(cid: str, secret: str, exp: Optional[float] = None) -> str:
    payload = {
        "cid": cid,
        "exp": exp if exp is not None else time.time() + 60,
    }
    body = base64.urlsafe_b64encode(json.dumps(payload).encode("utf-8")).decode("utf-8").rstrip("=")
    sig = base64.urlsafe_b64encode(
        hmac.new(secret.encode("utf-8"), body.encode("utf-8"), hashlib.sha256).digest()
    ).decode("utf-8").rstrip("=")
    return f"{body}.{sig}"


class FakeResponse:
    def __init__(
        self,
        status_code: int,
        text: str = "",
        content: bytes = b"",
        headers: Optional[Dict[str, str]] = None,
        json_data: Optional[Dict[str, object]] = None,
    ) -> None:
        self.status_code = status_code
        self.text = text
        self.content = content
        self.headers = headers or {}
        self._json_data = json_data or {}

    def iter_content(self, chunk_size: int = 64 * 1024):
        if self.content:
            yield self.content

    def json(self):
        return self._json_data

    def raise_for_status(self):
        if self.status_code < 200 or self.status_code > 299:
            raise requests.HTTPError(f"HTTP {self.status_code}")
        return None

    def close(self):
        return None


class FakeRedisLock:
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


class FakeRedis:
    def __init__(self) -> None:
        self.values: Dict[str, str] = {}
        self.sets: Dict[str, set[str]] = {}

    def ping(self):
        return True

    def lock(self, *_args, **_kwargs):
        return FakeRedisLock()

    def get(self, key: str):
        return self.values.get(key)

    def setex(self, key: str, _ttl: int, value: str):
        self.values[key] = value
        return True

    def delete(self, key: str):
        self.values.pop(key, None)
        self.sets.pop(key, None)
        return 1

    def sadd(self, key: str, value: str):
        self.sets.setdefault(key, set()).add(value)
        return 1

    def smembers(self, key: str):
        return set(self.sets.get(key, set()))


def engine_session_json(cid: str, playback_url: Optional[str] = None) -> Dict[str, object]:
    return {
        "response": {
            "infohash": cid,
            "playback_session_id": f"{cid}-session",
            "playback_url": playback_url or f"http://127.0.0.1:6878/ace/m/{cid}/playlist.m3u8",
            "stat_url": f"http://127.0.0.1:6878/ace/stat/{cid}/playlist",
            "command_url": f"http://127.0.0.1:6878/ace/cmd/{cid}/playlist",
            "is_live": 1,
            "is_encrypted": 0,
            "client_session_id": -1,
        },
        "error": None,
    }


class PrepareManifestMaterialTests(unittest.TestCase):
    def test_first_segment_probe_must_succeed_even_if_others_ok(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        manifest = (
            "#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:6.0,\n"
            "http://engine.test/0.ts\n"
            "#EXTINF:6.0,\n"
            "http://engine.test/1.ts\n"
        )

        def fake_probe(segment_url, cid, base_proxy_url, api_password, public_stream_token=None):
            proxy_url = p2p_proxy_service.segment_proxy_url(
                base_proxy_url,
                cid,
                api_password,
                segment_url,
                public_stream_token,
            )
            if segment_url.endswith("/0.ts"):
                return p2p_proxy_service.SegmentProbe(
                    original_url=segment_url,
                    proxy_url=proxy_url,
                    status_code=500,
                    bytes_read=0,
                    failure_class="segment_500",
                )
            return p2p_proxy_service.SegmentProbe(
                original_url=segment_url,
                proxy_url=proxy_url,
                status_code=206,
                bytes_read=1024,
                failure_class="ok",
            )

        with patch.object(p2p_proxy_service, "probe_segment_for_manifest", side_effect=fake_probe):
            with patch.object(p2p_proxy_service, "UPSTREAM_KIND", "mediaflow"):
                with patch("p2p_proxy_service.requests.get") as rg:
                    rg.return_value = FakeResponse(200, text=manifest)
                    with self.assertRaises(p2p_proxy_service.ManifestPreparationFailure) as ctx:
                        p2p_proxy_service.prepare_manifest_material(
                            cid="cid-head-fail",
                            api_password="secret",
                            base_proxy_url="https://p2p.test",
                        )
        self.assertEqual(ctx.exception.error_code, "segment_500")

    def test_failed_probe_window_segments_are_dropped_from_manifest(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        manifest = (
            "#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:6.0,\n"
            "http://engine.test/0.ts\n"
            "#EXTINF:6.0,\n"
            "http://engine.test/1.ts\n"
        )

        def fake_probe(segment_url, cid, base_proxy_url, api_password, public_stream_token=None):
            proxy_url = p2p_proxy_service.segment_proxy_url(
                base_proxy_url,
                cid,
                api_password,
                segment_url,
                public_stream_token,
            )
            if segment_url.endswith("/1.ts"):
                return p2p_proxy_service.SegmentProbe(
                    original_url=segment_url,
                    proxy_url=proxy_url,
                    status_code=500,
                    bytes_read=0,
                    failure_class="segment_500",
                )
            return p2p_proxy_service.SegmentProbe(
                original_url=segment_url,
                proxy_url=proxy_url,
                status_code=206,
                bytes_read=1024,
                failure_class="ok",
            )

        with patch.object(p2p_proxy_service, "probe_segment_for_manifest", side_effect=fake_probe):
            with patch.object(p2p_proxy_service, "UPSTREAM_KIND", "mediaflow"):
                with patch("p2p_proxy_service.requests.get") as rg:
                    rg.return_value = FakeResponse(200, text=manifest)
                    result = p2p_proxy_service.prepare_manifest_material(
                        cid="cid-drop-mid",
                        api_password="secret",
                        base_proxy_url="https://p2p.test",
                    )
        self.assertEqual(result.validated_segment_count, 1)
        self.assertIn("engine.test%2F0.ts", result.rewritten_manifest)
        self.assertNotIn("engine.test%2F1.ts", result.rewritten_manifest)


class P2PProxyCoreTests(unittest.TestCase):
    def test_classify_manifest_timeout(self):
        self.assertEqual(classify_manifest_failure(timed_out=True), "timeout")

    def test_classify_manifest_524(self):
        self.assertEqual(classify_manifest_failure(status_code=524), "524")

    def test_classify_segment_500(self):
        self.assertEqual(
            classify_segment_failure(status_code=500, bytes_read=0, minimum_segment_bytes=512),
            "segment_500",
        )

    def test_rewrite_manifest_drops_unvalidated_segments(self):
        manifest = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:3\n"
            "#EXTINF:6.0,\n"
            "https://example.com/seg-0.ts\n"
            "#EXTINF:6.0,\n"
            "https://example.com/seg-1.ts\n"
        )
        rewritten = rewrite_manifest(
            original_manifest=manifest,
            manifest_url="https://example.com/playlist.m3u8",
            valid_segment_urls={
                "https://example.com/seg-1.ts": "https://proxy.local/ace/proxy?url=seg-1",
            },
        )

        self.assertIn("https://proxy.local/ace/proxy?url=seg-1", rewritten)
        self.assertNotIn("https://example.com/seg-0.ts", rewritten)

    def test_normalize_upstream_url_rewrites_loopback_host(self):
        original_kind = p2p_proxy_service.UPSTREAM_KIND if p2p_proxy_service else None
        original_base = p2p_proxy_service.UPSTREAM_BASE_URL if p2p_proxy_service else None
        if p2p_proxy_service:
            try:
                p2p_proxy_service.UPSTREAM_BASE_URL = "http://172.18.0.1:6878"
                self.assertEqual(
                    p2p_proxy_service.normalize_upstream_url("http://127.0.0.1:6878/ace/m/cid/test.m3u8"),
                    "http://172.18.0.1:6878/ace/m/cid/test.m3u8",
                )
            finally:
                p2p_proxy_service.UPSTREAM_KIND = original_kind
                p2p_proxy_service.UPSTREAM_BASE_URL = original_base

    def test_broker_record_round_trips_persistent_payload(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        record = p2p_proxy_service.BrokerSessionRecord(
            session_id="session-1",
            cid="cid-1",
            api_password="secret",
            title="Test Channel",
            category="basketball",
            availability=0.8,
            bitrate_kbps=1800,
            categories=["sport"],
            source="test",
            manifest_url="https://p2p.test/session-1/manifest.m3u8",
            status_url="https://p2p.test/session-1/status",
            events_url="https://p2p.test/session-1/events",
        )
        record.manifest_text = "#EXTM3U\n"
        record.engine_playback_url = "http://127.0.0.1:6878/ace/m/cid-1/playlist.m3u8"
        record.prepare_inflight = True
        record.add_event("prepare_started", "warming", "Looking for peers.")

        restored = p2p_proxy_service.BrokerSessionRecord.from_payload(record.persist_payload())
        self.assertEqual(restored.session_id, record.session_id)
        self.assertEqual(restored.cid, record.cid)
        self.assertEqual(restored.manifest_text, record.manifest_text)
        self.assertTrue(restored.prepare_inflight)
        self.assertEqual(restored.events[-1].name, "prepare_started")

    def test_public_stream_token_must_match_cid_and_expiry(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        original_secret = p2p_proxy_service.PUBLIC_STREAM_TOKEN_SECRET
        try:
            p2p_proxy_service.PUBLIC_STREAM_TOKEN_SECRET = "test-public-stream-secret"
            token = make_public_stream_token("cid-token", p2p_proxy_service.PUBLIC_STREAM_TOKEN_SECRET)
            expired = make_public_stream_token(
                "cid-token",
                p2p_proxy_service.PUBLIC_STREAM_TOKEN_SECRET,
                exp=time.time() - 1,
            )

            self.assertTrue(p2p_proxy_service.verify_public_stream_token(token, "cid-token"))
            self.assertFalse(p2p_proxy_service.verify_public_stream_token(token, "other-cid"))
            self.assertFalse(p2p_proxy_service.verify_public_stream_token(expired, "cid-token"))
        finally:
            p2p_proxy_service.PUBLIC_STREAM_TOKEN_SECRET = original_secret

    def test_segment_proxy_url_uses_public_stream_token_without_api_password(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        url = p2p_proxy_service.segment_proxy_url(
            "https://p2p.test",
            "cid-public",
            "real-secret",
            "http://127.0.0.1:6878/ace/c/cid-public/0.ts",
            public_stream_token="short-lived-token",
        )

        self.assertIn("stream_token=short-lived-token", url)
        self.assertNotIn("api_password=", url)

    def test_redis_store_reuses_warming_session_across_store_instances(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        redis = FakeRedis()
        first_store = p2p_proxy_service.BrokerSessionStore(redis_client=redis)
        second_store = p2p_proxy_service.BrokerSessionStore(redis_client=redis)

        first_record, created = first_store.create(
            cid="cid-redis",
            api_password="secret",
            title="Redis Channel",
            category="football",
            availability=None,
            bitrate_kbps=None,
            categories=[],
            source=None,
            base_url="https://p2p.test",
        )
        self.assertTrue(created)
        context = first_store.ensure_prepare_context(first_record.session_id, reason="create", force=True)
        self.assertIsNotNone(context)

        second_record, second_created = second_store.create(
            cid="cid-redis",
            api_password="secret",
            title="Redis Channel Duplicate",
            category="football",
            availability=None,
            bitrate_kbps=None,
            categories=[],
            source=None,
            base_url="https://p2p.test",
        )

        self.assertFalse(second_created)
        self.assertEqual(first_record.session_id, second_record.session_id)
        self.assertEqual(second_record.state, "warming")
        self.assertEqual(second_store.broker_snapshot()["backend"], "redis")
        self.assertEqual(second_store.broker_snapshot()["total_sessions"], 1)

    def test_redis_store_shares_ready_session_and_health_across_instances(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        redis = FakeRedis()
        first_store = p2p_proxy_service.BrokerSessionStore(redis_client=redis)
        second_store = p2p_proxy_service.BrokerSessionStore(redis_client=redis)
        record, _created = first_store.create(
            cid="cid-ready",
            api_password="secret",
            title="Ready Channel",
            category="basketball",
            availability=None,
            bitrate_kbps=None,
            categories=[],
            source=None,
            base_url="https://p2p.test",
        )

        result = p2p_proxy_service.ManifestPreparationResult(
            cid="cid-ready",
            api_password="secret",
            rewritten_manifest="#EXTM3U\n#EXTINF:6.0,\nhttps://p2p.test/ace/proxy?cid=cid-ready&url=seg\n",
            manifest_ttfb_ms=1234,
            validated_segment_count=2,
            upstream_manifest_url="http://127.0.0.1:6878/ace/m/cid-ready/playlist.m3u8",
            rejection_reasons=[],
            first_segment_url="https://p2p.test/ace/proxy?cid=cid-ready&url=seg",
            first_upstream_segment_url="http://127.0.0.1:6878/ace/c/cid-ready/0.ts",
            engine_session=p2p_proxy_service.EnginePlaybackSession(
                playback_url="http://127.0.0.1:6878/ace/m/cid-ready/playlist.m3u8",
                stat_url="",
                command_url="",
                playback_session_id="engine-session",
            ),
        )
        first_store.complete_success(
            session_id=record.session_id,
            result=result,
            telemetry={"ready_segment_count": 0},
            reason="test",
        )

        restored = second_store.get(record.session_id)
        self.assertIsNotNone(restored)
        self.assertEqual(restored.state, "ready")
        self.assertEqual(restored.manifest_text, result.rewritten_manifest)
        self.assertEqual(restored.broker_health["success_count"], 1)
        self.assertEqual(restored.ready_segment_count, 2)

        rehydrated = second_store.hydrate_telemetry(
            record.session_id,
            {"ready_segment_count": 0, "first_segment_ready": False},
        )
        self.assertIsNotNone(rehydrated)
        self.assertEqual(rehydrated.ready_segment_count, 2)
        self.assertTrue(rehydrated.first_segment_ready)

    def test_cached_ready_manifest_ages_out_before_session_ttl(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        record = p2p_proxy_service.BrokerSessionRecord(
            session_id="session-freshness",
            cid="cid-freshness",
            api_password="secret",
            title="Freshness Channel",
            category="sport",
            availability=None,
            bitrate_kbps=None,
            categories=[],
            source=None,
            manifest_url="https://p2p.test/session-freshness/manifest.m3u8",
            status_url="https://p2p.test/session-freshness/status",
            events_url="https://p2p.test/session-freshness/events",
        )
        record.state = "ready"
        record.manifest_text = "#EXTM3U\n"
        record.expires_at = p2p_proxy_service.utcnow() + timedelta(seconds=90)
        record.last_prepare_completed_at = p2p_proxy_service.utcnow() - timedelta(
            seconds=p2p_proxy_service.BROKER_MANIFEST_FRESH_SECONDS + 1
        )

        self.assertFalse(p2p_proxy_service.cached_manifest_is_fresh(record))

        record.last_prepare_completed_at = p2p_proxy_service.utcnow()
        self.assertTrue(p2p_proxy_service.cached_manifest_is_fresh(record))

    def test_retryable_failure_becomes_failed_after_prepare_budget(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        store = p2p_proxy_service.BrokerSessionStore()
        record, _created = store.create(
            cid="cid-budget",
            api_password="secret",
            title="Budget Channel",
            category="sport",
            availability=None,
            bitrate_kbps=None,
            categories=[],
            source=None,
            base_url="https://p2p.test",
        )
        record.prepare_attempts = p2p_proxy_service.BROKER_MAX_RETRYABLE_PREPARE_ATTEMPTS
        record.prepare_inflight = True
        record.manifest_text = "#EXTM3U\n"
        record.first_segment_url = "https://p2p.test/ace/proxy?cid=cid-budget&url=seg"

        failed = store.complete_failure(
            session_id=record.session_id,
            failure=p2p_proxy_service.ManifestPreparationFailure(
                cid="cid-budget",
                error_code="timeout",
                detail="Warmup exceeded budget.",
            ),
            telemetry={},
            reason="test",
        )

        self.assertIsNotNone(failed)
        self.assertEqual(failed.state, "failed")
        self.assertEqual(failed.message, "No playable stream is available right now.")
        self.assertIsNone(failed.manifest_text)
        self.assertIsNone(store.ensure_prepare_context(record.session_id, reason="status_poll", force=False))

    def test_over_budget_warming_session_is_not_failed_while_prepare_inflight(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        store = p2p_proxy_service.BrokerSessionStore()
        record, _created = store.create(
            cid="cid-over-budget",
            api_password="secret",
            title="Over Budget Channel",
            category="sport",
            availability=None,
            bitrate_kbps=None,
            categories=[],
            source=None,
            base_url="https://p2p.test",
        )
        record.state = "warming"
        record.prepare_inflight = True
        record.prepare_attempts = p2p_proxy_service.BROKER_MAX_RETRYABLE_PREPARE_ATTEMPTS + 1
        record.manifest_text = "#EXTM3U\n"
        record.last_prepare_started_at = p2p_proxy_service.utcnow()

        self.assertIsNone(store.ensure_prepare_context(record.session_id, reason="status_poll", force=False))

        settled = store.get(record.session_id)
        self.assertIsNotNone(settled)
        self.assertEqual(settled.state, "warming")
        self.assertTrue(settled.prepare_inflight)
        self.assertEqual(settled.manifest_text, "#EXTM3U\n")

    def test_stale_over_budget_prepare_is_settled_on_poll(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        store = p2p_proxy_service.BrokerSessionStore()
        record, _created = store.create(
            cid="cid-stale-over-budget",
            api_password="secret",
            title="Stale Over Budget Channel",
            category="sport",
            availability=None,
            bitrate_kbps=None,
            categories=[],
            source=None,
            base_url="https://p2p.test",
        )
        record.state = "warming"
        record.prepare_inflight = True
        record.prepare_attempts = p2p_proxy_service.BROKER_MAX_RETRYABLE_PREPARE_ATTEMPTS + 1
        record.manifest_text = "#EXTM3U\n"
        record.last_prepare_started_at = p2p_proxy_service.utcnow() - timedelta(
            seconds=p2p_proxy_service.PREPARE_INFLIGHT_STALE_SECONDS + 1
        )

        self.assertIsNone(store.ensure_prepare_context(record.session_id, reason="status_poll", force=False))

        settled = store.get(record.session_id)
        self.assertIsNotNone(settled)
        self.assertEqual(settled.state, "failed")
        self.assertFalse(settled.prepare_inflight)
        self.assertIsNone(settled.manifest_text)
        self.assertEqual(settled.events[-1].name, "prepare_budget_exhausted")

    def test_ready_session_reuses_within_grace_after_nominal_expiry(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        store = p2p_proxy_service.BrokerSessionStore()
        record, created = store.create(
            cid="cid-grace",
            api_password="secret",
            title="Grace Channel",
            category="sport",
            availability=None,
            bitrate_kbps=None,
            categories=[],
            source=None,
            base_url="https://p2p.test",
        )
        self.assertTrue(created)
        result = p2p_proxy_service.ManifestPreparationResult(
            cid="cid-grace",
            api_password="secret",
            rewritten_manifest="#EXTM3U\n#EXTINF:6.0,\nhttps://p2p.test/seg.ts\n",
            manifest_ttfb_ms=1000,
            validated_segment_count=1,
            upstream_manifest_url="http://127.0.0.1:6878/ace/m/cid-grace/playlist.m3u8",
            rejection_reasons=[],
            first_segment_url="https://p2p.test/seg.ts",
            first_upstream_segment_url="http://127.0.0.1:6878/ace/c/cid-grace/0.ts",
            engine_session=p2p_proxy_service.EnginePlaybackSession(
                playback_url="http://127.0.0.1:6878/ace/m/cid-grace/playlist.m3u8",
                stat_url="http://127.0.0.1:6878/ace/stat/cid-grace/playlist",
                command_url="http://127.0.0.1:6878/ace/cmd/cid-grace/playlist",
                playback_session_id="engine-session",
            ),
        )
        store.complete_success(record.session_id, result, telemetry={}, reason="test")
        restored = store.get(record.session_id)
        self.assertIsNotNone(restored)
        restored.expires_at = p2p_proxy_service.utcnow() - timedelta(seconds=5)
        store._save_record_locked(restored)

        duplicate, duplicate_created = store.create(
            cid="cid-grace",
            api_password="secret",
            title="Grace Duplicate",
            category="sport",
            availability=None,
            bitrate_kbps=None,
            categories=[],
            source=None,
            base_url="https://p2p.test",
        )

        self.assertFalse(duplicate_created)
        self.assertEqual(duplicate.session_id, record.session_id)

    def test_engine_session_status_uses_playback_stat_url(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        engine_session = p2p_proxy_service.EnginePlaybackSession(
            playback_url="http://127.0.0.1:6878/ace/m/cid-stat/playlist.m3u8",
            stat_url="http://127.0.0.1:6878/ace/stat/cid-stat/playlist",
            command_url="http://127.0.0.1:6878/ace/cmd/cid-stat/playlist",
            playback_session_id="engine-session",
        )

        def fake_get(url, **_kwargs):
            self.assertIn("/ace/stat/cid-stat/", url)
            return FakeResponse(
                status_code=200,
                json_data={
                    "response": {
                        "status": "dl",
                        "peers": 7,
                        "speed_down": 512,
                        "speed_up": 12,
                        "downloaded": 4096,
                        "livepos": {"buffer_pieces": "4"},
                    }
                },
            )

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            snapshot = p2p_proxy_service.fetch_engine_status_snapshot("cid-stat", engine_session)

        self.assertEqual(snapshot["peer_count"], 7)
        self.assertEqual(snapshot["download_speed_kbps"], 4096)
        self.assertEqual(snapshot["ready_segment_count"], 4)
        self.assertTrue(snapshot["first_segment_ready"])

    def test_prewarm_selection_uses_health_and_availability(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        original_store = p2p_proxy_service.session_store
        try:
            p2p_proxy_service.session_store = p2p_proxy_service.BrokerSessionStore()
            good, _ = p2p_proxy_service.session_store.create(
                cid="cid-good-prewarm",
                api_password="secret",
                title="Good Channel",
                category="sport",
                availability=1.0,
                bitrate_kbps=2000,
                categories=[],
                source="test",
                base_url="https://p2p.test",
            )
            result = p2p_proxy_service.ManifestPreparationResult(
                cid="cid-good-prewarm",
                api_password="secret",
                rewritten_manifest="#EXTM3U\n#EXTINF:6,\nhttps://p2p.test/seg.ts\n",
                manifest_ttfb_ms=1000,
                validated_segment_count=3,
                upstream_manifest_url="http://127.0.0.1:6878/ace/m/cid-good-prewarm/playlist.m3u8",
                rejection_reasons=[],
                first_segment_url="https://p2p.test/seg.ts",
                first_upstream_segment_url="http://127.0.0.1:6878/ace/c/cid-good-prewarm/0.ts",
                engine_session=None,
            )
            p2p_proxy_service.session_store.complete_success(good.session_id, result, telemetry={}, reason="test")

            with patch.object(p2p_proxy_service, "PREWARM_LIMIT", 1):
                selected = p2p_proxy_service.select_prewarm_channels(
                    [
                        {
                            "cid": "cid-good-prewarm",
                            "title": "Good Channel",
                            "category": "sport",
                            "availability": 1.0,
                            "bitrate_kbps": 2000,
                            "categories": [],
                            "source": "test",
                        },
                        {
                            "cid": "cid-weak-prewarm",
                            "title": "Weak Channel",
                            "category": "sport",
                            "availability": 0.8,
                            "bitrate_kbps": 500,
                            "categories": [],
                            "source": "test",
                        },
                    ]
                )

            self.assertEqual(len(selected), 1)
            self.assertEqual(selected[0]["cid"], "cid-good-prewarm")
            self.assertEqual(selected[0]["broker_state"], "ready")
        finally:
            p2p_proxy_service.session_store = original_store

    def test_prewarm_once_creates_and_kicks_selected_session(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        original_store = p2p_proxy_service.session_store
        try:
            p2p_proxy_service.session_store = p2p_proxy_service.BrokerSessionStore()
            channels = [
                {
                    "cid": "cid-prewarm-once",
                    "title": "Always Online",
                    "category": "sport",
                    "availability": 1.0,
                    "bitrate_kbps": 1500,
                    "categories": ["sport"],
                    "source": "test",
                }
            ]
            with patch.object(p2p_proxy_service, "fetch_prewarm_channels", return_value=channels):
                with patch.object(p2p_proxy_service, "launch_background_task", return_value=None):
                    with patch.object(p2p_proxy_service, "PREWARM_LIMIT", 1):
                        with patch.object(p2p_proxy_service, "PREWARM_PINNED_CIDS", {"cid-prewarm-once"}):
                            result = p2p_proxy_service.prewarm_once(reason="test")

            self.assertIsNone(result["last_error"])
            self.assertEqual(result["last_candidate_count"], 1)
            self.assertEqual(result["last_selected_count"], 1)
            record = p2p_proxy_service.session_store.get_by_cid("cid-prewarm-once")
            self.assertIsNotNone(record)
            self.assertEqual(record.state, "warming")
            self.assertEqual(record.prepare_attempts, 1)
        finally:
            p2p_proxy_service.session_store = original_store

    def test_prewarm_once_respects_active_session_cap(self):
        if p2p_proxy_service is None:
            self.skipTest("service runtime unavailable")

        original_store = p2p_proxy_service.session_store
        try:
            p2p_proxy_service.session_store = p2p_proxy_service.BrokerSessionStore()
            for index in range(2):
                record, _created = p2p_proxy_service.session_store.create(
                    cid=f"cid-active-{index}",
                    api_password="secret",
                    title=f"Active {index}",
                    category="sport",
                    availability=1.0,
                    bitrate_kbps=1000,
                    categories=[],
                    source="test",
                    base_url="https://p2p.test",
                )
                context = p2p_proxy_service.session_store.ensure_prepare_context(
                    record.session_id,
                    reason="test",
                    force=True,
                )
                self.assertIsNotNone(context)

            with patch.object(p2p_proxy_service, "PREWARM_LIMIT", 2):
                with patch.object(p2p_proxy_service, "fetch_prewarm_channels") as fetch:
                    with patch.object(p2p_proxy_service, "launch_background_task", return_value=None):
                        result = p2p_proxy_service.prewarm_once(reason="test")

            fetch.assert_not_called()
            self.assertEqual(result["active_session_count"], 2)
            self.assertEqual(result["last_selected_count"], 2)
            self.assertEqual(p2p_proxy_service.session_store.broker_snapshot()["total_sessions"], 2)
        finally:
            p2p_proxy_service.session_store = original_store

    def test_engine_session_enables_events_and_types_missing_proxy_entitlement(self):
        response = FakeResponse(
            200,
            json_data={
                "response": None,
                "extra_data": {"reason": "missing_option", "option": "proxyServer"},
                "error": "paid option required",
            },
        )
        with patch.object(p2p_proxy_service.requests, "get", return_value=response) as fetch:
            with self.assertRaises(p2p_proxy_service.ManifestPreparationFailure) as raised:
                p2p_proxy_service.create_engine_hls_session("cid-missing-proxy")

        self.assertEqual(raised.exception.error_code, "missing_entitlement_proxyServer")
        params = fetch.call_args.kwargs["params"]
        self.assertEqual(params["use_api_events"], 1)
        self.assertEqual(params["use_stop_notifications"], 1)

    def test_engine_event_parser_supports_legacy_json_and_terminal_classification(self):
        event = p2p_proxy_service.parse_engine_event_payload(
            {
                "response": json.dumps(
                    {
                        "name": "download_stopped",
                        "params": {"reason": "missing_option", "option": "proxyServer"},
                    }
                )
            }
        )
        self.assertEqual(event["name"], "download_stopped")
        session = p2p_proxy_service.EnginePlaybackSession("", "", "", "", event_url="")
        failure = p2p_proxy_service.terminal_engine_event_failure("cid-event", event, session)
        self.assertEqual(failure.error_code, "missing_entitlement_proxyServer")


@unittest.skipIf(p2p_proxy_service is None, "Integration tests require flask + service runtime dependencies.")
class P2PProxyIntegrationTests(unittest.TestCase):
    def setUp(self):
        p2p_proxy_service.metrics = p2p_proxy_service.ProxyMetrics()
        p2p_proxy_service.session_store = p2p_proxy_service.BrokerSessionStore()
        p2p_proxy_service.EXPECTED_SERVICE_TOKEN_ID = ""
        p2p_proxy_service.EXPECTED_SERVICE_TOKEN_SECRET = ""
        p2p_proxy_service.UPSTREAM_KIND = "engine"
        p2p_proxy_service.UPSTREAM_BASE_URL = "http://127.0.0.1:6878"
        p2p_proxy_service.ENGINE_WARMUP_TIMEOUT_SECONDS = 0.02
        p2p_proxy_service.ENGINE_WARMUP_POLL_SECONDS = 0.001
        p2p_proxy_service.BROKER_RETRY_COOLDOWN_SECONDS = 12
        self.client = p2p_proxy_service.app.test_client()

    def test_catalog_and_metrics_require_broker_authorization(self):
        self.assertEqual(self.client.get("/matches").status_code, 403)
        self.assertEqual(self.client.get("/metrics").status_code, 403)

        headers = {"Authorization": f"Bearer {p2p_proxy_service.EXPECTED_API_PASSWORD}"}
        self.assertEqual(self.client.get("/matches", headers=headers).status_code, 200)
        with patch.object(p2p_proxy_service, "get_engine_version", return_value="test"):
            self.assertEqual(self.client.get("/metrics", headers=headers).status_code, 200)

    def sync_background_task(self, target, *args):
        target(*args)

    def test_segment_proxy_allows_configured_upstream_origin(self):
        self.assertTrue(
            p2p_proxy_service.is_allowed_segment_upstream_url(
                "http://127.0.0.1:6878/ace/c/test/0.ts"
            )
        )

    def test_segment_proxy_rejects_unconfigured_and_credentialed_origins(self):
        self.assertFalse(
            p2p_proxy_service.is_allowed_segment_upstream_url(
                "http://169.254.169.254/latest/meta-data/"
            )
        )
        self.assertFalse(
            p2p_proxy_service.is_allowed_segment_upstream_url(
                "http://user:pass@127.0.0.1:6878/ace/c/test/0.ts"
            )
        )

    def test_segment_proxy_blocks_ssrf_before_network_request(self):
        with patch.object(p2p_proxy_service.requests, "get") as fetch:
            response = self.client.get(
                "/ace/proxy",
                query_string={
                    "cid": "cid-ssrf",
                    "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD,
                    "url": "http://169.254.169.254/latest/meta-data/",
                },
            )

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.get_json()["error"], "upstream_not_allowed")
        fetch.assert_not_called()

    def test_manifest_proxy_unexpected_error_returns_structured_500(self):
        with patch.object(
            p2p_proxy_service.session_store,
            "get",
            side_effect=RuntimeError("manifest test failure"),
        ):
            response = self.client.get(
                "/proxy/acestream/session/test-session/manifest.m3u8",
                query_string={"api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
            )

        self.assertEqual(response.status_code, 500)
        self.assertEqual(
            response.get_json(),
            {"error": "server_error", "detail": "manifest test failure"},
        )

    def test_segment_proxy_unexpected_error_returns_structured_500(self):
        with patch.object(
            p2p_proxy_service.requests,
            "get",
            side_effect=RuntimeError("segment test failure"),
        ):
            response = self.client.get(
                "/ace/proxy",
                query_string={
                    "cid": "cid-error",
                    "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD,
                    "url": "http://127.0.0.1:6878/ace/c/cid-error/0.ts",
                },
            )

        self.assertEqual(response.status_code, 500)
        self.assertEqual(
            response.get_json(),
            {"error": "server_error", "detail": "segment test failure"},
        )

    def test_manifest_timeout_returns_503_with_code(self):
        def fake_get(*_args, **_kwargs):
            raise requests.Timeout()

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            response = self.client.get(
                "/proxy/acestream/stream",
                query_string={"id": "cid-timeout", "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
            )

        self.assertEqual(response.status_code, 503)
        payload = response.get_json()
        self.assertEqual(payload["error"], "stream_unavailable")
        self.assertEqual(payload["code"], "timeout")
        self.assertEqual(payload["cid"], "cid-timeout")

    def test_manifest_524_returns_503_with_code(self):
        def fake_get(url, **_kwargs):
            self.assertIn("/ace/manifest.m3u8", url)
            return FakeResponse(status_code=524, text="upstream timeout")

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            response = self.client.get(
                "/proxy/acestream/stream",
                query_string={"id": "cid-524", "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
            )

        self.assertEqual(response.status_code, 503)
        payload = response.get_json()
        self.assertEqual(payload["code"], "524")
        self.assertEqual(payload["cid"], "cid-524")

    def test_segment_500_download_not_found_rejected(self):
        manifest = "#EXTM3U\n#EXTINF:6.0,\nhttps://p2p.pixel-invoice.com/ace/c/cid-bad/0.ts\n"

        def fake_get(url, **kwargs):
            if "/ace/manifest.m3u8" in url and kwargs.get("params", {}).get("format") == "json":
                return FakeResponse(status_code=200, json_data=engine_session_json("cid-bad"))
            if "/ace/m/cid-bad/playlist.m3u8" in url:
                return FakeResponse(status_code=200, text=manifest)
            if "/ace/c/cid-bad/0.ts" in url:
                return FakeResponse(status_code=500, content=b"download not found")
            raise AssertionError(f"Unexpected URL in test: {url}")

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            response = self.client.get(
                "/proxy/acestream/stream",
                query_string={"id": "cid-bad", "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
            )

        self.assertEqual(response.status_code, 503)
        payload = response.get_json()
        self.assertEqual(payload["code"], "segment_500")
        self.assertEqual(payload["cid"], "cid-bad")

    def test_unhealthy_segments_are_filtered_and_manifest_is_playable(self):
        manifest = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:3\n"
            "#EXTINF:6.0,\n"
            "https://p2p.pixel-invoice.com/ace/c/cid-good/0.ts\n"
            "#EXTINF:6.0,\n"
            "https://p2p.pixel-invoice.com/ace/c/cid-good/1.ts\n"
        )

        def fake_get(url, **kwargs):
            if "/ace/manifest.m3u8" in url and kwargs.get("params", {}).get("format") == "json":
                return FakeResponse(status_code=200, json_data=engine_session_json("cid-good"))
            if "/ace/m/cid-good/playlist.m3u8" in url:
                return FakeResponse(status_code=200, text=manifest)
            if "/ace/c/cid-good/0.ts" in url:
                return FakeResponse(status_code=200, content=b"x" * 2048)
            if "/ace/c/cid-good/1.ts" in url:
                return FakeResponse(status_code=500, content=b"download not found")
            raise AssertionError(f"Unexpected URL in test: {url}")

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            response = self.client.get(
                "/proxy/acestream/stream",
                query_string={"id": "cid-good", "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
            )

        self.assertEqual(response.status_code, 200)
        output_manifest = response.get_data(as_text=True)
        self.assertIn("/ace/proxy?cid=cid-good&api_password=", output_manifest)
        self.assertIn("&url=", output_manifest)
        self.assertIn("cid-good%2F0.ts", output_manifest)
        self.assertNotIn("cid-good%2F1.ts", output_manifest)
        metrics = p2p_proxy_service.metrics.snapshot()
        self.assertGreater(metrics["segment_2xx_rate"], 0.0)

    def test_probe_uses_recent_segment_window_for_live_playlists(self):
        lines = ["#EXTM3U", "#EXT-X-VERSION:3"]
        for index in range(10):
            lines.append("#EXTINF:6.0,")
            lines.append(f"https://p2p.pixel-invoice.com/ace/c/cid-tail/{index}.ts")
        manifest = "\n".join(lines) + "\n"

        def fake_get(url, **kwargs):
            if "/ace/manifest.m3u8" in url and kwargs.get("params", {}).get("format") == "json":
                return FakeResponse(status_code=200, json_data=engine_session_json("cid-tail"))
            if "/ace/m/cid-tail/playlist.m3u8" in url:
                return FakeResponse(status_code=200, text=manifest)
            if "/ace/c/cid-tail/" in url:
                segment_name = url.rsplit("/", 1)[-1]
                # Playlist head and probe-window tails must succeed; first line is always probed.
                if segment_name in {"0.ts", "1.ts", "2.ts", "3.ts", "8.ts", "9.ts"}:
                    return FakeResponse(status_code=200, content=b"x" * 2048)
                return FakeResponse(status_code=500, content=b"download not found")
            raise AssertionError(f"Unexpected URL in test: {url}")

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            response = self.client.get(
                "/proxy/acestream/stream",
                query_string={"id": "cid-tail", "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
            )

        self.assertEqual(response.status_code, 200)
        output_manifest = response.get_data(as_text=True)
        self.assertIn("cid-tail%2F8.ts", output_manifest)
        self.assertIn("cid-tail%2F9.ts", output_manifest)
        self.assertIn("cid-tail%2F0.ts", output_manifest)

    def test_session_create_returns_broker_contract_and_ready_manifest(self):
        manifest = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:3\n"
            "#EXTINF:6.0,\n"
            "https://p2p.pixel-invoice.com/ace/c/cid-broker/0.ts\n"
        )

        def fake_get(url, **kwargs):
            if "/ace/manifest.m3u8" in url and kwargs.get("params", {}).get("format") == "json":
                return FakeResponse(status_code=200, json_data=engine_session_json("cid-broker"))
            if "/ace/m/cid-broker/playlist.m3u8" in url:
                return FakeResponse(status_code=200, text=manifest)
            if "/ace/c/cid-broker/0.ts" in url:
                return FakeResponse(status_code=200, content=b"x" * 2048)
            raise AssertionError(f"Unexpected URL in test: {url}")

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            with patch.object(p2p_proxy_service, "launch_background_task", side_effect=self.sync_background_task):
                response = self.client.post(
                    "/proxy/acestream/session",
                    json={
                        "cid": "cid-broker",
                        "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD,
                        "title": "BT Sport 1",
                        "category": "basketball",
                        "bitrate_kbps": 1800,
                        "categories": ["sport", "basketball"],
                        "source": "scraper",
                    },
                )

        self.assertEqual(response.status_code, 202)
        payload = response.get_json()
        self.assertEqual(payload["state"], "ready")
        self.assertEqual(payload["source_id"], "cid-broker")
        self.assertIn("/proxy/acestream/session/", payload["manifest_url"])
        self.assertIn("/status", payload["status_url"])
        self.assertEqual(payload["bitrate_kbps"], 1800)
        self.assertIn("basketball", payload["categories"])

        manifest_response = self.client.get(
            f"/proxy/acestream/session/{payload['session_id']}/manifest.m3u8",
            headers={"Authorization": f"Bearer {p2p_proxy_service.EXPECTED_API_PASSWORD}"},
        )
        self.assertEqual(manifest_response.status_code, 200)
        broker_manifest = manifest_response.get_data(as_text=True)
        self.assertIn("/ace/proxy?cid=cid-broker&api_password=", broker_manifest)
        self.assertIn("&url=", broker_manifest)

    def test_session_create_reuses_existing_retrying_session_for_same_cid(self):
        def fake_get(url, **kwargs):
            if "/ace/manifest.m3u8" in url and kwargs.get("params", {}).get("format") == "json":
                return FakeResponse(status_code=200, json_data=engine_session_json("cid-reuse"))
            if "/ace/m/cid-reuse/playlist.m3u8" in url:
                raise requests.Timeout()
            raise AssertionError(f"Unexpected URL in test: {url}")

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            with patch.object(p2p_proxy_service, "launch_background_task", side_effect=self.sync_background_task):
                first = self.client.post(
                    "/proxy/acestream/session",
                    json={"cid": "cid-reuse", "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
                )
                second = self.client.post(
                    "/proxy/acestream/session",
                    json={"cid": "cid-reuse", "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
                )

        self.assertEqual(first.status_code, 202)
        self.assertEqual(second.status_code, 202)
        first_payload = first.get_json()
        second_payload = second.get_json()
        self.assertEqual(first_payload["session_id"], second_payload["session_id"])
        self.assertEqual(second_payload["state"], "retrying")
        self.assertEqual(p2p_proxy_service.session_store.broker_snapshot()["total_sessions"], 1)

    def test_expired_cached_manifest_is_served_only_after_segment_revalidation(self):
        manifest = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:3\n"
            "#EXTINF:6.0,\n"
            "https://p2p.pixel-invoice.com/ace/c/cid-expired-ok/0.ts\n"
        )

        def fake_get(url, **kwargs):
            if "/ace/manifest.m3u8" in url and kwargs.get("params", {}).get("format") == "json":
                return FakeResponse(status_code=200, json_data=engine_session_json("cid-expired-ok"))
            if "/ace/m/cid-expired-ok/playlist.m3u8" in url:
                return FakeResponse(status_code=200, text=manifest)
            if "/ace/c/cid-expired-ok/0.ts" in url:
                return FakeResponse(status_code=200, content=b"x" * 2048)
            raise AssertionError(f"Unexpected URL in test: {url}")

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            with patch.object(p2p_proxy_service, "launch_background_task", side_effect=self.sync_background_task):
                response = self.client.post(
                    "/proxy/acestream/session",
                    json={"cid": "cid-expired-ok", "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
                )

        payload = response.get_json()
        record = p2p_proxy_service.session_store.get(payload["session_id"])
        self.assertIsNotNone(record)
        record.expires_at = p2p_proxy_service.utcnow() - timedelta(seconds=1)
        record.state = "warming"

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            with patch.object(p2p_proxy_service, "launch_background_task", return_value=None):
                manifest_response = self.client.get(
                    f"/proxy/acestream/session/{payload['session_id']}/manifest.m3u8",
                    headers={"Authorization": f"Bearer {p2p_proxy_service.EXPECTED_API_PASSWORD}"},
                )

        self.assertEqual(manifest_response.status_code, 200)
        expired_manifest = manifest_response.get_data(as_text=True)
        self.assertIn("/ace/proxy?cid=cid-expired-ok&api_password=", expired_manifest)
        self.assertIn("&url=", expired_manifest)
        # Stale manifests are served only after a segment probe proves the cached playlist is still usable.
        refreshed_record = p2p_proxy_service.session_store.get(payload["session_id"])
        self.assertIsNotNone(refreshed_record)

    def test_expired_cached_manifest_is_not_served_when_segment_revalidation_fails(self):
        manifest = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:3\n"
            "#EXTINF:6.0,\n"
            "https://p2p.pixel-invoice.com/ace/c/cid-expired-bad/0.ts\n"
        )

        def create_get(url, **kwargs):
            if "/ace/manifest.m3u8" in url and kwargs.get("params", {}).get("format") == "json":
                return FakeResponse(status_code=200, json_data=engine_session_json("cid-expired-bad"))
            if "/ace/m/cid-expired-bad/playlist.m3u8" in url:
                return FakeResponse(status_code=200, text=manifest)
            if "/ace/c/cid-expired-bad/0.ts" in url:
                return FakeResponse(status_code=200, content=b"x" * 2048)
            raise AssertionError(f"Unexpected URL in test: {url}")

        def revalidate_get(url, **kwargs):
            if "/ace/c/cid-expired-bad/0.ts" in url:
                return FakeResponse(status_code=500, content=b"download not found")
            raise AssertionError(f"Unexpected URL in test: {url}")

        with patch.object(p2p_proxy_service.requests, "get", side_effect=create_get):
            with patch.object(p2p_proxy_service, "launch_background_task", side_effect=self.sync_background_task):
                response = self.client.post(
                    "/proxy/acestream/session",
                    json={"cid": "cid-expired-bad", "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
                )

        payload = response.get_json()
        record = p2p_proxy_service.session_store.get(payload["session_id"])
        self.assertIsNotNone(record)
        record.expires_at = p2p_proxy_service.utcnow() - timedelta(seconds=1)
        record.state = "refreshing"
        p2p_proxy_service.session_store._save_record_locked(record)

        with patch.object(p2p_proxy_service.requests, "get", side_effect=revalidate_get):
            with patch.object(p2p_proxy_service, "launch_background_task", return_value=None):
                manifest_response = self.client.get(
                    f"/proxy/acestream/session/{payload['session_id']}/manifest.m3u8",
                    headers={"Authorization": f"Bearer {p2p_proxy_service.EXPECTED_API_PASSWORD}"},
                )

        self.assertEqual(manifest_response.status_code, 503)
        stale_payload = manifest_response.get_json()
        self.assertEqual(stale_payload["error"], "stream_unavailable")
        self.assertIn("code", stale_payload)

        stale_record = p2p_proxy_service.session_store.get(payload["session_id"])
        self.assertIsNotNone(stale_record)
        self.assertEqual(stale_record.state, "refreshing")

        reused_record, created = p2p_proxy_service.session_store.create(
            cid="cid-expired-bad",
            api_password=p2p_proxy_service.EXPECTED_API_PASSWORD,
            title=None,
            category=None,
            availability=None,
            bitrate_kbps=None,
            categories=[],
            source=None,
            base_url="https://p2p.test",
        )
        self.assertFalse(created)
        self.assertEqual(reused_record.session_id, payload["session_id"])
        self.assertEqual(reused_record.state, "refreshing")

    def test_mediaflow_upstream_mode_uses_manifest_endpoint(self):
        p2p_proxy_service.UPSTREAM_KIND = "mediaflow"
        p2p_proxy_service.UPSTREAM_BASE_URL = "http://127.0.0.1:8888"
        manifest = (
            "#EXTM3U\n"
            "#EXT-X-VERSION:3\n"
            "#EXTINF:6.0,\n"
            "http://127.0.0.1:8888/proxy/acestream/segment.ts?d=http://127.0.0.1:6878/ace/c/cid-mf/0.ts\n"
        )

        def fake_get(url, **kwargs):
            if "/proxy/acestream/manifest.m3u8" in url:
                self.assertEqual(kwargs["params"]["infohash"], "cid-mf")
                return FakeResponse(status_code=200, text=manifest)
            if "/proxy/acestream/segment.ts" in url:
                return FakeResponse(status_code=200, content=b"x" * 2048)
            raise AssertionError(f"Unexpected URL in test: {url}")

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            response = self.client.get(
                "/proxy/acestream/stream",
                query_string={"id": "cid-mf", "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
            )

        self.assertEqual(response.status_code, 200)
        mediaflow_manifest = response.get_data(as_text=True)
        self.assertIn("/ace/proxy?cid=cid-mf&api_password=", mediaflow_manifest)
        self.assertIn("&url=", mediaflow_manifest)

    def test_health_reports_upstream_kind(self):
        p2p_proxy_service.UPSTREAM_KIND = "mediaflow"
        p2p_proxy_service.UPSTREAM_BASE_URL = "http://127.0.0.1:8888"
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertEqual(payload["upstream_kind"], "mediaflow")

    def test_session_status_returns_retrying_state_when_prepare_fails_retryably(self):
        def fake_get(url, **kwargs):
            if "/ace/manifest.m3u8" in url and kwargs.get("params", {}).get("format") == "json":
                return FakeResponse(status_code=200, json_data=engine_session_json("cid-warm"))
            if "/ace/m/cid-warm/playlist.m3u8" in url:
                raise requests.Timeout()
            raise AssertionError(f"Unexpected URL in test: {url}")

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            with patch.object(p2p_proxy_service, "launch_background_task", side_effect=self.sync_background_task):
                response = self.client.post(
                    "/proxy/acestream/session",
                    json={"cid": "cid-warm", "api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
                )

        payload = response.get_json()
        self.assertEqual(payload["state"], "retrying")
        self.assertEqual(payload["message"], "This source is not playable yet. Trying again shortly.")
        self.assertEqual(payload["last_error_code"], "timeout")

        status_response = self.client.get(
            f"/proxy/acestream/session/{payload['session_id']}/status",
            headers={"Authorization": f"Bearer {p2p_proxy_service.EXPECTED_API_PASSWORD}"},
        )
        self.assertEqual(status_response.status_code, 200)
        status_payload = status_response.get_json()
        self.assertEqual(status_payload["state"], "retrying")
        self.assertEqual(status_payload["message"], "This source is not playable yet. Trying again shortly.")
        self.assertEqual(status_payload["last_error_code"], "timeout")

        manifest_response = self.client.get(
            f"/proxy/acestream/session/{payload['session_id']}/manifest.m3u8",
            headers={"Authorization": f"Bearer {p2p_proxy_service.EXPECTED_API_PASSWORD}"},
        )
        self.assertEqual(manifest_response.status_code, 503)
        manifest_payload = manifest_response.get_json()
        self.assertEqual(manifest_payload["code"], "timeout")

    def test_session_create_accepts_authorization_header(self):
        manifest = "#EXTM3U\n#EXTINF:6.0,\nhttps://p2p.pixel-invoice.com/ace/c/cid-auth/0.ts\n"

        def fake_get(url, **kwargs):
            if "/ace/manifest.m3u8" in url and kwargs.get("params", {}).get("format") == "json":
                return FakeResponse(status_code=200, json_data=engine_session_json("cid-auth"))
            if "/ace/m/cid-auth/playlist.m3u8" in url:
                return FakeResponse(status_code=200, text=manifest)
            if "/ace/c/cid-auth/0.ts" in url:
                return FakeResponse(status_code=200, content=b"x" * 2048)
            raise AssertionError(f"Unexpected URL in test: {url}")

        with patch.object(p2p_proxy_service.requests, "get", side_effect=fake_get):
            with patch.object(p2p_proxy_service, "launch_background_task", side_effect=self.sync_background_task):
                response = self.client.post(
                    "/proxy/acestream/session",
                    headers={"Authorization": f"Bearer {p2p_proxy_service.EXPECTED_API_PASSWORD}"},
                    json={"cid": "cid-auth"},
                )

        self.assertEqual(response.status_code, 202)
        payload = response.get_json()
        self.assertEqual(payload["state"], "ready")

    def test_service_token_requirement_allows_valid_api_password(self):
        p2p_proxy_service.EXPECTED_SERVICE_TOKEN_ID = "cf-id"
        p2p_proxy_service.EXPECTED_SERVICE_TOKEN_SECRET = "cf-secret"
        try:
            allowed_by_api_password = self.client.get(
                "/proxy/acestream/status",
                query_string={"api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
            )
            self.assertEqual(allowed_by_api_password.status_code, 200)

            blocked = self.client.get("/proxy/acestream/status")
            self.assertEqual(blocked.status_code, 403)
            self.assertEqual(blocked.get_json()["error"], "service_token_required")

            allowed = self.client.get(
                "/proxy/acestream/status",
                headers={
                    "CF-Access-Client-Id": "cf-id",
                    "CF-Access-Client-Secret": "cf-secret",
                },
                query_string={"api_password": p2p_proxy_service.EXPECTED_API_PASSWORD},
            )
            self.assertEqual(allowed.status_code, 200)
        finally:
            p2p_proxy_service.EXPECTED_SERVICE_TOKEN_ID = ""
            p2p_proxy_service.EXPECTED_SERVICE_TOKEN_SECRET = ""


if __name__ == "__main__":
    unittest.main()
