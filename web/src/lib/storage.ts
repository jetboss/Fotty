"use client";

import type { MediaItem, ScrapedMatch } from "./api";
import { syncPocketBaseRecordLater } from "./pocketbase-sync";

export interface FavoriteItem extends MediaItem {
  savedAt: string;
}

export interface RecentMatchEntry {
  cid: string;
  title: string;
  league?: string;
  poster?: string;
  watchedAt: string;
}

export interface ReminderEntry {
  id: string;
  cid: string;
  title: string;
  league?: string;
  sport?: string;
  startsAt: string;
  href: string;
  createdAt: string;
}

export interface TrackedTeamEntry {
  id: string;
  name: string;
  sport?: string;
  league?: string;
  createdAt: string;
}

export interface CollabInquiryEntry {
  packageId: string;
  packageTitle: string;
  organization?: string;
  contact?: string;
  region?: string;
  audienceSize?: string;
  useCase?: string;
  matchFocus?: string;
  createdAt: string;
}

export interface SupportPledgeEntry {
  plan: string;
  title: string;
  amount?: number;
  contact?: string;
  note?: string;
  createdAt: string;
}

export interface UserPreferences {
  matchReminders: boolean;
  spoilerProtection: boolean;
  compactMode: boolean;
  autoPlayHighlights: boolean;
  installCtaDismissed: boolean;
}

const FAVORITES_KEY = "fotty.web.favorites"; // gitleaks:allow -- localStorage namespace
const LEGACY_WATCH_HISTORY_KEY = "fotty.web.watchHistory";
const RECENT_MATCHES_KEY = "fotty.web.recentMatches";
const REMINDERS_KEY = "fotty.web.reminders";
export const TRACKED_TEAMS_KEY = "fotty.web.trackedTeams";
export const COLLAB_INQUIRIES_KEY = "fotty.web.collabInquiries.v1"; // gitleaks:allow -- localStorage namespace
export const SUPPORT_PLEDGES_KEY = "fotty.web.supportPledges.v1";
const PREFERENCES_KEY = "fotty.web.preferences";
const STORAGE_EVENT = "fotty:storage";

export const DEFAULT_PREFERENCES: UserPreferences = {
  matchReminders: true,
  spoilerProtection: false,
  compactMode: false,
  autoPlayHighlights: false,
  installCtaDismissed: false,
};

function readList<T>(key: string): T[] {
  if (typeof window === "undefined") return [];

  try {
    const value = window.localStorage.getItem(key);
    if (!value) return [];
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? (parsed as T[]) : [];
  } catch {
    return [];
  }
}

function writeList<T>(key: string, items: T[]) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(key, JSON.stringify(items));
  window.dispatchEvent(new CustomEvent(STORAGE_EVENT, { detail: { key, value: items } }));
}

function readObject<T>(key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;

  try {
    const value = window.localStorage.getItem(key);
    if (!value) return fallback;
    return { ...fallback, ...JSON.parse(value) } as T;
  } catch {
    return fallback;
  }
}

function writeObject<T>(key: string, value: T) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(key, JSON.stringify(value));
  window.dispatchEvent(new CustomEvent(STORAGE_EVENT, { detail: { key, value } }));
}

function reminderKey(reminder: Pick<ReminderEntry, "id" | "startsAt">) {
  return `${reminder.id}:${reminder.startsAt}`;
}

export function trackedTeamId(name: string) {
  return name.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "team";
}

function sanitizeReminders(reminders: ReminderEntry[]) {
  const cutoff = Date.now() - 6 * 60 * 60 * 1000;

  return reminders
    .filter((reminder) => {
      const kickoff = new Date(reminder.startsAt).getTime();
      return Boolean(reminder.id && reminder.cid && reminder.title && reminder.href) && Number.isFinite(kickoff) && kickoff >= cutoff;
    })
    .sort((left, right) => new Date(left.startsAt).getTime() - new Date(right.startsAt).getTime());
}

