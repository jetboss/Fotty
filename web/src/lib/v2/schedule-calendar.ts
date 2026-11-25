import type { ScrapedMatch } from "@/lib/api";
import { getDisplayTimeZone } from "@/lib/live";

type DayBucket = {
  key: string;
  date: Date;
  label: string;
  weekday: string;
  matches: ScrapedMatch[];
};

function dayKeyForInstant(iso: string, timeZone: string) {
  const date = new Date(iso);
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

export function groupFixturesByDay(matches: ScrapedMatch[], timeZone = getDisplayTimeZone()) {
  const buckets = new Map<string, ScrapedMatch[]>();

  for (const match of matches) {
    if (match.kind !== "fixture" || !match.startsAt) continue;
    const key = dayKeyForInstant(match.startsAt, timeZone);
    const list = buckets.get(key) ?? [];
    list.push(match);
    buckets.set(key, list);
  }

  const days: DayBucket[] = [];
  for (const [key, dayMatches] of buckets) {
    const date = new Date(`${key}T12:00:00`);
    dayMatches.sort((a, b) => new Date(a.startsAt!).getTime() - new Date(b.startsAt!).getTime());
    days.push({
      key,
      date,
      label: new Intl.DateTimeFormat(undefined, { timeZone, month: "short", day: "numeric" }).format(date),
      weekday: new Intl.DateTimeFormat(undefined, { timeZone, weekday: "long" }).format(date),
      matches: dayMatches,
    });
  }

  return days.sort((a, b) => a.date.getTime() - b.date.getTime());
}
