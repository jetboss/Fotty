"use client";

import Link from "next/link";
import { Shuffle } from "lucide-react";
import type { ScrapedMatch } from "@/lib/api";
import { fixtureTeamLabels } from "@/lib/fixture-normalization";
import { buildWatchHref, formatKickoff, matchKey } from "@/lib/live";
import { isMatchLive } from "@/lib/v2/match-priority";
import { matchIncludesTeam } from "@/lib/team-name-match";
import type { TrackedTeamEntry } from "@/lib/storage";
import { eventSportLabel } from "@/lib/v2/fixture-display";

const SOON_WINDOW_MS = 6 * 60 * 60 * 1000;

function isStartingSoon(match: ScrapedMatch) {
  if (isMatchLive(match)) return false;
  if (!match.startsAt) return match.status === "Starting Soon";
  const kickoff = new Date(match.startsAt).getTime();
  if (Number.isNaN(kickoff)) return false;
  const now = Date.now();
  return kickoff >= now - 60_000 && kickoff <= now + SOON_WINDOW_MS;
}

function sportKey(match: ScrapedMatch) {
  return (match.sport || match.categories?.[0] || "other").toLowerCase();
}

function shortTitle(match: ScrapedMatch) {
  const labels = fixtureTeamLabels(match);
  if (!labels.isUpdating) {
    const text = `${labels.home} · ${labels.away}`;
    return text.length > 36 ? `${text.slice(0, 34)}…` : text;
  }
  const title = match.displayTitle || match.title || "Match";
  return title.length > 36 ? `${title.slice(0, 34)}…` : title;
}

function diversifyBySport(matches: ScrapedMatch[], limit: number) {
  const buckets = new Map<string, ScrapedMatch[]>();
  const order: string[] = [];
  for (const match of matches) {
    const key = sportKey(match);
    if (!buckets.has(key)) {
      buckets.set(key, []);
      order.push(key);
    }
    buckets.get(key)!.push(match);
  }

  const result: ScrapedMatch[] = [];
  const indices = Object.fromEntries(order.map((k) => [k, 0]));
  while (result.length < limit) {
    let added = false;
    for (const sport of order) {
      if (result.length >= limit) break;
      const idx = indices[sport] ?? 0;
      const bucket = buckets.get(sport) ?? [];
      if (idx >= bucket.length) continue;
      if (
        idx >= 2 &&
        result.length + 1 < limit &&
        order.some((other) => other !== sport && (indices[other] ?? 0) < (buckets.get(other)?.length ?? 0))
      ) {
        continue;
      }
      result.push(bucket[idx]);
      indices[sport] = idx + 1;
      added = true;
    }
    if (!added) break;
  }
  return result;
}

function rankForGlance(matches: ScrapedMatch[], trackedTeams: TrackedTeamEntry[]) {
  return [...matches].sort((a, b) => {
    const aFollowed = trackedTeams.some((team) => matchIncludesTeam(a, team.name)) ? 0 : 1;
    const bFollowed = trackedTeams.some((team) => matchIncludesTeam(b, team.name)) ? 0 : 1;
    if (aFollowed !== bFollowed) return aFollowed - bFollowed;
    const aTime = a.startsAt ? new Date(a.startsAt).getTime() : Number.MAX_SAFE_INTEGER;
    const bTime = b.startsAt ? new Date(b.startsAt).getTime() : Number.MAX_SAFE_INTEGER;
    return aTime - bTime;
  });
}

export function buildOnNowGlance(
  matches: ScrapedMatch[],
  trackedTeams: TrackedTeamEntry[] = []
) {
  const fixtures = matches.filter((match) => match.kind === "fixture");
  const live = rankForGlance(fixtures.filter(isMatchLive), trackedTeams);
  const soon = rankForGlance(fixtures.filter(isStartingSoon), trackedTeams);
  const pool = live.length > 0 ? live : soon;
  const day = new Date().getDate();
  const surprise = pool.length === 0 ? null : pool[(day + pool.length) % pool.length];
  return {
    live,
    soon,
    liveChips: diversifyBySport(live, 4),
    soonChips: diversifyBySport(soon, 3),
    surprise,
  };
}

