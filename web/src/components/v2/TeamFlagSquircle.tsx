"use client";

import { useState } from "react";
import { teamFlagDisplay } from "@/lib/v2/team-flags";
import { resolveTeamColor } from "@/lib/v2/team-colors";
import { cn } from "@/lib/utils";

interface TeamFlagSquircleProps {
  name: string;
  badge?: string;
  size?: number;
  className?: string;
  radiusClass?: string;
  borderWidth?: number;
}

export function TeamFlagSquircle({
  name,
  badge,
  size = 100,
  className,
  radiusClass = "rounded-[20px]",
  borderWidth = 2.5,
}: TeamFlagSquircleProps) {
  const color = resolveTeamColor(name) ?? "#3f3f46";
  const [hasError, setHasError] = useState(false);
  const display = teamFlagDisplay(name, badge);
  const showImage = Boolean(display.imageSrc && !hasError);

  return (
    <div
      className={cn("shrink-0 overflow-hidden border-white/15", radiusClass, className)}
      style={{
        width: size,
        height: size,
        borderWidth,
        borderStyle: "solid",
        boxShadow: color ? `0 0 18px -8px ${color}66` : undefined,
        background: "#0a0a0d",
      }}
    >
      {showImage ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={display.imageSrc}
          alt={name}
          referrerPolicy="no-referrer"
          loading="lazy"
          onError={() => setHasError(true)}
          style={{ display: "block", width: "100%", height: "100%", objectFit: "cover" }}
        />
      ) : (
        <div
          className="flex h-full w-full items-center justify-center"
          style={{
            background: display.emoji
              ? "#0a0a0d"
              : `linear-gradient(135deg, ${color}44, #09090b)`,
          }}
        >
          <span
            className={cn(
              "font-black leading-none",
              display.emoji ? "select-none" : "tracking-wide text-white"
            )}
            style={{
              fontSize: display.emoji ? Math.round(size * 0.68) : Math.round(size * 0.24),
            }}
          >
            {display.emoji ?? display.initials}
          </span>
        </div>
      )}
    </div>
  );
}
