"use client";

import React from "react";
import { cn } from "@/lib/utils";

export function ShimmerBlock({ className }: { className?: string }) {
  return <div className={cn("animate-pulse rounded-lg bg-white/[0.07]", className)} />;
}
