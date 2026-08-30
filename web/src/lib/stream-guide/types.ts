import type { EventStreamVariant, ScrapedMatch, SwarmStatus } from "@/lib/api";

export type StreamProviderType = "embed" | "p2p" | "hls";
export type StreamDeliveryType = "direct" | "p2p" | "hls" | "backup";

export type StreamHealthState =
  | "excellent"
  | "good"
  | "fair"
  | "unstable"
  | "offline"
  | "checking"
  | "unknown";

export interface StreamSource {
  id: string;
  matchId?: string;
  displayName: string;
  providerType: StreamProviderType;
  streamType: StreamDeliveryType;
  quality: "HD" | "SD" | "Auto";
  status: StreamHealthState;
  healthScore: number | null;
  lastCheckedAt?: string;
  latencyMs?: number;
  isRecommended: boolean;
  isBackup: boolean;
  requiresP2P: boolean;
  peerStrength?: number;
  regionNotes?: string;
  priority: number;
  diagnosticsSafeId: string;
  whyThis?: string;
  /** Index in original event stream list (embed only). */
  eventIndex?: number;
  language?: string;
  viewers?: number;
  inferredHealth?: boolean;
}

export interface RankedStreamGuide {
  recommended: StreamSource | null;
  backups: StreamSource[];
  groups: StreamGuideGroup[];
  all: StreamSource[];
}

export interface StreamGuideGroup {
  id: "recommended" | "stable" | "p2p" | "lower-confidence" | "offline";
  title: string;
  description?: string;
  sources: StreamSource[];
}

export type EventStreamVariantWithSignals = EventStreamVariant & {
  heatTier?: string;
};

export interface P2PGuideSignals {
  telemetry: SwarmStatus;
  isWarming: boolean;
  isActive: boolean;
  cid: string;
  matchId?: string;
  p2pHealth?: ScrapedMatch["p2pHealth"];
}
