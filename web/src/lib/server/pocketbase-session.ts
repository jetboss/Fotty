import { getPocketBaseUrl } from "@/lib/fotty-config";

const POCKETBASE_BASE = getPocketBaseUrl();

export interface PocketBaseSessionRecord {
  userID: string;
  email: string;
  entitlement?: string;
  plan?: string;
  entitlementExpiresAt?: string;
}

function bearerToken(token: string) {
  return token.startsWith("Bearer ") ? token : `Bearer ${token}`;
}

/** Validates a PocketBase user JWT and returns the current record id + email. */
export async function refreshPocketBaseSession(token: string): Promise<PocketBaseSessionRecord | null> {
  try {
    const response = await fetch(`${POCKETBASE_BASE}/api/collections/users/auth-refresh`, {
      method: "POST",
      headers: {
        Accept: "application/json",
        Authorization: bearerToken(token),
      },
      cache: "no-store",
    });

    if (!response.ok) return null;

    const payload = (await response.json()) as {
      record?: {
        id?: string;
        email?: string;
        entitlement?: string;
        plan?: string;
        entitlementExpiresAt?: string;
      };
    };
    const userID = payload.record?.id?.trim();
    const email = payload.record?.email?.trim().toLowerCase();
    if (!userID || !email) return null;

    return {
      userID,
      email,
      entitlement: payload.record?.entitlement,
      plan: payload.record?.plan,
      entitlementExpiresAt: payload.record?.entitlementExpiresAt,
    };
  } catch {
    return null;
  }
}
