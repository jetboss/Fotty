"use client";

import React from "react";
import { cn } from "@/lib/utils";

export function ShimmerBlock({ className }: { className?: string }) {
  return <div className={cn("animate-pulse rounded-lg bg-white/[0.07]", className)} />;
}

export function HomeSkeleton() {
  return (
    <div className="min-h-dvh bg-background">
      <ShimmerBlock className="h-[430px] w-full rounded-none" />
      <div className="space-y-8 px-md py-lg">
        <ShimmerBlock className="h-16 w-full" />
        {[0, 1, 2].map((section) => (
          <div key={section} className="space-y-4">
            <ShimmerBlock className="h-8 w-56" />
            <div className="flex gap-md overflow-hidden">
              {[0, 1, 2, 3].map((item) => (
                <div key={item} className="w-36 shrink-0 space-y-2">
                  <ShimmerBlock className="aspect-[2/3] w-full" />
                  <ShimmerBlock className="h-4 w-28" />
                  <ShimmerBlock className="h-3 w-16" />
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
