"use client";

import React, { Suspense, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { ArrowLeft, Crown, Lock, LogIn, Mail, UserPlus } from "lucide-react";
import { useAuth } from "@/components/AuthProvider";
import { useEntitlement } from "@/components/EntitlementProvider";
import { ACCOUNTS_UNAVAILABLE_MESSAGE, isAccountsEnabled } from "@/lib/accounts";
import { trackEvent } from "@/lib/analytics";
import { getAuthSession } from "@/lib/auth";
import { isStaticFottyHost } from "@/lib/fotty-api-fetch";
import { pocketBaseRequestPasswordReset } from "@/lib/pocketbase-client-auth";
import { allowLocalAuth } from "@/lib/runtime-env";
import { v2HomePath } from "@/lib/v2/preview";
import { v2SurfaceClass } from "@/components/v2/V2PageShell";
import { cn } from "@/lib/utils";

function safeReturnTo(value: string | null | undefined, fallback: string) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return fallback;
  return value;
}

function LoginPageContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const homeHref = v2HomePath();
  const needsSessionRefresh = searchParams.get("refresh") === "1";
  const returnTo = useMemo(
    () => safeReturnTo(searchParams.get("next"), homeHref),
    [homeHref, searchParams]
  );
  const { session, signIn, signUp, isReady } = useAuth();
  const entitlement = useEntitlement();
  const [isSignUp, setIsSignUp] = useState(() => searchParams.get("mode") === "signup");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [resetPending, setResetPending] = useState(false);

  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    const hasWatchToken = Boolean(session?.token) || (allowLocalAuth && session?.provider === "local");
    if (mounted && isReady && session && hasWatchToken && !needsSessionRefresh) {
      router.replace(returnTo);
    }
  }, [mounted, isReady, needsSessionRefresh, returnTo, router, session]);

  useEffect(() => {
    if (session?.email && (needsSessionRefresh || !session.token)) {
      setEmail(session.email);
    }
  }, [needsSessionRefresh, session?.email, session?.token]);

  useEffect(() => {
    if (searchParams.get("mode") === "signup") {
      setIsSignUp(true);
    }
  }, [searchParams]);

  async function handleForgotPassword() {
    const trimmed = email.trim().toLowerCase();
    if (!trimmed) {
      setError("Enter your email first, then tap Forgot password.");
      setNotice(null);
      return;
    }
    setError(null);
    setNotice(null);
    setResetPending(true);
    try {
      let response: Response | null = null;
      try {
        response = await fetch("/api/pocketbase/reset-password", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ email: trimmed }),
        });
      } catch {
        response = null;
      }

      if (response?.status === 404 || isStaticFottyHost()) {
        const message = await pocketBaseRequestPasswordReset(trimmed);
        setNotice(
          `${message} If nothing arrives within a few minutes, try the Fotty app password or ask for a manual reset.`
        );
        return;
      }

      const payload = (await response?.json().catch(() => ({}))) as { message?: string; error?: string };
      if (!response?.ok) {
        throw new Error(typeof payload.error === "string" ? payload.error : "Could not send reset email.");
      }
      setNotice(
        typeof payload.message === "string"
          ? `${payload.message} If nothing arrives within a few minutes, try the Fotty app password or ask for a manual reset.`
          : "If an account exists for that email, you will receive a password reset link shortly."
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not send reset email.");
    } finally {
      setResetPending(false);
    }
  }

  async function handleSubmit() {
    setError(null);
    setNotice(null);
    setPending(true);
    try {
      trackEvent(isSignUp ? "signup_attempt" : "login_attempt", { hasEmail: Boolean(email.trim()) });
      if (isSignUp) {
        await signUp(email, password, displayName);
      } else {
        await signIn(email, password);
      }
      const updated = getAuthSession();
      const hasWatchToken =
        Boolean(updated?.token) || (allowLocalAuth && updated?.provider === "local");
      if (!hasWatchToken) {
        throw new Error("Sign-in succeeded but secure watch access was not restored. Try again.");
      }
      router.replace(returnTo);
    } catch (err) {
      console.error("Fotty auth submit failed", err);
      const fallback = isSignUp
        ? "We could not create this account yet. Check the details and try again."
        : "We could not verify those details. Check your email and password, then try again.";
      setError(err instanceof Error && err.message ? err.message : fallback);
    } finally {
      setPending(false);
    }
  }

  if (!mounted) {
    return <LoginSkeleton homeHref={homeHref} />;
  }

  if (!isAccountsEnabled()) {
    return (
      <AuthShell homeHref={homeHref}>
        <div className={cn("w-full max-w-md mx-auto space-y-6 p-6 sm:p-8", v2SurfaceClass)}>
          <div className="space-y-2 text-center">
            <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl border border-white/10 bg-white/[0.04] text-white/80">
              <Lock size={24} />
            </div>
            <h1 className="text-2xl font-semibold tracking-tight text-white">Accounts paused</h1>
            <p className="text-sm leading-relaxed text-text-secondary">{ACCOUNTS_UNAVAILABLE_MESSAGE}</p>
          </div>
          <Link
            href={homeHref}
            className="inline-flex min-h-11 w-full items-center justify-center rounded-full bg-white px-5 text-sm font-semibold transition hover:bg-zinc-100"
            style={{ color: "#09090b" }}
          >
            Back to matches
          </Link>
        </div>
      </AuthShell>
    );
  }

  if (isReady && session && (session.token || (allowLocalAuth && session.provider === "local")) && !needsSessionRefresh) {
    return (
      <AuthShell homeHref={homeHref}>
        <div className={cn("w-full max-w-md mx-auto space-y-6 p-6 sm:p-8", v2SurfaceClass)}>
          <div className="space-y-2 text-center">
            <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl border border-white/10 bg-white/[0.04] text-white/80">
              <Crown size={24} />
            </div>
            <h1 className="text-2xl font-semibold tracking-tight text-white">You are signed in</h1>
            <p className="text-sm text-text-secondary">{session.email}</p>
          </div>

          <div className="rounded-2xl border border-white/[0.06] bg-white/[0.02] p-4">
            <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-text-tertiary">Access</p>
            <p className="mt-1 text-sm font-semibold text-white">{entitlement.label}</p>
            <p className="mt-1 text-xs text-text-tertiary">{entitlement.accessDetail}</p>
          </div>

          <div className="flex flex-col gap-2.5">
            <Link
              href={returnTo}
              className="inline-flex min-h-11 items-center justify-center rounded-full bg-white px-5 text-sm font-semibold transition hover:bg-zinc-100"
              style={{ color: "#09090b" }}
            >
              Continue
            </Link>
            <Link
              href="/subscribe"
              className="inline-flex min-h-11 items-center justify-center rounded-full border border-white/15 bg-white/[0.04] px-5 text-sm font-semibold text-white transition hover:bg-white/[0.08]"
            >
              Manage access
            </Link>
          </div>
        </div>
      </AuthShell>
    );
  }

  return (
    <AuthShell homeHref={homeHref}>
      <div className={cn("w-full max-w-md mx-auto space-y-6 p-6 sm:p-8", v2SurfaceClass)}>
        <div className="space-y-2 text-center sm:text-left">
          <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl border border-white/10 bg-white/[0.04] text-white/80 sm:mx-0">
            {isSignUp ? <UserPlus size={24} /> : <LogIn size={24} />}
          </div>
          <h1 className="text-2xl font-semibold tracking-tight text-white sm:text-[1.65rem]">
            {needsSessionRefresh ? "Refresh watch access" : isSignUp ? "Create your account" : "Sign in to Fotty"}
          </h1>
          <p className="text-sm leading-relaxed text-text-secondary">
            {needsSessionRefresh
              ? "Enter your password again to restore secure playback on this device."
              : isSignUp
              ? "One account for web and mobile. Password must be at least 8 characters."
              : "Use the same email and password as the Fotty app. If autofill fails, type your password manually."}
          </p>
        </div>

        <div className="space-y-4">
          <label className="block space-y-1.5">
            <span className="text-[11px] font-semibold uppercase tracking-[0.12em] text-text-tertiary">Email</span>
            <span className="flex items-center gap-2 rounded-xl border border-white/10 bg-[#0a0a0d] px-3 py-2.5">
              <Mail size={16} className="shrink-0 text-text-tertiary" />
              <input
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="min-w-0 flex-1 bg-transparent text-sm text-white outline-none placeholder:text-white/25"
                placeholder="you@example.com"
              />
            </span>
          </label>

          <label className="block space-y-1.5">
            <span className="text-[11px] font-semibold uppercase tracking-[0.12em] text-text-tertiary">Password</span>
            <span className="flex items-center gap-2 rounded-xl border border-white/10 bg-[#0a0a0d] px-3 py-2.5">
              <Lock size={16} className="shrink-0 text-text-tertiary" />
              <input
                type="password"
                autoComplete={isSignUp ? "new-password" : "current-password"}
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="min-w-0 flex-1 bg-transparent text-sm text-white outline-none placeholder:text-white/25"
                placeholder={isSignUp ? "At least 8 characters" : "Your password"}
              />
            </span>
          </label>

          {isSignUp ? (
            <label className="block space-y-1.5">
              <span className="text-[11px] font-semibold uppercase tracking-[0.12em] text-text-tertiary">
                Display name <span className="normal-case tracking-normal text-text-tertiary">(optional)</span>
              </span>
              <input
                type="text"
                autoComplete="name"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                className="w-full rounded-xl border border-white/10 bg-[#0a0a0d] px-3 py-2.5 text-sm text-white outline-none placeholder:text-white/25"
                placeholder="How you appear in Fotty"
              />
            </label>
          ) : null}

          {!isSignUp ? (
            <button
              type="button"
              disabled={resetPending}
              onClick={handleForgotPassword}
              className="text-xs font-semibold text-white/55 underline-offset-2 transition hover:text-white hover:underline disabled:opacity-60"
            >
              {resetPending ? "Sending reset link…" : "Forgot password?"}
            </button>
          ) : null}

          {notice ? <p className="text-xs font-medium leading-relaxed text-emerald-400/90">{notice}</p> : null}
          {error ? <p className="text-xs font-medium leading-relaxed text-amber-300">{error}</p> : null}

          <button
            type="button"
            disabled={pending}
            onClick={handleSubmit}
            className="fotty-v2-auth-cta flex min-h-11 w-full items-center justify-center gap-2 rounded-full px-5 text-sm font-semibold accent-gradient text-white transition hover:brightness-110 disabled:opacity-60"
          >
            {pending ? (
              isSignUp ? "Creating account…" : "Signing in…"
            ) : isSignUp ? (
              <>
                <UserPlus size={16} />
                <span>Create account</span>
              </>
            ) : (
              <>
                <LogIn size={16} />
                <span>Sign in</span>
              </>
            )}
          </button>

          <button
            type="button"
            className="w-full text-center text-xs font-semibold text-zinc-300 transition hover:text-white"
            onClick={() => {
              setIsSignUp((value) => !value);
              setError(null);
              setNotice(null);
            }}
          >
            {isSignUp ? "Already have an account? Sign in" : "Need an account? Create one"}
          </button>
        </div>

        <ul className="space-y-2 rounded-2xl border border-white/[0.06] bg-white/[0.02] p-3 text-left">
          {[
            "Reminders and saved matches stay on this device.",
            "Plus access attaches to this account after checkout.",
            "Playback stays match-first — sign in unlocks watch and sync.",
          ].map((item) => (
            <li key={item} className="flex items-start gap-2 text-[11px] font-medium leading-snug text-text-secondary">
              <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-emerald-400/90" aria-hidden />
              {item}
            </li>
          ))}
        </ul>

        {allowLocalAuth ? (
          <p className="text-center text-[10px] leading-relaxed text-text-tertiary">
            Development mode: local auth fallback is enabled on this build.
          </p>
        ) : null}
      </div>
    </AuthShell>
  );
}

