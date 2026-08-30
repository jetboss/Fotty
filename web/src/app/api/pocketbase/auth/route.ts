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

  if (!email || !password) {
    return NextResponse.json({ error: "Email and password are required." }, { status: 400 });
  }

  try {
    const response = await fetch(`${POCKETBASE_BASE}/api/collections/users/auth-with-password`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ identity: email, password }),
      cache: "no-store",
    });

    if (!response.ok) {
      const errorPayload = await response.json().catch(() => ({}));
      const message = pocketBaseUserMessage(
        errorPayload,
        "Invalid email or password. Use Forgot password if this email is already registered."
      );
      return NextResponse.json({ error: message }, { status: response.status });
    }

    const payload = (await response.json()) as PocketBaseAuthResponse;
    if (!payload.token || !payload.record?.id) {
      return NextResponse.json({ error: "PocketBase returned an invalid session." }, { status: 502 });
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
    return NextResponse.json({ error: "PocketBase sign-in unavailable." }, { status: 503 });
  }
}
