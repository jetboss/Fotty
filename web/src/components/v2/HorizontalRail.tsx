"use client";

import type { ReactNode } from "react";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";

interface HorizontalRailProps {
  title: string;
  subtitle?: string;
  href?: string;
  actionLabel?: string;
  children: ReactNode;
  className?: string;
}

export function HorizontalRail({ title, subtitle, href, actionLabel, children, className }: HorizontalRailProps) {
  return (
    <section className={cn("space-y-3", className)}>
      <div className="flex items-end justify-between gap-3 px-4 lg:px-6">
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
      {/* Mobile: swipeable rail. Desktop: fixture grid (same pattern as Schedule). */}
      <div
        className={cn(
          "no-scrollbar flex snap-x snap-mandatory gap-3 overflow-x-auto px-4 pb-1",
          "lg:grid lg:grid-cols-2 lg:gap-4 lg:overflow-visible lg:px-6 lg:snap-none xl:grid-cols-3 2xl:grid-cols-4",
          "[&>*]:shrink-0 [&>*]:snap-start lg:[&>*]:w-full lg:[&>*]:max-w-none lg:[&>*]:shrink lg:[&_article]:w-full"
        )}
      >
        {children}
      </div>
    </section>
  );
}
