"use client";

import React from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import type { LucideIcon } from "lucide-react";
import {
  CalendarDays,
  Globe2,
  Heart,
  LayoutGrid,
  MoreHorizontal,
  Settings,
  Trophy,
  Users,
} from "lucide-react";
import { LIVE_BOARD_LABEL, LIVE_BOARD_PATH } from "@/lib/match-day-labels";
import { cn } from "@/lib/utils";

const MORE_PATHS = [
  "/tables",
  "/settings",
  "/support",
  "/collab",
  "/help",
  "/feedback",
  "/welcome",
  "/privacy",
  "/terms",
  "/favorites",
  "/search",
  "/teams",
];

const PRIMARY_NAV = [
  { href: "/", label: "Scores", icon: LayoutGrid, match: (path: string) => path === "/" || path === "" },
  { href: "/search", label: "Discover", icon: Globe2, match: (path: string) => path.startsWith("/search") },
  { href: LIVE_BOARD_PATH, label: LIVE_BOARD_LABEL, icon: CalendarDays, match: (path: string) => path.startsWith(LIVE_BOARD_PATH) },
] as const;

const SECONDARY_NAV = [
  { href: "/tables", label: "Tables", icon: Trophy },
  { href: "/favorites", label: "Saved", icon: Heart },
  { href: "/teams", label: "My Teams", icon: Users },
] as const;

const MORE_MENU = [
  ...SECONDARY_NAV,
  { href: "/settings", label: "Settings", icon: Settings },
] as const;