function sanitizeTrackedTeams(teams: TrackedTeamEntry[]) {
  const seen = new Set<string>();

  return teams
    .map((team) => ({
      ...team,
      id: team.id || trackedTeamId(team.name),
      name: team.name?.trim() || "",
      createdAt: team.createdAt || new Date().toISOString(),
    }))
    .filter((team) => {
      if (!team.name) return false;
      const key = team.id || trackedTeamId(team.name);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .sort((left, right) => new Date(right.createdAt).getTime() - new Date(left.createdAt).getTime())
    .slice(0, 40);
}

function mediaKey(item: Pick<MediaItem, "type" | "id">) {
  return `${item.type}:${item.id}`;
}

export function getFavorites(): FavoriteItem[] {
  return readList<FavoriteItem>(FAVORITES_KEY);
}

export function isFavorite(item: Pick<MediaItem, "type" | "id">): boolean {
  const key = mediaKey(item);
  return getFavorites().some((favorite) => mediaKey(favorite) === key);
}

export function toggleFavorite(item: MediaItem): boolean {
  const key = mediaKey(item);
  const favorites = getFavorites();
  const existingIndex = favorites.findIndex((favorite) => mediaKey(favorite) === key);

  if (existingIndex >= 0) {
    favorites.splice(existingIndex, 1);
    writeList(FAVORITES_KEY, favorites);
    return false;
  }

  writeList(FAVORITES_KEY, [{ ...item, savedAt: new Date().toISOString() }, ...favorites].slice(0, 80));
  return true;
}

/** Drops pre-sports-only media history (movies/TV) from localStorage. */
export function purgeLegacyWatchHistory() {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.removeItem(LEGACY_WATCH_HISTORY_KEY);
  } catch {
    // Non-blocking cleanup.
  }
}

export function getRecentMatches(): RecentMatchEntry[] {
  return readList<RecentMatchEntry>(RECENT_MATCHES_KEY);
}

export function recordRecentMatch(match: Pick<ScrapedMatch, "cid" | "title" | "league" | "poster">) {
  const next = [
    { ...match, watchedAt: new Date().toISOString() },
    ...getRecentMatches().filter((entry) => entry.cid !== match.cid),
  ].slice(0, 30);

  writeList(RECENT_MATCHES_KEY, next);
}

export function getReminders(): ReminderEntry[] {
  return sanitizeReminders(readList<ReminderEntry>(REMINDERS_KEY));
}

export function hasReminder(reminder: Pick<ReminderEntry, "id" | "startsAt">): boolean {
  const key = reminderKey(reminder);
  return getReminders().some((entry) => reminderKey(entry) === key);
}

export function saveReminder(reminder: Omit<ReminderEntry, "createdAt">) {
  const nextReminder: ReminderEntry = {
    ...reminder,
    createdAt: new Date().toISOString(),
  };
  const key = reminderKey(nextReminder);
  const next = [
    nextReminder,
    ...getReminders().filter((entry) => reminderKey(entry) !== key),
  ];

  writeList(REMINDERS_KEY, sanitizeReminders(next));
  syncPocketBaseRecordLater("matchReminder", nextReminder);
}

export function removeReminder(reminder: Pick<ReminderEntry, "id" | "startsAt">) {
  const key = reminderKey(reminder);
  writeList(
    REMINDERS_KEY,
    getReminders().filter((entry) => reminderKey(entry) !== key)
  );
}

export function getTrackedTeams(): TrackedTeamEntry[] {
  return sanitizeTrackedTeams(readList<TrackedTeamEntry>(TRACKED_TEAMS_KEY));
}

export function isTrackedTeam(name: string): boolean {
  const id = trackedTeamId(name);
  return getTrackedTeams().some((team) => team.id === id);
}

export function saveTrackedTeam(team: Omit<TrackedTeamEntry, "id" | "createdAt"> & { id?: string; createdAt?: string }) {
  const nextTeam: TrackedTeamEntry = {
    ...team,
    id: team.id || trackedTeamId(team.name),
    name: team.name.trim(),
    createdAt: team.createdAt || new Date().toISOString(),
  };
  const next = [nextTeam, ...getTrackedTeams().filter((entry) => entry.id !== nextTeam.id)];
  writeList(TRACKED_TEAMS_KEY, sanitizeTrackedTeams(next));
  syncPocketBaseRecordLater("teamFollow", nextTeam);
  return nextTeam;
}

export function removeTrackedTeam(team: Pick<TrackedTeamEntry, "id"> | string) {
  const id = typeof team === "string" ? trackedTeamId(team) : team.id;
  writeList(
    TRACKED_TEAMS_KEY,
    getTrackedTeams().filter((entry) => entry.id !== id)
  );
}

export function getCollabInquiries(): CollabInquiryEntry[] {
  return readList<CollabInquiryEntry>(COLLAB_INQUIRIES_KEY).slice(0, 30);
}

export function saveCollabInquiry(inquiry: Omit<CollabInquiryEntry, "createdAt"> & { createdAt?: string }) {
  const entry: CollabInquiryEntry = {
    ...inquiry,
    createdAt: inquiry.createdAt || new Date().toISOString(),
  };
  writeList(COLLAB_INQUIRIES_KEY, [entry, ...getCollabInquiries()].slice(0, 30));
  syncPocketBaseRecordLater("collabInquiry", entry);
  return entry;
}

export function getSupportPledges(): SupportPledgeEntry[] {
  return readList<SupportPledgeEntry>(SUPPORT_PLEDGES_KEY).slice(0, 20);
}

export function saveSupportPledge(pledge: Omit<SupportPledgeEntry, "createdAt"> & { createdAt?: string }) {
  const entry: SupportPledgeEntry = {
    ...pledge,
    createdAt: pledge.createdAt || new Date().toISOString(),
  };
  writeList(SUPPORT_PLEDGES_KEY, [entry, ...getSupportPledges()].slice(0, 20));
  syncPocketBaseRecordLater("supportPledge", entry);
  return entry;
}

export function getUserPreferences(): UserPreferences {
  return readObject<UserPreferences>(PREFERENCES_KEY, DEFAULT_PREFERENCES);
}

export function updateUserPreferences(updates: Partial<UserPreferences>) {
  const next = {
    ...getUserPreferences(),
    ...updates,
  };
  writeObject(PREFERENCES_KEY, next);
  return next;
}

export function buildReminderCalendarURL(reminder: ReminderEntry) {
  const start = new Date(reminder.startsAt);
  const end = new Date(start.getTime() + 2 * 60 * 60 * 1000);
  const escapeText = (value: string) => value.replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/,/g, "\\,").replace(/;/g, "\\;");
  const formatDate = (value: Date) => value.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
  const event = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Fotty//Match Reminder//EN",
    "BEGIN:VEVENT",
    `UID:${escapeText(reminder.id)}@fotty.web`,
    `DTSTAMP:${formatDate(new Date())}`,
    `DTSTART:${formatDate(start)}`,
    `DTEND:${formatDate(end)}`,
    `SUMMARY:${escapeText(reminder.title)}`,
    `DESCRIPTION:${escapeText(`Open in Fotty: ${reminder.href}`)}`,
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\r\n");

  return `data:text/calendar;charset=utf-8,${encodeURIComponent(event)}`;
}

export function subscribeToStorage(callback: (key: string) => void) {
  if (typeof window === "undefined") {
    return () => {};
  }

  const customHandler = (event: Event) => {
    const detail = (event as CustomEvent<{ key?: string }>).detail;
    if (detail?.key) callback(detail.key);
  };

  const storageHandler = (event: StorageEvent) => {
    if (event.key) callback(event.key);
  };

  window.addEventListener(STORAGE_EVENT, customHandler as EventListener);
  window.addEventListener("storage", storageHandler);

  return () => {
    window.removeEventListener(STORAGE_EVENT, customHandler as EventListener);
    window.removeEventListener("storage", storageHandler);
  };
}

export interface WatchHistoryEntry extends MediaItem {
  watchedAt: string;
  progress?: number;
}

export function getWatchHistory(): WatchHistoryEntry[] {
  return [];
}

export function recordWatch(item: MediaItem, progress = 0.1) {
  // Static export dummy stub
}
