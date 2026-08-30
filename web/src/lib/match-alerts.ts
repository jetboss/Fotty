import type { ScrapedMatch } from "@/lib/api";
import { buildReminderPayload, formatKickoff, matchKey } from "@/lib/live";
import { matchIncludesTeam } from "@/lib/team-name-match";
import type { ReminderEntry, TrackedTeamEntry } from "@/lib/storage";
import { hasReminder, saveReminder } from "@/lib/storage";
import { buildWatchPageHref, isP2PContentId } from "@/lib/watch-session";

/** Notify once when a tracked fixture is 2–48 hours away. */
export const TRACKED_UPCOMING_MIN_MS = 2 * 60 * 60 * 1000;
export const TRACKED_UPCOMING_MAX_MS = 48 * 60 * 60 * 1000;

/** Notify once in the final 15 minutes before kickoff. */
export const TRACKED_SOON_MS = 15 * 60 * 1000;

/** Saved reminders: same 15-minute pre-kickoff window. */
export const REMINDER_SOON_MS = 15 * 60 * 1000;

export type MatchAlertKind = "tracked-upcoming" | "tracked-soon" | "reminder-soon";

export function matchAlertKey(kind: MatchAlertKind, reminder: { id: string; startsAt: string }) {
  return `${kind}:${reminder.id}:${reminder.startsAt}`;
}

export function findNextTrackedFixture(matches: ScrapedMatch[], teamName: string) {
  const now = Date.now();
  let next: ScrapedMatch | null = null;
  let nextKickoff = Number.POSITIVE_INFINITY;

  for (const match of matches) {
    if (match.kind !== "fixture" || !match.startsAt || !matchIncludesTeam(match, teamName)) continue;
    const kickoff = new Date(match.startsAt).getTime();
    if (!Number.isFinite(kickoff) || kickoff <= now || kickoff >= nextKickoff) continue;
    next = match;
    nextKickoff = kickoff;
  }

  return next;
}

export function syncReminderForTrackedTeam(matches: ScrapedMatch[], teamName: string) {
  const next = findNextTrackedFixture(matches, teamName);
  if (!next) return null;

  const payload = buildReminderPayload(next, "/teams");
  if (!payload || hasReminder(payload)) return null;

  return saveReminder(payload);
}

export function collectTrackedTeamAlerts(
  matches: ScrapedMatch[],
  trackedTeams: TrackedTeamEntry[],
  now: number
) {
  const alerts: Array<{
    kind: MatchAlertKind;
    key: string;
    title: string;
    body: string;
    url: string;
    tag: string;
  }> = [];

  for (const match of matches) {
    if (match.kind !== "fixture" || !match.startsAt) continue;

    const kickoff = new Date(match.startsAt).getTime();
    if (!Number.isFinite(kickoff) || kickoff <= now) continue;

    const untilKickoff = kickoff - now;
    const tracked = trackedTeams.find((team) => matchIncludesTeam(match, team.name));
    if (!tracked) continue;

    const fixtureTitle = match.displayTitle || match.title;
    const kickoffLabel = formatKickoff(match.startsAt);
    const url =
      buildReminderPayload(match, "/")?.href ||
      buildWatchPageHref(
        new URLSearchParams({
          ...(isP2PContentId(match.cid) ? { cid: match.cid } : { id: match.cid }),
        })
      );
    const baseKey = `${matchKey(match)}:${match.startsAt}`;

    if (untilKickoff > TRACKED_UPCOMING_MIN_MS && untilKickoff <= TRACKED_UPCOMING_MAX_MS) {
      alerts.push({
        kind: "tracked-upcoming",
        key: matchAlertKey("tracked-upcoming", { id: match.id || match.cid, startsAt: match.startsAt }),
        title: `${tracked.name} plays soon`,
        body: [fixtureTitle, kickoffLabel, match.league].filter(Boolean).join(" · "),
        url,
        tag: `tracked-upcoming:${baseKey}`,
      });
    }

    if (untilKickoff >= 0 && untilKickoff <= TRACKED_SOON_MS) {
      alerts.push({
        kind: "tracked-soon",
        key: matchAlertKey("tracked-soon", { id: match.id || match.cid, startsAt: match.startsAt }),
        title: "Match starting soon",
        body: [fixtureTitle, tracked.name, match.league].filter(Boolean).join(" · "),
        url,
        tag: `tracked-soon:${baseKey}`,
      });
    }
  }

  return alerts;
}

export function collectSavedReminderAlerts(reminders: ReminderEntry[], now: number) {
  return reminders
    .map((reminder) => {
      const kickoff = new Date(reminder.startsAt).getTime();
      if (!Number.isFinite(kickoff)) return null;

      const untilKickoff = kickoff - now;
      if (untilKickoff < 0 || untilKickoff > REMINDER_SOON_MS) return null;

      return {
        kind: "reminder-soon" as const,
        key: matchAlertKey("reminder-soon", reminder),
        title: "Match starting soon",
        body: reminder.league ? `${reminder.title} · ${reminder.league}` : reminder.title,
        url: reminder.href,
        tag: `reminder-soon:${reminder.id}:${reminder.startsAt}`,
      };
    })
    .filter((entry): entry is NonNullable<typeof entry> => Boolean(entry));
}
