import { ACCOUNTS_UNAVAILABLE_MESSAGE, isAccountsEnabled } from "@/lib/accounts";
import { isPaidPlan } from "@/lib/billing-plans";
import { isAccessExpired } from "@/lib/entitlement-access";
import type { FottyPlan } from "@/lib/entitlements";
import { getPocketBaseUrl } from "@/lib/fotty-config";
import { pocketBaseUserMessage } from "@/lib/pocketbase-errors";
import type { FottyAuthSession } from "@/lib/auth";

function assertAccountsEnabled() {
  if (!isAccountsEnabled()) {
    throw new Error(ACCOUNTS_UNAVAILABLE_MESSAGE);
  }
  if (!getPocketBaseUrl()) {
    throw new Error(ACCOUNTS_UNAVAILABLE_MESSAGE);
  }
}

interface PocketBaseAuthResponse {
  token?: string;
  record?: {
    id?: string;
    email?: string;
    entitlement?: string;
    plan?: string;
    entitlementExpiresAt?: string;
  };
}

function normalizePlanValue(value: unknown): FottyPlan {
  if (value === "plus" || value === "supporter" || value === "collab" || value === "builder") return value;
  return "free";
}

function recordHasEntitlementField(record?: PocketBaseAuthResponse["record"] | null) {
  return Boolean(record?.entitlement?.trim() || record?.plan?.trim());
}

function mergeAuthRecords(
  authRecord: PocketBaseAuthResponse["record"],
  fetchedRecord?: PocketBaseAuthResponse["record"] | null
): PocketBaseAuthResponse["record"] {
  const merged = { ...authRecord, ...(fetchedRecord || {}) };
  if (recordHasEntitlementField(fetchedRecord)) return merged;
  if (recordHasEntitlementField(authRecord)) {
    return {
      ...merged,
      entitlement: authRecord?.entitlement || authRecord?.plan,
      plan: authRecord?.plan || authRecord?.entitlement,
      entitlementExpiresAt: authRecord?.entitlementExpiresAt || merged.entitlementExpiresAt,
    };
  }
  return merged;
}

function accessFromRecord(
  record: PocketBaseAuthResponse["record"],
  fallback?: Pick<FottyAuthSession, "entitlement" | "entitlementExpiresAt">
): Pick<FottyAuthSession, "entitlement" | "entitlementExpiresAt"> {
  const expiresAt = record?.entitlementExpiresAt?.trim() || fallback?.entitlementExpiresAt || null;
  let plan = normalizePlanValue(record?.entitlement || record?.plan);
  if (plan === "free" && fallback?.entitlement && fallback.entitlement !== "free" && !recordHasEntitlementField(record)) {
    plan = fallback.entitlement;
  }
  if (!isPaidPlan(plan) && plan !== "free") plan = "free";
  if (plan !== "free" && isAccessExpired(expiresAt)) plan = "free";
  return { entitlement: plan, entitlementExpiresAt: expiresAt };
}

async function fetchUserRecord(userID: string, token: string) {
  const response = await fetch(`${getPocketBaseUrl()}/api/collections/users/records/${userID}`, {
    headers: {
      Accept: "application/json",
      Authorization: token.startsWith("Bearer ") ? token : `Bearer ${token}`,
    },
    cache: "no-store",
  });
  if (!response.ok) return null;
  return (await response.json()) as PocketBaseAuthResponse["record"];
}

export async function pocketBaseSignInWithPassword(email: string, password: string): Promise<FottyAuthSession> {
  assertAccountsEnabled();
  const response = await fetch(`${getPocketBaseUrl()}/api/collections/users/auth-with-password`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ identity: email, password }),
    cache: "no-store",
  });

  if (!response.ok) {
    const errorPayload = await response.json().catch(() => ({}));
    throw new Error(
      pocketBaseUserMessage(
        errorPayload,
        "Invalid email or password. Use Forgot password if this email is already registered."
      )
    );
  }

  const payload = (await response.json()) as PocketBaseAuthResponse;
  if (!payload.token || !payload.record?.id) {
    throw new Error("PocketBase returned an invalid session.");
  }

  const fetched = await fetchUserRecord(payload.record.id, payload.token);
  const record = mergeAuthRecords(payload.record, fetched);
  const access = accessFromRecord(record);

  return {
    email: payload.record.email || email,
    token: payload.token,
    userID: payload.record.id,
    signedInAt: new Date().toISOString(),
    provider: "pocketbase",
    ...access,
  };
}

export async function pocketBaseSignUpWithPassword(
  email: string,
  password: string,
  displayName?: string
): Promise<FottyAuthSession> {
  assertAccountsEnabled();
  const createPayload: Record<string, string> = {
    email,
    password,
    passwordConfirm: password,
  };
  if (displayName?.trim()) createPayload.name = displayName.trim();

  const createResponse = await fetch(`${getPocketBaseUrl()}/api/collections/users/records`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify(createPayload),
    cache: "no-store",
  });

  if (!createResponse.ok) {
    const createError = await createResponse.json().catch(() => ({}));
    throw new Error(pocketBaseUserMessage(createError, "Could not create account."));
  }

  return pocketBaseSignInWithPassword(email, password);
}

export async function pocketBaseRefreshAuthToken(token: string): Promise<string | null> {
  const session = await pocketBaseRefreshSession(token);
  return session?.token ?? null;
}

async function pocketBaseRefreshSession(token: string): Promise<PocketBaseAuthResponse | null> {
  const response = await fetch(`${getPocketBaseUrl()}/api/collections/users/auth-refresh`, {
    method: "POST",
    headers: {
      Accept: "application/json",
      Authorization: token.startsWith("Bearer ") ? token : `Bearer ${token}`,
    },
    cache: "no-store",
  });
  if (!response.ok) return null;
  return (await response.json().catch(() => ({}))) as PocketBaseAuthResponse;
}

export async function pocketBaseSyncSessionEntitlement(
  session: Pick<FottyAuthSession, "token" | "userID" | "email" | "entitlement" | "entitlementExpiresAt">
): Promise<Pick<FottyAuthSession, "token" | "entitlement" | "entitlementExpiresAt"> | null> {
  if (!session.token) return null;

  const refreshed = await pocketBaseRefreshSession(session.token);
  const token = refreshed?.token?.trim() || session.token;

  if (!session.userID) {
    return { token, entitlement: session.entitlement || "free", entitlementExpiresAt: session.entitlementExpiresAt ?? null };
  }

  const fetched = await fetchUserRecord(session.userID, token);
  const record = mergeAuthRecords(refreshed?.record || { id: session.userID, email: session.email }, fetched);
  return { token, ...accessFromRecord(record, session) };
}

export async function pocketBaseRequestPasswordReset(email: string): Promise<string> {
  assertAccountsEnabled();
  const response = await fetch(`${getPocketBaseUrl()}/api/collections/users/request-password-reset`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ email }),
    cache: "no-store",
  });

  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(pocketBaseUserMessage(payload, "Could not send reset email."));
  }

  return "If an account exists for that email, you will receive a password reset link shortly.";
}