interface OnNowGlanceProps {
  matches: ScrapedMatch[];
  trackedTeams?: TrackedTeamEntry[];
  returnTo?: string;
}

export function OnNowGlance({ matches, trackedTeams = [], returnTo = "/" }: OnNowGlanceProps) {
  const glance = buildOnNowGlance(matches, trackedTeams);
  if (glance.live.length === 0 && glance.soon.length === 0) return null;

  const chips: Array<
    | { kind: "summary" }
    | { kind: "surprise"; match: ScrapedMatch }
    | { kind: "live" | "soon"; match: ScrapedMatch }
  > = [{ kind: "summary" }];

  if (glance.surprise && glance.live.length > 0) {
    chips.push({ kind: "surprise", match: glance.surprise });
  }
  for (const match of glance.liveChips) {
    chips.push({ kind: "live", match });
  }
  const remaining = Math.max(0, 7 - chips.length);
  for (const match of glance.soonChips.slice(0, remaining)) {
    chips.push({ kind: "soon", match });
  }

  return (
    <div className="px-4 lg:px-6">
      <div className="flex gap-1.5 overflow-x-auto pb-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {chips.map((chip) => {
          if (chip.kind === "summary") {
            return (
              <div
                key="summary"
                className="inline-flex h-7 shrink-0 items-center gap-1.5 rounded bg-white/[0.06] px-2.5 text-[11px] font-bold text-white"
              >
                {glance.live.length > 0 ? (
                  <>
                    <span className="h-1.5 w-1.5 rounded-full bg-accent" />
                    <span>{glance.live.length === 1 ? "1 live" : `${glance.live.length} live`}</span>
                  </>
                ) : null}
                {glance.soon.length > 0 ? (
                  <>
                    {glance.live.length > 0 ? <span className="text-white/35">·</span> : null}
                    <span className="font-semibold text-white/70">
                      {glance.soon.length === 1 ? "1 soon" : `${glance.soon.length} soon`}
                    </span>
                  </>
                ) : null}
              </div>
            );
          }

          if (chip.kind === "surprise") {
            return (
              <Link
                key={`surprise-${matchKey(chip.match)}`}
                href={buildWatchHref(chip.match, returnTo)}
                aria-label={`Surprise me: ${shortTitle(chip.match)}`}
                className="inline-flex h-7 shrink-0 items-center gap-1.5 rounded border border-accent/40 bg-accent/15 px-2.5 text-[11px] font-bold text-white"
              >
                <Shuffle size={11} className="text-accent" />
                Surprise
              </Link>
            );
          }

          const kickLabel =
            chip.kind === "soon" && chip.match.startsAt
              ? formatKickoff(chip.match.startsAt).replace(/^Today\s+/i, "")
              : null;
          const sportLabel = eventSportLabel(chip.match);
          const eventLabel = shortTitle(chip.match);
          const timingLabel = kickLabel ?? (chip.kind === "live" ? "Live" : "Soon");

          return (
            <Link
              key={`${chip.kind}-${matchKey(chip.match)}`}
              href={buildWatchHref(chip.match, returnTo)}
              aria-label={`${sportLabel}: ${eventLabel}, ${timingLabel}`}
              className={`inline-flex h-7 max-w-[220px] shrink-0 items-center gap-1.5 truncate rounded border px-2.5 text-[11px] font-semibold text-white ${
                chip.kind === "live"
                  ? "border-accent/35 bg-white/[0.06]"
                  : "border-white/10 bg-white/[0.06]"
              }`}
            >
              <span className={`shrink-0 ${chip.kind === "live" ? "text-accent" : "text-white/45"}`}>
                {sportLabel}
              </span>
              <span className="truncate">
                {kickLabel ? `${kickLabel} · ${eventLabel}` : eventLabel}
              </span>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
