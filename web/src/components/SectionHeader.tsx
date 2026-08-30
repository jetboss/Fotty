"use client";

import React from "react";
import { ChevronRight } from "lucide-react";

interface SectionHeaderProps {
  title: string;
  subtitle?: string;
  onSeeAll?: () => void;
}

export function SectionHeader({ title, subtitle, onSeeAll }: SectionHeaderProps) {
  return (
    <div className="flex items-end justify-between gap-4 px-md">
      <div className="min-w-0 space-y-1">
        <h3 className="truncate text-lg font-bold text-text-primary">{title}</h3>
        {subtitle && <p className="truncate text-xs font-medium text-text-tertiary">{subtitle}</p>}
      </div>
      {onSeeAll && (
        <button
          onClick={onSeeAll}
          aria-label={`See all ${title}`}
          className="flex shrink-0 items-center gap-1 text-xs font-bold text-accent transition-opacity hover:opacity-80"
        >
          See All <ChevronRight size={14} />
        </button>
      )}
    </div>
  );
}
