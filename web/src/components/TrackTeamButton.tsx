"use client";

import { Bell, BellRing } from "lucide-react";
import { trackEvent } from "@/lib/analytics";
import { FottyAPI } from "@/lib/api";
import { syncReminderForTrackedTeam } from "@/lib/match-alerts";
import { updateUserPreferences } from "@/lib/storage";
import { useTrackedTeams } from "@/lib/user-experience";
import { cn } from "@/lib/utils";

interface TrackTeamButtonProps {
  name: string;
  sport?: string;
  league?: string;
  className?: string;
}

export function TrackTeamButton({ name, sport, league, className }: TrackTeamButtonProps) {
  const { isTracked, trackTeam, removeTeam } = useTrackedTeams();
  const tracked = isTracked(name);

  return (
    <button
      type="button"
      onClick={() => {
        if (tracked) {
          removeTeam(name);
        } else {
          trackTeam({ name, sport, league });
          updateUserPreferences({ matchReminders: true });
          void FottyAPI.fetchMatches()
            .then((matches) => syncReminderForTrackedTeam(matches, name))
            .catch(() => undefined);
        }

        trackEvent("track_team_click", {
          team: name,
          sport,
          league,
          tracked: !tracked,
        });
      }}
      className={cn(
        "inline-flex min-h-11 items-center justify-center gap-2 rounded-lg border px-3 py-2 text-xs font-black transition-colors",
        tracked
          ? "border-accent/35 bg-accent/15 text-accent"
          : "border-white/10 bg-white/5 text-text-secondary hover:bg-white/10 hover:text-text-primary",
        className
      )}
      aria-pressed={tracked}
    >
      {tracked ? <BellRing size={14} /> : <Bell size={14} />}
      {tracked ? "Following" : `Follow ${name}`}
    </button>
  );
}
