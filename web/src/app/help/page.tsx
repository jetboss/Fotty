"use client";

import Link from "next/link";
import { ArrowLeft, Bell, Download, LifeBuoy, Shield } from "lucide-react";
import { useInstallState } from "@/lib/user-experience";

export default function HelpPage() {
  const { isIOS, isInstalled, canPromptInstall, promptInstall } = useInstallState();

  return (
    <main className="min-h-screen bg-background pb-32 pt-12 text-text-primary">
      <header className="space-y-4 px-md">
        <Link
          href="/settings"
          className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-surface text-text-primary"
          aria-label="Back to settings"
        >
          <ArrowLeft size={18} />
        </Link>

        <div className="space-y-2">
          <h1 className="text-4xl font-black">Help Center</h1>
          <p className="max-w-2xl text-sm font-medium leading-6 text-text-secondary">
            Install Fotty cleanly, understand what stays on this device, and get unstuck faster when a match needs a second try.
          </p>
        </div>
      </header>

      <div className="space-y-4 px-md py-lg">
        <section id="install" className="rounded-xl border border-white/5 bg-surface p-4">
          <div className="space-y-3">
            <div className="inline-flex h-11 w-11 items-center justify-center rounded-full bg-white/5 text-accent">
              <Download size={18} />
            </div>
            <div className="space-y-1">
              <h2 className="text-sm font-bold text-text-primary">{isInstalled ? "Fotty is already installed" : "Install Fotty"}</h2>
              <p className="text-xs font-medium leading-6 text-text-secondary">
                {isInstalled
                  ? "Open Fotty from your Home Screen or launcher for the cleanest full-screen experience."
                  : isIOS
                    ? "On iPhone or iPad, open Safari’s Share menu and choose Add to Home Screen."
                    : "Use your browser install or app menu to pin Fotty for faster launch."}
              </p>
            </div>
            {!isInstalled && canPromptInstall && (
              <button
                type="button"
                onClick={() => void promptInstall()}
                className="inline-flex items-center gap-2 rounded-full accent-gradient px-4 py-2 text-xs font-bold text-white"
              >
                <Download size={14} />
                Install now
              </button>
            )}
          </div>
        </section>

        <section className="rounded-xl border border-white/5 bg-surface p-4">
          <div className="space-y-3">
            <div className="inline-flex h-11 w-11 items-center justify-center rounded-full bg-white/5 text-accent">
              <Bell size={18} />
            </div>
            <div className="space-y-1">
              <h2 className="text-sm font-bold text-text-primary">How reminders work</h2>
              <p className="text-xs font-medium leading-6 text-text-secondary">
                Match reminders stay on this device. Save an upcoming fixture from Home, Live, or Watch, then open Saved to jump back in or add it to your calendar.
              </p>
            </div>
          </div>
        </section>

        <section className="rounded-xl border border-white/5 bg-surface p-4">
          <div className="space-y-3">
            <div className="inline-flex h-11 w-11 items-center justify-center rounded-full bg-white/5 text-accent">
              <LifeBuoy size={18} />
            </div>
            <div className="space-y-1">
              <h2 className="text-sm font-bold text-text-primary">Playback troubleshooting</h2>
              <p className="text-xs font-medium leading-6 text-text-secondary">
                If a stream feels slow, return to the Live board and try another listed source. Fotty does not probe or promise provider availability in the background.
              </p>
            </div>
          </div>
        </section>

        <section className="rounded-xl border border-white/5 bg-surface p-4">
          <div className="space-y-3">
            <div className="inline-flex h-11 w-11 items-center justify-center rounded-full bg-white/5 text-accent">
              <Shield size={18} />
            </div>
            <div className="space-y-1">
              <h2 className="text-sm font-bold text-text-primary">Privacy and local data</h2>
              <p className="text-xs font-medium leading-6 text-text-secondary">
                Favorites, reminders, and recent sessions are stored locally in this phase. There is no account sync or cloud profile attached to this release.
              </p>
            </div>
          </div>
        </section>

        <div className="flex flex-wrap gap-2">
          <Link href="/feedback" className="inline-flex items-center rounded-full bg-white/5 px-4 py-2 text-xs font-bold text-text-primary">
            Send feedback
          </Link>
          <Link href="/support" className="inline-flex items-center rounded-full border border-white/10 px-4 py-2 text-xs font-bold text-text-secondary">
            Support Fotty
          </Link>
        </div>
      </div>
    </main>
  );
}
