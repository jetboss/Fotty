# Homelab Operator Guide (Fotty)

This document tracks the server-side infrastructure powering the Fotty Brain.

## 1. Hardware Specification
- **CPU**: 8-Core high-performance CPU.
- **RAM**: 16GB.
- **GPU**: NVIDIA GeForce RTX 3050 Ti (Used for Ollama acceleration).

## 2. Core Services (Docker Compose)
The backend stack lives in `server/homelab-docker-compose.yml`.

- **Ollama**: Port `11434`. Handles embeddings (`nomic-embed-text`) and reasoning (`qwen2.5:3b`).
- **PocketBase**: Port `8090`. Main app database.
- **P2P Proxy**: Port `8006`. Resilient stream resolution.
- **Cloudflare Tunnel**: Manages external access via `*.pixel-invoice.com`.

## 3. Knowledge Base Ingestion
The server maintains a semantic index for AI agents.
- **Location**: `tools/brain/.cache/knowledge.jsonl` (generated).
- **Update Frequency**: On-demand via `./tools/private-kb-sync.sh`.
- **Health Check**: `./tools/brain-doctor.sh` verifies SSH, index content, required Ollama models, and a smoke retrieval.
- **Query Path**: `./tools/ask-brain.sh "question"` runs retrieval plus synthesis on the Homelab.

## 4. Networking
- **Local Access**: `192.168.100.253`.
- **Tailscale Access**: `homelab` (100.116.91.102) or `100.116.91.102`.
- **Public Entry**: `https://fotty-api.pixel-invoice.com`.

## 5. Maintenance
To restart the AI stack:
```bash
cd server
docker compose -f homelab-docker-compose.yml restart
```
