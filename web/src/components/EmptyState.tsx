"use client";

import React from "react";
import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

interface EmptyStateProps {
  icon: LucideIcon;
  title: string;
  message: string;
  actionLabel?: string;
  onAction?: () => void;
  className?: string;
}

export function EmptyState({ icon: Icon, title, message, actionLabel, onAction, className }: EmptyStateProps) {
  return (
    <div className={cn("flex flex-col items-center justify-center gap-4 px-md py-16 text-center", className)}>
      <div className="flex h-20 w-20 items-center justify-center rounded-full bg-surface text-text-tertiary">
        <Icon size={32} />
      </div>
      <div className="space-y-2">
        <h2 className="text-lg font-semibold text-text-primary">{title}</h2>
        <p className="mx-auto max-w-[320px] text-sm text-text-secondary">{message}</p>
      </div>
      {actionLabel && onAction && (
        <button
          onClick={onAction}
          className="rounded-full accent-gradient px-7 py-3 text-sm font-bold text-white transition-transform active:scale-95"
        >
          {actionLabel}
        </button>
      )}
    </div>
  );
}
