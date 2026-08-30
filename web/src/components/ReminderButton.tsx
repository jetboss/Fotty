"use client";

import React from "react";
import { Bell, BellOff, CalendarPlus } from "lucide-react";
import type { ScrapedMatch } from "@/lib/api";
import { buildReminderPayload } from "@/lib/live";
import { updateUserPreferences } from "@/lib/storage";
import { useReminderToggle } from "@/lib/user-experience";
import { cn } from "@/lib/utils";

interface ReminderButtonProps {
  match: ScrapedMatch;
  returnTo: string;
  compact?: boolean;
  className?: string;
}

export function ReminderButton({ match, returnTo, compact = false, className }: ReminderButtonProps) {
  const reminder = buildReminderPayload(match, returnTo);
  const { reminded, toggleReminder } = useReminderToggle(reminder);

  if (!reminder) return null;

  return (
    <button
      type="button"
      onClick={() => {
        const active = toggleReminder();
        if (active) {
          updateUserPreferences({ matchReminders: true });
        }
      }}
      className={cn(
        compact
          ? "inline-flex h-10 items-center justify-center gap-2 rounded-full border border-white/10 bg-white/5 px-3 py-2 text-[11px] font-bold text-text-secondary max-[430px]:h-11 max-[430px]:w-11 max-[430px]:px-0"
          : "inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-2.5 text-xs font-bold text-text-secondary",
        reminded && "border-accent/30 bg-accent/10 text-accent",
        className
      )}
      aria-pressed={reminded}
    >
      {reminded ? <BellOff size={compact ? 13 : 14} /> : compact ? <Bell size={13} /> : <CalendarPlus size={14} />}
      <span className={compact ? "max-[430px]:sr-only" : undefined}>{reminded ? "Remove reminder" : "Remind me"}</span>
    </button>
  );
}
