"use client";

import React from 'react';

interface MatchHeaderOverlayProps {
  home: { name: string; badge: string };
  away: { name: string; badge: string };
  isLive?: boolean;
}

export function MatchHeaderOverlay({ home, away, isLive = true }: MatchHeaderOverlayProps) {
  const shortCode = (name: string) => name.substring(0, 3).toUpperCase();
  
  return (
    <div className="flex items-center gap-2 rounded-full border border-white/10 bg-black/55 px-4 py-2 backdrop-blur-md">
      <div className="flex items-center">
        <span className="text-xs font-black text-white">{shortCode(home.name)}</span>
      </div>

      {isLive ? (
        <div className="flex items-center gap-1">
          <div className="h-1.5 w-1.5 animate-live-pulse rounded-full bg-live shadow-[0_0_8px_rgba(255,179,38,0.8)]" />
        </div>
      ) : null}

      <span className="text-[10px] font-black text-white/35">v</span>

      <div className="flex items-center">
        <span className="text-xs font-black text-white">{shortCode(away.name)}</span>
      </div>
    </div>
  );
}
