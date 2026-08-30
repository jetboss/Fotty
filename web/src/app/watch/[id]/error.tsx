"use client";

import { useEffect } from "react";
import { RouteErrorView } from "@/components/RouteStates";

export default function Error({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  const refreshApp = async () => {
    try {
      if ("caches" in window) {
        const cacheNames = await caches.keys();
        await Promise.all(cacheNames.filter((name) => name.startsWith("fotty-")).map((name) => caches.delete(name)));
      }
      if ("serviceWorker" in navigator) {
        const registrations = await navigator.serviceWorker.getRegistrations();
        await Promise.all(registrations.map((registration) => registration.update().catch(() => undefined)));
      }
    } finally {
      window.location.reload();
    }
  };

  return (
    <RouteErrorView
      title="Stream page failed to load"
      message="The player hit a browser-side load error. Try again, or refresh Fotty’s app shell if this desktop is holding an old cached version."
      reset={reset}
      secondaryAction={{ label: "Refresh app", onClick: refreshApp }}
    />
  );
}
