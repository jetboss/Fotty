import { NextResponse } from "next/server";
import type { FottyPlan } from "@/lib/entitlements";
import { isPaidPlan } from "@/lib/billing";
import { fetchUserAccess } from "@/lib/server/pocketbase-user";
import { resolveLocalEntitlement } from "@/lib/server/admin-grants-local";
import { getPocketBaseAdminTokenForRequest, getPocketBaseUser } from "@/lib/server/pocketbase-admin";
import { findUserIDByEmail } from "@/lib/server/pocketbase-user";
import { refreshPocketBaseSession, type PocketBaseSessionRecord } from "@/lib/server/pocketbase-session";
import { verifyWatchStreamToken } from "@/lib/server/watch-stream-token";
import { verifyQrSessionToken } from "@/lib/server/qr-login";
import { isAccessExpired } from "@/lib/entitlement-access";
import { isLocalAuthEnabled } from "@/lib/server/local-auth";

export interface WatchAccessContext {
  email: string;
  userID: string;
  entitlement: FottyPlan;
}

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

function normalizePlanValue(value: unknown): FottyPlan {
  if (value === "plus" || value === "supporter" || value === "collab" || value === "builder") return value;
  return "free";
}

function readBearerToken(request: Request) {
  const authHeader = request.headers.get("authorization");
  if (!authHeader) return undefined;
  return authHeader.startsWith("Bearer ") ? authHeader.slice("Bearer ".length).trim() : authHeader.trim();
}

/** Entitlement for a verified PocketBase session (token validated via auth-refresh or record fetch). */
async function resolveEntitlementForVerifiedSession(
  userID: string,
  token: string,
  email: string,
  authSnapshot?: PocketBaseSessionRecord
): Promise<FottyPlan> {
  let resolved: FottyPlan = "free";
  if (authSnapshot?.entitlement || authSnapshot?.plan) {
    resolved = pickHigher(resolved, normalizePlanValue(authSnapshot.entitlement || authSnapshot.plan));
  }
  const access = await fetchUserAccess(userID, token);
  if (access?.plan) resolved = pickHigher(resolved, access.plan);
  const adminToken = await getPocketBaseAdminTokenForRequest();
  const adminRecord = adminToken ? await getPocketBaseUser(adminToken, userID) : null;
  if (
    adminRecord?.entitlement &&
    adminRecord.entitlement !== "free" &&
    !isAccessExpired(adminRecord.entitlementExpiresAt || null)
  ) {
    resolved = pickHigher(resolved, adminRecord.entitlement);
  }
  const fromLocal = await resolveLocalEntitlement(email);
  if (fromLocal) resolved = pickHigher(resolved, fromLocal);
  return resolved;
}

/** Entitlement when email was issued inside a signed short-lived watch token (not from client headers). */
async function resolveEntitlementForTrustedEmail(email: string, userID?: string): Promise<FottyPlan> {
  let resolved: FottyPlan = "free";
  const adminToken = await getPocketBaseAdminTokenForRequest();
  if (adminToken) {
    const resolvedUserID = userID || (await findUserIDByEmail(email, adminToken));
    if (resolvedUserID) {
      const record = await getPocketBaseUser(adminToken, resolvedUserID);
      if (record?.entitlement) resolved = record.entitlement;
    }
  }
  const fromLocal = await resolveLocalEntitlement(email);
  if (fromLocal) resolved = pickHigher(resolved, fromLocal);
  return resolved;
}

/**
 * Verifies paid watch access. Never trusts X-Fotty-Email alone — requires a valid
 * PocketBase bearer token or a signed watchToken query param.
 */
export async function requireWatchAccess(
  request: Request
): Promise<WatchAccessContext | NextResponse> {
  const url = new URL(request.url);
  const watchStreamToken = url.searchParams.get("watchToken")?.trim();
  const streamTokenPayload = watchStreamToken ? verifyWatchStreamToken(watchStreamToken) : null;

  if (streamTokenPayload) {
    const entitlement = streamTokenPayload.entitlement;
    if (!isPaidPlan(entitlement)) {
      return NextResponse.json(
        {
          error:
            "A paid Fotty plan is required to watch. Subscribe via WhatsApp or ask for access to be enabled.",
        },
        { status: 403 }
      );
    }
    // URL-carried media credentials must not contain user PII. The signed
    // subject is a one-way HMAC and is only used for request attribution.
    const userID = `watch:${streamTokenPayload.subject}`;
    const email = `watch-${streamTokenPayload.subject}@token.invalid`;
    return { email, userID, entitlement };
  }

  // Under local auth dev/test mode, allow requests with a valid local entitlement
  const headerEmail = request.headers.get("x-fotty-email")?.trim().toLowerCase();
  if (isLocalAuthEnabled() && headerEmail) {
    const entitlement = await resolveLocalEntitlement(headerEmail);
    if (entitlement && isPaidPlan(entitlement)) {
      const userID = request.headers.get("x-fotty-user-id")?.trim() || `local:${headerEmail}`;
      return { email: headerEmail, userID, entitlement };
    }
  }

  const token = readBearerToken(request);
  if (!token) {
    return NextResponse.json({ error: "Sign in required to watch live streams." }, { status: 401 });
  }

  const qrSession = verifyQrSessionToken(token);
  if (qrSession) {
    const entitlement = await resolveEntitlementForTrustedEmail(qrSession.email, qrSession.userID);
    if (!isPaidPlan(entitlement)) {
      return NextResponse.json(
        {
          error:
            "A paid Fotty plan is required to watch. Subscribe via WhatsApp or ask for access to be enabled.",
        },
        { status: 403 }
      );
    }
    return { email: qrSession.email, userID: qrSession.userID, entitlement };
  }

  const headerUserID = request.headers.get("x-fotty-user-id")?.trim();
  let session = headerUserID
    ? await refreshPocketBaseSession(token).then((refreshed) =>
        refreshed && refreshed.userID === headerUserID ? refreshed : null
      )
    : await refreshPocketBaseSession(token);

  if (!session && headerUserID) {
    const access = await fetchUserAccess(headerUserID, token);
    if (!access) {
      return NextResponse.json({ error: "Invalid or expired session." }, { status: 401 });
    }
    const adminToken = await getPocketBaseAdminTokenForRequest();
    const record = adminToken ? await getPocketBaseUser(adminToken, headerUserID) : null;
    const email = record?.email?.trim().toLowerCase();
    if (!email) {
      return NextResponse.json({ error: "Invalid session." }, { status: 401 });
    }
    session = { userID: headerUserID, email };
  }

  if (!session) {
    return NextResponse.json({ error: "Invalid or expired session." }, { status: 401 });
  }

  const entitlement = await resolveEntitlementForVerifiedSession(
    session.userID,
    token,
    session.email,
    session
  );
  if (!isPaidPlan(entitlement)) {
    return NextResponse.json(
      {
        error:
          "A paid Fotty plan is required to watch. Subscribe via WhatsApp or ask for access to be enabled.",
      },
      { status: 403 }
    );
  }

  return { email: session.email, userID: session.userID, entitlement };
}

/** @deprecated Use requireWatchAccess — returns null when allowed, NextResponse when denied. */
export async function assertWatchAccess(request: Request) {
  const result = await requireWatchAccess(request);
  return result instanceof NextResponse ? result : null;
}
