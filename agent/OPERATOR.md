# Fotty Operator Guide

## Active services

- **iOS/iPadOS app**: distributed to internal testers through App Store Connect and TestFlight.
- **Public web companion**: static export deployed to getfotty.com by `tools/web-deploy-ftp.sh`.
- **Playback and Coach API**: Cloudflare Worker defined in `web/workers/playback/`.
- **Repository controls**: protected `main`, Actions gates, secret scanning, push protection, Dependabot, and CodeQL.

## Retired infrastructure

The homelab, PocketBase, AceStream/P2P services, Tailscale deployment path, and Cloudflare Tunnels are gone. Do not probe old hosts, recreate tunnels, or treat old deployment notes in the decision history as current instructions.

## Secrets

Production credentials belong only in App Store Connect, Cloudflare Worker secrets, GitHub encrypted secrets, or the operator's local environment. Never write credentials, provider tokens, private stream URLs, or signing material into tracked files or generated project-memory documents.

## Release operations

- Verify web changes locally and in GitHub Actions before deployment.
- Verify iOS changes through the simulator-free Xcode gate.
- Use TestFlight for tester-facing builds and preserve the build/release record in `docs/releases/`.
- Keep direct device installation for narrow owner-only acceptance checks.
- Remove temporary archives, DerivedData, result bundles, and screenshots after use.
