import type { FottyPlan } from "@/lib/entitlements";
import { fetchUserEntitlement } from "@/lib/server/pocketbase-user";
import { resolveLocalEntitlement } from "@/lib/server/admin-grants-local";
const PLAN_RANK: Record<FottyPlan, number> = {
  free: 0,
  supporter: 1,
  plus: 2,
  builder: 3,
  collab: 4,
};

function pickHigher(a: FottyPlan, b: FottyPlan): FottyPlan {
  return PLAN_RANK[b] > PLAN_RANK[a] ? b : a;
}

export async function resolveUserEntitlement(input: {
  userID?: string;
  token?: string;
  email?: string;
}): Promise<FottyPlan> {
  let resolved: FottyPlan = "free";

  if (input.userID && input.token) {
    const fromPb = await fetchUserEntitlement(input.userID, input.token);
    if (fromPb) resolved = fromPb;
  }
  // Email-only lookup is intentionally not supported here — prevents header spoofing on watch routes.

  if (input.email) {
    const fromLocal = await resolveLocalEntitlement(input.email);
    if (fromLocal) resolved = pickHigher(resolved, fromLocal);
  }

  return resolved;
}
