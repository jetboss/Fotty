"use client";

import { useEffect, useState } from "react";

export function useLoadingTimeout(active: boolean, timeoutMs = 12_000) {
  const [timedOut, setTimedOut] = useState(false);

  useEffect(() => {
    if (!active) {
      setTimedOut(false);
      return;
    }

    const timer = window.setTimeout(() => setTimedOut(true), timeoutMs);
    return () => window.clearTimeout(timer);
  }, [active, timeoutMs]);

  return timedOut;
}
