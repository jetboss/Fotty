"use client";

import Link from "next/link";
import { Suspense, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { ArrowLeft, CheckCircle2, Loader2 } from "lucide-react";
import { useAuth } from "@/components/AuthProvider";
import { setLocalEntitlement, type FottyPlan } from "@/lib/entitlements";
import { trackEvent } from "@/lib/analytics";
import { checkoutPlanToEntitlement, getTtPlan, type TtCheckoutPlanId } from "@/lib/tt-plans";

function isCheckoutPlanId(value: string | null): value is TtCheckoutPlanId {
  return (
    value === "supporter" ||
    value === "plus_annual" ||
    value === "plus_lifetime" ||
    value === "plus" ||
    value === "builder" ||
    value === "collab"
  );
}

export default function SubscribeSuccessPage() {
  return (
    <Suspense
      fallback={
        <main className="min-h-dvh bg-background pt-12 text-text-primary">
          <div className="px-md py-lg">
            <div className="flex items-center gap-3 text-sm font-bold text-text-secondary">
              <Loader2 size={18} className="animate-spin text-accent" />
              Loading checkout confirmation…
            </div>
          </div>
        </main>
      }
    >
      <SubscribeSuccessContent />
    </Suspense>
  );
}

function SubscribeSuccessContent() {
  const searchParams = useSearchParams();
  const { session } = useAuth();

  const planParam = searchParams.get("plan");
  const email = searchParams.get("email")?.trim().toLowerCase() || session?.email || "";
  const token = searchParams.get("token") || "";

  const checkoutPlan = useMemo(() => (isCheckoutPlanId(planParam) ? planParam : null), [planParam]);

  if (!checkoutPlan) {
    return <SubscribeSuccessView status="error" title="Subscription" email={email} />;
  }

  const paidPlan = checkoutPlanToEntitlement(checkoutPlan);
  const title = getTtPlan(checkoutPlan).title;

  return (
    <SubscribeSuccessConfirmed
      paidPlan={paidPlan}
      title={title}
      email={email}
      token={token}
      sessionEmail={session?.email}
      signedIn={Boolean(session)}
    />
  );
}

function SubscribeSuccessConfirmed({
  paidPlan,
  title,
  email,
  token,
  sessionEmail,
  signedIn,
}: {
  paidPlan: Exclude<FottyPlan, "free">;
  title: string;
  email: string;
  token: string;
  sessionEmail?: string;
  signedIn: boolean;
}) {
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");

  useEffect(() => {
    const params = new URLSearchParams({ plan: paidPlan });
    if (email) params.set("email", email);
    if (token) params.set("token", token);

    let cancelled = false;

    fetch(`/api/billing/confirm?${params.toString()}`)
      .then(async (response) => {
        if (!response.ok) throw new Error("confirm_failed");
        if (cancelled) return;
        setLocalEntitlement({ plan: paidPlan, email: email || sessionEmail });
        trackEvent("subscription_checkout_success", { plan: paidPlan, signedIn });
        setStatus("ready");
      })
      .catch(() => {
        if (!cancelled) setStatus("error");
      });

    return () => {
      cancelled = true;
    };
  }, [email, paidPlan, sessionEmail, signedIn, token]);

  return <SubscribeSuccessView status={status} title={title} email={email} />;
}

function SubscribeSuccessView({
  status,
  title,
  email,
}: {
  status: "loading" | "ready" | "error";
  title: string;
  email: string;
}) {
  return (
    <main className="min-h-dvh bg-background pt-12 text-text-primary" data-checkout-status={status}>
      <header className="space-y-4 px-md">
        <Link href="/settings" className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-surface text-text-primary" aria-label="Back">
          <ArrowLeft size={18} />
        </Link>
        <div className="space-y-2">
          <h1 className="text-4xl font-black">Thanks for supporting Fotty</h1>
          <p className="max-w-2xl text-sm font-medium leading-6 text-text-secondary">
            {status === "loading"
              ? "Confirming your checkout and updating access on this device…"
              : status === "ready"
                ? `${title} is active here. PocketBase entitlements sync when the billing webhook is configured.`
                : "We could not confirm this checkout link. Return to Subscribe and try again, or contact support if you were charged."}
          </p>
        </div>
      </header>

      <div className="px-md py-lg">
        <div className="mx-auto max-w-lg rounded-xl border border-white/5 bg-surface p-6">
          {status === "loading" ? (
            <div className="flex items-center gap-3 text-sm font-bold text-text-secondary">
              <Loader2 size={18} className="animate-spin text-accent" />
              Finishing setup…
            </div>
          ) : status === "ready" ? (
            <div className="space-y-3">
              <div className="inline-flex items-center gap-2 text-success">
                <CheckCircle2 size={20} />
                <span className="text-sm font-black">{title} active on this device</span>
              </div>
              {email ? <p className="text-xs font-medium text-text-secondary">Checkout email: {email}</p> : null}
              <p className="text-xs font-medium leading-5 text-text-tertiary">
                Sign in with the same email to keep access across browsers once PocketBase entitlements are enabled.
              </p>
            </div>
          ) : (
            <p className="text-sm font-medium text-text-secondary">Missing or invalid plan in the return URL.</p>
          )}

          <div className="mt-6 flex flex-col gap-3 sm:flex-row">
            <Link href="/" className="inline-flex min-h-11 flex-1 items-center justify-center rounded-lg accent-gradient px-4 text-xs font-black text-white">
              Back to live board
            </Link>
            <Link href="/subscribe" className="inline-flex min-h-11 flex-1 items-center justify-center rounded-lg border border-white/10 bg-white/5 px-4 text-xs font-black text-text-primary">
              View plans
            </Link>
          </div>
        </div>
      </div>
    </main>
  );
}
