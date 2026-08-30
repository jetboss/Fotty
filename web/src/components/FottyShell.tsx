"use client";

import type { ReactNode } from "react";
import { Suspense } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import { isV2ShellPath } from "@/lib/v2/shell-routes";
import { isV2Enabled } from "@/lib/v2/preview";
import { isV2WatchReturn } from "@/lib/v2/watch-context";
import { AppChrome } from "@/components/AppChrome";
import { FottyErrorBoundary } from "@/components/FottyErrorBoundary";
import { TopBar } from "@/components/TopBar";
import { V2ShellChrome } from "@/components/v2/V2Shell";

function isBareAuthPath(pathname: string) {
  return pathname === "/login" || pathname.startsWith("/login/");
}

function WatchShellInner({ children }: { children: ReactNode }) {
  const searchParams = useSearchParams();
  const returnTo = searchParams.get("returnTo");
  
  const isV2 = isV2Enabled();
  const isPreview = isV2 || Boolean(returnTo && isV2WatchReturn(returnTo));

  if (isPreview) {
    return <>{children}</>;
  }

  return (
    <FottyErrorBoundary>
      <TopBar />
      <AppChrome>{children}</AppChrome>
    </FottyErrorBoundary>
  );
}

function FottyShellInner({ bare, children }: { bare: boolean; children: ReactNode }) {
  const pathname = usePathname();

  if (bare || isBareAuthPath(pathname)) {
    return <>{children}</>;
  }

  if (pathname.startsWith("/watch/")) {
    return (
      <Suspense fallback={<>{children}</>}>
        <WatchShellInner>{children}</WatchShellInner>
      </Suspense>
    );
  }

  if (isV2ShellPath(pathname)) {
    return (
      <FottyErrorBoundary>
        <div data-shell="v2" className="fotty-shell-v2">
          <V2ShellChrome>{children}</V2ShellChrome>
        </div>
      </FottyErrorBoundary>
    );
  }

  return (
    <FottyErrorBoundary>
      <TopBar />
      <AppChrome>{children}</AppChrome>
    </FottyErrorBoundary>
  );
}

export function FottyShell({ bare, children }: { bare: boolean; children: ReactNode }) {
  return (
    <Suspense fallback={<>{children}</>}>
      <FottyShellInner bare={bare}>{children}</FottyShellInner>
    </Suspense>
  );
}