function AuthShell({
  homeHref,
  children,
}: {
  homeHref: string;
  children: React.ReactNode;
}) {
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

        <div className="w-full flex flex-col flex-1 justify-center py-10 sm:py-14">{children}</div>
      </div>
    </main>
  );
}

/** Skeleton shown while LoginPageContent suspends (useSearchParams) */
function LoginSkeleton({ homeHref }: { homeHref: string }) {
  return (
    <AuthShell homeHref={homeHref}>
      <div className={cn("w-full max-w-md mx-auto space-y-6 p-6 sm:p-8", v2SurfaceClass)}>
        <div className="space-y-2">
          <div className="h-14 w-14 animate-pulse rounded-2xl bg-white/[0.06]" />
          <div className="h-7 w-40 animate-pulse rounded-lg bg-white/[0.06]" />
          <div className="h-4 w-full animate-pulse rounded bg-white/[0.04]" />
          <div className="h-4 w-3/4 animate-pulse rounded bg-white/[0.04]" />
        </div>
        <div className="space-y-4">
          <div className="h-11 w-full animate-pulse rounded-xl bg-white/[0.06]" />
          <div className="h-11 w-full animate-pulse rounded-xl bg-white/[0.06]" />
          <div className="h-11 w-full animate-pulse rounded-full bg-white/[0.08]" />
        </div>
      </div>
    </AuthShell>
  );
}

export default function LoginPage() {
  const homeHref = v2HomePath();
  return (
    <Suspense fallback={<LoginSkeleton homeHref={homeHref} />}>
      <LoginPageContent />
    </Suspense>
  );
}