export function BottomNav() {
  const pathname = usePathname();
  const router = useRouter();
  const [moreOpen, setMoreOpen] = React.useState(false);
  const [lastPathname, setLastPathname] = React.useState(pathname);
  const moreActive = MORE_PATHS.some((path) => pathname.startsWith(path));
  const hideNavigation = pathname.startsWith("/watch");

  // Close the sheet when navigation happens (adjust state during render, no effect needed).
  if (lastPathname !== pathname) {
    setLastPathname(pathname);
    setMoreOpen(false);
  }

  React.useEffect(() => {
    if (!moreOpen) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMoreOpen(false);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [moreOpen]);

  React.useEffect(() => {
    if (hideNavigation) return;
    const routes = [...PRIMARY_NAV.map((item) => item.href), ...MORE_MENU.map((item) => item.href)];
    const warmRoutes = () => {
      routes.forEach((route) => router.prefetch(route));
    };

    const idleWindow = window as Window & {
      requestIdleCallback?: (callback: () => void, options?: { timeout?: number }) => number;
      cancelIdleCallback?: (id: number) => void;
    };

    if (idleWindow.requestIdleCallback) {
      const idleId = idleWindow.requestIdleCallback(warmRoutes, { timeout: 1500 });
      return () => idleWindow.cancelIdleCallback?.(idleId);
    }

    const timeout = window.setTimeout(warmRoutes, 500);
    return () => window.clearTimeout(timeout);
  }, [hideNavigation, router]);

  if (hideNavigation) return null;

  return (
    <>
      <MoreSheet open={moreOpen} onClose={() => setMoreOpen(false)} pathname={pathname} />

      <nav
        aria-label="Primary"
        className="fixed inset-x-0 bottom-0 z-50 px-3 pb-[calc(0.45rem+env(safe-area-inset-bottom,0px))] pt-2 sm:px-4 lg:hidden"
      >
        <div className="rounded-xl border border-white/10 bg-surface/95 py-2 shadow-[0_-12px_40px_rgba(0,0,0,0.35)] backdrop-blur-2xl sm:rounded-2xl sm:py-3">
          <NavRow>
            {PRIMARY_NAV.map((item) => (
              <NavItem
                key={item.href}
                icon={item.icon}
                label={item.label}
                href={item.href}
                active={item.match(pathname)}
              />
            ))}
            <MoreNavButton active={moreActive} open={moreOpen} onToggle={() => setMoreOpen((value) => !value)} />
          </NavRow>
        </div>
      </nav>

      <aside aria-label="Primary" className="fixed left-0 top-0 z-40 hidden h-screen w-[104px] border-r border-white/5 bg-background px-3 pb-4 pt-6 lg:flex lg:flex-col">
        <Link href="/" className="flex h-14 shrink-0 items-center justify-center rounded-2xl border border-white/10 bg-surface text-white">
          <div className="flex flex-col items-center leading-none">
            <span className="text-xs font-black tracking-[0.2em]">FO</span>
            <span className="mt-1 text-[10px] font-bold text-text-secondary">TTY</span>
          </div>
        </Link>

        <div className="no-scrollbar mt-6 flex flex-1 flex-col gap-1.5 overflow-y-auto">
          {PRIMARY_NAV.map((item) => (
            <DesktopNavItem
              key={item.href}
              icon={item.icon}
              label={item.label}
              href={item.href}
              active={item.match(pathname)}
            />
          ))}

          <div className="mx-2 my-2 h-px shrink-0 bg-white/8" aria-hidden />

          {SECONDARY_NAV.map((item) => (
            <DesktopNavItem
              key={item.href}
              icon={item.icon}
              label={item.label}
              href={item.href}
              active={pathname.startsWith(item.href)}
              compact
            />
          ))}
        </div>

        <div className="mt-2 shrink-0 border-t border-white/8 pt-2">
          <DesktopNavItem
            icon={Settings}
            label="Settings"
            href="/settings"
            active={pathname.startsWith("/settings")}
            compact
          />
        </div>
      </aside>
    </>
  );
}

function MoreSheet({ open, onClose, pathname }: { open: boolean; onClose: () => void; pathname: string }) {
  if (!open) return null;

  return (
    <>
      <button
        type="button"
        aria-label="Close menu"
        className="fotty-fade-in fixed inset-0 z-50 bg-black/60 backdrop-blur-sm lg:hidden"
        onClick={onClose}
      />
      <div
        role="menu"
        aria-label="More destinations"
        className={cn(
          "fotty-sheet-in fixed z-50 overflow-hidden rounded-2xl border border-white/10 bg-surface-elevated/95 shadow-[0_24px_80px_rgba(0,0,0,0.6)] backdrop-blur-2xl lg:hidden",
          "inset-x-3 bottom-[calc(6.5rem+env(safe-area-inset-bottom,0px))] sm:inset-x-4"
        )}
      >
        <div className="px-4 pb-1 pt-3 text-[11px] font-bold uppercase tracking-wider text-text-tertiary">
          More
        </div>
        <div className="p-2 pt-0">
          {MORE_MENU.map((item) => {
            const Icon = item.icon;
            const active = pathname.startsWith(item.href);
            return (
              <Link
                key={item.href}
                role="menuitem"
                href={item.href}
                prefetch
                onClick={onClose}
                className={cn(
                  "flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-semibold transition-colors",
                  active ? "bg-accent/10 text-accent" : "text-text-primary hover:bg-white/5"
                )}
              >
                <Icon size={18} strokeWidth={active ? 2.6 : 2} />
                {item.label}
              </Link>
            );
          })}
        </div>
      </div>
    </>
  );
}

function NavRow({ children }: { children: React.ReactNode }) {
  return <div className="flex w-full items-center">{children}</div>;
}

function NavItem({ icon: Icon, label, href, active }: { icon: LucideIcon; label: string; href: string; active: boolean }) {
  const router = useRouter();
  const prefetch = React.useCallback(() => {
    router.prefetch(href);
  }, [href, router]);

  return (
    <Link
      href={href}
      prefetch
      onPointerEnter={prefetch}
      onTouchStart={prefetch}
      className="flex flex-1 min-w-0 touch-manipulation flex-col items-center transition-all duration-300"
    >
      <div
        className={cn(
          "flex h-[54px] min-w-0 flex-col items-center justify-center gap-1 transition-all duration-300",
          active ? "font-black text-accent" : "text-text-tertiary hover:text-text-secondary"
        )}
      >
        <Icon size={active ? 22 : 20} strokeWidth={active ? 3 : 2} />
        <span className="max-w-full truncate px-0.5 text-[10px] font-semibold leading-none">{label}</span>
        {active && <div className="fotty-fade-in mt-0.5 h-1.5 w-1.5 shrink-0 rounded-full bg-accent" />}
      </div>
    </Link>
  );
}

function MoreNavButton({ active, open, onToggle }: { active: boolean; open: boolean; onToggle: () => void }) {
  const highlighted = active || open;
  return (
    <button
      type="button"
      aria-haspopup="menu"
      aria-expanded={open}
      aria-label="More destinations"
      onClick={onToggle}
      className="flex flex-1 min-w-0 touch-manipulation flex-col items-center transition-all duration-300"
    >
      <div
        className={cn(
          "flex h-[54px] min-w-0 flex-col items-center justify-center gap-1 transition-all duration-300",
          highlighted ? "font-black text-accent" : "text-text-tertiary hover:text-text-secondary"
        )}
      >
        <MoreHorizontal size={highlighted ? 22 : 20} strokeWidth={highlighted ? 3 : 2} />
        <span className="max-w-full truncate px-0.5 text-[10px] font-semibold leading-none">More</span>
        {active && !open && (
          <div className="fotty-fade-in mt-0.5 h-1.5 w-1.5 shrink-0 rounded-full bg-accent" />
        )}
      </div>
    </button>
  );
}

function DesktopNavItem({
  icon: Icon,
  label,
  href,
  active,
  compact = false,
}: {
  icon: LucideIcon;
  label: string;
  href: string;
  active: boolean;
  compact?: boolean;
}) {
  const router = useRouter();
  const prefetch = React.useCallback(() => {
    router.prefetch(href);
  }, [href, router]);

  return (
    <Link
      href={href}
      prefetch
      onPointerEnter={prefetch}
      className={cn(
        "flex shrink-0 flex-col items-center rounded-2xl px-2 text-center transition-all duration-200",
        compact ? "gap-1 py-2" : "gap-2 py-3.5",
        active ? "text-text-primary" : "text-text-tertiary hover:bg-surface/70 hover:text-text-primary"
      )}
    >
      <span
        className={cn(
          "flex items-center justify-center rounded-xl transition-all duration-200",
          compact ? "h-8 w-8" : "h-9 w-9",
          active ? "bg-accent text-white shadow-[0_6px_18px_rgba(224,31,71,0.35)]" : ""
        )}
      >
        <Icon size={compact ? 17 : 20} strokeWidth={active ? 2.6 : 2.1} />
      </span>
      <span className={cn("font-semibold", compact ? "text-[10px]" : "text-[11px]")}>{label}</span>
    </Link>
  );
}
