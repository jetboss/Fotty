"use client";

import React from "react";
import Link from "next/link";
import { ChevronRight, Search } from "lucide-react";

export function HomeSearchCard() {
  return (
    <Link
      href="/search"
      className="mx-md flex items-center justify-between rounded-xl border border-white/5 bg-surface px-4 py-3 transition-colors hover:bg-surface-elevated"
    >
      <div className="flex items-center gap-4">
        <Search size={18} className="text-text-tertiary" />
        <div className="flex flex-col">
          <span className="text-sm font-semibold text-text-primary">Search Fotty</span>
          <span className="text-xs text-text-secondary">Teams, leagues, and live channels</span>
        </div>
      </div>
      <ChevronRight size={14} className="text-text-tertiary" />
    </Link>
  );
}
