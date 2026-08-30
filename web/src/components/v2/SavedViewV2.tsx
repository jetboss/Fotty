"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Bell, CalendarPlus, Clock, Heart, Play, Trash2 } from "lucide-react";
import Image from "next/image";
import { FallbackState } from "@/components/FallbackState";
import { isOptimizedImageSrc } from "@/lib/image-hosts";
import {
  buildReminderCalendarURL,
  type FavoriteItem,
  getFavorites,
  getRecentMatches,
  type RecentMatchEntry,
  removeReminder,
} from "@/lib/storage";
import { useReminders, useUserPreferences } from "@/lib/user-experience";
import { formatKickoff } from "@/lib/live";
import { buildWatchPageHref, isP2PContentId } from "@/lib/watch-session";
import { V2PageHeader, V2PageShell, V2Section, v2ListRowClass, v2PanelClass } from "@/components/v2/V2PageShell";

import { v2FavoritesPath, v2HomePath, v2SchedulePath, v2SearchPath } from "@/lib/v2/preview";

export function SavedViewV2() {
  const returnTo = v2FavoritesPath();
  const { reminders, refresh: refreshReminders } = useReminders();
  const { preferences } = useUserPreferences();
  const [favorites, setFavorites] = useState<FavoriteItem[]>([]);
  const [recentMatches, setRecentMatches] = useState<RecentMatchEntry[]>([]);

  useEffect(() => {
    const timeout = window.setTimeout(() => {
      setFavorites(getFavorites());
      setRecentMatches(getRecentMatches());
    }, 0);
    return () => window.clearTimeout(timeout);
  }, []);

  return (
    <V2PageShell innerClassName="max-w-2xl space-y-8">
      <header className="space-y-4">
        <V2PageHeader
          title="Saved"
          subtitle="Reminders, bookmarks, and recent sessions on this device."
        />
        <div className="grid gap-2 sm:grid-cols-3">
          <Metric label="Reminders" value={reminders.length} />
          <Metric label="Bookmarks" value={favorites.length} />
          <Metric label="Recent" value={recentMatches.length} />
        </div>
      </header>

      <V2Section title="Upcoming reminders">
        {reminders.length > 0 ? (
          <ul className="space-y-2">
            {reminders.map((reminder) => (
              <li key={`${reminder.id}:${reminder.startsAt}`} className={`${v2PanelClass} p-4`}>
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div className="space-y-1">
                    <span className="inline-flex items-center gap-1.5 rounded-full bg-live/15 px-2.5 py-0.5 text-[10px] font-semibold text-live">
                      <Bell size={11} />
                      Reminder
                    </span>
                    <p className="pt-1 text-sm font-semibold text-white">{reminder.title}</p>
                    <p className="text-xs text-text-tertiary">
                      {[reminder.sport || reminder.league || "Match", formatKickoff(reminder.startsAt)]
                        .filter(Boolean)
                        .join(" · ")}
                    </p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Link
                      href={reminder.href}
                      className="rounded-full bg-white/5 px-3 py-1.5 text-xs font-medium text-white hover:bg-white/10"
                    >
                      Match page
                    </Link>
                    <a
                      href={buildReminderCalendarURL(reminder)}
                      download={`${reminder.title.replace(/[^a-z0-9]+/gi, "-").toLowerCase() || "fotty-reminder"}.ics`}
                      className="inline-flex items-center gap-1.5 rounded-full border border-white/10 px-3 py-1.5 text-xs font-medium text-text-secondary"
                    >
                      <CalendarPlus size={12} />
                      Calendar
                    </a>
                    <button
                      type="button"
                      onClick={() => {
                        removeReminder(reminder);
                        refreshReminders();
                      }}
                      className="inline-flex items-center gap-1.5 rounded-full border border-white/10 px-3 py-1.5 text-xs font-medium text-text-secondary hover:text-white"
                    >
                      <Trash2 size={12} />
                      Remove
                    </button>
                  </div>
                </div>
              </li>
            ))}
          </ul>
        ) : (
          <FallbackState
            icon={Bell}
            title="No reminders saved yet"
            message="Save an upcoming fixture from home or the schedule."
            primaryAction={{ label: "Open home", href: v2HomePath() }}
            secondaryAction={{ label: "Schedule", href: v2SchedulePath() }}
            compact
            variant="v2"
          />
        )}
        {reminders.length > 0 && !preferences.matchReminders ? (
          <p className="text-xs text-text-tertiary">
            Reminder prompts are paused in Settings — your saved list stays here.
          </p>
        ) : null}
      </V2Section>

      <V2Section title="Bookmarks">
        {favorites.length > 0 ? (
          <div className="no-scrollbar flex gap-3 overflow-x-auto pb-1">
            {favorites.map((item) => (
              <SavedBookmarkCard key={`${item.type}-${item.id}`} item={item} />
            ))}
          </div>
        ) : (
          <FallbackState
            icon={Heart}
            title="No bookmarks yet"
            message="Bookmark matches and channels to return to quickly."
            primaryAction={{ label: "Discover", href: v2SearchPath() }}
            compact
            variant="v2"
          />
        )}
      </V2Section>

      <V2Section title="Recent sessions">
        {recentMatches.length > 0 ? (
          <ul className="space-y-2">
            {recentMatches.map((match) => (
              <li key={match.cid}>
                <Link
                  href={buildWatchPageHref(new URLSearchParams({
                    title: match.title,
                    league: match.league || "",
                    returnTo,
                    ...(isP2PContentId(match.cid) ? { cid: match.cid } : { id: match.cid }),
                  }))}
                  className={`flex items-center justify-between ${v2ListRowClass}`}
                >
                  <div className="flex min-w-0 items-center gap-3">
                    <span className="grid h-10 w-10 shrink-0 place-items-center rounded-lg bg-white/10 text-white">
                      <Play size={16} className="fill-current" />
                    </span>
                    <div className="min-w-0">
                      <p className="truncate text-sm font-semibold text-white">{match.title}</p>
                      <p className="truncate text-xs text-text-tertiary">{match.league || "Live session"}</p>
                    </div>
                  </div>
                  <Clock size={15} className="shrink-0 text-text-tertiary" />
                </Link>
              </li>
            ))}
          </ul>
        ) : (
          <FallbackState
            icon={Clock}
            title="No recent sessions"
            message="Matches you watch will appear here for quick return."
            primaryAction={{ label: "Open home", href: v2HomePath() }}
            compact
            variant="v2"
          />
        )}
      </V2Section>
    </V2PageShell>
  );
}

