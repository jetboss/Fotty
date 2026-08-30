"use client";

import type { ReactNode } from "react";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { AmbientGlow } from "@/components/v2/AmbientGlow";
import { cn } from "@/lib/utils";

/** Card / panel surface — matches PosterCard chrome. */
export const v2SurfaceClass =
  "rounded-2xl border border-white/[0.08] bg-[#0d0d10] ring-1 ring-white/[0.04]";

/** Lighter inset panel for forms and settings lists. */
export const v2PanelClass = "rounded-2xl bg-white/[0.02] ring-1 ring-white/[0.06]";

export const v2ListRowClass =
  "rounded-2xl border border-white/[0.08] bg-[#0d0d10] px-3 py-3 transition hover:border-white/12 hover:bg-[#111114]";

interface V2PageShellProps {
  children: ReactNode;
  className?: string;
  /** Applied to the inner content wrapper (padding / max-width). */
  innerClassName?: string;
  glowHome?: string;
  glowAway?: string;
  /** Skip default max-width padding — use for full-bleed rails (Discover, Home). */
  fullBleed?: boolean;
}

export function V2PageShell({
  children,
  className,
  innerClassName,
  glowHome,
  glowAway,
  fullBleed = false,
}: V2PageShellProps) {
  return (
    <main
      className={cn(
        "relative min-h-dvh overflow-x-clip bg-[var(--v2-background)] text-text-primary",
        className
      )}
    >
      <AmbientGlow home={glowHome} away={glowAway} />
      <div className="pointer-events-none absolute inset-0 z-0 stadium-lights mix-blend-screen" />
      {fullBleed ? (
        <div className={cn("relative z-10", innerClassName)}>{children}</div>
      ) : (
        <div
          className={cn(
            "relative z-10 mx-auto max-w-[1440px] space-y-10 px-4 pb-10 pt-6 lg:px-8",
            innerClassName
          )}
        >
          {children}
        </div>
      )}
    </main>
  );
}

interface V2PageHeaderProps {
  title: string;
  subtitle?: string;
  action?: ReactNode;
  className?: string;
}

export function V2PageHeader({ title, subtitle, action, className }: V2PageHeaderProps) {
  return (
    <header className={cn("flex flex-wrap items-end justify-between gap-4", className)}>
      <div className="min-w-0 space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight text-white sm:text-[1.75rem]">{title}</h1>
        {subtitle ? <p className="max-w-2xl text-sm text-text-tertiary">{subtitle}</p> : null}
      </div>
      {action ? <div className="shrink-0">{action}</div> : null}
    </header>
  );
}

interface V2SectionProps {
  title: string;
  subtitle?: string;
  href?: string;
  actionLabel?: string;
  children: ReactNode;
  className?: string;
}

/** Vertical section header — same typography as HorizontalRail. */
export function V2Section({ title, subtitle, href, actionLabel, children, className }: V2SectionProps) {
  return (
    <section className={cn("space-y-3", className)}>
      <div className="flex items-end justify-between gap-3">
        <div className="min-w-0">
          <h2 className="text-lg font-semibold tracking-tight text-white">{title}</h2>
          {subtitle ? <p className="mt-0.5 text-sm text-text-tertiary">{subtitle}</p> : null}
        </div>
        {href ? (
          <Link
            href={href}
            className="inline-flex shrink-0 items-center gap-0.5 text-sm font-medium text-text-secondary transition-colors hover:text-white"
          >
            {actionLabel || "See all"}
            <ChevronRight size={16} />
          </Link>
        ) : null}
      </div>
      {children}
    </section>
  );
}
