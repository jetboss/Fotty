"use client";

import { AlertTriangle, RotateCcw } from "lucide-react";
import { ShimmerBlock } from "@/components/Skeleton";

/** Generic route-level loading skeleton shown by App Router `loading.tsx` files. */
export function RouteLoading({ hero = false }: { hero?: boolean }) {
  return (
    <div className="min-h-dvh bg-background">
      <div className="mx-auto max-w-5xl space-y-6 px-md py-6">
        {hero ? (
          <ShimmerBlock className="h-64 w-full rounded-2xl sm:h-80" />
        ) : (
          <div className="space-y-2">
            <ShimmerBlock className="h-4 w-28" />
            <ShimmerBlock className="h-8 w-64" />
            <ShimmerBlock className="h-4 w-80 max-w-full" />
          </div>
        )}
        <ShimmerBlock className="h-14 w-full rounded-xl" />
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {[0, 1, 2, 3, 4, 5].map((item) => (
            <ShimmerBlock key={item} className="h-24 w-full rounded-xl" />
          ))}
        </div>
      </div>
    </div>
  );
}

/** Shared error view rendered by App Router `error.tsx` boundaries. */
export function RouteErrorView({
  title = "Something went wrong",
  message = "The page hit an unexpected error. Your data is safe — try loading it again.",
  reset,
  secondaryAction,
}: {
  title?: string;
  message?: string;
  reset: () => void;
  secondaryAction?: {
    label: string;
    onClick: () => void;
  };
}) {
  return (
    <div className="flex min-h-dvh items-center justify-center bg-background px-md">
      <div className="w-full max-w-sm rounded-2xl border border-white/10 bg-surface p-6 text-center">
        <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-accent/10 text-accent">
          <AlertTriangle size={22} />
        </div>
        <h2 className="mt-4 text-lg font-black text-white">{title}</h2>
        <p className="mt-1 text-sm font-medium text-text-secondary">
          {message}
        </p>
        <div className="mt-5 flex flex-wrap justify-center gap-2">
          <button
            type="button"
            onClick={reset}
            className="inline-flex min-h-10 items-center gap-2 rounded-full bg-accent px-5 text-sm font-bold text-white transition-opacity hover:opacity-90"
          >
            <RotateCcw size={15} />
            Try again
          </button>
          {secondaryAction ? (
            <button
              type="button"
              onClick={secondaryAction.onClick}
              className="inline-flex min-h-10 items-center gap-2 rounded-full border border-white/10 bg-background px-5 text-sm font-bold text-text-primary transition-colors hover:bg-surface-elevated"
            >
              {secondaryAction.label}
            </button>
          ) : null}
        </div>
      </div>
    </div>
  );
}
