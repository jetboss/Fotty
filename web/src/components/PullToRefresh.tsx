"use client";

import { ReactNode, useEffect, useRef, useState } from "react";
import { RotateCw } from "lucide-react";
import { cn } from "@/lib/utils";

const TRIGGER_DISTANCE = 86;
const MAX_DISTANCE = 124;

function shouldIgnorePull(target: EventTarget | null) {
  if (!(target instanceof Element)) return false;
  return Boolean(
    target.closest("input, textarea, select, button, a, iframe, video, [data-pull-refresh-ignore]")
  );
}

export function PullToRefresh({
  children,
  onRefresh,
  className,
}: {
  children: ReactNode;
  onRefresh: () => Promise<unknown> | unknown;
  className?: string;
}) {
  const [distance, setDistance] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const startYRef = useRef<number | null>(null);
  const activeRef = useRef(false);
  const armedRef = useRef(false);
  const refreshRef = useRef(onRefresh);

  useEffect(() => {
    refreshRef.current = onRefresh;
  }, [onRefresh]);

  useEffect(() => {
    function onTouchStart(event: TouchEvent) {
      if (refreshing || window.scrollY > 0 || shouldIgnorePull(event.target)) {
        startYRef.current = null;
        activeRef.current = false;
        return;
      }
      startYRef.current = event.touches[0]?.clientY ?? null;
      activeRef.current = false;
      armedRef.current = false;
    }

    function onTouchMove(event: TouchEvent) {
      const startY = startYRef.current;
      if (startY === null || refreshing) return;

      const currentY = event.touches[0]?.clientY ?? startY;
      const delta = currentY - startY;
      if (delta <= 0) {
        setDistance(0);
        return;
      }

      if (window.scrollY <= 0) {
        activeRef.current = true;
        const eased = Math.min(MAX_DISTANCE, Math.round(delta * 0.55));
        setDistance(eased);
        armedRef.current = eased >= TRIGGER_DISTANCE;
        event.preventDefault();
      }
    }

    function onTouchEnd() {
      if (!activeRef.current) return;

      const shouldRefresh = armedRef.current;
      startYRef.current = null;
      activeRef.current = false;
      armedRef.current = false;

      if (!shouldRefresh) {
        setDistance(0);
        return;
      }

      setRefreshing(true);
      setDistance(TRIGGER_DISTANCE);
      if ("vibrate" in navigator) navigator.vibrate?.(12);
      Promise.resolve(refreshRef.current())
        .catch(() => undefined)
        .finally(() => {
          window.setTimeout(() => {
            setRefreshing(false);
            setDistance(0);
          }, 220);
        });
    }

    window.addEventListener("touchstart", onTouchStart, { passive: true });
    window.addEventListener("touchmove", onTouchMove, { passive: false });
    window.addEventListener("touchend", onTouchEnd, { passive: true });
    window.addEventListener("touchcancel", onTouchEnd, { passive: true });
    return () => {
      window.removeEventListener("touchstart", onTouchStart);
      window.removeEventListener("touchmove", onTouchMove);
      window.removeEventListener("touchend", onTouchEnd);
      window.removeEventListener("touchcancel", onTouchEnd);
    };
  }, [refreshing]);

  const active = distance > 0 || refreshing;
  const ready = distance >= TRIGGER_DISTANCE || refreshing;
  const spin = refreshing || ready;

  return (
    <div className={className}>
      <div
        className={cn(
          "pointer-events-none fixed left-1/2 top-[calc(env(safe-area-inset-top,0px)+0.5rem)] z-[80] -translate-x-1/2 transition-all duration-200 md:hidden",
          active ? "opacity-100" : "-translate-y-4 opacity-0"
        )}
        style={{ transform: `translate(-50%, ${Math.max(0, distance - 42)}px)` }}
      >
        <div
          className={cn(
            "grid h-10 w-10 place-items-center rounded-full border shadow-2xl backdrop-blur-xl",
            ready
              ? "border-accent/35 bg-accent/20 text-white"
              : "border-white/10 bg-surface/90 text-text-secondary"
          )}
          aria-label="Refreshing"
        >
          <RotateCw
            size={17}
            className={cn(spin ? "animate-spin text-accent" : "text-text-tertiary")}
          />
        </div>
      </div>
      {children}
    </div>
  );
}
