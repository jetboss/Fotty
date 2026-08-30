"use client";

import React, { useState } from "react";
import { isFlagEmoji, teamFlagDisplay } from "@/lib/v2/team-flags";

function initials(name: string) {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length >= 2) return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  return name.slice(0, 2).toUpperCase();
}

function colors(name: string) {
  let hash = 0;
  for (const char of name) hash = (hash * 31 + char.charCodeAt(0)) % 360;
  return {
    from: `hsl(${hash} 58% 36%)`,
    to: `hsl(${(hash + 40) % 360} 68% 26%)`,
  };
}

export function TeamBadge({ name, badge, size = 40 }: { name: string; badge?: string; size?: number }) {
  const gradient = colors(name);
  const display = teamFlagDisplay(name, badge);
  const src = display.imageSrc;
  const [hasError, setHasError] = useState(false);

  const canShowImage = Boolean(src && !hasError);
  const showBadgeText = Boolean(!canShowImage && (display.emoji || badge));
  const badgeText = display.emoji || (badge && badge.length <= 4 && !isFlagEmoji(badge) ? badge : initials(name));
  const emojiBadge = isFlagEmoji(badgeText);

  return (
    <div
      className="grid shrink-0 place-items-center overflow-hidden rounded-full border border-white/10 text-white shadow-inner select-none"
      style={{
        width: size,
        height: size,
        background: `linear-gradient(135deg, ${gradient.from}, ${gradient.to})`,
      }}
      aria-label={`Team badge for ${name}`}
    >
      {canShowImage ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={src!}
          alt={name}
          width={Math.round(size * 0.76)}
          height={Math.round(size * 0.76)}
          loading="lazy"
          referrerPolicy="no-referrer"
          className="h-[76%] w-[76%] object-contain"
          onError={() => setHasError(true)}
        />
      ) : (
        <span
          className={emojiBadge ? "leading-none" : "text-[11px] font-black tracking-tight text-white/90"}
          style={emojiBadge ? { fontSize: Math.round(size * 0.62) } : undefined}
        >
          {showBadgeText ? badgeText : initials(name)}
        </span>
      )}
    </div>
  );
}
