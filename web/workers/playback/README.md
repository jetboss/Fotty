# Fotty playback Worker

Edge API so **getfotty.com** (static FTP) can play the same StreamEx / VipLeague embeds the iOS app plays.

iOS can use its native local proxy. Browser Watch stays on the third-party
provider origin; the Worker supplies source metadata and redirects only.

## Routes

| Path | Role |
|------|------|
| `GET /api/live/streams` | Catalog stream variants (echo/delta/…) |
| `GET /api/embed/player` | Validate the requested source identity and redirect to the provider origin |
| `POST /api/fpl/coach` | Rate-limited official FPL evidence check and structured DeepSeek proxy |
| `GET /api/football/matches` | Server-keyed football-data.org schedule and score fallback |
| `GET /api/football/live` | Optional Premier League live score/minute proxy via API-Football |
| `GET /health` | Smoke |

## Deploy

```bash
cd web/workers/playback
npx wrangler login
npx wrangler secret put DEEPSEEK_API_KEY
npx wrangler secret put FOOTBALL_DATA_API_KEY
# Optional but required for Premier League live scores and match minutes:
npx wrangler secret put API_FOOTBALL_KEY
npx wrangler deploy
```

Copy the Worker URL (e.g. `https://fotty-playback.<account>.workers.dev`).

Rebuild and FTP the site with the API base:

```bash
cd web
NEXT_PUBLIC_FOTTY_API_BASE=https://fotty-playback.<account>.workers.dev npm run build:static
# upload web/out/ to getfotty.com
```

Without `NEXT_PUBLIC_FOTTY_API_BASE`, Watch can still synthesize direct
`embed.st` iframe URLs, but it loses Worker-backed stream-variant lookup.

## Notes

- Local complexity-audit patch (2026-08-28; deployment is separate): `coach-request.mjs` validates bounded request bodies and handles limiter outages. Scoring questions stay deterministic even when official evidence is missing/incomplete/stale; unknown statistics never prove a non-appearance. A known official total may be returned with `officialDataStatus: "incomplete"`; otherwise the answer explicitly declines to calculate. Regression commands: `node --test src/coach-contract.test.mjs src/fpl-scoring.test.mjs`, or the full `npm run test:unit` from `web/`.
- Source order matches iOS: `echo`, `delta`, `hotel`, `india`, `golf`, `alpha`.
- P2P / AceStream / `admin` are not served.
- `FOTTY_PLAYBACK_OPEN=1` leaves stream lookup ungated for companion Watch; the Worker does not proxy provider media.
- The FPL coach never exposes `DEEPSEEK_API_KEY` to iOS. It limits request size, requires a per-installation identifier, applies per-installation/IP and per-location capacity limits, refreshes official public FPL evidence, and asks DeepSeek for structured evidence and assumptions. Current-points and automatic-substitution questions bypass DeepSeek: `fpl-scoring.mjs` deterministically applies completed-fixture, appearance, goalkeeper, bench-order, legal-formation, captain-fallback, and transfer-cost rules and returns zero model-token usage. Apply an account-level Cloudflare spend ceiling as the final abuse guardrail.
- The coach uses V4 Flash non-thinking JSON mode because measured thinking runs exhausted 1,400- and 3,000-token budgets without producing an answer. The Worker rejects empty, incomplete, or known rule-contradicting output and returns token counts for operator cost measurement. On 2026-08-23, a no-manager smoke cost about $0.00134 and a compact public-manager smoke cost about $0.00209 at then-current rates. Treat those as baselines, not fixed prices.
- Football provider keys stay in Worker secrets. `FOOTBALL_DATA_API_KEY` covers schedules available on that account. With one active score competition, `API_FOOTBALL_KEY` requests Premier League league `39` for the current season/date and the Worker retains only in-play statuses; if Champions League id `2` is later enabled, the provider's multi-league `live=39-2` form becomes valid. One SQLite Durable Object serializes the upstream feed globally, caches successful data for four minutes, caps Fotty at 80 upstream calls per UTC day, stops when API-Football reports 20 calls remaining, and remembers a current-season plan restriction for four hours. iOS loads its cached schedule first, does not call the route outside the Premier League match window, reuses live payloads in Match Hub, and visibly labels football-data fallback as delayed. The iOS binary contains neither key. A configured API-Football credential is not sufficient: the provider plan must include the current season.
