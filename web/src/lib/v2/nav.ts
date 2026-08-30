"use client";

import type { LucideIcon } from "lucide-react";
import {
  Bookmark,
  CalendarDays,
  Compass,
  LayoutGrid,
  MoreHorizontal,
  Settings,
  Table2,
  Users,
} from "lucide-react";
import {
  v2FavoritesPath,
  v2HomePath,
  v2MorePath,
  v2SchedulePath,
  v2SearchPath,
  v2SettingsPath,
  v2TablesPath,
  v2TeamsPath,
} from "@/lib/v2/preview";

export type V2NavItem = {
  href: string;
  label: string;
  icon: LucideIcon;
  match: (pathname: string) => boolean;
};

function matchesHref(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  return pathname === href || pathname.startsWith(`${href}/`) || pathname.startsWith(`${href}?`);
}

export function buildV2MobileNav(): V2NavItem[] {
  const home = v2HomePath();
  return [
    {
      href: home,
      label: "Home",
      icon: LayoutGrid,
      match: (pathname) => pathname === "/" || pathname === "/next" || pathname === "/next/",
    },
    {
      href: v2SearchPath(),
      label: "Discover",
      icon: Compass,
      match: (pathname) => matchesHref(pathname, v2SearchPath()),
    },
    {
      href: v2SchedulePath(),
      label: "Schedule",
      icon: CalendarDays,
      match: (pathname) => matchesHref(pathname, v2SchedulePath()),
    },
    {
      href: v2MorePath(),
      label: "More",
      icon: MoreHorizontal,
      match: (pathname) =>
        [v2MorePath(), v2TeamsPath(), v2FavoritesPath(), v2TablesPath(), v2SettingsPath()].some(
          (href) => matchesHref(pathname, href)
        ),
    },
  ];
}

export function buildV2DesktopNav(): V2NavItem[] {
  const home = v2HomePath();
  return [
    {
      href: home,
      label: "Home",
      icon: LayoutGrid,
      match: (pathname) => pathname === "/" || pathname === "/next" || pathname === "/next/",
    },
    {
      href: v2SearchPath(),
      label: "Discover",
      icon: Compass,
      match: (pathname) => matchesHref(pathname, v2SearchPath()),
    },
    {
      href: v2SchedulePath(),
      label: "Schedule",
      icon: CalendarDays,
      match: (pathname) => matchesHref(pathname, v2SchedulePath()),
    },
    {
      href: v2TablesPath(),
      label: "Tables",
      icon: Table2,
      match: (pathname) => matchesHref(pathname, v2TablesPath()),
    },
    {
      href: v2TeamsPath(),
      label: "My teams",
      icon: Users,
      match: (pathname) => matchesHref(pathname, v2TeamsPath()),
    },
    {
      href: v2FavoritesPath(),
      label: "Saved",
      icon: Bookmark,
      match: (pathname) => matchesHref(pathname, v2FavoritesPath()),
    },
  ];
}

export function buildV2MoreLinks() {
  return [
    { href: v2TeamsPath(), label: "Your teams", subtitle: "Track clubs and alerts", icon: Users },
    { href: v2SchedulePath(), label: "Schedule", subtitle: "Fixtures by day", icon: CalendarDays },
    { href: v2FavoritesPath(), label: "Saved", subtitle: "Reminders and bookmarks", icon: Bookmark },
    { href: v2TablesPath(), label: "League tables", subtitle: "Standings by competition", icon: Table2 },
    { href: v2SettingsPath(), label: "Settings", subtitle: "Preferences & display", icon: Settings },
  ];
}
