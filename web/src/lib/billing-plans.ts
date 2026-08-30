import type { FottyPlan } from "@/lib/entitlements";

export type PaidPlan = Exclude<FottyPlan, "free">;

const PAID_PLANS = new Set<PaidPlan>(["plus", "supporter", "collab", "builder"]);

export function isPaidPlan(value: unknown): value is PaidPlan {
  return typeof value === "string" && PAID_PLANS.has(value as PaidPlan);
}
