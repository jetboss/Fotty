"use client";

import React from "react";
import Link from "next/link";
import Image from "next/image";
import { Star, Trophy } from "lucide-react";
import type { MediaItem } from "@/lib/api";
import { isOptimizedImageSrc } from "@/lib/image-hosts";
import { cn } from "@/lib/utils";

interface MediaCardProps {
  item?: MediaItem;
  title?: string;
  poster?: string;
  rating?: number;
  type?: string;
  href?: string;
  className?: string;
}

function kindLabel(item?: MediaItem, type?: string): string {
  if (type) return type;
  if (!item) return "Fotty";
  if (item.meta) return item.meta;
  const k = String(item.type).toLowerCase();
  if (k === "fixture") return "Match";
  if (k === "channel") return "Channel";
  if (k === "session") return "Session";
  return "Saved";
}

export function MediaCard({ item, title, poster, rating, type, href, className }: MediaCardProps) {
  const displayTitle = item?.title || title || "Untitled";
  const displayPoster = item?.poster || poster;
  const displayRating = item?.rating ?? rating;
  const displayType = kindLabel(item, type);
  const target = href || item?.href;

  const card = (
    <div className={cn("group flex w-36 shrink-0 cursor-pointer flex-col gap-2 transition-transform active:scale-95", className)}>
      <div className="relative aspect-[2/3] overflow-hidden rounded-lg border border-white/5 bg-white/5 shadow-lg">
        {displayPoster ? (
          <Image
            src={displayPoster}
            alt={displayTitle}
            fill
            sizes="144px"
            unoptimized={!isOptimizedImageSrc(displayPoster)}
            className="object-cover transition-transform duration-500 group-hover:scale-105"
          />
        ) : (
          <div className="grid h-full w-full place-items-center bg-surface text-text-tertiary">
            <Trophy size={30} />
          </div>
        )}

        {typeof displayRating === "number" && displayRating > 0 && (
          <div className="absolute right-2 top-2 flex items-center gap-1 rounded bg-black/55 px-1.5 py-1 text-[10px] font-bold text-live backdrop-blur">
            <Star size={9} className="fill-current" />
            {displayRating.toFixed(1)}
          </div>
        )}
      </div>

      <div className="space-y-0.5">
        <h4 className="truncate text-xs font-bold text-text-primary">{displayTitle}</h4>
        <p className="truncate text-[10px] font-semibold text-text-tertiary">{displayType}</p>
      </div>
    </div>
  );

  return target ? <Link href={target}>{card}</Link> : card;
}
