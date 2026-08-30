# Fotty Web — deploy notes

## Current hosting (homelab retired)

| Surface | Build | Notes |
|---------|-------|--------|
| **getfotty.com** (Apache / FTP) | `npm run build:static` → upload `web/out/` | Primary public site. No Node server. |
| **Playback Worker** (`web/workers/playback`) | `npx wrangler deploy` | Streams catalog for Watch; not full iOS unmute/HLS parity. |
| Homelab Docker / PocketBase | **Retired** | Accounts disabled on web (`NEXT_PUBLIC_ACCOUNTS_ENABLED` unset). Watch is open to guests. |

Do **not** set `NEXT_PUBLIC_ACCOUNTS_ENABLED=true` until a replacement auth host exists. Same-origin unmute/HLS still needs a non-blocked VPS (deferred).

Static export patches watch/auth routes to `force-static` for that build only (`scripts/patch-watch-routes-static.sh`). Source of truth for any future Node deploy remains `force-dynamic` in `web/src/lib/route-segment-config.ts`.

## iOS ↔ web Watch parity

The iOS app plays StreamEx / VipLeague (and other catalog embeds) by:

1. Resolving feeds (`echo` → `delta` → …)
2. Injecting StreamEx **Referer**
3. Proxying HLS segments locally (`LocalStreamProxy`)

Browsers cannot set those headers on cross-origin media. On getfotty.com you must point the static site at the playback Worker:

```bash
# 1) Deploy Worker once
cd web/workers/playback
npx wrangler deploy

# 2) Rebuild static site against that Worker
cd ../..
NEXT_PUBLIC_FOTTY_API_BASE=https://fotty-playback-v3.adaptive-rhubarb.workers.dev npm run build:static
# Upload web/out/ to FTP (getfotty.com)
```

Live Worker (stream catalog): `https://fotty-playback-v3.adaptive-rhubarb.workers.dev`
In-page Watch iframes `embed.st` directly. `/playback/*.php` returns **410** (proxy retired on this host).

For future Worker deploys, set `CLOUDFLARE_API_TOKEN` (dashboard password alone is not enough for wrangler).

Retired / not in scope: AceStream, P2P `admin`, EPG.

## Deploy to getfotty.com

```bash
cd web
npm run build:static
# Upload contents of web/out/ to the FTP web root (Octavia / getfotty.com)
```

## Required env (local / CI build)

| Variable | Purpose |
|----------|---------|
| `NEXT_PUBLIC_SITE_URL` | Canonical URLs, OG tags (`https://getfotty.com`) |
| `NEXT_PUBLIC_FOTTY_API_BASE` | **Required for Watch streams/embed** — Worker origin (no trailing slash). Does **not** replace `/api/matches` (that stays same-origin static JSON). |
| `FOOTBALL_DATA_API_KEY` | Optional standings / match proxy at build time |

Match feed is the **StreamEx / Nexus catalog** (same as the iOS app: VipLeague=`echo`, StreamEx=`delta`, other web embeds). Baked into `/api/matches` at `build:static` time — redeploy to refresh. Retired P2P `admin` sources are stripped. Source order matches iOS: `echo`, `delta`, `hotel`, `india`, `golf`, `alpha`.

## Product posture

- **iOS app** is primary (cinema Home, On-now, stream modules, Watch Now health).
- **getfotty.com** is coverage / companion — Home + Discover + Schedule + Watch.
- **Removed:** TV Guide, Live Board, EPG/XMLTV, P2P channel catalog, World Cup hubs.
