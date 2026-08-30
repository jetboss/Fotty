"use client";

import Link from "next/link";
import { ArrowLeft, LogIn, Lock, Play } from "lucide-react";
import { buildWhatsAppPayUrl } from "@/lib/tt-plans";
import type { WatchAccessReason } from "@/lib/watch-access";
import { clearAuthSession } from "@/lib/auth";
import { v2HomePath } from "@/lib/v2/preview";
import { v2SurfaceClass } from "@/components/v2/V2PageShell";
import { cn } from "@/lib/utils";

const BENEFITS = [
  "Verified streams on Fotty",
  "Backup feeds when available",
  "Match-day stream ranking",
  "Reminders on this device",
] as const;

function gateCopy(reason: WatchAccessReason, title: string) {
  switch (reason) {
    case "sign_in":
      return {
        heading: "Sign in to watch",
        body: `${title} is ready on Fotty. Use the same email and password as the iOS app to start playback, save reminders, and keep your match-day setup in sync.`,
        primaryLabel: "Sign in",
        primaryHref: (returnTo: string) => `/login?next=${encodeURIComponent(returnTo)}`,
      };
    case "refresh":
      return {
        heading: "Refresh your session",
        body: `You are signed in, but this device needs a fresh secure watch session before ${title} can play.`,
        primaryLabel: "Refresh access",
        primaryHref: (returnTo: string) => `/login?refresh=1&next=${encodeURIComponent(returnTo)}`,
      };
    default:
      return {
        heading: "Plus required to watch",
        body: `Live streams and backup feeds are included with Fotty Plus. Get access, then return here for ${title}.`,
        primaryLabel: "View plans",
        primaryHref: () => "/subscribe",
      };
  }
}

export function WatchAccessGate({
  reason,
  title,
  returnTo,
  homeHref = v2HomePath(),
}: {
  reason: WatchAccessReason;
  title: string;
  returnTo: string;
  /** @deprecated Use homeHref — kept for callers that still pass onClose. */
  onClose?: () => void;
  homeHref?: string;
  /** @deprecated Removed with TV Guide; ignored if passed. */
  guideHref?: string;
}) {
  const copy = gateCopy(reason, title);
  const isUpgrade = reason === "upgrade";
  const whatsappHref = buildWhatsAppPayUrl("plus");
  const primaryHref = isUpgrade ? "/subscribe" : copy.primaryHref(returnTo);

  return (
    <main className="relative min-h-dvh overflow-x-clip bg-[var(--v2-background)] text-text-primary">
      <div className="pointer-events-none absolute inset-0 z-0 stadium-lights mix-blend-screen" />
      <div className="relative z-10 mx-auto flex min-h-dvh w-full max-w-[1440px] flex-col px-4 py-[calc(1.5rem+env(safe-area-inset-top,0px))] lg:px-8">
        <div className="flex items-center justify-between gap-3">
          <Link
            href={homeHref}
            className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-3 py-2 text-xs font-semibold text-white/80 transition hover:border-white/15 hover:bg-white/[0.07]"
          >
            <ArrowLeft size={14} />
            Home
          </Link>
        </div>

        <div className="flex flex-1 items-center justify-center py-10 sm:py-14">
          <div className={cn("w-full max-w-md space-y-6 p-6 sm:p-8", v2SurfaceClass)}>
            <div className="space-y-4 text-center">
              <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl border border-white/10 bg-white/[0.04] text-white/80">
                {isUpgrade ? <Play size={24} fill="currentColor" className="text-white/70" /> : <Lock size={24} />}
              </div>

              <div className="space-y-2">
                <p className="mx-auto inline-flex max-w-full items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-3 py-1 text-[11px] font-medium text-text-tertiary">
                  <span className="truncate">{title}</span>
                </p>
                <h1 className="text-2xl font-semibold tracking-tight text-white sm:text-[1.65rem]">
                  {copy.heading}
                </h1>
                <p className="text-sm leading-relaxed text-text-secondary">{copy.body}</p>
              </div>
            </div>

            <ul className="grid gap-2 rounded-2xl border border-white/[0.06] bg-white/[0.02] p-3 text-left sm:grid-cols-2">
              {BENEFITS.map((item) => (
                <li key={item} className="flex items-start gap-2 text-xs font-medium leading-snug text-text-secondary">
                  <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-emerald-400/90" aria-hidden />
                  {item}
                </li>
              ))}
            </ul>

            <div className="flex flex-col gap-2.5">
              {isUpgrade ? (
                <>
                  {whatsappHref ? (
                    <a
                      href={whatsappHref}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex min-h-11 items-center justify-center rounded-full bg-white px-5 text-sm font-semibold transition hover:bg-zinc-100"
                      style={{ color: "#09090b" }}
                    >
                      <span style={{ color: "#09090b" }}>Get access on WhatsApp</span>
                    </a>
                  ) : null}
                  <Link
                    href="/subscribe"
                    className={cn(
                      "inline-flex min-h-11 items-center justify-center rounded-full px-5 text-sm font-semibold transition",
                      whatsappHref
                        ? "border border-white/15 bg-white/[0.04] text-white hover:bg-white/[0.08]"
                        : "bg-white hover:bg-zinc-100"
                    )}
                    style={whatsappHref ? undefined : { color: "#09090b" }}
                  >
                    <span style={whatsappHref ? undefined : { color: "#09090b" }}>View plans</span>
                  </Link>
                </>
              ) : (
                <Link
                  href={primaryHref}
                  className="inline-flex min-h-11 items-center justify-center gap-2 rounded-full bg-white px-5 text-sm font-semibold transition hover:bg-zinc-100"
                  style={{ color: "#09090b" }}
                >
                  <LogIn size={16} style={{ color: "#09090b" }} />
                  <span style={{ color: "#09090b" }}>{copy.primaryLabel}</span>
                </Link>
              )}

              {!isUpgrade ? (
                <p className="text-center text-[11px] leading-relaxed text-text-tertiary">
                  Same account as the Fotty iOS app.{" "}
                  <Link href="/login" className="font-semibold text-white/70 underline-offset-2 hover:text-white hover:underline">
                    Create one
                  </Link>{" "}
                  if you are new.
                  {reason === "refresh" ? (
                    <>
                      {" "}
                      <button
                        type="button"
                        onClick={() => {
                          clearAuthSession();
                          window.location.href = `/login?refresh=1&next=${encodeURIComponent(returnTo)}`;
                        }}
                        className="font-semibold text-white/70 underline-offset-2 hover:text-white hover:underline"
                      >
                        Sign out and try again
                      </button>
                    </>
                  ) : null}
                </p>
              ) : null}
            </div>
          </div>
        </div>
      </div>
    </main>
  );
}
