# Fotty Web

Next.js companion/PWA surface for Fotty live-sports discovery and browser playback.

The supported web product is deliberately small: static discovery pages, four
same-origin catalog/football routes for standalone builds, and the separate
Cloudflare playback/Coach Worker. It has no account, billing, admin, PocketBase,
P2P, movie/TV, or same-origin embed-proxy service.

## Getting Started

Install dependencies, then run the safer webpack dev server:

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser.

## Test Build

Use the production-style standalone path for readiness checks:

```bash
npm run lint
npm run build:standalone
npm run preview:standalone
```

The standalone server uses `PORT` when you need another port:

```bash
PORT=3001 npm run preview:standalone
```

## Notes

- `/` loads fixture data in the browser (Home / Discover / Schedule).
- `/api/matches` is the main live feed smoke endpoint.
- Local preview unregisters service workers so stale PWA caches do not interfere with testing.
