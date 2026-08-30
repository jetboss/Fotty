"use client";

import type Hls from "hls.js";
import { logStreamDiagnostic } from "@/lib/stream-guide/diagnostics";

const MEDIA_LOADER_SCRIPT_ID = "fotty-p2p-media-loader-hlsjs";
const MEDIA_LOADER_IIFE_URL =
  "https://cdn.jsdelivr.net/npm/p2p-media-loader-hlsjs@3.0.1/dist/p2p-media-loader-hlsjs.iife.min.js";
const STORAGE_KEY = "fotty:p2p-delivery-engine";

type HlsConstructor = typeof Hls;
type DeliveryMode = "plain-hls" | "webrtc-hls" | "webrtc-fallback";

interface P2PMediaLoaderWindow extends Window {
  p2pml?: {
    hlsjs?: {
      HlsJsP2PEngine?: {
        injectMixin: (hls: HlsConstructor) => HlsConstructor;
      };
    };
  };
  __fottyP2PDelivery?: {
    mode: DeliveryMode;
    swarmId?: string;
    eventCounts: Record<string, number>;
    lastEvent?: string;
    lastUpdatedAt: string;
  };
}

export interface P2PDeliverySetup {
  HlsConstructor: HlsConstructor;
  mode: DeliveryMode;
  swarmId?: string;
}

function normalizeDeliveryPreference(value: string | null | undefined): "plain-hls" | "webrtc-hls" | null {
  const normalized = (value || "").trim().toLowerCase();
  if (!normalized) return null;
  if (["1", "true", "on", "webrtc", "webrtc-hls", "media-loader", "p2p"].includes(normalized)) {
    return "webrtc-hls";
  }
  if (["0", "false", "off", "plain", "plain-hls", "hls"].includes(normalized)) {
    return "plain-hls";
  }
  return null;
}

export function p2pDeliveryPreference(): "plain-hls" | "webrtc-hls" {
  if (typeof window === "undefined") {
    return normalizeDeliveryPreference(process.env.NEXT_PUBLIC_P2P_DELIVERY_ENGINE) || "plain-hls";
  }

  const query = new URL(window.location.href).searchParams.get("p2pDelivery");
  const fromQuery = normalizeDeliveryPreference(query);
  if (fromQuery) {
    try {
      window.localStorage.setItem(STORAGE_KEY, fromQuery);
    } catch {
      // Local storage is optional; the query flag is enough for this page load.
    }
    return fromQuery;
  }

  let stored: string | null = null;
  try {
    stored = window.localStorage.getItem(STORAGE_KEY);
  } catch {
    stored = null;
  }

  return (
    normalizeDeliveryPreference(stored) ||
    normalizeDeliveryPreference(process.env.NEXT_PUBLIC_P2P_DELIVERY_ENGINE) ||
    "plain-hls"
  );
}

function stableSwarmId(streamSrc: string): string {
  try {
    const url = new URL(streamSrc, window.location.origin);
    const cid = url.searchParams.get("id") || url.searchParams.get("infohash") || url.searchParams.get("cid");
    if (cid) return `fotty-ace:${cid}`;
    return `fotty-hls:${url.origin}${url.pathname}`;
  } catch {
    return `fotty-hls:${streamSrc.split("?")[0]}`;
  }
}

function updateDeliveryDebug(mode: DeliveryMode, swarmId: string | undefined, eventName?: string) {
  const target = window as P2PMediaLoaderWindow;
  const current = target.__fottyP2PDelivery;
  const eventCounts = { ...(current?.eventCounts || {}) };
  if (eventName) eventCounts[eventName] = (eventCounts[eventName] || 0) + 1;
  target.__fottyP2PDelivery = {
    mode,
    swarmId,
    eventCounts,
    lastEvent: eventName || current?.lastEvent,
    lastUpdatedAt: new Date().toISOString(),
  };
  document.documentElement.dataset.fottyP2PDelivery = mode;
  if (swarmId) document.documentElement.dataset.fottyP2PSwarm = swarmId;
  document.documentElement.dataset.fottyP2PEvents = JSON.stringify(eventCounts);
  if (eventName) document.documentElement.dataset.fottyP2PLastEvent = eventName;
}

