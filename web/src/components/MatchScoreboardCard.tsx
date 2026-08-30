"use client";

import Link from "next/link";
import { Bell, BellOff, CalendarClock, ChevronRight, Play, Radio, ShieldCheck, Signal, Tv, Users } from "lucide-react";
import type { ScrapedMatch } from "@/lib/api";
import { trackEvent } from "@/lib/analytics";
import { buildReminderPayload, buildWatchHref, canOpenBroadcast, formatKickoff, isMatchLiveNow } from "@/lib/live";
import { matchFeedSummary } from "@/lib/watch-stream-display";
import { updateUserPreferences } from "@/lib/storage";
import { useReminderToggle, useUserPreferences } from "@/lib/user-experience";
import { fixtureTeamLabels } from "@/lib/fixture-normalization";
import { cn } from "@/lib/utils";
import { TeamBadge } from "./TeamBadge";

interface MatchScoreboardCardProps {
  match: ScrapedMatch;
  returnTo: string;
  layout?: "rail" | "row" | "hero";
  actionLabel?: string;
}

export function MatchScoreboardCard({
  match,
  returnTo,
  layout = "rail",
  actionLabel,
}: MatchScoreboardCardProps) {
  const { preferences } = useUserPreferences();
  const isFixture = match.kind === "fixture" && Boolean(match.teams);
  const isLive = isMatchLiveNow(match);
  const title = match.displayTitle || match.title;
  const href = buildWatchHref(match, returnTo);
  const canOpen = canOpenBroadcast(match);
  const reminder = buildReminderPayload(match, returnTo);
  const { reminded, toggleReminder } = useReminderToggle(reminder);
  const sourceCount = match.sourceCount || match.alternateCount || 1;
  const sourceLabel = matchFeedSummary(match);
  const statusLabel = isLive
    ? "Live"
    : match.p2pHealth?.playable
      ? "Verified"
      : match.p2pHealth && !match.p2pHealth.playable
        ? "Needs retry"
        : formatKickoff(match.startsAt) || match.status || "Available";
  const cta = actionLabel || (canOpen ? (isLive ? "Watch Live" : isFixture ? "Open Match" : "Watch") : reminded ? "Reminder saved" : "Remind me");
  const cardClassName = cn(
    "group relative block overflow-hidden rounded-2xl border border-white/8 bg-[linear-gradient(145deg,rgba(255,255,255,0.055),rgba(255,255,255,0.018))] shadow-[0_18px_60px_rgba(0,0,0,0.32)] transition duration-300",
    canOpen ? "hover:-translate-y-0.5 hover:border-white/18 hover:bg-white/[0.06]" : "cursor-default",
    layout === "rail" && "min-w-[292px]",
    layout === "row" && "w-full",
    layout === "hero" && "w-full"
  );
  const content = (
    <>
      <div className="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-white/30 to-transparent" />
      <div className="border-b border-white/6 bg-black/18 px-4 py-3 backdrop-blur">
        <div className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="truncate text-[11px] font-black uppercase tracking-wide text-text-secondary">
              {match.league || match.sport || "Live Sports"}
            </p>
            {layout !== "rail" && (
              <p className="mt-1 truncate text-xs font-medium text-text-tertiary">{match.subtitle || sourceLabel}</p>
            )}
          </div>
          <span
            className={cn(
              "inline-flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1 text-[11px] font-black",
              isLive
                ? "border border-live/30 bg-live/12 text-live shadow-[0_0_24px_rgba(255,179,38,0.12)]"
                : "border border-white/10 bg-white/5 text-text-secondary"
            )}
          >
            {isLive ? <Radio size={11} className="animate-pulse" /> : <CalendarClock size={11} />}
            {statusLabel}
          </span>
        </div>
      </div>

      <div className={cn("space-y-4 p-4", layout === "hero" && "sm:p-5")}>
        {isFixture ? (
          <FixtureScoreboard match={match} hideScores={preferences.spoilerProtection} layout={layout} />
        ) : (
          <ChannelPanel match={match} title={title} />
        )}

        <div className="flex items-center justify-between gap-3 border-t border-white/6 pt-3">
          <div className="min-w-0 space-y-1">
            <div className="flex min-w-0 items-center gap-2 text-xs font-semibold text-text-secondary">
              {match.playbackType === "event" ? <Users size={13} /> : <Signal size={13} />}
              <span className="truncate">{sourceLabel}</span>
            </div>
            <div className="inline-flex items-center gap-1.5 rounded-full border border-white/10 bg-black/20 px-2 py-1 text-[10px] font-black uppercase text-text-tertiary">
              <ShieldCheck size={11} />
              {watchConfidenceLabel(match)}
            </div>
          </div>
          {canOpen ? (
            <div className="inline-flex min-h-10 shrink-0 items-center gap-2 rounded-full bg-gradient-to-r from-accent to-rose-600 px-4 py-2 text-xs font-black text-white shadow-[0_12px_32px_rgba(224,31,71,0.26)]">
              <Play size={13} fill="currentColor" />
              {cta}
              {layout !== "rail" && <ChevronRight size={13} />}
            </div>
          ) : (
            <button
              type="button"
              onClick={() => {
                const active = toggleReminder();
                if (active) updateUserPreferences({ matchReminders: true });
              }}
              disabled={!reminder}
              className={cn(
                "inline-flex min-h-10 shrink-0 items-center gap-2 rounded-full px-4 py-2 text-xs font-black transition-colors",
                reminded
                  ? "border border-accent/30 bg-accent/10 text-accent"
                  : "border border-white/10 bg-white/5 text-text-secondary hover:border-accent/30 hover:text-accent",
                !reminder && "cursor-not-allowed opacity-60"
              )}
            >
              {reminded ? <BellOff size={13} /> : <Bell size={13} />}
              {cta}
            </button>
          )}
        </div>
      </div>
    </>
  );

  if (!canOpen) {
    return <div className={cardClassName}>{content}</div>;
  }

  return (
    <Link
      href={href}
      onClick={() =>
        trackEvent("watch_match_click", {
          matchId: match.id || match.cid,
          title,
          sport: match.sport,
          status: match.status,
          playbackType: match.playbackType,
          sourceCount,
        })
      }
      className={cardClassName}
    >
      {content}
    </Link>
  );
}

