"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { FottyAPI, ScrapedMatch, SwarmStatus } from "@/lib/api";
import { logStreamDiagnostic } from "@/lib/stream-guide";

const P2P_WARMUP_TIMEOUT_MS = 75_000;

export type BrokerPlaybackState = "idle" | "warming" | "ready" | "failed";

/**
 * Owns the P2P broker playback lifecycle for the watch page:
 * session warm-up (with timeout), swarm telemetry polling, and channel health checks.
 */
export function useP2PBrokerSession({
  enabled,
  cid,
  title,
  matchId,
}: {
  /** watch access granted and not in direct-event playback */
  enabled: boolean;
  cid: string;
  title: string;
  matchId: string;
}) {
  const [brokerPlaybackState, setBrokerPlaybackState] = useState<BrokerPlaybackState>("idle");
  const [brokerWarmMessage, setBrokerWarmMessage] = useState("Preparing P2P broker session…");
  const [brokerSessionId, setBrokerSessionId] = useState<string | null>(null);
  const [brokerWarmStartedAt, setBrokerWarmStartedAt] = useState<number | undefined>();
  const [playerGeneration, setPlayerGeneration] = useState(0);
  const [telemetry, setTelemetry] = useState<SwarmStatus>({
    peerCount: 0,
    downloadSpeedKbps: 0,
    bufferSeconds: 0,
    readySegmentCount: 0,
    firstSegmentReady: false,
    error: "Initializing...",
  });
  const [p2pHealth, setP2PHealth] = useState<ScrapedMatch["p2pHealth"]>();
  const brokerWarmTimeoutRef = useRef<number | null>(null);
  const forceNextSessionRef = useRef(false);

  // Channel health refresh (90s cadence).
  useEffect(() => {
    if (!enabled || !cid) return;
    let cancelled = false;

    const refreshHealth = () => {
      FottyAPI.checkP2PHealth(cid)
        .then((health) => {
          if (!cancelled) {
            setP2PHealth(health);
            logStreamDiagnostic("stream_health_refresh", {
              matchId,
              healthState: health.playable ? "good" : "offline",
              playbackMode: "p2p",
            });
          }
        })
        .catch(() => undefined);
    };

    refreshHealth();
    const interval = window.setInterval(refreshHealth, 90_000);
    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, [cid, enabled, matchId]);

  // Broker session warm-up with hard timeout.
  useEffect(() => {
    if (!enabled || !cid) {
      setBrokerPlaybackState("idle");
      setBrokerSessionId(null);
      setBrokerWarmStartedAt(undefined);
      forceNextSessionRef.current = false;
      return;
    }

    let cancelled = false;
    const forceNew = forceNextSessionRef.current;
    forceNextSessionRef.current = false;

    setBrokerPlaybackState("warming");
    setBrokerSessionId(null);
    setBrokerWarmStartedAt(Date.now());
    setBrokerWarmMessage("Checking stream signal…");

    if (brokerWarmTimeoutRef.current) {
      window.clearTimeout(brokerWarmTimeoutRef.current);
    }
    const failTimer = window.setTimeout(() => {
      if (cancelled) return;
      brokerWarmTimeoutRef.current = null;
      setBrokerPlaybackState((prev) => (prev === "warming" ? "failed" : prev));
      setBrokerWarmStartedAt(undefined);
      setBrokerWarmMessage("This source did not start quickly. Try again, choose another feed, or use the TV guide.");
    }, P2P_WARMUP_TIMEOUT_MS);
    brokerWarmTimeoutRef.current = failTimer;

    void FottyAPI.prepareP2PBrokerSession(cid, { title, forceNew })
      .then((result) => {
        if (cancelled) return;

        if (result?.ready && result.sessionId) {
          window.clearTimeout(failTimer);
          brokerWarmTimeoutRef.current = null;
          setBrokerSessionId(result.sessionId);
          setBrokerPlaybackState("ready");
          setBrokerWarmStartedAt(undefined);
          setBrokerWarmMessage("");
          return;
        }

        if (result?.sessionId) {
          setBrokerSessionId(result.sessionId);
          setBrokerPlaybackState("warming");
          setBrokerWarmMessage("Checking stream signal…");
          return;
        }

        window.clearTimeout(failTimer);
        brokerWarmTimeoutRef.current = null;
        setBrokerPlaybackState("failed");
        setBrokerWarmStartedAt(undefined);
        console.error("P2P broker session failed", result);
        const statusMessage =
          result?.status === 401
            ? "Your sign-in needs to be refreshed before this stream can open."
            : result?.status === 403
              ? "This account needs active live access before this stream can open."
              : result?.message || result?.error || "The stream broker could not prepare this source. Try another feed.";
        setBrokerWarmMessage(statusMessage);
      })
      .catch((error) => {
        if (cancelled) return;
        console.error("P2P broker session request failed", error);
        window.clearTimeout(failTimer);
        brokerWarmTimeoutRef.current = null;
        setBrokerPlaybackState("failed");
        setBrokerWarmStartedAt(undefined);
        setBrokerWarmMessage("This device could not reach the stream broker. Refresh Fotty or try another feed.");
      });

    return () => {
      cancelled = true;
      window.clearTimeout(failTimer);
      if (brokerWarmTimeoutRef.current === failTimer) {
        brokerWarmTimeoutRef.current = null;
      }
    };
  }, [cid, enabled, title, playerGeneration]);

  // Swarm telemetry polling — 2s while warming, 5s once steady.
  useEffect(() => {
    if (!enabled || !cid) return;

    const poll = async () => {
      try {
        const status = await FottyAPI.getSwarmStatus(cid, brokerSessionId);
        setTelemetry(status);
        const normalizedStatus = status.status?.trim().toLowerCase();
        const hasReadySignal =
          brokerSessionId &&
          (status.firstSegmentReady ||
            status.readySegmentCount > 0 ||
            normalizedStatus === "ready" ||
            normalizedStatus === "active");

        if (hasReadySignal) {
          if (brokerWarmTimeoutRef.current) {
            window.clearTimeout(brokerWarmTimeoutRef.current);
            brokerWarmTimeoutRef.current = null;
          }
          setBrokerPlaybackState("ready");
          setBrokerWarmStartedAt(undefined);
          setBrokerWarmMessage("");
        } else if (brokerPlaybackState === "failed" && brokerSessionId && normalizedStatus && !["failed", "error"].includes(normalizedStatus)) {
          setBrokerPlaybackState("warming");
          setBrokerWarmStartedAt((value) => value ?? Date.now());
          setBrokerWarmMessage("Checking stream signal…");
        }
      } catch (e) {
        console.error("Poll error", e);
      }
    };

    const interval = setInterval(poll, brokerPlaybackState === "warming" ? 2000 : 5000);
    poll();
    return () => {
      clearInterval(interval);
    };
  }, [brokerPlaybackState, brokerSessionId, cid, enabled]);

  /** Reset the broker session and bump the player generation (forces a fresh warm-up). */
  const retryBrokerSession = useCallback(() => {
    forceNextSessionRef.current = true;
    setBrokerPlaybackState("warming");
    setBrokerWarmMessage("Reconnecting P2P broker session…");
    setBrokerSessionId(null);
    setPlayerGeneration((value) => value + 1);
  }, []);

  return {
    brokerPlaybackState,
    brokerWarmMessage,
    brokerSessionId,
    brokerWarmStartedAt,
    playerGeneration,
    telemetry,
    p2pHealth,
    retryBrokerSession,
  };
}
