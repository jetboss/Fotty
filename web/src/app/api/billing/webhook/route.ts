export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { getBillingWebhookSecret, isPaidPlan } from "@/lib/billing";
import { findUserIDByEmail, updateUserEntitlement } from "@/lib/server/pocketbase-user";
import { getPocketBaseAdminTokenForRequest } from "@/lib/server/pocketbase-admin";

export async function POST(request: Request) {
  const secret = getBillingWebhookSecret();
  if (!secret) {
    return NextResponse.json({ error: "Billing webhook is not configured." }, { status: 503 });
  }

  const provided = request.headers.get("x-fotty-webhook-secret") || request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (provided !== secret) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => ({}));
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const plan = body.plan;
  const userID = typeof body.userID === "string" ? body.userID : undefined;

  if (!email || !isPaidPlan(plan)) {
    return NextResponse.json({ error: "email and paid plan are required." }, { status: 400 });
  }

  const adminToken = await getPocketBaseAdminTokenForRequest();
  if (!adminToken) {
    return NextResponse.json({
      ok: true,
      stored: false,
      message: "Webhook accepted. Set POCKETBASE_ADMIN_TOKEN to persist entitlements on users.",
    });
  }

  const targetUserID = userID || (await findUserIDByEmail(email, adminToken));
  if (!targetUserID) {
    return NextResponse.json({ error: "User not found for entitlement update." }, { status: 404 });
  }

  const updated = await updateUserEntitlement(targetUserID, adminToken, plan);
  if (!updated) {
    return NextResponse.json({ error: "Failed to update PocketBase user entitlement." }, { status: 502 });
  }

  return NextResponse.json({ ok: true, stored: true, userID: targetUserID, plan });
}