function loadScript(src: string): Promise<void> {
  const existing = document.getElementById(MEDIA_LOADER_SCRIPT_ID) as HTMLScriptElement | null;
  if (existing) {
    if (existing.dataset.ready === "true") return Promise.resolve();
    return new Promise((resolve, reject) => {
      existing.addEventListener("load", () => resolve(), { once: true });
      existing.addEventListener("error", () => reject(new Error("P2P Media Loader script failed")), { once: true });
    });
  }

  return new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.id = MEDIA_LOADER_SCRIPT_ID;
    script.src = src;
    script.async = true;
    script.crossOrigin = "anonymous";
    script.onload = () => {
      script.dataset.ready = "true";
      resolve();
    };
    script.onerror = () => reject(new Error("P2P Media Loader script failed"));
    document.head.appendChild(script);
  });
}

function attachP2PDiagnostics(hls: Hls & { p2pEngine?: EventTarget }, swarmId: string) {
  const engine = hls.p2pEngine;
  if (!engine || typeof engine.addEventListener !== "function") return;

  const eventNames = ["onPeerConnect", "onPeerClose", "onChunkDownloaded", "onChunkUploaded"] as const;
  for (const eventName of eventNames) {
    engine.addEventListener(eventName, (event) => {
      updateDeliveryDebug("webrtc-hls", swarmId, eventName);
      const detail = "detail" in event ? (event as CustomEvent<Record<string, unknown>>).detail : undefined;
      logStreamDiagnostic("stream_health_refresh", {
        playbackMode: "p2p",
        providerType: "webrtc-hls",
        healthState: eventName,
        sourceId: swarmId,
        peerId: typeof detail?.peerId === "string" ? detail.peerId : undefined,
        bytes:
          typeof detail?.bytes === "number"
            ? detail.bytes
            : typeof detail?.byteLength === "number"
              ? detail.byteLength
              : undefined,
      });
    });
  }
}

export async function resolveP2PDeliverySetup(
  HlsBase: HlsConstructor,
  streamSrc: string
): Promise<P2PDeliverySetup> {
  if (p2pDeliveryPreference() !== "webrtc-hls") {
    return { HlsConstructor: HlsBase, mode: "plain-hls" };
  }

  const swarmId = stableSwarmId(streamSrc);

  try {
    await loadScript(MEDIA_LOADER_IIFE_URL);
    const mediaLoader = (window as P2PMediaLoaderWindow).p2pml?.hlsjs?.HlsJsP2PEngine;
    if (!mediaLoader) {
      throw new Error("P2P Media Loader API unavailable");
    }

    return {
      HlsConstructor: mediaLoader.injectMixin(HlsBase),
      mode: "webrtc-hls",
      swarmId,
    };
  } catch (error) {
    updateDeliveryDebug("webrtc-fallback", swarmId, "webrtc_hls_unavailable");
    logStreamDiagnostic("stream_health_refresh", {
      playbackMode: "p2p",
      providerType: "webrtc-hls",
      healthState: "webrtc_hls_unavailable",
      sourceId: swarmId,
      reason: error instanceof Error ? error.message : "media_loader_unavailable",
    });
    return { HlsConstructor: HlsBase, mode: "webrtc-fallback", swarmId };
  }
}

export function p2pHlsConfig(swarmId: string | undefined) {
  if (!swarmId) return {};
  return {
    p2p: {
      core: {
        swarmId,
      },
      onHlsJsCreated: (hls: Hls & { p2pEngine?: EventTarget }) => {
        updateDeliveryDebug("webrtc-hls", swarmId, "webrtc_hls_created");
        attachP2PDiagnostics(hls, swarmId);
        logStreamDiagnostic("stream_health_refresh", {
          playbackMode: "p2p",
          providerType: "webrtc-hls",
          healthState: "webrtc_hls_created",
          sourceId: swarmId,
        });
      },
    },
  };
}
