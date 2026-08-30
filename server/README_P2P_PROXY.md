# P2P Proxy Reliability Service

This service hardens `/proxy/acestream/stream` by:

- returning deterministic `503` JSON errors for manifest failures (timeouts, upstream status issues, empty/invalid manifests),
- validating segment URLs before exposing them to clients,
- rewriting validated segment URLs through a local proxy route,
- exposing health metrics for `manifest_ttfb`, `segment_2xx_rate`, and per-CID failure reasons.

## Run Locally

```bash
cd server
python3 p2p_proxy_service.py
```

## Docker

```bash
cd server
docker build -f Dockerfile.p2p-proxy -t fotty-p2p-proxy .
docker run --rm -p 8006:8006 fotty-p2p-proxy
```

## Environment Variables

- `P2P_UPSTREAM_BASE_URL` (default: `http://127.0.0.1:6878`, the local AceStream engine)
- `P2P_API_PASSWORD` (**required** — no default in source; set in `.env` on homelab)
- `P2P_MANIFEST_TIMEOUT_SECONDS` (default: `20`)
- `P2P_ENGINE_SESSION_CREATE_TIMEOUT_SECONDS` (default: `20`)
- `P2P_ENGINE_WARMUP_TIMEOUT_SECONDS` (default: `150`)
- `P2P_SEGMENT_TIMEOUT_SECONDS` (default: `5`)
- `P2P_BROKER_RETRY_COOLDOWN_SECONDS` (default: `12`)
- `P2P_BROKER_MAX_RETRYABLE_PREPARE_ATTEMPTS` (default: `3`; repeated retryable warmup failures become a clean failed state)
- `P2P_BROKER_MANIFEST_FRESH_SECONDS` (default: `12`; cached live manifests older than this are revalidated before being served)
- `P2P_BROKER_MANIFEST_STALE_GRACE_SECONDS` (default: `15`)
- `P2P_REDIS_URL` or `REDIS_URL` (optional; enables shared broker sessions across workers)
- `P2P_REDIS_KEY_PREFIX` (default: `fotty:p2p:broker`)
- `P2P_BROKER_REDIS_RECORD_TTL_SECONDS` (default: warmup budget plus 300s)
- `P2P_BROKER_REDIS_CONNECT_TIMEOUT_SECONDS` / `P2P_BROKER_REDIS_SOCKET_TIMEOUT_SECONDS` (default: `2`; keeps Redis outages from hanging broker startup or health checks)
- `P2P_PREWARM_ENABLED` (default: off; set to `true` to keep likely channels warming before taps)
- `P2P_PREWARM_CHANNEL_SOURCE_URL` (production uses the embedded catalog at `http://127.0.0.1:8006/matches`)
- `P2P_PREWARM_BASE_URL` (public broker base URL used in returned session links)
- `P2P_PREWARM_INTERVAL_SECONDS` (default: `45`)
- `P2P_PREWARM_LIMIT` (default: `6`)
- `P2P_PREWARM_CONCURRENT_LIMIT` (default: `1`; keep this low because the AceStream engine does not warm many channels reliably in parallel)
- `P2P_PREWARM_MIN_AVAILABILITY` (default: `0.75`; availability is weak metadata, health still decides ranking)
- `P2P_PREWARM_EVIDENCE_MAX_AGE_SECONDS` (default: `21600`; unpinned channels need recent successful manifest/segment evidence)
- `P2P_PREWARM_PINNED_CIDS` (optional comma-separated CIDs to keep warm even after recent failures)
- `P2P_MIN_SEGMENT_BYTES` (default: `512`)
- `P2P_MAX_SEGMENTS_TO_VALIDATE` (default: `8`)
- `PORT` (default: `8006`)
- `P2P_SCRAPER_US_UK_QUERIES` (optional comma-separated AceStream text searches; default list in `p2p_scraper_queries.py` covers NFL/MLB/NHL/CBS SN, Sky F1/Golf, Racing TV, etc.)
- `P2P_SCRAPER_EXTRA_QUERIES` (optional; overrides core PL/UCL/NBA search terms)
- `P2P_SCRAPER_MAX_TEXT_QUERIES` (default: `120`; US/UK network queries are prioritized first)
- `P2P_SCRAPER_SPORT_PAGE_SIZE` / `P2P_SCRAPER_EXTRA_PAGE_SIZE` (sport category vs per-query page sizes)

Homelab redeploy after changing scraper queries:

```bash
./tools/p2p-proxy-deploy-homelab.sh
```

### Pinned channels (when Ace search has no results)

US league linear nets (NFL/MLB/NHL/CBS SN) and some UK feeds may not appear in the AceStream
engine index even with text search. Add confirmed infohashes to `server/p2p_pinned_channels.json`
(only non-empty 40-char `cid` values are merged). The homelab container mounts this file read-only
so you can update CIDs without rebuilding the image.

Probe a query on the running proxy:

```bash
curl -sS -H "Authorization: Bearer $P2P_API_PASSWORD" \
  "https://scraper.pixel-invoice.com/search/nfl%20network" | python3 -m json.tool
```

The Docker image runs Flask through Gunicorn using `gthread`. Production explicitly uses two
workers × 16 threads with Redis. Keep `GUNICORN_WORKERS=1` when `P2P_REDIS_URL` is not set.
Once Redis is enabled, multiple workers share broker sessions, per-CID dedupe, event timelines,
and CID health history safely.

Retryable validation failures surface as `retrying` instead of an endless `warming` state. The
broker still retries them on the normal cooldown, but clients can show a clearer message while
preferring sessions that are already `ready`.

## TV guide / EPG (retired)

Homelab XMLTV/EPG infrastructure has been removed. There is no `server/epg/` bundle, no `/epg/*` broker endpoints, and no `EPG_*` env vars on this service.

## Endpoints

- `GET /proxy/acestream/stream?id=<cid>&api_password=<password>`
- `POST /proxy/acestream/session`
- `GET /proxy/acestream/session/<session_id>/status`
- `GET|POST /proxy/acestream/prewarm`
- `GET /ace/proxy?cid=<cid>&url=<encoded_segment_url>`
- `GET /metrics` (broker authorization required)
- `GET /health`
- `GET /matches`, `GET /status`, and `GET /search/<query>` (broker authorization required)
- `GET /dashboard` — private Glances-style page that polls `/health` + `/metrics` every 1.5s (disabled in production; enable with `P2P_DASHBOARD_ENABLED=1` and require either broker authorization or `P2P_DASHBOARD_KEY`)

AceStream sessions request API events and stop notifications. Broker events distinguish codec
discovery, segmenter failure, engine stop, and missing `proxyServer` entitlement. Capture a
five-minute free/paid comparison with `server/scripts/acestream_premium_baseline.py`; the script
reads `P2P_API_PASSWORD` from the environment and never writes it to the result.
