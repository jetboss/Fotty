# getfotty.com website — parked

Parked 8 November 2026 by owner decision until the iOS app is stable.

- The Next.js companion under `web/src`, `web/public` and `web/e2e` is kept
  unchanged for a later relaunch. Nothing is deployed from it.
- `tools/web-deploy-ftp.sh` refuses to run unless `FOTTY_WEB_UNPARK=1`.
- Web CI no longer runs the site lint or Next.js build. It still runs the
  shared unit tests, type check and Worker dry run.
- The Cloudflare Worker (`web/workers/playback`, `web/workers/watchdog`) is
  NOT parked. The iOS app depends on it for fixtures and the stream catalog.

Before relaunch: move hosting off plaintext FTP (Cloudflare Pages on the same
account as the Worker gives atomic deploys, previews and rollback), restore the
Lint and Build steps in `.github/workflows/web.yml`, and remove this guard.
