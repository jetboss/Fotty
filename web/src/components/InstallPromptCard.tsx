"use client";

import React, { useMemo } from "react";
import Link from "next/link";
import { Download, MonitorSmartphone, Share2, X } from "lucide-react";
import { updateUserPreferences } from "@/lib/storage";
import { useInstallState, useUserPreferences } from "@/lib/user-experience";

interface InstallPromptCardProps {
  variant?: "home" | "settings";
}

export function InstallPromptCard({ variant = "home" }: InstallPromptCardProps) {
  const { preferences } = useUserPreferences();
  const { isIOS, isInstalled, canPromptInstall, promptInstall, isMobile } = useInstallState();

  const copy = useMemo(() => {
    if (isInstalled) {
      return {
        title: "Installed and ready",
        body: "Fotty will open like an app from your Home Screen or app launcher.",
        action: null as React.ReactNode,
      };
    }

    if (isIOS) {
      return {
        title: "Add Fotty to your Home Screen",
        body: "Open the Share menu in Safari, then choose Add to Home Screen for the fastest return to Live.",
        action: (
          <Link
            href="/help#install"
            className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-2 text-xs font-bold text-text-primary"
          >
            <Share2 size={14} />
            Show steps
          </Link>
        ),
      };
    }

    if (canPromptInstall) {
      return {
        title: "Install Fotty",
        body: "Install Fotty for a cleaner fullscreen launch and quicker jump back into matches.",
        action: (
          <button
            type="button"
            onClick={() => void promptInstall()}
            className="inline-flex items-center gap-2 rounded-full accent-gradient px-4 py-2 text-xs font-bold text-white"
          >
            <Download size={14} />
            Install now
          </button>
        ),
      };
    }

    return {
      title: isMobile ? "Install from your browser menu" : "Pin Fotty for faster access",
      body: isMobile
        ? "Use your browser menu to add Fotty to your Home Screen when install is available on this device."
        : "Use your browser install or app menu to pin Fotty for quicker match-day launch.",
      action: (
        <Link
          href="/help#install"
          className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-2 text-xs font-bold text-text-primary"
        >
          <MonitorSmartphone size={14} />
          Install help
        </Link>
      ),
    };
  }, [canPromptInstall, isIOS, isInstalled, isMobile, promptInstall]);

  if (variant === "home" && (isInstalled || preferences.installCtaDismissed)) {
    return null;
  }

  const sectionClass =
    variant === "home"
      ? "mx-md rounded-xl border border-white/5 bg-surface p-5 lg:mx-auto lg:max-w-5xl lg:p-6"
      : "rounded-xl border border-white/5 bg-surface p-4";

  return (
    <section className={sectionClass}>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex min-w-0 flex-1 gap-4">
          <div className="mt-0.5 inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-white/5 text-accent">
            <Download size={18} />
          </div>

          <div className="min-w-0 flex-1 space-y-3">
            <div className="space-y-1">
              <p className="text-sm font-bold text-text-primary sm:text-base">{copy.title}</p>
              <p className="max-w-2xl text-sm font-medium leading-6 text-text-secondary">{copy.body}</p>
            </div>
            {copy.action && <div className="flex flex-wrap gap-2">{copy.action}</div>}
          </div>
        </div>

        {variant === "home" && (
          <button
            type="button"
            aria-label="Dismiss install prompt"
            onClick={() => updateUserPreferences({ installCtaDismissed: true })}
            className="grid h-9 w-9 shrink-0 place-items-center self-end rounded-full bg-white/5 text-text-secondary sm:self-start"
          >
            <X size={16} />
          </button>
        )}
      </div>
    </section>
  );
}
