"use client";

import { useEffect, useRef } from "react";
import { FottyAPI } from "@/lib/api";
import {
  collectSavedReminderAlerts,
  collectTrackedTeamAlerts,
} from "@/lib/match-alerts";
import { showMatchReminderNotification } from "@/lib/push";
import {
  getReminders,
  getTrackedTeams,
  getUserPreferences,
  subscribeToStorage,
  TRACKED_TEAMS_KEY,
} from "@/lib/storage";

const NOTIFIED_ALERTS_KEY = "fotty.web.notifiedAlerts.v1";
const MATCH_REFRESH_MS = 5 * 60 * 1000;
const CHECK_INTERVAL_MS = 30 * 1000;

function readNotifiedAlerts() {
  if (typeof window === "undefined") return new Set<string>();

  try {
    const parsed = JSON.parse(window.localStorage.getItem(NOTIFIED_ALERTS_KEY) || "[]");
    return new Set<string>(Array.isArray(parsed) ? parsed.filter((value) => typeof value === "string") : []);
  } catch {
    return new Set<string>();
  }
}

function writeNotifiedAlerts(keys: Set<string>) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(NOTIFIED_ALERTS_KEY, JSON.stringify([...keys].slice(-120)));
}

export function ReminderNotifier() {
  const notifiedRef = useRef<Set<string>>(new Set());
  const matchesRef = useRef<Awaited<ReturnType<typeof FottyAPI.fetchMatches>>>([]);
  const matchesLoadedAtRef = useRef(0);

  useEffect(() => {
    notifiedRef.current = readNotifiedAlerts();

    const refreshMatches = async () => {
      try {
        matchesRef.current = await FottyAPI.fetchMatches();
        matchesLoadedAtRef.current = Date.now();
      } catch {
        // Keep the last good feed for alert checks.
      }
    };

    const checkAlerts = () => {
      if (!("Notification" in window) || Notification.permission !== "granted") return;
      if (!getUserPreferences().matchReminders) return;

      const now = Date.now();
      if (now - matchesLoadedAtRef.current > MATCH_REFRESH_MS) {
        void refreshMatches().then(() => checkAlerts());
        return;
      }

      const trackedTeams = getTrackedTeams();
      const trackedAlerts = collectTrackedTeamAlerts(matchesRef.current, trackedTeams, now);
      const reminderAlerts = collectSavedReminderAlerts(getReminders(), now);
      const alerts = [...trackedAlerts, ...reminderAlerts];

      alerts.forEach((alert) => {
        if (notifiedRef.current.has(alert.key)) return;

        notifiedRef.current.add(alert.key);
        writeNotifiedAlerts(notifiedRef.current);

        void showMatchReminderNotification({
          title: alert.title,
          body: alert.body,
          url: alert.url,
          tag: alert.tag,
        });
      });
    };

    void refreshMatches().then(checkAlerts);

    const interval = window.setInterval(checkAlerts, CHECK_INTERVAL_MS);
    const matchInterval = window.setInterval(() => {
      void refreshMatches();
    }, MATCH_REFRESH_MS);

    const unsubscribe = subscribeToStorage((key) => {
      if (key.includes("reminders") || key.includes("preferences") || key === TRACKED_TEAMS_KEY) {
        checkAlerts();
      }
    });

    const onVisible = () => {
      if (document.visibilityState === "visible") {
        void refreshMatches().then(checkAlerts);
      }
    };
    document.addEventListener("visibilitychange", onVisible);

    return () => {
      window.clearInterval(interval);
      window.clearInterval(matchInterval);
      document.removeEventListener("visibilitychange", onVisible);
      unsubscribe();
    };
  }, []);

  return null;
}
