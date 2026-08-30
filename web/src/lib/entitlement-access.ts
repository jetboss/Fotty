import type { FottyPlan } from "@/lib/entitlements";

export type EntitlementPreset = "matchday" | "monthly" | "annual" | "lifetime";

const PLAN_LABELS: Record<FottyPlan, string> = {
  free: "Free",
  plus: "Fotty Plus",
  supporter: "Match-Day Pass",
  collab: "Fotty Collab",
  builder: "Fotty Builder",
};

export function addDaysIso(days: number, from = new Date()): string {
  const date = new Date(from);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString();
}

export function addYearsIso(years: number, from = new Date()): string {
  const date = new Date(from);
  date.setUTCFullYear(date.getUTCFullYear() + years);
  return date.toISOString();
}

export function presetToAccess(preset: EntitlementPreset): { entitlement: FottyPlan; expiresAt: string | null } {
  switch (preset) {
    case "matchday":
      return { entitlement: "supporter", expiresAt: addDaysIso(7) };
    case "monthly":
      return { entitlement: "plus", expiresAt: addDaysIso(30) };
    case "annual":
      return { entitlement: "plus", expiresAt: addYearsIso(1) };
    case "lifetime":
      return { entitlement: "plus", expiresAt: null };
  }
}

export function presetExpiryInputValue(preset: EntitlementPreset): string {
  const { expiresAt } = presetToAccess(preset);
  if (!expiresAt) return "";
  return expiresAt.slice(0, 10);
}

export function isAccessExpired(expiresAt: string | null | undefined): boolean {
  if (!expiresAt) return false;
  const expMs = new Date(expiresAt).getTime();
  return Number.isFinite(expMs) && Date.now() > expMs;
}

export function formatExpiryDate(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const date = new Date(iso);
  if (!Number.isFinite(date.getTime())) return null;
  return date.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

/** User-facing access line for Settings and subscribe sidebar. */
export function formatAccessDetail(plan: FottyPlan, expiresAt?: string | null): string {
  const base = PLAN_LABELS[plan];
  if (plan === "free") return base;
  if (expiresAt && isAccessExpired(expiresAt)) return `${base} · expired`;
  if (!expiresAt) return `${base} · lifetime`;
  const until = formatExpiryDate(expiresAt);
  return until ? `${base} · until ${until}` : base;
}
