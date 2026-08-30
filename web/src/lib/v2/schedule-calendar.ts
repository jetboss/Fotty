import type { ScrapedMatch } from "@/lib/api";
import { getDisplayTimeZone } from "@/lib/live";

export type DayBucket = {
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

function startOfMonth(year: number, month: number) {
  return new Date(year, month, 1);
}

function daysInMonth(year: number, month: number) {
  return new Date(year, month + 1, 0).getDate();
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

export function monthMatrix(year: number, month: number, timeZone = getDisplayTimeZone()) {
  const first = startOfMonth(year, month);
  const total = daysInMonth(year, month);
  const startWeekday = first.getDay();
  const mondayBasedOffset = (startWeekday + 6) % 7;
  const cells: Array<{ key: string; day: number | null; date: Date | null }> = [];

  for (let i = 0; i < mondayBasedOffset; i++) {
    cells.push({ key: `pad-${i}`, day: null, date: null });
  }

  for (let day = 1; day <= total; day++) {
    const date = new Date(year, month, day, 12, 0, 0);
    const key = new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(date);
    cells.push({ key, day, date });
  }

  return { year, month, cells };
}

export function monthTitle(year: number, month: number) {
  return new Date(year, month, 1).toLocaleDateString(undefined, { month: "long", year: "numeric" });
}
