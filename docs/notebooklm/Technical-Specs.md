# Fotty Technical Specifications

## 1. Database Schema (PocketBase)

We use a self-hosted PocketBase instance for all sports metadata. This replaces the rate-limited TheSportsDB API.

### `leagues` Collection
- `id`: (Standard PB ID)
- `name`: (String) e.g., "Premier League"
- `slug`: (String) e.g., "english-premier-league"
- `external_id`: (String) Mapping ID for external providers.
- `logo_url`: (URL) High-fidelity CDN link.

### `teams` Collection
- `id`: (Standard PB ID)
- `name`: (String) e.g., "Arsenal"
- `league`: (Relation -> leagues)
- `external_id`: (String) Mapping ID.
- `badge_url`: (URL) ESPN/CDN link.
- `primary_color`: (Hex) e.g., "#EF0107"
- `secondary_color`: (Hex)

## 2. Authentication Strategy
**Current**: PocketBase Auth (Internal).
**Status**: We have successfully moved away from Firebase/Supabase to maintain 100% self-hosted data sovereignty. Agents should NOT propose Firebase/Supabase integrations.

## 3. Playback Resolution Logic (Sub-10s)
- **Layer 1**: Direct manifest resolution (5s timeout).
- **Layer 2**: Web extraction (8s timeout).
- **Pre-warming**: The server (3050 Ti) pre-calculates stream health via `p2p_proxy_service.py` to ensure the iOS app receives a "hot" URL.
