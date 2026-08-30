"use client";

import { FOTTY_LOCALE, FOTTY_TIME_ZONE } from "@/lib/live";

function formatRelativeTime(date: Date) {
  const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
  if (seconds < 15) return "Updated just now";
  if (seconds < 60) return `Updated ${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `Updated ${minutes}m ago`;
  return `Updated ${new Intl.DateTimeFormat(FOTTY_LOCALE, {
    timeZone: FOTTY_TIME_ZONE,
    hour: "numeric",
    minute: "2-digit",
  }).format(date)}`;
}

export function FeedUpdatedBanner({ lastUpdated, className }: { lastUpdated: Date | null; className?: string }) {
  if (!lastUpdated) return null;

  return (
    <p className={["text-[10px] font-medium text-text-tertiary", className].filter(Boolean).join(" ")} aria-live="polite">
      {formatRelativeTime(lastUpdated)}
    </p>
  );
}
