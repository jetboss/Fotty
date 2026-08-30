"use client";

import Link from "next/link";
import React, { useState } from "react";
import { ArrowLeft, Calendar, Check, Crown, Handshake, Heart, Infinity, Rocket, ShieldCheck } from "lucide-react";
import { useAuth } from "@/components/AuthProvider";
import { useEntitlement } from "@/components/EntitlementProvider";
import { WhatsAppPayButton } from "@/components/WhatsAppPayButton";
import { trackEvent } from "@/lib/analytics";
import { saveSupportPledge } from "@/lib/storage";
import { TtPlanPrice } from "@/components/TtPlanPrice";
import {
  formatPlanCheckoutPrice,
  TT_PLANS_PRIMARY,
  TT_PLANS_SECONDARY,
  type TtCheckoutPlanId,
  type TtPlanDefinition,
} from "@/lib/tt-plans";
import { cn } from "@/lib/utils";

const PLAN_ICONS: Record<TtCheckoutPlanId, typeof Crown> = {
  supporter: ShieldCheck,
  plus_annual: Calendar,
  plus_lifetime: Infinity,
  plus: Crown,
  builder: Rocket,
  collab: Handshake,
};

const ACTIVATION_STEPS = [
  "Choose a plan and tap WhatsApp — your email is prefilled if you're signed in.",
  "We reply with Trinidad & Tobago bank transfer details.",
  "Send payment proof (screenshot) in the chat.",
  "We activate your account, usually within 24 hours.",
  "Sign in on Fotty — your plan and expiry show under Settings.",
];

export default function SubscribePage() {
  const { session } = useAuth();
  const entitlement = useEntitlement();
  const [selectedPlan, setSelectedPlan] = useState<TtCheckoutPlanId>("plus_annual");
  const plan =
    [...TT_PLANS_PRIMARY, ...TT_PLANS_SECONDARY].find((item) => item.id === selectedPlan) ?? TT_PLANS_PRIMARY[1];

  function recordPledge() {
    saveSupportPledge({
      plan: plan.id,
      title: plan.title,
      contact: session?.email,
      note: `TT WhatsApp lead — ${formatPlanCheckoutPrice(plan)}`,
    });
    trackEvent("support_pledge_saved", { plan: plan.id, channel: "whatsapp" });
  }

  return (
    <main className="min-h-dvh bg-background pt-12 text-text-primary">
      <header className="space-y-4 px-md">
        <Link href="/settings" className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-surface text-text-primary" aria-label="Back">
          <ArrowLeft size={18} />
        </Link>
        <div className="space-y-2">
          <p className="text-xs font-bold uppercase tracking-wide text-accent">Trinidad &amp; Tobago</p>
          <h1 className="text-4xl font-black">Plans in TTD</h1>
          <p className="max-w-2xl text-sm font-medium leading-6 text-text-secondary">
            Pay by bank transfer through WhatsApp. Annual and lifetime are one payment — we confirm and activate your
            account. Paid plans keep your match-day setup organized across reminders, saved teams, guide context, and
            source management.
          </p>
        </div>
      </header>

      <section className="mx-md mt-4 rounded-xl border border-live/25 bg-live/10 p-4">
        <p className="text-xs font-bold uppercase tracking-wide text-live">Launch pricing</p>
        <p className="mt-2 text-sm font-medium leading-6 text-text-secondary">
          <span className="font-bold text-white">Plus Annual</span> is TT$700/year (about two months free vs monthly).
          Monthly Plus stays at <span className="font-bold text-white">TT$65/mo</span> while the promo runs.{" "}
          <span className="font-bold text-white">Plus Lifetime</span> — message us on WhatsApp for the current one-time
          rate.
        </p>
      </section>

      <section className="mx-md mt-4 rounded-xl border border-accent/20 bg-accent/5 p-4">
        <div className="flex gap-3">
          <Heart size={18} className="mt-0.5 shrink-0 text-accent" />
          <div className="space-y-2 text-sm font-medium leading-6 text-text-secondary">
            <p className="font-bold text-text-primary">Same Plus tools on every paid plan</p>
            <p>
              Match-Day is 7 days. Annual renews after 12 months. Lifetime never expires. Monthly renews each month via
              WhatsApp or standing order. Choose the rhythm that fits how you follow games.
            </p>
            <p className="text-xs text-text-tertiary">
              Prices in TTD. Personal/household use — please don&apos;t share your login. Activation usually within 24
              hours after payment is confirmed.
            </p>
          </div>
        </div>
      </section>

      <div className="grid gap-4 px-md py-lg lg:grid-cols-[minmax(0,1fr)_400px]">
        <section className="space-y-6">
          <PlanGroup title="Choose your term" plans={TT_PLANS_PRIMARY} selectedPlan={selectedPlan} onSelect={setSelectedPlan} />
          <PlanGroup title="More options" plans={TT_PLANS_SECONDARY} selectedPlan={selectedPlan} onSelect={setSelectedPlan} />
        </section>

        <aside className="h-fit space-y-4 lg:sticky lg:top-24">
          <div className="rounded-xl border border-white/5 bg-surface p-4">
            <div className="space-y-4">
              <div className="rounded-lg border border-white/5 bg-background/70 p-4">
                <p className="text-xs font-bold uppercase text-text-tertiary">Current access</p>
                <p className="mt-1 text-2xl font-black text-white">{entitlement.label}</p>
                <p className="mt-1 text-xs font-medium text-accent">{entitlement.accessDetail}</p>
                <p className="mt-2 text-xs font-medium leading-5 text-text-secondary">
                  {session ? `Signed in as ${session.email}` : "Sign in so we can activate the right account."}
                </p>
              </div>

              <div>
                <p className="text-xs font-bold uppercase text-text-tertiary">Selected</p>
                <h2 className="mt-1 text-xl font-black text-white">{plan.title}</h2>
                <TtPlanPrice plan={plan} align="start" className="mt-2" />
                <p className="mt-2 text-xs font-medium leading-5 text-text-secondary">{plan.supportMessage}</p>
              </div>

              <div onClick={recordPledge}>
                <WhatsAppPayButton planId={plan.id} email={session?.email} />
              </div>

              {!session && (
                <Link
                  href="/login"
                  className="inline-flex min-h-11 w-full items-center justify-center rounded-lg border border-white/10 bg-white/5 px-4 text-xs font-bold text-text-primary"
                >
                  Sign in before you pay
                </Link>
              )}
            </div>
          </div>

          <div className="rounded-xl border border-white/5 bg-surface p-4">
            <p className="text-xs font-bold uppercase text-text-tertiary">How activation works</p>
            <ol className="mt-3 space-y-2">
              {ACTIVATION_STEPS.map((step, index) => (
                <li key={step} className="flex gap-2 text-xs font-medium leading-5 text-text-secondary">
                  <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-white/5 text-[10px] font-black text-text-primary">
                    {index + 1}
                  </span>
                  {step}
                </li>
              ))}
            </ol>
          </div>
        </aside>
      </div>
    </main>
  );
}

