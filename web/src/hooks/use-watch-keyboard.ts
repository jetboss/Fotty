"use client";

import { useEffect } from "react";

export function useWatchKeyboard(options: {
  enabled?: boolean;
  feedCount?: number;
  onSelectFeed?: (index: number) => void;
  onBack?: () => void;
  onTogglePiP?: () => void;
}) {
  const { enabled = true, feedCount = 0, onSelectFeed, onBack, onTogglePiP } = options;

  useEffect(() => {
    if (!enabled) return;

    function handleKeyDown(event: KeyboardEvent) {
      const target = event.target as HTMLElement | null;
      if (target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable)) {
        return;
      }

      if (event.key === "Escape") {
        event.preventDefault();
        onBack?.();
        return;
      }

      if ((event.key === "p" || event.key === "P") && onTogglePiP) {
        event.preventDefault();
        onTogglePiP();
        return;
      }

      const digit = Number(event.key);
      if (Number.isInteger(digit) && digit >= 1 && digit <= 9 && digit <= feedCount) {
        event.preventDefault();
        onSelectFeed?.(digit - 1);
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [enabled, feedCount, onBack, onSelectFeed, onTogglePiP]);
}
