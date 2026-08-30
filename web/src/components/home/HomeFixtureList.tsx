"use client";

import { memo } from "react";
import Link from "next/link";
import { CalendarClock, Play, Radio, Tv } from "lucide-react";
import type { ScrapedMatch } from "@/lib/api";
import { buildWatchHref, canOpenBroadcast, FOTTY_LOCALE, FOTTY_TIME_ZONE, formatKickoff, isMatchLiveNow, matchKey } from "@/lib/live";
import { fottyFeedCountShort } from "@/lib/watch-stream-display";
import { matchIncludesTeam } from "@/lib/team-name-match";
import { useUserPreferences } from "@/lib/user-experience";
import { fixtureDisplayTitle, fixtureTeamLabels } from "@/lib/fixture-normalization";
import { fixtureLeagueLine } from "@/lib/v2/fixture-display";
import { v2AppPath, v2HomePath } from "@/lib/v2/preview";
import { ReminderButton } from "@/components/ReminderButton";
import { TeamBadge } from "@/components/TeamBadge";
import { FallbackState } from "@/components/FallbackState";
import { cn } from "@/lib/utils";

interface HomeFixtureListProps {
  matches: ScrapedMatch[];
  emptyMessage?: string;
  returnTo?: string;
  highlightTeam?: string | null;
  onTeamClick?: (teamName: string) => void;
  layout?: "list" | "grid" | "grid-wide";
  variant?: "classic" | "v2";
}

export function HomeFixtureList({
  matches,
  emptyMessage,
  returnTo = "/",
  highlightTeam = null,
  onTeamClick,
  layout = "list",
  variant = "classic",
}: HomeFixtureListProps) {
  const isV2 = variant === "v2";
  const { preferences } = useUserPreferences();

  if (matches.length === 0) {
    return (
      <FallbackState
        title="Nothing matched this view"
        message={emptyMessage || "No verified fixtures are in this window. Fotty will keep checking as schedules and watch paths update."}
        primaryAction={{ label: "Open home", href: v2HomePath() }}
        secondaryAction={{ label: "Discover", href: v2AppPath("/search") }}
        compact
        inline
        variant={variant}
      />
    );
  }

  return (
    <div
      className={
        layout === "grid"
          ? "grid gap-2 sm:grid-cols-2"
          : layout === "grid-wide"
            ? "grid gap-2 sm:grid-cols-2 xl:grid-cols-3"
            : "space-y-2"
      }
    >
      {matches.map((match) => {
        const highlighted = highlightTeam ? matchIncludesTeam(match, highlightTeam) : false;
        return (
          <HomeFixtureRow
            key={matchKey(match)}
            match={match}
            returnTo={returnTo}
            highlighted={highlighted}
            hideScores={preferences.spoilerProtection && match.status === "Live"}
            onTeamClick={onTeamClick}
            variant={variant}
          />
        );
      })}
    </div>
  );
}

const rowClass = (highlighted: boolean, interactive: boolean, isV2: boolean) =>
  cn(
    "group relative overflow-hidden rounded-2xl border px-3 py-3 transition duration-300 [content-visibility:auto] [contain-intrinsic-size:0_96px] max-[430px]:py-3",
    highlighted
      ? isV2
        ? "border-white/20 bg-white/[0.06]"
        : "border-accent/45 bg-[linear-gradient(135deg,rgba(224,31,71,0.18),rgba(12,17,25,0.92))]"
      : isV2
        ? "border-white/[0.06] bg-white/[0.02] ring-1 ring-white/[0.04]"
        : "border-white/8 bg-[linear-gradient(135deg,rgba(255,255,255,0.045),rgba(255,255,255,0.018))]",
    interactive && (isV2 ? "hover:bg-white/[0.04]" : "hover:-translate-y-0.5 hover:border-white/18 hover:bg-white/[0.055]")
  );

