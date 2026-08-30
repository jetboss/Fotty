import { fottyFeedLabel } from "@/lib/watch-stream-display";
import { eventSourceDisplayName } from "./feed-label";
import { healthScoreFromHeatTier, healthStateFromScore } from "./health";
import { p2pHealthToScore, p2pHealthToStatus } from "./p2p-health";
import type {
  EventStreamVariantWithSignals,
  P2PGuideSignals,
  RankedStreamGuide,
  StreamGuideGroup,
  StreamSource,
} from "./types";

function heatTierRank(value?: string) {
  switch (value?.toLowerCase()) {
    case "veryhigh":
      return 0;
    case "high":
      return 1;
    case "medium":
      return 2;
    case "low":
      return 3;
    default:
      return 4;
  }
}

function isWeakCatalogTier(value?: string) {
  const tier = value?.toLowerCase() || "";
  return tier === "legacy" || tier === "synthesized";
}

const SOURCE_CODE_ORDER: Record<string, number> = {
  admin: 0,
  delta: 1,
  golf: 2,
  hotel: 3,
  echo: 4,
  india: 5,
  alpha: 6,
};

function sourceCodeRank(source?: string) {
  if (!source) return 99;
  return SOURCE_CODE_ORDER[source.toLowerCase()] ?? 50;
}

function compareEventVariants(a: EventStreamVariantWithSignals, b: EventStreamVariantWithSignals) {
  // Prefer real active rows over legacy fallbacks.
  const weakDelta = Number(isWeakCatalogTier(a.heatTier)) - Number(isWeakCatalogTier(b.heatTier));
  if (weakDelta !== 0) return weakDelta;
  const heatDelta = heatTierRank(a.heatTier) - heatTierRank(b.heatTier);
  if (heatDelta !== 0) return heatDelta;
  if ((b.viewers || 0) !== (a.viewers || 0)) return (b.viewers || 0) - (a.viewers || 0);
  const sourceDelta = sourceCodeRank(a.source) - sourceCodeRank(b.source);
  if (sourceDelta !== 0) return sourceDelta;
  if (a.hd !== b.hd) return Number(b.hd) - Number(a.hd);
  return (a.streamNo || 1) - (b.streamNo || 1);
}

function eventVariantToSource(
  variant: EventStreamVariantWithSignals,
  rankIndex: number,
  matchId: string | undefined,
  eventIndex: number
): StreamSource {
  const inferredScore =
    healthScoreFromHeatTier(variant.heatTier) ??
    (variant.hd ? 72 : 58) + Math.min(variant.viewers || 0, 5000) / 500;
  const healthScore = Math.round(Math.min(100, Math.max(0, inferredScore)));
  const status = healthStateFromScore(healthScore);
  const hasStrongSignal = Boolean(variant.heatTier);

  return {
    id: `event-${variant.streamNo}-${eventIndex}`,
    matchId,
    displayName: eventSourceDisplayName(variant.source, variant.streamNo || rankIndex + 1),
    providerType: "embed",
    streamType: rankIndex === 0 ? "direct" : "backup",
    quality: variant.hd ? "HD" : "SD",
    status,
    healthScore,
    isRecommended: rankIndex === 0,
    isBackup: rankIndex > 0,
    requiresP2P: false,
    priority: 100 - rankIndex,
    diagnosticsSafeId: `embed-${variant.streamNo}`,
    whyThis:
      rankIndex === 0
        ? "Top-ranked feed for this match based on stability signals."
        : "Alternate feed if the first one buffers.",
    eventIndex,
    language: variant.language,
    viewers: variant.viewers,
    inferredHealth: hasStrongSignal || !variant.heatTier,
  };
}

export function rankEventStreamGuide(
  variants: EventStreamVariantWithSignals[],
  matchId?: string
): RankedStreamGuide {
  const indexed = variants.map((variant, eventIndex) => ({ variant, eventIndex }));
  const sorted = [...indexed].sort((a, b) => compareEventVariants(a.variant, b.variant));
  const all = sorted.map(({ variant, eventIndex }, rankIndex) =>
    eventVariantToSource(variant, rankIndex, matchId, eventIndex)
  );

  if (all.length > 0) {
    all[0] = {
      ...all[0],
      displayName: eventSourceDisplayName(sorted[0]?.variant.source, sorted[0]?.variant.streamNo || 1),
      isRecommended: true,
      isBackup: false,
      streamType: "direct",
    };
    for (let i = 1; i < all.length; i += 1) {
      all[i] = {
        ...all[i],
        displayName: eventSourceDisplayName(sorted[i]?.variant.source, sorted[i]?.variant.streamNo || i + 1),
        isRecommended: false,
        isBackup: true,
        streamType: "backup",
      };
    }
  }

  const recommended = all[0] ?? null;
  const backups = all.slice(1);
  const stable = backups.filter((s) => s.status === "excellent" || s.status === "good" || s.status === "fair");
  const lowerConfidence = backups.filter((s) => s.status === "unstable" || s.status === "unknown");
  const offline = all.filter((s) => s.status === "offline");

  const groups: StreamGuideGroup[] = [];
  if (recommended) {
    groups.push({
      id: "recommended",
      title: "Recommended",
      description: "Fotty’s first pick for this match.",
      sources: [recommended],
    });
  }
  if (stable.length > 0) {
    groups.push({
      id: "stable",
      title: "Stable backups",
      description: "Reliable alternates if the main feed stalls.",
      sources: stable,
    });
  }
  if (lowerConfidence.length > 0) {
    groups.push({
      id: "lower-confidence",
      title: "Lower confidence",
      description: "Worth trying if other feeds are busy or offline.",
      sources: lowerConfidence,
    });
  }
  if (offline.length > 0) {
    groups.push({
      id: "offline",
      title: "Currently offline",
      description: "Fotty will keep checking these feeds.",
      sources: offline,
    });
  }

  return { recommended, backups, groups, all };
}

