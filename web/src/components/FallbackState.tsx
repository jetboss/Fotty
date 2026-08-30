"use client";

import Link from "next/link";
import type { LucideIcon } from "lucide-react";
import {
  AlertTriangle,
  Bell,
  CalendarClock,
  LoaderCircle,
  LogIn,
  Radio,
  RefreshCw,
  Search,
  ShieldCheck,
} from "lucide-react";
import { cn } from "@/lib/utils";

type FallbackKind =
  | "loading"
  | "empty"
  | "error"
  | "updating"
  | "signed-out"
  | "no-stream"
  | "refresh";

type FallbackAction = {
  label: string;
  href?: string;
  onClick?: () => void;
};

interface FallbackStateProps {
  kind?: FallbackKind;
  icon?: LucideIcon;
  title: string;
  message: string;
  primaryAction?: FallbackAction;
  secondaryAction?: FallbackAction;
  compact?: boolean;
  inline?: boolean;
  className?: string;
  variant?: "classic" | "v2";
}

const KIND_ICON: Record<FallbackKind, LucideIcon> = {
  loading: LoaderCircle,
  empty: Search,
  error: AlertTriangle,
  updating: RefreshCw,
  "signed-out": LogIn,
  "no-stream": Radio,
  refresh: RefreshCw,
};

export function FallbackState({
  kind = "empty",
  icon,
  title,
  message,
  primaryAction,
  secondaryAction,
  compact = false,
  inline = false,
  className,
  variant = "classic",
}: FallbackStateProps) {
  const isV2 = variant === "v2";
  const Icon = icon ?? KIND_ICON[kind];
  const spin = kind === "loading" || kind === "refresh";

  return (
    <div
      className={cn(
        "relative overflow-hidden rounded-2xl text-center",
        isV2
          ? "bg-white/[0.02] ring-1 ring-white/[0.06]"
          : "border border-white/10 bg-[linear-gradient(135deg,rgba(255,255,255,0.055),rgba(255,255,255,0.018))] shadow-[0_20px_80px_rgba(0,0,0,0.28)]",
        inline ? "px-4 py-5" : compact ? "px-4 py-6" : "px-5 py-10 sm:px-8",
        className
      )}
    >
      {!isV2 ? (
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(224,31,71,0.14),transparent_42%)] opacity-70" />
      ) : null}
      <div className="relative mx-auto flex max-w-md flex-col items-center">
        <div
          className={cn(
            "grid place-items-center rounded-full border border-white/10 bg-black/25",
            isV2 ? "text-white/70" : "text-accent",
            compact || inline ? "h-11 w-11" : "h-16 w-16"
          )}
        >
          <Icon size={compact || inline ? 20 : 26} className={cn(spin && "animate-spin")} />
        </div>
        <h2
          className={cn(
            "mt-4 text-white",
            isV2 ? "font-semibold tracking-tight" : "font-black",
            compact || inline ? "text-base" : "text-2xl"
          )}
        >
          {title}
        </h2>
        <p className={cn("mt-2 font-medium leading-6 text-text-secondary", compact || inline ? "text-xs" : "text-sm")}>
          {message}
        </p>
        {(primaryAction || secondaryAction) && (
          <div className="mt-5 flex flex-wrap items-center justify-center gap-2">
            {primaryAction ? <FallbackButton action={primaryAction} primary variant={variant} /> : null}
            {secondaryAction ? <FallbackButton action={secondaryAction} variant={variant} /> : null}
          </div>
        )}
      </div>
    </div>
  );
}

function FallbackButton({
  action,
  primary = false,
  variant = "classic",
}: {
  action: FallbackAction;
  primary?: boolean;
  variant?: "classic" | "v2";
}) {
  const isV2 = variant === "v2";
  const className = primary
    ? isV2
      ? "inline-flex min-h-10 items-center justify-center rounded-full bg-white px-5 text-sm font-bold text-black hover:bg-white/90 transition shadow-sm"
      : "inline-flex min-h-10 items-center justify-center rounded-full bg-accent px-4 text-sm font-black text-white shadow-[0_14px_42px_rgba(224,31,71,0.28)]"
    : "inline-flex min-h-10 items-center justify-center rounded-full border border-white/10 bg-white/[0.04] px-4 text-sm font-bold text-text-primary";

  if (action.href) {
    return (
      <Link href={action.href} className={className}>
        {action.label}
      </Link>
    );
  }

  return (
    <button type="button" onClick={action.onClick} className={className}>
      {action.label}
    </button>
  );
}

export function LoadingState(props: Omit<FallbackStateProps, "kind" | "icon">) {
  return <FallbackState kind="loading" {...props} />;
}

export function UpdatingState(props: Omit<FallbackStateProps, "kind" | "icon">) {
  return <FallbackState kind="updating" {...props} />;
}

export function ErrorState(props: Omit<FallbackStateProps, "kind" | "icon">) {
  return <FallbackState kind="error" {...props} />;
}

export function SignedOutState(props: Omit<FallbackStateProps, "kind" | "icon">) {
  return <FallbackState kind="signed-out" {...props} />;
}

export function NoVerifiedStreamState(props: Omit<FallbackStateProps, "kind" | "icon">) {
  return <FallbackState kind="no-stream" {...props} />;
}

export function DataRefreshState(props: Omit<FallbackStateProps, "kind" | "icon">) {
  return <FallbackState kind="refresh" {...props} />;
}

export function FallbackSkeleton({ rows = 4, className }: { rows?: number; className?: string }) {
  return (
    <div className={cn("space-y-3 rounded-2xl border border-white/10 bg-surface p-4", className)}>
      {Array.from({ length: rows }, (_, index) => (
        <div key={index} className="h-12 animate-pulse rounded-xl bg-white/[0.06]" />
      ))}
    </div>
  );
}

export function CompactLoadingPill({ label = "Refreshing data" }: { label?: string }) {
  return (
    <span className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-surface px-3 py-1.5 text-xs font-bold text-text-secondary">
      <LoaderCircle size={13} className="animate-spin text-accent" />
      {label}
    </span>
  );
}

export function NoStreamReminderAction({ onClick }: { onClick?: () => void }) {
  return {
    label: "Set Reminder",
    onClick,
  };
}

export { Bell, CalendarClock, ShieldCheck };