function PlanGroup({
  title,
  plans,
  selectedPlan,
  onSelect,
}: {
  title: string;
  plans: TtPlanDefinition[];
  selectedPlan: TtCheckoutPlanId;
  onSelect: (id: TtCheckoutPlanId) => void;
}) {
  if (plans.length === 0) return null;

  return (
    <div className="space-y-3">
      <h2 className="px-1 text-xs font-bold uppercase tracking-wide text-text-tertiary">{title}</h2>
      <div className="space-y-3">
        {plans.map((item) => {
          const Icon = PLAN_ICONS[item.id];
          const selected = item.id === selectedPlan;
          return (
            <button
              key={item.id}
              type="button"
              onClick={() => {
                onSelect(item.id);
                trackEvent("subscription_plan_select", { plan: item.id });
              }}
              className={cn(
                "w-full rounded-xl border p-4 text-left transition-colors",
                selected ? "border-accent/40 bg-accent/10" : "border-white/5 bg-surface hover:bg-surface-elevated",
                item.highlight && !selected && "border-accent/15"
              )}
            >
              <div className="flex gap-4">
                <div
                  className={cn(
                    "grid h-11 w-11 shrink-0 place-items-center rounded-full",
                    selected ? "bg-accent/15 text-accent" : "bg-white/5 text-accent"
                  )}
                >
                  <Icon size={18} />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <h3 className="text-base font-black text-white">{item.title}</h3>
                    <TtPlanPrice plan={item} />
                  </div>
                  <p className="mt-1 text-xs font-medium leading-5 text-text-secondary">{item.description}</p>
                  <p className="mt-2 text-[11px] font-medium text-text-tertiary">{item.billingNote}</p>
                  <div className="mt-3 grid gap-2 sm:grid-cols-2">
                    {item.features.map((feature) => (
                      <span key={feature} className="flex items-start gap-2 text-[11px] font-medium leading-5 text-text-secondary">
                        <Check size={13} className="mt-0.5 shrink-0 text-success" />
                        {feature}
                      </span>
                    ))}
                  </div>
                </div>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