function Metric({ label, value }: { label: string; value: number }) {
  return (
    <div className={`${v2PanelClass} px-4 py-3`}>
      <p className="text-[10px] font-semibold uppercase tracking-wider text-text-tertiary">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums text-white">{value}</p>
    </div>
  );
}

function SavedBookmarkCard({ item }: { item: FavoriteItem }) {
  const poster = item.poster?.trim();
  const meta = item.meta || (item.type === "channel" ? "Channel" : item.type === "fixture" ? "Match" : "Saved");
  const card = (
    <article className="group w-[132px] shrink-0 snap-start sm:w-[148px]">
      <div className="relative aspect-[2/3] overflow-hidden rounded-xl border border-white/[0.08] bg-[#0d0d10] shadow-[0_12px_40px_rgba(0,0,0,0.45)] ring-1 ring-white/[0.04] transition duration-300 group-hover:border-white/12">
        {poster ? (
          <Image
            src={poster}
            alt={item.title}
            fill
            sizes="148px"
            unoptimized={!isOptimizedImageSrc(poster)}
            className="object-cover transition duration-500 group-hover:scale-[1.03]"
          />
        ) : (
          <div className="flex h-full flex-col items-center justify-center bg-gradient-to-b from-white/[0.08] to-black/50 px-2">
            <Heart size={28} className="text-white/40" />
          </div>
        )}
        <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent" />
        <span className="absolute bottom-2 right-2 rounded-full bg-white/90 px-2 py-0.5 text-[10px] font-semibold text-zinc-950">
          Saved
        </span>
      </div>
      <div className="mt-2 space-y-0.5 px-0.5">
        <h3 className="line-clamp-2 text-xs font-semibold leading-snug text-white">{item.title}</h3>
        <p className="line-clamp-1 text-[10px] text-text-tertiary">{meta}</p>
      </div>
    </article>
  );

  if (!item.href) return card;
  return <Link href={item.href}>{card}</Link>;
}
