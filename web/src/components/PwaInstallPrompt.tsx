"use client";

import { useState, useSyncExternalStore } from "react";
import { Download, Share, Smartphone, X } from "lucide-react";
import {
  canShowAddToHomeScreenHint,
  dismissPwaInstallHint,
  isPwaInstallDismissed,
} from "@/lib/pwa";
import { useInstallState } from "@/lib/user-experience";
import { cn } from "@/lib/utils";

const subscribeToStaticBrowserState = () => () => {};

function useBrowserSnapshot(getSnapshot: () => boolean) {
  return useSyncExternalStore(subscribeToStaticBrowserState, getSnapshot, () => false);
}

export function PwaInstallBanner({ className }: { className?: string }) {
  const { canPromptInstall, promptInstall, isInstalled } = useInstallState();
  const canShowIosHint = useBrowserSnapshot(canShowAddToHomeScreenHint);
  const persistedDismissal = useBrowserSnapshot(isPwaInstallDismissed);
  const [dismissedLocally, setDismissedLocally] = useState(false);
  const dismissed = persistedDismissal || dismissedLocally;
  const iosHintVisible = canShowIosHint && !dismissed;

  const dismiss = () => {
    dismissPwaInstallHint();
    setDismissedLocally(true);
  };

  // Android / desktop Chrome: native install prompt is available.
  if (canPromptInstall && !isInstalled && !dismissed) {
    return (
      <aside
        className={cn("rounded-xl border border-accent/25 bg-accent/10 p-4", className)}
        aria-label="Install Fotty as an app"
      >
        <div className="flex items-center gap-3">
          <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-accent/15 text-accent">
            <Download size={18} />
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-sm font-bold text-white">Install the Fotty app</p>
            <p className="text-xs font-medium text-text-secondary">
              Fullscreen, faster launch, and home-screen access.
            </p>
          </div>
          <div className="flex shrink-0 items-center gap-1">
            <button
              type="button"
              onClick={() => void promptInstall()}
              className="rounded-full bg-accent px-4 py-2 text-xs font-bold text-white transition-opacity hover:opacity-90"
            >
              Install
            </button>
            <button
              type="button"
              onClick={dismiss}
              className="rounded-full p-1.5 text-text-tertiary hover:bg-white/10 hover:text-white"
              aria-label="Dismiss"
            >
              <X size={16} />
            </button>
          </div>
        </div>
      </aside>
    );
  }

  if (!iosHintVisible) return null;

  return (
    <aside
      className={cn("rounded-xl border border-accent/25 bg-accent/10 p-4", className)}
      aria-label="Install Fotty on your iPhone"
    >
      <div className="flex gap-3">
        <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-accent/15 text-accent">
          <Smartphone size={18} />
        </div>
        <div className="min-w-0 flex-1 space-y-2">
          <div className="flex items-start justify-between gap-2">
            <p className="text-sm font-bold text-white">Add Fotty to your Home Screen</p>
            <button
              type="button"
              onClick={dismiss}
              className="shrink-0 rounded-full p-1 text-text-tertiary hover:bg-white/10 hover:text-white"
              aria-label="Dismiss"
            >
              <X size={16} />
            </button>
          </div>
          <ol className="space-y-1.5 text-xs font-medium leading-5 text-text-secondary">
            <li className="flex gap-2">
              <span className="font-black text-accent">1.</span>
              Tap <Share size={12} className="inline align-text-bottom" /> Share in Safari (bottom bar).
            </li>
            <li className="flex gap-2">
              <span className="font-black text-accent">2.</span>
              Scroll and tap <strong className="text-text-primary">Add to Home Screen</strong>.
            </li>
            <li className="flex gap-2">
              <span className="font-black text-accent">3.</span>
              Tap <strong className="text-text-primary">Add</strong> — opens fullscreen like an app.
            </li>
          </ol>
        </div>
      </div>
    </aside>
  );
}
