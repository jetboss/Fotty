import { getPocketBaseUrl } from "@/lib/fotty-config";
import type { FottyPlan } from "@/lib/entitlements";
import { isPaidPlan } from "@/lib/billing";
import { isAccessExpired } from "@/lib/entitlement-access";

const POCKETBASE_BASE = getPocketBaseUrl();

export interface UserAccessRecord {
  plan: FottyPlan;
  expiresAt: string | null;
}

function normalizePlanValue(value: unknown): FottyPlan {
  if (value === "plus" || value === "supporter" || value === "collab" || value === "builder") return value;
  return "free";
}

export async function fetchUserAccess(userID: string, token: string): Promise<UserAccessRecord | undefined> {
  try {
    const response = await fetch(`${POCKETBASE_BASE}/api/collections/users/records/${userID}`, {
      headers: {
        Accept: "application/json",
        Authorization: token.startsWith("Bearer ") ? token : `Bearer ${token}`,
      },
      cache: "no-store",
    });

    if (!response.ok) return undefined;
    const record = (await response.json()) as {
      entitlement?: string;
      plan?: string;
      entitlementExpiresAt?: string;
    };
    const expiresAt = record.entitlementExpiresAt?.trim() || null;
    let plan = normalizePlanValue(record.entitlement || record.plan);
    if (!isPaidPlan(plan) && plan !== "free") plan = "free";
    if (plan !== "free" && isAccessExpired(expiresAt)) plan = "free";
    return { plan, expiresAt };
  } catch {
    return undefined;
  }
}

export async function fetchUserEntitlement(userID: string, token: string): Promise<FottyPlan | undefined> {
  const access = await fetchUserAccess(userID, token);
  return access?.plan;
}

export async function updateUserEntitlement(userID: string, adminToken: string, plan: FottyPlan) {
  const response = await fetch(`${POCKETBASE_BASE}/api/collections/users/records/${userID}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: adminToken,
    },
    body: JSON.stringify({ entitlement: plan, plan }),
    cache: "no-store",
  });

  return response.ok;
}

export async function findUserIDByEmail(email: string, adminToken: string) {
  const filter = encodeURIComponent(`email="${email.replace(/"/g, '\\"')}"`);
  const response = await fetch(`${POCKETBASE_BASE}/api/collections/users/records?filter=${filter}&perPage=1`, {
    headers: {
      Accept: "application/json",
      Authorization: adminToken,
    },
    cache: "no-store",
  });

  if (!response.ok) return null;
  const payload = (await response.json()) as { items?: Array<{ id?: string }> };
  return payload.items?.[0]?.id || null;
}
