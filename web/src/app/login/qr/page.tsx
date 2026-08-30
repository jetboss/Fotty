"use client";

import { Suspense, useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { CheckCircle2, Loader2, LockKeyhole, XCircle } from "lucide-react";
import { setAuthSession, type FottyAuthSession } from "@/lib/auth";
import { v2HomePath } from "@/lib/v2/preview";

function safeReturnTo(value: string | null | undefined) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return v2HomePath();
  return value;
}

function QrLoginRedeemer() {
  const params = useSearchParams();
  const token = params.get("token") || "";
  const [state, setState] = useState<"loading" | "success" | "error">("loading");
  const [message, setMessage] = useState("Checking secure login link...");
  const [returnTo, setReturnTo] = useState(v2HomePath());

  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    if (!mounted) return;
    let cancelled = false;

    async function redeem() {
      if (!token) {
        setState("error");
        setMessage("This QR code is missing its login token.");
        return;
      }

      try {
        const response = await fetch("/api/auth/qr/redeem", {
          method: "POST",
          headers: { "Content-Type": "application/json", Accept: "application/json" },
          body: JSON.stringify({ token }),
        });
        const payload = (await response.json().catch(() => ({}))) as {
          session?: FottyAuthSession;
          returnTo?: string;
          error?: string;
        };
        if (cancelled) return;
        if (!response.ok || !payload.session) {
          setState("error");
          setMessage(payload.error || "This QR login link could not be used.");
          return;
        }
        setAuthSession(payload.session);
        const next = safeReturnTo(payload.returnTo);
        setReturnTo(next);
        setState("success");
        setMessage(`Signed in as ${payload.session.email}`);
        window.setTimeout(() => {
          window.location.href = next;
        }, 900);
      } catch {
        if (cancelled) return;
        setState("error");
        setMessage("QR login is temporarily unavailable.");
      }
    }

    void redeem();
    return () => {
      cancelled = true;
    };
  }, [token]);

  if (!mounted) {
    return (
      <main className="grid min-h-dvh place-items-center bg-background px-5 text-text-primary">
        <section className="w-full max-w-md mx-auto rounded-xl border border-white/10 bg-surface p-6 text-center">
          <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-accent/15 text-accent">
            <Loader2 className="animate-spin" size={24} />
          </div>
          <p className="mt-5 text-xs font-black uppercase tracking-wide text-accent">Fotty QR login</p>
          <h1 className="mt-2 text-2xl font-black text-white">Signing you in</h1>
          <p className="mt-3 text-sm font-medium leading-6 text-text-secondary">Checking secure login link...</p>
        </section>
      </main>
    );
  }

  return (
    <main className="grid min-h-dvh place-items-center bg-background px-5 text-text-primary">
      <section className="w-full max-w-md mx-auto rounded-xl border border-white/10 bg-surface p-6 text-center">
        <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-accent/15 text-accent">
          {state === "loading" ? <Loader2 className="animate-spin" size={24} /> : state === "success" ? <CheckCircle2 size={24} /> : <XCircle size={24} />}
        </div>
        <p className="mt-5 text-xs font-black uppercase tracking-wide text-accent">Fotty QR login</p>
        <h1 className="mt-2 text-2xl font-black text-white">
          {state === "loading" ? "Signing you in" : state === "success" ? "You are signed in" : "Login link failed"}
        </h1>
        <p className="mt-3 text-sm font-medium leading-6 text-text-secondary">{message}</p>
        <div className="mt-6 flex flex-wrap justify-center gap-2">
          {state === "success" ? (
            <Link href={returnTo} className="inline-flex min-h-10 items-center rounded-full accent-gradient px-5 text-sm font-bold text-white">
              Continue
            </Link>
          ) : null}
          {state === "error" ? (
            <Link href="/login" className="inline-flex min-h-10 items-center gap-2 rounded-full border border-white/10 bg-background px-5 text-sm font-bold text-white">
              <LockKeyhole size={15} />
              Sign in another way
            </Link>
          ) : null}
        </div>
      </section>
    </main>
  );
}

export default function QrLoginPage() {
  return (
    <Suspense
      fallback={
        <main className="grid min-h-dvh place-items-center bg-background px-5 text-text-primary">
          <section className="w-full max-w-md mx-auto rounded-xl border border-white/10 bg-surface p-6 text-center">
            <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-accent/15 text-accent">
              <Loader2 className="animate-spin" size={24} />
            </div>
            <p className="mt-5 text-xs font-black uppercase tracking-wide text-accent">Fotty QR login</p>
            <h1 className="mt-2 text-2xl font-black text-white">Signing you in</h1>
            <p className="mt-3 text-sm font-medium leading-6 text-text-secondary">Checking secure login link...</p>
          </section>
        </main>
      }
    >
      <QrLoginRedeemer />
    </Suspense>
  );
}
