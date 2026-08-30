"use client";

import { AlertTriangle, RefreshCw, WifiOff } from "lucide-react";
import { cn } from "@/lib/utils";

interface FeedStatusBannerProps {
  tone?: "warning" | "error";
  title: string;
  message: string;
  onRetry?: () => void;
  className?: string;
}

export function FeedStatusBanner({ tone = "warning", title, message, onRetry, className }: FeedStatusBannerProps) {
  const Icon = tone === "error" ? WifiOff : AlertTriangle;

  return (
    <div
      className={cn(
        "mx-md rounded-xl border px-4 py-3",
        tone === "error" ? "border-live/25 bg-live/10" : "border-accent/25 bg-accent/10",
        className
      )}
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <BannerCopy icon={Icon} title={title} message={message} tone={tone} />
        {onRetry ? (
          <button
            type="button"
            onClick={onRetry}
            className="inline-flex shrink-0 items-center gap-2 rounded-full border border-white/10 bg-white/5 px-3 py-2 text-xs font-bold text-text-primary"
          >
            <RefreshCw size={13} />
            Retry
          </button>
        ) : null}
      </div>
    </div>
  );
}

function BannerCopy({
  icon: Icon,
  title,
  message,
  tone,
}: {
  icon: typeof AlertTriangle;
  title: string;
  message: string;
  tone: "warning" | "error";
}) {
  return (
    <div className="flex min-w-0 items-start gap-3">
      <div
        className={cn(
          "grid h-9 w-9 shrink-0 place-items-center rounded-full",
          tone === "error" ? "bg-live/15 text-live" : "bg-accent/15 text-accent"
        )}
      >
        <Icon size={16} />
      </div>
      <div className="min-w-0 space-y-1">
        <p className="text-sm font-bold text-text-primary">{title}</p>
        <p className="text-xs font-medium leading-5 text-text-secondary">{message}</p>
      </div>
    </div>
  );
}
