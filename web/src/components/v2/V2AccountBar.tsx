"use client";

import Link from "next/link";
import { Heart } from "lucide-react";
import { v2FavoritesPath } from "@/lib/v2/preview";
import { cn } from "@/lib/utils";

export function V2AccountBar({ className }: { className?: string }) {
  return (
    <div className={cn("flex shrink-0 items-center gap-1.5", className)}>
      <Link
        href={v2FavoritesPath()}
        prefetch
        className="inline-flex h-9 w-9 items-center justify-center rounded-full text-zinc-300 transition hover:bg-white/10 hover:text-white"
        aria-label="Saved"
      >
        <Heart size={17} />
      </Link>
    </div>
  );
}