function watchConfidenceLabel(match: ScrapedMatch) {
  if (match.p2pHealth?.playable) return "checked";
  const feedCount = match.sourceCount || match.alternateCount || 0;
  if (feedCount >= 4) return "strong";
  if (feedCount >= 2) return "good";
  if (match.playbackType === "event") return "ready";
  return "backup";
}

function FixtureScoreboard({
  match,
  hideScores,
  layout,
}: {
  match: ScrapedMatch;
  hideScores: boolean;
  layout: MatchScoreboardCardProps["layout"];
}) {
  const labels = fixtureTeamLabels(match);
  const homeName = labels.home;
  const awayName = labels.away;
  const score = match.score && !hideScores ? `${match.score.home} : ${match.score.away}` : "vs";

  return (
    <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-3">
      <TeamColumn name={homeName} badge={labels.homeBadge} size={layout === "row" ? 42 : 50} />
      <div className="min-w-[72px] text-center">
        {isMatchLiveNow(match) && (
          <div className="mx-auto mb-1 inline-flex items-center gap-1 rounded-full border border-live/20 bg-live/10 px-2 py-0.5 text-[9px] font-black uppercase text-live">
            <span className="h-1.5 w-1.5 rounded-full bg-live animate-live-pulse" />
            Live
          </div>
        )}
        <div className="text-2xl font-black text-white sm:text-3xl">{score}</div>
        <div className="mt-1 truncate text-[10px] font-bold uppercase text-text-tertiary">
          {match.quality || match.coverage || "Ready"}
        </div>
      </div>
      <TeamColumn name={awayName} badge={labels.awayBadge} size={layout === "row" ? 42 : 50} />
    </div>
  );
}

function TeamColumn({ name, badge, size }: { name: string; badge?: string; size: number }) {
  return (
    <div className="flex min-w-0 flex-col items-center gap-2">
      <TeamBadge name={name} badge={badge} size={size} />
      <span className="line-clamp-2 min-h-[2rem] text-center text-xs font-black leading-4 text-text-primary">
        {name}
      </span>
    </div>
  );
}

function ChannelPanel({ match, title }: { match: ScrapedMatch; title: string }) {
  return (
    <div className="flex items-center gap-4">
      <div className="grid h-14 w-14 shrink-0 place-items-center rounded-2xl border border-white/10 bg-black/24 text-accent">
        <Tv size={25} />
      </div>
      <div className="min-w-0 flex-1 space-y-1">
        <h3 className="line-clamp-2 text-base font-black text-text-primary">{title}</h3>
        <p className="truncate text-xs font-medium text-text-secondary">
          {match.subtitle || match.league || "Live sports channel"}
        </p>
        {match.region && <p className="truncate text-[11px] text-text-tertiary">{match.region}</p>}
      </div>
    </div>
  );
}