export function buildP2PStreamGuide(signals: P2PGuideSignals): RankedStreamGuide {
  const { telemetry, isWarming, isActive, cid, matchId, p2pHealth } = signals;
  const hasPeers = telemetry.peerCount > 0;
  const hasSegments = telemetry.readySegmentCount > 0 || telemetry.firstSegmentReady;
  const hasSpeed = telemetry.downloadSpeedKbps > 0;
  const probeScore = p2pHealthToScore(p2pHealth);
  const probeStatus = p2pHealth ? p2pHealthToStatus(p2pHealth) : null;

  let healthScore: number | null = probeScore;
  let status = probeStatus ?? healthStateFromScore(null);
  let inferredHealth = !p2pHealth;

  if (isWarming) {
    status = "checking";
    healthScore = probeScore;
    inferredHealth = true;
  } else if (probeStatus === "offline" && !hasPeers && !hasSegments) {
    status = "offline";
    healthScore = probeScore ?? 15;
    inferredHealth = Boolean(p2pHealth);
  } else if (isActive && hasSegments && hasSpeed) {
    const liveScore = Math.min(98, 75 + Math.min(telemetry.peerCount, 12) * 2);
    healthScore = probeScore !== null ? Math.round((probeScore + liveScore) / 2) : liveScore;
    status = healthStateFromScore(healthScore);
    inferredHealth = probeScore === null;
  } else if (hasPeers || hasSegments) {
    healthScore = probeScore !== null ? Math.max(probeScore, 62) : 62;
    status = healthStateFromScore(healthScore);
    inferredHealth = probeScore === null;
  } else if (telemetry.error) {
    status = probeStatus && probeStatus !== "checking" ? probeStatus : "unstable";
    healthScore = probeScore ?? 40;
    inferredHealth = !p2pHealth;
  } else if (!p2pHealth) {
    status = "checking";
    healthScore = null;
    inferredHealth = true;
  }

  const whyParts: string[] = [];
  if (isWarming) {
    whyParts.push("P2P streams may take a few seconds to stabilize while peers connect.");
  } else {
    whyParts.push("Primary P2P feed for this channel from the Live Board.");
  }
  if (p2pHealth?.latencyMs) {
    whyParts.push(`Last probe ${p2pHealth.latencyMs}ms.`);
  }

  const source: StreamSource = {
    id: `p2p-${cid}`,
    matchId,
    displayName: "Best Stream",
    providerType: "p2p",
    streamType: "p2p",
    quality: "Auto",
    status,
    healthScore,
    lastCheckedAt: p2pHealth?.checkedAt,
    latencyMs: p2pHealth?.latencyMs,
    isRecommended: true,
    isBackup: false,
    requiresP2P: true,
    peerStrength: telemetry.peerCount,
    priority: 100,
    diagnosticsSafeId: `p2p-${cid.slice(0, 8)}`,
    whyThis: whyParts.join(" "),
    inferredHealth,
  };

  return {
    recommended: source,
    backups: [],
    groups: [
      {
        id: "p2p",
        title: "P2P source",
        description: "Use Live Board to switch channels for this match.",
        sources: [source],
      },
    ],
    all: [source],
  };
}

export function pickBackupAfterFailure(
  guide: RankedStreamGuide,
  failedSourceId?: string,
  alsoFailedSourceIds?: Iterable<string>
): StreamSource | null {
  const failed = new Set<string>();
  if (failedSourceId) failed.add(failedSourceId);
  if (alsoFailedSourceIds) {
    for (const id of alsoFailedSourceIds) failed.add(id);
  }
  const candidates = guide.all.filter((source) => !failed.has(source.id) && source.status !== "offline");
  const backup = candidates[0] ?? guide.backups.find((source) => !failed.has(source.id)) ?? null;
  return backup;
}
