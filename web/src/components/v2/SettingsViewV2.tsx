"use client";

import Link from "next/link";
import type { LucideIcon } from "lucide-react";
import { Bell, Crown, EyeOff, Lock, Mail, MonitorSmartphone, User } from "lucide-react";
import { useAuth } from "@/components/AuthProvider";
import { useEntitlement } from "@/components/EntitlementProvider";
import { isAccountsEnabled } from "@/lib/accounts";
import { useReminders, useTrackedTeams, useUserPreferences } from "@/lib/user-experience";
import { v2FavoritesPath, v2TeamsPath } from "@/lib/v2/preview";
import { cn } from "@/lib/utils";
import { V2PageHeader, V2PageShell, v2PanelClass } from "@/components/v2/V2PageShell";

export function SettingsViewV2() {
  const { session } = useAuth();
  const entitlement = useEntitlement();
  const accountsEnabled = isAccountsEnabled();
  const { preferences, setPreference } = useUserPreferences();
  const { reminders } = useReminders();
  const { trackedTeams } = useTrackedTeams();

  return (
    <V2PageShell innerClassName="max-w-lg space-y-6">
      <V2PageHeader title="Settings" subtitle="Account and match-day preferences." />

      <section className={`${v2PanelClass} p-4`}>
        <div className="flex items-center gap-4">
          <div className="grid h-12 w-12 place-items-center rounded-full bg-white/10 text-sm font-bold text-white">
            FT
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold text-white">
              {accountsEnabled ? session?.email || "Guest" : "Guest"}
            </p>
            <p className="truncate text-xs text-text-tertiary">
              {accountsEnabled
                ? session
                  ? entitlement.accessDetail
                  : "Sign in for full access"
                : "Accounts paused — watching is open on the web"}
            </p>
          </div>
          {accountsEnabled ? (
            <Link
              href={session ? "/login" : "/login?mode=signup"}
              className="fotty-v2-auth-cta shrink-0 rounded-full px-3 py-1.5 text-xs font-semibold accent-gradient text-white"
            >
              {session ? "Account" : "Sign up"}
            </Link>
          ) : null}
        </div>
      </section>

      <SettingsBlock title="Match day">
        <SettingLink
          icon={Bell}
          title="Your teams"
          subtitle="Track clubs for home rails and alerts"
          value={trackedTeams.length > 0 ? String(trackedTeams.length) : undefined}
          href={v2TeamsPath()}
        />
        <SettingLink
          icon={Bell}
          title="Saved reminders"
          subtitle="Upcoming fixtures on this device"
          value={reminders.length > 0 ? String(reminders.length) : undefined}
          href={v2FavoritesPath()}
        />
        <ToggleSetting
          icon={Bell}
          title="Match reminders"
          subtitle="Surfaces and saved upcoming fixtures"
          value={preferences.matchReminders}
          onChange={(value) => setPreference("matchReminders", value)}
        />
        <ToggleSetting
          icon={EyeOff}
          title="Spoiler protection"
          subtitle="Hide scores until you watch"
          value={preferences.spoilerProtection}
          onChange={(value) => setPreference("spoilerProtection", value)}
        />
        <ToggleSetting
          icon={MonitorSmartphone}
          title="Compact mode"
          subtitle="Tighter cards on busy days"
          value={preferences.compactMode}
          onChange={(value) => setPreference("compactMode", value)}
        />
      </SettingsBlock>

      <SettingsBlock title="Legal & support">
        <SettingLink icon={Lock} title="Privacy" href="/privacy" />
        <SettingLink icon={Mail} title="Feedback" href="/feedback" />
        <SettingLink icon={MonitorSmartphone} title="Help" href="/help" />
      </SettingsBlock>
    </V2PageShell>
  );
}

function SettingsBlock({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="space-y-2">
      <h2 className="px-1 text-[11px] font-semibold uppercase tracking-wider text-text-tertiary">{title}</h2>
      <div className={`${v2PanelClass} divide-y divide-white/[0.06] overflow-hidden`}>{children}</div>
    </section>
  );
}

function SettingLink({
  icon: Icon,
  title,
  subtitle,
  value,
  href,
}: {
  icon: LucideIcon;
  title: string;
  subtitle?: string;
  value?: string;
  href: string;
}) {
  return (
    <Link href={href} className="flex items-center gap-4 px-4 py-3.5 transition hover:bg-white/[0.04]">
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-white/5 text-white">
        <Icon size={17} />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-sm font-medium text-white">{title}</span>
        {subtitle ? <span className="block text-xs text-text-tertiary">{subtitle}</span> : null}
      </span>
      {value ? <span className="shrink-0 text-xs font-medium text-text-tertiary">{value}</span> : null}
    </Link>
  );
}

function ToggleSetting({
  icon: Icon,
  title,
  subtitle,
  value,
  onChange,
}: {
  icon: LucideIcon;
  title: string;
  subtitle?: string;
  value: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <div className="flex items-center gap-4 px-4 py-3.5">
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-white/5 text-white">
        <Icon size={17} />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-sm font-medium text-white">{title}</span>
        {subtitle ? <span className="block text-xs text-text-tertiary">{subtitle}</span> : null}
      </span>
      <button
        type="button"
        onClick={() => onChange(!value)}
        className={cn(
          "relative h-7 w-12 shrink-0 rounded-full transition-colors",
          value ? "bg-white" : "bg-white/15"
        )}
        aria-pressed={value}
        aria-label={title}
      >
        <span
          className={cn(
            "absolute top-1 h-5 w-5 rounded-full transition-all",
            value ? "right-1 bg-zinc-950" : "left-1 bg-white"
          )}
        />
      </button>
    </div>
  );
}
