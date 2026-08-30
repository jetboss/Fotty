export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { isAdminRequest } from "@/lib/server/admin-auth";
import { createQrLoginLink } from "@/lib/server/qr-login";
import { getPocketBaseAdminTokenForRequest, getPocketBaseUser } from "@/lib/server/pocketbase-admin";

function normalizeReturnTo(value: unknown) {
  return typeof value === "string" ? value : "/";
}

export async function POST(request: NextRequest) {
  if (!(await isAdminRequest(request))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => ({}));
  const userID = typeof body.userID === "string" ? body.userID.trim() : "";
  if (!userID || userID.startsWith("local:")) {
    return NextResponse.json({ error: "Select a PocketBase user first." }, { status: 400 });
  }

  const adminToken = await getPocketBaseAdminTokenForRequest();
  const user = adminToken ? await getPocketBaseUser(adminToken, userID) : null;
  if (!user?.email) {
    return NextResponse.json({ error: "User not found." }, { status: 404 });
  }

  const result = await createQrLoginLink({
    userID,
    email: user.email,
    entitlement: user.entitlement,
    entitlementExpiresAt: user.entitlementExpiresAt ?? null,
    returnTo: normalizeReturnTo(body.returnTo),
  });

  if (!result.ok) {
    return NextResponse.json({ error: result.error }, { status: 400 });
  }

  const origin = request.nextUrl.origin;
  const url = new URL("/login/qr", origin);
  url.searchParams.set("token", result.token);

  return NextResponse.json({
    ok: true,
    url: url.toString(),
    expiresAt: result.record.expiresAt,
    email: result.record.email,
  });
}
