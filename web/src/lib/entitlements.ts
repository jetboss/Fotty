"use client";

import { getAuthSession, setAuthSession, type FottyAuthSession } from "@/lib/auth";
import { formatAccessDetail, isAccessExpired } from "@/lib/entitlement-access";

export type FottyPlan = "free" | "plus" | "supporter" | "collab" | "builder";

export interface EntitlementState {
  plan: FottyPlan;
  label: string;
  /** Full line for profile / settings, e.g. "Fotty Plus · until May 2027". */
  accessDetail: string;
  expiresAt: string | null;
  isPaid: boolean;
  hasPlus: boolean;
  source: "session" | "local";
}

export interface EntitlementUpgrade {
  plan: Exclude<FottyPlan, "free">;
  email?: string;
}

const ENTITLEMENT_KEY = "fotty.web.entitlement.v1";
const ENTITLEMENT_EVENT = "fotty:entitlement";

const PLAN_LABELS: Record<FottyPlan, string> = {
  free: "Free",
  plus: "Fotty Plus",
  supporter: "Match-Day Pass",
  collab: "Fotty Collab",
  builder: "Fotty Builder",
};

function normalizePlan(value: unknown): FottyPlan {
  if (value === "plus" || value === "supporter" || value === "collab" || value === "builder") return value;
  return "free";
}

function readLocalPlan(): FottyPlan {
  if (typeof window === "undefined") return "free";
  try {
    return normalizePlan(JSON.parse(window.localStorage.getItem(ENTITLEMENT_KEY) || "{}")?.plan);
  } catch {
    return "free";
  }
}

function effectivePlan(plan: FottyPlan, expiresAt: string | null | undefined): FottyPlan {
  if (plan === "free") return "free";
  if (expiresAt && isAccessExpired(expiresAt)) return "free";
  return plan;
}

export function getEntitlementState(session = getAuthSession()): EntitlementState {
  const rawPlan = normalizePlan(session?.entitlement || readLocalPlan());
  const expiresAt = session?.entitlementExpiresAt ?? null;
  const plan = effectivePlan(rawPlan, expiresAt);
  return {
    plan,
    label: PLAN_LABELS[plan],
    accessDetail: formatAccessDetail(plan, expiresAt),
    expiresAt,
    isPaid: plan !== "free",
    hasPlus: plan !== "free",
    source: session?.entitlement ? "session" : "local",
  };
}

export function setLocalEntitlement(upgrade: EntitlementUpgrade) {
  if (typeof window === "undefined") return;
  const next = {
    plan: upgrade.plan,
    email: upgrade.email,
    updatedAt: new Date().toISOString(),
  };
  window.localStorage.setItem(ENTITLEMENT_KEY, JSON.stringify(next));

  const session = getAuthSession();
  if (session) {
    setAuthSession({
      ...session,
      email: upgrade.email || session.email,
      entitlement: upgrade.plan,
    } satisfies FottyAuthSession);
  }

  window.dispatchEvent(new CustomEvent(ENTITLEMENT_EVENT));
}

export function subscribeToEntitlements(onStoreChange: () => void) {
  window.addEventListener(ENTITLEMENT_EVENT, onStoreChange);
  window.addEventListener("fotty:auth", onStoreChange);
  window.addEventListener("storage", onStoreChange);
  return () => {
    window.removeEventListener(ENTITLEMENT_EVENT, onStoreChange);
    window.removeEventListener("fotty:auth", onStoreChange);
    window.removeEventListener("storage", onStoreChange);
  };
}

