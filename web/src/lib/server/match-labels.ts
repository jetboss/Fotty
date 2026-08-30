import type { ScrapedMatch } from "@/lib/api";
import { FOTTY_LOCALE, FOTTY_TIME_ZONE } from "@/lib/live";

export function formatServerKickoff(startsAt?: string) {
  if (!startsAt) return "";
  const date = new Date(startsAt);
  if (Number.isNaN(date.getTime())) return "";

  return new Intl.DateTimeFormat(FOTTY_LOCALE, {
    timeZone: FOTTY_TIME_ZONE,
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

export function serverStatusLabel(match: ScrapedMatch) {
  if (match.status === "Live") return "Live";
  return formatServerKickoff(match.startsAt) || match.status || "Available";
}
