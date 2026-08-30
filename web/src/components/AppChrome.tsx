"use client";

import React from "react";
import { usePathname } from "next/navigation";
import { BottomNav } from "@/components/BottomNav";
import { PwaInstallBanner } from "@/components/PwaInstallPrompt";

export function AppChrome({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const hideNavigation = pathname.startsWith("/watch") || pathname.startsWith("/demo");
  const showInstallBanner = !hideNavigation && ["/welcome", "/settings", "/help"].some((route) => pathname.startsWith(route));

  return (
    <>
      {showInstallBanner && (
        <div className="pointer-events-none fixed inset-x-0 top-14 z-40 px-3 sm:top-16 lg:left-[104px] lg:pl-0">
          <div className="pointer-events-auto mx-auto max-w-lg">
            <PwaInstallBanner />
          </div>
        </div>
      )}
      <div className={hideNavigation ? "" : "fotty-mobile-main lg:pl-[104px]"}>{children}</div>
      {!hideNavigation && <BottomNav />}
    </>
  );
}