const HomeFixtureRow = memo(function HomeFixtureRow({
  match,
  returnTo,
  highlighted,
  hideScores,
  onTeamClick,
  variant = "classic",
}: {
  match: ScrapedMatch;
  returnTo: string;
  highlighted: boolean;
  hideScores: boolean;
  onTeamClick?: (teamName: string) => void;
  variant?: "classic" | "v2";
}) {
  const isV2 = variant === "v2";
  const isLive = isMatchLiveNow(match);
  const canOpen = canOpenBroadcast(match);
  const href = buildWatchHref(match, returnTo);
  const kickoff = formatKickoff(match.startsAt);
  const labels = fixtureTeamLabels(match);
  const home = labels.home;
  const away = labels.away;
  const scoreHome = match.score?.home;
  const scoreAway = match.score?.away;
  const sourceLabel =
    typeof match.sourceCount === "number" && match.sourceCount > 0
      ? fottyFeedCountShort(match.sourceCount)
      : null;
  const sportLabel = fixtureLeagueLine(match) || match.league || match.sport || "Live sport";
  const kickoffLabel = kickoff || kickoffBadge(match.startsAt);

  const body = (
    <>
      {!isV2 ? (
        <div className="pointer-events-none absolute inset-y-0 right-0 w-28 bg-gradient-to-l from-accent/10 to-transparent opacity-0 transition group-hover:opacity-100" />
      ) : null}

      <div className="flex min-w-0 flex-1 items-center gap-3">
        <div className="flex h-14 w-20 shrink-0 items-center justify-center -space-x-3 rounded-2xl border border-white/8 bg-black/20 max-[430px]:h-13 max-[430px]:w-16">
          {!labels.isUpdating ? (
            <>
              <TeamBadge name={home} badge={labels.homeBadge} size={36} />
              <TeamBadge name={away} badge={labels.awayBadge} size={36} />
            </>
          ) : (
            <Tv size={24} className={isV2 ? "text-white/70" : "text-accent"} />
          )}
        </div>

        <div className="min-w-0 flex-1">
          <div className="mb-1 flex min-w-0 items-center gap-2">
            <span
              className={cn(
                "inline-flex shrink-0 items-center gap-1 rounded-full border px-2 py-0.5 text-[9px] uppercase",
                isV2 ? "font-semibold" : "font-black",
                isLive ? "border-live/25 bg-live/10 text-live" : "border-white/10 bg-white/[0.04] text-text-tertiary"
              )}
            >
              {isLive ? <Radio size={10} className="animate-live-pulse" /> : <CalendarClock size={10} />}
              {isLive ? "Live" : kickoffBadge(match.startsAt)}
            </span>
            {sourceLabel ? (
              <span className="truncate text-[10px] font-black uppercase text-text-tertiary">{sourceLabel}</span>
            ) : null}
          </div>
          {labels.isUpdating ? (
            <p className={cn("line-clamp-2 text-base leading-tight text-text-primary max-[430px]:text-sm", isV2 ? "font-semibold" : "font-black")}>
              {fixtureDisplayTitle(match)}
            </p>
          ) : (
            <p className={cn("line-clamp-2 text-base leading-tight text-text-primary max-[430px]:text-sm", isV2 ? "font-semibold" : "font-black")}>
              <TeamNameButton name={home} label={matchupName(home)} onTeamClick={onTeamClick} />
              <span className="text-text-tertiary"> v </span>
              <TeamNameButton name={away} label={matchupName(away)} onTeamClick={onTeamClick} />
            </p>
          )}
          <p className="mt-1 truncate text-[11px] font-bold text-text-tertiary">
            {[sportLabel, isLive ? "In play" : kickoffLabel].filter(Boolean).join(" · ")}
          </p>
        </div>
      </div>

      <div className="relative z-10 shrink-0 text-right">
        {canOpen ? (
          <div className="flex flex-col items-end gap-1.5">
            <p className={cn("text-sm tabular-nums text-text-primary max-[430px]:hidden", isV2 ? "font-semibold" : "font-black")}>
              {isLive && !hideScores && scoreHome != null && scoreAway != null
                ? `${scoreHome} - ${scoreAway}`
                : isLive && hideScores
                  ? "In play"
                  : kickoff || "Ready"}
            </p>
            <span
              className={cn(
                "inline-flex h-9 items-center gap-2 rounded-full px-3 text-xs",
                isV2 ? "bg-white font-semibold text-zinc-950" : "bg-accent font-black text-white shadow-[0_12px_32px_rgba(224,31,71,0.28)]"
              )}
            >
              <Play size={12} fill="currentColor" />
              <span className="max-[430px]:sr-only">{isLive ? "Watch" : "Open"}</span>
            </span>
          </div>
        ) : (
          <ReminderButton match={match} returnTo={returnTo} compact className="mt-1" />
        )}
      </div>
    </>
  );

  if (canOpen) {
    return (
      <Link href={href} className={rowClass(highlighted, true, isV2)}>
        {body}
      </Link>
    );
  }

  return <div className={rowClass(highlighted, false, isV2)}>{body}</div>;
});

function TeamNameButton({
  name,
  label,
  onTeamClick,
}: {
  name: string;
  label: string;
  onTeamClick?: (teamName: string) => void;
}) {
  if (!onTeamClick) return <span>{label}</span>;
  return (
    <button
      type="button"
      className="transition hover:text-accent"
      onClick={(event) => {
        event.preventDefault();
        event.stopPropagation();
        onTeamClick(name);
      }}
    >
      {label}
    </button>
  );
}

function matchupName(name: string) {
  const clean = name.trim();
  if (clean.length <= 16) return clean;
  return shortName(clean);
}

function shortName(name: string) {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].slice(0, 3).toUpperCase();
  return parts
    .map((part) => part[0])
    .join("")
    .slice(0, 3)
    .toUpperCase();
}

function kickoffBadge(startsAt?: string) {
  if (!startsAt) return "Upcoming";
  const kickoff = new Date(startsAt);
  if (Number.isNaN(kickoff.getTime())) return "Upcoming";
  const now = new Date();
  const hours = (kickoff.getTime() - now.getTime()) / 3600000;
  if (hours > 0 && hours <= 3) return "Soon";
  const dayFormatter = new Intl.DateTimeFormat(FOTTY_LOCALE, {
    timeZone: FOTTY_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  if (dayFormatter.format(kickoff) === dayFormatter.format(now)) return "Today";
  const tomorrow = new Date(now);
  tomorrow.setDate(now.getDate() + 1);
  if (dayFormatter.format(kickoff) === dayFormatter.format(tomorrow)) return "Tomorrow";
  return new Intl.DateTimeFormat(FOTTY_LOCALE, { timeZone: FOTTY_TIME_ZONE, weekday: "short" }).format(kickoff);
}
