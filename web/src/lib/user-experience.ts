"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  defaultLeagueTabForUser,
} from "@/lib/football-personalization";
import {
  readFootballLeaguePreference,
  writeFootballLeaguePreference,
} from "@/lib/football-league-preference";
import {
  type ReminderEntry,
  type TrackedTeamEntry,
  type UserPreferences,
  getReminders,
  getTrackedTeams,
  getUserPreferences,
  hasReminder,
  isTrackedTeam,
  removeReminder,
  removeTrackedTeam,
  saveReminder,
  saveTrackedTeam,
  subscribeToStorage,
  TRACKED_TEAMS_KEY,
  DEFAULT_PREFERENCES,
  updateUserPreferences,
} from "./storage";

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed"; platform: string }>;
}

function detectInstalled() {
  if (typeof window === "undefined") return false;
  const mediaMatch = window.matchMedia?.("(display-mode: standalone)").matches;
  const navigatorWithStandalone = window.navigator as Navigator & { standalone?: boolean };
  return Boolean(mediaMatch || navigatorWithStandalone.standalone === true);
}

function detectPlatform() {
  if (typeof window === "undefined") {
    return {
      isIOS: false,
      isSafari: false,
      isMobile: false,
    };
  }

  const userAgent = window.navigator.userAgent;
  const isIOS = /iPad|iPhone|iPod/.test(userAgent) || (window.navigator.platform === "MacIntel" && window.navigator.maxTouchPoints > 1);
  const isSafari = /^((?!chrome|android).)*safari/i.test(userAgent);
  const isMobile = /Android|iPhone|iPad|iPod/i.test(userAgent);

  return { isIOS, isSafari, isMobile };
}

export function useUserPreferences() {
  const [preferences, setPreferences] = useState<UserPreferences>(DEFAULT_PREFERENCES);

  useEffect(() => {
    const timer = window.setTimeout(() => setPreferences(getUserPreferences()), 0);
    const unsubscribe = subscribeToStorage((key) => {
      if (key === "fotty.web.preferences") {
        setPreferences(getUserPreferences());
      }
    });
    return () => {
      window.clearTimeout(timer);
      unsubscribe();
    };
  }, []);

  const setPreference = useCallback(
    <K extends keyof UserPreferences>(key: K, value: UserPreferences[K]) => {
      const next = updateUserPreferences({ [key]: value } as Partial<UserPreferences>);
      setPreferences(next);
    },
    []
  );

  return { preferences, setPreference };
}

export function useReminders() {
  const [reminders, setReminders] = useState<ReminderEntry[]>([]);

  useEffect(() => {
    const timer = window.setTimeout(() => setReminders(getReminders()), 0);
    const unsubscribe = subscribeToStorage((key) => {
      if (key === "fotty.web.reminders") {
        setReminders(getReminders());
      }
    });
    return () => {
      window.clearTimeout(timer);
      unsubscribe();
    };
  }, []);

  const refresh = useCallback(() => setReminders(getReminders()), []);

  return { reminders, refresh };
}

export function useReminderToggle(reminder: Omit<ReminderEntry, "createdAt"> | null) {
  const { reminders, refresh } = useReminders();

  const reminded = useMemo(() => {
    if (!reminder) return false;
    return reminders.some((entry) => entry.id === reminder.id && entry.startsAt === reminder.startsAt);
  }, [reminder, reminders]);

  const toggleReminder = useCallback(() => {
    if (!reminder) return false;

    if (hasReminder(reminder)) {
      removeReminder(reminder);
      refresh();
      return false;
    }

    saveReminder(reminder);
    refresh();
    return true;
  }, [refresh, reminder]);

  return { reminded, toggleReminder };
}

export function useTrackedTeams() {
  const [trackedTeams, setTrackedTeams] = useState<TrackedTeamEntry[]>([]);

  useEffect(() => {
    const timer = window.setTimeout(() => setTrackedTeams(getTrackedTeams()), 0);
    const unsubscribe = subscribeToStorage((key) => {
      if (key === TRACKED_TEAMS_KEY) {
        setTrackedTeams(getTrackedTeams());
      }
    });
    return () => {
      window.clearTimeout(timer);
      unsubscribe();
    };
  }, []);

  const refresh = useCallback(() => setTrackedTeams(getTrackedTeams()), []);

  const trackTeam = useCallback(
    (team: Omit<TrackedTeamEntry, "id" | "createdAt"> & { id?: string }) => {
      const saved = saveTrackedTeam(team);
      if (readFootballLeaguePreference() === null) {
        writeFootballLeaguePreference(defaultLeagueTabForUser(getTrackedTeams()));
      }
      refresh();
      return saved;
    },
    [refresh]
  );

  const removeTeam = useCallback(
    (team: Pick<TrackedTeamEntry, "id"> | string) => {
      removeTrackedTeam(team);
      refresh();
    },
    [refresh]
  );

  const isTracked = useCallback((name: string) => isTrackedTeam(name), []);

  return { trackedTeams, trackTeam, removeTeam, isTracked };
}

export function useInstallState() {
  const [platform, setPlatform] = useState(() => detectPlatform());
  const [isInstalled, setIsInstalled] = useState(() => detectInstalled());
  const promptRef = useRef<BeforeInstallPromptEvent | null>(null);
  const [canPromptInstall, setCanPromptInstall] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined") return;

    const updateInstalled = () => {
      setPlatform(detectPlatform());
      setIsInstalled(detectInstalled());
    };

    const handlePrompt = (event: Event) => {
      event.preventDefault();
      promptRef.current = event as BeforeInstallPromptEvent;
      setCanPromptInstall(true);
    };

    const handleInstalled = () => {
      promptRef.current = null;
      setCanPromptInstall(false);
      setIsInstalled(true);
    };

    const mediaQuery = window.matchMedia?.("(display-mode: standalone)");
    updateInstalled();

    mediaQuery?.addEventListener?.("change", updateInstalled);
    window.addEventListener("beforeinstallprompt", handlePrompt as EventListener);
    window.addEventListener("appinstalled", handleInstalled);

    return () => {
      mediaQuery?.removeEventListener?.("change", updateInstalled);
      window.removeEventListener("beforeinstallprompt", handlePrompt as EventListener);
      window.removeEventListener("appinstalled", handleInstalled);
    };
  }, []);

  const promptInstall = useCallback(async () => {
    if (!promptRef.current) return false;

    await promptRef.current.prompt();
    const choice = await promptRef.current.userChoice;
    if (choice.outcome === "accepted") {
      promptRef.current = null;
      setCanPromptInstall(false);
      setIsInstalled(true);
      return true;
    }

    return false;
  }, []);

  return {
    ...platform,
    isInstalled,
    canPromptInstall,
    promptInstall,
  };
}
