import { rejectIfAccountsDisabled } from "@/lib/server/accounts-disabled";
import { NextResponse } from "next/server";
import { fetchUserAccess, findUserIDByEmail } from "@/lib/server/pocketbase-user";
import { resolveLocalEntitlement } from "@/lib/server/admin-grants-local";
import type { FottyPlan } from "@/lib/entitlements";
import { refreshPocketBaseSession } from "@/lib/server/pocketbase-session";
import { getPocketBaseAdminTokenForRequest, getPocketBaseUser } from "@/lib/server/pocketbase-admin";
import { verifyQrSessionToken } from "@/lib/server/qr-login";
import { isAccessExpired } from "@/lib/entitlement-access";
import { isLocalAuthEnabled } from "@/lib/server/local-auth";

export const dynamic = "force-dynamic";

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

export async function POST(request: Request) {
  const disabled = rejectIfAccountsDisabled();
  if (disabled) return disabled;

  const body = await request.json().catch(() => ({}));
  const token = typeof body.token === "string" ? body.token.trim() : "";
  const userID = typeof body.userID === "string" ? body.userID.trim() : "";
  const bodyEmail = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";

  if (!token && isLocalAuthEnabled() && bodyEmail) {
    let entitlement: FottyPlan = "free";
    let entitlementExpiresAt: string | null = null;
    const adminToken = await getPocketBaseAdminTokenForRequest();
    const adminUserID = adminToken ? await findUserIDByEmail(bodyEmail, adminToken) : null;
    const adminRecord = adminToken && adminUserID ? await getPocketBaseUser(adminToken, adminUserID) : null;
    if (
      adminRecord?.entitlement &&
      adminRecord.entitlement !== "free" &&
      !isAccessExpired(adminRecord.entitlementExpiresAt || null)
    ) {
      entitlement = pickHigher(entitlement, adminRecord.entitlement);
      entitlementExpiresAt = adminRecord.entitlementExpiresAt || null;
    }
    const fromLocal = await resolveLocalEntitlement(bodyEmail);
    if (fromLocal) entitlement = pickHigher(entitlement, fromLocal);
    return NextResponse.json({
      entitlement,
      entitlementExpiresAt,
    });
  }

  if (!token) {
    return NextResponse.json({ error: "token is required." }, { status: 400 });
  }

  const qrSession = verifyQrSessionToken(token);
  if (qrSession) {
    let entitlement = qrSession.entitlement;
    const adminToken = await getPocketBaseAdminTokenForRequest();
    const adminRecord = adminToken ? await getPocketBaseUser(adminToken, qrSession.userID) : null;
    if (
      adminRecord?.entitlement &&
      adminRecord.entitlement !== "free" &&
      !isAccessExpired(adminRecord.entitlementExpiresAt || null)
    ) {
      entitlement = pickHigher(entitlement, adminRecord.entitlement);
    }
    const fromLocal = await resolveLocalEntitlement(qrSession.email);
    if (fromLocal) entitlement = pickHigher(entitlement, fromLocal);
    return NextResponse.json({
      entitlement,
      entitlementExpiresAt: adminRecord?.entitlementExpiresAt || qrSession.entitlementExpiresAt || null,
    });
  }

  const session = await refreshPocketBaseSession(token);
  if (!session) {
    return NextResponse.json({ error: "Invalid or expired session." }, { status: 401 });
  }

  const resolvedUserID = userID || session.userID;
  const email = session.email || bodyEmail || "";
  let entitlement: FottyPlan = "free";
  if (session.entitlement || session.plan) {
    entitlement = pickHigher(entitlement, normalizePlanValue(session.entitlement || session.plan));
  }

  const access = resolvedUserID ? await fetchUserAccess(resolvedUserID, token) : undefined;
  if (access?.plan) {
    entitlement = pickHigher(entitlement, access.plan);
  }

  const adminToken = await getPocketBaseAdminTokenForRequest();
  const adminRecord =
    adminToken && resolvedUserID ? await getPocketBaseUser(adminToken, resolvedUserID) : null;
  if (
    adminRecord?.entitlement &&
    adminRecord.entitlement !== "free" &&
    !isAccessExpired(adminRecord.entitlementExpiresAt || null)
  ) {
    entitlement = pickHigher(entitlement, adminRecord.entitlement);
  }
  if (email) {
    const fromLocal = await resolveLocalEntitlement(email);
    if (fromLocal) entitlement = pickHigher(entitlement, fromLocal);
  }

  return NextResponse.json({
    entitlement,
    entitlementExpiresAt: adminRecord?.entitlementExpiresAt || access?.expiresAt || session.entitlementExpiresAt || null,
  });
}
