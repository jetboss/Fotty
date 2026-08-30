"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Crown, LogIn, LogOut, Search, Settings } from "lucide-react";
import { cn } from "@/lib/utils";
import { PwaInstallBanner } from "@/components/PwaInstallPrompt";
import { V2AccountBar } from "@/components/v2/V2AccountBar";
import { buildV2DesktopNav, buildV2MobileNav, type V2NavItem } from "@/lib/v2/nav";
import { v2HomePath, v2SearchPath, v2SettingsPath } from "@/lib/v2/preview";
import { useAuth } from "@/components/AuthProvider";
import { useEntitlement } from "@/components/EntitlementProvider";

function sideRailLinkClass(active: boolean) {
  return cn(
    "flex h-10 items-center gap-3 whitespace-nowrap rounded-xl px-3 text-[13px] font-medium transition-colors",
    active
      ? "bg-white/10 text-white shadow-[inset_3px_0_0_0_rgba(255,255,255,0.9)]"
      : "text-text-tertiary hover:bg-white/5 hover:text-white"
  );
}

function bottomNavClass(active: boolean) {
  return cn(
    "flex min-h-[3.25rem] flex-1 flex-col items-center justify-center gap-0.5 rounded-xl px-1 py-2 text-[10px] font-medium transition-colors",
    active ? "bg-white/10 text-white" : "text-text-tertiary"
  );
}

function SideRailLink({ item, pathname }: { item: V2NavItem; pathname: string }) {
  const active = item.match(pathname);
  const Icon = item.icon;
  return (
    <Link href={item.href} className={sideRailLinkClass(active)} aria-current={active ? "page" : undefined}>
      <Icon size={17} className="shrink-0" />
      <span>{item.label}</span>
    </Link>
  );
}

export function V2TopNav() {
  const homeHref = v2HomePath();

  return (
    <header className="sticky top-0 z-40 border-b border-white/[0.06] bg-[var(--v2-background)]/90 px-4 pt-[calc(0.65rem+env(safe-area-inset-top,0px))] backdrop-blur-xl lg:hidden">
      <div className="mx-auto flex h-11 max-w-[1440px] items-center gap-3">
        <Link href={homeHref} className="text-sm font-bold tracking-[0.2em] text-white" aria-label="Fotty home">
          FOTTY
        </Link>
        <div className="ml-auto flex items-center gap-1">
          <Link
            href={v2SearchPath()}
            className="inline-flex h-9 w-9 items-center justify-center rounded-full text-text-secondary transition hover:bg-white/5 hover:text-white"
            aria-label="Search"
          >
            <Search size={18} />
          </Link>
          <V2AccountBar />
        </div>
      </div>
    </header>
  );
}

export function V2SideRail() {
  const pathname = usePathname();
  const homeHref = v2HomePath();
  const desktopNav = buildV2DesktopNav();
  const { session, signOut } = useAuth();
  const entitlement = useEntitlement();
  const settingsItem: V2NavItem = {
    href: v2SettingsPath(),
    label: "Settings",
    icon: Settings,
    match: (path) => path.startsWith(v2SettingsPath()),
  };

  return (
    <aside className="sticky top-0 z-50 hidden h-svh w-52 shrink-0 flex-col border-r border-white/[0.06] bg-[var(--v2-background)] px-3 py-5 lg:flex">
      <div className="mb-6 flex items-center justify-between gap-3 whitespace-nowrap rounded-xl px-2">
        <Link href={homeHref} className="flex items-center gap-2.5 py-1.5 transition hover:opacity-90" aria-label="Fotty home">
          <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-white/10 text-[11px] font-bold text-white">
            F
          </span>
          <span className="text-[13px] font-bold tracking-[0.14em] text-white">FOTTY</span>
        </Link>
      </div>

      <nav className="flex min-h-0 flex-1 flex-col gap-1.5" aria-label="Sidebar">
        {desktopNav.map((item) => (
          <SideRailLink key={item.href} item={item} pathname={pathname} />
        ))}
      </nav>

      <div className="mt-4 border-t border-white/[0.06] pt-4 flex flex-col gap-1.5">
        <SideRailLink item={settingsItem} pathname={pathname} />
      </div>
    </aside>
  );
}

export function V2BottomNav() {
  const pathname = usePathname();
  const mobileNav = buildV2MobileNav();

  return (
    <nav
      className="fixed inset-x-0 bottom-0 z-40 border-t border-white/[0.06] bg-[var(--v2-background)]/95 px-2 pb-[env(safe-area-inset-bottom,0px)] pt-1 backdrop-blur-xl lg:hidden"
      aria-label="Mobile"
    >
      <div className="mx-auto flex max-w-lg items-stretch justify-around gap-0.5">
        {mobileNav.map((item) => {
          const active = item.match(pathname);
          const Icon = item.icon;
          return (
            <Link key={item.href} href={item.href} className={bottomNavClass(active)} aria-current={active ? "page" : undefined}>
              <Icon size={19} />
              <span className="max-w-[4.5rem] truncate">{item.label}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}

function shouldShowPwaBanner(pathname: string) {
  return ["/", "/settings", "/help", "/welcome", "/more"].some(
    (route) => pathname === route || pathname.startsWith(`${route}/`)
  );
}

export function V2ShellChrome({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const showPwa = shouldShowPwaBanner(pathname);

  return (
    <div className="min-h-dvh lg:grid lg:grid-cols-[max-content_minmax(0,1fr)]">
      <V2SideRail />
      <div className="flex min-h-dvh min-w-0 flex-col overflow-x-hidden pb-[calc(4.5rem+env(safe-area-inset-bottom,0px))] lg:pb-0">
        <V2TopNav />
        {showPwa ? (
          <div className="px-4 pt-2 lg:px-6">
            <PwaInstallBanner />
          </div>
        ) : null}
        <div className="min-w-0 flex-1">{children}</div>
        <V2BottomNav />
      </div>
    </div>
  );
}
