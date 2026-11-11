import type { EventStreamVariant } from "@/lib/api";

type StreamProviderType = "embed";
type StreamDeliveryType = "direct" | "backup";

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
  id: "recommended" | "stable" | "lower-confidence" | "offline";
  title: string;
  description?: string;
  sources: StreamSource[];
}

export type EventStreamVariantWithSignals = EventStreamVariant & {
  heatTier?: string;
};
