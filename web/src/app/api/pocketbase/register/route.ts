export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { getPocketBaseUrl } from "@/lib/fotty-config";
import { fetchUserAccess } from "@/lib/server/pocketbase-user";
import { pocketBaseUserMessage } from "@/lib/server/pocketbase-errors";
import { rejectIfAccountsDisabled } from "@/lib/server/accounts-disabled";

const POCKETBASE_BASE = getPocketBaseUrl();

interface PocketBaseAuthResponse {
  token?: string;
  record?: {
    id?: string;
    email?: string;
  };
}

export async function POST(request: Request) {
  const disabled = rejectIfAccountsDisabled();
  if (disabled) return disabled;

  const body = await request.json().catch(() => ({}));
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const password = typeof body.password === "string" ? body.password.trim() : "";
  const displayName = typeof body.displayName === "string" ? body.displayName.trim() : "";

  if (!email) {
    return NextResponse.json({ error: "Email is required." }, { status: 400 });
  }
  if (password.length < 8) {
    return NextResponse.json({ error: "Password must be at least 8 characters." }, { status: 400 });
  }

  const createPayload: Record<string, string> = {
    email,
    password,
    passwordConfirm: password,
  };
  if (displayName) createPayload.name = displayName;

  try {
    const createResponse = await fetch(`${POCKETBASE_BASE}/api/collections/users/records`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(createPayload),
      cache: "no-store",
    });

    if (!createResponse.ok) {
      const createError = await createResponse.json().catch(() => ({}));
      return NextResponse.json(
        { error: pocketBaseUserMessage(createError, "Could not create account.") },
        { status: createResponse.status }
      );
    }

    const authResponse = await fetch(`${POCKETBASE_BASE}/api/collections/users/auth-with-password`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ identity: email, password }),
      cache: "no-store",
    });

    if (!authResponse.ok) {
      const authError = await authResponse.json().catch(() => ({}));
      return NextResponse.json(
        { error: pocketBaseUserMessage(authError, "Account created but sign-in failed. Try signing in.") },
        { status: authResponse.status }
      );
    }

    const payload = (await authResponse.json()) as PocketBaseAuthResponse;
    if (!payload.token || !payload.record?.id) {
      return NextResponse.json({ error: "Account created but session was invalid. Try signing in." }, { status: 502 });
    }

    const access = await fetchUserAccess(payload.record.id, payload.token);

    return NextResponse.json({
      email: payload.record.email || email,
      token: payload.token,
      userID: payload.record.id,
      signedInAt: new Date().toISOString(),
      provider: "pocketbase",
      entitlement: access?.plan || "free",
      entitlementExpiresAt: access?.expiresAt ?? null,
    });
  } catch {
    return NextResponse.json({ error: "Account creation is temporarily unavailable." }, { status: 503 });
  }
}
