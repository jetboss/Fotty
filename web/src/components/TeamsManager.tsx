"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { ArrowLeft, Bell, BellRing, Check, Plus, Trash2 } from "lucide-react";
import { TeamNameAutocomplete, resolveTeamSelection } from "@/components/TeamNameAutocomplete";
import { FallbackState } from "@/components/FallbackState";
import { trackEvent } from "@/lib/analytics";
import { FottyAPI } from "@/lib/api";
import { syncReminderForTrackedTeam } from "@/lib/match-alerts";
import { buildTeamCatalogFromMatches, type TeamSuggestion } from "@/lib/team-catalog";
import { updateUserPreferences } from "@/lib/storage";
import { useTrackedTeams } from "@/lib/user-experience";
import { cn } from "@/lib/utils";
import { v2HomePath } from "@/lib/v2/preview";
import { V2PageHeader, V2PageShell, v2PanelClass } from "@/components/v2/V2PageShell";

interface TeamsManagerProps {
  variant?: "classic" | "v2";
  backHref?: string;
  homeHref?: string;
}

export function TeamsManager({ variant = "classic", backHref, homeHref }: TeamsManagerProps) {
  const isV2 = variant === "v2";
  const resolvedBackHref = backHref ?? (isV2 ? v2HomePath() : "/settings");
  const resolvedHomeHref = homeHref ?? v2HomePath();

  const { trackedTeams, trackTeam, removeTeam } = useTrackedTeams();
  const [teamName, setTeamName] = useState("");
  const [matches, setMatches] = useState<Awaited<ReturnType<typeof FottyAPI.fetchMatches>>>([]);
  const [notificationPermission, setNotificationPermission] = useState<NotificationPermission | "unsupported">("unsupported");

  useEffect(() => {
    if (typeof window !== "undefined" && "Notification" in window) {
      setNotificationPermission(Notification.permission);
    }
  }, []);

  const catalog = useMemo(() => buildTeamCatalogFromMatches(matches), [matches]);

  useEffect(() => {
    let cancelled = false;
    FottyAPI.fetchMatches()
      .then((next) => {
        if (!cancelled) setMatches(next);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, []);

  const requestNotifications = useCallback(async () => {
    if (!("Notification" in window)) {
      setNotificationPermission("unsupported");
      return false;
    }

    if (Notification.permission === "denied") {
      window.alert(
        "Notifications are blocked for this site. Open your browser settings, allow notifications for Fotty, then reload."
      );
      return false;
    }

    const permission = await Notification.requestPermission();
    setNotificationPermission(permission);
    trackEvent("browser_notifications_permission", {
      permission,
      source: isV2 ? "teams_page_v2" : "teams_page",
    });

    if (permission === "granted") {
      updateUserPreferences({ matchReminders: true });
    }

    return permission === "granted";
  }, [isV2]);

  const addTeam = async (selection?: TeamSuggestion) => {
    const resolved = selection || resolveTeamSelection(teamName, catalog);
    if (!resolved) return;
    const name = resolved.name.trim();
    if (!name) return;

    trackTeam({
      name,
      sport: resolved.sport || "Football",
      league: resolved.league,
    });
    updateUserPreferences({ matchReminders: true });
    syncReminderForTrackedTeam(matches, name);

    trackEvent("track_team_click", {
      team: name,
      sport: resolved.sport || "Football",
      league: resolved.league,
      source: isV2 ? "teams_page_v2" : "teams_page",
      tracked: true,
    });

    setTeamName("");

    if (notificationPermission !== "granted") {
      await requestNotifications();
    }
  };

  const notificationsEnabled = notificationPermission === "granted";
  const panelClass = isV2 ? v2PanelClass : "rounded-xl border border-white/5 bg-surface";
  const trackButtonClass = isV2
    ? "inline-flex min-h-12 items-center justify-center gap-2 rounded-full bg-white px-5 text-sm font-semibold text-black"
    : "inline-flex min-h-12 items-center justify-center gap-2 rounded-lg accent-gradient px-4 text-xs font-black text-white";

  const body = (
    <>
      <header className={cn("space-y-4", !isV2 && "px-md")}>
        {isV2 ? (
          <V2PageHeader
            title="Your teams"
            subtitle="Track clubs you care about. Fotty surfaces their matches on home and sends kickoff reminders when notifications are enabled."
          />
        ) : (
          <>
            <Link
              href={resolvedBackHref}
              className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-surface text-text-primary"
              aria-label="Back"
            >
              <ArrowLeft size={18} />
            </Link>
            <div className="space-y-2">
              <h1 className="text-4xl font-black text-white">Your teams</h1>
              <p className="max-w-2xl text-sm font-medium leading-6 text-text-secondary">
                Track clubs you care about. Fotty surfaces their matches on home and sends kickoff reminders when
                notifications are enabled.
              </p>
            </div>
          </>
        )}
      </header>

      <div className={cn("space-y-4 py-6", !isV2 && "px-md py-lg", isV2 && "py-0")}>
        <section className={cn(panelClass, "p-4 space-y-4")}>
          <div className="flex flex-col gap-3 sm:flex-row">
            <TeamNameAutocomplete
              inputId={isV2 ? "team-name-v2" : "team-name"}
              value={teamName}
              onChange={setTeamName}
              onSelect={(suggestion) => {
                void addTeam(suggestion);
              }}
            />
            <button type="button" onClick={() => void addTeam()} className={trackButtonClass}>
              <Plus size={15} />
              Track team
            </button>
          </div>

          {/* Quick Track Popular Clubs */}
          <div className="space-y-2 pt-2 border-t border-white/[0.06]">
            <p className="text-xs font-semibold text-text-tertiary">Quick add top clubs</p>
            <div className="flex flex-wrap gap-2">
              {[
                { name: "Arsenal", league: "Premier League" },
                { name: "Real Madrid", league: "La Liga" },
                { name: "Liverpool", league: "Premier League" },
                { name: "Barcelona", league: "La Liga" },
                { name: "Manchester City", league: "Premier League" },
                { name: "Chelsea", league: "Premier League" },
                { name: "Bayern Munich", league: "Bundesliga" },
                { name: "Inter Milan", league: "Serie A" },
                { name: "PSG", league: "Ligue 1" },
                { name: "Inter Miami", league: "MLS" },
              ].map((club) => {
                const isTracked = trackedTeams.some((t) => t.name.toLowerCase() === club.name.toLowerCase());
                return (
                  <button
                    key={club.name}
                    type="button"
                    onClick={() => {
                      if (isTracked) {
                        const match = trackedTeams.find((t) => t.name.toLowerCase() === club.name.toLowerCase());
                        if (match) removeTeam(match);
                      } else {
                        void addTeam({ name: club.name, league: club.league, sport: "Football" });
                      }
                    }}
                    className={cn(
                      "inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold transition",
                      isTracked
                        ? "bg-white text-black font-bold"
                        : "border border-white/10 bg-white/[0.04] text-zinc-300 hover:border-white/20 hover:text-white"
                    )}
                  >
                    {isTracked ? <Check size={12} /> : <Plus size={12} />}
                    {club.name}
                  </button>
                );
              })}
            </div>
          </div>
        </section>

        <section className={cn(panelClass, "overflow-hidden")}>
          {trackedTeams.length > 0 ? (
            trackedTeams.map((team) => (
              <div
                key={team.id}
                className="flex items-center justify-between gap-4 border-b border-white/5 p-4 last:border-b-0"
              >
                <div className="flex min-w-0 items-center gap-3">
                  <div
                    className={cn(
                      "grid h-10 w-10 shrink-0 place-items-center rounded-full",
                      isV2 ? "bg-white/10 text-white" : "bg-accent/15 text-accent"
                    )}
                  >
                    <BellRing size={17} />
                  </div>
                  <div className="min-w-0">
                    <p className="truncate text-sm font-semibold text-white">{team.name}</p>
                    <p className="truncate text-xs text-text-tertiary">
                      {[team.sport || "Football", team.league].filter(Boolean).join(" · ")}
                    </p>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    removeTeam(team);
                    trackEvent("track_team_click", {
                      team: team.name,
                      sport: team.sport,
                      league: team.league,
                      source: isV2 ? "teams_page_v2" : "teams_page",
                      tracked: false,
                    });
                  }}
                  className="grid h-10 w-10 shrink-0 place-items-center rounded-full border border-white/10 bg-white/5 text-text-secondary"
                  aria-label={`Stop tracking ${team.name}`}
                >
                  <Trash2 size={15} />
                </button>
              </div>
            ))
          ) : (
            <div className="p-4">
              <FallbackState
                icon={BellRing}
                title="No teams tracked yet"
                message="Start typing a club name to see suggestions, or track a team from a fixture on home."
                primaryAction={{ label: "Back to home", href: resolvedHomeHref }}
                compact
                variant={variant}
              />
            </div>
          )}
        </section>

        <section className={cn(panelClass, "relative z-10 p-4")}>
          <p className="text-sm font-semibold text-white">Notification status</p>
          <p className="mt-2 text-xs leading-6 text-text-tertiary">
            Enable browser notifications for upcoming-match alerts and a final reminder before kickoff.
          </p>
          <div className="mt-4 flex flex-col gap-3">
            <div className="inline-flex items-center gap-2 text-xs font-medium text-white">
              <span
                className={
                  notificationsEnabled
                    ? "grid h-8 w-8 place-items-center rounded-full bg-live/15 text-live"
                    : "grid h-8 w-8 place-items-center rounded-full bg-white/5 text-text-secondary"
                }
              >
                {notificationsEnabled ? <Check size={15} /> : <Bell size={15} />}
              </span>
              {notificationPermission === "unsupported"
                ? "Notifications unavailable in this browser"
                : notificationPermission === "denied"
                  ? "Notifications blocked in browser settings"
                  : notificationsEnabled
                    ? "Browser notifications enabled"
                    : "Browser notifications not enabled"}
            </div>
            <button
              type="button"
              onClick={() => void requestNotifications()}
              disabled={notificationsEnabled || notificationPermission === "unsupported"}
              className="inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 text-xs font-semibold text-white disabled:cursor-not-allowed disabled:opacity-55 sm:w-auto sm:self-start"
            >
              <Bell size={15} />
              {notificationPermission === "denied" ? "How to unblock notifications" : "Enable browser notifications"}
            </button>
          </div>
        </section>
      </div>
    </>
  );

  if (isV2) {
    return (
      <V2PageShell innerClassName="max-w-2xl space-y-6">
        {body}
      </V2PageShell>
    );
  }

  return (
    <main className="min-h-dvh bg-background pt-12 text-text-primary">
      {body}
    </main>
  );
}
