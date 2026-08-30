"use client";

import { useEffect, useState } from "react";
import { Download, Share, Smartphone, X } from "lucide-react";
import {
  canShowAddToHomeScreenHint,
  dismissPwaInstallHint,
  isIosDevice,
  isPwaInstallDismissed,
  isStandaloneDisplayMode,
} from "@/lib/pwa";
import { useInstallState } from "@/lib/user-experience";
import { cn } from "@/lib/utils";

export function PwaInstallBanner({ className }: { className?: string }) {
  const { canPromptInstall, promptInstall, isInstalled } = useInstallState();
  const [iosHintVisible, setIosHintVisible] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    setIosHintVisible(canShowAddToHomeScreenHint() && !isPwaInstallDismissed());
    setDismissed(isPwaInstallDismissed());
  }, []);

  const dismiss = () => {
    dismissPwaInstallHint();
    setIosHintVisible(false);
    setDismissed(true);
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

export function PwaInstallSettingsCard() {
  const { canPromptInstall, promptInstall } = useInstallState();
  const [standalone, setStandalone] = useState(false);
  const [ios, setIos] = useState(false);

  useEffect(() => {
    setStandalone(isStandaloneDisplayMode());
    setIos(canShowAddToHomeScreenHint() || isIosDevice());
  }, []);

  if (standalone) {
    return (
      <p className="px-4 py-3 text-xs font-medium leading-5 text-success">
        Fotty is installed on your Home Screen. You&apos;re using the app-style version.
      </p>
    );
  }

  if (!ios) {
    if (canPromptInstall) {
      return (
        <div className="flex items-center justify-between gap-3 px-4 py-3">
          <p className="text-xs font-medium leading-5 text-text-secondary">
            Install Fotty as an app for fullscreen and faster launch.
          </p>
          <button
            type="button"
            onClick={() => void promptInstall()}
            className="inline-flex shrink-0 items-center gap-1.5 rounded-full bg-accent px-4 py-2 text-xs font-bold text-white transition-opacity hover:opacity-90"
          >
            <Download size={13} />
            Install app
          </button>
        </div>
      );
    }
    return (
      <p className="px-4 py-3 text-xs font-medium leading-5 text-text-tertiary">
        On Android or desktop Chrome, use the browser menu to install Fotty as an app when offered.
      </p>
    );
  }

  return <PwaInstallBanner className="m-4" />;
}
