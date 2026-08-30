"use client";

import { useCallback, useEffect, useRef, useState } from "react";

export function useMatchFeedPoll(
  onPoll: () => boolean | void | Promise<boolean | void>,
  intervalMs = 120_000,
  enabled = true
) {
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const onPollRef = useRef(onPoll);
  onPollRef.current = onPoll;

  const markUpdated = useCallback(() => {
    setLastUpdated(new Date());
  }, []);

  const runPoll = useCallback(async () => {
    if (typeof document !== "undefined" && document.visibilityState === "hidden") return;
    const result = await onPollRef.current();
    if (result !== false) setLastUpdated(new Date());
  }, []);

  useEffect(() => {
    if (!enabled) return;
    void runPoll();
    const id = window.setInterval(() => {
      void runPoll();
    }, intervalMs);
    return () => window.clearInterval(id);
  }, [enabled, intervalMs, runPoll]);

  return { lastUpdated, markUpdated, refreshNow: runPoll };
}
