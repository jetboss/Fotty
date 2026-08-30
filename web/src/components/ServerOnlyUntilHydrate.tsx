"use client";

import { useSyncExternalStore } from "react";

function subscribe() {
  return () => {};
}

function getClientSnapshot() {
  return true;
}

function getServerSnapshot() {
  return false;
}

/** Renders children for SSR/crawlers, then removes them once the client feed is active. */
export function ServerOnlyUntilHydrate({ children }: { children: React.ReactNode }) {
  const hydrated = useSyncExternalStore(subscribe, getClientSnapshot, getServerSnapshot);
  if (hydrated) return null;
  return children;
}
